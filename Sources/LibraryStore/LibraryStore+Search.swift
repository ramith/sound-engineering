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
        // `tracks_fts` is referenced unaliased (an alias trips "no such column").
        let sql = """
        SELECT \(LibraryStore.displayTrackColumns)
        FROM tracks_fts
        JOIN tracks t ON t.id = tracks_fts.rowid
        LEFT JOIN artists ar ON ar.id = t.artist_id
        LEFT JOIN albums  al ON al.id = t.album_id
        WHERE tracks_fts MATCH ?
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
}
