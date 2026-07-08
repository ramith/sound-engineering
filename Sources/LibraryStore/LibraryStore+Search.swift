// LibraryStore+Search — the S9.2 full-text search read (design §4).
//
// Queries the `tracks_fts` FTS5 index (maintained by LibraryStore+SearchIndex) and
// returns bm25-ranked track hits plus the deduped albums/artists those hits belong
// to (for the sectioned search-results UI). Like every read: actor-isolated,
// synchronous, Sendable returns, no filesystem access.
//
// Injection-safety lives in `ftsMatchQuery`: raw user input is reduced to
// alphanumeric tokens (stripping ALL FTS5 syntax specials) then wrapped as quoted
// prefix terms, so a query can never be a syntax error or an unintended full-table
// match — and an empty / all-punctuation query yields `.empty`, never everything.

import Foundation

/// The grouped result of a library search: bm25-ranked track hits plus the deduped
/// albums/artists those hits belong to (the sectioned Songs/Albums/Artists UI).
public struct SearchResults: Sendable {
    public let tracks: [LibraryTrackDisplay]
    public let albums: [AlbumFacet]
    public let artists: [ArtistFacet]

    /// The no-results value (empty/all-stripped query, or a query that matched nothing).
    public static let empty = SearchResults(tracks: [], albums: [], artists: [])

    public init(tracks: [LibraryTrackDisplay], albums: [AlbumFacet], artists: [ArtistFacet]) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
    }
}

public extension LibraryStore {
    /// The token characters — letters (incl. accented + CJK) and decimal digits. This
    /// deliberately mirrors what `unicode61` treats as token characters, and is TIGHTER
    /// than `CharacterSet.alphanumerics` (which also admits category No/Nl like "½"/"①"
    /// that `unicode61` would drop, yielding a zero-token phrase that can error).
    private static let ftsTokenCharacters = CharacterSet.letters.union(.decimalDigits)

    /// Build an FTS5 `MATCH` expression from raw user input, or `nil` when nothing
    /// searchable remains (→ empty results; never a full-table match, never a syntax
    /// error). The query is **split on non-token boundaries** — mirroring `unicode61`,
    /// so each maximal letters/digits run becomes its own term (e.g. "AC/DC" →
    /// `"ac"* "dc"*`, matching the index's `["ac","dc"]`; a whitespace-only strip would
    /// instead FUSE to "acdc" and never match). Each term is a quoted prefix; terms are
    /// implicit-ANDed. `unicode61 remove_diacritics 2` folds case + accents.
    internal static func ftsMatchQuery(for raw: String) -> String? {
        let tokens = raw.unicodeScalars
            .split(whereSeparator: { !ftsTokenCharacters.contains($0) })
            .map { String(String.UnicodeScalarView($0)) }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// The shared `MATCH` predicate text — ONE source of truth so `search()` and
    /// `searchMatchingIDs()` can never diverge on membership. FTS5's `MATCH` operator takes
    /// the FTS table by NAME (`tracks_fts`), never an alias.
    internal static let ftsMatchWhere = "WHERE tracks_fts MATCH ?"

    /// The IDs-only membership read behind the Songs "filter-preserves-sort" filter (S9.5
    /// §4, A2 LOCKED). It is `search()`'s predicate with EVERYTHING presentational removed:
    /// `SELECT rowid` (== `tracks.id`), NO `ORDER BY bm25`, NO `LIMIT`, and NO joins — so it
    /// touches neither `tracks` nor the artist/album joins, and can only ever return the SAME
    /// membership `search()` would. This ONE constant drives both the read and its EXPLAIN
    /// (no drift), and shares `ftsMatchWhere` with `search()`.
    internal static let searchMatchingIDsSQL = """
    SELECT rowid
    FROM tracks_fts
    \(LibraryStore.ftsMatchWhere);
    """

    /// Full-text search across track title/artist/album/genre. Returns bm25-ranked
    /// track hits (capped at `limit`) plus the deduped albums/artists the hits belong
    /// to, in first-hit order. An empty / all-stripped query yields `.empty`.
    ///
    /// The default cap is a BOUNDED 400 (S9.5 D4/OD-3): high enough that the incremental
    /// filter over a medium (~2k–20k) library shows a complete-feeling result set, low
    /// enough to stay off the scale cliff. `ftsMatchQuery`'s injection/diacritics/prefix
    /// behaviour is unchanged. Callers may still pass an explicit `limit`.
    func search(_ query: String, limit: Int = 400) throws -> SearchResults {
        guard let match = LibraryStore.ftsMatchQuery(for: query) else { return .empty }
        // NB: FTS5's MATCH operator + bm25() take the FTS table by NAME, not by alias —
        // `tracks_fts` is referenced unaliased (an alias trips "no such column"). This FROM
        // clause can't reuse `displayTracksSQL` (it starts from `tracks_fts`, not `tracks`),
        // so it interpolates the shared `displayArtistAlbumJoins` constant instead of
        // hand-rolling the join text — see that constant's doc for why (S9.5 §12.1 drift).
        let sql = """
        SELECT \(LibraryStore.displayTrackColumns)
        FROM tracks_fts
        JOIN tracks t ON t.id = tracks_fts.rowid
        \(LibraryStore.displayArtistAlbumJoins)
        \(LibraryStore.ftsMatchWhere)
        ORDER BY bm25(tracks_fts)
        LIMIT ?;
        """
        let tracks = try fetchDisplayTracks(sql) { statement in
            try statement.bind(match, at: 1)
            try statement.bind(Int64(max(0, limit)), at: 2)
        }
        guard !tracks.isEmpty else { return .empty }

        // Deduped albums/artists the hits belong to, preserving first-hit (bm25) order,
        // via the S9.1 single-facet reads. The id-0 unknown-artist sentinel is skipped.
        var albums: [AlbumFacet] = []
        var seenAlbums = Set<Int64>()
        var artists: [ArtistFacet] = []
        var seenArtists = Set<Int64>()
        for track in tracks {
            if let albumID = track.albumID, seenAlbums.insert(albumID).inserted,
               let facet = try album(id: albumID) {
                albums.append(facet)
            }
            if let artistID = track.artistID, artistID != unknownArtistID,
               seenArtists.insert(artistID).inserted, let facet = try artist(id: artistID) {
                artists.append(facet)
            }
        }
        return SearchResults(tracks: tracks, albums: albums, artists: artists)
    }

    /// The set of `tracks.id`s matching `query` — the IDs-only membership read behind the
    /// Songs "filter-preserves-sort" filter (S9.5 §4, A2 LOCKED). Reuses the SAME
    /// `ftsMatchQuery` sanitizer and the SAME `WHERE tracks_fts MATCH ?` predicate as
    /// `search()` (via `searchMatchingIDsSQL`), so the two can never diverge on membership;
    /// it differs ONLY by `SELECT rowid` (== `tracks.id`), no `ORDER BY bm25`, no `LIMIT`,
    /// and no joins.
    ///
    /// Junk / all-stripped input (`ftsMatchQuery → nil`) returns an EMPTY set — mirroring how
    /// `search()` yields `.empty` for the same input — NEVER all rows and never a throw for
    /// that reason. `nil` (i.e. "not filtering") is the CALLER's concept; this read only ever
    /// returns a concrete set. The ≥2-char gate is likewise the caller's job.
    func searchMatchingIDs(_ query: String) throws -> Set<Int64> {
        guard let match = LibraryStore.ftsMatchQuery(for: query) else { return [] }
        let statement = try connection.prepare(LibraryStore.searchMatchingIDsSQL)
        defer { statement.finalize() }
        try statement.bind(match, at: 1)
        var ids = Set<Int64>()
        while try statement.step() {
            ids.insert(statement.columnInt64(0))
        }
        return ids
    }

    /// The `EXPLAIN QUERY PLAN` `detail` rows for `searchMatchingIDs`, EXPLAINing the EXACT
    /// `searchMatchingIDsSQL` the read prepares (same constant, so no drift). The plan is
    /// independent of the (unbound) `MATCH` value. Diagnostic/verification hook (like
    /// `explainQueryPlan(for:)`/`explainAllTracksDisplayPlan`), NOT browse-facing: it lets the
    /// gate prove the membership read visits `tracks_fts` ONLY and never scans `tracks`.
    func explainSearchMatchingIDsPlan() throws -> [String] {
        try collectQueryPlan(LibraryStore.searchMatchingIDsSQL)
    }
}
