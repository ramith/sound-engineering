import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @Environment(AudioViewModel.self) var viewModel
    @State private var selectedTab: TabSelection = .nowPlaying
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Primary Toolbar (60pt): Logo | Device | Tabs
            ToolbarView(selectedTab: $selectedTab)
                .environment(viewModel)

            // Tab Content
            TabContentView(selectedTab: selectedTab)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedTab)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.asWindow)
        .task {
            viewModel.initializeEngine()
        }
        .onDisappear {
            viewModel.shutdown()
        }
    }
}
