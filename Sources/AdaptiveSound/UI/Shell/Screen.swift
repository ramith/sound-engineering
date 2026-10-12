import SwiftUI

/// The only sanctioned way to occupy the shell's content region.
///
/// Always fills the region and top-aligns (never centers). It paints NO background: the app glow the
/// shell mounts behind every tab but Now Playing shows through (`TabContentView`, S10.8 F1).
/// `.stack` wraps content in a `ScrollView` so short windows scroll instead of clipping;
/// `.fill` hands the child the whole region edge-to-edge. `readableWidth` caps form-like
/// screens at `LayoutMetrics.readableMaxWidth`; `edgeToEdge` drops the standard insets.
struct Screen<Content: View>: View {
    var mode: ScreenMode = .stack
    var readableWidth = false
    var edgeToEdge = false
    @ViewBuilder var content: Content

    private var contentMaxWidth: CGFloat {
        readableWidth ? DesignSystem.LayoutMetrics.readableMaxWidth : .infinity
    }

    var body: some View {
        Group {
            switch mode {
            case .stack:
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: DesignSystem.LayoutMetrics.sectionGap) {
                        content
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, edgeToEdge ? 0 : DesignSystem.LayoutMetrics.screenInsetH)
                    .padding(.vertical, edgeToEdge ? 0 : DesignSystem.LayoutMetrics.screenInsetV)
                }
            case .fill:
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
