import SwiftUI

// MARK: - Teal pill button (primary actions)

/// The app's primary-action button (S10.8 A2): a capsule wearing the SHIPPED teal gloss — the
/// same `TealGloss` as the active tab capsule and the footer play button — with dark-on-teal
/// `onAccent` text (R4-TAB-01 audits it on the gradient stops the label sits on).
///
/// It replaces the system bordered-prominent style, whose WHITE-on-teal label fails AA (≈ 2.5:1 on
/// `accent`, ≈ 4.3:1 even on `accentDeep`); semgrep `ui-no-bordered-prominent` keeps it out.
/// The whole capsule is built inside the style's body, so it is the hit shape (a fill outside
/// a Button never extends its hit area) and the keyboard focus ring's shape. Pressed and
/// disabled are drawn here — a custom style gets neither from the system.
///
/// Height follows `controlSize` like a system button: regular matches a `.bordered` button
/// (24pt, measured offscreen on macOS 26) so a pill sits level with its system neighbours;
/// `.large` is the 30pt header pill. Both scale with Dynamic Type so larger text never clips.
struct PillButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .body) private var regularHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var largeHeight = ControlMetrics.pillHeight
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    /// Label inset from the capsule's ends — wide enough that the round caps clear the text.
    private let horizontalPadding: CGFloat = 14
    /// Pressed matches the footer play button (the other `TealGloss` control) so every teal
    /// gloss control answers a press the same way.
    private let pressedOpacity = 0.6
    private let disabledOpacity = 0.45

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Font.bodyMedium)
            .foregroundStyle(DesignSystem.Color.onAccent)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minHeight)
            .background(TealGloss(shape: Capsule()))
            .contentShape([.interaction, .focusEffect], Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? pressedOpacity : 1) : disabledOpacity)
    }

    private var minHeight: CGFloat {
        switch controlSize {
        case .large, .extraLarge: largeHeight
        default: regularHeight
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    /// The teal pill for a screen's primary action: `.buttonStyle(.pill)`.
    static var pill: PillButtonStyle {
        PillButtonStyle()
    }
}
