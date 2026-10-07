// ChecksAlbumIdentity — the S10.8 C2 fix round, the album RULE (`AlbumGrouping`), each case driven
// through the real scan → metadata pass (`AlbumFixture`) and compared EXACTLY (title → credit × songs):
//   ALB-11 (C1) the year is not identity — a compilation whose tracks carry their original years,
//          and an album with a year-less bonus track, are each ONE album, shown with the most common
//          year (a tie → the latest); a tagged album with two years across folders is one;
//   ALB-12 (C2) disc and bonus folders fold into the album folder — every disc-folder spelling the
//          break-it found, plus "Bonus" / "Bonus Tracks" / "Extras"; look-alikes do not; a real album
//          titled "CD 1" still works;
//   ALB-13 (C3) mixed tagging — untagged songs adopt the one tag their folder-mates agree on; with
//          two tags in the folder they don't; a same-title song in ANOTHER folder never does;
//   ALB-14 (C4) one missing rule — a literal "Unknown Artist" album-artist tag is no tag (CD-ripper
//          "Unknown Album"s in two folders stay two), and an empty / whitespace artist is no artist;
//   ALB-15 (C5) normalised once — "Abbey Road " and "Abbey Road", NFC and NFD titles and tags, and
//          'Ann ' vs 'Ann' are the same bytes in the store — including through a single write;
//   ALB-16 (C6) featured artists — "Mara Lind" + "Mara Lind feat. X" is Mara Lind's album, the
//          artist rows keep their full names; two different primary artists are still "Various".

import Foundation
import LibraryStore

// MARK: - Registration

func albumIdentityCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "alb11-year-not-identity", run: checkYearIsNotIdentity),
        CheckCase(label: "alb12-disc-bonus-folders-fold", run: checkDiscAndBonusFoldersFold),
        CheckCase(label: "alb13-mixed-tagging-adopts", run: checkMixedTaggingAdopts),
        CheckCase(label: "alb14-one-missing-rule", run: checkOneMissingRule),
        CheckCase(label: "alb15-normalised-once", run: checkNormalisedOnce),
        CheckCase(label: "alb16-featured-artists", run: checkFeaturedArtists),
    ]
}

/// The shown year of the album titled `title` (nil when there is no such album, or several).
private func shownYear(_ store: LibraryStore, _ title: String) async throws -> Int? {
    let albums = try await store.albums().filter { $0.title == title }
    return albums.count == 1 ? albums[0].year : nil
}

// MARK: - ALB-11 (C1) — the year is not identity

func checkYearIsNotIdentity(number: Int, url: URL) async -> Bool {
    do {
        let fixture = try await AlbumFixture("alb11", url: url, songs: [
            song("C/o1.flac", songTags("Ann", album: "Oldies", year: 1965, compilation: true)),
            song("C/o2.flac", songTags("Bob", album: "Oldies", year: 1972, compilation: true)),
            song("C/o3.flac", songTags("Cat", album: "Oldies", year: 1981, compilation: true)),
            song("Y/y1.flac", songTags("Yan", album: "Years", year: 2001)),
            song("Y/y2.flac", songTags("Yan", album: "Years", year: 2001)),
            song("Y/bonus.flac", songTags("Yan", album: "Years")),
            song("M/m1.flac", songTags("Mo", album: "Mostly", year: 2003)),
            song("M/m2.flac", songTags("Mo", album: "Mostly", year: 2001)),
            song("M/m3.flac", songTags("Mo", album: "Mostly", year: 2003)),
            song("T/A/t1.flac", songTags("Tess", album: "Tagged", year: 1999, albumArtist: "Tess")),
            song("T/B/t2.flac", songTags("Tess", album: "Tagged", year: 2009, albumArtist: "Tess")),
        ])
        let store = fixture.store
        guard try await expectAlbums(store, [
            "Oldies": ["\(variousArtistsName) ×3"], "Years": ["Yan ×3"], "Mostly": ["Mo ×3"], "Tagged": ["Tess ×2"],
        ], "years within one album", number: number) else { return false }
        let years = try await ["Oldies", "Years", "Mostly", "Tagged"].asyncYears(store)
        guard years == [1981, 2001, 2003, 2009] else {
            printFail(number, "ALB-11: shown years \(years), expected [1981, 2001, 2003, 2009] (the most common; "
                + "a tie → the latest)")
            return false
        }
        printPass(number, "ALB-11 (C1) the year is not identity: a compilation of original years, an album with a "
            + "year-less bonus track and a tagged album with two years across folders are each ONE album, "
            + "shown with the most common non-zero year (a tie → the latest)")
        return true
    } catch {
        printFail(number, "ALB-11 threw: \(error)"); return false
    }
}

private extension [String] {
    /// The shown year of each title, in order (-1 when not exactly one album has it).
    func asyncYears(_ store: LibraryStore) async throws -> [Int] {
        var years: [Int] = []
        for title in self {
            try await years.append(shownYear(store, title) ?? -1)
        }
        return years
    }
}

// MARK: - ALB-12 (C2) — disc and bonus folders fold into the album folder

/// Folder names that fold into their parent, and look-alikes that do not.
private let foldedFolderNames = [
    "CD 1", "Disc2", "disk 003", "cd-1", "Disc 1 of 2", "CD1 - Live", "Disc One", "[CD 1]", "Disc 1 - The Hits",
    "Disc #1", "Disc 1 (Remastered)", "CD 01", "(Disc 2)", "Bonus", "Bonus Tracks", "Extras",
]
private let keptFolderNames = ["CD Collection", "Discography", "CD 1234", "Disco Hits", "CDs", "Disc 1a", "Bonus Round"]

func checkDiscAndBonusFoldersFold(number: Int, url: URL) async -> Bool {
    do {
        let folds = { (name: String) in AlbumGrouping.albumFolder(ofTrackPath: "/M/Set/\(name)/a.flac") == "/M/Set" }
        for name in foldedFolderNames where !folds(name) {
            printFail(number, "ALB-12: '\(name)' did not fold into its album folder"); return false
        }
        for name in keptFolderNames where folds(name) {
            printFail(number, "ALB-12: '\(name)' folded into its parent, but it is an album folder of its own")
            return false
        }
        var songs: [SongSpec] = []
        for (index, name) in foldedFolderNames.enumerated() {
            songs.append(song("Sets/Set\(index)/\(name)/d\(index).flac", songTags("Dee", album: "Set \(index)")))
            songs.append(song("Sets/Set\(index)/top\(index).flac", songTags("Dee", album: "Set \(index)")))
        }
        // A real album titled "CD 1" (its own folder) next to another album: still two albums.
        songs += [
            song("X/CD 1/x1.flac", songTags("Xan", album: "CD 1")),
            song("X/CD 1/x2.flac", songTags("Xan", album: "CD 1")),
            song("X/Other/o1.flac", songTags("Xan", album: "Other")),
        ]
        let fixture = try await AlbumFixture("alb12", url: url, songs: songs)
        var expected: [String: [String]] = ["CD 1": ["Xan ×2"], "Other": ["Xan ×1"]]
        for index in foldedFolderNames.indices {
            expected["Set \(index)"] = ["Dee ×2"]
        }
        guard try await expectAlbums(fixture.store, expected, "disc and bonus folders", number: number) else {
            return false
        }
        printPass(number, "ALB-12 (C2) disc and bonus folders fold into the album folder: \(foldedFolderNames.count) "
            + "spellings ('Disc 1 of 2', 'CD1 - Live', 'Disc One', '[CD 1]', 'Disc #1', 'CD 01', 'Bonus Tracks', "
            + "'Extras' …) each keep their set ONE album; look-alikes ('CD Collection', 'Discography', 'CD 1234' "
            + "…) stay their own folder; a real album titled 'CD 1' still groups")
        return true
    } catch {
        printFail(number, "ALB-12 threw: \(error)"); return false
    }
}

// MARK: - ALB-13 (C3) — mixed tagging

func checkMixedTaggingAdopts(number: Int, url: URL) async -> Bool {
    do {
        var songs = (1 ... 9).map {
            song("Band/Album/m\($0).flac", songTags("Band", album: "Mixed", albumArtist: "Band"))
        }
        songs += [
            song("Band/Album/m10.flac", songTags("Band", album: "Mixed")),
            // The same title in ANOTHER folder never adopts the tag.
            song("Elsewhere/Album/e1.flac", songTags("Eve", album: "Mixed")),
            // Two tags in one folder: no adoption — the untagged song keeps its own (folder) album.
            song("Split/Album/s1.flac", songTags("Ann", album: "Split", albumArtist: "Ann")),
            song("Split/Album/s2.flac", songTags("Bob", album: "Split", albumArtist: "Bob")),
            song("Split/Album/s3.flac", songTags("Cy", album: "Split")),
            // A compilation: every song flagged, the VA tag on only some.
            song("Comp/Album/q1.flac",
                 songTags("Ann", album: "PartTag", albumArtist: variousArtistsName, compilation: true)),
            song("Comp/Album/q2.flac", songTags("Bob", album: "PartTag", compilation: true)),
        ]
        let fixture = try await AlbumFixture("alb13", url: url, songs: songs)
        guard try await expectAlbums(fixture.store, [
            "Mixed": ["Band ×10", "Eve ×1"], "Split": ["Ann ×1", "Bob ×1", "Cy ×1"],
            "PartTag": ["\(variousArtistsName) ×2"],
        ], "mixed tagging", number: number) else { return false }
        printPass(number, "ALB-13 (C3) mixed tagging: an untagged song adopts the one album-artist tag its "
            + "folder-mates on that title agree on (9 tagged + 1 untagged = ONE album; a partly VA-tagged "
            + "compilation = one); with two tags in the folder it does not; another folder never adopts")
        return true
    } catch {
        printFail(number, "ALB-13 threw: \(error)"); return false
    }
}

// MARK: - ALB-14 (C4) — one missing rule

func checkOneMissingRule(number: Int, url: URL) async -> Bool {
    do {
        for spelling in [unknownArtistName, "unknown artist", "  UNKNOWN ARTIST ", "", "   ", "\n"]
            where AlbumGrouping.presentArtist(spelling) != nil {
            printFail(number, "ALB-14: '\(spelling)' is not treated as a missing artist"); return false
        }
        let fixture = try await AlbumFixture("alb14", url: url, songs: [
            // CD rips: a literal "Unknown Artist" album-artist tag in two folders — two albums.
            song("Rip1/r1.flac", songTags("Ann", album: "Unknown Album", albumArtist: unknownArtistName)),
            song("Rip1/r2.flac", songTags("Ann", album: "Unknown Album", albumArtist: "unknown artist")),
            song("Rip2/r3.flac", songTags("Bob", album: "Unknown Album", albumArtist: unknownArtistName)),
            // A whitespace album-artist tag is no tag; empty / whitespace artists are no artist.
            song("Blank/b1.flac", songTags("Ann", album: "Blank", albumArtist: "   ")),
            song("Blank/b2.flac", songTags("   ", album: "Blank")),
            song("Blank/b3.flac", songTags("", album: "Blank")),
        ])
        guard try await expectAlbums(fixture.store, [
            "Unknown Album": ["Ann ×2", "Bob ×1"], "Blank": ["Ann ×3"],
        ], "the missing rule", number: number) else { return false }
        printPass(number, "ALB-14 (C4) one missing rule: a literal 'Unknown Artist' album-artist tag (any case) is "
            + "no tag, so CD-ripper 'Unknown Album's in two folders stay two albums; empty / whitespace artists "
            + "and album artists are missing too — the same AlbumGrouping.presentArtist for both")
        return true
    } catch {
        printFail(number, "ALB-14 threw: \(error)"); return false
    }
}

// MARK: - ALB-15 (C5) — normalised once

func checkNormalisedOnce(number: Int, url: URL) async -> Bool {
    let cafeNFC = "Caf\u{00E9}", cafeNFD = "Cafe\u{0301}"
    let zoeNFC = "Zo\u{00EB}", zoeNFD = "Zoe\u{0308}"
    do {
        let fixture = try await AlbumFixture("alb15", url: url, songs: [
            song("Abbey/a1.flac", songTags("The Beatles", album: "Abbey Road ")),
            song("Abbey/a2.flac", songTags("The Beatles", album: "Abbey Road")),
            song("Cafe/c1.flac", songTags("Ann", album: cafeNFC)),
            song("Cafe/c2.flac", songTags("Ann", album: cafeNFD)),
            song("Tag/t1.flac", songTags("Ann", album: "TagNorm", albumArtist: zoeNFC)),
            song("Tag/t2.flac", songTags("Ann", album: "TagNorm", albumArtist: zoeNFD)),
            song("Space/s1.flac", songTags("Ann ", album: "Space")),
            song("Space/s2.flac", songTags("Ann", album: "Space")),
        ])
        let store = fixture.store
        let expected: [String: [String]] = [
            "Abbey Road": ["The Beatles ×2"], cafeNFC: ["Ann ×2"], "TagNorm": ["\(zoeNFC) ×2"], "Space": ["Ann ×2"],
        ]
        guard try await expectAlbums(store, expected, "normalised tags", number: number) else { return false }
        // A single write of the NFD title keeps ONE album, and the store holds the NFC bytes.
        guard let nfdSong = try await store.track(url: fixture.fileURL("Cafe/c2.flac")) else { return false }
        try await store.applyMetadata(songTags("Ann", album: cafeNFD), forTrack: nfdSong.id)
        let cafe = try await store.albums().filter { $0.title == cafeNFC }
        guard try await expectAlbums(store, expected, "after a single NFD write", number: number),
              cafe.count == 1, cafe[0].title.unicodeScalars.elementsEqual(cafeNFC.unicodeScalars) else {
            printFail(number, "ALB-15: the album title is not stored as NFC bytes"); return false
        }
        printPass(number, "ALB-15 (C5) normalised once (TrackMetadata.init): 'Abbey Road ' and 'Abbey Road', an "
            + "NFC and an NFD title, an NFC and an NFD album-artist tag, and 'Ann ' vs 'Ann' are each ONE album "
            + "(not Various Artists) — through the pass and a single write; the store holds NFC bytes")
        return true
    } catch {
        printFail(number, "ALB-15 threw: \(error)"); return false
    }
}

// MARK: - ALB-16 (C6) — featured artists

func checkFeaturedArtists(number: Int, url: URL) async -> Bool {
    do {
        let fixture = try await AlbumFixture("alb16", url: url, songs: [
            song("Mara/One/m1.flac", songTags("Mara Lind", album: "Duets")),
            song("Mara/One/m2.flac", songTags("Mara Lind feat. Ola", album: "Duets")),
            song("Mara/Two/n1.flac", songTags("Mara Lind ft. Ola", album: "Guests")),
            song("Mara/Two/n2.flac", songTags("Mara Lind (featuring Per)", album: "Guests")),
            song("Mixed/Up/u1.flac", songTags("Ann", album: "Mixed Up")),
            song("Mixed/Up/u2.flac", songTags("Bob feat. Ann", album: "Mixed Up")),
        ])
        let store = fixture.store
        guard try await expectAlbums(store, [
            "Duets": ["Mara Lind ×2"], "Guests": ["Mara Lind ×2"], "Mixed Up": ["\(variousArtistsName) ×2"],
        ], "featured artists", number: number) else { return false }
        let names = try await Set(store.artists().map(\.name))
        guard names.isSuperset(of: ["Mara Lind", "Mara Lind feat. Ola", "Mara Lind ft. Ola", "Bob feat. Ann"]) else {
            printFail(number, "ALB-16: the track artist rows lost their full names: \(names.sorted())"); return false
        }
        printPass(number, "ALB-16 (C6) featured artists: 'Mara Lind' + 'Mara Lind feat. Ola' is Mara Lind's album, "
            + "and 'Mara Lind ft. Ola' + 'Mara Lind (featuring Per)' too (the primary artist's row); 'Ann' + "
            + "'Bob feat. Ann' is still \(variousArtistsName); the artist rows keep their full names")
        return true
    } catch {
        printFail(number, "ALB-16 threw: \(error)"); return false
    }
}
