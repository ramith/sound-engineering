import Foundation
import SwiftUI

@main
struct AdaptiveSound: App {
    @StateObject private var viewModel = AudioViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Main Content View (Phase 2: Tab-Based Layout)

struct ContentView: View {
    @EnvironmentObject var viewModel: AudioViewModel
    @State private var selectedTab: TabSelection = .nowPlaying
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Fixed Header (44pt)
            FixedHeaderView()
                .environmentObject(viewModel)

            // Tab Navigation
            VStack(spacing: 12) {
                Picker("Tab Selection", selection: $selectedTab.animation(reduceMotion ? nil : .easeInOut(duration: 0.2))) {
                    ForEach(TabSelection.allCases, id: \.id) { tab in
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Tab Navigation")
                .accessibilityValue(selectedTab.rawValue)

                // Breadcrumb subtitle
                HStack {
                    Text(selectedTab.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.asLabelSecond)
                        .transition(.opacity)
                        .id(selectedTab.id)
                    Spacer()
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Tab Content
            Group {
                switch selectedTab {
                case .nowPlaying:
                    NowPlayingTabView()
                case .eq:
                    EQTabView()
                case .settings:
                    SettingsTabView()
                }
            }
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
