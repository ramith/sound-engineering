// AlbumGrouping+Years — when the year tells albums apart (S10.8 C2 final round).
//
// The year is not an album's identity (C1): a compilation of tracks carrying their original years,
// or an album with one year-less bonus track, is ONE album. But taking it out entirely merged
// distinct albums, so it comes back as a SPLIT, only where a group visibly holds two albums:
//   • a TAGGED group spanning album folders whose dominant years differ splits per folder year —
//     Weezer's self-titled Blue (1994) and Green (2001) albums, both tagged "Weezer", or Thriller
//     (1982) and its 2008 anniversary edition. Folders that agree stay together (a disc folder the
//     fold missed), and a folder with no year joins the group's most common year;
//   • an UNTAGGED group (one album folder) by two or more primary artists in two or more years
//     splits per year — a flat folder holding Queen's 1981 and ABBA's 1992 "Greatest Hits" is two
//     albums, not one "Various Artists" album. One artist with mixed years stays one album, and a
//     year-less song joins the group's most common year;
//   • a COMPILATION — the flag, or a "Various Artists" album-artist tag — never splits: its tracks
//     carry their originals' years.
// Adoption (C3) is year-gated the same way: an untagged song adopts its folder-mates' one tag only
// when its year agrees with theirs, or either side has none.

import Foundation

public extension AlbumGrouping {
    /// The most common non-zero year (a tie → the LATEST — a compilation of originals came out no
    /// earlier than its newest track), or nil when no song has one. An album's shown year, and the
    /// year a split or an adoption is decided by.
    static func dominantYear(_ years: [Int?]) -> Int? {
        var counts: [Int: Int] = [:]
        for year in years.compactMap(nonZeroYear) {
            counts[year, default: 0] += 1
        }
        return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }

    /// A year tag that says something: nil for none or 0.
    static func nonZeroYear(_ year: Int?) -> Int? {
        guard let year, year > 0 else { return nil }
        return year
    }
}

extension AlbumGrouping {
    /// The year that tells a group's albums apart, per member in order — 0 for every member when the
    /// group is ONE album (file header). `taggedArtist` is the group's album-artist tag, nil for an
    /// untagged (one-folder) group.
    static func editionYears(of members: [YearMember], taggedArtist: String?) -> [Int] {
        let oneAlbum = [Int](repeating: 0, count: members.count)
        let taggedVarious = taggedArtist.map { sameArtistKey($0) == sameArtistKey(variousArtistsName) } ?? false
        guard !taggedVarious, !members.contains(where: \.isCompilation) else { return oneAlbum }
        let groupYear = dominantYear(members.map(\.year)) ?? 0
        if taggedArtist != nil {
            var folderYears: [String: [Int?]] = [:]
            for member in members {
                folderYears[member.folder, default: []].append(member.year)
            }
            let dominant = folderYears.mapValues(dominantYear)
            guard Set(dominant.values.compactMap(\.self)).count > 1 else { return oneAlbum }
            return members.map { (dominant[$0.folder] ?? nil) ?? groupYear }
        }
        guard Set(members.compactMap { nonZeroYear($0.year) }).count > 1,
              derivedArtist(anyCompilation: false, artists: members.map(\.artist)) == .various else { return oneAlbum }
        return members.map { nonZeroYear($0.year) ?? groupYear }
    }
}

/// What a year split reads of one group member.
struct YearMember {
    let folder: String
    let year: Int?
    let artist: String?
    let isCompilation: Bool

    init(_ song: some AlbumGroupingSong, folder: String) {
        self.folder = folder
        year = song.year
        artist = song.artistName
        isCompilation = song.isCompilation
    }
}

/// The tagged songs of one title in one album folder — what an untagged song there may adopt (C3).
struct TaggedPlace {
    private var tags: Set<String> = []
    private var years: [Int?] = []

    mutating func add(tag: String, year: Int?) {
        tags.insert(tag)
        years.append(year)
    }

    /// The tag an untagged song of this place adopts: the ONE tag every tagged song agrees on —
    /// when the song's year agrees with theirs, or either side has none. Else nil.
    func adoptedTag(forYear year: Int?) -> String? {
        guard tags.count == 1, let tag = tags.first else { return nil }
        guard let year = AlbumGrouping.nonZeroYear(year), let placeYear = AlbumGrouping.dominantYear(years) else {
            return tag
        }
        return year == placeYear ? tag : nil
    }
}
