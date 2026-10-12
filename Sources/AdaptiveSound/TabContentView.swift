import DesignTokenKit
import SwiftUI

// MARK: - Tab Content View

/// Switches the visible tab based on `selectedTab`, over the app glow.
/// Extracted from `ContentView` to avoid a `@ViewBuilder` computed property
/// on `body`, which would suppress structural identity optimizations.
struct TabContentView: View {
    let selectedTab: TabSelection

    var body: some View {
        // A container, not a `Group`: a `Group` hands its modifiers to each branch, so every tab would get
        // its own copy of the glow and a switch would replace it. Modifiers on the `ZStack` stay one view.
        ZStack(alignment: .top) {
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
        // Fill the content region whatever a tab's own size, so the glow behind it always does.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The app glow (S10.8 F1, decision 2): one teal pool behind Library, EQ, Monitoring and Settings,
        // mounted ONCE here, so switching between them leaves it still and no tab paints a backdrop of its
        // own. Now Playing paints its own art-sampled field instead. `GlowField` keeps the window base under
        // it and drops the glow under Reduce Transparency / Increase Contrast.
        .background {
            if selectedTab != .nowPlaying {
                GlowField(glows: GlowFieldSpec.appGlows)
            }
        }
    }
}
