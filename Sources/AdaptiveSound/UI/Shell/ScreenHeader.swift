import SwiftUI

/// The only sanctioned in-content title surface (replaces `.navigationTitle`, which would
/// leak into the window titlebar the app owns).
///
/// A title (optional subtitle) with an optional leading back control. The back button keeps
/// its "Back" label for VoiceOver even under `.labelStyle(.iconOnly)`.
struct ScreenHeader: View {
    let title: String
    let subtitle: String?
    let onBack: (() -> Void)?

    init(title: String, subtitle: String? = nil, onBack: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
            if let onBack {
                Button("Back", systemImage: "chevron.backward", action: onBack)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                Text(title)
                    .font(DesignSystem.Font.displayTitle)
                    .foregroundStyle(DesignSystem.Color.label)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
        .padding(.vertical, DesignSystem.Spacing.small)
    }
}
