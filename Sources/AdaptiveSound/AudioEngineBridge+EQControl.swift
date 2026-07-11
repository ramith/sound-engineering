@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge EQ control plane

extension AudioEngineBridge {
    /// Compute + publish the EQ biquad cascade for `gainsDb` (31 bands) to the live AU.
    /// The coefficient design sample rate is read from the AU output bus (the negotiated rate),
    /// falling back to the 48 kHz graph format. No-op if the AU isn't live.
    func publishEQGains(_ gainsDb: [Float]) {
        // Strong borrow under the leaf lock (`dspAudioUnitRef`): keeps the AU alive across the
        // C-ABI call even if a concurrent teardown nils the field (S3 finding F1). The bus read,
        // handle derivation, and C-ABI all run OFF the lock, on the retained local `unit`.
        guard let unit = dspAudioUnitRef else {
            logUX("[QW1] bridge.publishEQGains SKIP — no DSP AU handle (count=\(gainsDb.count))")
            return
        }
        guard gainsDb.count == 31 else { return }
        logUX("[QW1] bridge.publishEQGains → C-ABI count=\(gainsDb.count)")
        // Design coefficients for the AU's negotiated output rate (graph is 48 kHz; fall back
        // to that if the bus isn't queryable). AUAudioUnitBusArray is not a Swift collection.
        var sampleRate = 48000.0
        let busArray = unit.auAudioUnit.outputBusses
        if busArray.count >= 1 {
            sampleRate = busArray[0].format.sampleRate
        }
        let handle = Unmanaged.passUnretained(unit.auAudioUnit).toOpaque()
        _ = gainsDb.withUnsafeBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return publishEQBandGains(handle, base, UInt32(gainsDb.count), sampleRate)
        }
    }
}
