// LibrarySortOrders — the `TrackSort`/`FacetSort` enums (split out of `LibraryTypes.swift`,
// S9.5 §12.1, to keep that file under the `file_length` budget as the catalog grew).
//
// Sendable value types crossing the `LibraryStore` actor boundary, same discipline as
// `LibraryTypes.swift` (design §4).

// MARK: - Sort orders

/// Sort order for `allTracks(sortedBy:)` / `allTracksDisplay(sortedBy:)`. Every order is
/// realised in SQL by `trackOrder(_:prefix:)` (one definition site, so the bare-`tracks`
/// and JOINed-Display reads can never drift) and ALWAYS ends in `id` as the final unique
/// tiebreaker, so a collision on the primary key yields a fully deterministic order.
///
/// `Hashable` so `trackOrder` can classify the descending variants by set membership.
///
/// The S9.5 (D7) additions serve the rich sortable Songs table. Nulls-ordering is EXPLICIT
/// and documented per case below; the JOINed artist/album **name** sorts
/// (`artistAlbumTrack`, `albumTitle*`) reference the Display reads' `ar`/`al` join aliases
/// and are therefore valid ONLY on the LEFT-JOINed Display reads — the bare `tracks` reads
/// use only the column-based sorts.
public enum TrackSort: Sendable, Hashable {
    /// By display name, locale-insensitive (SQLite `NOCASE`) — the S8.2 default.
    case name
    /// By resolved album then disc/track order (the album-detail order). No-album tracks
    /// (`album_id` NULL) sort FIRST (the `album_id IS NULL` lead term).
    case album
    /// By `date_added` descending (most-recent first) — a "recently added" view.
    case dateAddedDescending

    // MARK: S9.5 (D7) — rich sortable-table orders

    /// By display title (tag `title`, falling back to filename `name`) NOCASE ascending.
    case titleAsc
    /// By display title NOCASE descending.
    case titleDesc
    /// The composite DEFAULT: artist name NOCASE → album title NOCASE → disc_no → track_no
    /// → id. A NULL artist/album name (no artist / no album) sorts FIRST within its group
    /// (SQLite's default NULLS-FIRST for ascending).
    case artistAlbumTrack
    /// By album title NOCASE ascending; tracks with NO album (`al.title` NULL) sort LAST.
    case albumTitleAsc
    /// By album title NOCASE descending; tracks with NO album sort LAST (both directions,
    /// via the `al.title IS NULL` lead term).
    case albumTitleDesc
    /// By `duration_ms` ascending. `duration_ms` is `NOT NULL DEFAULT 0`, so undecoded
    /// tracks (0 ms) sort FIRST.
    case durationAsc
    /// By `duration_ms` descending; undecoded tracks (0 ms) sort LAST.
    case durationDesc
    /// By `date_added` ascending (oldest first) — complements `dateAddedDescending`.
    case dateAddedAsc
    /// By container `format` NOCASE ascending (`format` is `NOT NULL`).
    case formatAsc
    /// By container `format` NOCASE descending.
    case formatDesc
    /// By release `year` ascending; NULL year (unknown) sorts FIRST (NULLS-FIRST for asc),
    /// which keeps the read index-driven on `idx_tracks_year`.
    case yearAsc
    /// By release `year` descending; NULL year sorts LAST (NULLS-LAST for desc).
    case yearDesc

    // MARK: S9.5 §12.1 — full-catalog columns' rich sortable orders

    /// By `disc_no` ascending; NULL (no disc number) sorts FIRST (SQLite's default
    /// NULLS-FIRST for asc, same convention as `.yearAsc`). No dedicated index (only the
    /// composite `idx_tracks_album_order`), so this is an accepted bounded filesort (R3).
    case discNoAsc
    /// By `disc_no` descending; NULL sorts LAST (NULLS-LAST for desc).
    case discNoDesc
    /// By `file_size` ascending. `file_size` is `NOT NULL` — no NULLs-ordering concern
    /// (accepted bounded filesort, same class as `.durationAsc`/`.formatAsc`).
    case fileSizeAsc
    /// By `file_size` descending.
    case fileSizeDesc
    /// By `play_count` ascending. `play_count` is `NOT NULL DEFAULT 0` — no NULLs-ordering
    /// concern (accepted bounded filesort).
    case playCountAsc
    /// By `play_count` descending.
    case playCountDesc
    /// By `last_played` ascending; NULL (never played) sorts FIRST (SQLite's default
    /// NULLS-FIRST for asc, same convention as `.yearAsc`/`.dateAddedAsc`).
    case lastPlayedAsc
    /// By `last_played` descending; NULL sorts LAST (NULLS-LAST for desc).
    case lastPlayedDesc
    /// By resolved ALBUM-artist name NOCASE ascending (Display-only — the `aa` join). NULL
    /// album-artist (no album, OR the id-0 "Unknown Artist" sentinel) sorts LAST in BOTH
    /// directions — mirrors `.albumTitleAsc`, deliberately NOT the SQL NULLS-FIRST default.
    case albumArtistAsc
    /// By resolved ALBUM-artist name NOCASE descending; NULL still sorts LAST (mirrors
    /// `.albumTitleDesc` — NOT a plain reverse of `.albumArtistAsc`).
    case albumArtistDesc
    // Deliberately NO `.genre*` sort case: Genre is display-only (a correlated per-row
    // MIN subquery); sorting by it is an unbounded BR5 temp-b-tree hazard (§11.1/§12.1,
    // confirmed out of scope by both the architect-reviewer and the-fool pre-reviews).
}

/// Sort order for the facet queries (`albums`/`artists`).
public enum FacetSort: Sendable {
    /// Alphabetical by title/name (case-insensitive).
    case title
    /// By year ascending then title (albums); by name for artists.
    case year
}
