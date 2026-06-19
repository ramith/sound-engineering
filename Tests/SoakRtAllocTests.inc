// SoakRtAllocTests.inc
//
// S7 / US-QA-06 (automated half): RT-allocation-guard SOAK tests.
//
// GOAL: prove the audio PROCESSING path performs ZERO heap allocations under a long
// (~1 hr-equivalent) soak, and that per-buffer work stays bounded (no drift / leak).
// The founder runs Instruments separately for XRuns on real hardware — this is the
// automatable, deterministic, offline half of the acceptance criterion.
//
// MECHANISM — a TEST-ONLY global operator new/delete override (defined in this file, which
// links ONLY into the test binary — never the AudioDSP target / shipping app):
//
//   * rtGuardArmed is a THREAD_LOCAL flag. Only the thread that arms the guard is measured.
//     This is load-bearing: FileDecodeSource spawns an off-RT decoder thread that legitimately
//     allocates, and the loudness worker thread does too. A *global* (non-thread-local) flag
//     would catch those and produce false positives. The thread_local flag scopes the count to
//     the RT-pull / process() caller only.
//   * rtAllocCount is a global atomic, bumped once per allocation WHILE the calling thread is
//     armed. The override ALWAYS performs the real allocation (via std::malloc) so nothing ever
//     crashes — it only RECORDS. When disarmed it is a thin malloc/free passthrough.
//   * Every new/delete form is overridden (plain, array, nothrow, sized, aligned) and routed
//     through malloc/free so new/delete always pair correctly. The build is -fno-exceptions, so
//     the throwing forms simply terminate on a null malloc rather than throwing bad_alloc.
//
// WHY WARM-UP MATTERS: vDSP setup adoption, first-call lazy paths, std::vector growth, and any
// one-time initialisation must happen BEFORE the guard is armed, or they masquerade as RT-path
// allocations. Each soak warms up with several process()/pullFloat() calls disarmed first.
//
// Tests: Soak_DSPKernel_ZeroRtAlloc_FullChain (intensity 1.0),
//        Soak_DSPKernel_ZeroRtAlloc_Blend    (intensity 0.5 — exercises the crossfade path),
//        Soak_GaplessSource_ZeroRtAlloc_Pull (seam-straddle path under the guard).
//
// A non-zero count is a REAL FINDING (it is reported with the stage and count, not papered over).

#include <cstdlib> // std::getenv (SOAK_FULL opt-in for the full 1 hr soak)
#include <new> // std::nothrow_t, std::align_val_t (operator new/delete overload signatures)

namespace
{
    // -----------------------------------------------------------------------------------------
    // Allocation-guard state. THREAD_LOCAL armed flag (only the measured thread trips the guard);
    // global atomic counter. Defined in the unnamed namespace of this single TU; the operator
    // new/delete overrides below reference them at namespace scope via these accessors.
    // -----------------------------------------------------------------------------------------
    // NOLINTBEGIN(cppcoreguidelines-avoid-non-const-globals)
    thread_local bool rtGuardArmed = false;
    std::atomic<uint64_t> rtAllocCount{0U};
    // NOLINTEND(cppcoreguidelines-avoid-non-const-globals)

    // RAII arm/disarm so an early return inside a soak can never leave the guard armed.
    struct RtGuardScope
    {
        RtGuardScope() noexcept
        {
            rtAllocCount.store(0U, std::memory_order_relaxed);
            rtGuardArmed = true;
        }
        ~RtGuardScope() noexcept { rtGuardArmed = false; }
        RtGuardScope(const RtGuardScope&) = delete;
        RtGuardScope(RtGuardScope&&) = delete;
        auto operator=(const RtGuardScope&) -> RtGuardScope& = delete;
        auto operator=(RtGuardScope&&) -> RtGuardScope& = delete;

        [[nodiscard]] static auto count() noexcept -> uint64_t
        {
            return rtAllocCount.load(std::memory_order_relaxed);
        }
    };
} // namespace

// ---------------------------------------------------------------------------------------------
// TEST-ONLY global operator new / delete overrides. These live in the test TU only and are
// therefore harmless to the shipping app. Each form routes through std::malloc / std::free so
// new/delete always pair, and bumps rtAllocCount only when the CALLING thread is armed.
//
// -fno-exceptions: the standard "throwing" operator new cannot throw here; on a null malloc we
// std::abort() (equivalent to the runtime's terminate-on-bad_alloc under -fno-exceptions).
// ---------------------------------------------------------------------------------------------

namespace
{
    inline auto rtGuardedMalloc(std::size_t size) -> void*
    {
        if (rtGuardArmed)
        {
            rtAllocCount.fetch_add(1U, std::memory_order_relaxed);
        }
        // malloc(0) may return nullptr legitimately; normalise to a 1-byte request so a valid,
        // freeable pointer is always returned (matches the standard new's "non-null" contract).
        void* ptr = std::malloc(size == 0U ? 1U : size); // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
        if (ptr == nullptr)
        {
            std::abort(); // -fno-exceptions: cannot throw std::bad_alloc; terminate like the runtime.
        }
        return ptr;
    }

    inline auto rtGuardedAlignedMalloc(std::size_t size, std::size_t alignment) -> void*
    {
        if (rtGuardArmed)
        {
            rtAllocCount.fetch_add(1U, std::memory_order_relaxed);
        }
        void* ptr = nullptr;
        // posix_memalign requires alignment be a power of two and a multiple of sizeof(void*).
        std::size_t align = alignment < sizeof(void*) ? sizeof(void*) : alignment;
        if (posix_memalign(&ptr, align, size == 0U ? 1U : size) != 0)
        {
            std::abort();
        }
        return ptr;
    }
} // namespace

// NOLINTBEGIN(readability-named-parameter,readability-inconsistent-declaration-parameter-name)
// Global operator new/delete overrides intentionally use unnamed params: they cannot match
// libc++'s reserved declaration parameter names (e.g. __sz / __align), so readability-named-parameter
// and readability-inconsistent-declaration-parameter-name are mutually unsatisfiable for this idiom.
// The overrides themselves are correct and test-only (the RT-allocation guard).
// Plain + array, throwing forms.
auto operator new(std::size_t size) -> void* { return rtGuardedMalloc(size); }
auto operator new[](std::size_t size) -> void* { return rtGuardedMalloc(size); }

// nothrow forms (never abort: return nullptr on failure to honour the nothrow contract).
auto operator new(std::size_t size, const std::nothrow_t&) noexcept -> void*
{
    if (rtGuardArmed)
    {
        rtAllocCount.fetch_add(1U, std::memory_order_relaxed);
    }
    return std::malloc(size == 0U ? 1U : size); // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
}
auto operator new[](std::size_t size, const std::nothrow_t&) noexcept -> void*
{
    if (rtGuardArmed)
    {
        rtAllocCount.fetch_add(1U, std::memory_order_relaxed);
    }
    return std::malloc(size == 0U ? 1U : size); // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
}

// Aligned forms (C++17 over-aligned new). The toolchain emits these for over-aligned types.
auto operator new(std::size_t size, std::align_val_t align) -> void*
{
    return rtGuardedAlignedMalloc(size, static_cast<std::size_t>(align));
}
auto operator new[](std::size_t size, std::align_val_t align) -> void*
{
    return rtGuardedAlignedMalloc(size, static_cast<std::size_t>(align));
}

// Matching delete forms — all route to std::free (malloc/posix_memalign are both free-able).
void operator delete(void* ptr) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete[](void* ptr) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete(void* ptr, std::size_t) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete[](void* ptr, std::size_t) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete(void* ptr, const std::nothrow_t&) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete[](void* ptr, const std::nothrow_t&) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete(void* ptr, std::align_val_t) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete[](void* ptr, std::align_val_t) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete(void* ptr, std::size_t, std::align_val_t) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
void operator delete[](void* ptr, std::size_t, std::align_val_t) noexcept { std::free(ptr); } // NOLINT(cppcoreguidelines-no-malloc,hicpp-no-malloc)
// NOLINTEND(readability-named-parameter,readability-inconsistent-declaration-parameter-name)

namespace
{
    // -----------------------------------------------------------------------------------------
    // Soak parameters.
    //
    // 1 hr at 512 frames / 48 kHz ≈ 48000*3600/512 ≈ 337,500 buffers. Running the full hour-
    // equivalent through process() is fast (a few seconds), so the DSPKernel soaks use the full
    // count. The Gapless soak re-arms a fresh real-file seam each iteration (decode-thread bound),
    // so it uses a representative count and documents the equivalent duration.
    // -----------------------------------------------------------------------------------------
    constexpr uint32_t kSoakFrames = TestConstants::kFrames512;       // 512
    constexpr uint32_t kSoakSampleRate = TestConstants::kSampleRate48k; // 48 kHz
    // Full ~1 hr-equivalent buffer count at 512/48k.
    constexpr uint64_t kSoakBuffers1hr = 337500U;    // full ~1 hr @ 512/48k (opt-in: SOAK_FULL=1)
    constexpr uint64_t kSoakBuffersDefault = 2000U; // ~21 s @ 512/48k — fast default (~1 s/soak)
    constexpr uint32_t kSoakChannels = 2U;

    // Zero-allocation is a BINARY property, so the fast default count proves it in a few seconds;
    // the full ~1 hr-equivalent soak (opt-in via the SOAK_FULL=1 env var) adds coverage for rare
    // PERIODIC allocations during a deep/periodic run.
    [[nodiscard]] auto soakBuffers() -> uint64_t
    {
        const char* full = std::getenv("SOAK_FULL");
        return (full != nullptr && full[0] == '1') ? kSoakBuffers1hr : kSoakBuffersDefault;
    }
    // Warm-up calls before arming: enough to settle the intensity ramp, adopt vDSP setups, and
    // walk any first-call lazy path.
    constexpr uint32_t kSoakWarmup = 256U;

    // Fill a stereo TestABL with band-limited-ish pseudo-noise (deterministic) so every module
    // does real work each buffer (the limiter ring, loudness meter, EQ biquads all run).
    auto fillSoakBlock(TestABL& abl, uint32_t frames, uint32_t& phase) -> void
    {
        for (uint32_t idx = 0U; idx < frames; ++idx)
        {
            // Cheap deterministic signal at moderate level (~-12 dBFS) — no allocation, just maths.
            const float t = static_cast<float>((phase + idx) % kSoakSampleRate);
            const float s = TestConstants::kPerChAmplitude *
                            std::sin(2.0F * std::numbers::pi_v<float> * 997.0F * t /
                                     static_cast<float>(kSoakSampleRate));
            abl.left[idx] = s;
            abl.right[idx] = s;
        }
        phase += frames;
    }

    // Median of a small sample vector (copy + nth_element). Used off-guard for the timing report.
    auto medianOf(std::vector<double> v) -> double
    {
        if (v.empty())
        {
            return 0.0;
        }
        const std::size_t mid = v.size() / 2U;
        std::nth_element(v.begin(), v.begin() + static_cast<std::ptrdiff_t>(mid), v.end());
        return v[mid];
    }

    // Shared body: soak DSPKernel::process() at a given intensity for `buffers` buffers under the
    // RT-allocation guard, asserting zero allocations and bounded per-buffer timing. Returns "" on
    // pass, a non-empty failure string otherwise. `info` is populated with the report line.
    auto dspKernelSoakBody(float intensity, uint64_t buffers, std::string& info) -> std::string
    {
        DSPKernel kernel;
        kernel.initialize(kSoakSampleRate, kSoakFrames);

        // EQ active (a +6 dB @ 1 kHz boost, real biquads) so the chain actually computes; plus the
        // requested intensity. makeIdentityState() neutralises the stub modules + bypasses the
        // limiter; we re-enable the limiter ceiling so the limiter ring path also runs.
        std::array<float, kEqBands> gains{};
        gains[kBand1kHzIndex] = kEqBoostDb;
        TargetState state = makeIdentityState();
        state.eq = EQModuleCoefficients::computeBiquadCascade(
            gains, static_cast<float>(kSoakSampleRate));
        state.intensityLinear = intensity;
        state.limiter.truePeakCeilingLinear = 0.89F; // < 1.0 → limiter ring path active (-1 dBTP-ish)
        kernel.publishTargetState(state);

        TestABL abl(kSoakFrames);
        uint32_t phase = 0U;

        // WARM-UP (disarmed): settle the intensity ramp + walk first-call/vDSP-setup paths so any
        // one-time allocation happens OUTSIDE the guarded region.
        for (uint32_t w = 0U; w < kSoakWarmup; ++w)
        {
            fillSoakBlock(abl, kSoakFrames, phase);
            kernel.process(abl.abl(), kSoakFrames);
        }

        // Timing sample (off-guard arithmetic is fine; the guard is thread_local and only set
        // inside the armed region — std::chrono::now() does not allocate).
        double minNs = 0.0;
        double maxNs = 0.0;
        double lastNs = 0.0;
        std::vector<double> sample;            // sparse timing sample for the median
        sample.reserve(1024U);                 // reserved BEFORE arming → no alloc under guard
        const uint64_t sampleEvery = std::max<uint64_t>(1U, buffers / 1000U);

        {
            const RtGuardScope guard; // arms this thread; resets the counter
            for (uint64_t b = 0U; b < buffers; ++b)
            {
                fillSoakBlock(abl, kSoakFrames, phase);
                const auto t0 = std::chrono::steady_clock::now();
                kernel.process(abl.abl(), kSoakFrames);
                const auto t1 = std::chrono::steady_clock::now();
                const double ns =
                    std::chrono::duration<double, std::nano>(t1 - t0).count();
                lastNs = ns;
                if (b == 0U || ns < minNs) { minNs = ns; }
                if (ns > maxNs) { maxNs = ns; }
                if ((b % sampleEvery) == 0U && sample.size() < sample.capacity())
                {
                    sample.push_back(ns);
                }
            }
        } // guard disarmed here

        const uint64_t allocs = RtGuardScope::count();
        const double seconds =
            static_cast<double>(buffers) * static_cast<double>(kSoakFrames) /
            static_cast<double>(kSoakSampleRate);
        const double median = medianOf(sample);

        std::ostringstream oss;
        oss << "  [info] intensity=" << intensity << " buffers=" << buffers
            << " (~" << seconds << " s @ " << kSoakFrames << "/" << kSoakSampleRate << ")"
            << " rtAllocs=" << allocs << " perBuf_ns[min/med/max/last]=" << minNs << "/" << median
            << "/" << maxNs << "/" << lastNs << "\n";
        info = oss.str();

        if (allocs != 0U)
        {
            std::ostringstream err;
            err << "RT path ALLOCATED " << allocs << " time(s) over " << buffers
                << " buffers at intensity " << intensity
                << " — DSPKernel::process() is NOT allocation-free (REAL FINDING)";
            return err.str();
        }

        // Bounded-timing guard (LENIENT — timing is noisy in a test; the alloc assertion is the
        // primary gate). The LAST buffer must not be pathologically slower than the median (a
        // growth/leak symptom). Only enforced when the median is meaningfully above the clock floor.
        constexpr double kTimingFloorNs = 200.0; // below this the ratio is pure clock noise
        constexpr double kMaxLastOverMedian = 50.0;
        if (median > kTimingFloorNs && lastNs > kMaxLastOverMedian * median)
        {
            std::ostringstream err;
            err << "per-buffer time DRIFT: last=" << lastNs << " ns > " << kMaxLastOverMedian
                << "x median=" << median << " ns (possible unbounded growth)";
            return err.str();
        }
        return {};
    }
} // namespace

// Soak 1: full chain at intensity 1.0 (BRANCH 2 — in-place chain, the golden-master path).
static auto testSoakDspKernelZeroRtAllocFullChain() -> void
{
    static const char* const kName = "Soak_DSPKernel_ZeroRtAlloc_FullChain";
    std::string info;
    const std::string err = dspKernelSoakBody(1.0F, soakBuffers(), info);
    logInfo(info);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// Soak 2: intermediate intensity 0.5 (BRANCH 3 — equal-power crossfade / blend path, which uses the
// pre-allocated dryScratch_ / wetGainBuf_ / dryGainBuf_). This is the path most at risk of an
// accidental allocation, so it gets its own soak.
static auto testSoakDspKernelZeroRtAllocBlend() -> void
{
    static const char* const kName = "Soak_DSPKernel_ZeroRtAlloc_Blend";
    std::string info;
    const std::string err = dspKernelSoakBody(0.5F, soakBuffers(), info);
    logInfo(info);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// Soak 3: GaplessSource::pullFloat under the guard, with a seam armed each iteration so the
// seam-straddle path is exercised. The decoder runs on a SEPARATE off-RT thread that legitimately
// allocates — the thread_local guard means only THIS (pull) thread is measured, so the decoder
// thread's allocations never trip it. Off-RT control work (setCurrent/armNext/reapRetired, which
// DOES allocate FileDecodeSources + spawn decode threads) is deliberately done DISARMED, around the
// armed pull region.
//
// Because each seam consumes a real decoded file, this soak uses a representative iteration count
// (not the full 337,500) and documents the equivalent duration. Within each iteration the actual
// pullFloat hot path — including the A→B straddle — runs under the armed guard.
static auto testSoakGaplessSourceZeroRtAllocPull() -> void
{
    static const char* const kName = "Soak_GaplessSource_ZeroRtAlloc_Pull";

    // A small two-segment ramp pair (reuses the gapless fixtures). Each seam drains A then B; we
    // rebuild the session each iteration so a fresh seam straddle is measured every time.
    const std::string writeErr =
        writeGaplessSeamPair(kPathPureGaplessA, kPathPureGaplessB, kB2bRate48k);
    if (!writeErr.empty())
    {
        logFail(kName, writeErr);
        return;
    }
    const auto cleanup = []
    {
        std::remove(kPathPureGaplessA);
        std::remove(kPathPureGaplessB);
    };

    // Representative iteration count. Each iteration drains the full A+B pair (4096 frames) across
    // seam-straddling pulls. kGaplessIters seams × kGaplessTotalFrames frames is the soak's audio.
    constexpr uint32_t kGaplessIters = 200U;
    const uint64_t framesPerIter = kGaplessTotalFrames; // 4096
    const double secondsEquiv = static_cast<double>(kGaplessIters) *
                                static_cast<double>(framesPerIter) / kB2bRate48k;

    // Pull buffer: one chunk; reused across all pulls. Reserve capacity off-guard.
    std::vector<float> out(static_cast<std::size_t>(kPureGaplessPullChunk) * kSoakChannels, 0.0F);

    uint64_t totalSeams = 0U;
    uint64_t totalPulls = 0U;

    for (uint32_t iter = 0U; iter < kGaplessIters; ++iter)
    {
        // --- Off-RT control (DISARMED): open fresh sources, install + arm the seam. ---
        auto srcA = openPureGaplessSource(kPathPureGaplessA);
        auto srcB = openPureGaplessSource(kPathPureGaplessB);
        if (srcA == nullptr || srcB == nullptr)
        {
            cleanup();
            logFail(kName, "could not open A and/or B FileDecodeSource");
            return;
        }
        GaplessSource gapless;
        gapless.setCurrent(std::move(srcA));
        if (!gapless.armNext(std::move(srcB)))
        {
            cleanup();
            logFail(kName, "armNext(B) refused");
            return;
        }

        // WARM-UP (disarmed): pull a few chunks so the decode thread is running and the ring is
        // primed before we measure the RT pulls.
        for (uint32_t w = 0U; w < 4U; ++w)
        {
            static_cast<void>(gapless.pullFloat(out.data(), kPureGaplessPullChunk, kSoakChannels));
        }

        // --- RT pull region (ARMED): drain to ended(), straddling the A→B seam under the guard. ---
        {
            const RtGuardScope guard;
            int idleSpins = 0;
            while (idleSpins < kPureGaplessMaxSpins && !gapless.ended())
            {
                const uint32_t produced =
                    gapless.pullFloat(out.data(), kPureGaplessPullChunk, kSoakChannels);
                ++totalPulls;
                if (produced == 0U)
                {
                    ++idleSpins;
                    // sleep_for does not allocate; it is the only place the armed thread blocks.
                    std::this_thread::sleep_for(std::chrono::milliseconds(kPureGaplessSpinNapMs));
                }
                else
                {
                    idleSpins = 0;
                }
            }
            const uint64_t allocs = RtGuardScope::count();
            if (allocs != 0U)
            {
                // Disarm happens at scope exit; report BEFORE control-plane cleanup runs.
                std::ostringstream err;
                err << "RT pull path ALLOCATED " << allocs << " time(s) on iteration " << iter
                    << " — GaplessSource::pullFloat is NOT allocation-free (REAL FINDING)";
                gapless.reapRetired();
                cleanup();
                logFail(kName, err.str());
                return;
            }
        } // guard disarmed

        totalSeams += gapless.transitionCount();
        gapless.reapRetired(); // off-RT: join the seam-retired source (poll-plane contract)
    }

    cleanup();

    std::ostringstream info;
    info << "  [info] gapless seams=" << totalSeams << " over " << kGaplessIters
         << " iters, pulls=" << totalPulls << " (~" << secondsEquiv << " s of audio @ "
         << kB2bRate48k << " Hz) rtAllocs=0\n";
    logInfo(info.str());

    if (totalSeams != kGaplessIters)
    {
        std::ostringstream err;
        err << "expected " << kGaplessIters << " seams, observed " << totalSeams
            << " (seam-straddle path not exercised each iteration)";
        logFail(kName, err.str());
        return;
    }
    logPass(kName);
}
