import Foundation

// MARK: - AudioEngineBridge Crossfeed control plane

/// File-scope type alias matching the C-ABI signature for `publishCrossfeed`.
/// Captured here so it can be called unambiguously from the `AudioEngineBridge`
/// extension without the compiler preferring the Swift instance method of the same name.
private typealias CPublishCrossfeed = (UnsafeMutableRawPointer?, UInt32, Float, UInt32) -> Void
private let cPublishCrossfeed: CPublishCrossfeed = publishCrossfeed

extension AudioEngineBridge {
    /// Publish a new crossfeed state to the live DSP AU (QW1 §3).
    ///
    /// Mirrors the `publishIntensity` pattern: borrows the AU handle passUnretained and calls
    /// the `publishCrossfeed` C-ABI. No-op when the AU is not yet instantiated.
    /// Must be called from a single control thread (the `@MainActor`).
    ///
    /// - Parameters:
    ///   - enabled: `true` activates the crossfeed stage; `false` passes audio through bit-exactly.
    ///   - strength: The `CrossfeedStrength` preset, which resolves to a (level, presetIndex) pair.
    func publishCrossfeed(enabled: Bool, strength: CrossfeedStrength) async {
        guard let handle = dspAudioUnitHandle else {
            logUX("[QW1] bridge.publishCrossfeed SKIP — no DSP AU handle "
                + "(enabled=\(enabled) strength=\(strength))")
            return
        }
        let enabledFlag: UInt32 = enabled ? 1 : 0
        logUX("[QW1] bridge.publishCrossfeed → C-ABI enabled=\(enabledFlag) "
            + "level=\(strength.dspLevel) preset=\(strength.presetIndex)")
        cPublishCrossfeed(handle, enabledFlag, strength.dspLevel, strength.presetIndex)
    }
}
