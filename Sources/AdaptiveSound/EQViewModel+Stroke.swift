import EQEditKit
import Foundation

// MARK: - EQViewModel: the graph drag (strokes) and the keyboard / VoiceOver step

/// The views never write the curve: the graph reports pointer samples and key presses here, and the
/// kit's `EQStroke` shapes them (review F12). A stroke sends every sample at once (the engine
/// coalesces) and persists and logs only at its end (review F18).
extension EQViewModel {
    /// A drag in progress: the shape it draws, every sample computed from the mouse-down curve, and
    /// the whole state from before it, which Esc restores.
    struct ActiveStroke {
        var shape: EQStroke
        let before: EQState
    }

    /// Mouse-down on the graph: a stroke starts from what plays now.
    func beginStroke() {
        stroke = ActiveStroke(shape: EQStroke(start: current.resolvedCurve), before: current)
    }

    /// A pointer sample at `band` and `db`: the stroke's curve plays at once. Ignored once the
    /// stroke has ended or been cancelled, until the next mouse-down begins another.
    func updateStroke(band: Int, db: Float) {
        guard var active = stroke else { return }
        let curve = active.shape.curve(movingTo: band, db: db)
        stroke = active
        edit(to: curve)
    }

    /// Mouse-up: the stroke stays — persisted and logged once.
    func endStroke() {
        guard let active = stroke else { return }
        stroke = nil
        guard current != active.before else { return }
        persist()
        let points = current.points
        logUX("EQ stroke → '\(presetLabel)' max=\(String(format: "%+.1f", points.max() ?? 0))dB "
            + "min=\(String(format: "%+.1f", points.min() ?? 0))dB")
    }

    /// Esc during a drag: the state from before the stroke plays again, exactly. Returns whether
    /// there was a stroke to cancel; if not, Esc is the caller's to pass on.
    func cancelStroke() -> Bool {
        guard let active = stroke else { return false }
        stroke = nil
        setCurrent(active.before)
        logUX("EQ stroke cancelled")
        return true
    }

    /// The keyboard / VoiceOver step: `band` moves by `db`, persisted per step (a key press has no
    /// stroke end).
    func nudge(band: Int, by db: Float) {
        var curve = current.resolvedCurve
        guard curve.points.indices.contains(band) else { return }
        curve.setPoint(band, to: curve.points[band] + db)
        edit(to: curve)
        persist()
    }
}
