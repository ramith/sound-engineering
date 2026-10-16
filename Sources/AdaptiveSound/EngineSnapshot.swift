import EQEditKit
import PlaybackQueueKit

// MARK: - EngineSnapshot

/// Everything the main thread reads of the engine's state, in one copy (S10.8 G, the disconnect
/// freeze): the transport (as the engine's clock last sampled it), the signal path, the loudness and
/// the EQ's design rate. `AudioPlaybackEngine.snapshot()` assembles it from values the engine has
/// already published — a snapshot channel, a value under a lock held only for the copy, and atomics
/// — so reading it never waits on AVFAudio, the CoreAudio HAL or an engine queue, whatever they are
/// doing. The 20 Hz transport tick reads one per tick.
struct EngineSnapshot: Equatable {
    /// The playhead, the seam count and the end of the queue.
    var transport = TransportSnapshot()
    /// The active path, its rate and depth, the device volume on Pure, and `interrupted` (playback
    /// paused for a lost device — published before the engine does anything that can wait).
    var signalPath = SignalPathInfo()
    /// The playback tap's BS.1770-5 loudness.
    var loudness: LoudnessSnapshot = .unmeasured
    /// The rate the EQ is designed at: the live AU's, else the graph's 48 kHz.
    var eqDesignRate: Double = 48000
    /// The output devices whose own volume Pure turned down and has not yet put back
    /// (`MasterGainOnPure.allLoans`): what the view model keeps with the listener's settings.
    var pureVolumeLoans: [PureVolumeLoan] = []
}
