import DesignTokenKit
import SwiftUI

// MARK: - EQ graph card header (Sprint EQ, EQ3)

/// The preset and its state over the "Used on <output>" pin (`EQGraphHeading`), then Compare, Reset and
/// Save — on one row, or on two where they don't fit (larger text, a long preset name): macOS ignores
/// Dynamic Type clamps, so the header holds by reflowing, never by clipping. At least
/// `EQScreenLayout.headerHeight`, which holds the pin's line, so it comes and goes without moving the graph.
struct EQGraphHeader: View {
    /// Opens the Save sheet.
    let save: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                EQGraphHeading()
                Spacer(minLength: DesignSystem.Spacing.small)
                EQGraphActions(save: save)
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                EQGraphHeading()
                EQGraphActions(save: save)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(minHeight: CGFloat(EQScreenLayout.headerHeight))
    }
}
