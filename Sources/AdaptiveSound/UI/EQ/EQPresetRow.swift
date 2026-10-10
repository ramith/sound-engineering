import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - EQ preset row (Sprint EQ, EQ3)

/// One preset in the EQ rail: its curve glyph, its name, and "edited" on the preset playing with edits —
/// the Library rail's `NavRow` at the EQ's denser 28 pt. A plain button (a `List`'s selection would race
/// it); choosing plays at once. While edits are set aside, its context menu and a VoiceOver action
/// bring them back, with no time limit (WCAG 2.2.1).
struct EQPresetRow: View {
    let preset: EQPresetRef
    /// The 31 points the preset plays unedited, for its glyph.
    let glyph: [Float]
    let isCurrent: Bool
    /// The current preset plays with edits.
    let isEdited: Bool
    let isKeyboardCursor: Bool
    /// The preset whose edits a switch set aside, while they can be brought back.
    let setAside: String?
    let choose: () -> Void
    let bringBack: () -> Void

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
        .help(preset.displayName)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .contextMenu { bringBackItem }
        .accessibilityActions { bringBackItem }
    }

    @ViewBuilder private var bringBackItem: some View {
        if let setAside {
            Button("Bring Back Edits to \(setAside)", action: bringBack)
        }
    }
}
