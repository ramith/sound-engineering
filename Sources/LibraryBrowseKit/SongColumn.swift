// SongColumn — the Songs-list column CATALOG (S10.8 Library PR-D.2 — the addendum's ColumnSpec):
// each column's identity, labels, and fixed layout. Pure data, so it lives in the Kit where the
// header-fit test (SLOT-04) can measure it; the app target extends it with the parts that need
// the store row type and the app's formatters (`comparator`, `displayText`).

import Foundation

/// The identity of a Songs-list column. `index` (# / equalizer) and `title` are the FROZEN leading
/// group — always first, always visible, pinned on horizontal scroll. Every other column is
/// toggleable + reorderable, fixed-width, and lives in the horizontally-scrolling region. Sortable
/// columns expose a comparator app-side (the same keypaths the old Table used, so
/// `SongSortMapping` + `applySortOrder` are unchanged); the rest (index, genre, and the new
/// sampleRate/bitDepth/lastPlayed) are display-only — `isSortable` is the catalog's record of
/// which is which.
public enum SongColumn: String, CaseIterable, Codable, Identifiable, Sendable {
    case index, title, artist, album, genre, year, duration, dateAdded, quality
    case sampleRate, bitDepth, trackNo, discNo, fileSize, playCount, lastPlayed, albumArtist, format

    public var id: String {
        rawValue
    }

    /// The full label: the Columns menu, and the header's accessibility label.
    public var label: String {
        switch self {
        case .index: "#"
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .genre: "Genre"
        case .year: "Year"
        case .duration: "Time"
        case .dateAdded: "Date Added"
        case .quality: "Quality"
        case .sampleRate: "Sample Rate"
        case .bitDepth: "Bit Depth"
        case .trackNo: "Track #"
        case .discNo: "Disc #"
        case .fileSize: "File Size"
        case .playCount: "Play Count"
        case .lastPlayed: "Last Played"
        case .albumArtist: "Album Artist"
        case .format: "Format"
        }
    }

    /// The glass column-header row's label. Compact for the three narrow numeric columns whose
    /// full label cannot fit its own column ("Track #" 47pt in 44, "Play Count" 68pt in 56 —
    /// the founder's truncated "TRA…" header, 2026-10-06); everything else uses `label`.
    /// VoiceOver still reads the full `label`.
    public var headerLabel: String {
        switch self {
        case .trackNo: "Track"
        case .discNo: "Disc"
        case .playCount: "Plays"
        default: label
        }
    }

    /// Whether a header click sorts by this column — i.e. whether its header can carry the
    /// sort arrow, which SLOT-04 budgets. The app-side `comparator(_:)` table is the behaviour;
    /// it asserts (debug builds) that it returns a comparator exactly when this is true, so the
    /// two cannot drift silently.
    public var isSortable: Bool {
        switch self {
        case .index, .genre, .sampleRate, .bitDepth, .lastPlayed: false
        default: true
        }
    }

    /// Header-row typography + the active-sort arrow, as DATA: the header view renders with
    /// these and SLOT-04 measures with them, so the test cannot drift from the render.
    public static let headerTracking: CGFloat = 0.6
    public static let headerArrowSize: CGFloat = 8
    public static let headerArrowSpacing: CGFloat = 4

    /// Fixed width in points, or `nil` for the only flexible column (Title: `minmax(240, 1fr)`).
    /// Widths per the addendum; Format / Album Artist (not in the addendum's list, kept from the
    /// old Table) get sensible values. Two deliberate departures: Track No 44 → 52 and Disc
    /// 40 → 44 — at the addendum widths even the compact header ("Track" / "Disc") plus the sort
    /// arrow does not fit (47.4pt and 39.5pt measured), so an actively-sorted header truncated.
    /// SLOT-04 holds every column to "its header fits its width".
    public var width: CGFloat? {
        switch self {
        case .index: 34
        case .title: nil // flexible — takes leftover, min 240 (applied at the row)
        case .artist: 150
        case .album: 150
        case .genre: 100
        case .year: 52
        case .duration: 58
        case .dateAdded: 96
        case .quality: 84
        case .sampleRate: 82
        case .bitDepth: 64
        case .trackNo: 52
        case .discNo: 44
        case .fileSize: 74
        case .playCount: 56
        case .lastPlayed: 96
        case .albumArtist: 150
        case .format: 64
        }
    }

    /// The flexible Title column's minimum before horizontal scrolling starts (addendum).
    public static let titleMinWidth: CGFloat = 240

    /// Trailing-aligned (mono numerics) vs leading (text). Index is centered (handled at the row).
    public var isTrailing: Bool {
        switch self {
        case .year, .duration, .sampleRate, .bitDepth, .trackNo, .discNo, .fileSize, .playCount:
            true
        default:
            false
        }
    }

    /// Monospaced numeric/technical columns (addendum: "mono numerics right-aligned").
    public var isMono: Bool {
        switch self {
        case .index, .year, .duration, .dateAdded, .quality, .sampleRate, .bitDepth,
             .trackNo, .discNo, .fileSize, .playCount, .lastPlayed:
            true
        default:
            false
        }
    }

    /// The frozen leading group — always first, always visible, pinned on horizontal scroll.
    public var isFrozen: Bool {
        self == .index || self == .title
    }

    /// First-click direction: recency columns lead descending, everything else ascending.
    public var defaultOrder: SortOrder {
        switch self {
        case .dateAdded, .lastPlayed, .playCount: .reverse
        default: .forward
        }
    }
}
