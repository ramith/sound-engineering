import SwiftUI

// MARK: - Teal pill button (primary actions)

/// The app's primary-action button (S10.8 A2): a capsule wearing the SHIPPED teal gloss — the
/// same `TealGloss` as the active tab capsule and the footer play button — with dark-on-teal
/// `onAccent` text (R4-TAB-01 audits it on the gradient stops the label sits on).
///
/// It replaces the system bordered-prominent style, whose WHITE-on-teal label fails AA (≈ 2.5:1 on
/// `accent`, ≈ 4.3:1 even on `accentDeep`); semgrep `ui-no-bordered-prominent` keeps it out.
/// The whole capsule is built inside the style's body, so it is the hit shape (a fill outside
/// a Button never extends its hit area). Pressed and disabled are drawn here — a custom style
/// gets neither from the system.
struct PillButtonStyle: ButtonStyle {
    /// The base pill height (30pt), scaled with Dynamic Type so larger text never clips.
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 30
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
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? pressedOpacity : 1) : disabledOpacity)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    /// The teal pill for a screen's primary action: `.buttonStyle(.pill)`.
    static var pill: PillButtonStyle {
        PillButtonStyle()
    }
}
