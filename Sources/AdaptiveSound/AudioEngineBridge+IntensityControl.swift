import Foundation

// MARK: - AudioEngineBridge Intensity control plane

/// Caseless-enum namespace holding an alias for the C-ABI `publishIntensity(void*, float)`
/// so it can be called unambiguously from the `AudioEngineBridge` extension — the
/// extension's own `func publishIntensity(_:)` would otherwise shadow the free function.
/// A caseless enum is a `Sendable` static namespace (no shared mutable state); the stored
/// value is an immutable C-function pointer that is never mutated.
private enum CIntensityABI {
    static let publish: @Sendable (UnsafeMutableRawPointer?, Float) -> Void = publishIntensity
}

extension AudioEngineBridge {
    /// Publish a new Reimagine intensity value (wet/dry blend, [0, 1]) to the live DSP AU.
    ///
    /// Mirrors the `publishEQGains` pattern: borrows the AU handle passUnretained and calls
    /// the `publishIntensity` C-ABI (S6 §1.5). No-op when the AU is not yet instantiated.
    /// Must be called from a single control thread (the `@MainActor`).
    func publishIntensity(_ intensity: Float) {
        guard let handle = dspAudioUnitHandle else {
            logUX("[QW1] bridge.publishIntensity SKIP — no DSP AU handle (intensity=\(intensity))")
            return
        }
        logUX("[QW1] bridge.publishIntensity → C-ABI intensity=\(intensity)")
        CIntensityABI.publish(handle, intensity)
    }
}
