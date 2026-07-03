@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge EQ control plane

extension AudioEngineBridge {
    /// Opaque pointer to the underlying `AUAudioUnit`, used by the C-ABI `publishTargetState` /
    /// `setAUParameter` bridge (the EQ coefficient publication path). `nil` until `initialize()`
    /// has instantiated the AU. Borrowed (passUnretained) — callers must not retain it past
    /// `shutdown()`; the `AVAudioUnit` owns the underlying instance.
    var dspAudioUnitHandle: UnsafeMutableRawPointer? {
        guard let unit = dspAudioUnit?.auAudioUnit else { return nil }
        return Unmanaged.passUnretained(unit).toOpaque()
    }

    /// Compute + publish the EQ biquad cascade for `gainsDb` (31 bands) to the live AU.
    /// The coefficient design sample rate is read from the AU output bus (the negotiated rate),
    /// falling back to the 48 kHz graph format. No-op if the AU isn't live.
    func publishEQGains(_ gainsDb: [Float]) {
        guard gainsDb.count == 31, let handle = dspAudioUnitHandle else {
            if dspAudioUnitHandle == nil {
                logUX("[QW1] bridge.publishEQGains SKIP — no DSP AU handle "
                    + "(count=\(gainsDb.count))")
            }
            return
        }
        logUX("[QW1] bridge.publishEQGains → C-ABI count=\(gainsDb.count)")
        // Design coefficients for the AU's negotiated output rate (graph is 48 kHz; fall back
        // to that if the bus isn't queryable). AUAudioUnitBusArray is not a Swift collection.
        var sampleRate = 48000.0
        if let busArray = dspAudioUnit?.auAudioUnit.outputBusses, busArray.count >= 1 {
            sampleRate = busArray[0].format.sampleRate
        }
        _ = gainsDb.withUnsafeBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return publishEQBandGains(handle, base, UInt32(gainsDb.count), sampleRate)
        }
    }
}
