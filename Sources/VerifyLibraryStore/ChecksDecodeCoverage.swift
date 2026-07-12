// ChecksDecodeCoverage — GRDB `FetchableRecord` positional-decode guards (GRDB rewrite).
//
// The value types now decode via hand-written positional `init(row:)` mappers against fixed
// SELECT column orders (`trackColumns`, `displayTrackColumns`, `albumSelectSQL`, …). A wrong
// index silently mis-maps a same-typed column and every other assertion still passes. SS3
// (ChecksSongsSort) already guards the 22-column `LibraryTrackDisplay`; these add the missing
// full-field guards for `LibraryTrack` (M-5) and `ArtistFacet.artworkKey` (N-3).

import Foundation
import LibraryStore

func decodeCoverageCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "dc1-librarytrack-decode", run: checkLibraryTrackFullDecode),
        CheckCase(label: "dc2-artistfacet-artwork", run: checkArtistFacetArtworkKey),
    ]
}

/// DC1 (M-5): every `LibraryTrack` field decodes from the correct column. Seed a track with
/// DISTINCT values across the same-typed fields (so a positional swap in `trackColumns` — e.g.
/// fileSize↔mtime, inode↔dev, albumID↔artistID — is caught), enrich it, then read it back and
/// assert each field.
func checkLibraryTrackFullDecode(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/DC"))
        let gen = try await store.beginScanGeneration()
        let path = "/Music/DC/sub/decode.flac"
        let seed = ScannedFile(
            url: URL(fileURLWithPath: path), relativePath: "sub/decode.flac", name: "decode",
            format: "FLAC", fileSize: 111_111, mtime: 222_222, inode: 333_333, dev: 444_444
        )
        let ids = try await store.upsert([seed], folderID: root, generation: gen)
        guard let trackID = ids.first else { printFail(number, "DC1: seed failed"); return false }
        // Enrich with distinct metadata + an artwork key in ONE transaction.
        try await store.applyExtractedResult(
            trackID: trackID,
            meta: TrackMetadata(
                title: "Decode Title", artistName: "Decode Artist", albumTitle: "Decode Album",
                year: 1999, trackNo: 5, discNo: 6
            ),
            artwork: ArtworkLink(contentHash: "decodehash", cachePath: "/cache/decodehash.jpg",
                                 pixelSize: .zero, byteSize: 4096),
            generation: gen
        )
        guard let track = try await store.track(id: trackID) else {
            printFail(number, "DC1: track(id:) returned nil after enrich"); return false
        }
        let key = PathNormalizer.normalizedString(for: URL(fileURLWithPath: path))
        // Data-driven field checks (a flat list of (ok, label) — no per-field branching, so the
        // decode guard stays within the cyclomatic-complexity budget as fields are added).
        let fieldChecks: [(ok: Bool, label: String)] = [
            (track.id == trackID, "id=\(track.id)"),
            (PathNormalizer.normalizedString(for: track.url) == key, "url=\(track.url.path)"),
            (track.folderID == root, "folderID=\(String(describing: track.folderID))"),
            (track.relativePath == "sub/decode.flac", "relativePath=\(track.relativePath)"),
            (track.name == "decode", "name=\(track.name)"),
            (track.format == "FLAC", "format=\(track.format)"),
            (track.fileSize == 111_111, "fileSize=\(track.fileSize)"),
            (track.mtime == 222_222, "mtime=\(track.mtime)"),
            (track.inode == 333_333, "inode=\(String(describing: track.inode))"),
            (track.dev == 444_444, "dev=\(String(describing: track.dev))"),
            (track.albumID != nil, "albumID=nil"),
            (track.artistID != nil, "artistID=nil"),
            (track.title == "Decode Title", "title=\(String(describing: track.title))"),
            (track.trackNo == 5, "trackNo=\(String(describing: track.trackNo))"),
            (track.discNo == 6, "discNo=\(String(describing: track.discNo))"),
            (track.year == 1999, "year=\(String(describing: track.year))"),
            (track.artworkKey == "decodehash", "artworkKey=\(String(describing: track.artworkKey))"),
        ]
        let mismatches = fieldChecks.filter { !$0.ok }.map(\.label)
        guard mismatches.isEmpty else {
            printFail(number, "DC1: LibraryTrack field(s) mis-decoded: \(mismatches.joined(separator: ", "))")
            return false
        }
        printPass(number, "DC1 (M-5): every LibraryTrack field decodes from the correct column "
            + "(distinct fileSize/mtime/inode/dev + resolved album/artist + title/trackNo/discNo/year/"
            + "artworkKey) — no positional index drift in trackColumns")
        return true
    } catch {
        printFail(number, "DC1 threw: \(error)"); return false
    }
}

/// DC2 (N-3): `ArtistFacet.artworkKey` (index 4 — the representative-cover correlated subquery)
/// decodes. An artist whose track's album has artwork must surface that key via both
/// `artists()` and `artist(id:)` (they share `artistSelectSQL`).
func checkArtistFacetArtworkKey(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/DCA"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(
            [ScannedFile(url: URL(fileURLWithPath: "/Music/DCA/a.flac"), relativePath: "a.flac",
                         name: "a", format: "FLAC", fileSize: 10, mtime: 20, inode: 30, dev: 40)],
            folderID: root, generation: gen
        )
        guard let trackID = ids.first else { printFail(number, "DC2: seed failed"); return false }
        try await store.applyExtractedResult(
            trackID: trackID,
            meta: TrackMetadata(title: "T", artistName: "Cover Artist", albumTitle: "Cover Album", year: 2001),
            artwork: ArtworkLink(contentHash: "artcover", cachePath: "/cache/artcover.jpg",
                                 pixelSize: .zero, byteSize: 2048),
            generation: gen
        )
        let artists = try await store.artists()
        guard let artist = artists.first(where: { $0.name == "Cover Artist" }) else {
            printFail(number, "DC2: artist 'Cover Artist' not listed"); return false
        }
        guard artist.artworkKey == "artcover" else {
            printFail(number, "DC2: ArtistFacet.artworkKey \(String(describing: artist.artworkKey)) != 'artcover' "
                + "(representative-cover subquery mis-decoded at index 4)"); return false
        }
        // artist(id:) must agree (shared builder).
        guard let single = try await store.artist(id: artist.id), single.artworkKey == "artcover" else {
            printFail(number, "DC2: artist(id:).artworkKey disagrees with the list entry"); return false
        }
        printPass(number, "DC2 (N-3): ArtistFacet.artworkKey (the representative album-cover subquery, "
            + "index 4) decodes for both artists() and artist(id:)")
        return true
    } catch {
        printFail(number, "DC2 threw: \(error)"); return false
    }
}
