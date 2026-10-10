// EQSession: drags (strokes), key steps and Tone (Sprint EQ; review F12/F18, break-it A1/A2/S0/D1, the
// review fix round). The views never write the curve: the graph and the Tone sliders report pointer
// samples and key presses, and the kit's `EQStroke` shapes the graph's.
//
// A STROKE is one drag — on the graph, or on a Tone slider. It sends every sample at once (the engine
// coalesces) and is written and logged only at its end. Its rules:
// - a discrete edit ends it first (kept and written), so the edit applies to what plays and what is on
//   disk; the rest of that drag is ignored until the next mouse-down;
// - beginning a stroke ends one whose end never came (a drag the system cancelled), kept;
// - Esc puts back everything it changed — the curve AND the Bring back offer its first sample cleared;
// - an output switch ends it only when the slot changes (`+Slots`): a drag stays with its slot.

import Foundation

public extension EQSession {
    /// A drag in progress: the shape it draws, every sample computed from the mouse-down curve, and
    /// what Esc restores — the whole state from before it, and the Bring back offer then on show.
    internal struct Stroke: Sendable {
        var shape: EQStroke
        let before: EQState
        let bringBack: EQBringBack?
    }

    /// Whether a drag's stroke is live. It ends early when Esc cancels it or a discrete edit lands
    /// mid-drag; the graph then ignores the rest of that drag.
    var isStroking: Bool {
        stroke != nil
    }

    /// Mouse-down on the graph or a Tone slider: a stroke starts from what plays now. One still open —
    /// its mouse-up never came — is ended first, kept.
    mutating func beginStroke() -> EQOutcome {
        let ended = endStroke()
        stroke = Stroke(shape: EQStroke(start: current.resolvedCurve), before: current, bringBack: bringBack)
        return ended
    }

    /// A pointer sample on the graph at `band` and `db`: the stroke's curve plays at once. Ignored once
    /// the stroke has ended or been cancelled, until the next mouse-down begins another.
    mutating func updateStroke(band: Int, db: Float) -> EQOutcome {
        guard var active = stroke else { return .none }
        let curve = active.shape.curve(movingTo: band, db: db)
        stroke = active
        return edit(to: curve)
    }

    /// A Tone slider drag's pointer sample: `region` moves to `db` and plays at once. Ignored once the
    /// stroke has ended, like a graph sample.
    mutating func updateStroke(tone region: EQToneRegion, to db: Float) -> EQOutcome {
        guard stroke != nil else { return .none }
        return edit(to: toned(region, to: db))
    }

    /// Mouse-up: the stroke stays — written and logged once, when it changed anything. A discrete edit
    /// calls this first too, so an Esc never restores a state that isn't on disk.
    mutating func endStroke() -> EQOutcome {
        guard let active = stroke else { return .none }
        stroke = nil
        guard current != active.before else { return .none }
        let points = current.points
        return EQOutcome(.saveSlots, log: "EQ stroke → '\(presetLabel)' "
            + "max=\(String(format: "%+.1f", points.max() ?? 0))dB min=\(String(format: "%+.1f", points.min() ?? 0))dB")
    }

    /// Esc during a drag: the state from before the stroke plays again, exactly, and the Bring back
    /// offer it cleared is offered again. `.none` when there was no stroke: Esc is the caller's to pass on.
    mutating func cancelStroke() -> EQOutcome {
        guard let active = stroke else { return .none }
        stroke = nil
        let restored = setCurrent(active.before)
        bringBack = active.bringBack
        return restored.then(EQOutcome([], log: "EQ stroke cancelled"))
    }

    /// The keyboard / VoiceOver step on the graph: `band` moves by `db`, written per step (a key press
    /// has no stroke end).
    mutating func nudge(band: Int, by db: Float) -> EQOutcome {
        let ended = endStroke() // a discrete edit ends a drag first
        var curve = current.resolvedCurve
        guard curve.points.indices.contains(band) else { return ended }
        curve.setPoint(band, to: curve.points[band] + db)
        return ended.then(edit(to: curve)).then(EQOutcome(.saveSlots))
    }

    // MARK: - Tone (decision 24: a macro over the points, not a second mode)

    /// Tone `region`'s level in what plays now (dB).
    func tone(of region: EQToneRegion) -> Float {
        current.resolvedCurve.tone(of: region)
    }

    /// Whether any Tone is set: Reset Tone is enabled, and the folded card says what is set.
    var hasTone: Bool {
        current.resolvedCurve.hasTone
    }

    /// How many points that `region` reaches are held at the ±12 ceiling (`EQCurve.heldPointCount`).
    func heldPointCount(in region: EQToneRegion) -> Int {
        current.resolvedCurve.heldPointCount(in: region)
    }

    /// The graph's Tone readout for `region`: "Tone · Presence 2–6 kHz +3.0 dB · 3 points held".
    func toneReadout(for region: EQToneRegion) -> String {
        EQToneText.readout(region, db: tone(of: region), heldPoints: heldPointCount(in: region))
    }

    /// One Tone step — a key press or a VoiceOver swipe on a slider: `region` moves to `db` (held in
    /// ±12), written at once, like `nudge`.
    mutating func setTone(_ region: EQToneRegion, to db: Float) -> EQOutcome {
        let ended = endStroke() // a discrete edit ends a drag first
        return ended.then(edit(to: toned(region, to: db))).then(EQOutcome(.saveSlots))
    }

    /// Reset Tone: every region back to 0, so the points return to the user's own layer. With no Tone
    /// set there is nothing to do (the button is disabled then).
    mutating func resetTone() -> EQOutcome {
        let ended = endStroke() // a discrete edit ends a drag first
        guard current.resolvedCurve.hasTone else { return ended }
        var curve = current.resolvedCurve
        curve.resetTone()
        let reset = ended.then(edit(to: curve))
        return reset.then(EQOutcome(.saveSlots, log: "EQ tone reset → '\(presetLabel)'"))
    }

    /// What plays now with Tone `region` at `db`.
    private func toned(_ region: EQToneRegion, to db: Float) -> EQCurve {
        var curve = current.resolvedCurve
        curve.setTone(region, to: db)
        return curve
    }
}
