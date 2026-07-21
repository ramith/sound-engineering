import Foundation
import LibraryStore
import SwiftUI

// MARK: - Songs column model (S10.8 Library PR-D.2 — the addendum's ColumnSpec)

/// The identity of a Songs-list column. `index` (# / equalizer) and `title` are the FROZEN leading
/// group — always first, always visible, pinned on horizontal scroll. Every other column is
/// toggleable + reorderable, fixed-width, and lives in the horizontally-scrolling region. Sortable
/// columns expose a comparator (the same keypaths the old Table used, so `SongSortMapping` +
/// `applySortOrder` are unchanged); the rest (index, genre, and the new sampleRate/bitDepth/
/// lastPlayed) are display-only.
enum SongColumn: String, CaseIterable, Codable, Identifiable {
    case index, title, artist, album, genre, year, duration, dateAdded, quality
    case sampleRate, bitDepth, trackNo, discNo, fileSize, playCount, lastPlayed, albumArtist, format

    var id: String {
        rawValue
    }

    /// Menu / header label.
    var label: String {
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

    /// Fixed width in points, or `nil` for the only flexible column (Title: `minmax(240, 1fr)`).
    /// Widths per the addendum; Format / Album Artist (not in the addendum's list, kept from the
    /// old Table) get sensible values.
    var width: CGFloat? {
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
        case .trackNo: 44
        case .discNo: 40
        case .fileSize: 74
        case .playCount: 56
        case .lastPlayed: 96
        case .albumArtist: 150
        case .format: 64
        }
    }

    /// The flexible Title column's minimum before horizontal scrolling starts (addendum).
    static let titleMinWidth: CGFloat = 240

    /// Trailing-aligned (mono numerics) vs leading (text). Index is centered (handled at the row).
    var isTrailing: Bool {
        switch self {
        case .year, .duration, .sampleRate, .bitDepth, .trackNo, .discNo, .fileSize, .playCount:
            true
        default:
            false
        }
    }

    /// Monospaced numeric/technical columns (addendum: "mono numerics right-aligned").
    var isMono: Bool {
        switch self {
        case .index, .year, .duration, .dateAdded, .quality, .sampleRate, .bitDepth,
             .trackNo, .discNo, .fileSize, .playCount, .lastPlayed:
            true
        default:
            false
        }
    }

    /// The frozen leading group — always first, always visible, pinned on horizontal scroll.
    var isFrozen: Bool {
        self == .index || self == .title
    }

    /// The sort comparator for a header click, or `nil` for display-only columns (index, genre,
    /// and the new technical columns that `SongSortMapping` doesn't map). Same keypaths the old
    /// Table used, so the DAO mapping is unchanged.
    func comparator(_ order: SortOrder) -> KeyPathComparator<LibraryTrackDisplay>? {
        // Function-local (not `static`): a `KeyPathComparator` holds a non-Sendable `PartialKeyPath`,
        // so a stored table trips Swift 6 concurrency (the `SongSortMapping` idiom); rebuilding this
        // small map on the rare header render/click is negligible. Same keypaths the old Table used,
        // so `SongSortMapping` + the DAO mapping are unchanged. Display-only columns are absent → nil.
        let comparators: [SongColumn: KeyPathComparator<LibraryTrackDisplay>] = [
            .title: KeyPathComparator(\.title, order: order),
            .artist: KeyPathComparator(\.artistName, order: order),
            .album: KeyPathComparator(\.albumName, order: order),
            .year: KeyPathComparator(\.year, order: order),
            .duration: KeyPathComparator(\.durationMs, order: order),
            .dateAdded: KeyPathComparator(\.dateAdded, order: order),
            .quality: KeyPathComparator(\.format, order: order), // Quality + Format both sort by container
            .format: KeyPathComparator(\.format, order: order),
            .trackNo: KeyPathComparator(\.trackNo, order: order),
            .discNo: KeyPathComparator(\.discNo, order: order),
            .fileSize: KeyPathComparator(\.fileSize, order: order),
            .playCount: KeyPathComparator(\.playCount, order: order),
            .albumArtist: KeyPathComparator(\.albumArtistName, order: order),
        ]
        return comparators[self]
    }

    /// First-click direction: recency columns lead descending, everything else ascending.
    var defaultOrder: SortOrder {
        switch self {
        case .dateAdded, .lastPlayed, .playCount: .reverse
        default: .forward
        }
    }

    /// The row-cell display string for this column ("" → blank cell). A STATIC formatter table
    /// (built once): each closure captures nothing, so it's `Sendable` — unlike `comparator`'s
    /// keypath-bearing values. Index / Title render specially in the row, so they're absent here.
    func displayText(_ track: LibraryTrackDisplay) -> String {
        Self.formatters[self]?(track) ?? ""
    }

    private static let formatters: [SongColumn: @Sendable (LibraryTrackDisplay) -> String] = [
        .artist: { $0.artistName },
        .album: { $0.albumName ?? "" },
        .genre: { $0.genreName ?? "" },
        .albumArtist: { $0.albumArtistName ?? "" },
        .format: { $0.format },
        .quality: { qualityString(format: $0.format, sampleRate: $0.sampleRate, bitDepth: $0.bitDepth) },
        .year: { $0.year.flatMap { $0 > 0 ? String($0) : nil } ?? "" },
        .duration: { $0.durationSeconds > 0 ? formatDuration($0.durationSeconds) : "" },
        .dateAdded: { compactDate($0.dateAdded) },
        .sampleRate: { track in
            guard let rate = track.sampleRate, rate > 0 else { return "" }
            return (Double(rate) / 1000).formatted(.number.precision(.fractionLength(0 ... 1))) + " kHz"
        },
        .bitDepth: { $0.bitDepth.flatMap { $0 > 0 ? "\($0)-bit" : nil } ?? "" },
        .trackNo: { $0.trackNo.flatMap { $0 > 0 ? String($0) : nil } ?? "" },
        .discNo: { $0.discNo.flatMap { $0 > 0 ? String($0) : nil } ?? "" },
        .fileSize: { $0.fileSize > 0 ? $0.fileSize.formatted(.byteCount(style: .file)) : "" },
        .playCount: { $0.playCount > 0 ? $0.playCount.formatted(.number) : "" },
        .lastPlayed: { $0.lastPlayed.map { compactDate($0) } ?? "" },
    ]
}

// MARK: - Persisted configuration (order + visibility)

/// The user's Songs columns — ORDER (array position) + per-column visibility. Width / alignment /
/// label are intrinsic to `SongColumn`, so only order + visibility persist. `RawRepresentable`
/// over a JSON string so it survives launches via `@AppStorage` (the Codable-`@AppStorage`
/// idiom); a garbage/absent blob falls back to `.default`.
struct SongColumnConfig: RawRepresentable, Equatable {
    struct Entry: Codable, Equatable {
        let column: SongColumn
        var visible: Bool
    }

    var entries: [Entry]

    /// The frozen leading group, always first + visible regardless of the stored blob.
    var frozen: [SongColumn] {
        [.index, .title]
    }

    /// The visible NON-frozen columns, in order — the horizontally-scrolling metadata region.
    var scrollingColumns: [SongColumn] {
        entries.filter { $0.visible && !$0.column.isFrozen }.map(\.column)
    }

    /// The glass column-header row appears only once the visible set differs from the default
    /// (any non-default column shown, or the default 5 disturbed).
    var isCustomized: Bool {
        self != .default
    }

    /// Display order for `.default`: the clean hero row leads (png/00 — # · Title · Artist ·
    /// Date Added · Time), then every other (hidden) column in catalog order. The single source
    /// for BOTH which columns show by default AND their order — kept separate from `allCases` (the
    /// catalog / Columns-menu order) so the hero order never rides on enum declaration order (which
    /// lists Time before Date Added for the columns-mode header, png/06).
    private static let defaultVisibleColumns: [SongColumn] = [.index, .title, .artist, .dateAdded, .duration]

    static let `default`: SongColumnConfig = {
        let hidden = SongColumn.allCases.filter { !defaultVisibleColumns.contains($0) }
        return SongColumnConfig(entries: (defaultVisibleColumns + hidden).map {
            Entry(column: $0, visible: defaultVisibleColumns.contains($0))
        })
    }()

    /// RawRepresentable (JSON) for @AppStorage. Encode the `entries` ARRAY, never `self`: `self` is
    /// RawRepresentable, whose default `Encodable.encode(to:)` re-reads `rawValue` — encoding `self`
    /// recurses forever (stack overflow). `Entry` is plainly `Codable`, so the array round-trips.
    var rawValue: String {
        guard let data = try? JSONEncoder().encode(entries),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    init(entries: [Entry]) {
        self.entries = entries
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        let config = SongColumnConfig(entries: decoded)
        guard config.isStructurallyValid else { return nil }
        self = config
    }

    /// A decoded blob must still cover EXACTLY the current `SongColumn` set (no missing/extra/dupe)
    /// — a catalog change (added/removed case) invalidates the old blob → fall back to `.default`.
    private var isStructurallyValid: Bool {
        Set(entries.map(\.column)) == Set(SongColumn.allCases) && entries.count == SongColumn.allCases.count
    }
}
