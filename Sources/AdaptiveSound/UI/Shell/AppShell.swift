import SwiftUI

/// The app-shell canvas: a pinned header, a flexible content region, and a pinned footer.
///
/// A literal `VStack(spacing: 0)` of fixed-height chrome, flexible content, fixed-height footer.
/// The bands have fixed heights and the content is frame-bounded to *exactly* the rectangle
/// between them (and clips its overflow), so the bands can never be clipped, centered, or pushed
/// off-screen, and no tab can spill up into the chrome. An earlier revision pinned the bands with
/// `.safeAreaInset`, but that only insets the safe *area*, not the frame — so frame-filling
/// content (`NavigationSplitView`, a plain `VStack` header) rendered behind the chrome; an
/// explicit frame is the robust fix. This is L1 — the primitive only. Scene-level concerns
/// (`.windowStyle(.hiddenTitleBar)`, `.windowBackgroundDragBehavior(.enabled)`, the window
/// toolbar) are wired at the scene in L2, NOT here. The chrome band is made draggable by the
/// native scene modifier in L2, so there is deliberately no `WindowDragArea` NSView here.
struct AppShell<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        // A literal three-row stack: fixed chrome, flexible content, fixed footer. The content
        // region is given an EXPLICIT frame (the rectangle between the bands), NOT a
        // `.safeAreaInset`. A safe-area inset only shrinks the *safe area*, not the *frame* — so
        // a plain `VStack` (e.g. AlbumDetailView's fixed header) or a `NavigationSplitView`,
        // which lay their content out from the top of their frame, rendered UP behind the chrome.
        // An explicit frame physically bounds every tab — split view included — to this rectangle.
        VStack(spacing: 0) {
            header
                .frame(height: DesignSystem.ShellMetrics.chromeHeight)
                .frame(maxWidth: .infinity)
                // Realigned styled glass (S10.8 PR G): fill strata + specular/seam edges —
                // owns what `.background(window)` + the bottom `Hairline` did.
                .chromeBand(lightFrom: .top)

            // `maxHeight: .infinity` claims the space between the bands; `.top` alignment forces
            // an over-tall child to spill DOWNWARD (never up into the chrome); `.clipped()`
            // confines that spill. L4's `Screen` scrolls (.stack) or fills (.fill) WITHIN this
            // same rectangle, so the clip is only a backstop for a `.fill` child that overflows —
            // not a second scroll clip that would fight `Screen`'s own ScrollView.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()

            footer
                .frame(height: DesignSystem.ShellMetrics.footerHeight)
                .frame(maxWidth: .infinity)
                // Realigned styled glass, light source flipped (lit from its bottom); the
                // specular top edge replaces the old top `Hairline` + `panel` fill.
                .chromeBand(lightFrom: .bottom)
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
