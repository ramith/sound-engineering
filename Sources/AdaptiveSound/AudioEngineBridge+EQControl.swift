@preconcurrency import AVFoundation
import EQEditKit
import Foundation

// MARK: - AudioEngineBridge EQ control plane

extension AudioEngineBridge {
    /// Publish the EQ (`AudioPlaybackEngine.publishEQ`) to the live AU through today's C-ABI,
    /// which designs the biquad cascade from 31 band gains. Until the C-ABI takes the contract
    /// over, this is the engine's trust boundary: a wrong count or a non-finite point is rejected
    /// (the last good EQ keeps playing), each point is held in ±12 dB (`EQCurve(points:)`, the
    /// definition of a point), and Off plays the flat curve. Today's engine still plays the summed-dB
    /// shape of Sprint 4's `EQSafetyClamp` (moved here from the EQ view model, which now sends the
    /// points as drawn) until EQ2's cut-over retires it. No-op if the AU isn't live.
    func publishEQ(points: [Float], isOn: Bool) {
        // Strong borrow under the leaf lock (`dspAudioUnitRef`): keeps the AU alive across the
        // C-ABI call even if a concurrent teardown nils the field (S3 finding F1). The bus read,
        // handle derivation, and C-ABI all run OFF the lock, on the retained local `unit`.
        guard let unit = dspAudioUnitRef else {
            logUX("[QW1] bridge.publishEQ SKIP — no DSP AU handle (count=\(points.count))")
            return
        }
        guard points.count == EQBands.count, points.allSatisfy(\.isFinite) else {
            logUX("[QW1] bridge.publishEQ REJECT — \(points.count) point(s), need \(EQBands.count) finite")
            return
        }
        let gainsDb = EQSafetyClamp.clamped((isOn ? EQCurve(points: points) : .flat).points)
        logUX("[QW1] bridge.publishEQ → C-ABI on=\(isOn) count=\(gainsDb.count)")
        let sampleRate = Self.eqDesignSampleRate(of: unit)
        let handle = Unmanaged.passUnretained(unit.auAudioUnit).toOpaque()
        _ = gainsDb.withUnsafeBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return publishEQBandGains(handle, base, UInt32(buffer.count), sampleRate)
        }
    }

    /// The rate the EQ is designed at (`AudioPlaybackEngine.eqSampleRate`): the live AU's, else the
    /// graph format's — what the next publish would design at, so the graph's played curve matches.
    func eqSampleRate() -> Double {
        dspAudioUnitRef.map(Self.eqDesignSampleRate(of:)) ?? Self.graphSampleRate
    }

    /// The graph format's rate: the EQ's design rate whenever the AU's own can't be read.
    private static let graphSampleRate = 48000.0

    /// The rate the EQ is designed at: the AU's negotiated output-bus rate, falling back to the
    /// 48 kHz graph format when the bus isn't queryable. (`AUAudioUnitBusArray` is not a Swift
    /// collection, hence the count check.)
    private static func eqDesignSampleRate(of unit: AVAudioUnit) -> Double {
        let busArray = unit.auAudioUnit.outputBusses
        return busArray.count >= 1 ? busArray[0].format.sampleRate : graphSampleRate
    }
}
