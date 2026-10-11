#if DEBUG
    import SwiftUI

    // MARK: - Picture-sheet dialog stand-in (Sprint EQ)

    /// A dialog world's sheet, drawn in the window: a real sheet is a window of its own, which an
    /// offscreen render of the main window can't capture. The dialog's own view (it paints its own
    /// surface), clipped to a sheet's corners and given the panel glass's rim and shadow, hanging below
    /// the chrome where macOS attaches a sheet.
    struct SheetDialogStandIn<Dialog: View>: View {
        @ViewBuilder let dialog: Dialog

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: DesignSystem.Radius.container)
            dialog
                .clipShape(shape)
                .glassPanel(.panel, in: shape)
                .padding(.top, DesignSystem.ShellMetrics.chromeHeight + DesignSystem.Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
#endif
