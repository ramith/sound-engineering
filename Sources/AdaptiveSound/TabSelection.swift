import Foundation

// MARK: - Tab Selection

enum TabSelection: String, CaseIterable {
    case nowPlaying = "Now Playing"
    case eq = "EQ"
    case settings = "Settings"

    var id: String {
        rawValue
    }

    var subtitle: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .eq: "EQ Editing"
        case .settings: "Preferences"
        }
    }

    var icon: String {
        switch self {
        case .nowPlaying: "play.circle.fill"
        case .eq: "slider.horizontal.3"
        case .settings: "gearshape.fill"
        }
    }
}
