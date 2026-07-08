import LibraryBrowseKit
import Testing

// MARK: - SearchEpoch (S9.5 filter — the H2 / review LOW-1 newest-wins contract)

@Suite("SearchEpoch — newest-wins guard")
struct SearchEpochTests {
    @Test("no edit since capture → the read may publish")
    func happyPath() {
        var epoch = SearchEpoch()
        let captured = epoch.value
        #expect(epoch.isCurrent(captured))
    }

    @Test("an edit after capture invalidates the read (stale result dropped)")
    func staleDropped() {
        var epoch = SearchEpoch()
        epoch.invalidate() // edit → "ab"
        let abRead = epoch.value // the "ab" read captures its epoch
        epoch.invalidate() // a newer edit (e.g. "abc") lands while the read is in flight
        #expect(!epoch.isCurrent(abRead)) // the late "ab" result must NOT publish
    }

    @Test("cross-2-char boundary (H2): a stale ≥2 read can't republish over a cleared field")
    func crossTwoCharBoundary() {
        // Exactly the H2 trace: type "ab" (read dispatched), backspace to "a" (clear path).
        var epoch = SearchEpoch()
        epoch.invalidate() // edit → "ab"
        let abRead = epoch.value
        epoch.invalidate() // edit → "a": the didSet invalidates synchronously (before the debounce)
        let clearRun = epoch.value
        #expect(!epoch.isCurrent(abRead)) // in-flight "ab" read resolving late → rejected: no phantom
        #expect(epoch.isCurrent(clearRun)) // the clearing run is newest → still valid
    }

    @Test("only the newest of several rapid edits publishes")
    func newestWins() {
        var epoch = SearchEpoch()
        epoch.invalidate(); let e1 = epoch.value
        epoch.invalidate(); let e2 = epoch.value
        epoch.invalidate(); let e3 = epoch.value
        #expect(!epoch.isCurrent(e1))
        #expect(!epoch.isCurrent(e2))
        #expect(epoch.isCurrent(e3))
    }
}

// MARK: - SearchQueryGate (≥2-char trimmed gate)

@Suite("SearchQueryGate — ≥2-char trimmed gate")
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
}
