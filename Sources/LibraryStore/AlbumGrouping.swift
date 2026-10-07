// AlbumGrouping — which album a song belongs to, and who that album is credited to (S10.8 C2).
//
// ONE pure rule, used by the store's write path (`LibraryStore+AlbumGrouping`) AND by the verify
// harness's expectations, so the two can never fork. It AMENDS the S8.1 M1 total album key
// (docs/sprints/s8-1-persistent-store-design.md §3) the way Apple Music groups a library:
//   • IDENTITY — a song WITH an album-artist tag is on (title, tag), in any folder; a song WITHOUT
//     one is on (title, album folder), so same-title albums in different folders never merge
//     (ALB-05) while a compilation in one folder stays one album (ALB-02). The YEAR is not part of
//     identity (C2 fix round, C1): a compilation whose tracks carry their original years, or an
//     album with one year-less bonus track, stays ONE album, shown with its most common year.
//   • ALBUM FOLDER — the file's folder, with disc and bonus subfolders ("CD 1", "Disc 2 of 2",
//     "[CD 1]", "Bonus Tracks", "Extras" …) folded into their parent (`albumFolder`, C2).
//   • MIXED TAGGING — in one album folder, untagged songs whose title matches tagged songs that
//     all agree on ONE tag adopt that tag (C3): one album, not twin tiles.
//   • CREDIT of an untagged album — "Various Artists" when any song carries the compilation flag
//     or its songs have two or more PRIMARY artists (decision 12; "X feat. Y" counts as X — C6),
//     else their one shared artist, else the id-0 "Unknown Artist" sentinel.
//   • MISSING — an empty, whitespace-only or literal "Unknown Artist" artist or album artist is
//     no artist at all (`presentArtist`, C4): one rule for both.
//   • NORMALISED ONCE — `TrackMetadata.init` trims + NFC-normalises the album title, the
//     album-artist tag and the artist (`normalizedTag` / `presentArtist`, C5), so the store's SQL
//     compares the same bytes Swift does.
// The key stays TOTAL (M1): no component is ever NULL — a tagged album's folder key is "".
// The names and folders half of the rule lives in `AlbumGrouping+Names.swift`.

import Foundation

/// The credit on an album whose songs are a compilation or are by several artists — the SAME
/// artist row a "Various Artists" album-artist tag resolves to, so tagged and derived compilations
/// list under one artist.
public let variousArtistsName = "Various Artists"

/// The identity of one album (S10.8 C2): two songs share an album iff their keys are equal. The
/// store persists it as `albums(title, album_artist_id, folder_key)`.
public struct AlbumGroupKey: Hashable, Sendable {
    /// The album title tag (never empty).
    public let title: String
    /// The album-artist TAG (the song's own, or the one it adopted — C3), or nil: then the album is
    /// grouped by folder and its artist derived.
    public let taggedArtist: String?
    /// "" for a tagged album (folder-independent); the album folder otherwise (`albums.folder_key`).
    public let folderKey: String
}

/// What the grouping rule reads of one song. The store's grouping row conforms, so the rule runs
/// on exactly the columns the store keeps.
public protocol AlbumGroupingSong {
    /// The album title as stored (normalised at write — C5), or nil: the song is on no album.
    var albumTitle: String? { get }
    /// The album-artist tag as stored (normalised, never "missing" — C4/C5), or nil.
    var albumArtistTag: String? { get }
    /// The song's stored (normalised) path — only its album folder matters.
    var path: String { get }
}

/// Who an album WITHOUT an album-artist tag is credited to.
public enum DerivedAlbumArtist: Equatable {
    /// A compilation, or songs by two or more primary artists → "Various Artists" (decision 12).
    case various
    /// Every song with an artist is by this one — spelled as the FIRST such song spells it.
    case shared(String)
    /// No song has an artist → the id-0 "Unknown Artist" sentinel.
    case unknown
}

/// One album member's display inputs — what decides the album's shown year and cover.
public struct AlbumMemberDisplay: Sendable {
    public let songID: Int64
    public let year: Int?
    public let discNo: Int?
    public let trackNo: Int?
    public let artworkKey: String?

    public init(songID: Int64, year: Int?, discNo: Int?, trackNo: Int?, artworkKey: String?) {
        self.songID = songID
        self.year = year
        self.discNo = discNo
        self.trackNo = trackNo
        self.artworkKey = artworkKey
    }
}

/// What an album SHOWS (not its identity): its year and its cover.
public struct AlbumDisplay: Equatable, Sendable {
    /// The most common non-zero year of its songs, or 0 when none has one.
    public let year: Int
    /// The cover of its first song (lowest disc, then track number) that has art, or nil.
    public let artworkKey: String?

    public init(year: Int, artworkKey: String?) {
        self.year = year
        self.artworkKey = artworkKey
    }
}

/// The pure album-grouping rule (S10.8 C2). No store, no filesystem — paths are plain strings.
public enum AlbumGrouping {
    /// The album key of every song, in order (nil = the song has no album title, so no album).
    /// Takes the whole set at once because mixed tagging (C3) looks at a song's folder-mates:
    /// an untagged song adopts the tag of the same-title songs in its album folder when they all
    /// agree on one.
    public static func keys(for songs: [some AlbumGroupingSong]) -> [AlbumGroupKey?] {
        let folders = songs.map { albumFolder(ofTrackPath: $0.path) }
        var tagsInPlace: [AlbumPlace: Set<String>] = [:]
        for (song, folder) in zip(songs, folders) {
            if let title = song.albumTitle, let tag = song.albumArtistTag {
                tagsInPlace[AlbumPlace(title: title, folder: folder), default: []].insert(tag)
            }
        }
        return zip(songs, folders).map { song, folder in
            guard let title = song.albumTitle else { return nil }
            let tags = tagsInPlace[AlbumPlace(title: title, folder: folder)]
            if let tag = song.albumArtistTag ?? (tags?.count == 1 ? tags?.first : nil) {
                return AlbumGroupKey(title: title, taggedArtist: tag, folderKey: "")
            }
            return AlbumGroupKey(title: title, taggedArtist: nil, folderKey: folder)
        }
    }

    /// The album credit for an UNTAGGED album from its songs' artist names (in song order): any
    /// compilation flag → `.various`; one artist (`sameArtistKey`) → `.shared` (the first song's
    /// spelling); one PRIMARY artist across "X" / "X feat. Y" (C6) → `.shared(X)`; two or more →
    /// `.various`; none → `.unknown`. A missing artist (C4) neither adds nor removes one (nine
    /// songs by X plus one untagged song → X).
    public static func derivedArtist(anyCompilation: Bool, artists: [String?]) -> DerivedAlbumArtist {
        if anyCompilation {
            return .various
        }
        let named = artists.compactMap(presentArtist)
        guard let first = named.first else { return .unknown }
        if Set(named.map(sameArtistKey)).count == 1 {
            return .shared(first)
        }
        let primaries = named.map(primaryArtist)
        return Set(primaries.map(sameArtistKey)).count == 1 ? .shared(primaries[0]) : .various
    }

    /// What an album shows (C1, C8): its songs' most common non-zero year (a tie goes to the
    /// LATEST — a compilation of originals came out no earlier than its newest track; 0 when no
    /// song has a year), and the cover of its first song with art in (disc, track) order — so the
    /// cover never depends on which file happened to be read first.
    public static func display(of members: [AlbumMemberDisplay]) -> AlbumDisplay {
        var counts: [Int: Int] = [:]
        for year in members.compactMap(\.year) where year > 0 {
            counts[year, default: 0] += 1
        }
        let year = counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0
        let cover = members.filter { $0.artworkKey != nil }.min(by: precedesForCover)?.artworkKey
        return AlbumDisplay(year: year, artworkKey: cover)
    }

    /// Album order for the cover: a missing disc reads as disc 1, a song without a track number
    /// comes after the numbered ones, and the song id breaks ties.
    private static func precedesForCover(_ lhs: AlbumMemberDisplay, _ rhs: AlbumMemberDisplay) -> Bool {
        (lhs.discNo ?? 1, lhs.trackNo == nil ? 1 : 0, lhs.trackNo ?? 0, lhs.songID)
            < (rhs.discNo ?? 1, rhs.trackNo == nil ? 1 : 0, rhs.trackNo ?? 0, rhs.songID)
    }
}

/// One album title within one album folder — where mixed tagging (C3) compares tags.
private struct AlbumPlace: Hashable {
    let title: String
    let folder: String
}
