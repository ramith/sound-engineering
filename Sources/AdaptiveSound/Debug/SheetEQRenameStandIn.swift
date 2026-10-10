#if DEBUG
    import SwiftUI

    // MARK: - Picture-sheet Rename sheet (Sprint EQ, EQ4)

    /// The `rename` world's Rename sheet, drawn in the window: a real sheet is a window of its own, which
    /// an offscreen render of the main window can't capture. The sheet's own view, on the panel glass,
    /// hanging below the chrome where macOS attaches a sheet.
    struct SheetEQRenameStandIn: View {
        let name: String
        let eq: EQViewModel

        var body: some View {
            // Opaque, as a sheet is: the window colour under the panel glass.
            let shape = RoundedRectangle(cornerRadius: DesignSystem.Radius.container)
            SaveCustomPresetView(sheet: .rename(name), eqViewModel: eq)
                .background(DesignSystem.Color.window, in: shape)
                .glassPanel(.panel, in: shape)
                .padding(.top, DesignSystem.ShellMetrics.chromeHeight + DesignSystem.Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
#endif
