// MARK: - Facet browse decisions (S9.6 — Artists/Genres/Years pure decisions)

/// Pure count labels: "N songs" for the browse tiles and detail headers, and the Library card
/// headers' count line. Groups the number (`.formatted(.number)`) and singularizes at 1. Extracted
/// so the copy + pluralization are unit-tested once instead of drifting across the tiles, the four
/// card headers and the detail headers.
public enum FacetCountLabel {
    public static func songs(count: Int) -> String {
        Self.count(count, noun: "song", filtered: false)
    }

    /// A card header's count line (S10.8 D4): "857 albums" — `noun` takes an "s" except at 1 — or,
    /// while a filter narrows the list, "N results" ("1 result").
    public static func count(_ count: Int, noun: String, filtered: Bool) -> String {
        let word = filtered ? "result" : noun
        return "\(count.formatted(.number)) \(word)\(count == 1 ? "" : "s")"
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

/// Whether a facet row is shown in the Albums grid and the Artists/Genres lists. 0-song facets
/// (e.g. an album-artist-only "Various Artists" with no track-level appearances, or an album a
/// retag just emptied) are hidden from the browse lists; the DAO keeps them reachable for detail
/// reads + the sweep gate.
public enum FacetListVisibility {
    public static func isVisible(trackCount: Int) -> Bool {
        trackCount > 0
    }
}
