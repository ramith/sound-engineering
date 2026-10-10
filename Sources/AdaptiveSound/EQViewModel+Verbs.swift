import EQEditKit
import Foundation

// MARK: - EQViewModel: the verbs and readings the screen uses

/// One line each over `EQSession`, where every rule lives: the view reads the session's state and
/// asks for a verb; `perform` carries out what the verb decides.
extension EQViewModel {
    // MARK: Readings

    /// Whether the current state differs from its preset (the "Edited" rule).
    var isEdited: Bool {
        session.isEdited
    }

    /// One line for the EQ as it plays: `presetLabel`, or "Off".
    var summary: String {
        session.summary
    }

    /// Compare is held (decision 28).
    var isComparing: Bool {
        session.isComparing
    }

    /// Edits a preset switch set aside, offered back until the next edit (decision 27).
    var bringBack: EQBringBack? {
        session.bringBack
    }

    /// Whether a drag's stroke is live; the graph ignores the rest of a drag once it ended early.
    var isStroking: Bool {
        session.isStroking
    }

    /// The presets list top to bottom: the built-ins, then My Presets.
    var presetRows: [EQPresetRef] {
        session.presetRows
    }

    /// The user's saved presets by name, in the list's order.
    var myPresetNames: [String] {
        session.myPresetNames
    }

    /// The 31 points `preset` plays unedited (its row's curve glyph).
    func glyphPoints(for preset: EQPresetRef) -> [Float] {
        session.glyphPoints(for: preset)
    }

    /// How the current output stands with the pins; `nil` with no output, or one that can't be pinned.
    var outputPin: EQOutputPin? {
        session.outputPin
    }

    /// Tone `region`'s level in what plays now (dB).
    func tone(of region: EQToneRegion) -> Float {
        session.tone(of: region)
    }

    /// Whether any Tone is set.
    var hasTone: Bool {
        session.hasTone
    }

    /// How many points `region` reaches are held at the ±12 ceiling.
    func heldPointCount(in region: EQToneRegion) -> Int {
        session.heldPointCount(in: region)
    }

    /// The graph's Tone readout while a Tone slider is in use (`highlightedRegion`); `nil` otherwise.
    var toneReadout: String? {
        highlightedRegion.map(session.toneReadout(for:))
    }

    /// What Save would save now: taken when the Save sheet opens (break-it C1).
    func saveSource() -> EQSaveSource {
        session.saveSource()
    }

    /// `typed` checked as a My Preset's name, for the sheet's inline copy.
    func nameCheck(_ typed: String, renaming: String? = nil) -> EQPresetName.Check {
        session.nameCheck(typed, renaming: renaming)
    }

    // MARK: Verbs

    /// The Equalizer switch. Off is a true bypass at matched loudness (decision 26); the curve is kept.
    var isOn: Bool {
        get { current.isOn }
        set { perform { $0.setOn(newValue) } }
    }

    func choose(_ preset: EQPresetRef) {
        perform { $0.choose(preset) }
    }

    func reset() {
        perform { $0.reset() }
    }

    func resetBand(_ band: Int) {
        perform { $0.resetBand(band) }
    }

    func beginStroke() {
        perform { $0.beginStroke() }
    }

    func updateStroke(band: Int, db: Float) {
        perform { $0.updateStroke(band: band, db: db) }
    }

    func updateStroke(tone region: EQToneRegion, to db: Float) {
        perform { $0.updateStroke(tone: region, to: db) }
    }

    func endStroke() {
        perform { $0.endStroke() }
    }

    /// Esc during a drag; whether there was one to cancel (if not, Esc is the caller's to pass on).
    func cancelStroke() -> Bool {
        !perform { $0.cancelStroke() }.isNone
    }

    func nudge(band: Int, by db: Float) {
        perform { $0.nudge(band: band, by: db) }
    }

    func setTone(_ region: EQToneRegion, to db: Float) {
        perform { $0.setTone(region, to: db) }
    }

    func resetTone() {
        perform { $0.resetTone() }
    }

    func beginCompare() {
        let audible = audible
        perform { $0.beginCompare(when: audible) }
    }

    func endCompare() {
        perform { $0.endCompare() }
    }

    func bringBackEdits() {
        perform { $0.bringBackEdits() }
    }

    func save(_ source: EQSaveSource, as typed: String) {
        perform { $0.save(source, as: typed) }
    }

    func renameMyPreset(_ name: String, to typed: String) {
        perform { $0.renameMyPreset(name, to: typed) }
    }

    func deleteMyPreset(_ name: String) {
        perform { $0.deleteMyPreset(name) }
    }

    func togglePin() {
        perform { $0.togglePin() }
    }
}
