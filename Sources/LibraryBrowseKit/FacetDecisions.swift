// MARK: - Facet browse decisions (S9.6 — Artists/Genres/Years pure decisions)

/// Pure "N songs" count label for facet rows + detail headers. Groups the number
/// (`.formatted(.number)`, matching the Songs-tab count line) and singularizes at 1.
/// Extracted so the copy + pluralization are unit-tested once instead of drifting across
/// the three list rows and three detail headers.
public enum FacetCountLabel {
    public static func songs(count: Int) -> String {
        "\(count.formatted(.number)) \(count == 1 ? "song" : "songs")"
    }
}

/// Whether a facet detail shows its track list or the facet empty-state. A reachable
/// 0-song facet (e.g. a genre that dropped to 0 after a rescan) renders `.empty`.
public enum FacetDetailState: Sendable, Equatable {
    case empty
    case list

    public static func state(trackCount: Int) -> FacetDetailState {
        trackCount > 0 ? .list : .empty
    }
}

/// Whether a facet row is shown in the Artists/Genres lists. 0-song facets (e.g. an
/// album-artist-only "Various Artists" with no track-level appearances) are hidden from
/// the browse lists; the DAO keeps them reachable for detail reads + the sweep gate.
public enum FacetListVisibility {
    public static func isVisible(trackCount: Int) -> Bool {
        trackCount > 0
    }
}
