import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - EQ preset row (Sprint EQ, EQ3)

/// One preset in the EQ rail: its curve glyph, its name, and "edited" on the preset playing with edits —
/// the Library rail's `NavRow` at the EQ's denser 28 pt. A plain button (a `List`'s selection would race
/// it); choosing plays at once. Its context menu and VoiceOver actions are `EQPresetRowMenu`'s: bring
/// back set-aside edits, the "Use on <output>" pin, and Rename / Delete on My Presets.
struct EQPresetRow: View {
    let preset: EQPresetRef
    /// The 31 points the preset plays unedited, for its glyph.
    let glyph: [Float]
    let isCurrent: Bool
    /// The current preset plays with edits.
    let isEdited: Bool
    let isKeyboardCursor: Bool
    let menu: EQPresetRowMenu
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            NavRow(label: preset.displayName, active: isCurrent, isKeyboardCursor: isKeyboardCursor,
                   rowHeight: CGFloat(EQScreenLayout.presetRowHeight), truncation: .middle) {
                EQCurveGlyph(points: glyph)
            } trailing: {
                if isCurrent, isEdited {
                    Text("edited")
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.accentText)
                }
            }
        }
        .buttonStyle(.plain)
        // Not a Tab stop of its own: the LIST is the one stop, its arrows walk the rows (as the Songs
        // rows and browse tiles). Clicks, the menu and VoiceOver are unaffected.
        .focusable(false)
        .help(preset.displayName)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .contextMenu { menu }
        .accessibilityActions { menu.voiceOverActions }
    }
}
