// PeakHoldTracker — the pure resolver of the analyzer's peak-cap motion tokens over FED
// time (S10.7 PR 3, design §6/§7 R2). Kit-charter placement: `holdSeconds`/`decayPerSecond`
// are motion-design data, and this struct resolves them exactly like `resolveSurface`
// resolves color tokens. TIME-FED by design (the S10.6 monotonic-while-playing lesson):
// no wall clock anywhere — no feed, no decay, so "caps freeze on pause" is structural.

import Foundation

// MARK: - Config (motion-design tokens)

public struct PeakHoldConfig: Sendable, Equatable {
    /// How long a latched cap holds before decaying (design §6 PR 3: ~600 ms).
    public let holdSeconds: Double
    /// Decay slope once the hold expires, in full-scale units per second.
    public let decayPerSecond: Double

    public init(holdSeconds: Double = 0.6, decayPerSecond: Double = 1.25) {
        self.holdSeconds = holdSeconds
        self.decayPerSecond = decayPerSecond
    }
}

// MARK: - Tracker

public struct PeakHoldTracker: Sendable, Equatable {
    public let config: PeakHoldConfig
    public private(set) var caps: [Double]
    /// Per-band hold time remaining (seconds of FED time) before decay begins.
    private var holdRemaining: [Double]

    public init(bandCount: Int, config: PeakHoldConfig = PeakHoldConfig()) {
        self.config = config
        caps = Array(repeating: 0, count: max(0, bandCount))
        holdRemaining = Array(repeating: 0, count: max(0, bandCount))
    }

    /// Advance by `elapsed` fed-seconds with the current live bars.
    /// Semantics (PH-01..09): a rising bar re-latches its cap AND restarts the hold; past the
    /// hold, the cap decays linearly; a cap never falls below the live bar or 0; hostile
    /// input clamps (negative elapsed → 0; non-finite / out-of-range bars → [0, 1]); a
    /// band-count change resizes and resets the new layout.
    public mutating func update(bars: [Double], elapsed: Double) {
        if bars.count != caps.count {
            caps = Array(repeating: 0, count: bars.count)
            holdRemaining = Array(repeating: 0, count: bars.count)
        }
        let step = max(0, elapsed.isFinite ? elapsed : 0)
        for index in bars.indices {
            let raw = bars[index]
            let bar = raw.isFinite ? min(max(raw, 0), 1) : 0
            if bar >= caps[index] {
                caps[index] = bar
                holdRemaining[index] = config.holdSeconds
                continue
            }
            // Consume the hold first; any spill past it decays the cap linearly.
            let spill = step - holdRemaining[index]
            if spill <= 0 {
                holdRemaining[index] -= step
            } else {
                holdRemaining[index] = 0
                caps[index] = max(bar, caps[index] - config.decayPerSecond * spill)
            }
        }
    }

    /// Clear to the given live bars (track change / stop); empty means all-zero.
    public mutating func reset(to bars: [Double] = []) {
        for index in caps.indices {
            let bar = index < bars.count ? min(max(bars[index], 0), 1) : 0
            caps[index] = bar.isFinite ? bar : 0
            holdRemaining[index] = 0
        }
    }
}
