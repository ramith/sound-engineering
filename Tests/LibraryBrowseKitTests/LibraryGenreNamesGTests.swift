@testable import LibraryScan
import Testing

// MARK: - Sprint G break-it: genre names split on "/" (G-LIB-07)

/// MetadataExtractor.parseGenres splits a genre tag on ";" AND "/". Apple names several of its own
/// genres with a slash — every song bought from the iTunes Store or tagged by Music carries them — so
/// "Singer/Songwriter" becomes two Genres tiles, "Singer" and "Songwriter", and "Hip-Hop/Rap" and
/// "R&B/Soul" two each.
@Suite("Sprint G break-it — genre names")
struct LibraryGenreNamesGTests {
    @Test("G-LIB-07: an Apple genre with a slash in its name stays one genre",
          arguments: ["Singer/Songwriter", "Hip-Hop/Rap", "R&B/Soul"])
    func appleSlashGenreIsOneGenre(name: String) {
        #expect(MetadataExtractor.parseGenres(name) == [name])
    }
}
