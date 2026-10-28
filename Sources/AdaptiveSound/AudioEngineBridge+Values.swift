@preconcurrency import AVFoundation
import Synchronization

// MARK: - Values the bridge swaps whole under `stateLock`

/// One of the app's two custom AUs — the effects unit or the spatial unit — as the graph holds it and as
/// the control plane reaches it.
struct GraphUnit {
    /// The node in the graph (attach, connect, tap, detach) — `engineQueue` only.
    let node: AVAudioUnit
    /// Its `AUAudioUnit` (our `AdaptiveSoundAU` or `SpatialRendererAU`), read once when the unit is set:
    /// every control-plane C-ABI call takes it (`withEffectsAU`, `withSpatialAU`).
    let au: AUAudioUnit
}

/// The taps' analysis objects. Each analyzer owns its FFT state and a lock-free triple buffer the
/// main thread reads; the meter owns the C LufsMeter handle (the RT mixer tap captures its raw
/// handle at install and never the wrapper, so no ARC touches the audio thread).
struct TapAnalysis {
    /// The Now-Playing spectrum (mixer tap).
    var spectrum: SpectrumAnalyzer?
    /// The BS.1770-5 loudness meter (mixer tap). Dropped only after `removeSpectrumTap()`.
    var meter: LoudnessMeterHandle?
    /// One analyzer per channel, pre-DSP (player tap) — N-channel by construction.
    var before: [SpectrumAnalyzer] = []
    /// One analyzer per channel, post-DSP (effects-AU tap).
    var after: [SpectrumAnalyzer] = []
}

/// Whether Monitoring shows, so its per-channel analysers — two per channel — run (council C-52):
/// set from the main thread (`AudioPlaybackEngine.setMonitorAnalysis`), read by the before / after
/// tap blocks with one relaxed load per buffer. Off until Monitoring first appears.
final class MonitorAnalysisSwitch: Sendable {
    private let on = Atomic<Bool>(false)

    var isOn: Bool {
        on.load(ordering: .relaxed)
    }

    func set(_ isOn: Bool) {
        on.store(isOn, ordering: .relaxed)
    }
}
