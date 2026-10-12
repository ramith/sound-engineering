// PlaybackQueueKit — what a seek (the footer scrubber, its keys, Control Center) does (S10.8 G).
//
// Pure, so the routing is unit-tested without the engine or the view model (`ResumePointTests`).

/// Where a seek goes, decided from the transport state.
public enum SeekRoute: Sendable {
    /// Playing: the engine seeks, and the playhead shows the target.
    case engine
    /// Paused: only the resume point moves. The engine is stopped and must schedule nothing — a
    /// segment queued on a stopped player stays there and plays ahead of the next song.
    case resumePoint
    /// Stopped (never started, Stop, or the queue ended): nothing is loaded to seek in.
    case ignore

    /// The route for a seek. `isPaused` (a resume point for the selected song) wins over `isPlaying`:
    /// Pause records the resume point at once, while `isPlaying` drops only when the engine has
    /// stopped — a scrub in between belongs to the pause.
    public static func route(isPlaying: Bool, isPaused: Bool) -> SeekRoute {
        if isPaused {
            return .resumePoint
        }
        return isPlaying ? .engine : .ignore
    }
}
