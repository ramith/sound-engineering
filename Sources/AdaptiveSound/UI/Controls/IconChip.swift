import SwiftUI

// MARK: - Icon chip (S10.8 D3 — the app's one icon-only button)

/// The app's icon-only button: a 28pt rounded-square chip with a resting wash, a hover lift (the
/// glyph brightens to `label`), a pressed dim and, for a state chip, an "on" look.
///
/// - **A label is required.** `title` is the chip's VoiceOver label and Voice Control name — the
///   glyph is a `Label` drawn icon-only, so its text is always there for assistive tech. There is
///   no way to build a chip without one.
/// - **"On" is not shown by fill alone.** The teal tint (≈ 1.1–1.3:1 against the window) is joined
///   by the teal glyph and a 1pt `accentForeground` ring that clears 3:1 against the window and
///   the tint in both appearances (R4-CHIP-04), so "on" still reads in grayscale. VoiceOver reads
///   the state as the chip's value ("Shuffle, On").
/// - **Keyboard:** a Tab stop under Full Keyboard Access, pressed with Return (Space is the
///   app-wide play / pause key). It carries the app's keyboard ring (`controlFocusRing`) in place
///   of the system focus effect, drawn only while the window is keyboard-driven.
/// - The chip is built inside the button (its style), so the chip IS the hit shape — a frame or
///   background around a Button never extends its hit area.
///
/// Glyph-on-fill contrast for every state is R4-CHIP-01.
struct IconChip: View {
    /// The glyph's colour while the chip is not on.
    enum Emphasis {
        /// The secondary label, brightening to the label on hover.
        case standard
        /// The teal of a leading ACTION (jump to now playing): accent identity without the on look.
        case accented
    }

    private let title: String
    private let systemImage: String
    private let emphasis: Emphasis
    /// A state chip's on state and the value VoiceOver reads; nil for a plain action.
    private let state: (isOn: Bool, value: String)?
    private let action: () -> Void

    @State private var isHovered = false

    /// An action chip (Clear Queue, Jump to Now Playing).
    init(_ title: String, systemImage: String, emphasis: Emphasis = .standard, action: @escaping () -> Void) {
        assert(!title.isEmpty, "an icon chip needs its accessibility label")
        self.title = title
        self.systemImage = systemImage
        self.emphasis = emphasis
        state = nil
        self.action = action
    }

    /// A state chip (Shuffle, Repeat): `isOn` draws the on look; `value` is the state VoiceOver reads
    /// after the title ("On", "All", "One").
    init(_ title: String, systemImage: String, isOn: Bool, value: String, action: @escaping () -> Void) {
        assert(!title.isEmpty, "an icon chip needs its accessibility label")
        self.title = title
        self.systemImage = systemImage
        emphasis = .standard
        state = (isOn, value)
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(ChipStyle(isOn: state?.isOn ?? false, emphasis: emphasis, isHovered: isHovered))
            .controlFocusRing(around: RoundedRectangle(cornerRadius: DesignSystem.Radius.control))
            .onHover { isHovered = $0 }
            .accessibilityValue(state?.value ?? "")
    }
}

extension IconChip {
    /// The chip itself. Private, so the only way to the chip look is through `IconChip` and its
    /// required label; a style (not a plain label) because the pressed state is the style's.
    private struct ChipStyle: ButtonStyle {
        let isOn: Bool
        let emphasis: Emphasis
        let isHovered: Bool

        @ScaledMetric(relativeTo: .callout) private var side = ControlMetrics.chipSide
        @ScaledMetric(relativeTo: .callout) private var symbolSize = ControlMetrics.chipSymbol
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            let shape = RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
            configuration.label
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(glyph)
                .frame(width: side, height: side)
                .background(fill, in: shape)
                .overlay {
                    if isOn {
                        shape.strokeBorder(DesignSystem.Color.accentForeground,
                                           lineWidth: ControlMetrics.stateRingWidth)
                    }
                }
                .contentShape(shape)
                .opacity(configuration.isPressed ? ControlMetrics.pressedOpacity : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        }

        private var glyph: Color {
            if !isEnabled {
                DesignSystem.Color.labelDisabled
            } else if isOn || emphasis == .accented {
                DesignSystem.Color.accentText
            } else {
                isHovered ? DesignSystem.Color.label : DesignSystem.Color.labelSecondary
            }
        }

        private var fill: Color {
            if isOn {
                DesignSystem.Color.controlActiveFill
            } else {
                isHovered && isEnabled ? DesignSystem.Color.controlHover : DesignSystem.Color.hoverWash
            }
        }
    }
}
