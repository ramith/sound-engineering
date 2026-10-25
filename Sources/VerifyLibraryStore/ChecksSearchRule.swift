// ChecksSearchRule — R1.1-B, US-R1F-14: the Library's one search rule (`SearchRule`) and the v10 → v11
// search index.
//   SR-1 PARITY — every Unicode scalar but NUL (1,112,063 of them) goes through the app's own SQLite
//        tokenizer, in a throwaway index built from the store's own DDL (`Schema.createV9FtsStatement`), and
//        through `SearchRule`: whether it is a word character, and what it folds to, must agree for every
//        one. The in-memory side (the grids' Filter, ⌘F, type-to-select) and the index cannot drift.
//   SR-2 THE v11 UPGRADE — a v10-or-earlier store, its index written as the v9 seam wrote it (NFKC, joiners
//        kept), with a playlist and play history, shows the fault first (a Sinhala conjunct written with
//        its zero-width joiner is two words, so "ශ්රී" typed without the joiner does not find it); it opens
//        through the real open path at v11 with every user row kept and one index row per song, and the
//        conjunct is found typed either way.
//   SR-3 THE COUNTER-EXAMPLES (plan check §6, "One search rule") on a fresh store, through the Songs search:
//        "beyo" finds "Beyoncé", "eyon" does not; NFD and NFC each find the other; a two-word query ANDs its
//        words in any order; "²", "Ⅳ" and a private-use character read alike in the index and the query; a
//        query of a lone accent, or of punctuation, finds nothing — never everything.
// LibraryBrowseKitTests (`OneSearchRuleTests`) hold the same cases across every tab's Filter and ⌘F.

import Foundation
import GRDB
import LibraryScan
import LibraryStore

// MARK: - Registration

func searchRuleCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "sr1-search-rule-parity", run: checkSearchRuleParity),
        CheckCase(label: "sr2-v11-search-joiners-upgrade", run: checkSearchJoinersUpgrade),
        CheckCase(label: "sr3-search-rule-counter-examples", run: checkSearchRuleCounterExamples),
    ]
}

// MARK: - SR-1 — the rule and the index tokenizer agree on every Unicode scalar

/// What the index tokenizer made of one scalar `c` written as "q c q": one token (c is a word character;
/// the token's middle is c folded), or two (c separates words).
private struct TokenizerReading {
    var isWordCharacter: Bool
    var folded: [UInt32]
}

/// Every scalar's reading by the app's SQLite tokenizer, keyed by scalar value.
private func tokenizerReadings(of scalars: [Unicode.Scalar]) throws -> [UInt32: TokenizerReading] {
    let queue = try DatabaseQueue()
    var readings: [UInt32: TokenizerReading] = [:]
    try queue.write { db in
        try db.execute(sql: Schema.createV9FtsStatement)
        let insert = try db.makeStatement(sql: "INSERT INTO tracks_fts(rowid, title) VALUES (?, ?);")
        for scalar in scalars {
            try insert.execute(arguments: [Int64(scalar.value), "q\(Character(scalar))q"])
        }
        try db.execute(sql: "CREATE VIRTUAL TABLE temp.vocab USING fts5vocab(main, tracks_fts, instance);")
        let rows = try Row.fetchCursor(db, sql: "SELECT doc, term FROM temp.vocab ORDER BY doc, offset;")
        var terms: [UInt32: [String]] = [:]
        while let row = try rows.next() {
            let doc: Int64 = row[0]
            let term: String = row[1]
            terms[UInt32(doc), default: []].append(term)
        }
        for (value, found) in terms {
            if found.count == 1, let term = found.first {
                let middle = term.unicodeScalars.dropFirst().dropLast().map(\.value)
                readings[value] = TokenizerReading(isWordCharacter: true, folded: middle)
            } else {
                readings[value] = TokenizerReading(isWordCharacter: false, folded: [])
            }
        }
    }
    return readings
}

func checkSearchRuleParity(number: Int, url _: URL) async -> Bool {
    do {
        let scalars = (UInt32(1) ... 0x10FFFF).compactMap(Unicode.Scalar.init)
        let readings = try tokenizerReadings(of: scalars)
        var differing: [String] = []
        for scalar in scalars {
            guard let reading = readings[scalar.value] else {
                differing.append(String(format: "U+%04X unread", scalar.value)); continue
            }
            var folded = String.UnicodeScalarView()
            let isWord = SearchRule.isWordScalar(scalar)
            if isWord {
                SearchRule.fold(scalar, into: &folded)
            }
            if isWord != reading.isWordCharacter || (isWord && folded.map(\.value) != reading.folded) {
                differing.append(String(format: "U+%04X", scalar.value))
            }
        }
        guard differing.isEmpty else {
            printFail(number, "SR-1: the search rule and the index tokenizer differ on \(differing.count) scalars, "
                + "first: \(differing.prefix(12).joined(separator: ", "))")
            return false
        }
        printPass(number, "SR-1 the one search rule and the app's SQLite tokenizer agree on all \(scalars.count) "
            + "Unicode scalars — which are word characters, and what each folds to")
        return true
    } catch {
        printFail(number, "SR-1 threw: \(error)"); return false
    }
}

// MARK: - SR-2 — the v10 → v11 upgrade

/// "Sri", written with its zero-width joiner (as typed on a Sinhala keyboard), and without.
private let sriWithJoiner = "\u{0DC1}\u{0DCA}\u{200D}\u{0DBB}\u{0DD3}"
private let sriWithoutJoiner = "\u{0DC1}\u{0DCA}\u{0DBB}\u{0DD3}"

/// The fixture's song titles, in id order: the conjunct with its joiner (a Sinhala title), and a Latin one.
private let joinerTitles = ["\(sriWithJoiner) ලංකා", "Beyoncé"]

/// A store at the version before v11 at `url`, holding `joinerTitles`, each indexed as the v9 seam indexed
/// it (NFKC, joiners kept); the first played 3 times and loved, both in a user playlist.
private func seedPreJoinerStore(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try migrator(through: 10).migrate(queue)
    try queue.write { db in
        for (index, title) in joinerTitles.enumerated() {
            try db.execute(sql: """
            INSERT INTO tracks(url, relative_path, name, format, file_size, mtime, title, date_added,
                               last_seen_scan, play_count, loved)
            VALUES (?, '', ?, 'FLAC', 8, 1, ?, 1, 1, ?, ?);
            """, arguments: ["/sr2/\(index).flac", "song\(index)", title, index == 0 ? 3 : 0, index == 0])
            try db.execute(sql: "INSERT INTO tracks_fts(rowid, title, artist, album, genre) VALUES (?, ?, '', '', '');",
                           arguments: [db.lastInsertedRowID, title.precomposedStringWithCompatibilityMapping])
        }
        try db.execute(sql: "INSERT INTO playlists(name, is_builtin, created_at) VALUES ('Kept', 0, 1);")
        let playlist = db.lastInsertedRowID
        for (position, track) in [2, 1].enumerated() {
            try db.execute(
                sql: "INSERT INTO playlist_entries(playlist_id, track_id, position, added_at) VALUES (?, ?, ?, 1);",
                arguments: [playlist, track, position]
            )
        }
    }
}

/// The ids a raw MATCH of `term` finds in the store file at `url`, on its own connection.
private func rawJoinerMatches(_ term: String, at url: URL) throws -> Set<Int64> {
    try DatabaseQueue(path: url.path).read { db in
        try Int64.fetchSet(db, sql: "SELECT rowid FROM tracks_fts WHERE tracks_fts MATCH ?;",
                           arguments: ["\"\(term)\"*"])
    }
}

func checkSearchJoinersUpgrade(number: Int, url: URL) async -> Bool {
    do {
        try seedPreJoinerStore(at: url)
        // The fault, first: the joiner split the conjunct, so the word typed without it finds nothing.
        guard try rawJoinerMatches(sriWithoutJoiner, at: url).isEmpty else {
            printFail(number, "SR-2: the pre-v11 fixture does not show the joiner fault (its index is not v9's)")
            return false
        }
        let store = try await LibraryStore(url: url, appBuild: "verify")
        for query in [sriWithJoiner, sriWithoutJoiner, "\(sriWithoutJoiner) ලං", "beyo"] {
            let expected: Set<Int64> = query == "beyo" ? [2] : [1]
            let found = try await store.searchMatchingIDs(query)
            guard found == expected else {
                printFail(number, "SR-2: after the upgrade “\(query)” found \(found.sorted()), expected "
                    + "\(expected.sorted())")
                return false
            }
        }
        guard await store.schemaVersion() == currentSchemaVersion,
              try await store.countRows(inTable: "tracks_fts") == joinerTitles.count,
              try await store.countRows(inTable: "tracks") == joinerTitles.count else {
            printFail(number, "SR-2: the upgraded store is not at v\(currentSchemaVersion) with one index row per song")
            return false
        }
        let kept = try await store.playlists().first { $0.name == "Kept" }
        let played = try await store.userState(trackID: 1)
        guard let kept, try await store.entries(inPlaylist: kept.id).map(\.trackID) == [2, 1],
              played?.playCount == 3, played?.loved == true else {
            printFail(number, "SR-2: the upgrade lost user data (the playlist, its order, or the play history)")
            return false
        }
        printPass(number, "SR-2 the v11 upgrade: a store whose index split “ශ්‍රී” at its zero-width joiner reaches "
            + "v\(currentSchemaVersion) with its playlist, order and play history kept and one index row per "
            + "song; the conjunct is found typed with and without the joiner, and with the next word begun")
        return true
    } catch {
        printFail(number, "SR-2 threw: \(error)"); return false
    }
}

// MARK: - SR-3 — the counter-examples, through the Songs search

/// The fixture's titles: each counter-example's song.
private let counterExampleTitles = [
    "Beyoncé — Halo", // 1
    "Cafe\u{301} del Mar", // 2: stored decomposed (NFD)
    "Café Society", // 3: stored composed (NFC)
    "Rock and Roll", // 4
    "E=mc² Ⅳ", // 5
    "Song \u{E000}\u{E001}", // 6: private-use characters
    "\(sriWithoutJoiner) පාද", // 7: written without the joiner
]

/// One counter-example: a query, and the fixture songs (1-based) the Songs search must find.
private struct SearchExpectation {
    let query: String
    let songs: Set<Int64>
    let why: String
}

private let counterExamples: [SearchExpectation] = [
    SearchExpectation(query: "beyo", songs: [1], why: "a word's start finds it"),
    SearchExpectation(query: "eyon", songs: [], why: "the middle of a word does not (founder, 2026-10-25)"),
    SearchExpectation(query: "café", songs: [2, 3], why: "NFC finds the NFD and NFC titles"),
    SearchExpectation(query: "Cafe\u{301}", songs: [2, 3], why: "NFD finds both too"),
    SearchExpectation(query: "roll rock", songs: [4], why: "two words AND, in any order"),
    SearchExpectation(query: "rock jazz", songs: [], why: "every word must be found"),
    SearchExpectation(query: "mc2", songs: [5], why: "² reads as 2 in the index and the query"),
    SearchExpectation(query: "mc²", songs: [5], why: "² typed finds it too"),
    SearchExpectation(query: "iv", songs: [5], why: "Ⅳ reads as IV"),
    SearchExpectation(query: "Ⅳ", songs: [5], why: "Ⅳ typed finds it too"),
    SearchExpectation(query: "\u{E000}", songs: [6], why: "a private-use character is a word character"),
    SearchExpectation(query: sriWithJoiner, songs: [7], why: "the joiner typed finds the title written without"),
    SearchExpectation(query: "\u{301}\u{301} \u{301}", songs: [], why: "a lone accent is no word: nothing, never all"),
    SearchExpectation(query: "— * ( ) \"", songs: [], why: "punctuation is no word: nothing, never all"),
]

func checkSearchRuleCounterExamples(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/SR3"))
        let files = counterExampleTitles.indices.map { index in
            makeScanned(path: "/Music/SR3/\(index).flac", name: "\(index)", inode: Int64(100 + index))
        }
        let ids = try await store.upsert(files, folderID: root, generation: generation)
        for (id, title) in zip(ids, counterExampleTitles) {
            try await store.applyMetadata(TrackMetadata(title: title), forTrack: id)
        }
        for example in counterExamples {
            let found = try await store.searchMatchingIDs(example.query)
            let expected = Set(example.songs.map { ids[Int($0) - 1] })
            guard found == expected else {
                printFail(number, "SR-3: “\(example.query)” found \(found.sorted()), expected \(expected.sorted()) — "
                    + example.why)
                return false
            }
        }
        printPass(number, "SR-3 the one search rule's counter-examples through the Songs search: “beyo” finds "
            + "“Beyoncé”, “eyon” does not; NFD and NFC find each other; words AND in any order; ², Ⅳ and "
            + "private-use characters read alike; the joiner folds away; a lone accent or punctuation finds nothing")
        return true
    } catch {
        printFail(number, "SR-3 threw: \(error)"); return false
    }
}
