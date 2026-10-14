import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import Testing

// P5a panel — UNCOMMITTED adversarial tests for the FTS5 search (N61–N63): scripts with
// combining marks (Sinhala), NFD text, CJK, and injection.

@Suite("P5a search — scripts, normalization, injection", .serialized)
struct P5aSearchBreakTests {
    /// A store with one song per title (title tag set through the real metadata write).
    private func store(titles: [String], tag: String) async throws -> (LibraryStore, [String: Int64], URL) {
        let base = P5aFixture.base(tag)
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music, count: titles.count)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        let scan = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        var ids: [String: Int64] = [:]
        for (file, title) in zip(files, titles) {
            let id = try #require(try await store.track(url: file)).id
            try await store.applyExtractedResult(
                trackID: id, meta: TrackMetadata(title: title, artistName: "Artist", albumTitle: "Album"),
                artwork: nil, generation: scan.generation
            )
            ids[title] = id
        }
        _ = try await store.refreshDerivedFacets()
        return (store, ids, base)
    }

    private func matches(_ store: LibraryStore, _ query: String, _ ids: [String: Int64]) async throws -> [String] {
        let hits = try await store.searchMatchingIDs(query)
        return ids.filter { hits.contains($0.value) }.map(\.key).sorted()
    }

    /// Sinhala: "මිල" (price), "මාල" (necklace), "මුල" (root), "මල" (flower) differ only by vowel
    /// signs (Mn/Mc). FTS5 unicode61's default token categories are "L* N* Co" — marks are
    /// separators — so all four index as the tokens [ම][ල] (or [මල]).
    @Test("SRCH-1: a Sinhala query matches only the word typed")
    func sinhalaVowelSigns() async throws {
        let titles = ["මිල", "මාල", "මුල", "මල", "අමරදේව ගීත", "ගීතය", "ගැටලුව"]
        let (store, ids, base) = try await store(titles: titles, tag: "srch1")
        defer { try? FileManager.default.removeItem(at: base) }
        var report: [String] = []
        var wrong = 0
        let expected: [String: Set<String>] = [
            "මාල": ["මාල"], "මිල": ["මිල"], "මුල": ["මුල"], "ගීත": ["ගීතය", "අමරදේව ගීත"],
            "අමරදේව": ["අමරදේව ගීත"], "ගීතය": ["ගීතය"],
        ]
        for (query, want) in expected.sorted(by: { $0.key < $1.key }) {
            let got = try await matches(store, query, ids)
            if Set(got) != want {
                wrong += 1
            }
            report.append("\(query)→\(got)")
        }
        print("P5A SRCH-1 " + report.joined(separator: " ; "))
        #expect(wrong == 0, "\(wrong) Sinhala queries returned the wrong songs")
    }

    /// NFD text in the index (an untagged song keeps its filename; HFS+ volumes, zips and many
    /// copies leave names decomposed). The user types NFC.
    @Test("SRCH-2: an NFD filename is found by the NFC spelling")
    func nfdFilenameSearch() async throws {
        let base = P5aFixture.base("srch2")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let names = ["\u{1102}\u{1169}\u{1105}\u{1162}", "Cafe\u{301} del Mar", "\u{0DB8}\u{0DD9}\u{0DCA}"] // 노래, Café, මේ (NFD)
        for name in names {
            FileManager.default.createFile(atPath: music.appendingPathComponent(name + ".flac").path, contents: Data([1]))
        }
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        var report: [String] = []
        var missed = 0
        for query in ["노래", "Café", "cafe", "\u{0DB8}\u{0DDA}"] { // NFC queries
            let hits = try await store.searchMatchingIDs(query).count
            if hits == 0 {
                missed += 1
            }
            report.append("\(query)(\(query.unicodeScalars.count)sc)→\(hits)")
        }
        print("P5A SRCH-2 " + report.joined(separator: " ; "))
        #expect(missed == 0, "\(missed) NFC queries missed an NFD-named song")
    }

    @Test("SRCH-3: CJK — a word inside a run of ideographs")
    func cjkInfix() async throws {
        let (store, ids, base) = try await store(titles: ["東京事変", "東京", "事変の夜"], tag: "srch3")
        defer { try? FileManager.default.removeItem(at: base) }
        let prefix = try await matches(store, "東京", ids)
        let infix = try await matches(store, "事変", ids)
        print("P5A SRCH-3 東京→\(prefix) ; 事変→\(infix)")
        #expect(infix.contains("東京事変"), "a CJK word inside a title is not found (no segmentation)")
    }

    /// Injection: random strings of FTS5 syntax never throw, never match everything, and
    /// operator words are literal terms.
    @Test("SRCH-4: FTS5 syntax in the query is inert")
    func injectionFuzz() async throws {
        let titles = ["Rock and Roll", "Jazz Night", "NOT Fade Away", "Love * Hate", "Near Far", "Hello World"]
        let (store, ids, base) = try await store(titles: titles, tag: "srch4")
        defer { try? FileManager.default.removeItem(at: base) }
        let pieces = ["\"", "*", "^", ":", "(", ")", "-", "+", "NEAR", "AND", "OR", "NOT", "{", "}", "[", "]",
                      "'", ",", ".", "/", "\\", "title", "rock", "jazz", "zz", " ", "\u{0}", "%", "_", "NEAR/2"]
        var generator = SystemRandomNumberGenerator()
        var thrown = 0
        var matchedAll = 0
        for _ in 0 ..< 3000 {
            let query = (0 ..< Int.random(in: 1 ... 8, using: &generator))
                .map { _ in pieces.randomElement(using: &generator)! }.joined()
            do {
                let hits = try await store.searchMatchingIDs(query)
                let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }
                if hits.count == titles.count, !words.isEmpty {
                    matchedAll += 1
                }
            } catch {
                thrown += 1
            }
        }
        let operatorsAreLiteral = try await (
            matches(store, "rock OR jazz", ids),
            matches(store, "NOT", ids),
            matches(store, "title:jazz", ids),
            matches(store, "\"rock", ids),
            matches(store, "near", ids)
        )
        print("P5A SRCH-4 fuzz thrown=\(thrown) matchedAll=\(matchedAll); 'rock OR jazz'→\(operatorsAreLiteral.0) "
            + "'NOT'→\(operatorsAreLiteral.1) 'title:jazz'→\(operatorsAreLiteral.2) '\"rock'→\(operatorsAreLiteral.3) "
            + "'near'→\(operatorsAreLiteral.4)")
        #expect(thrown == 0 && matchedAll == 0)
        #expect(operatorsAreLiteral.0.isEmpty) // "rock" AND "or" AND "jazz": no title has all three
        #expect(operatorsAreLiteral.1 == ["NOT Fade Away"])
    }

    /// LIB-05: the same typed text, two tabs. Songs = FTS5 prefix tokens; Albums/Artists/Genres =
    /// FacetTextFilter (localizedStandardContains, substring).
    @Test("SRCH-5: one query, one meaning across tabs")
    func oneSemantic() async throws {
        let titles = ["Pearl Jam", "මිල", "東京事変"]
        let (store, ids, base) = try await store(titles: titles, tag: "srch5")
        defer { try? FileManager.default.removeItem(at: base) }
        var rows: [String] = []
        var disagreements = 0
        for (query, title) in [("ear", "Pearl Jam"), ("මාල", "මිල"), ("事変", "東京事変"), ("jam", "Pearl Jam")] {
            let songsTab = try await matches(store, query, ids).contains(title)
            let facetTab = FacetTextFilter.matches(title, query: query)
            if songsTab != facetTab {
                disagreements += 1
            }
            rows.append("'\(query)' vs '\(title)': songs=\(songsTab) facets=\(facetTab)")
        }
        print("P5A SRCH-5 " + rows.joined(separator: " ; "))
        #expect(disagreements == 0)
    }
}
