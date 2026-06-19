// GaplessContractTests.inc
//
// Pure-path gapless CONFORMANCE — S6 Tier-3 sub-step 3d (design doc §4 "GaplessController"). These
// tests pin the BEHAVIORAL CONTRACT of GaplessSource (the Pure-path implementation behind the
// AudioPlaybackEngine protocol: setNextTrack / trackTransitionCount / playbackEnded). They are
// ADDITIVE — no production DSP change — so the golden master is unaffected.
//
// #included into Tests/DSPKernelNullTest.cpp AFTER PureGaplessTests.inc: it reuses PureGapless's
// openPureGaplessSource / drainGapless / pollGaplessEnded helpers and the same fixture paths, plus
// GaplessTests' makeGaplessRampSegment / kGapless* constants and FileDecodeTests' writeWav16 /
// kB2b* constants.
//
// The invariants pinned (mapping to design doc §4 + the C-ABI in PureModeBridge.h):
//
//   1. Transition count increments by EXACTLY ONE per seam crossed. One armed track → count 1;
//      a second armed track in sequence → count 2. (transitionCount() / trackTransitionCount.)
//   2. clearNext() cancels the on-deck track: arming then clearing before the seam means NO
//      transition occurs and the active source plays to its own end → ended() true, count 0.
//      (clearNext() / setNextTrack(nil).)
//   3. End-of-queue signals: the active track exhausted with nothing armed → ended() true.
//      (ended() / playbackEnded.)
//   4. Position RE-ZEROES at the seam (per-track Pure semantic, PureModeBridge.h:137-140): the
//      rendered-frame counter for the NEW track restarts near 0 immediately after the seam — an
//      explicit assertion, not a comment.
//   5. Poll-reaps-source side effect (PureModeBridge.h:156-159 / GaplessSource::reapRetired): a
//      seam parks the retired source; the poll plane (pureModeEnginePollTrackAdvance → reapRetired)
//      MUST join+free it off-RT or decode threads leak. Asserted via the observability hooks
//      hasPendingReap() / reapCount() so a future change that stops polling can't silently leak.
//
// Tests: GaplessContract_TransitionCountPerSeam, GaplessContract_ClearCancelsOnDeck,
//        GaplessContract_EndOfQueueSignals, GaplessContract_PositionRezeroesAtSeam,
//        GaplessContract_PollReapsRetiredSource.

namespace
{
    // Distinct fixture paths so the contract tests never collide with PureGaplessTests' fixtures.
    constexpr const char* kPathContractA = ADAPTIVESOUND_TEST_DATA_DIR "/gapless_contract_A.wav";
    constexpr const char* kPathContractB = ADAPTIVESOUND_TEST_DATA_DIR "/gapless_contract_B.wav";
    constexpr const char* kPathContractC = ADAPTIVESOUND_TEST_DATA_DIR "/gapless_contract_C.wav";

    // Write one single-segment ramp fixture (kGaplessSegmentFrames stereo int16 @ 48 kHz). Returns
    // true on success. The ramp content is irrelevant to the contract tests (they assert counts /
    // position / reap, not sample values), but a real decodable file is required.
    auto writeContractSegment(const char* path) -> bool
    {
        const std::vector<int16_t> seg = makeGaplessRampSegment(0U, kGaplessSegmentFrames);
        return writeWav16(path, seg, kB2bChannels2, kB2bRate48k);
    }
} // namespace

// Contract 1: transitionCount increments by EXACTLY ONE per seam crossed. Arm B behind A, drain to
// A's true EOF and across the seam → count 1; reap, arm C behind B, drain to B's true EOF and across
// that seam → count 2. (GaplessSource is two-slot, so the second arm requires reaping the retired
// slot first — which mirrors the live poll-plane contract.)
static auto testGaplessContractTransitionCountPerSeam() -> void
{
    static const char* const kName = "GaplessContract_TransitionCountPerSeam";

    const bool wroteA = writeContractSegment(kPathContractA);
    const bool wroteB = writeContractSegment(kPathContractB);
    const bool wroteC = writeContractSegment(kPathContractC);
    const auto cleanup = []
    {
        std::remove(kPathContractA);
        std::remove(kPathContractB);
        std::remove(kPathContractC);
    };
    if (!wroteA || !wroteB || !wroteC)
    {
        cleanup();
        logFail(kName, "could not write A/B/C fixtures");
        return;
    }

    auto srcA = openPureGaplessSource(kPathContractA);
    auto srcB = openPureGaplessSource(kPathContractB);
    auto srcC = openPureGaplessSource(kPathContractC);
    if (srcA == nullptr || srcB == nullptr || srcC == nullptr)
    {
        cleanup();
        logFail(kName, "could not open A/B/C FileDecodeSources");
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

    // Drain across the A->B seam. Each track is kGaplessSegmentFrames; after the first seam we have
    // produced kGaplessTotalFrames of real audio (A then B) but B is NOT yet exhausted — stop the
    // drain at the seam so we can arm C and cross a second seam. drainGapless keeps pulling until
    // ended(), so instead pull manually here.
    std::vector<float> buf(static_cast<std::size_t>(kPureGaplessPullChunk) * kB2bChannels2, 0.0F);
    const auto pumpToTransition = [&](uint64_t targetCount) -> bool
    {
        for (int spin = 0; spin < kPureGaplessMaxSpins; ++spin)
        {
            if (gapless.transitionCount() >= targetCount)
            {
                return true;
            }
            const uint32_t produced =
                gapless.pullFloat(buf.data(), kPureGaplessPullChunk, kB2bChannels2);
            if (produced == 0U)
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(kPureGaplessSpinNapMs));
            }
        }
        return gapless.transitionCount() >= targetCount;
    };

    if (!pumpToTransition(1U))
    {
        cleanup();
        logFail(kName, "first seam (A->B) never observed");
        return;
    }
    if (gapless.transitionCount() != 1U)
    {
        std::ostringstream oss;
        oss << "after first seam transitionCount " << gapless.transitionCount() << ", expected 1";
        cleanup();
        logFail(kName, oss.str());
        return;
    }

    // Reap A (frees the retired slot so C can be armed) — the live poll plane does this.
    gapless.reapRetired();
    if (!gapless.armNext(std::move(srcC)))
    {
        cleanup();
        logFail(kName, "armNext(C) refused after reaping A's slot");
        return;
    }

    if (!pumpToTransition(2U))
    {
        cleanup();
        logFail(kName, "second seam (B->C) never observed");
        return;
    }
    const uint64_t finalCount = gapless.transitionCount();
    gapless.reapRetired();
    cleanup();

    if (finalCount != 2U)
    {
        std::ostringstream oss;
        oss << "after second seam transitionCount " << finalCount << ", expected exactly 2";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Contract 2: clearNext() cancels the on-deck track. Arm B, then clearNext() BEFORE A reaches its
// true EOF → no seam fires (transitionCount stays 0), A plays to its own end, and ended() becomes
// true (the engine never advances to the cleared track). This is the Pure-path setNextTrack(nil).
static auto testGaplessContractClearCancelsOnDeck() -> void
{
    static const char* const kName = "GaplessContract_ClearCancelsOnDeck";

    const bool wroteA = writeContractSegment(kPathContractA);
    const bool wroteB = writeContractSegment(kPathContractB);
    const auto cleanup = []
    {
        std::remove(kPathContractA);
        std::remove(kPathContractB);
    };
    if (!wroteA || !wroteB)
    {
        cleanup();
        logFail(kName, "could not write A/B fixtures");
        return;
    }

    auto srcA = openPureGaplessSource(kPathContractA);
    auto srcB = openPureGaplessSource(kPathContractB);
    if (srcA == nullptr || srcB == nullptr)
    {
        cleanup();
        logFail(kName, "could not open A/B FileDecodeSources");
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

    // Clear the on-deck track before A is anywhere near its EOF (no pulls yet → A is full).
    gapless.clearNext();

    // Now drain A to its true EOF. With nothing armed the seam exchange observes a null slot, so no
    // transition fires and ended() must become true (A plays to its own end; B is never reached).
    std::vector<float> out(
        static_cast<std::size_t>(kGaplessSegmentFrames + kPureGaplessPullChunk) * kB2bChannels2,
        0.0F);
    const uint32_t total = drainGapless(gapless, out, kGaplessSegmentFrames, kB2bChannels2);
    const bool ended = pollGaplessEnded(gapless);
    const uint64_t transitions = gapless.transitionCount();
    gapless.reapRetired(); // no-op (nothing parked) — just to mirror the poll plane
    cleanup();

    if (transitions != 0U)
    {
        std::ostringstream oss;
        oss << "transitionCount " << transitions << ", expected 0 (cleared on-deck must not advance)";
        logFail(kName, oss.str());
        return;
    }
    if (total != kGaplessSegmentFrames)
    {
        std::ostringstream oss;
        oss << "active drained " << total << " of " << kGaplessSegmentFrames
            << " frames (A should play to its own end)";
        logFail(kName, oss.str());
        return;
    }
    if (!ended)
    {
        logFail(kName, "ended() not true after the active track exhausts with the on-deck cleared");
        return;
    }
    logPass(kName);
}

// Contract 3: end-of-queue signals. The active track exhausted with NOTHING armed → ended() true.
// (PureGapless_PlaylistEndNoNext also touches this; this is the explicit contract-suite assertion,
// kept distinct so the conformance suite stands alone.)
static auto testGaplessContractEndOfQueueSignals() -> void
{
    static const char* const kName = "GaplessContract_EndOfQueueSignals";

    if (!writeContractSegment(kPathContractA))
    {
        std::remove(kPathContractA);
        logFail(kName, "could not write the single-track fixture");
        return;
    }

    auto srcA = openPureGaplessSource(kPathContractA);
    if (srcA == nullptr)
    {
        std::remove(kPathContractA);
        logFail(kName, "open() failed");
        return;
    }

    GaplessSource gapless;
    gapless.setCurrent(std::move(srcA)); // nothing armed

    // ended() must be false while the track still has audio (before any pull discovers true EOF).
    if (gapless.ended())
    {
        std::remove(kPathContractA);
        logFail(kName, "ended() true before the active track is exhausted");
        return;
    }

    std::vector<float> out(
        static_cast<std::size_t>(kGaplessSegmentFrames + kPureGaplessPullChunk) * kB2bChannels2,
        0.0F);
    const uint32_t total = drainGapless(gapless, out, kGaplessSegmentFrames, kB2bChannels2);
    const bool ended = pollGaplessEnded(gapless);
    std::remove(kPathContractA);

    if (total != kGaplessSegmentFrames)
    {
        std::ostringstream oss;
        oss << "drained " << total << " of " << kGaplessSegmentFrames << " frames";
        logFail(kName, oss.str());
        return;
    }
    if (!ended)
    {
        logFail(kName, "ended() not true at end-of-queue (active exhausted, nothing armed)");
        return;
    }
    logPass(kName);
}

// Contract 4: position RE-ZEROES at the seam (per-track Pure semantic, PureModeBridge.h:137-140).
// renderedFramesCurrent() counts frames the ACTIVE track has rendered since IT became active. Just
// before the seam it has counted ~all of A (≈ kGaplessSegmentFrames). Immediately after the seam
// the active track is B, so the counter must restart near 0 — explicitly asserted here.
static auto testGaplessContractPositionRezeroesAtSeam() -> void
{
    static const char* const kName = "GaplessContract_PositionRezeroesAtSeam";

    const bool wroteA = writeContractSegment(kPathContractA);
    const bool wroteB = writeContractSegment(kPathContractB);
    const auto cleanup = []
    {
        std::remove(kPathContractA);
        std::remove(kPathContractB);
    };
    if (!wroteA || !wroteB)
    {
        cleanup();
        logFail(kName, "could not write A/B fixtures");
        return;
    }

    auto srcA = openPureGaplessSource(kPathContractA);
    auto srcB = openPureGaplessSource(kPathContractB);
    if (srcA == nullptr || srcB == nullptr)
    {
        cleanup();
        logFail(kName, "could not open A/B FileDecodeSources");
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

    // Pull chunk-by-chunk, capturing the active-track rendered-frame counter on the LAST chunk
    // before the seam and the FIRST chunk after it. The seam fires inside the pull that crosses
    // A's true EOF, so the chunk that bumps transitionCount() to 1 is the seam chunk: at that point
    // the active track is B and its counter holds only the B-head frames pulled this callback.
    std::vector<float> buf(static_cast<std::size_t>(kPureGaplessPullChunk) * kB2bChannels2, 0.0F);
    uint64_t preSeamRendered = 0U;  // active-track frames just before the seam crossing
    uint64_t postSeamRendered = 0U; // active-track frames right after the seam crossing
    bool sawSeam = false;
    for (int spin = 0; spin < kPureGaplessMaxSpins && !sawSeam; ++spin)
    {
        const uint64_t before = gapless.renderedFramesCurrent();
        const uint32_t produced =
            gapless.pullFloat(buf.data(), kPureGaplessPullChunk, kB2bChannels2);
        if (gapless.transitionCount() >= 1U)
        {
            preSeamRendered = before; // A's counter just before it swapped out
            postSeamRendered = gapless.renderedFramesCurrent(); // B's freshly-zeroed counter
            sawSeam = true;
            break;
        }
        if (produced == 0U)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(kPureGaplessSpinNapMs));
        }
    }
    gapless.reapRetired();
    cleanup();

    if (!sawSeam)
    {
        logFail(kName, "seam never observed (transitionCount stayed 0)");
        return;
    }
    // Before the seam, A had rendered nearly its whole length (not a fresh counter).
    if (preSeamRendered < kGaplessSegmentFrames - kPureGaplessPullChunk)
    {
        std::ostringstream oss;
        oss << "pre-seam rendered " << preSeamRendered << " frames, expected near "
            << kGaplessSegmentFrames << " (counter was not tracking A)";
        logFail(kName, oss.str());
        return;
    }
    // After the seam the counter must have RE-ZEROED for B: it holds only the B-head frames pulled
    // in the seam callback (< one pull chunk), NOT A's accumulated count.
    if (postSeamRendered > kPureGaplessPullChunk)
    {
        std::ostringstream oss;
        oss << "post-seam rendered " << postSeamRendered << " frames, expected <= "
            << kPureGaplessPullChunk << " (position did NOT re-zero at the seam — it carried A's "
            << "count, breaking the per-track Pure semantic)";
        logFail(kName, oss.str());
        return;
    }
    std::ostringstream info;
    info << "  [info] " << kName << ": preSeam=" << preSeamRendered
         << " postSeam=" << postSeamRendered << " (re-zeroed at seam)\n";
    logInfo(info.str());
    logPass(kName);
}

// Contract 5: the poll-reaps-source side effect. A seam parks the old active in the retired slot;
// pureModeEnginePollTrackAdvance() → reapRetired() must join+free it off-RT or its decode thread
// leaks. Asserted via the observability hooks: right after the seam a reap is PENDING and the reap
// count is still 0; after one reapRetired() the pending flag clears and the reap count is exactly 1.
// A future change that stops polling would leave hasPendingReap() stuck true and reapCount() at 0
// even as transitionCount() climbs — this test is the guard against that silent decode-thread leak.
static auto testGaplessContractPollReapsRetiredSource() -> void
{
    static const char* const kName = "GaplessContract_PollReapsRetiredSource";

    const bool wroteA = writeContractSegment(kPathContractA);
    const bool wroteB = writeContractSegment(kPathContractB);
    const auto cleanup = []
    {
        std::remove(kPathContractA);
        std::remove(kPathContractB);
    };
    if (!wroteA || !wroteB)
    {
        cleanup();
        logFail(kName, "could not write A/B fixtures");
        return;
    }

    auto srcA = openPureGaplessSource(kPathContractA);
    auto srcB = openPureGaplessSource(kPathContractB);
    if (srcA == nullptr || srcB == nullptr)
    {
        cleanup();
        logFail(kName, "could not open A/B FileDecodeSources");
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

    // Fresh session: nothing parked, nothing reaped.
    if (gapless.hasPendingReap() || gapless.reapCount() != 0U)
    {
        cleanup();
        logFail(kName, "fresh session reports a pending/completed reap");
        return;
    }

    // Drain across the A->B seam WITHOUT reaping, so the retired slot stays parked.
    std::vector<float> buf(static_cast<std::size_t>(kPureGaplessPullChunk) * kB2bChannels2, 0.0F);
    bool sawSeam = false;
    for (int spin = 0; spin < kPureGaplessMaxSpins && !sawSeam; ++spin)
    {
        const uint32_t produced =
            gapless.pullFloat(buf.data(), kPureGaplessPullChunk, kB2bChannels2);
        if (gapless.transitionCount() >= 1U)
        {
            sawSeam = true;
            break;
        }
        if (produced == 0U)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(kPureGaplessSpinNapMs));
        }
    }
    if (!sawSeam)
    {
        cleanup();
        logFail(kName, "seam never observed (transitionCount stayed 0)");
        return;
    }

    // Post-seam, pre-poll: the retired source is PARKED (reap pending) and has NOT been freed.
    if (!gapless.hasPendingReap())
    {
        cleanup();
        logFail(kName, "no pending reap after the seam (retired source was not parked — RT joined?)");
        return;
    }
    if (gapless.reapCount() != 0U)
    {
        std::ostringstream oss;
        oss << "reapCount " << gapless.reapCount() << " before any poll, expected 0";
        cleanup();
        logFail(kName, oss.str());
        return;
    }

    // The poll plane reaps it (pureModeEnginePollTrackAdvance does exactly this off-RT).
    gapless.reapRetired();

    if (gapless.hasPendingReap())
    {
        cleanup();
        logFail(kName, "reap still pending after reapRetired() (retired source was not freed)");
        return;
    }
    if (gapless.reapCount() != 1U)
    {
        std::ostringstream oss;
        oss << "reapCount " << gapless.reapCount() << " after one poll, expected exactly 1 "
            << "(poll-reaps-source contract broken → decode threads would leak)";
        cleanup();
        logFail(kName, oss.str());
        return;
    }

    // A second poll with nothing parked must NOT bump the count (reap is a no-op when idle).
    gapless.reapRetired();
    const uint64_t finalReaps = gapless.reapCount();
    cleanup();

    if (finalReaps != 1U)
    {
        std::ostringstream oss;
        oss << "reapCount " << finalReaps << " after an idle poll, expected 1 (idle reap must be a no-op)";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}
