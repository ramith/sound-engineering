// LibraryTypes — the `Sendable` value types that cross the `LibraryStore` actor.
//
// S8.1b (design §4). These are the ONLY things allowed over the actor boundary —
// no `sqlite3*` handle, no `SQLiteConnection`/`SQLiteStatement` (none of which are
// `Sendable`) ever escapes. `LibraryTrack` is a superset of the app's `AudioFile`
// (same url/name/relativePath/format/duration) so S9 can browse from the store.
//
// All of these are value types (`struct`/`enum`) and explicitly `Sendable`; they
// carry only plain scalars, `String`, and `URL` (itself `Sendable`).

import CoreGraphics
import Foundation

// MARK: - Track (read model + the AudioFile superset)

/// A fully materialised library track row (the read model). Superset of the app's
/// `AudioFile`: it adds the stable `id`, the owning `folderID` (nil = loose), the
/// delta signature `(fileSize, mtime, inode)`, the S8.3 metadata fields, and the
/// artwork reference key. Reads NEVER assert filesystem existence (design §2a) —
/// `url` may point at a path that has since moved/changed/vanished.
public struct LibraryTrack: Sendable, Identifiable, Equatable {
    /// Stable durable reference identity (`tracks.id`) — never changes on move/retag.
    public let id: Int64
    /// Absolute file URL — the mutable natural key (`UNIQUE(url)`).
    public let url: URL
    /// Owning folder rowid, or `nil` for a loose track (`folder_id` NULL).
    public let folderID: Int64?
    /// Path relative to the owning scan root (empty for loose tracks).
    public let relativePath: String
    /// Track display name (filename without extension in S8.2).
    public let name: String
    /// Uppercased container format, e.g. "FLAC", "MP3".
    public let format: String
    /// File byte size — part of the delta signature.
    public let fileSize: Int64
    /// File modification time in WHOLE Unix seconds — part of the delta signature.
    public let mtime: Int64
    /// Filesystem inode (volume-local) — part of the move-signature, populated by
    /// the S8.2 scan; `nil` if the `lstat` failed.
    public let inode: Int64?
    /// Filesystem device id (`st_dev`) — the volume-scoping half of the move-
    /// signature (M-B), populated by the S8.2 scan; `nil` if the `lstat` failed.
    /// S8.4's move-matcher pairs it with `inode` to avoid cross-volume false hits.
    public let dev: Int64?
    /// Resolved album rowid (S8.3), or `nil`.
    public let albumID: Int64?
    /// Resolved track-artist rowid (S8.3), or `nil`.
    public let artistID: Int64?
    /// Tag title (S8.3), or `nil` — distinct from the filesystem `name`.
    public let title: String?
    /// Track number within its disc (S8.3), or `nil`.
    public let trackNo: Int?
    /// Disc number (S8.3), or `nil`.
    public let discNo: Int?
    /// Release year (S8.3), or `nil`.
    public let year: Int?
    /// Artwork content-hash reference key (S8.3), or `nil`.
    public let artworkKey: String?

    public init(
        id: Int64, url: URL, folderID: Int64?, relativePath: String, name: String,
        format: String, fileSize: Int64, mtime: Int64, inode: Int64?, dev: Int64?,
        albumID: Int64?, artistID: Int64?, title: String?, trackNo: Int?, discNo: Int?,
        year: Int?, artworkKey: String?
    ) {
        self.id = id
        self.url = url
        self.folderID = folderID
        self.relativePath = relativePath
        self.name = name
        self.format = format
        self.fileSize = fileSize
        self.mtime = mtime
        self.inode = inode
        self.dev = dev
        self.albumID = albumID
        self.artistID = artistID
        self.title = title
        self.trackNo = trackNo
        self.discNo = discNo
        self.year = year
        self.artworkKey = artworkKey
    }
}

// MARK: - Track display projection (S9.1 browse/search row — resolved names)

/// A browse/search row: a `Sendable` projection of a track with its artist and album
/// NAMES resolved by a SQL LEFT JOIN (added ALONGSIDE `LibraryTrack`, which carries
/// only `artistID`/`albumID`). A Songs/search row renders "Title · Artist · Album" from
/// this in ONE query — no N per-row name lookups. `title` is the display title (the tag
/// title, or the filename `name` when the tag title is absent/empty); `artistName` is
/// `COALESCE`d to '' (a track with no artist still yields a row), while `albumName`
/// stays a true optional (nil = no album). The UI never renders `relativePath` (design
/// §3.1). Reads never assert filesystem existence (§2a).
public struct LibraryTrackDisplay: Sendable, Identifiable, Equatable {
    /// Stable durable reference identity (`tracks.id`).
    public let id: Int64
    /// Absolute file URL — the mutable natural key.
    public let url: URL
    /// Display title: the tag title, falling back to the filename name if absent/empty.
    public let title: String
    /// Resolved track-artist rowid, or `nil`.
    public let artistID: Int64?
    /// Resolved track-artist name; "" when the track has no artist (COALESCE).
    public let artistName: String
    /// Resolved album rowid, or `nil`.
    public let albumID: Int64?
    /// Resolved album title, or `nil` when the track has no album.
    public let albumName: String?
    /// Uppercased container format, e.g. "FLAC", "MP3".
    public let format: String
    /// Track number within its disc, or `nil`.
    public let trackNo: Int?
    /// Duration in whole milliseconds (0 until decoded).
    public let durationMs: Int64

    /// Duration in seconds — the `AudioFile`-shaped convenience the UI consumes.
    public var durationSeconds: Double {
        Double(durationMs) / 1000.0
    }

    public init(
        id: Int64, url: URL, title: String, artistID: Int64?,
        artistName: String, albumID: Int64?, albumName: String?, format: String,
        trackNo: Int?, durationMs: Int64
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artistID = artistID
        self.artistName = artistName
        self.albumID = albumID
        self.albumName = albumName
        self.format = format
        self.trackNo = trackNo
        self.durationMs = durationMs
    }
}

// MARK: - Scanned file (write model — the scanner's product, S8.2)

/// A file as observed on disk by a scan (design §4). It is the WRITE model fed into
/// `upsert`/`addLooseFile`/`classify`; the store turns it into a `tracks` row. The
/// delta signature `(fileSize, mtime, inode)` is what `classify` diffs against the
/// stored row to decide new/modified/unchanged (S8.4 reconciliation building block).
public struct ScannedFile: Sendable, Equatable {
    /// Absolute file URL (normalised to the stored key form on write).
    public let url: URL
    /// Path relative to the owning scan root (empty for a loose file).
    public let relativePath: String
    /// Display name (filename without extension).
    public let name: String
    /// Uppercased container format.
    public let format: String
    /// File byte size (delta signature).
    public let fileSize: Int64
    /// Modification time in WHOLE Unix seconds (delta signature; design §3 discipline).
    public let mtime: Int64
    /// Filesystem inode (volume-local), or `nil` if unavailable (move-signature).
    public let inode: Int64?
    /// Filesystem device id (`st_dev`), or `nil` if unavailable. Completes the
    /// `(dev, inode, size, mtime)` move-signature (M-B); populated in S8.2.
    public let dev: Int64?

    public init(
        url: URL, relativePath: String = "", name: String, format: String,
        fileSize: Int64, mtime: Int64, inode: Int64? = nil, dev: Int64? = nil
    ) {
        self.url = url
        self.relativePath = relativePath
        self.name = name
        self.format = format
        self.fileSize = fileSize
        self.mtime = mtime
        self.inode = inode
        self.dev = dev
    }
}

// MARK: - Classify result (delta primitive — design §6 M2 / FS-2)

/// The result of classifying a `ScannedFile` against the store. Drives S8.4's
/// incremental reconciliation: `.new` → insert, `.modified` → update-in-place,
/// `.unchanged` → just refresh `last_seen_scan`. Per-field: a change to EITHER
/// `size` OR `mtime` yields `.modified` (M2).
public enum TrackDelta: Sendable, Equatable {
    /// No stored row for this `url` — a new track to insert.
    case new
    /// A stored row exists (`id`) and its `(size,mtime)` signature differs — modified.
    case modified(id: Int64)
    /// A stored row exists (`id`) and its signature is identical — unchanged.
    case unchanged(id: Int64)
}

// MARK: - Facets (S9 browse — synthetic fixtures in S8.1)

/// An album grid entry: the album row plus its resolved artist name and track count.
public struct AlbumFacet: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let title: String
    public let albumArtistID: Int64
    public let albumArtist: String
    public let year: Int
    public let trackCount: Int
    public let artworkKey: String?

    public init(
        id: Int64, title: String, albumArtistID: Int64, albumArtist: String,
        year: Int, trackCount: Int, artworkKey: String?
    ) {
        self.id = id
        self.title = title
        self.albumArtistID = albumArtistID
        self.albumArtist = albumArtist
        self.year = year
        self.trackCount = trackCount
        self.artworkKey = artworkKey
    }
}

/// An artist list entry: the artist row (id + resolved name).
public struct ArtistFacet: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

/// A genre list entry: the genre row plus its track count.
public struct GenreFacet: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let trackCount: Int

    public init(id: Int64, name: String, trackCount: Int) {
        self.id = id
        self.name = name
        self.trackCount = trackCount
    }
}

// MARK: - Folder (scan roots)

/// A `folders` row (design §4 `roots()`). Roots persist as plain absolute paths — no
/// security-scoped bookmark under the Developer-ID (non-sandboxed) posture.
public struct LibraryFolder: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let path: String

    public init(id: Int64, path: String) {
        self.id = id
        self.path = path
    }
}

// MARK: - Sort orders

/// Sort order for `allTracks(sortedBy:)`. Ordering is done in SQL (indexed columns).
public enum TrackSort: Sendable {
    /// By display name, locale-insensitive (SQLite `NOCASE`) — the S8.2 default.
    case name
    /// By resolved album then disc/track order (the album-detail order).
    case album
    /// By `date_added` descending (most-recent first) — a "recently added" view.
    case dateAddedDescending
}

/// Sort order for the facet queries (`albums`/`artists`).
public enum FacetSort: Sendable {
    /// Alphabetical by title/name (case-insensitive).
    case title
    /// By year ascending then title (albums); by name for artists.
    case year
}

// MARK: - Metadata write payload (S8.3 fills — provided now)

/// The tag metadata applied to a track in S8.3 (design §4 `applyMetadata`). The
/// store resolves album/artist/genre rows from these via the M1 total-album-key
/// query-then-insert so untagged albums collapse to one. Provided now so the write
/// path exists and is testable; S8.3 populates it from real tag extraction.
public struct TrackMetadata: Sendable, Equatable {
    /// Track title tag, or `nil`.
    public let title: String?
    /// Track-artist name, or `nil` (resolved/created in `artists`).
    public let artistName: String?
    /// Album title, or `nil` (defaults to the untagged sentinel handling in resolution).
    public let albumTitle: String?
    /// Album-artist name, or `nil` (defaults to the unknown-artist sentinel, id 0).
    public let albumArtistName: String?
    /// Release year, or `nil` (defaults to 0 = "unknown" in the total album key).
    public let year: Int?
    /// Track number, or `nil`.
    public let trackNo: Int?
    /// Disc number, or `nil`.
    public let discNo: Int?
    /// Genre names to attach via `track_genres`, or empty.
    public let genres: [String]
    /// Duration in whole milliseconds (0 if unknown).
    public let durationMs: Int64
    /// PCM sample rate in Hz, or `nil`.
    public let sampleRate: Int?
    /// PCM bit depth, or `nil`.
    public let bitDepth: Int?
    /// PCM channel count, or `nil`.
    public let channels: Int?

    public init(
        title: String? = nil, artistName: String? = nil, albumTitle: String? = nil,
        albumArtistName: String? = nil, year: Int? = nil, trackNo: Int? = nil,
        discNo: Int? = nil, genres: [String] = [], durationMs: Int64 = 0,
        sampleRate: Int? = nil, bitDepth: Int? = nil, channels: Int? = nil
    ) {
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.albumArtistName = albumArtistName
        self.year = year
        self.trackNo = trackNo
        self.discNo = discNo
        self.genres = genres
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
    }
}

// MARK: - Typed conflict (design §4, M6)

/// A typed `UNIQUE(url)` collision surfaced by `moveTrack`/`upsert`/`addLooseFile`
/// so callers can distinguish "a row already occupies that URL" (a duplicate,
/// normal per Req 5) from a generic SQLite failure. Carries, where known, the id of
/// the row that already holds the URL. `Sendable` — no handle.
public struct URLConflict: Error, Sendable, Equatable {
    /// The rowid of the pre-existing occupant, if it was looked up.
    public let existingID: Int64?

    public init(existingID: Int64?) {
        self.existingID = existingID
    }
}

// MARK: - Track user-state (reserved play_count / loved / rating)

/// A track's reserved user-authored state — the durable, `tracks.id`-keyed values
/// (play-count, loved, rating) that S9/S10 build on and that a move MUST preserve.
/// Returned by the `setUserState`/`userState` verification hooks so the S8.4 harness can
/// prove they survive a move (Gate-2). A value struct, not a tuple (lint: large_tuple).
public struct TrackUserState: Sendable, Equatable {
    public let playCount: Int64
    public let loved: Bool
    public let rating: Int64?

    public init(playCount: Int64, loved: Bool, rating: Int64?) {
        self.playCount = playCount
        self.loved = loved
        self.rating = rating
    }
}

// MARK: - Facet-orphan sweep counts (SF-2)

/// Per-table deletion counts from `sweepOrphanFacets` (S8.4 SF-2) — for logging and
/// harness assertions. A value struct, not a 3-tuple (lint: large_tuple).
public struct FacetSweepCounts: Sendable, Equatable {
    public let albums: Int
    public let artists: Int
    public let genres: Int

    public init(albums: Int, artists: Int, genres: Int) {
        self.albums = albums
        self.artists = artists
        self.genres = genres
    }
}

// MARK: - Artwork link (S8.3 — the cache→store descriptor)

/// A cached-artwork descriptor produced by `ArtworkCache` (S8.3, `LibraryScan`) and
/// consumed by the store's `applyExtractedResult`/`attachArtwork`. Defined HERE (in
/// `LibraryStore`) rather than in `LibraryScan` so the store can take it as a parameter
/// without a `LibraryStore → LibraryScan` dependency cycle. `Sendable` — scalars + a
/// `CGSize` (itself `Sendable`) only.
public struct ArtworkLink: Sendable, Equatable {
    /// sha256 (lowercase hex) of the ORIGINAL embedded image bytes — the dedup key and `artwork.content_hash`.
    public let contentHash: String
    /// On-disk path of the cached ORIGINAL image (the thumbnail path is derived from it).
    public let cachePath: String
    /// The original image's pixel dimensions (`.zero` if it could not be decoded).
    public let pixelSize: CGSize
    /// The original image's byte count.
    public let byteSize: Int64

    public init(contentHash: String, cachePath: String, pixelSize: CGSize, byteSize: Int64) {
        self.contentHash = contentHash
        self.cachePath = cachePath
        self.pixelSize = pixelSize
        self.byteSize = byteSize
    }
}
