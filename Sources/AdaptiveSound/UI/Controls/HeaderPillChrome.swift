import DesignTokenKit
import SwiftUI

// MARK: - Header pill chrome (S10.8 D fix round — the Filter, Sort and Columns pills' one capsule)

/// The capsule every header pill wears — the Filter pill (`FilterPill`) and Songs' Sort and Columns
/// pills — in one place, so the three can't drift (Sort hand-rolled it, and Columns drew its edge
/// inside the capsule while the others centred theirs on it). The pill's content sits
/// `FilterPillMetrics.horizontalInset` in from the round ends; the height is the shared pill height,
/// scaled with the text size; the edge is drawn INSIDE the capsule.
struct HeaderPillChrome: ViewModifier {
    /// How the pill reads at rest.
    enum Tone {
        /// The Filter and Sort pills: the card fill and a hairline edge.
        case neutral
        /// The Columns pill: the chip's "on" fill (`controlActiveFill`, the accent at 16%) and a
        /// teal edge.
        case active
        /// A destructive action (the dialog's Delete): the error red's tint (`destructiveFill`) and
        /// a `statusErrorText` edge — the app's error family, not the system red.
        case destructive
    }

    let tone: Tone
    /// The pointer is over a pill that acts on a click (the EQ header's Reset and Compare): the chip's
    /// hover wash over the fill.
    var isHovered = false

    /// 30 pt at the default text size.
    @ScaledMetric(relativeTo: .body) private var height = ControlMetrics.pillHeight

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, CGFloat(FilterPillMetrics.horizontalInset))
            .frame(height: height)
            .background {
                Self.capsule.fill(fill)
                    .overlay { Self.capsule.fill(isHovered ? DesignSystem.Color.controlHover : .clear) }
            }
            .overlay(Self.capsule.strokeBorder(edge, lineWidth: edgeWidth))
    }

    /// The pill's shape: fully round ends. Circular, not the continuous default, whose corners need more
    /// straight edge than a pill this short has — its stroke then overran the ends as two vertical ticks.
    private static let capsule = Capsule(style: .circular)

    private var fill: Color {
        switch tone {
        case .neutral: DesignSystem.Color.card
        case .active: DesignSystem.Color.controlActiveFill
        case .destructive: DesignSystem.Color.destructiveFill
        }
    }

    private var edge: Color {
        switch tone {
        case .neutral: DesignSystem.Color.hairline
        case .active: DesignSystem.Color.accent.opacity(0.30)
        case .destructive: DesignSystem.Color.statusErrorText
        }
    }

    private var edgeWidth: CGFloat {
        switch tone {
        case .neutral: 0.5
        case .active, .destructive: ControlMetrics.stateRingWidth
        }
    }
}

extension View {
    /// Wear the header pills' capsule (`HeaderPillChrome`), washed while `isHovered`.
    func headerPillChrome(_ tone: HeaderPillChrome.Tone, isHovered: Bool = false) -> some View {
        modifier(HeaderPillChrome(tone: tone, isHovered: isHovered))
    }
}
