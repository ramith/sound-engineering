// AlbumGrouping — which album a song belongs to, and who that album is credited to (S10.8 C2).
//
// ONE pure rule, used by the store's write path (`regroupAlbumsLocked`) AND by the verify
// harness's expectations, so the two can never fork. It AMENDS the S8.1 M1 total album key
// (docs/sprints/s8-1-persistent-store-design.md §3):
//   • a song WITH an album-artist tag keys on (title, tag, year) — folder-independent, as before;
//   • a song WITHOUT one keys on (title, year, album folder), so same-title albums in different
//     folders never merge (ALB-05) while a compilation in one folder stays one album (ALB-02);
//   • an untagged album is credited to "Various Artists" when any song carries the compilation
//     flag or its songs have two or more artists (decision 12), else to their one shared artist,
//     else to the id-0 "Unknown Artist" sentinel.
// The key stays TOTAL (M1): no component is ever NULL — year defaults to 0, and a tagged album's
// folder component is the empty string.

import Foundation

/// The credit on an album whose songs are a compilation or are by several artists — the SAME
/// artist row a "Various Artists" album-artist tag resolves to, so tagged and derived compilations
/// list under one artist.
public let variousArtistsName = "Various Artists"

/// The identity of one album (S10.8 C2): two songs share an album iff their keys are equal. The
/// store persists it as `albums(title, year, folder_key)` plus the resolved album artist.
public struct AlbumGroupKey: Hashable, Sendable {
    /// The album title tag (never empty).
    public let title: String
    /// The year tag, or 0 when absent (M1: the key stays total).
    public let year: Int
    /// The album-artist TAG, or nil — then the album is grouped by folder and its artist derived.
    public let taggedArtist: String?
    /// "" for a tagged album (folder-independent); the album folder otherwise (`albums.folder_key`).
    public let folderKey: String
}

/// Who an album WITHOUT an album-artist tag is credited to.
public enum DerivedAlbumArtist: Equatable {
    /// A compilation, or songs by two or more artists → "Various Artists" (decision 12).
    case various
    /// Every song with an artist has this one — spelled as the FIRST such song spells it.
    case shared(String)
    /// No song has an artist → the id-0 "Unknown Artist" sentinel.
    case unknown
}

/// The pure album-grouping rule (S10.8 C2). No store, no filesystem — paths are plain strings.
public enum AlbumGrouping {
    /// The album key for one song, or nil when it has no album title (it belongs to no album).
    /// `trackPath` is the song's stored (normalised) path; it only matters without a tag.
    public static func key(
        albumTitle: String?, albumArtistTag: String?, year: Int?, trackPath: String
    ) -> AlbumGroupKey? {
        guard let title = nonEmpty(albumTitle) else { return nil }
        let tag = nonEmpty(albumArtistTag)
        return AlbumGroupKey(
            title: title, year: year ?? 0, taggedArtist: tag,
            folderKey: tag == nil ? albumFolder(ofTrackPath: trackPath) : ""
        )
    }

    /// The album credit for an UNTAGGED album from its songs' artist names (in song order): any
    /// compilation flag, or two or more DIFFERENT artists (`sameArtistKey`) → `.various`; exactly
    /// one → `.shared` (the first song's spelling); none → `.unknown`. A song with no (or an empty)
    /// artist neither adds nor removes one (nine songs by X plus one untagged song → X).
    public static func derivedArtist(anyCompilation: Bool, artists: [String?]) -> DerivedAlbumArtist {
        if anyCompilation {
            return .various
        }
        let named = artists.compactMap { nonEmpty($0) }
        guard let first = named.first else { return .unknown }
        return Set(named.map(sameArtistKey)).count == 1 ? .shared(first) : .various
    }

    /// Two spellings are ONE artist for the credit when they differ only by Unicode normalisation
    /// (NFC vs NFD — "Zoë" typed vs read from a decomposed tag) or by case. Artist ROWS keep their
    /// exact spelling (S8 identity is untouched — those variants are still separate rows, a finding
    /// for later); this only stops such variants faking "mixed artists" → "Various Artists".
    public static func sameArtistKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The album folder of a song: the folder holding the file, except that a disc subfolder
    /// ("CD 1", "Disc 2", "disk03") folds into its parent — so a multi-disc set ripped one folder
    /// per disc is still one album.
    public static func albumFolder(ofTrackPath path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        guard isDiscFolderName((folder as NSString).lastPathComponent) else { return folder }
        return (folder as NSString).deletingLastPathComponent
    }

    /// The tag value when non-empty, else nil (an empty tag is no tag). The store writes the raw
    /// album columns through this too, so a stored title is never "".
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// "cd", "disc" or "disk", an optional space/-/_/. separator, then 1–3 digits; any case.
    static func isDiscFolderName(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard let prefix = ["disc", "disk", "cd"].first(where: { lower.hasPrefix($0) }) else { return false }
        let number = lower.dropFirst(prefix.count).drop { " -_.".contains($0) }
        return (1 ... 3).contains(number.count) && number.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
