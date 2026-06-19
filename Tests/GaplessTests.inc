// GaplessTests.inc
//
// Gapless playback — DECODE LAYER (Stage 1). #included into Tests/DSPKernelNullTest.cpp after
// TestSupport.h and FileDecodeTests.inc (it reuses FileDecodeTests' writeWav16 / drainFrames /
// pollFinished / BackendGuard helpers and the kB2b* decode constants).
//
// These tests prove the EXISTING FileDecodeSource decode->concatenate contract that gapless relies
// on: decoding two adjacent files back-to-back must advance the signal by exactly one ramp step at
// the A->B seam, with no inserted silence, no dropped/duplicated frame, and no channel swap. They do
// NOT exercise the Pure-path GaplessSource or any C-ABI (that is Stage 2) — only FileDecodeSource.
//
// Design: every fixture is a RAMP THAT CONTINUES ACROSS THE A->B SEAM. Decode is bit-exact, so the
// recovered LEFT sample maps straight back to an absolute concatenated-frame index; any seam defect
// (silence/drop/dup/click) shows up as a wrong delta at the seam. The right channel is a fixed known
// offset from the left so a channel swap is caught too.
//
// Tests: Gapless_SeamFrameAccuracy, Gapless_TotalFrameCount_48kOnly,
//        Gapless_SampleRateMismatch_ProducesFrameCountForEach, Gapless_ShortFile_DrainCorrectly,
//        Gapless_OpenFailure_SecondSource.

namespace
{
    // Per-file frame count for the seam fixtures (A and B each).
    constexpr uint32_t kGaplessSegmentFrames = 2048U;
    // Total across the concatenated A->B pair.
    constexpr uint32_t kGaplessTotalFrames = kGaplessSegmentFrames * 2U; // 4096
    // Short-file test segment.
    constexpr uint32_t kGaplessShortFrames = 512U;

    // One ramp step == one 16-bit LSB. The left channel advances by exactly this per frame, so a
    // correct A->B seam advances by exactly kRampStep and any inserted/dropped/duplicated frame is
    // detectable as a wrong seam delta.
    constexpr float kRampStep = 1.0F / 32768.0F;
    // Fixed offset (in int16 LSBs) of the right channel above the left — catches channel swaps.
    // Max left value is 4095 (frame 4095), so right stays well within int16 range.
    constexpr int kGaplessRightOffset = 8192;

    // Fixture paths (unique per file; runtime-generated, git-ignored, removed after each test).
    constexpr const char* kPathGaplessA = ADAPTIVESOUND_TEST_DATA_DIR "/gapless_ramp_A.wav";
    constexpr const char* kPathGaplessB = ADAPTIVESOUND_TEST_DATA_DIR "/gapless_ramp_B.wav";
    constexpr const char* kPathGaplessB44k = ADAPTIVESOUND_TEST_DATA_DIR "/gapless_ramp_B_44k.wav";
    constexpr const char* kPathGaplessShort = ADAPTIVESOUND_TEST_DATA_DIR "/gapless_ramp_short.wav";

    // Expected LEFT float at absolute concatenated-frame index `absFrame` (A is 0..2047, B continues
    // 2048..4095). value = absFrame LSBs => float = absFrame / 32768.
    auto gaplessExpectedLeft(uint32_t absFrame) -> float
    {
        return static_cast<float>(static_cast<int16_t>(absFrame)) / static_cast<float>(kB2bI16Scale);
    }

    // Build the gapless ramp segment starting at absolute frame `startAbsFrame`:
    //   left  = startAbsFrame + localFrame                       (continues across the seam)
    //   right = left + kGaplessRightOffset                       (fixed offset; catches swaps)
    auto makeGaplessRampSegment(uint32_t startAbsFrame, uint32_t frameCount) -> std::vector<int16_t>
    {
        std::vector<int16_t> interleaved(static_cast<std::size_t>(frameCount) * kB2bChannels2);
        for (uint32_t local = 0U; local < frameCount; ++local)
        {
            const auto left = static_cast<int16_t>(startAbsFrame + local);
            const auto right = static_cast<int16_t>(static_cast<int>(left) + kGaplessRightOffset);
            interleaved[static_cast<std::size_t>(local) * kB2bChannels2] = left;
            interleaved[(static_cast<std::size_t>(local) * kB2bChannels2) + 1U] = right;
        }
        return interleaved;
    }

    // Fully drain one fixture via FileDecodeSource into per-channel left/right vectors (the source
    // produces interleaved float; pullFloat fills [L,R,L,R,...]). Returns "" on success and appends
    // the recovered channels to `left`/`right`; a non-empty string is a real failure.
    auto gaplessDrainSegment(const char* path,
                             uint32_t expectedFrames,
                             double expectedRate,
                             std::vector<float>& left,
                             std::vector<float>& right) -> std::string
    {
        FileDecodeSource src;
        if (!src.open(path))
        {
            src.close();
            return "open() failed";
        }
        if (std::abs(src.sampleRate() - expectedRate) > kB2bRateTol)
        {
            std::ostringstream oss;
            oss << "sampleRate() " << src.sampleRate() << " != " << expectedRate;
            src.close();
            return oss.str();
        }
        if (src.channels() != kB2bChannels2)
        {
            std::ostringstream oss;
            oss << "channels() " << src.channels() << " != 2";
            src.close();
            return oss.str();
        }

        std::vector<float> got(static_cast<std::size_t>(expectedFrames) * kB2bChannels2, 0.0F);
        const uint32_t total = drainFrames(src, got, expectedFrames, kB2bChannels2);
        const bool finished = pollFinished(src);
        src.close();

        if (total != expectedFrames)
        {
            std::ostringstream oss;
            oss << "drained " << total << " of " << expectedFrames << " frames";
            return oss.str();
        }
        if (!finished)
        {
            return "decoderFinished() not true within ~120 ms after full drain";
        }
        left.reserve(left.size() + expectedFrames);
        right.reserve(right.size() + expectedFrames);
        for (uint32_t frame = 0U; frame < expectedFrames; ++frame)
        {
            left.push_back(got[static_cast<std::size_t>(frame) * kB2bChannels2]);
            right.push_back(got[(static_cast<std::size_t>(frame) * kB2bChannels2) + 1U]);
        }
        return {};
    }

    // Write the A and B seam fixtures (continuous ramp; B continues exactly where A ends).
    // `rateB` lets the 44.1k variant share this writer. Returns "" on success.
    auto writeGaplessSeamPair(const char* pathA, const char* pathB, double rateB) -> std::string
    {
        const std::vector<int16_t> segA = makeGaplessRampSegment(0U, kGaplessSegmentFrames);
        const std::vector<int16_t> segB =
            makeGaplessRampSegment(kGaplessSegmentFrames, kGaplessSegmentFrames);
        if (!writeWav16(pathA, segA, kB2bChannels2, kB2bRate48k))
        {
            return "could not write segment A fixture";
        }
        if (!writeWav16(pathB, segB, kB2bChannels2, rateB))
        {
            std::remove(pathA);
            return "could not write segment B fixture";
        }
        return {};
    }
} // namespace

// Gapless 1: seam frame accuracy. Drain A and B fully, concatenate the left channels, and assert the
// ramp is continuous across the A->B seam: the last frame of A and first frame of B recover their
// exact ramp values, the seam delta is one ramp step (no click / inserted silence / drop / dup), and
// the right-channel offset is preserved across the seam (no channel swap).
static auto testGaplessSeamFrameAccuracy() -> void
{
    static const char* const kName = "Gapless_SeamFrameAccuracy";
    constexpr float kClickTol = 3.0F * kRampStep; // seam step must look like one ordinary ramp step

    const std::string writeErr = writeGaplessSeamPair(kPathGaplessA, kPathGaplessB, kB2bRate48k);
    if (!writeErr.empty())
    {
        logFail(kName, writeErr);
        return;
    }

    std::vector<float> left;
    std::vector<float> right;
    const std::string errA =
        gaplessDrainSegment(kPathGaplessA, kGaplessSegmentFrames, kB2bRate48k, left, right);
    if (!errA.empty())
    {
        std::remove(kPathGaplessA);
        std::remove(kPathGaplessB);
        logFail(kName, "A: " + errA);
        return;
    }
    const std::string errB =
        gaplessDrainSegment(kPathGaplessB, kGaplessSegmentFrames, kB2bRate48k, left, right);
    std::remove(kPathGaplessA);
    std::remove(kPathGaplessB);
    if (!errB.empty())
    {
        logFail(kName, "B: " + errB);
        return;
    }

    if (left.size() != kGaplessTotalFrames || right.size() != kGaplessTotalFrames)
    {
        std::ostringstream oss;
        oss << "concatenated " << left.size() << " frames, expected " << kGaplessTotalFrames;
        logFail(kName, oss.str());
        return;
    }

    const uint32_t lastA = kGaplessSegmentFrames - 1U; // 2047
    const uint32_t firstB = kGaplessSegmentFrames;     // 2048
    const float expectedAlast = gaplessExpectedLeft(lastA);
    const float expectedBfirst = gaplessExpectedLeft(firstB);

    if (std::abs(left[lastA] - expectedAlast) > kRampStep)
    {
        logFail(kName, mismatchMsg("seam A.last left", lastA, expectedAlast, left[lastA]));
        return;
    }
    if (std::abs(left[firstB] - expectedBfirst) > kRampStep)
    {
        logFail(kName, mismatchMsg("seam B.first left", firstB, expectedBfirst, left[firstB]));
        return;
    }

    // Click / inserted-silence / drop / dup detection: the seam step must be one ordinary ramp step.
    const float seamDelta = std::abs(left[firstB] - left[lastA]);
    if (seamDelta > kClickTol)
    {
        std::ostringstream oss;
        oss << "seam delta " << seamDelta << " exceeds " << kClickTol
            << " (click / inserted silence / dropped or duplicated frame at the A->B seam)";
        logFail(kName, oss.str());
        return;
    }

    // Channel-swap check: the fixed right-above-left offset must hold across the seam.
    const float expectedOffset = static_cast<float>(kGaplessRightOffset) / static_cast<float>(kB2bI16Scale);
    for (const uint32_t frame : {lastA, firstB})
    {
        const float offset = right[frame] - left[frame];
        if (std::abs(offset - expectedOffset) > kRampStep)
        {
            std::ostringstream oss;
            oss << "right-left offset at frame " << frame << " is " << offset << ", expected "
                << expectedOffset << " (channel swap?)";
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// Gapless 2: total frame count (48k only). drained(A) + drained(B) must equal exactly 4096 — no
// inserted or dropped frames anywhere in the concatenation.
static auto testGaplessTotalFrameCount48kOnly() -> void
{
    static const char* const kName = "Gapless_TotalFrameCount_48kOnly";

    const std::string writeErr = writeGaplessSeamPair(kPathGaplessA, kPathGaplessB, kB2bRate48k);
    if (!writeErr.empty())
    {
        logFail(kName, writeErr);
        return;
    }

    const auto drainCount = [](const char* path) -> uint32_t
    {
        FileDecodeSource src;
        if (!src.open(path))
        {
            src.close();
            return 0U;
        }
        std::vector<float> got(static_cast<std::size_t>(kGaplessSegmentFrames) * kB2bChannels2,
                               0.0F);
        const uint32_t total = drainFrames(src, got, kGaplessSegmentFrames, kB2bChannels2);
        src.close();
        return total;
    };

    const uint32_t drainedA = drainCount(kPathGaplessA);
    const uint32_t drainedB = drainCount(kPathGaplessB);
    std::remove(kPathGaplessA);
    std::remove(kPathGaplessB);

    const uint32_t combined = drainedA + drainedB;
    if (combined != kGaplessTotalFrames)
    {
        std::ostringstream oss;
        oss << "drained(A)=" << drainedA << " + drained(B)=" << drainedB << " = " << combined
            << ", expected " << kGaplessTotalFrames;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Gapless 3: sample-rate mismatch reports each rate and drains each fully. A @ 48000 and B_44k @
// 44100 each report their own rate and drain exactly 2048 frames (the decode layer does NOT splice
// across mismatched rates — that resampling is the gapless ENGINE's job in Stage 2).
static auto testGaplessSampleRateMismatchProducesFrameCountForEach() -> void
{
    static const char* const kName = "Gapless_SampleRateMismatch_ProducesFrameCountForEach";

    const std::string writeErr =
        writeGaplessSeamPair(kPathGaplessA, kPathGaplessB44k, kB2bRate44k);
    if (!writeErr.empty())
    {
        logFail(kName, writeErr);
        return;
    }

    std::vector<float> leftA;
    std::vector<float> rightA;
    const std::string errA =
        gaplessDrainSegment(kPathGaplessA, kGaplessSegmentFrames, kB2bRate48k, leftA, rightA);
    if (!errA.empty())
    {
        std::remove(kPathGaplessA);
        std::remove(kPathGaplessB44k);
        logFail(kName, "A @ 48k: " + errA);
        return;
    }

    std::vector<float> leftB;
    std::vector<float> rightB;
    const std::string errB =
        gaplessDrainSegment(kPathGaplessB44k, kGaplessSegmentFrames, kB2bRate44k, leftB, rightB);
    std::remove(kPathGaplessA);
    std::remove(kPathGaplessB44k);
    if (!errB.empty())
    {
        logFail(kName, "B @ 44.1k: " + errB);
        return;
    }

    if (leftA.size() != kGaplessSegmentFrames || leftB.size() != kGaplessSegmentFrames)
    {
        std::ostringstream oss;
        oss << "drained A=" << leftA.size() << " B=" << leftB.size() << " frames, expected "
            << kGaplessSegmentFrames << " each";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Gapless 4: short file drains correctly. A 512-frame fixture drains exactly 512 frames, then
// decoderFinished() becomes true — no crash, no hang, no truncation, no over-read.
static auto testGaplessShortFileDrainCorrectly() -> void
{
    static const char* const kName = "Gapless_ShortFile_DrainCorrectly";

    const std::vector<int16_t> seg = makeGaplessRampSegment(0U, kGaplessShortFrames);
    if (!writeWav16(kPathGaplessShort, seg, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the short-file fixture");
        return;
    }

    FileDecodeSource src;
    if (!src.open(kPathGaplessShort))
    {
        src.close();
        std::remove(kPathGaplessShort);
        logFail(kName, "open() failed");
        return;
    }

    std::vector<float> got(static_cast<std::size_t>(kGaplessShortFrames) * kB2bChannels2, 0.0F);
    const uint32_t total = drainFrames(src, got, kGaplessShortFrames, kB2bChannels2);
    const bool finished = pollFinished(src);
    src.close();
    std::remove(kPathGaplessShort);

    if (total != kGaplessShortFrames)
    {
        std::ostringstream oss;
        oss << "drained " << total << " of " << kGaplessShortFrames << " frames";
        logFail(kName, oss.str());
        return;
    }
    if (!finished)
    {
        logFail(kName, "decoderFinished() not true within ~120 ms after full drain");
        return;
    }
    logPass(kName);
}

// Gapless 5: open failure on the second source. open() on a non-existent path returns false and does
// not crash — gapless preloads the next track, so a missing/bad next file must fail gracefully.
static auto testGaplessOpenFailureSecondSource() -> void
{
    static const char* const kName = "Gapless_OpenFailure_SecondSource";

    // First source: a valid short fixture opens cleanly (models the currently-playing track).
    const std::vector<int16_t> seg = makeGaplessRampSegment(0U, kGaplessShortFrames);
    if (!writeWav16(kPathGaplessShort, seg, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the first-source fixture");
        return;
    }
    {
        FileDecodeSource first;
        const bool firstOpened = first.open(kPathGaplessShort);
        first.close();
        std::remove(kPathGaplessShort);
        if (!firstOpened)
        {
            logFail(kName, "first (valid) source open() failed");
            return;
        }
    }

    // Second source: the "next track" is missing -> open() must return false, no crash.
    {
        FileDecodeSource second;
        const bool secondOpened =
            second.open(ADAPTIVESOUND_TEST_DATA_DIR "/gapless_next_does_not_exist.wav");
        second.close();
        if (secondOpened)
        {
            logFail(kName, "open(missing next track) returned true");
            return;
        }
    }
    logPass(kName);
}
