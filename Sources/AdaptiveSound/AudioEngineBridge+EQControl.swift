import AudioDSP
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge EQ control plane

/// Caseless-enum namespace holding the EQ C-ABI, so the extension's own `publishEQ(points:isOn:)`
/// never shadows the free functions (the `CIntensityABI` pattern). Immutable C-function pointers.
private enum CEQABI {
    static let publish: @Sendable (UnsafeMutableRawPointer?, UnsafePointer<Float>?, UInt32, Bool, Bool) -> Bool =
        publishEQIntent
    static let designRate: @Sendable (UnsafeMutableRawPointer?) -> Double = eqDesignSampleRate
    static let crossfeed: @Sendable (UnsafeMutableRawPointer?) -> Bool = crossfeedEngaged
    static let transport: @Sendable (UnsafeMutableRawPointer?, UInt32) -> Void = publishOutputTransport
}

extension AudioEngineBridge {
    /// Publish the EQ (`AudioPlaybackEngine.publishEQ`) to the live AU: the 31 points as drawn,
    /// whether it is on, and whether Compare is held. The C-ABI is the trust boundary (a wrong count or a
    /// non-finite point is rejected and the last good EQ keeps playing; points clamp to ±12 dB), and the
    /// engine designs the curve itself at its own rate — what plays is what the graph reads back. Off
    /// plays the identity. No-op if the AU isn't live.
    func publishEQ(points: [Float], isOn: Bool, comparing: Bool) {
        // The borrow keeps the AU alive across the C-ABI call even if a concurrent teardown clears
        // the field (S3 finding F1), and the teardown waits it out (`withEffectsAU`).
        let accepted = withEffectsAU { handle in
            points.withUnsafeBufferPointer { buffer in
                CEQABI.publish(handle, buffer.baseAddress, UInt32(buffer.count), isOn, comparing)
            }
        }
        guard let accepted else {
            logUX("[QW1] bridge.publishEQ SKIP — no DSP AU handle (count=\(points.count))")
            return
        }
        if !accepted {
            logUX("[QW1] bridge.publishEQ REJECT — \(points.count) point(s); the last good EQ keeps playing")
        }
    }

    /// The rate the EQ is designed at (`EngineSnapshot.eqDesignRate`): the live AU's — the rate its
    /// Realizer designs at, the kernel's, an atomic — else the graph format's 48 kHz, so the graph's
    /// played curve is designed exactly as the engine plays it.
    func eqSampleRate() -> Double {
        let rate = withEffectsAU { CEQABI.designRate($0) } ?? 0
        return rate > 0 ? rate : Self.graphSampleRate
    }

    /// Whether the crossfeed played on the effects unit's last block (R1.1-B, S2): what the "XF" chip shows —
    /// never on a folded file or the bit-perfect path. One atomic load through the borrow; `nil` when the AU
    /// isn't live. Safe on the main thread (lane 2's `snapshot()` reads it).
    func crossfeedEngagedNow() -> Bool? {
        withEffectsAU { CEQABI.crossfeed($0) }
    }

    /// Tell the engine which kind of output it plays on (`AudioPlaybackEngine.publishOutputTransport`;
    /// founder decision 29): the view model's hand-over, as a value. It becomes the output state's transport
    /// (`levelingOutputTransport()`, M2), and the EQ-only path's limiter ceiling follows it. No-op on the AU if
    /// it isn't live.
    func publishOutputTransport(_ transportType: UInt32) {
        leveling.setOutputTransport(transportType)
        _ = withEffectsAU { CEQABI.transport($0, transportType) }
    }

    /// The graph format's rate: the EQ's design rate whenever the AU's own can't be read.
    private static let graphSampleRate = 48000.0
}
