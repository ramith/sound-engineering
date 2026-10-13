@preconcurrency import AVFoundation

// MARK: - Values the bridge swaps whole under `stateLock`

/// The effects AU as the graph holds it and as the control plane reaches it.
struct EffectsUnit {
    /// The node in the graph (attach, connect, tap, detach) — `engineQueue` only.
    let node: AVAudioUnit
    /// Its `AUAudioUnit` (our `AdaptiveSoundAU`), read once when the unit is set: every control-plane
    /// C-ABI call takes it (`withEffectsAU`).
    let au: AUAudioUnit
}

/// The taps' analysis objects. Each analyzer owns its FFT state and a lock-free double buffer the
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
