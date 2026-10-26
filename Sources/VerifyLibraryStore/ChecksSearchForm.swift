// ChecksSearchForm — R1.1-B fix round (review S6, break-it BI-P08): the form the search index is written in
// is tied to the rule the queries use.
//   SR-4 THE FORM GUARD — `SearchRule.indexFormVersion` is the form of the latest re-index migration
//        (`Schema.searchIndexForms`), that migration is registered, and the forms rise; and what
//        `SearchRule.normalized` writes is that form's: its output over every assigned Unicode scalar (to
//        Unicode 15.0) alone, after a word character, after a symbol and before a combining accent hashes to
//        the form's golden — so a change to the rule that lands without a new form and a re-index fails here,
//        before any upgraded library keeps rows the queries no longer meet. (It pins the platform's
//        composition too: macOS 26's NFC/NFKC composes a supplementary-plane letter followed by an accent as if
//        it were the BMP letter with its low 16 bits — U+200A8 U+0301 → U+0385 — on both halves alike; an OS
//        that fixes it changes the form, and this check says so.)
//   SR-5 THE v13 UPGRADE — a v12 store whose index holds an emoji title in form 2 (its variation selector a
//        one-mark "word": "❤️❤️" finds "☀️ Summer"), with a playlist and play history, opens through the real
//        open path with every user row kept and one index row per song; an emoji query then finds nothing,
//        and the title's words still find it.

import Foundation
import GRDB
import LibraryStore

// MARK: - Registration

func searchFormCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "sr4-search-index-form-guard") { number, _ in checkSearchIndexFormGuard(number: number) },
        CheckCase(label: "sr5-v13-search-stray-marks-upgrade", run: checkSearchStrayMarksUpgrade),
    ]
}

// MARK: - SR-4 — the form guard

/// FNV-1a of `SearchRule.normalized` over the form corpus (`formCorpus`) at form `SearchRule.indexFormVersion`
/// (3: v13). Regenerate ONLY with a new form: bump `indexFormVersion`, append its re-index migration to
/// `Schema.searchIndexForms`, and paste the hash SR-4 prints.
let goldenSearchFormHash = "4108d0601a680ae1"

/// The texts the form golden reads: every assigned scalar to Unicode 15.0 but private use, alone, after a
/// word character, after a symbol, and before a combining accent.
private func formCorpus() -> [String] {
    var corpus: [String] = []
    for value in UInt32(1) ... 0x10FFFF {
        guard let scalar = Unicode.Scalar(value), let age = scalar.properties.age, (age.major, age.minor) <= (15, 0),
              scalar.properties.generalCategory != .privateUse else { continue }
        let character = String(scalar)
        corpus.append(contentsOf: [character, "a" + character, "!" + character, character + "\u{301}"])
    }
    return corpus
}

func checkSearchIndexFormGuard(number: Int) -> Bool {
    let forms = Schema.searchIndexForms
    guard let latest = forms.last, latest.form == SearchRule.indexFormVersion,
          let version = Schema.MigrationID.version(of: latest.migration), version <= currentSchemaVersion,
          zip(forms, forms.dropFirst()).allSatisfy({ $0.form < $1.form }) else {
        printFail(number, "SR-4: the search rule's form \(SearchRule.indexFormVersion) is not the form of the latest "
            + "registered re-index migration (\(forms.map { "\($0.migration)=\($0.form)" })): a change to the rule "
            + "needs a re-index migration that names its form")
        return false
    }
    var written = ""
    for text in formCorpus() {
        written += SearchRule.normalized(text) + "\u{1}"
    }
    let hash = fnv1a64Hex(written)
    guard hash == goldenSearchFormHash else {
        printFail(number, "SR-4: SearchRule.normalized writes another form than form \(SearchRule.indexFormVersion)'s "
            + "golden (hash \(hash)). A change to the rule is a new form: bump SearchRule.indexFormVersion, add a "
            + "re-index migration naming it to Schema.searchIndexForms, then set goldenSearchFormHash to \(hash)")
        return false
    }
    printPass(number, "SR-4 the search index's form is the rule's: form \(SearchRule.indexFormVersion) is the latest "
        + "registered re-index migration's (\(latest.migration)), and SearchRule.normalized writes exactly that "
        + "form over every assigned scalar in four contexts (golden \(hash))")
    return true
}

// MARK: - SR-5 — the v12 → v13 upgrade

/// The fixture's titles: an emoji title and a plain one.
private let markTitles = ["\u{2600}\u{FE0F} Summer", "Plain Song"]

/// A store at v12 at `url`, holding `markTitles` with each index row as form 2 wrote it (NFKC, joiners folded,
/// the variation selector kept); the first played twice and loved, both in a user playlist.
private func seedV12Store(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try migrator(through: 12).migrate(queue)
    try queue.write { db in
        for (index, title) in markTitles.enumerated() {
            try db.execute(sql: """
            INSERT INTO tracks(id, url, relative_path, name, format, file_size, mtime, title, date_added,
                               last_seen_scan, play_count, loved)
            VALUES (?, ?, '', ?, 'FLAC', 8, 1, ?, 1, 1, ?, ?);
            """, arguments: [index + 1, "/sr5/\(index).flac", "song\(index)", title, index == 0 ? 2 : 0, index == 0])
            try db.execute(sql: "INSERT INTO tracks_fts(rowid, title, artist, album, genre) VALUES (?, ?, '', '', '');",
                           arguments: [index + 1, title.precomposedStringWithCompatibilityMapping])
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

func checkSearchStrayMarksUpgrade(number: Int, url: URL) async -> Bool {
    do {
        try seedV12Store(at: url)
        // The fault, first: the variation selector is a word of its own in the form-2 index.
        let before = try rawMatches("\u{FE0F}", at: url)
        guard before == [1] else {
            printFail(number, "SR-5: the v12 fixture does not show the stray-mark fault (\(before.sorted()))")
            return false
        }
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let expectations: [(String, Set<Int64>)] = [
            ("\u{2764}\u{FE0F}\u{2764}\u{FE0F}", []), ("\u{2600}\u{FE0F}", []), ("summer", [1]), ("plain", [2]),
        ]
        for (query, expected) in expectations {
            let found = try await store.searchMatchingIDs(query)
            guard found == expected else {
                printFail(number, "SR-5: after the upgrade “\(query)” found \(found.sorted()), expected "
                    + "\(expected.sorted())")
                return false
            }
        }
        let kept = try await store.playlists().first { $0.name == "Kept" }
        let played = try await store.userState(trackID: 1)
        guard await store.schemaVersion() == currentSchemaVersion,
              try await store.countRows(inTable: "tracks_fts") == markTitles.count,
              let kept, try await store.entries(inPlaylist: kept.id).map(\.trackID) == [2, 1],
              played?.playCount == 2, played?.loved == true else {
            printFail(number, "SR-5: the upgrade lost user data, or did not leave one index row per song")
            return false
        }
        printPass(number, "SR-5 the v13 upgrade: a v12 store whose index read an emoji's variation selector as a "
            + "word reaches v\(currentSchemaVersion) with its playlist, order and play history kept and one index "
            + "row per song; “❤️❤️” and “☀️” find nothing, “summer” finds the emoji title")
        return true
    } catch {
        printFail(number, "SR-5 threw: \(error)"); return false
    }
}

/// The ids a raw MATCH of `term` (a quoted prefix) finds in the store file at `url`, on its own connection.
private func rawMatches(_ term: String, at url: URL) throws -> Set<Int64> {
    try DatabaseQueue(path: url.path).read { db in
        try Int64.fetchSet(db, sql: "SELECT rowid FROM tracks_fts WHERE tracks_fts MATCH ?;",
                           arguments: ["\"\(term)\"*"])
    }
}
