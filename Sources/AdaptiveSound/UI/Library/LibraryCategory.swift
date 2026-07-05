import Foundation

// MARK: - Library sidebar categories (S9.4)

/// The top-level browse categories shown in the Library sidebar. Albums + its detail
/// ship in S9.4; Songs/Artists/Genres/Years fill in over S9.5/S9.6 (their roots show a
/// "coming in a later slice" placeholder until then). S10 extends the sidebar with Playlists.
enum LibraryCategory: String, CaseIterable, Identifiable {
    case albums
    case artists
    case songs
    case genres
    case years

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .albums: "Albums"
        case .artists: "Artists"
        case .songs: "Songs"
        case .genres: "Genres"
        case .years: "Years"
        }
    }

    var icon: String {
        switch self {
        case .albums: "square.grid.2x2"
        case .artists: "music.mic"
        case .songs: "music.note"
        case .genres: "guitars"
        case .years: "calendar"
        }
    }
}
