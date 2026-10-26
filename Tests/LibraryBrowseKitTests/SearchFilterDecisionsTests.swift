import LibraryBrowseKit
import Testing

// MARK: - SearchEpoch (S9.5 filter — the H2 / review LOW-1 newest-wins contract; C-58 / P5B-01)

@Suite("SearchEpoch — newest-wins guard")
struct SearchEpochTests {
    @Test("no edit and no newer read since it began → the read may publish")
    func happyPath() {
        var epoch = SearchEpoch()
        let read = epoch.beginRead()
        #expect(epoch.isCurrent(read))
    }

    @Test("an edit after a read began invalidates it (stale result dropped)")
    func staleDropped() {
        var epoch = SearchEpoch()
        let abRead = epoch.beginRead() // the "ab" read is in flight
        epoch.invalidate() // a newer edit (e.g. "abc") lands
        #expect(!epoch.isCurrent(abRead)) // the late "ab" result must NOT publish
    }

    @Test("cross-2-char boundary (H2): a stale ≥2 read can't republish over a cleared field")
    func crossTwoCharBoundary() {
        // Exactly the H2 trace: type "ab" (read begun), backspace to "a" (clear path).
        var epoch = SearchEpoch()
        let abRead = epoch.beginRead()
        epoch.invalidate() // edit → "a": the didSet invalidates synchronously (before the debounce)
        let clearRun = epoch.beginRead()
        #expect(!epoch.isCurrent(abRead)) // in-flight "ab" read resolving late → rejected: no phantom
        #expect(epoch.isCurrent(clearRun)) // the clearing run is newest → still valid
    }

    /// P5B-01: a filtered reload re-runs the read with NO edit (a scan added songs), once per library
    /// revision, each in its own task, and the store reads concurrently — so two reads of the same query
    /// can finish in either order. The older snapshot (without the new song) must not land last.
    @Test("P5B-01: of two reads with no edit between them, only the newer may publish")
    func newerReadWinsWithoutAnEdit() {
        var epoch = SearchEpoch()
        epoch.invalidate() // the query was typed once
        let older = epoch.beginRead() // reload for revision N
        let newer = epoch.beginRead() // reload for revision N+1
        var published: Set<Int64>?
        if epoch.isCurrent(newer) {
            published = [1, 2, 3] // the newer read lands first
        }
        if epoch.isCurrent(older) {
            published = [1, 2] // the older read lands last
        }
        #expect(published == [1, 2, 3])
    }

    @Test("only the newest of several rapid edits publishes")
    func newestWins() {
        var epoch = SearchEpoch()
        epoch.invalidate(); let e1 = epoch.beginRead()
        epoch.invalidate(); let e2 = epoch.beginRead()
        epoch.invalidate(); let e3 = epoch.beginRead()
        #expect(!epoch.isCurrent(e1))
        #expect(!epoch.isCurrent(e2))
        #expect(epoch.isCurrent(e3))
    }
}

// MARK: - SearchQueryGate (the one search gate: 2 characters, or 1 syllable)

@Suite("SearchQueryGate — the one search gate (2 characters, or 1 syllable)")
struct SearchQueryGateTests {
    @Test("below 2 trimmed chars does NOT query (restore full list)")
    func belowGate() {
        #expect(!SearchQueryGate.shouldQuery(""))
        #expect(!SearchQueryGate.shouldQuery(" "))
        #expect(!SearchQueryGate.shouldQuery("a"))
        #expect(!SearchQueryGate.shouldQuery("   a   ")) // trims to 1
    }

    @Test("2+ trimmed chars queries — length-only, so tokenizable junk still passes")
    func atOrAboveGate() {
        #expect(SearchQueryGate.shouldQuery("ab"))
        #expect(SearchQueryGate.shouldQuery("   ab   ")) // trims to 2
        #expect(SearchQueryGate.shouldQuery("!!!")) // 3 chars: gate is length-only; the DAO returns []
    }

    /// R1.1-B fix round (break-it BI-P09, the coordinator's live finding): one character that is a syllable
    /// or a word in itself is a query; one Latin, Greek or Cyrillic letter, or a digit, is not.
    @Test("one character: a syllable is past the gate — an ideograph, kana, a Hangul syllable, a Brahmic syllable",
          arguments: ["東", "あ", "ア", "한", "මා", "ම", "क", "ก", " 東 "])
    func oneSyllable(query: String) {
        #expect(SearchQueryGate.shouldQuery(query), "“\(query)”")
    }

    @Test("one character that is no syllable stays below the gate — a letter, a digit, a sign",
          arguments: ["a", "B", "1", "é", "λ", "Ж", "١", "!", "ー", "ㅎ", "\u{0DCF}"])
    func oneLetterBelow(query: String) {
        #expect(!SearchQueryGate.shouldQuery(query), "“\(query)”")
    }

    @Test("a decomposed Hangul syllable is one syllable, as its composed form")
    func decomposedHangul() {
        #expect(SearchQueryGate.shouldQuery("\u{1112}\u{1161}\u{11AB}")) // 한, written as its jamo
    }
}
