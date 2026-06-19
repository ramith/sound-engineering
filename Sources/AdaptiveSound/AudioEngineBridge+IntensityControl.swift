import Foundation

// MARK: - AudioEngineBridge Intensity control plane

/// File-scope alias so the C-ABI `publishIntensity(void*, float)` can be called
/// unambiguously from the `AudioEngineBridge` extension — the extension's own
/// `func publishIntensity(_:)` would otherwise shadow the free function.
private let cPublishIntensity: (UnsafeMutableRawPointer?, Float) -> Void = publishIntensity

extension AudioEngineBridge {
    /// Publish a new Reimagine intensity value (wet/dry blend, [0, 1]) to the live DSP AU.
    ///
    /// Mirrors the `publishEQGains` pattern: borrows the AU handle passUnretained and calls
    /// the `publishIntensity` C-ABI (S6 §1.5). No-op when the AU is not yet instantiated.
    /// Must be called from a single control thread (the `@MainActor`).
    func publishIntensity(_ intensity: Float) {
        guard let handle = dspAudioUnitHandle else { return }
        cPublishIntensity(handle, intensity)
    }
}
