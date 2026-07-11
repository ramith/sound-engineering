import Foundation

// MARK: - Library sidebar categories (S9.4)

/// The top-level browse categories shown in the Library sidebar (Songs · Albums · Artists ·
/// Genres). S10 extends the sidebar with Playlists.
enum LibraryCategory: String, CaseIterable, Identifiable {
    // Declaration order = sidebar order (CaseIterable). Songs leads: the library skews toward
    // loose singles (album-less tracks appear only in Songs), so it's the most useful entry point.
    case songs
    case albums
    case artists
    case genres

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .genres: "Genres"
        }
    }

    var icon: String {
        switch self {
        case .songs: "music.note"
        case .albums: "square.grid.2x2"
        case .artists: "music.mic"
        case .genres: "guitars"
        }
    }
}
