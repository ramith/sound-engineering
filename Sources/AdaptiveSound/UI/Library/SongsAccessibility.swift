import Foundation
import LibraryStore
import SwiftUI

// MARK: - Songs table accessibility (S9.5 §10.7 / §11.6)

/// Pure builders for the Songs table's VoiceOver strings + sort-change announcements. The row
/// label / value are composed from the TRACK MODEL — never from the visible cells — so they stay
/// STABLE regardless of which columns are shown or hidden (§11.6): hiding a column changes the
/// visual grid, NOT the row's spoken identity. Kept out of `SongsTable` so the hot table body stays
/// lean and this composition (which reuses the same `quality`/`date`/`duration` formatters as the
/// cells) is isolated and self-documenting.
enum SongsAccessibility {
    /// The row's spoken identity (§10.7): "Title, Artist" + album (when present) + duration. An
    /// empty artist falls back to "Unknown Artist" — the cell renders blank, but VoiceOver
    /// substitutes it so a track never reads as anonymous.
    static func rowLabel(for track: LibraryTrackDisplay) -> String {
        let artist = track.artistName.isEmpty ? "Unknown Artist" : track.artistName
        var parts = ["\(track.title), \(artist)"]
        if let album = track.albumName, !album.isEmpty { parts.append(album) }
        parts.append(spokenDuration(track.durationSeconds))
        return parts.joined(separator: ", ")
    }

    /// The row's spoken value (§10.7): quality, year, added-date — nils skipped. Quality is always
    /// present (`format` is NOT NULL); year and date drop out when absent.
    static func rowValue(for track: LibraryTrackDisplay) -> String {
        var parts = [
            qualityString(format: track.format, sampleRate: track.sampleRate, bitDepth: track.bitDepth),
        ]
        if let year = track.year, year > 0 { parts.append(String(year)) }
        let date = compactDate(track.dateAdded)
        if !date.isEmpty { parts.append("added \(date)") }
        return parts.joined(separator: ", ")
    }

    /// "Sorted by Title, ascending" — the sort-change VoiceOver announcement (§10.7). Returns `nil`
    /// for an empty order (the composite default / a triangle cleared by hiding the active column),
    /// so those transitions announce nothing. `\.format` maps to the default-visible "Quality"
    /// header (Quality and Format share the comparator); Genre/Artwork are display-only → `nil`.
    static func sortAnnouncement(for comparators: [KeyPathComparator<LibraryTrackDisplay>]) -> String? {
        guard let primary = comparators.first, let name = columnName(for: primary.keyPath) else {
            return nil
        }
        let direction = primary.order == .forward ? "ascending" : "descending"
        return "Sorted by \(name), \(direction)"
    }

    /// The header display name for a sort comparator's keypath. A function-local table (mirrors
    /// `SongSortMapping`): `PartialKeyPath` is not `Sendable`, so a stored global trips Swift 6
    /// concurrency checking; rebuilding it on the rare sort change is negligible.
    private static func columnName(for keyPath: PartialKeyPath<LibraryTrackDisplay>) -> String? {
        let names: [PartialKeyPath<LibraryTrackDisplay>: String] = [
            \LibraryTrackDisplay.title: "Title",
            \LibraryTrackDisplay.artistName: "Artist",
            \LibraryTrackDisplay.albumName: "Album",
            \LibraryTrackDisplay.durationMs: "Time",
            \LibraryTrackDisplay.dateAdded: "Date Added",
            \LibraryTrackDisplay.format: "Quality",
            \LibraryTrackDisplay.year: "Year",
            \LibraryTrackDisplay.trackNo: "Track Number",
            \LibraryTrackDisplay.discNo: "Disc Number",
            \LibraryTrackDisplay.fileSize: "File Size",
            \LibraryTrackDisplay.albumArtistName: "Album Artist",
            \LibraryTrackDisplay.playCount: "Play Count",
        ]
        return names[keyPath]
    }
}
