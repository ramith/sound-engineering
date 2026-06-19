// PureGaplessTests.inc
//
// Pure-path gapless — STAGE 2 (GaplessSource). #included into Tests/DSPKernelNullTest.cpp after
// TestSupport.h, FileDecodeTests.inc, and GaplessTests.inc (it reuses FileDecodeTests' writeWav16 /
// the kB2b* decode constants and GaplessTests' kGapless* ramp fixtures + makeGaplessRampSegment /
// gaplessExpectedLeft / writeGaplessSeamPair).
//
// These tests drive the RT-thread GaplessSource WITHOUT a CoreAudio device (offline): two
// FileDecodeSources, an active-source swap at A's TRUE end-of-file inside ONE pullFloat call, and
// the off-RT control/poll plane. They prove the Stage-2 seam contract:
//
//   * same-format two-track seam is sample-accurate concatenation (total frames == A+B, boundary
//     samples exact, seam delta == one ramp step → no inserted/dropped/duplicated frame),
//     transitionCount 0→1, ended() true after B exhausts;
//   * exhausted() is false mid-stream and true only after finished_ ∧ ring-drained;
//   * sameRateGaplessCompatible is true for matching sources, false for each differing field
//     (rate / channels / float / bits);
//   * playlist end (no armed next) → ended() true, no crash.
//
// Tests: PureGapless_SeamSampleAccurate, PureGapless_ExhaustedPredicate,
//        PureGapless_SameRateCompatible, PureGapless_PlaylistEndNoNext.

namespace
{
    // Distinct seam fixture paths so these tests never collide with GaplessTests' decode-layer
    // fixtures (which share kPathGaplessA/B and clean them up per test).
    constexpr const char* kPathPureGaplessA = ADAPTIVESOUND_TEST_DATA_DIR "/pure_gapless_A.wav";
    constexpr const char* kPathPureGaplessB = ADAPTIVESOUND_TEST_DATA_DIR "/pure_gapless_B.wav";

    // 32-bit float fixture for the float-mismatch leg of the compatibility test.
    constexpr const char* kPathPureGaplessFloat =
        ADAPTIVESOUND_TEST_DATA_DIR "/pure_gapless_float.wav";
    // 44.1 kHz fixture for the rate-mismatch leg.
    constexpr const char* kPathPureGaplessB44k =
        ADAPTIVESOUND_TEST_DATA_DIR "/pure_gapless_B_44k.wav";
    // Mono fixture for the channel-mismatch leg.
    constexpr const char* kPathPureGaplessMono =
        ADAPTIVESOUND_TEST_DATA_DIR "/pure_gapless_mono.wav";

    // Pull-chunk granularity for the offline seam drains. Small enough that the seam straddle is
    // exercised inside a single pullFloat call, large enough to drain quickly.
    constexpr uint32_t kPureGaplessPullChunk = 256U;
    // Poll budget: the decode thread fills the ring on a background thread; cap total spins.
    constexpr int kPureGaplessMaxSpins = 4000;
    constexpr int kPureGaplessSpinNapMs = 1;
    // ended() can lag the final pull by the poll plane; give it a short budget.
    constexpr int kPureGaplessEndedPollAttempts = 200;

    // Open a FileDecodeSource at `path`; returns nullptr on open failure (caller logs).
    auto openPureGaplessSource(const char* path) -> std::unique_ptr<FileDecodeSource>
    {
        auto src = std::make_unique<FileDecodeSource>();
        if (!src->open(path))
        {
            return nullptr;
        }
        return src;
    }

    // Drain a GaplessSource into `out` (interleaved L,R,...), polling the background decoders, and
    // KEEP pulling past `expectedFrames` until ended() — the final pull that discovers the last
    // track's true EOF is what sets ended() (a drain that stops exactly at the frame count would
    // never trigger it). `out` must hold expectedFrames + one extra chunk. Returns the total
    // NON-ZERO frames produced (real audio, before the trailing zero-fill pulls).
    auto drainGapless(GaplessSource& gapless,
                      std::vector<float>& out,
                      uint32_t expectedFrames,
                      uint32_t channels) -> uint32_t
    {
        const std::size_t capFrames = out.size() / channels;
        uint32_t total = 0U;
        int idleSpins = 0;
        while (idleSpins < kPureGaplessMaxSpins && !gapless.ended())
        {
            const std::size_t room = (total < capFrames) ? (capFrames - total) : 0U;
            if (room == 0U)
            {
                break; // buffer exhausted (should not happen — capacity > expectedFrames)
            }
            const uint32_t want =
                static_cast<uint32_t>(std::min<std::size_t>(kPureGaplessPullChunk, room));
            const uint32_t produced = gapless.pullFloat(
                out.data() + (static_cast<std::size_t>(total) * channels), want, channels);
            total += produced;
            if (produced == 0U)
            {
                ++idleSpins;
                std::this_thread::sleep_for(std::chrono::milliseconds(kPureGaplessSpinNapMs));
            }
            else
            {
                idleSpins = 0;
            }
        }
        // Clamp the reported count to the expected real-audio frames (trailing zero-fill pulls
        // after the last track's EOF do not count as produced audio).
        return std::min(total, expectedFrames);
    }

    // Poll ended() for a short budget (the poll plane can lag the final RT pull).
    auto pollGaplessEnded(GaplessSource& gapless) -> bool
    {
        for (int attempt = 0; attempt < kPureGaplessEndedPollAttempts; ++attempt)
        {
            if (gapless.ended())
            {
                return true;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(kPureGaplessSpinNapMs));
        }
        return gapless.ended();
    }
} // namespace

// Pure-gapless 1: same-format two-track seam is sample-accurate concatenation. setCurrent(A) +
// armNext(B), then drain through GaplessSource::pullFloat. Asserts: total frames == A+B, the
// boundary samples recover their exact ramp values, the seam delta is one ramp step (no inserted/
// dropped/duplicated frame), transitionCount goes 0→1, and ended() is true after B exhausts.
static auto testPureGaplessSeamSampleAccurate() -> void
{
    static const char* const kName = "PureGapless_SeamSampleAccurate";
    constexpr float kClickTol = 3.0F * kRampStep; // one ordinary ramp step at the seam

    const std::string writeErr =
        writeGaplessSeamPair(kPathPureGaplessA, kPathPureGaplessB, kB2bRate48k);
    if (!writeErr.empty())
    {
        logFail(kName, writeErr);
        return;
    }

    auto srcA = openPureGaplessSource(kPathPureGaplessA);
    auto srcB = openPureGaplessSource(kPathPureGaplessB);
    if (srcA == nullptr || srcB == nullptr)
    {
        std::remove(kPathPureGaplessA);
        std::remove(kPathPureGaplessB);
        logFail(kName, "could not open A and/or B FileDecodeSource");
        return;
    }

    GaplessSource gapless;
    gapless.setCurrent(std::move(srcA));
    if (gapless.transitionCount() != 0U)
    {
        std::remove(kPathPureGaplessA);
        std::remove(kPathPureGaplessB);
        logFail(kName, "transitionCount nonzero before any seam");
        return;
    }
    if (!gapless.armNext(std::move(srcB)))
    {
        std::remove(kPathPureGaplessA);
        std::remove(kPathPureGaplessB);
        logFail(kName, "armNext(B) refused");
        return;
    }

    std::vector<float> out(
        static_cast<std::size_t>(kGaplessTotalFrames + kPureGaplessPullChunk) * kB2bChannels2,
        0.0F);
    const uint32_t total = drainGapless(gapless, out, kGaplessTotalFrames, kB2bChannels2);
    const bool ended = pollGaplessEnded(gapless);
    const uint64_t transitions = gapless.transitionCount();
    gapless.reapRetired(); // join the seam-retired source off-RT (poll-plane contract)
    std::remove(kPathPureGaplessA);
    std::remove(kPathPureGaplessB);

    if (total != kGaplessTotalFrames)
    {
        std::ostringstream oss;
        oss << "drained " << total << " of " << kGaplessTotalFrames << " frames (seam dropped/dup?)";
        logFail(kName, oss.str());
        return;
    }
    if (transitions != 1U)
    {
        std::ostringstream oss;
        oss << "transitionCount " << transitions << ", expected 1";
        logFail(kName, oss.str());
        return;
    }
    if (!ended)
    {
        logFail(kName, "ended() not true after B exhausts");
        return;
    }

    const uint32_t lastA = kGaplessSegmentFrames - 1U; // 2047
    const uint32_t firstB = kGaplessSegmentFrames;     // 2048
    const float lastAleft = out[static_cast<std::size_t>(lastA) * kB2bChannels2];
    const float firstBleft = out[static_cast<std::size_t>(firstB) * kB2bChannels2];
    if (std::abs(lastAleft - gaplessExpectedLeft(lastA)) > kRampStep)
    {
        logFail(kName, mismatchMsg("seam A.last left", lastA, gaplessExpectedLeft(lastA), lastAleft));
        return;
    }
    if (std::abs(firstBleft - gaplessExpectedLeft(firstB)) > kRampStep)
    {
        logFail(kName,
                mismatchMsg("seam B.first left", firstB, gaplessExpectedLeft(firstB), firstBleft));
        return;
    }
    const float seamDelta = std::abs(firstBleft - lastAleft);
    if (seamDelta > kClickTol)
    {
        std::ostringstream oss;
        oss << "seam delta " << seamDelta << " exceeds " << kClickTol
            << " (click / inserted silence / dropped or duplicated frame at the A->B seam)";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Pure-gapless 2: the exhausted() true-EOF predicate. A FileDecodeSource is NOT exhausted while it
// still has buffered/undecoded audio, and becomes exhausted only after finished_ AND the ring is
// drained — this is exactly what the seam logic keys off to swap (never on a transient underrun).
static auto testPureGaplessExhaustedPredicate() -> void
{
    static const char* const kName = "PureGapless_ExhaustedPredicate";

    const std::vector<int16_t> seg = makeGaplessRampSegment(0U, kGaplessSegmentFrames);
    if (!writeWav16(kPathPureGaplessA, seg, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the single-segment fixture");
        return;
    }

    FileDecodeSource src;
    if (!src.open(kPathPureGaplessA))
    {
        src.close();
        std::remove(kPathPureGaplessA);
        logFail(kName, "open() failed");
        return;
    }

    // Mid-stream: pull a small prefix, then assert exhausted() is false (there is more audio).
    std::vector<float> prefix(static_cast<std::size_t>(kPureGaplessPullChunk) * kB2bChannels2,
                              0.0F);
    static_cast<void>(drainFrames(src, prefix, kPureGaplessPullChunk, kB2bChannels2));
    if (src.exhausted())
    {
        src.close();
        std::remove(kPathPureGaplessA);
        logFail(kName, "exhausted() true mid-stream (before EOF)");
        return;
    }

    // Drain the remainder, then exhausted() must become true once the decoder finished and the
    // ring drained. Poll: the decode thread sets finished_ after its final push.
    std::vector<float> rest(static_cast<std::size_t>(kGaplessSegmentFrames) * kB2bChannels2, 0.0F);
    uint32_t drained = kPureGaplessPullChunk;
    drained += drainFrames(src, rest, kGaplessSegmentFrames - kPureGaplessPullChunk, kB2bChannels2);

    bool exhausted = false;
    for (int attempt = 0; attempt < kPureGaplessEndedPollAttempts && !exhausted; ++attempt)
    {
        // Keep pulling (returns 0 once drained) so the ring empties and the carry clears.
        std::vector<float> tail(static_cast<std::size_t>(kPureGaplessPullChunk) * kB2bChannels2,
                                0.0F);
        static_cast<void>(src.pullFloat(tail.data(), kPureGaplessPullChunk, kB2bChannels2));
        exhausted = src.exhausted();
        if (!exhausted)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(kPureGaplessSpinNapMs));
        }
    }
    src.close();
    std::remove(kPathPureGaplessA);

    if (drained != kGaplessSegmentFrames)
    {
        std::ostringstream oss;
        oss << "drained " << drained << " of " << kGaplessSegmentFrames << " frames";
        logFail(kName, oss.str());
        return;
    }
    if (!exhausted)
    {
        logFail(kName, "exhausted() not true after finished_ AND ring drained");
        return;
    }
    logPass(kName);
}

// Pure-gapless 3: sameRateGaplessCompatible is true for matching sources and false for EACH
// differing field (rate / channels / float / bits). Builds a 48 kHz/16-bit/stereo reference and
// one mismatched fixture per field, opening real FileDecodeSources so the predicate runs on the
// actual reported format.
static auto testPureGaplessSameRateCompatible() -> void
{
    static const char* const kName = "PureGapless_SameRateCompatible";

    const std::vector<int16_t> seg = makeGaplessRampSegment(0U, kGaplessSegmentFrames);
    // Reference + a second identical-format file → must be compatible.
    const bool wroteRef = writeWav16(kPathPureGaplessA, seg, kB2bChannels2, kB2bRate48k);
    const bool wroteMatch = writeWav16(kPathPureGaplessB, seg, kB2bChannels2, kB2bRate48k);
    // Rate mismatch: same int16/stereo at 44.1 kHz.
    const bool wrote44k = writeWav16(kPathPureGaplessB44k, seg, kB2bChannels2, kB2bRate44k);
    // Channel mismatch: mono.
    const std::vector<int16_t> monoSeg(seg.begin(),
                                       seg.begin()
                                           + static_cast<std::ptrdiff_t>(kGaplessSegmentFrames)
                                               * static_cast<std::ptrdiff_t>(kB2bChannels1));
    const bool wroteMono = writeWav16(kPathPureGaplessMono, monoSeg, kB2bChannels1, kB2bRate48k);
    // Float mismatch: 32-bit float stereo at 48 kHz (same rate/channels, different float-ness/bits).
    std::vector<float> floatSeg(static_cast<std::size_t>(kGaplessSegmentFrames) * kB2bChannels2,
                                0.0F);
    for (std::size_t idx = 0; idx < floatSeg.size(); ++idx)
    {
        floatSeg[idx] = static_cast<float>(seg[idx]) / static_cast<float>(kB2bI16Scale);
    }
    const bool wroteFloat =
        writeWavFloat32(kPathPureGaplessFloat, floatSeg, kB2bChannels2, kB2bRate48k);

    const auto cleanup = []
    {
        std::remove(kPathPureGaplessA);
        std::remove(kPathPureGaplessB);
        std::remove(kPathPureGaplessB44k);
        std::remove(kPathPureGaplessMono);
        std::remove(kPathPureGaplessFloat);
    };

    if (!wroteRef || !wroteMatch || !wrote44k || !wroteMono || !wroteFloat)
    {
        cleanup();
        logFail(kName, "could not write one or more compatibility fixtures");
        return;
    }

    auto ref = openPureGaplessSource(kPathPureGaplessA);
    auto match = openPureGaplessSource(kPathPureGaplessB);
    auto rate44k = openPureGaplessSource(kPathPureGaplessB44k);
    auto mono = openPureGaplessSource(kPathPureGaplessMono);
    auto floaty = openPureGaplessSource(kPathPureGaplessFloat);
    if (ref == nullptr || match == nullptr || rate44k == nullptr || mono == nullptr ||
        floaty == nullptr)
    {
        cleanup();
        logFail(kName, "could not open one or more compatibility fixtures");
        return;
    }

    std::string err;
    if (!sameRateGaplessCompatible(*ref, *match))
    {
        err = "matching same-format pair reported INCOMPATIBLE";
    }
    else if (sameRateGaplessCompatible(*ref, *rate44k))
    {
        err = "rate mismatch (48k vs 44.1k) reported compatible";
    }
    else if (sameRateGaplessCompatible(*ref, *mono))
    {
        err = "channel mismatch (stereo vs mono) reported compatible";
    }
    else if (sameRateGaplessCompatible(*ref, *floaty))
    {
        err = "float/bits mismatch (int16 vs float32) reported compatible";
    }
    cleanup();

    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// Pure-gapless 4: playlist end with NO armed next. setCurrent(A) with nothing armed; draining to
// A's true EOF must set ended() and never crash (the seam exchange observes a null armed slot).
static auto testPureGaplessPlaylistEndNoNext() -> void
{
    static const char* const kName = "PureGapless_PlaylistEndNoNext";

    const std::vector<int16_t> seg = makeGaplessRampSegment(0U, kGaplessSegmentFrames);
    if (!writeWav16(kPathPureGaplessA, seg, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the single-track fixture");
        return;
    }

    auto srcA = openPureGaplessSource(kPathPureGaplessA);
    if (srcA == nullptr)
    {
        std::remove(kPathPureGaplessA);
        logFail(kName, "open() failed");
        return;
    }

    GaplessSource gapless;
    gapless.setCurrent(std::move(srcA)); // nothing armed

    std::vector<float> out(
        static_cast<std::size_t>(kGaplessSegmentFrames + kPureGaplessPullChunk) * kB2bChannels2,
        0.0F);
    const uint32_t total = drainGapless(gapless, out, kGaplessSegmentFrames, kB2bChannels2);
    const bool ended = pollGaplessEnded(gapless);
    const uint64_t transitions = gapless.transitionCount();
    std::remove(kPathPureGaplessA);

    if (total != kGaplessSegmentFrames)
    {
        std::ostringstream oss;
        oss << "drained " << total << " of " << kGaplessSegmentFrames << " frames";
        logFail(kName, oss.str());
        return;
    }
    if (transitions != 0U)
    {
        std::ostringstream oss;
        oss << "transitionCount " << transitions << ", expected 0 (no armed next)";
        logFail(kName, oss.str());
        return;
    }
    if (!ended)
    {
        logFail(kName, "ended() not true at playlist end");
        return;
    }
    logPass(kName);
}
