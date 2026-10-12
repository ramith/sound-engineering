import SwiftUI

/// A tab that stacks its sections in the shell's content region: a vertical stack, inside a
/// `ScrollView` so a short window scrolls rather than clips, filling the region and top-aligned
/// (never centred) — Monitoring and Settings. (Now Playing, Library and EQ lay out their own panes.)
///
/// It paints NO background: the app glow the shell mounts behind every tab but Now Playing shows
/// through (`TabContentView`, S10.8 F1). `edgeToEdge` drops the standard insets, for content that
/// brings its own.
struct Screen<Content: View>: View {
    var edgeToEdge = false
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DesignSystem.LayoutMetrics.sectionGap) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, edgeToEdge ? 0 : DesignSystem.LayoutMetrics.screenInsetH)
            .padding(.vertical, edgeToEdge ? 0 : DesignSystem.LayoutMetrics.screenInsetV)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
