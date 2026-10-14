// PlaybackQueueKit — where a seek lands (council C-25 / DUP-1, R1.1-A).
//
// A seek to the end used to be refused: the scrubber sends `seconds == duration`, which truncated to
// exactly the file's length, and the Enhanced seek treated "the end" as an error — after moving the
// playhead and abandoning the resampler's chain, so the music stopped and never moved on (KI-PB-18).
// A NaN trapped. And the Enhanced paths that start somewhere disagreed: the start clamped, the seeks
// ignored, one rounded, the others truncated. This is the one rule they all use now.

/// Where a seek — or any start at a place — lands in a track. ONE rule for every path:
///
/// 1. A place must be a number: NaN and ±∞ are not places (`place(_:duration:)` returns `nil`).
/// 2. Nothing comes before the top: a negative place is 0.
/// 3. Seconds become a frame by rounding to the nearest frame — as Pure's decoder does (`llround`).
/// 4. A frame at or past the last one is `.end`: the track ends now, through the end-of-track path,
///    exactly as if it had played out. Never an error.
public enum SeekTarget: Equatable, Sendable {
    /// Play from this frame, inside the track (`0 ..< length`).
    case frame(Int64)
    /// At or past the track's last frame: the track ends now.
    case end

    /// The frame `seconds` lands on in a track of `length` frames at `sampleRate`. `nil` when the
    /// request is not a place, or the track has no usable rate.
    public init?(seconds: Double, length: Int64, sampleRate: Double) {
        guard let place = Self.place(seconds), sampleRate.isFinite, sampleRate > 0 else { return nil }
        let frame = (place * sampleRate).rounded()
        // Compared as a Double first, so a huge (but finite) place is the end, never an overflow.
        self = frame >= Double(length) ? .end : .frame(Int64(frame))
    }

    /// The rule in seconds, for a caller that has no frames: `nil` when `seconds` is not a place;
    /// otherwise no earlier than 0, and no later than `duration` when one is known (finite, > 0 —
    /// the view model's 0 means "not known yet").
    public static func place(_ seconds: Double, duration: Double? = nil) -> Double? {
        guard seconds.isFinite else { return nil }
        let place = max(seconds, 0)
        guard let duration, duration.isFinite, duration > 0 else { return place }
        return min(place, duration)
    }
}
