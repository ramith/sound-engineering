import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - Tone row (EQ3t — one region of the Tone card)

/// One Tone region on one line (UI plan §5.6, 29 pt): its name over its range on the graph's own axis
/// ("Presence" / "2–6 kHz"), a centre-zero ±12 dB slider, and its level — one format at every value,
/// "+3.0", "0.0", "-2.5" (`EQLevelText.number`; the column is too narrow for "+12.0 dB").
///
/// The slider never writes the curve: a drag is a stroke on the view model (`beginStroke()`, a Tone
/// sample per move, `endStroke()` — persisted and logged once), and a key or VoiceOver step is one
/// `setTone`, persisted at once. Every one is an edit, so it turns the EQ on.
///
/// VoiceOver hears one adjustable element per row, "Presence tone, 2 to 6 kilohertz", whose value
/// adds "limited" when the ceiling holds points the region reaches; the name, range and value
/// texts are hidden from it, since the slider says all three.
struct EQToneRow: View {
    let region: EQToneRegion
    /// The row the user is on (hovered, dragged or keyboard-focused): tinted, its name and level teal.
    let isHighlighted: Bool
    /// The card's focus: this row's slider holds key focus while it equals `region`.
    let focus: FocusState<EQToneRegion?>.Binding
    /// A drag on this row's slider began (`true`) or ended (`false`).
    let onDragChanged: (Bool) -> Void

    @Environment(EQViewModel.self) private var eq
    /// A drag is in progress: the binding sends its samples to the stroke, not as steps. Read from
    /// the binding's setter, which sees the State's current value (never a stale copy).
    @State private var isDragging = false

    /// A key press or a VoiceOver swipe moves Tone half a decibel, like a point on the graph.
    private static let step: Float = 0.5
    private static let limit = EQBands.toneLimitDb

    var body: some View {
        let level = eq.tone(of: region)
        HStack(spacing: CGFloat(EQScreenLayout.toneRowGap)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(region.name)
                    .font(DesignSystem.Font.caption.weight(isHighlighted ? .semibold : .regular))
                    .foregroundStyle(isHighlighted ? DesignSystem.Color.accentText : DesignSystem.Color.label)
                Text(region.span)
                    .font(DesignSystem.Font.monoMicro)
                    .foregroundStyle(DesignSystem.Color.labelTertiary(onSelectedRow: isHighlighted))
            }
            .lineLimit(1)
            .frame(width: CGFloat(EQScreenLayout.toneNameWidth), alignment: .leading)
            .accessibilityHidden(true)

            CarvedSlider(
                value: levelBinding,
                range: -Self.limit ... Self.limit,
                step: Self.step,
                origin: 0,
                stepsWithVerticalArrows: true,
                usesAppFocusRing: true,
                accessibilityLabel: "\(region.name) tone, \(region.spokenSpan)",
                accessibilityValueText: EQToneText.spokenValue(level, isLimited: eq.heldPointCount(in: region) > 0),
                onEditingChanged: dragChanged
            )
            .focused(focus, equals: region)

            Text(EQLevelText.number(level))
                .font(DesignSystem.Font.monoMicro)
                .foregroundStyle(isHighlighted ? DesignSystem.Color.accentText : DesignSystem.Color.labelSecondary)
                .lineLimit(1)
                .frame(width: CGFloat(EQScreenLayout.toneValueWidth), alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, CGFloat(EQScreenLayout.toneRowGap))
        .frame(height: CGFloat(EQScreenLayout.toneRowHeight))
        .background(isHighlighted ? DesignSystem.Color.rowSelected : .clear,
                    in: RoundedRectangle(cornerRadius: DesignSystem.Radius.container))
        .contentShape(Rectangle())
    }

    /// The slider's value: this region's Tone in what plays now.
    private var levelBinding: Binding<Float> {
        Binding(get: { eq.tone(of: region) }, set: { move(to: $0) })
    }

    private func move(to db: Float) {
        if isDragging {
            eq.updateStroke(tone: region, to: db)
        } else {
            eq.setTone(region, to: db)
        }
    }

    private func dragChanged(_ dragging: Bool) {
        isDragging = dragging
        if dragging {
            eq.beginStroke()
        } else {
            eq.endStroke()
        }
        onDragChanged(dragging)
    }
}
