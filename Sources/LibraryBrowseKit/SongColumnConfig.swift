// SongColumnConfig — the user's Songs columns (order + visibility), persisted by the app's
// `@AppStorage`. Pure data beside the `SongColumn` catalog, so its equality — which decides
// whether the glass column-header row shows — is headlessly tested (S10.8 B2a).

import Foundation

/// The user's Songs columns — ORDER (array position) + per-column visibility. Width / alignment /
/// label are intrinsic to `SongColumn`, so only order + visibility persist. `RawRepresentable`
/// over a JSON string so it survives launches via `@AppStorage` (the Codable-`@AppStorage`
/// idiom); a garbage/absent blob falls back to `.default`.
public struct SongColumnConfig: RawRepresentable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let column: SongColumn
        public var visible: Bool
    }

    public var entries: [Entry]

    /// The frozen leading group, always first + visible regardless of the stored blob.
    public var frozen: [SongColumn] {
        [.index, .title]
    }

    /// The visible NON-frozen columns, in order — the horizontally-scrolling metadata region.
    public var scrollingColumns: [SongColumn] {
        entries.filter { $0.visible && !$0.column.isFrozen }.map(\.column)
    }

    /// The glass column-header row appears only once the visible set differs from the default
    /// (any non-default column shown, or the default 5 disturbed).
    public var isCustomized: Bool {
        self != .default
    }

    /// Display order for `.default`: the clean hero row leads (png/00 — # · Title · Artist ·
    /// Date Added · Time), then every other (hidden) column in catalog order. The single source
    /// for BOTH which columns show by default AND their order — kept separate from `allCases` (the
    /// catalog / Columns-menu order) so the hero order never rides on enum declaration order (which
    /// lists Time before Date Added for the columns-mode header, png/06).
    private static let defaultVisibleColumns: [SongColumn] = [.index, .title, .artist, .dateAdded, .duration]

    public static let `default`: SongColumnConfig = {
        let hidden = SongColumn.allCases.filter { !defaultVisibleColumns.contains($0) }
        return SongColumnConfig(entries: (defaultVisibleColumns + hidden).map {
            Entry(column: $0, visible: defaultVisibleColumns.contains($0))
        })
    }()

    /// RawRepresentable (JSON) for @AppStorage. Encode the `entries` ARRAY, never `self`: `self` is
    /// RawRepresentable, whose default `Encodable.encode(to:)` re-reads `rawValue` — encoding `self`
    /// recurses forever (stack overflow). `Entry` is plainly `Codable`, so the array round-trips.
    ///
    /// The string is CANONICAL (sorted keys), and that is load-bearing: this type's `Equatable` is
    /// the standard library's `RawRepresentable` `==`, which compares `rawValue`s — so
    /// `isCustomized` is exactly as stable as this encoding. With unsorted keys the JSON key order
    /// varied from one encode to the next, `.default == .default` came out false at random, and the
    /// column-header row showed for an untouched config (S10.8 B2a — about one Songs render in
    /// four, the live app included).
    public var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(entries),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public init?(rawValue: String) {
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
