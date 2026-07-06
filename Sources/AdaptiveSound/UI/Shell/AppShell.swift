import SwiftUI

/// The app-shell canvas: a pinned header, a flexible content region, and a pinned footer.
///
/// The header and footer are reserved via `.safeAreaInset` (top / bottom), so they can
/// never be clipped, centered, or pushed off-screen. `content` is hard-bounded to *exactly*
/// the region between them and clips its own overflow, so an over-tall tab can never spill up
/// into — or push around — the fixed chrome band. This is L1 — the primitive only. Scene-level concerns
/// (`.windowStyle(.hiddenTitleBar)`, `.windowBackgroundDragBehavior(.enabled)`, the window
/// toolbar) are wired at the scene in L2, NOT here. The chrome band is made draggable by the
/// native scene modifier in L2, so there is deliberately no `WindowDragArea` NSView here.
struct AppShell<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        content
            // Hard-bound the content to EXACTLY the region (window - chrome - footer) and
            // CONTAIN its overflow, so it can never disturb the pinned bands. `maxHeight:
            // .infinity` makes this frame report the region height; `.top` alignment forces an
            // over-tall child to spill DOWNWARD (never centered up into the chrome); `.clipped()`
            // confines that spill to the region. The `.safeAreaInset` strips below are applied
            // AFTER the clip, so the chrome/footer sit outside it and always render in full. L4's
            // `Screen` scrolls (.stack) or fills (.fill) WITHIN this same rectangle, so the clip
            // is a backstop — not a second scroll clip that would fight `Screen`'s own ScrollView.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
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
