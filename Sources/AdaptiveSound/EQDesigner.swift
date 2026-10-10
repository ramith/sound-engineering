import EQEditKit
import Foundation

// MARK: - EQ designer (the graph's played curve, from EQ1a's C-ABI)

/// EQ1a's 31-band graphic-EQ designer (`EQDesignBridge.h`) for one Swift owner: it designs the
/// cascade the engine runs for a set of points and reads back what that cascade PLAYS, so the graph
/// draws the real response, never a Swift copy of the fitter.
///
/// One owner, one designer: the C-ABI's rule (a designer keeps per-rate tables between calls and is
/// not thread-safe), so it is never shared. Deliberately not `Sendable` — its owner, the main-actor
/// EQ view model, is its one thread. The designer itself allocates nothing per call and takes no
/// locks; the handle is created here and destroyed with this object.
final class EQDesigner {
    /// The C designer; `nil` only if its allocation failed, when every design reports nothing.
    private let handle: OpaquePointer?

    init() {
        handle = asEqDesignerCreate()
    }

    deinit {
        asEqDesignerDestroy(handle)
    }

    /// What the engine plays for `points` (31, dB) at `sampleRate`: the response at the band centres
    /// and on the graph's grid (`EQPlayed.frequencies`). `nil` when the designer rejects the input
    /// (a wrong count, a non-finite point, a rate outside 44–768 kHz) — the C-ABI writes nothing then.
    func played(points: [Float], sampleRate: Double) -> EQPlayed? {
        guard let handle, points.count == EQBands.count else { return nil }
        var centreDb = [Float](repeating: 0, count: EQBands.count)
        var responseDb = [Float](repeating: 0, count: EQPlayed.frequencies.count)
        let designed = points.withUnsafeBufferPointer { pointsDb in
            EQPlayed.frequencies.withUnsafeBufferPointer { responseHz in
                centreDb.withUnsafeMutableBufferPointer { centre in
                    responseDb.withUnsafeMutableBufferPointer { response in
                        var output = AsEqDesignOutput(
                            centreDb: centre.baseAddress, responseHz: responseHz.baseAddress,
                            responseDb: response.baseAddress, responseCount: UInt32(response.count),
                            filterGainDb: nil, svfK: nil, svfM1: nil
                        )
                        return asEqDesign(handle, pointsDb.baseAddress, UInt32(pointsDb.count), sampleRate, &output)
                    }
                }
            }
        }
        return designed ? EQPlayed(centreDb: centreDb, responseDb: responseDb) : nil
    }
}
