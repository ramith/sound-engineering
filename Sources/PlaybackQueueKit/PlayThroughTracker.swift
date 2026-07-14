// PlayThroughTracker — the pure ≥60%-heard play-detection decision (S10.6 R1/FIX-1..3).
//
// Fed monotonic-time deltas (seconds) of ACTUAL playback and counts a play ONCE per play-through
// when the heard time reaches `min(60%·duration, 240s)`, subject to a ≥30s minimum-track floor
// (Last.fm-style). The caller (the AudioViewModel transport tick) advances its monotonic reference
// every tick but feeds a delta only while `isPlaying`, so pauses / stalls / seeks never mis-accrue.
// Pure + `Sendable` so it is unit-tested without a clock or an audio engine.

public struct PlayThroughTracker: Equatable, Sendable {
    /// Fraction of the track that must be heard to count (design D2).
    public static let thresholdFraction = 0.60
    /// Absolute cap so a very long track counts after a substantial listen, not 60% of an hour (D2).
    public static let capSeconds = 240.0
    /// Minimum track duration to be eligible at all — a Last.fm-style floor (FIX-1/R1): sub-30s
    /// clips / gapless fragments never count.
    public static let minTrackSeconds = 30.0
    /// Belt-and-braces clamp on a single accrual (FIX-3). A real UI-tick stall of a few seconds is
    /// genuine playtime and IS accrued in full; only a pathological single-tick jump beyond this is
    /// bounded (the suspend-stopping monotonic clock shouldn't produce one, but this caps the blast).
    public static let maxPlausibleDelta = 10.0

    public private(set) var heardSeconds: Double = 0
    public private(set) var didCount: Bool = false

    public init() {}

    /// Begin a NEW play-through (a fresh manual start, a gapless advance, or a repeat-one re-arm).
    public mutating func reset() {
        heardSeconds = 0
        didCount = false
    }

    /// The heard-time threshold for `duration`, or `nil` if the track is too short to ever count.
    public static func threshold(forDuration duration: Double) -> Double? {
        guard duration >= minTrackSeconds else { return nil }
        return min(thresholdFraction * duration, capSeconds)
    }

    /// Accrue one playback-time delta (seconds). Returns `true` EXACTLY on the accrual that first
    /// reaches the qualifying threshold, so the caller records the play then (and only then).
    public mutating func accrue(_ delta: Double, duration: Double) -> Bool {
        guard !didCount, delta > 0 else { return false }
        heardSeconds += min(delta, Self.maxPlausibleDelta)
        return fireIfQualified(duration: duration)
    }

    /// The track reached its natural end. Counts (once) only if it QUALIFIES by the same gate as
    /// the tick path — `duration ≥ 30s` AND `heardSeconds ≥ threshold` — so a scrub-to-end or a
    /// short / unresolved-duration (`duration == 0`) track does NOT count (FIX-1). Its real job is a
    /// genuine full listen whose threshold-crossing tick was missed at a gapless seam (there
    /// `heardSeconds ≈ duration`, so it qualifies).
    public mutating func naturalEnd(duration: Double) -> Bool {
        guard !didCount else { return false }
        return fireIfQualified(duration: duration)
    }

    private mutating func fireIfQualified(duration: Double) -> Bool {
        guard let threshold = Self.threshold(forDuration: duration), heardSeconds >= threshold else {
            return false
        }
        didCount = true
        return true
    }
}
