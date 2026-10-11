import SwiftUI

// MARK: - Header pill face (Sprint EQ, EQ3 — the look of a header pill that acts on a click)

/// What a clickable header pill looks like — the EQ header's Reset and Compare (and EQ4's "Used on"
/// pin): its label in the header pills' capsule (`headerPillChrome`), the chip's hover wash, the shared
/// press dim, and a disabled look drawn by the label alone. The pill's behaviour is its owner's: a
/// `HeaderPillButton` for an action, `EQCompareButton` for press-and-hold.
struct HeaderPillFace<Content: View>: View {
    let content: Content
    let tone: HeaderPillChrome.Tone
    let isHovered: Bool
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content
            .font(DesignSystem.Font.bodyMedium)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .headerPillChrome(tone, isHovered: isHovered && isEnabled)
            .contentShape(Capsule())
            .opacity(isPressed ? ControlMetrics.pressedOpacity : 1)
    }

    private var foreground: Color {
        if !isEnabled {
            DesignSystem.Color.labelDisabled
        } else {
            switch tone {
            case .neutral: DesignSystem.Color.label
            case .active: DesignSystem.Color.accentText
            case .destructive: DesignSystem.Color.statusErrorText
            }
        }
    }
}
