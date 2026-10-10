import SwiftUI

// MARK: - EQ graph card title (Sprint EQ, EQ3)

/// The preset playing, large, with its state: "Warm · Edited", or "Warm · Off" while the EQ is off. One
/// line, middle-truncated, the full name in the tooltip. The "Used on <output>" pin sits under it
/// (`EQGraphHeading`).
struct EQGraphTitle: View {
    @Environment(EQViewModel.self) private var eq

    var body: some View {
        let name = eq.current.preset.displayName
        HStack(spacing: 8) {
            Text(name)
                .font(DesignSystem.Font.displayTitle)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)
            if !eq.isOn {
                EQStateChip(kind: .off)
            } else if eq.isEdited {
                EQStateChip(kind: .edited)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
