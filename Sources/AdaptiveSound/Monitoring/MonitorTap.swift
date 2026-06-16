import Foundation

// MARK: - Monitor Tap Point

/// A tap point in the DSP signal path, used by the Monitoring tab to compare the signal
/// before and after processing (Sprint 5 M3). Per-channel: each tap point has one analyzer
/// per channel (N-channel — stereo today, up to 7.1).
enum MonitorTap {
    /// Pre-DSP: tapped on the player node, before the AdaptiveSound AU.
    case before
    /// Post-DSP: tapped on the main mixer, after the AdaptiveSound AU.
    case after
}
