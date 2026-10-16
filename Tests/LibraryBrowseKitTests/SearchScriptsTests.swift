import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import Testing

// MARK: - Search finds a word in any script, however its text is stored (council C-61 slice, KI-LIB-11)

/// The council panel's SRCH-1/2/5 and N81 (P5A-04, P5B-07), kept as regression tests over the real store,
/// scanner and kit matchers. Songs search used the full-text tokenizer's default token characters, so a
/// Sinhala vowel sign split a word: "මාල" (necklace), "මිල" (price) and "මුල" (root) each found all three.
/// Text stored decomposed (an untagged song's NFD filename — older Mac drives, zips) was never found by
/// what the user types. And the Albums / Artists Filter and type-to-select folded every mark away, so
/// they agreed with neither.
@Suite("Search — any script, any stored form, one rule for words (C-61)", .serialized)
struct SearchScriptsTests {
    /// A music folder whose songs carry `titles` (title tags written through the store), and each
    /// title's song id.
    private func library(titled titles: [String], _ tag: String) async throws -> (MusicFolder, [String: Int64]) {
        let folder = try await MusicFolder.make(tag)
        let files = try folder.songs(in: "Album", count: titles.count)
        _ = try await LibraryScanner().scan(root: folder.music, folderID: folder.root, into: folder.store)
        var ids: [String: Int64] = [:]
        for (file, title) in zip(files, titles) {
            let id = try #require(try await folder.store.track(url: file)).id
            try await folder.store.applyMetadata(TrackMetadata(title: title), forTrack: id)
            ids[title] = id
        }
        return (folder, ids)
    }

    /// The titles Songs search finds for `query`.
    private func songs(matching query: String, in folder: MusicFolder, _ ids: [String: Int64]) async throws
        -> Set<String> {
        let hits = try await folder.store.searchMatchingIDs(query)
        return Set(ids.filter { hits.contains($0.value) }.keys)
    }

    @Test("SRCH-1: a Sinhala word finds itself — never the words that differ from it by a vowel sign")
    func sinhalaVowelSigns() async throws {
        let (folder, ids) = try await library(titled: ["මාල", "මිල", "මුල", "මල", "අමරදේව ගීත", "ගීතය"], "srch1")
        defer { folder.discard() }
        let expected: [(query: String, titles: Set<String>)] = [
            ("මාල", ["මාල"]), ("මිල", ["මිල"]), ("මුල", ["මුල"]), ("මල", ["මල"]),
            ("ගීත", ["ගීතය", "අමරදේව ගීත"]), ("අමරදේව", ["අමරදේව ගීත"]),
        ]
        for (query, titles) in expected {
            #expect(try await songs(matching: query, in: folder, ids) == titles, "“\(query)”")
        }
    }

    @Test("SRCH-2: text stored decomposed (NFD) is found by what the user types")
    func decomposedText() async throws {
        let folder = try await MusicFolder.make("srch2")
        defer { folder.discard() }
        // Untagged songs keep their filenames, stored as the drive spelled them: decomposed.
        let names = ["\u{1102}\u{1169}\u{1105}\u{1162}", "Cafe\u{301} del Mar", "\u{0DB8}\u{0DD9}\u{0DCA} ගීතය"]
        var files: [URL] = []
        for name in names {
            let file = folder.music.appendingPathComponent(name + ".flac")
            FileManager.default.createFile(atPath: file.path, contents: Data([1]))
            files.append(file)
        }
        _ = try await LibraryScanner().scan(root: folder.music, folderID: folder.root, into: folder.store)
        var ids: [String: Int64] = [:]
        for (file, name) in zip(files, ["노래", "Café", "මේ"]) {
            ids[name] = try #require(try await folder.store.track(url: file)).id
        }
        // What the user types: composed (NFC).
        for (query, title) in [("노래", "노래"), ("노", "노래"), ("Café", "Café"), ("cafe", "Café"), ("මේ", "මේ")] {
            #expect(try await songs(matching: query, in: folder, ids) == [title], "“\(query)”")
        }
    }

    /// One query, one answer, wherever it is typed: the Songs search, the Albums / Artists / Genres
    /// Filter and type-to-select read a word the same way — case and a Latin letter's accents don't
    /// count; every other script's marks are part of the word. (Where the three differ is the SHAPE of a
    /// match — a word's start, a substring, the title's start — which the one search rule settles,
    /// R1.1-B; every query here starts its title's first word, so all three shapes see it alike.)
    @Test("N81 / SRCH-5: the grids' Filter and type-to-select agree with Songs, word for word")
    func oneRuleForWords() async throws {
        let hangulNFD = "\u{1102}\u{1169}\u{1105}\u{1162}"
        let titles = ["මාල", "මිල", "Beyoncé", "Motörhead", "Ｊａｐａｎ", hangulNFD, "Йога", "Άλφα"]
        let (folder, ids) = try await library(titled: titles, "srch5")
        defer { folder.discard() }
        let cases = [
            Word("මාල", "මාල", true), Word("මිල", "මාල", false), Word("මාල", "මා", true), Word("මිල", "මා", false),
            Word("Beyoncé", "beyonce", true), Word("Beyoncé", "BEYO", true), Word("Motörhead", "motorhead", true),
            Word("Ｊａｐａｎ", "japan", true), Word(hangulNFD, "노래", true), Word(hangulNFD, "노", true),
            Word("Йога", "йога", true), Word("Йога", "иога", false), Word("Άλφα", "άλφα", true),
            Word("මාල", "ම", true), // typed mid-syllable, before its vowel sign
        ]
        for word in cases {
            let (title, query) = (word.title, word.query)
            let id = try #require(ids[title])
            let songsTab = try await folder.store.searchMatchingIDs(query).contains(id)
            let filter = FacetTextFilter.matches(title, query: query)
            let typeSelect = TypeSelectBuffer.firstMatch(for: query, in: [title]) { $0 } != nil
            #expect(songsTab == word.matches, "Songs: “\(query)” in “\(title)”")
            #expect(filter == word.matches, "Filter: “\(query)” in “\(title)”")
            #expect(typeSelect == word.matches, "type-select: “\(query)” on “\(title)”")
        }
    }

    /// One title, one query typed at its first word, and whether the query finds the title.
    private struct Word {
        let title: String
        let query: String
        let matches: Bool

        init(_ title: String, _ query: String, _ matches: Bool) {
            self.title = title
            self.query = query
            self.matches = matches
        }
    }
}
