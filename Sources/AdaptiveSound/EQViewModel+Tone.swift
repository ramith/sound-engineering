import EQEditKit
import Foundation

// MARK: - EQViewModel: Tone (decision 24)

/// Tone is a macro over the 31 points, not a second mode: each of the five regions moves the points
/// it reaches by its weight there (`EQCurve.setTone`), and the one 31-band engine plays the result.
/// A Tone move is an edit like any other — it goes through `edit(to:)`, so it turns the EQ on, clears
/// a Bring back offer, releases a held Compare and is sent from the one dispatch. Choosing a preset
/// puts Tone back to 0 (`EQState(choosing:)`), and Save bakes it into the saved points
/// (`EQState.saved(as:)`).
///
/// A slider drag is a stroke, like a drag on the graph: `beginStroke()` at mouse-down, a Tone sample
/// per pointer move here, `endStroke()` at mouse-up — sent at once, persisted and logged once. A step
/// and Reset Tone are discrete edits: they end a drag first (+Stroke).
extension EQViewModel {
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

    /// The graph's Tone readout while a Tone slider is in use (`highlightedRegion`): "Tone · Presence
    /// 2–6 kHz +3.0 dB · 3 points held". `nil` otherwise.
    var toneReadout: String? {
        highlightedRegion.map { region in
            EQToneText.readout(region, db: tone(of: region), heldPoints: heldPointCount(in: region))
        }
    }

    /// One Tone step — a key press or a VoiceOver swipe on a slider: `region` moves to `db` (held in
    /// ±12), sent and persisted at once (a step has no stroke end), like `nudge`.
    func setTone(_ region: EQToneRegion, to db: Float) {
        endStroke() // a discrete edit ends a drag first (+Stroke)
        edit(to: toned(region, to: db))
        persist()
    }

    /// A Tone slider drag's pointer sample: `region` moves to `db` and plays at once. Ignored once the
    /// stroke has ended — Esc, a discrete edit, or an output switch that changes the slot — so the
    /// rest of that drag never lands on top of it.
    func updateStroke(tone region: EQToneRegion, to db: Float) {
        guard stroke != nil else { return }
        edit(to: toned(region, to: db))
    }

    /// Reset Tone: every region back to 0, so the points return to the user's own layer. Persisted and
    /// logged; with no Tone set there is nothing to do (the button is disabled then).
    func resetTone() {
        endStroke() // a discrete edit ends a drag first (+Stroke)
        guard hasTone else { return }
        var curve = current.resolvedCurve
        curve.resetTone()
        edit(to: curve)
        persist()
        logUX("EQ tone reset → '\(presetLabel)'")
    }

    /// What plays now with Tone `region` at `db`.
    private func toned(_ region: EQToneRegion, to db: Float) -> EQCurve {
        var curve = current.resolvedCurve
        curve.setTone(region, to: db)
        return curve
    }
}
