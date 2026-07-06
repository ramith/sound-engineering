import Foundation

// MARK: - Tab Selection

enum TabSelection: String, CaseIterable {
    case nowPlaying = "Now Playing"
    case library = "Library"
    case eq = "EQ"
    case monitoring = "Monitoring"
    case settings = "Settings"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .nowPlaying: "play.circle.fill"
        case .library: "square.grid.2x2"
        case .eq: "slider.horizontal.3"
        case .monitoring: "waveform.and.magnifyingglass"
        case .settings: "gearshape.fill"
        }
    }
}
