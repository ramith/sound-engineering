// GaplessArmContractTests.inc
//
// The ARM contract of the Pure gapless engine (council D41): what plays after the current track
// when the view model changes its mind while it plays (Play Next, a shuffle or repeat change,
// removing the next song). The bridge takes the old pick off at once (clearNext, which races the
// render's seam claim exactly once), arms the new pick only after its file opened and only while
// its request is still the newest, and never replaces an armed pick. GaplessSource adds two
// mechanism rules, pinned here:
//
//   * the end is final — a track that ended with nothing armed never seams into a pick armed
//     later (the view model starts that pick fresh: a short gap, the right song);
//   * arming frees the slot the last seam retired, so a pick armed right after a seam, before the
//     poll plane reaped, still arms.
//
// Fixtures are constant-code tracks — every sample of A is 1000, of B 2000, of C 3000 (int16) —
// so what plays after A is read straight off the output, frame by frame, as the device would get
// it (each render callback zero-fills what the source did not produce). The two race tests run a
// render thread against the control plane and are the TSan/ASan proof of the exchange.
//
// #included into Tests/DSPKernelNullTest.cpp after PureGaplessTests.inc: it reuses
// openPureGaplessSource and FileDecodeTests' writeWav16 / kB2b* constants.
//
// Tests: ArmContract_RetractArmBeforeEnd, ArmContract_OccupiedRefuses, ArmContract_RetractEndArm,
//        ArmContract_ArmBeforeReap, ArmContract_ClearRacesSeam, ArmContract_ArmRacesEnd.

namespace
{
    constexpr const char* kPathArmA = ADAPTIVESOUND_TEST_DATA_DIR "/arm_contract_A.wav";
    constexpr const char* kPathArmB = ADAPTIVESOUND_TEST_DATA_DIR "/arm_contract_B.wav";
    constexpr const char* kPathArmC = ADAPTIVESOUND_TEST_DATA_DIR "/arm_contract_C.wav";

    // Track fingerprints: every int16 sample of the track carries its code (0 = silence).
    constexpr int kArmCodeA = 1000;
    constexpr int kArmCodeB = 2000;
    constexpr int kArmCodeC = 3000;

    constexpr uint32_t kArmTrackFrames = 4800U; // 100 ms at 48 kHz
    constexpr uint32_t kArmShortFrames = 960U;  // 20 ms: a short middle track
    constexpr uint32_t kArmChunk = 256U;        // one render callback (deterministic tests)
    constexpr uint32_t kArmRaceChunk = 64U;     // one render callback (race tests)
    constexpr int kArmBufferPolls = 20000;      // decoder-finished budget, 100 us naps (2 s)
    constexpr int kArmRaceTrials = 2000;
    constexpr uint32_t kArmRaceTrackFrames = 1024U; // the race tests' A: short, so a trial is quick
    constexpr uint32_t kArmRaceJitterFrames = 64U;  // how far before A's end the control plane acts
    constexpr int kArmRaceTailCallbacks = 8; // render callbacks after the control plane acted
    constexpr uint64_t kArmRaceSeed = 0xD41AU;

    // Write the three constant-code fixtures on construction and remove them on destruction, so
    // every return path cleans up. `framesA` / `framesB` size A and B; C is always kArmTrackFrames.
    struct ArmContractFixtures
    {
        bool written = false;

        explicit ArmContractFixtures(uint32_t framesA = kArmTrackFrames,
                                     uint32_t framesB = kArmTrackFrames)
            : written(write(kPathArmA, kArmCodeA, framesA) &&
                      write(kPathArmB, kArmCodeB, framesB) &&
                      write(kPathArmC, kArmCodeC, kArmTrackFrames))
        {
        }

        ~ArmContractFixtures()
        {
            std::remove(kPathArmA);
            std::remove(kPathArmB);
            std::remove(kPathArmC);
        }

        ArmContractFixtures(const ArmContractFixtures&) = delete;
        ArmContractFixtures(ArmContractFixtures&&) = delete;
        auto operator=(const ArmContractFixtures&) -> ArmContractFixtures& = delete;
        auto operator=(ArmContractFixtures&&) -> ArmContractFixtures& = delete;

      private:
        static auto write(const char* path, int code, uint32_t frames) -> bool
        {
            const std::vector<int16_t> samples(static_cast<std::size_t>(frames) * kB2bChannels2,
                                               static_cast<int16_t>(code));
            return writeWav16(path, samples, kB2bChannels2, kB2bRate48k);
        }
    };

    // Open a fixture and wait until it is fully decoded: the tracks fit the decode ring, so from
    // then on every pull is served from memory and a short fill can only mean the true end.
    auto openArmTrack(const char* path) -> std::unique_ptr<FileDecodeSource>
    {
        auto source = openPureGaplessSource(path);
        for (int poll = 0;
             source != nullptr && !source->decoderFinished() && poll < kArmBufferPolls;
             ++poll)
        {
            std::this_thread::sleep_for(std::chrono::microseconds(100));
        }
        return source;
    }

    // The fingerprint of one rendered sample.
    auto armCode(float sample) -> int
    {
        return static_cast<int>(std::lround(static_cast<double>(sample) * kB2bI16Scale));
    }

    // One render callback of `frames` frames, as the device gets it: the source's frames, then
    // silence for the rest. Appends one fingerprint per frame (left channel) to `codes`.
    auto renderCallback(GaplessSource& gapless,
                        std::vector<float>& block,
                        uint32_t frames,
                        std::vector<int>& codes) -> void
    {
        std::ranges::fill(block, 0.0F);
        static_cast<void>(gapless.pullFloat(block.data(), frames, kB2bChannels2));
        for (uint32_t frame = 0U; frame < frames; ++frame)
        {
            codes.push_back(armCode(block[static_cast<std::size_t>(frame) * kB2bChannels2]));
        }
    }

    auto renderCallbacks(GaplessSource& gapless, int callbacks) -> std::vector<int>
    {
        std::vector<float> block(static_cast<std::size_t>(kArmChunk) * kB2bChannels2, 0.0F);
        std::vector<int> codes;
        for (int callback = 0; callback < callbacks; ++callback)
        {
            renderCallback(gapless, block, kArmChunk, codes);
        }
        return codes;
    }

    // What the device played after A: A's frame count, the code of the frame right after A's last
    // (0 = silence), and whether `code` sounds anywhere after A.
    struct AfterA
    {
        std::size_t framesOfA = 0U;
        int next = 0;

        [[nodiscard]] auto heard(const std::vector<int>& codes, int code) const -> bool
        {
            return std::ranges::find(codes.begin() + static_cast<std::ptrdiff_t>(framesOfA),
                                     codes.end(),
                                     code) != codes.end();
        }
    };

    auto afterA(const std::vector<int>& codes) -> AfterA
    {
        AfterA result;
        while (result.framesOfA < codes.size() && codes[result.framesOfA] == kArmCodeA)
        {
            ++result.framesOfA;
        }
        result.next = result.framesOfA < codes.size() ? codes[result.framesOfA] : 0;
        return result;
    }

    // A tiny deterministic generator for the race tests' jitter (splitmix64).
    struct ArmRaceRng
    {
        uint64_t state;

        auto next() -> uint64_t
        {
            state += 0x9E3779B97F4A7C15ULL;
            uint64_t mixed = state;
            mixed = (mixed ^ (mixed >> 30U)) * 0xBF58476D1CE4E5B9ULL;
            mixed = (mixed ^ (mixed >> 27U)) * 0x94D049BB133111EBULL;
            return mixed ^ (mixed >> 31U);
        }
    };
} // namespace

// The view model's change of mind, before A ends: the old pick B comes off, the new pick C arms,
// and C plays right after A — B never sounds. (Passes before and after D41: the guard.)
static auto testArmContractRetractArmBeforeEnd() -> void
{
    static const char* const kName = "ArmContract_RetractArmBeforeEnd";
    const ArmContractFixtures fixtures;
    auto trackA = openArmTrack(kPathArmA);
    auto trackB = openArmTrack(kPathArmB);
    auto trackC = openArmTrack(kPathArmC);
    if (!fixtures.written || trackA == nullptr || trackB == nullptr || trackC == nullptr)
    {
        logFail(kName, "could not write or open the A/B/C fixtures");
        return;
    }
    GaplessSource gapless;
    gapless.setCurrent(std::move(trackA));
    std::string err;
    if (!gapless.armNext(std::move(trackB)))
    {
        err += "armNext(B) refused; ";
    }
    gapless.clearNext(); // the old pick comes off at admission
    if (!gapless.armNext(std::move(trackC)))
    {
        err += "armNext(C) refused into the slot clearNext emptied; ";
    }
    constexpr int kCallbacks = 40; // A (4800) + C (4800) < 40 x 256
    const std::vector<int> codes = renderCallbacks(gapless, kCallbacks);
    const AfterA after = afterA(codes);
    if (after.framesOfA != kArmTrackFrames)
    {
        err += std::format("A played {} of {} frames; ", after.framesOfA, kArmTrackFrames);
    }
    if (after.next != kArmCodeC)
    {
        err += std::format("the frame after A is {}, not C ({}); ", after.next, kArmCodeC);
    }
    if (after.heard(codes, kArmCodeB))
    {
        err += "the retracted pick B sounded; ";
    }
    if (gapless.transitionCount() != 1U)
    {
        err += std::format("transitionCount {}, expected 1; ", gapless.transitionCount());
    }
    gapless.reapRetired();
    if (err.empty())
    {
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}

// One slot, never replaced: arming while a pick is armed is refused and the armed pick plays. The
// bridge never relies on a replace — it takes the old pick off first. (Passes before and after.)
static auto testArmContractOccupiedRefuses() -> void
{
    static const char* const kName = "ArmContract_OccupiedRefuses";
    const ArmContractFixtures fixtures;
    auto trackA = openArmTrack(kPathArmA);
    auto trackB = openArmTrack(kPathArmB);
    auto trackC = openArmTrack(kPathArmC);
    if (!fixtures.written || trackA == nullptr || trackB == nullptr || trackC == nullptr)
    {
        logFail(kName, "could not write or open the A/B/C fixtures");
        return;
    }
    GaplessSource gapless;
    gapless.setCurrent(std::move(trackA));
    std::string err;
    if (!gapless.armNext(std::move(trackB)))
    {
        err += "armNext(B) refused; ";
    }
    if (gapless.armNext(std::move(trackC)))
    {
        err += "armNext(C) replaced the armed B (arming must never replace); ";
    }
    constexpr int kCallbacks = 40;
    const std::vector<int> codes = renderCallbacks(gapless, kCallbacks);
    const AfterA after = afterA(codes);
    if (after.next != kArmCodeB || after.heard(codes, kArmCodeC))
    {
        err += std::format("after A came {} (C heard: {}), expected B ({}) alone; ",
                           after.next,
                           after.heard(codes, kArmCodeC),
                           kArmCodeB);
    }
    gapless.reapRetired();
    if (err.empty())
    {
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}

// The end is final. The old pick B came off and A ended before the new pick C opened: the session
// is over, the arm of C is refused, and no later render callback seams into it — the view model
// starts C fresh. Before D41 the late arm was accepted and the next callback seamed into C after
// the end (a second start of C stuttered over it; a queue-end stop cut it off).
static auto testArmContractRetractEndArm() -> void
{
    static const char* const kName = "ArmContract_RetractEndArm";
    const ArmContractFixtures fixtures;
    auto trackA = openArmTrack(kPathArmA);
    auto trackB = openArmTrack(kPathArmB);
    auto trackC = openArmTrack(kPathArmC);
    if (!fixtures.written || trackA == nullptr || trackB == nullptr || trackC == nullptr)
    {
        logFail(kName, "could not write or open the A/B/C fixtures");
        return;
    }
    GaplessSource gapless;
    gapless.setCurrent(std::move(trackA));
    std::string err;
    if (!gapless.armNext(std::move(trackB)))
    {
        err += "armNext(B) refused; ";
    }
    gapless.clearNext();                // retracted at admission; C is still opening
    constexpr int kCallbacksToEnd = 20; // A is 18.75 callbacks
    std::vector<int> codes = renderCallbacks(gapless, kCallbacksToEnd);
    if (!gapless.ended())
    {
        err += "A did not end with nothing armed; ";
    }
    if (gapless.armNext(std::move(trackC)))
    {
        err += "armNext(C) accepted after the end; ";
    }
    constexpr int kCallbacksAfter = 20;
    const std::vector<int> later = renderCallbacks(gapless, kCallbacksAfter);
    codes.insert(codes.end(), later.begin(), later.end());
    const AfterA after = afterA(codes);
    if (after.framesOfA != kArmTrackFrames || after.heard(codes, kArmCodeB) ||
        after.heard(codes, kArmCodeC))
    {
        err += std::format(
            "after the end: A {} frames, B heard {}, C heard {} (only silence may "
            "follow A); ",
            after.framesOfA,
            after.heard(codes, kArmCodeB),
            after.heard(codes, kArmCodeC));
    }
    if (gapless.transitionCount() != 0U || !gapless.ended())
    {
        err += std::format("transitionCount {}, ended {} (expected 0, true); ",
                           gapless.transitionCount(),
                           gapless.ended());
    }
    if (err.empty())
    {
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}

// Arming frees the slot the last seam retired. A seamed into a short B; C is armed right away,
// before any reap (the poll plane's or anyone's): it arms, and plays right after B. Before D41 the
// retired A still held the free slot, so the arm failed and B -> C took a gap (council H3e).
static auto testArmContractArmBeforeReap() -> void
{
    static const char* const kName = "ArmContract_ArmBeforeReap";
    const ArmContractFixtures fixtures(kArmTrackFrames, kArmShortFrames);
    auto trackA = openArmTrack(kPathArmA);
    auto trackB = openArmTrack(kPathArmB);
    auto trackC = openArmTrack(kPathArmC);
    if (!fixtures.written || trackA == nullptr || trackB == nullptr || trackC == nullptr)
    {
        logFail(kName, "could not write or open the A/B/C fixtures");
        return;
    }
    GaplessSource gapless;
    gapless.setCurrent(std::move(trackA));
    std::string err;
    if (!gapless.armNext(std::move(trackB)))
    {
        err += "armNext(B) refused; ";
    }
    std::vector<float> block(static_cast<std::size_t>(kArmChunk) * kB2bChannels2, 0.0F);
    std::vector<int> codes;
    constexpr int kMaxCallbacks = 40;
    int callbacks = 0;
    while (gapless.transitionCount() == 0U && callbacks < kMaxCallbacks)
    {
        renderCallback(gapless, block, kArmChunk, codes);
        ++callbacks;
    }
    if (!gapless.hasPendingReap())
    {
        err += "the A->B seam left nothing parked (precondition); ";
    }
    if (!gapless.armNext(std::move(trackC)))
    {
        err += "armNext(C) refused right after the seam, before a reap; ";
    }
    const std::vector<int> later = renderCallbacks(gapless, kMaxCallbacks - callbacks);
    codes.insert(codes.end(), later.begin(), later.end());
    const AfterA after = afterA(codes);
    std::size_t framesOfB = 0U;
    while (after.framesOfA + framesOfB < codes.size() &&
           codes[after.framesOfA + framesOfB] == kArmCodeB)
    {
        ++framesOfB;
    }
    const std::size_t firstAfterB = after.framesOfA + framesOfB;
    const int nextAfterB = firstAfterB < codes.size() ? codes[firstAfterB] : 0;
    if (after.framesOfA != kArmTrackFrames || framesOfB != kArmShortFrames ||
        nextAfterB != kArmCodeC)
    {
        err += std::format(
            "played A {} / B {} frames, then {} (expected {} / {}, then C {} "
            "gaplessly); ",
            after.framesOfA,
            framesOfB,
            nextAfterB,
            kArmTrackFrames,
            kArmShortFrames,
            kArmCodeC);
    }
    if (gapless.transitionCount() != 2U)
    {
        err += std::format("transitionCount {}, expected 2; ", gapless.transitionCount());
    }
    gapless.reapRetired();
    if (err.empty())
    {
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}

namespace
{
    // The outcome of one race trial, read after the render thread joined.
    struct ArmRaceOutcome
    {
        std::vector<int> codes;
        uint64_t transitions = 0U;
        bool ended = false;
    };

    // Run one trial: a render thread pulls kArmRaceChunk-frame callbacks from `gapless` (A playing)
    // until the control plane has acted and kArmRaceTailCallbacks more callbacks rendered. The
    // control plane (this thread) waits until `when` says it is time — or the render thread ran out
    // of callbacks — then runs `act`.
    template <typename When, typename Act>
    auto runArmRace(GaplessSource& gapless, When when, Act act) -> ArmRaceOutcome
    {
        std::atomic<bool> acted{false};
        std::atomic<bool> renderDone{false};
        ArmRaceOutcome outcome;
        std::thread render(
            [&gapless, &acted, &renderDone, &outcome]
            {
                std::vector<float> block(static_cast<std::size_t>(kArmRaceChunk) * kB2bChannels2,
                                         0.0F);
                int tail = 0;
                constexpr int kMaxCallbacks = 4096;
                for (int callback = 0; callback < kMaxCallbacks && tail < kArmRaceTailCallbacks;
                     ++callback)
                {
                    renderCallback(gapless, block, kArmRaceChunk, outcome.codes);
                    if (acted.load(std::memory_order_acquire))
                    {
                        ++tail;
                    }
                }
                renderDone.store(true, std::memory_order_release);
            });
        while (!when() && !renderDone.load(std::memory_order_acquire))
        {
            std::this_thread::yield();
        }
        act();
        acted.store(true, std::memory_order_release);
        render.join();
        outcome.transitions = gapless.transitionCount();
        outcome.ended = gapless.ended();
        return outcome;
    }
} // namespace

// The old pick comes off while the render reaches A's end: the clear races the seam claim, and
// exactly one side wins, every trial. Either the seam won — B follows A gaplessly and stays the
// current track — or the clear won — A ends, nothing follows, B never sounds. Nothing in between:
// no B after silence, no seam counted without B, no double free or leak (ASan), no data race (TSan).
static auto testArmContractClearRacesSeam() -> void
{
    static const char* const kName = "ArmContract_ClearRacesSeam";
    const ArmContractFixtures fixtures(kArmRaceTrackFrames, kArmTrackFrames);
    if (!fixtures.written)
    {
        logFail(kName, "could not write the fixtures");
        return;
    }
    ArmRaceRng rng{kArmRaceSeed};
    int seamWon = 0;
    int clearWon = 0;
    std::string err;
    for (int trial = 0; trial < kArmRaceTrials && err.empty(); ++trial)
    {
        auto trackA = openArmTrack(kPathArmA);
        auto trackB = openArmTrack(kPathArmB);
        if (trackA == nullptr || trackB == nullptr)
        {
            err = "could not open the fixtures";
            break;
        }
        GaplessSource gapless;
        gapless.setCurrent(std::move(trackA));
        if (!gapless.armNext(std::move(trackB)))
        {
            err = "armNext(B) refused";
            break;
        }
        const uint64_t actAt = kArmRaceTrackFrames - (rng.next() % kArmRaceJitterFrames);
        const ArmRaceOutcome outcome = runArmRace(
            gapless,
            [&gapless, actAt]
            {
                return gapless.transitionCount() > 0U || gapless.ended() ||
                       gapless.renderedFramesCurrent() >= actAt;
            },
            [&gapless] { gapless.clearNext(); });
        const AfterA after = afterA(outcome.codes);
        const bool bHeard = after.heard(outcome.codes, kArmCodeB);
        if (after.framesOfA != kArmRaceTrackFrames)
        {
            err = std::format(
                "trial {}: A played {} of {} frames", trial, after.framesOfA, kArmRaceTrackFrames);
        }
        else if (outcome.transitions == 1U && after.next == kArmCodeB)
        {
            ++seamWon; // B follows A gaplessly (it may have played out on a slow runner)
        }
        else if (outcome.transitions == 0U && outcome.ended && !bHeard)
        {
            ++clearWon;
        }
        else
        {
            err = std::format(
                "trial {}: transitions {}, ended {}, after A {}, B heard {} — neither "
                "a clean seam nor a clean clear",
                trial,
                outcome.transitions,
                outcome.ended,
                after.next,
                bHeard);
        }
        gapless.reapRetired();
    }
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logInfo(std::format("  [info] {}: {} trials, seam won {}, clear won {}\n",
                        kName,
                        kArmRaceTrials,
                        seamWon,
                        clearWon));
    logPass(kName);
}

// The new pick C arms while the render reaches A's end with nothing armed. Half the trials arm
// after the end was seen (the late open of a retracted-then-re-picked track); half race the end.
// Either C was armed in time and follows A gaplessly, or the end won and C never sounds — the end
// is final, whether armNext saw it or the arm slipped in behind it. Before D41 every late arm was
// accepted and a later callback seamed into C after the end (silence, then C, with ended still set).
static auto testArmContractArmRacesEnd() -> void
{
    static const char* const kName = "ArmContract_ArmRacesEnd";
    const ArmContractFixtures fixtures(kArmRaceTrackFrames, kArmTrackFrames);
    if (!fixtures.written)
    {
        logFail(kName, "could not write the fixtures");
        return;
    }
    ArmRaceRng rng{kArmRaceSeed + 1U};
    int seamed = 0;
    int endWon = 0;
    int armedUnplayed = 0;
    std::string err;
    for (int trial = 0; trial < kArmRaceTrials && err.empty(); ++trial)
    {
        auto trackA = openArmTrack(kPathArmA);
        auto trackC = openArmTrack(kPathArmC);
        if (trackA == nullptr || trackC == nullptr)
        {
            err = "could not open the fixtures";
            break;
        }
        GaplessSource source;
        source.setCurrent(std::move(trackA));
        const bool late = (trial % 2) == 1;
        const uint64_t actAt = kArmRaceTrackFrames - (rng.next() % kArmRaceJitterFrames);
        bool accepted = false;
        const ArmRaceOutcome outcome = runArmRace(
            source,
            [&source, late, actAt]
            { return source.ended() || (!late && source.renderedFramesCurrent() >= actAt); },
            [&source, &trackC, &accepted] { accepted = source.armNext(std::move(trackC)); });
        const AfterA after = afterA(outcome.codes);
        const bool cHeard = after.heard(outcome.codes, kArmCodeC);
        if (after.framesOfA != kArmRaceTrackFrames)
        {
            err = std::format(
                "trial {}: A played {} of {} frames", trial, after.framesOfA, kArmRaceTrackFrames);
        }
        else if (outcome.transitions == 1U && after.next == kArmCodeC)
        {
            ++seamed; // C follows A gaplessly (it may have played out on a slow runner)
        }
        else if (outcome.transitions == 0U && outcome.ended && !cHeard)
        {
            ++endWon;
            armedUnplayed += accepted ? 1 : 0;
        }
        else
        {
            err = std::format(
                "trial {} ({}): transitions {}, ended {}, after A {}, C heard {} — C "
                "after the end, or a seam that is not gapless",
                trial,
                late ? "arm after the end" : "arm racing the end",
                outcome.transitions,
                outcome.ended,
                after.next,
                cHeard);
        }
    }
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logInfo(
        std::format("  [info] {}: {} trials, gapless {}, end won {} (of which an arm slipped in "
                    "behind the end and was left unplayed: {})\n",
                    kName,
                    kArmRaceTrials,
                    seamed,
                    endWon,
                    armedUnplayed));
    logPass(kName);
}
