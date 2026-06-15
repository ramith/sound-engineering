import Foundation
import SwiftUI

@main
struct AdaptiveSound: App {
    @State private var viewModel = AudioViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
    }
}

// MARK: - Main Content View (Phase 2: Tab-Based Layout)

struct ContentView: View {
    @Environment(AudioViewModel.self) var viewModel
    @State private var selectedTab: TabSelection = .nowPlaying
    @State private var volume: Float = 0.75
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Primary Toolbar (60pt): Logo | Device | Tabs | Volume
            ToolbarView(selectedTab: $selectedTab, volume: $volume)
                .environment(viewModel)

            // Tab Content
            tabContent
                .transition(.opacity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.asWindow)
        .onAppear {
            viewModel.initializeEngine()
        }
        .onDisappear {
            viewModel.shutdown()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .nowPlaying:
            NowPlayingTabView()
        case .eq:
            EQTabView()
        case .settings:
            SettingsTabView()
        }
    }
}

// MARK: - Tab Selection Enum

enum TabSelection: String, CaseIterable {
    case nowPlaying = "Now Playing"
    case eq = "EQ"
    case settings = "Settings"

    var id: String {
        rawValue
    }

    var subtitle: String {
        switch self {
        case .nowPlaying:
            return "Now Playing"
        case .eq:
            return "EQ Editing"
        case .settings:
            return "Preferences"
        }
    }

    var icon: String {
        switch self {
        case .nowPlaying:
            return "play.circle.fill"
        case .eq:
            return "slider.horizontal.3"
        case .settings:
            return "gearshape.fill"
        }
    }
}
