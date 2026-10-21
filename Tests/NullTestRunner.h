// NullTestRunner.h
//
// The null test's runner: GoogleTest 1.18.0 runs the kTests table (DSPKernelNullTest.cpp), which
// registers at run time — the test bodies are the plain `void()` functions of the *.inc files, and
// their logPass / logFail / logPending verdicts (TestSupport.h) are GoogleTest results. #included
// ONCE, by DSPKernelNullTest.cpp, after TestSupport.h and the *.inc files.
//
// What it adds to GoogleTest:
//   * Tiers. Each test is in exactly one tier, its GoogleTest suite: Correctness, Concurrent (it
//     runs threads — its own, a decoder's, a worker's, the Realizer's queue — beside the test),
//     AccuracySweep (a long single-threaded numeric sweep) or Timing (a CPU budget). Two flags
//     cross the tiers: serial (it writes fixtures under test-data/ shared by name, or mutates the
//     process environment, so it never runs in a parallel shard) and needsFfmpeg (it has an FFmpeg
//     leg, skipped with an [info] line where FFmpeg is absent). `--tier=` selects by them.
//   * A per-test ceiling: a watchdog thread names a test that runs past its tier's ceiling, with
//     its last progress (rig::Progress), and aborts the run with a non-zero exit — a hang costs the
//     ceiling, not the CI job's limit.
//   * A body that returns without a verdict fails; each test records its tier, flags and the
//     process CPU it used (all threads) as JSON properties (--gtest_output=json:FILE).
//
// Command line (GoogleTest's own --gtest_* flags work as documented: filter, repeat, shuffle,
// random_seed, output, list_tests, fail_fast, …; a filter or tier that selects nothing FAILS):
//   --tier=<list>          tiers/flags to run, comma-separated; a leading '-' excludes. Names:
//                          correctness concurrent accuracySweep timing serial parallelSafe
//                          needsFfmpeg all. E.g. --tier=-timing, --tier=concurrent.
//   --serial-only          only the serial tests (the one process beside parallel shards)
//   --parallel-safe-only   only the tests that are not serial (the parallel shards)
//   --test-ceiling=<s>     every test's ceiling, in seconds (default: per tier and build, below);
//                          also ADAPTIVESOUND_TEST_CEILING=<s>
//   --list                 list the selected tests with their tier and flags, and exit
//   --filter=<name>        run the one test named <name> (= --gtest_filter=*.<name>)

#pragma once

#include <algorithm>
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <format>
#include <mutex>
#include <optional>
#include <span>
#include <stop_token>
#include <string>
#include <string_view>
#include <sys/resource.h>
#include <thread>
#include <vector>

#include <gtest/gtest.h>

#include "TestSupport.h" // the verdicts and the rig (already included first by the one TU)

// ---------------------------------------------------------------------------
// Tiers and flags
// ---------------------------------------------------------------------------

enum class Tier : uint8_t
{
    Correctness,
    Concurrent,
    AccuracySweep,
    Timing,
};

// Flags that cross the tiers (TestEntry::flags).
constexpr uint8_t kSerial = 1U << 0U;      // shares on-disk fixtures or the process environment
constexpr uint8_t kNeedsFfmpeg = 1U << 1U; // has an FFmpeg leg (skipped when FFmpeg is absent)

namespace
{
    struct TestEntry
    {
        const char* name;
        void (*fn)();
        Tier tier;
        uint8_t flags = 0U;
    };

    // The GoogleTest suite of each tier: --gtest_filter='Timing.*' selects a tier too.
    constexpr auto tierName(Tier tier) -> const char*
    {
        switch (tier)
        {
            case Tier::Correctness:
                return "Correctness";
            case Tier::Concurrent:
                return "Concurrent";
            case Tier::AccuracySweep:
                return "AccuracySweep";
            case Tier::Timing:
                return "Timing";
        }
        return "Correctness";
    }

    auto flagNames(uint8_t flags) -> std::string
    {
        std::string names;
        if ((flags & kSerial) != 0U)
        {
            names += "serial";
        }
        if ((flags & kNeedsFfmpeg) != 0U)
        {
            names += names.empty() ? "needsFfmpeg" : " needsFfmpeg";
        }
        return names;
    }

    // Whether `entry` is in the tier or carries the flag named `token` (--tier names).
    auto matches(const TestEntry& entry, std::string_view token) -> bool
    {
        if (token == "all")
        {
            return true;
        }
        if (token == "correctness")
        {
            return entry.tier == Tier::Correctness;
        }
        if (token == "concurrent")
        {
            return entry.tier == Tier::Concurrent;
        }
        if (token == "accuracySweep")
        {
            return entry.tier == Tier::AccuracySweep;
        }
        if (token == "timing")
        {
            return entry.tier == Tier::Timing;
        }
        if (token == "serial")
        {
            return (entry.flags & kSerial) != 0U;
        }
        if (token == "parallelSafe")
        {
            return (entry.flags & kSerial) == 0U;
        }
        return token == "needsFfmpeg" && (entry.flags & kNeedsFfmpeg) != 0U;
    }

    constexpr std::array<std::string_view, 8> kSelectorNames = {
        "all",
        "correctness",
        "concurrent",
        "accuracySweep",
        "timing",
        "serial",
        "parallelSafe",
        "needsFfmpeg",
    };

    // ---------------------------------------------------------------------------
    // Ceilings: each test's hang guard, by tier, ≥ 10× the slowest test of the tier in that build
    // (measured; the report's per-test CPU column). Time only breaks a hang here: a passing test
    // never comes near its ceiling. The clock is the time the Mac was AWAKE (rig::AwakeClock), so a
    // laptop that sleeps through a run does not trip it.
    // ---------------------------------------------------------------------------
#if __has_feature(thread_sanitizer)
    constexpr int kCeilingScale = 8;
#elif __has_feature(address_sanitizer)
    constexpr int kCeilingScale = 3;
#else
    constexpr int kCeilingScale = 1;
#endif

    constexpr auto baseCeiling(Tier tier) -> std::chrono::seconds
    {
        switch (tier)
        {
            case Tier::Correctness:
                return std::chrono::seconds{120};
            case Tier::Concurrent:
            case Tier::AccuracySweep:
            case Tier::Timing:
                return std::chrono::seconds{300};
        }
        return std::chrono::seconds{300};
    }

    // ---------------------------------------------------------------------------
    // The watchdog: one thread, armed per test. A test that runs past its ceiling is named, with its
    // last progress, and the run aborts (non-zero exit; the sanitizers print their report).
    // ---------------------------------------------------------------------------
    class Watchdog final : public testing::EmptyTestEventListener
    {
      public:
        explicit Watchdog(std::optional<std::chrono::seconds> ceilingOverride)
            : ceilingOverride_(ceilingOverride),
              thread_([this](const std::stop_token& stop) { watch(stop); })
        {
        }
        ~Watchdog() override = default; // thread_ (the last member) stops and joins first
        Watchdog(const Watchdog&) = delete;
        Watchdog(Watchdog&&) = delete;
        auto operator=(const Watchdog&) -> Watchdog& = delete;
        auto operator=(Watchdog&&) -> Watchdog& = delete;

        void OnTestStart(const testing::TestInfo& info) override
        {
            rig::gProgress.store("started", std::memory_order_release);
            const std::scoped_lock lock(mutex_);
            test_ = std::format("{}.{}", info.test_suite_name(), info.name());
            ceiling_ = ceilingOverride_.value_or(ceilingFor(info.test_suite_name()));
            started_ = rig::AwakeClock::now();
            armed_ = true;
            changed_.notify_all();
        }

        void OnTestEnd(const testing::TestInfo& /*info*/) override
        {
            const std::scoped_lock lock(mutex_);
            armed_ = false;
            changed_.notify_all();
        }

      private:
        static auto ceilingFor(std::string_view suite) -> std::chrono::seconds
        {
            for (const Tier tier :
                 {Tier::Correctness, Tier::Concurrent, Tier::AccuracySweep, Tier::Timing})
            {
                if (suite == tierName(tier))
                {
                    return baseCeiling(tier) * kCeilingScale;
                }
            }
            return baseCeiling(Tier::Concurrent) * kCeilingScale;
        }

        // Wakes once a second while a test runs (or at once when it ends), and compares the awake
        // time since the test started with its ceiling.
        void watch(const std::stop_token& stop)
        {
            using namespace std::chrono_literals;
            std::unique_lock lock(mutex_);
            while (!stop.stop_requested())
            {
                if (!armed_)
                {
                    changed_.wait(lock, stop, [this] { return armed_; });
                    continue;
                }
                (void)changed_.wait_for(lock, stop, 1s, [this] { return !armed_; });
                if (armed_ && !stop.stop_requested() &&
                    rig::AwakeClock::now() - started_ >= ceiling_)
                {
                    fire();
                }
            }
        }

        // Name the test and its last progress, then abort: the hang is the run's verdict.
        [[noreturn]] void fire() const
        {
            const std::string line =
                std::format("\n[HANG] {} ran past its {} s ceiling. Last progress: {}. Aborting.\n",
                            test_,
                            ceiling_.count(),
                            rig::gProgress.load(std::memory_order_acquire));
            (void)std::fflush(stdout);
            (void)std::fputs(line.c_str(), stderr);
            (void)std::fflush(stderr);
            std::abort();
        }

        std::optional<std::chrono::seconds> ceilingOverride_;
        std::mutex mutex_;
        std::condition_variable_any changed_;
        std::string test_;
        std::chrono::seconds ceiling_{0};
        rig::AwakeClock::time_point started_{};
        bool armed_ = false;
        std::jthread thread_; // LAST: stopped and joined before the members it reads go
    };

    // ---------------------------------------------------------------------------
    // Registration: one GoogleTest test per selected kTests entry, in the table's order.
    // ---------------------------------------------------------------------------

    // The process's CPU time (every thread: the test's own, its workers', its decoders').
    auto processCpuTime() -> std::chrono::microseconds
    {
        rusage usage{};
        (void)getrusage(RUSAGE_SELF, &usage);
        const auto micros = [](const timeval& time)
        { return (std::chrono::seconds{time.tv_sec} + std::chrono::microseconds{time.tv_usec}); };
        return std::chrono::duration_cast<std::chrono::microseconds>(micros(usage.ru_utime) +
                                                                     micros(usage.ru_stime));
    }

    // Not final: GoogleTest derives from the fixture type to reach its suite hooks.
    class NullTest : public testing::Test
    {
      public:
        explicit NullTest(const TestEntry& entry) : entry_(entry)
        {
        }

        void TestBody() override
        {
            RecordProperty("tier", tierName(entry_.tier));
            if (entry_.flags != 0U)
            {
                RecordProperty("flags", flagNames(entry_.flags));
            }
            gVerdictGiven.store(false, std::memory_order_relaxed);
            const std::chrono::microseconds before = processCpuTime();
            entry_.fn();
            const auto cpuMs =
                std::chrono::duration_cast<std::chrono::milliseconds>(processCpuTime() - before)
                    .count();
            RecordProperty("cpu_ms", std::to_string(cpuMs));
            logInfo(std::format("  [cpu] {} ms\n", cpuMs));
            if (!gVerdictGiven.load(std::memory_order_relaxed))
            {
                ADD_FAILURE() << "[FAIL] " << entry_.name
                              << " -- the test body returned without a verdict (logPass, logFail "
                                 "or logPending)";
            }
        }

      private:
        const TestEntry& entry_;
    };

    // ---------------------------------------------------------------------------
    // The runner's own command line (GoogleTest has removed its --gtest_* flags by now).
    // ---------------------------------------------------------------------------
    struct RunnerOptions
    {
        std::vector<std::string_view> include; // empty: every tier
        std::vector<std::string_view> exclude;
        bool serialOnly = false;
        bool parallelSafeOnly = false;
        bool listOnly = false;
        std::optional<std::chrono::seconds> ceiling;
    };

    auto parseCeiling(std::string_view text) -> std::optional<std::chrono::seconds>
    {
        int seconds = 0;
        for (const char digit : text)
        {
            if (digit < '0' || digit > '9' || seconds > 1'000'000)
            {
                return std::nullopt;
            }
            seconds = (seconds * 10) + (digit - '0');
        }
        if (text.empty() || seconds == 0)
        {
            return std::nullopt;
        }
        return std::chrono::seconds{seconds};
    }

    auto parseTiers(std::string_view list, RunnerOptions& options) -> bool
    {
        while (!list.empty())
        {
            const std::size_t comma = list.find(',');
            std::string_view token = list.substr(0U, comma);
            list = (comma == std::string_view::npos) ? std::string_view{} : list.substr(comma + 1U);
            const bool exclude = token.starts_with('-');
            if (exclude)
            {
                token.remove_prefix(1U);
            }
            if (std::ranges::find(kSelectorNames, token) == kSelectorNames.end())
            {
                (void)std::fputs(std::format("error: unknown tier '{}' (known: correctness "
                                             "concurrent accuracySweep timing serial parallelSafe "
                                             "needsFfmpeg all)\n",
                                             token)
                                     .c_str(),
                                 stderr);
                return false;
            }
            (exclude ? options.exclude : options.include).push_back(token);
        }
        return true;
    }

    auto parseRunnerOptions(std::span<char*> args) -> std::optional<RunnerOptions>
    {
        RunnerOptions options;
        if (const char* env = std::getenv("ADAPTIVESOUND_TEST_CEILING"); env != nullptr)
        {
            options.ceiling = parseCeiling(env);
        }
        for (const char* raw : args)
        {
            const std::string_view arg(raw);
            if (arg.starts_with("--tier="))
            {
                if (!parseTiers(arg.substr(7U), options))
                {
                    return std::nullopt;
                }
            }
            else if (arg == "--serial-only")
            {
                options.serialOnly = true;
            }
            else if (arg == "--parallel-safe-only")
            {
                options.parallelSafeOnly = true;
            }
            else if (arg.starts_with("--test-ceiling="))
            {
                options.ceiling = parseCeiling(arg.substr(15U));
                if (!options.ceiling)
                {
                    (void)std::fputs("error: --test-ceiling wants whole seconds > 0\n", stderr);
                    return std::nullopt;
                }
            }
            else if (arg == "--list")
            {
                options.listOnly = true;
            }
            else if (arg.starts_with("--filter="))
            {
                GTEST_FLAG_SET(filter, std::format("*.{}", arg.substr(9U)));
            }
            else
            {
                // In-process --parallel is gone with the home runner: GoogleTest runs one test at a
                // time, and parallel runs are process shards (build-null-test.sh --shards N).
                (void)std::fputs(std::format("error: unknown argument '{}' (see NullTestRunner.h; "
                                             "parallel runs: build-null-test.sh --shards N)\n",
                                             arg)
                                     .c_str(),
                                 stderr);
                return std::nullopt;
            }
        }
        if (options.serialOnly && options.parallelSafeOnly)
        {
            (void)std::fputs("error: --serial-only and --parallel-safe-only exclude each other\n",
                             stderr);
            return std::nullopt;
        }
        return options;
    }

    auto selected(const TestEntry& entry, const RunnerOptions& options) -> bool
    {
        const auto hit = [&entry](std::string_view token) { return matches(entry, token); };
        const bool included = options.include.empty() || std::ranges::any_of(options.include, hit);
        const bool excluded = std::ranges::any_of(options.exclude, hit);
        const bool serial = (entry.flags & kSerial) != 0U;
        const bool roleFits = serial ? !options.parallelSafeOnly : !options.serialOnly;
        return included && !excluded && roleFits;
    }

    // Register the selected entries, list them (--list) or run them; the process's exit code.
    template <std::size_t N>
    auto runNullTest(int argc, char** argv, const std::array<TestEntry, N>& tests) -> int
    {
        // Line-buffered: CI shows each test as it finishes, and a crash loses no finished line.
        (void)std::setvbuf(stdout, nullptr, _IOLBF, 0);
        // A misspelt filter or an empty tier selects nothing: that is a failure, never a pass. The
        // flag goes in first, so a caller's own --gtest_fail_if_no_test_selected=0 still wins.
        std::string failIfNone = "--gtest_fail_if_no_test_selected";
        // argv[argc] is the null that ends argv: GoogleTest shifts it down as it removes its flags.
        std::vector<char*> args(argv, argv + argc + 1);
        args.insert(args.begin() + 1, failIfNone.data());
        int count = argc + 1;
        testing::InitGoogleTest(&count, args.data());
        const std::optional<RunnerOptions> options = parseRunnerOptions(
            std::span<char*>(args).subspan(1U, static_cast<std::size_t>(count) - 1U));
        if (!options)
        {
            return 2;
        }
        std::size_t registered = 0U;
        for (const TestEntry& entry : tests)
        {
            if (!selected(entry, *options))
            {
                continue;
            }
            ++registered;
            if (options->listOnly)
            {
                (void)std::fputs(
                    std::format(
                        "{}.{}  {}\n", tierName(entry.tier), entry.name, flagNames(entry.flags))
                        .c_str(),
                    stdout);
                continue;
            }
            testing::RegisterTest(tierName(entry.tier),
                                  entry.name,
                                  nullptr,
                                  nullptr,
                                  __FILE__,
                                  __LINE__,
                                  // GoogleTest owns what the factory returns.
                                  [&entry] { return std::make_unique<NullTest>(entry).release(); });
        }
        if (options->listOnly)
        {
            return registered == 0U ? 1 : 0;
        }
        (void)std::fputs(std::format("[rig] {} build; {} of {} tests selected; ceilings {}\n",
                                     rig::kBuild,
                                     registered,
                                     N,
                                     options->ceiling
                                         ? std::format("{} s (override)", options->ceiling->count())
                                         : std::format("by tier (×{})", kCeilingScale))
                             .c_str(),
                         stdout);
        // The watchdog lives in this frame: GoogleTest is handed it, then gives it back (Release)
        // before it goes, so it never deletes it.
        Watchdog watchdog(options->ceiling);
        testing::TestEventListeners& listeners = testing::UnitTest::GetInstance()->listeners();
        listeners.Append(&watchdog);
        const int status = RUN_ALL_TESTS();
        (void)listeners.Release(&watchdog);
        return status;
    }
} // namespace
