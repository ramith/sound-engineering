import EQEditKit

// MARK: - EQ graph drag (Sprint EQ, EQ3)

/// A drag on the EQ graph as the view sees it: the band under the pointer and the level the pointer
/// asks for, unclamped. The view model's stroke holds the point in ±12 dB; past +12 the graph ghosts
/// what was asked (ui-plan §4.3).
struct EQGraphDrag: Equatable {
    let band: Int
    let requestedDb: Double

    /// The pointer asks for more than the EQ's +12 dB ceiling, which holds the point.
    var isPastCeiling: Bool {
        requestedDb > Double(EQBands.pointLimitDb)
    }
}
