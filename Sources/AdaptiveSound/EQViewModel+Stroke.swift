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

    /// Mouse-up: the stroke stays — persisted and logged once. A discrete edit (a preset choice,
    /// Save, a key step) calls this first too (break-it A1/A2/S0): it then applies to what plays and
    /// what is on disk — never to a stroke that would redraw over it — and the rest of that drag is
    /// ignored until the next mouse-down. So an Esc never restores a state that isn't on disk.
    func endStroke() {
        guard let active = stroke else { return }
        stroke = nil
        guard current != active.before else { return }
        persist()
        let points = current.points
        logUX("EQ stroke → '\(presetLabel)' max=\(String(format: "%+.1f", points.max() ?? 0))dB "
            + "min=\(String(format: "%+.1f", points.min() ?? 0))dB")
    }

    /// The output is moving to `key`. A drag stays with its slot: it ends (kept, persisted) only when
    /// the move changes the slot, and draws on across an output change that keeps it (break-it D1).
    func endStroke(beforeMovingTo key: EQOutputKey?) {
        guard store.isSlotChange(from: output, to: key) else { return }
        endStroke()
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
        endStroke()
        var curve = current.resolvedCurve
        guard curve.points.indices.contains(band) else { return }
        curve.setPoint(band, to: curve.points[band] + db)
        edit(to: curve)
        persist()
    }
}
