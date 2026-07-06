import SwiftUI

/// The app-shell canvas: a pinned header, a flexible content region, and a pinned footer.
///
/// The header and footer are reserved via `.safeAreaInset` (top / bottom), so they can
/// never be clipped, centered, or pushed off-screen; `content` owns the flexible vertical
/// axis and lays out *between* them. This is L1 — the primitive only. Scene-level concerns
/// (`.windowStyle(.hiddenTitleBar)`, `.windowBackgroundDragBehavior(.enabled)`, the window
/// toolbar) are wired at the scene in L2, NOT here. The chrome band is made draggable by the
/// native scene modifier in L2, so there is deliberately no `WindowDragArea` NSView here.
struct AppShell<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .frame(height: DesignSystem.ShellMetrics.chromeHeight)
                    .frame(maxWidth: .infinity)
                    .background(DesignSystem.Color.window)
                    .overlay(alignment: .bottom) { Hairline() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
                    .frame(height: DesignSystem.ShellMetrics.footerHeight)
                    .frame(maxWidth: .infinity)
                    .background(DesignSystem.Color.panel)
                    .overlay(alignment: .top) { Hairline() }
            }
            .background(DesignSystem.Color.window)
            .frame(
                minWidth: DesignSystem.ShellMetrics.windowMinWidth,
                minHeight: DesignSystem.ShellMetrics.windowMinHeight
            )
            // Hard window-min clamp at the AppKit layer — `.windowResizability(.contentMinSize)`
            // alone didn't stop the window being dragged smaller than the shell (chrome clipped).
            .background(WindowMinSize(
                width: DesignSystem.ShellMetrics.windowMinWidth,
                height: DesignSystem.ShellMetrics.windowMinHeight
            ))
    }
}
