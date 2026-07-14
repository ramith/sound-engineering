import PlaybackQueueKit
import Testing

// MARK: - PlayThroughTracker — the ≥60%-heard play-detection decision core (S10.6 R1/FIX-1..3)

//
// Imports the shipped `PlaybackQueueKit.PlayThroughTracker` (not a mirror). Feeds monotonic
// playback-time deltas directly (the tracker is pure — the clock/seek/pause handling is the VM's
// job and is the one acknowledged manual seam), and asserts the full ≥60% edge matrix headlessly.

@Suite("PlaybackQueueKit — PlayThroughTracker ≥60%-heard rule")
struct PlayThroughTrackerTests {
    /// A 180s track: threshold = min(0.6·180, 240) = 108s.
    private let longTrack = 180.0

    @Test("PT-01: below threshold does not count")
    func belowThreshold() {
        var tracker = PlayThroughTracker()
        var fired = false
        for _ in 0 ..< 100 {
            fired = tracker.accrue(1.0, duration: longTrack) || fired
        } // 100s < 108
        #expect(!fired)
        #expect(!tracker.didCount)
    }

    @Test("PT-02: crossing the threshold counts exactly once, on the crossing accrual")
    func crossingCountsOnce() {
        var tracker = PlayThroughTracker()
        var fireCount = 0
        for _ in 0 ..< 120 where tracker.accrue(1.0, duration: longTrack) {
            fireCount += 1
        } // crosses at 108
        #expect(fireCount == 1)
        #expect(tracker.didCount)
    }

    @Test("PT-03: accruing past the threshold (to natural end) never double-counts")
    func pastThresholdNoDoubleCount() {
        var tracker = PlayThroughTracker()
        _ = tracker.accrue(108, duration: longTrack) // cross in one delta (clamped, see PT-09) …
        // … so accrue to threshold in small deltas instead, to isolate the double-count guard:
        var t2 = PlayThroughTracker()
        var fires = 0
        for _ in 0 ..< 180 where t2.accrue(1.0, duration: longTrack) {
            fires += 1
        }
        #expect(fires == 1) // fired at 108, never again through 180
        #expect(t2.naturalEnd(duration: longTrack) == false) // already counted → no-op
    }

    @Test("PT-04: reset re-arms a new play-through (repeat-one counts again)")
    func resetReArms() {
        var tracker = PlayThroughTracker()
        for _ in 0 ..< 120 {
            _ = tracker.accrue(1.0, duration: longTrack)
        }
        #expect(tracker.didCount)
        tracker.reset()
        #expect(!tracker.didCount && tracker.heardSeconds == 0)
        var refired = false
        for _ in 0 ..< 120 {
            refired = tracker.accrue(1.0, duration: longTrack) || refired
        }
        #expect(refired)
    }

    @Test("PT-05: a track under the 30s floor never counts, even played in full")
    func shortTrackFloor() {
        var tracker = PlayThroughTracker()
        var fired = false
        for _ in 0 ..< 25 {
            fired = tracker.accrue(1.0, duration: 25.0) || fired
        } // 25s track, fully heard
        #expect(!fired)
        #expect(tracker.naturalEnd(duration: 25.0) == false)
        #expect(PlayThroughTracker.threshold(forDuration: 25.0) == nil)
    }

    @Test("PT-06: the 30s boundary counts at 18s (0.6·30)")
    func thirtySecondBoundary() {
        #expect(PlayThroughTracker.threshold(forDuration: 30.0) == 18.0)
        var tracker = PlayThroughTracker()
        var fires = 0
        for _ in 0 ..< 30 where tracker.accrue(1.0, duration: 30.0) {
            fires += 1
        }
        #expect(fires == 1)
    }

    @Test("PT-07: a very long track counts at the 240s cap, not 60% of an hour")
    func longTrackCap() {
        let show = 104.0 * 60.0 // 6240s; 60% would be 3744s
        #expect(PlayThroughTracker.threshold(forDuration: show) == 240.0)
        var tracker = PlayThroughTracker()
        var fires = 0
        for _ in 0 ..< 240 where tracker.accrue(1.0, duration: show) {
            fires += 1
        } // crosses at 240
        #expect(fires == 1)
        #expect(tracker.heardSeconds >= 240)
    }

    @Test("PT-08: a stall's large real delta accrues (not rejected) up to the plausibility clamp")
    func stallAccrues() {
        var tracker = PlayThroughTracker()
        _ = tracker.accrue(100, duration: longTrack) // one big (stall-like) delta
        #expect(tracker.heardSeconds == PlayThroughTracker.maxPlausibleDelta) // clamped to 10s, not dropped
    }

    @Test("PT-09: a pathological single delta is clamped, not dropped")
    func pathologicalDeltaClamped() {
        var tracker = PlayThroughTracker()
        _ = tracker.accrue(10000, duration: longTrack)
        #expect(tracker.heardSeconds == PlayThroughTracker.maxPlausibleDelta)
        #expect(!tracker.didCount) // 10s << 108s threshold
    }

    @Test("PT-10: non-positive deltas (seek-back / no motion) never accrue")
    func nonPositiveDeltaIgnored() {
        var tracker = PlayThroughTracker()
        #expect(tracker.accrue(0, duration: longTrack) == false)
        #expect(tracker.accrue(-5, duration: longTrack) == false)
        #expect(tracker.heardSeconds == 0)
    }

    @Test("PT-11: duration 0 (unresolved) never accrues a count; naturalEnd also refuses")
    func unresolvedDuration() {
        var tracker = PlayThroughTracker()
        for _ in 0 ..< 300 {
            _ = tracker.accrue(1.0, duration: 0)
        } // duration not yet known
        #expect(!tracker.didCount)
        #expect(tracker.naturalEnd(duration: 0) == false)
    }

    @Test("PT-12: naturalEnd on a below-threshold play-through does not count (scrub-to-end)")
    func naturalEndBelowThreshold() {
        var tracker = PlayThroughTracker()
        _ = tracker.accrue(5, duration: longTrack) // heard ~5s (e.g. scrubbed to the end)
        #expect(tracker.naturalEnd(duration: longTrack) == false)
        #expect(!tracker.didCount)
    }
}
