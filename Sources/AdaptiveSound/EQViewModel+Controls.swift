import EQEditKit
import Foundation

// MARK: - EQViewModel: the screen's switch, Reset, and the presets list (EQ3)

/// The V1b screen's verbs over the one dispatch (`setCurrent`): every one sends what plays at once and
/// persists once, and — like every change — releases a held Compare.
extension EQViewModel {
    /// The Equalizer switch. Off is a true bypass at matched loudness (decision 26); the curve is kept.
    var isOn: Bool {
        get { current.isOn }
        set {
            guard newValue != current.isOn else { return }
            endStroke() // a discrete edit ends a drag first (+Stroke)
            var state = current
            state.isOn = newValue
            setCurrent(state)
            persist()
            logUX("EQ \(newValue ? "on" : "off")")
        }
    }

    /// Whether a drag's stroke is live. It ends early when Esc cancels it or a discrete edit (a preset
    /// choice, Save, a key step) lands mid-drag; the graph then ignores the rest of that drag.
    var isStroking: Bool {
        stroke != nil
    }

    /// Reset (the header): the same as re-choosing the preset — its points, Tone at 0, on. It offers
    /// nothing back: resetting is the user's explicit intent.
    func reset() {
        choose(current.preset)
    }

    /// The band at `band` back to its preset's value (⌫ on the graph, VoiceOver's "Reset band"); the
    /// rest of the curve and Tone stay. An edit like any other: persisted per press.
    func resetBand(_ band: Int) {
        endStroke() // a discrete edit ends a drag first (+Stroke)
        guard let preset = EQState(choosing: current.preset, myPresets: customPresets)?.points,
              preset.indices.contains(band) else { return }
        var curve = current.resolvedCurve
        curve.setPoint(band, to: preset[band])
        edit(to: curve)
        persist()
    }

    /// The user's saved presets by name, in the list's order (as Finder sorts names).
    var myPresetNames: [String] {
        customPresets.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The presets list top to bottom: the built-ins, then My Presets — the rows the arrow keys walk.
    var presetRows: [EQPresetRef] {
        EQBuiltInPreset.allCases.map(EQPresetRef.builtIn) + myPresetNames.map(EQPresetRef.mine)
    }

    /// The 31 points `preset` plays unedited (its row's curve glyph); flat for a My Preset that is gone.
    func glyphPoints(for preset: EQPresetRef) -> [Float] {
        EQState(choosing: preset, myPresets: customPresets)?.points ?? EQCurve.flat.points
    }
}
