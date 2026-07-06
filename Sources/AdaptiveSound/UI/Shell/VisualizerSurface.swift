import SwiftUI

/// The drawing-surface contract: a fill-width card sized by *either* an aspect ratio *or*
/// a min / ideal / max height, tokenized (no magic pixel heights).
///
/// The child (an EQ graph, spectrum, artwork, …) draws to whatever size the surface is
/// given. When `aspect` is set it wins; otherwise the height band applies (an absent
/// `maxHeight` means "grow to fill"). The surface paints the card background, clips to the
/// container radius, and strokes a hairline border.
struct VisualizerSurface<Content: View>: View {
    let minHeight: CGFloat
    let idealHeight: CGFloat?
    let maxHeight: CGFloat?
    let aspect: CGFloat?
    let content: Content

    init(
        minHeight: CGFloat,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        aspect: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.aspect = aspect
        self.content = content()
    }

    var body: some View {
        Group {
            if let aspect {
                content
                    .frame(maxWidth: .infinity)
                    .aspectRatio(aspect, contentMode: .fit)
            } else {
                content
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight ?? .infinity)
            }
        }
        .background(DesignSystem.Color.card)
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.container))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.container)
                .strokeBorder(DesignSystem.Color.hairline, lineWidth: DesignSystem.ShellMetrics.hairline)
        }
    }
}
