import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            // Primary Toolbar (60pt): Logo | Device | Tabs
            ToolbarView(selectedTab: $viewModel.selectedTab)
                .environment(viewModel)

            // Tab Content
            TabContentView(selectedTab: viewModel.selectedTab)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.selectedTab)
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
