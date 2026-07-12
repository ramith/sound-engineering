// LibraryStore+Search — the S9.2 full-text search read (design §4), GRDB-backed.
//
// Queries the `tracks_fts` FTS5 index (maintained by LibraryStore+SearchIndex) and returns
// bm25-ranked track hits plus the deduped albums/artists those hits belong to (for the
// sectioned search-results UI). One `dbWriter.read` snapshot covers the hits AND the facet
// resolution, so the sections are consistent.
//
// Injection-safety lives in `ftsMatchQuery`: raw user input is reduced to alphanumeric tokens
// (stripping ALL FTS5 syntax specials) then wrapped as quoted prefix terms, so a query can
// never be a syntax error or an unintended full-table match — and an empty / all-punctuation
// query yields `.empty`, never everything.

import Foundation
import GRDB

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
    /// The token characters — letters (incl. accented + CJK) and decimal digits. Mirrors what
    /// `unicode61` treats as token characters, and is TIGHTER than `CharacterSet.alphanumerics`.
    private static let ftsTokenCharacters = CharacterSet.letters.union(.decimalDigits)

    /// Build an FTS5 `MATCH` expression from raw user input, or `nil` when nothing searchable
    /// remains (→ empty results; never a full-table match, never a syntax error). Split on
    /// non-token boundaries (mirroring `unicode61`), each maximal run a quoted prefix term;
    /// terms are implicit-ANDed. `unicode61 remove_diacritics 2` folds case + accents.
    internal static func ftsMatchQuery(for raw: String) -> String? {
        let tokens = raw.unicodeScalars
            .split(whereSeparator: { !ftsTokenCharacters.contains($0) })
            .map { String(String.UnicodeScalarView($0)) }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// The shared `MATCH` predicate text — ONE source of truth so `search()` and
    /// `searchMatchingIDs()` can never diverge. FTS5's `MATCH` takes the FTS table by NAME.
    internal static let ftsMatchWhere = "WHERE tracks_fts MATCH ?"

    /// The IDs-only membership read behind the Songs "filter-preserves-sort" filter (S9.5 §4,
    /// A2 LOCKED): `search()`'s predicate with EVERYTHING presentational removed — `SELECT rowid`
    /// (== `tracks.id`), NO `ORDER BY bm25`, NO `LIMIT`, NO joins.
    internal static let searchMatchingIDsSQL = """
    SELECT rowid
    FROM tracks_fts
    \(LibraryStore.ftsMatchWhere);
    """

    /// The bm25-ranked track-hit read behind `search()`. FTS5's `MATCH` + `bm25()` take the FTS
    /// table by NAME (not alias), so this FROM starts at `tracks_fts` and can't reuse
    /// `displayTracksSQL`; it interpolates the shared `displayTrackColumns`/`displayArtistAlbumJoins`
    /// /`ftsMatchWhere` constants so the projection + joins live in ONE place.
    private static let searchTracksSQL = """
    SELECT \(LibraryStore.displayTrackColumns)
    FROM tracks_fts
    JOIN tracks t ON t.id = tracks_fts.rowid
    \(LibraryStore.displayArtistAlbumJoins)
    \(LibraryStore.ftsMatchWhere)
    ORDER BY bm25(tracks_fts)
    LIMIT ?;
    """

    /// Full-text search across track title/artist/album/genre. Returns bm25-ranked track hits
    /// (capped at `limit`, default a bounded 400) plus the deduped albums/artists the hits
    /// belong to, in first-hit order. An empty / all-stripped query yields `.empty`.
    func search(_ query: String, limit: Int = 400) async throws -> SearchResults {
        guard let match = LibraryStore.ftsMatchQuery(for: query) else { return .empty }
        return try await dbWriter.read { db in
            let tracks = try LibraryTrackDisplay.fetchAll(
                db, sql: LibraryStore.searchTracksSQL, arguments: [match, Int64(max(0, limit))]
            )
            guard !tracks.isEmpty else { return .empty }

            // Deduped albums/artists the hits belong to, preserving first-hit (bm25) order, via
            // the SAME shared facet builders as the single-facet reads. The id-0 sentinel skipped.
            var albums: [AlbumFacet] = []
            var seenAlbums = Set<Int64>()
            var artists: [ArtistFacet] = []
            var seenArtists = Set<Int64>()
            for track in tracks {
                if let albumID = track.albumID, seenAlbums.insert(albumID).inserted,
                   let facet = try Self.fetchAlbums(
                       db, whereClause: "WHERE al.id = ?", order: LibraryStore.albumTitleOrder,
                       limited: false, arguments: [albumID]
                   ).first {
                    albums.append(facet)
                }
                if let artistID = track.artistID, artistID != unknownArtistID,
                   seenArtists.insert(artistID).inserted,
                   let facet = try Self.fetchArtists(
                       db, extraWhere: "AND ar.id = ?", order: LibraryStore.artistNameOrder,
                       limited: false, arguments: [artistID]
                   ).first {
                    artists.append(facet)
                }
            }
            return SearchResults(tracks: tracks, albums: albums, artists: artists)
        }
    }

    /// The set of `tracks.id`s matching `query` — the IDs-only membership read behind the Songs
    /// filter (S9.5 §4). Reuses the SAME `ftsMatchQuery` sanitizer and `searchMatchingIDsSQL`
    /// predicate as `search()`, so the two can never diverge on membership. Junk / all-stripped
    /// input returns an EMPTY set, never all rows and never a throw.
    func searchMatchingIDs(_ query: String) async throws -> Set<Int64> {
        guard let match = LibraryStore.ftsMatchQuery(for: query) else { return [] }
        return try await dbWriter.read { db in
            try Int64.fetchSet(db, sql: LibraryStore.searchMatchingIDsSQL, arguments: [match])
        }
    }

    /// The `EXPLAIN QUERY PLAN` `detail` rows for `searchMatchingIDs` (same `searchMatchingIDsSQL`
    /// constant, so no drift). Diagnostic/verification hook: proves the membership read visits
    /// `tracks_fts` ONLY and never scans `tracks`.
    func explainSearchMatchingIDsPlan() async throws -> [String] {
        try await dbWriter.read { db in try Self.collectQueryPlan(db, LibraryStore.searchMatchingIDsSQL) }
    }
}
