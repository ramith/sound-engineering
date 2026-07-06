import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        @Bindable var viewModel = viewModel
        // Pinned chrome header + flexible content + pinned footer. AppShell owns the band
        // heights, backgrounds, hairlines, and the window minimum (L2) — this view no longer
        // sets `.frame(minWidth:minHeight:)` or the window background.
        AppShell {
            ChromeBar(selectedTab: $viewModel.selectedTab)
                .environment(viewModel)
        } content: {
            TabContentView(selectedTab: viewModel.selectedTab)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.selectedTab)
        } footer: {
            NowPlayingBar()
        }
        // Engine init/teardown intentionally NOT here — it's owned by the app/scene lifecycle
        // (AdaptiveSound.swift `.onAppear` starts it; AppDelegate.applicationShouldTerminate
        // tears it down, awaited). Binding it to a view's `.task`/`.onDisappear` made teardown
        // unreliable at quit (fire-and-forget) and re-inited on any view re-appearance.
    }
}
