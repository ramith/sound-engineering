import DesignTokenKit
import SwiftUI

// MARK: - EQ graph card (Sprint EQ, EQ3 — V1b's right column)

/// The right column's one glass card: the header over the graph on its analyzer lens, filling the
/// height, with the "Bring back edits" capsule floating over the lens's lower edge when a switch set
/// edits aside.
struct EQGraphCard: View {
    /// Opens the Save sheet.
    let save: () -> Void

    var body: some View {
        VStack(spacing: CGFloat(EQScreenLayout.headerGap)) {
            EQGraphHeader(save: save)
            EQGraph()
                .glassPanel(.lens, in: RoundedRectangle(cornerRadius: CGFloat(GlassDecor.lensRadius)))
        }
        .padding(CGFloat(EQScreenLayout.graphCardPadding))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            EQBringBackMessage()
                .padding(.bottom, CGFloat(EQScreenLayout.graphCardPadding) + DesignSystem.Spacing.small)
        }
        .libraryDetailCard()
    }
}
