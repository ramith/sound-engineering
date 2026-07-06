import SwiftUI

/// The reusable content card — dedupes the repeated pad + card-background + clip + hairline
/// pattern used across screens.
///
/// Padding is `DesignSystem.Spacing.medium`; the fill is `DesignSystem.Color.card`, clipped
/// to the container radius with a hairline stroke.
struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Color.card)
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.container))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.container)
                    .strokeBorder(DesignSystem.Color.hairline, lineWidth: DesignSystem.ShellMetrics.hairline)
            }
    }
}
