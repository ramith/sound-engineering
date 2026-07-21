// ChecksSongsSortPlayTracking — SS5 (§12.3) of the songs-sort verification suite, split out of
// ChecksSongsSort for file length. `incrementPlayCount` is atomic + URL-keyed: two calls on one
// track accumulate play_count and refresh last_played; a second track increments independently;
// a nonexistent-url call is a silent no-op. Registered via `songsSortCheckCases()` (ChecksSongsSort).

import Foundation
import LibraryStore

// MARK: - SS5 — incrementPlayCount: atomic, URL-keyed, independent, silent no-op

func checkIncrementPlayCount(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/PlayFix"))
        let generation = try await store.beginScanGeneration()
        let files = [
            ScannedFile(url: URL(fileURLWithPath: "/PlayFix/a.flac"), relativePath: "",
                        name: "a", format: "FLAC", fileSize: 1000, mtime: 1000),
            ScannedFile(url: URL(fileURLWithPath: "/PlayFix/b.flac"), relativePath: "",
                        name: "b", format: "FLAC", fileSize: 1000, mtime: 1000),
        ]
        _ = try await store.upsert(files, folderID: root, generation: generation)

        // Two increments on track A (accumulation + last_played refresh), one on track B
        // (independence), then a nonexistent-url call (silent no-op).
        let firstPlay: Int64 = 1_700_000_000
        let secondPlay: Int64 = 1_700_000_500
        try await store.incrementPlayCount(url: files[0].url, playedAt: firstPlay)
        try await store.incrementPlayCount(url: files[0].url, playedAt: secondPlay)
        try await store.incrementPlayCount(url: files[1].url, playedAt: firstPlay)
        try await store.incrementPlayCount(
            url: URL(fileURLWithPath: "/PlayFix/does-not-exist.flac"), playedAt: secondPlay
        )

        let rows = try await store.allTracksDisplay(sortedBy: .name)
        guard rows.count == 2 else {
            printFail(number, "SS5: a nonexistent-URL incrementPlayCount call altered row count "
                + "(\(rows.count) rows, expected 2)")
            return false
        }
        guard let trackA = rows.first(where: { $0.url == files[0].url }),
              let trackB = rows.first(where: { $0.url == files[1].url }) else {
            printFail(number, "SS5: seeded tracks missing from the projection"); return false
        }
        guard trackA.playCount == 2, trackA.lastPlayed == secondPlay else {
            printFail(number, "SS5: track A play_count/last_played wrong "
                + "(count=\(trackA.playCount) lastPlayed=\(String(describing: trackA.lastPlayed)))")
            return false
        }
        guard trackB.playCount == 1, trackB.lastPlayed == firstPlay else {
            printFail(number, "SS5: track B did not increment independently of track A "
                + "(count=\(trackB.playCount) lastPlayed=\(String(describing: trackB.lastPlayed)))")
            return false
        }
        printPass(number, "SS5: incrementPlayCount is atomic + URL-keyed — two calls on one track "
            + "accumulate play_count and refresh last_played; a second track increments "
            + "independently; a nonexistent-url call is a silent no-op (no throw, other rows untouched)")
        return true
    } catch {
        printFail(number, "SS5 threw: \(error)"); return false
    }
}
