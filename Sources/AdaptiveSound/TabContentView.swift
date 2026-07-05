import SwiftUI

// MARK: - Tab Content View

/// Switches the visible tab based on `selectedTab`.
/// Extracted from `ContentView` to avoid a `@ViewBuilder` computed property
/// on `body`, which would suppress structural identity optimizations.
struct TabContentView: View {
    let selectedTab: TabSelection

    var body: some View {
        switch selectedTab {
        case .nowPlaying:
            NowPlayingTabView()
        case .library:
            LibraryTabView()
        case .eq:
            EQTabView()
        case .monitoring:
            MonitoringTabView()
        case .settings:
            SettingsTabView()
        }
    }
}
