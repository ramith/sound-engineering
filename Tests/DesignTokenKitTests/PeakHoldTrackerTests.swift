// PH — PeakHoldTracker cases (design §7 R2). Derived expectations only: every number below
// is computed from the tracker's own config, never a pixel/magic literal. The tracker is
// time-FED, so pause semantics (PH-06) are structural, not timed.

import DesignTokenKit
import Testing

@Suite("PeakHoldTracker (PH)")
struct PeakHoldTrackerTests {
    private let config = PeakHoldConfig()

    private func tracker(_ bands: Int = 3) -> PeakHoldTracker {
        PeakHoldTracker(bandCount: bands, config: config)
    }

    @Test("PH-01: the cap always rides at or above the live bar, re-latching a rise instantly")
    func capNeverBelowBar() {
        var sut = tracker(1)
        sut.update(bars: [0.4], elapsed: 0.05)
        #expect(sut.caps[0] == 0.4)
        sut.update(bars: [0.9], elapsed: 0.05)
        #expect(sut.caps[0] == 0.9, "a rising bar re-latches immediately")
    }

    @Test("PH-02: a latched cap holds its value for exactly holdSeconds of fed time")
    func holdWindow() {
        var sut = tracker(1)
        sut.update(bars: [0.8], elapsed: 0.05) // latch
        let justUnderHold = config.holdSeconds - 0.001
        sut.update(bars: [0.1], elapsed: justUnderHold)
        #expect(sut.caps[0] == 0.8, "unchanged at hold − ε")
    }

    @Test("PH-03: past the hold, the cap decays linearly at decayPerSecond")
    func linearDecay() {
        var sut = tracker(1)
        sut.update(bars: [0.8], elapsed: 0.05) // latch (hold restarts)
        let delta = 0.2
        sut.update(bars: [0.0], elapsed: config.holdSeconds + delta)
        let expected = 0.8 - config.decayPerSecond * delta
        #expect(abs(sut.caps[0] - expected) < 1e-12,
                "cap \(sut.caps[0]) vs derived \(expected)")
    }

    @Test("PH-04: decay floors at the live bar and never goes negative")
    func decayFloors() {
        var sut = tracker(2)
        sut.update(bars: [0.8, 0.8], elapsed: 0.05)
        sut.update(bars: [0.5, 0.0], elapsed: config.holdSeconds + 10) // decay far past both
        #expect(sut.caps[0] == 0.5, "floors at the live bar")
        #expect(sut.caps[1] == 0.0, "floors at zero")
    }

    @Test("PH-05: a new higher bar re-latches AND restarts the hold window")
    func relatchRestartsHold() {
        var sut = tracker(1)
        sut.update(bars: [0.5], elapsed: 0.05)
        sut.update(bars: [0.2], elapsed: config.holdSeconds / 2) // half the hold consumed
        sut.update(bars: [0.7], elapsed: 0.05) // re-latch
        sut.update(bars: [0.1], elapsed: config.holdSeconds - 0.001) // fresh, full hold
        #expect(sut.caps[0] == 0.7, "the hold restarted at re-latch")
    }

    @Test("PH-06: no feed, no decay — pause is structural")
    func pauseIsStructural() {
        var sut = tracker(1)
        sut.update(bars: [0.8], elapsed: 0.05)
        let frozen = sut.caps
        // Nothing calls update. However much wall time "passes", the caps are identical.
        #expect(sut.caps == frozen)
    }

    @Test("PH-07: reset clears to the live bars (or zero)")
    func reset() {
        var sut = tracker(2)
        sut.update(bars: [0.8, 0.6], elapsed: 0.05)
        sut.reset(to: [0.3])
        #expect(sut.caps == [0.3, 0.0], "reset takes given bars, zero-fills the rest")
    }

    @Test("PH-08: a band-count change resizes and resets the new layout without crashing")
    func bandCountChange() {
        var sut = tracker(2)
        sut.update(bars: [0.8, 0.6], elapsed: 0.05)
        sut.update(bars: [0.1, 0.2, 0.3, 0.4], elapsed: 0.05)
        #expect(sut.caps == [0.1, 0.2, 0.3, 0.4], "resized layout starts from the live bars")
    }

    @Test("PH-09: hostile input clamps — negative elapsed, NaN/∞/out-of-range bars")
    func hostileInput() {
        var sut = tracker(4)
        sut.update(bars: [0.5, 0.5, 0.5, 0.5], elapsed: 0.05)
        sut.update(bars: [Double.nan, .infinity, -3, 7], elapsed: -5)
        for cap in sut.caps {
            #expect(cap.isFinite && cap >= 0 && cap <= 1, "cap \(cap) escaped [0, 1]")
        }
        // Negative elapsed must not decay (clamped to 0): band 3 latched to 1.0 (clamped 7).
        #expect(sut.caps[3] == 1.0)
    }
}
