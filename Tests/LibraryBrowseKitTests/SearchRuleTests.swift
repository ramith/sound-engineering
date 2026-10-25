import Foundation
import LibraryBrowseKit
import LibraryStore
import Testing

// MARK: - SearchRule — the Library's one search rule, read in memory (R1.1-B, US-R1F-14)

/// The rule the grids' Filter, ⌘F and type-to-select read words by, and the Songs index matches by.
/// (Its agreement with the index's tokenizer on every Unicode scalar is VerifyLibraryStore's SR-1.)
@Suite("SearchRule — one word-start rule (US-R1F-14)")
struct SearchRuleTests {
    /// "Sri" written with its zero-width joiner, as a Sinhala keyboard writes it, and without.
    private let sriWithJoiner = "\u{0DC1}\u{0DCA}\u{200D}\u{0DBB}\u{0DD3}"
    private let sriWithoutJoiner = "\u{0DC1}\u{0DCA}\u{0DBB}\u{0DD3}"

    @Test("words: case and a Latin letter's accents fold; punctuation separates")
    func latinWords() {
        #expect(SearchRule.words(of: "Beyoncé — Halo (Live)") == ["beyonce", "halo", "live"])
        #expect(SearchRule.words(of: "AC/DC") == ["ac", "dc"])
        #expect(SearchRule.words(of: "Motörhead") == ["motorhead"])
        #expect(SearchRule.words(of: "Røyksopp") == ["røyksopp"]) // ø is its own letter, as the index keeps it
    }

    @Test("words: another script's marks stay in their word (මාල ≠ මිල, й ≠ и)")
    func marksStay() {
        #expect(SearchRule.words(of: "මාල") != SearchRule.words(of: "මිල"))
        #expect(SearchRule.words(of: "Йога") == ["йога"])
        #expect(SearchRule.words(of: "Йога") != SearchRule.words(of: "иога"))
    }

    @Test("a Sinhala conjunct is one word, written with or without its zero-width joiner")
    func joinersFoldAway() {
        #expect(SearchRule.words(of: sriWithJoiner) == [sriWithoutJoiner])
        #expect(SearchRule.words(of: "\(sriWithJoiner) ලංකා").count == 2)
        #expect(SearchRule.normalized("a\u{200C}b") == "ab") // the non-joiner too
    }

    @Test("a decomposed (NFD) spelling and the composed (NFC) one are one word, both ways")
    func normalForms() {
        let nfd = "Cafe\u{301}"
        let nfc = "Café"
        #expect(SearchRule.words(of: nfd) == SearchRule.words(of: nfc))
        #expect(SearchRule.matches([nfc], query: nfd))
        #expect(SearchRule.matches([nfd], query: nfc))
        let hangulNFD = "\u{1102}\u{1169}\u{1105}\u{1162}"
        #expect(SearchRule.matches([hangulNFD], query: "노래"))
        #expect(SearchRule.matches(["노래"], query: hangulNFD))
        let sinhalaNFD = "\u{0DB8}\u{0DD9}\u{0DCA}" // මේ written as its parts
        #expect(SearchRule.matches(["මේ ගීතය"], query: sinhalaNFD))
    }

    @Test("a query word matches a word it STARTS — “beyo” finds “Beyoncé”, “eyon” does not")
    func wordStart() {
        #expect(SearchRule.matches(["Beyoncé"], query: "beyo"))
        #expect(!SearchRule.matches(["Beyoncé"], query: "eyon"))
        #expect(SearchRule.matches(["The Beatles"], query: "beat"))
        #expect(!SearchRule.matches(["The Beatles"], query: "eatles"))
        #expect(SearchRule.matches(["මාල"], query: "මා"))
        #expect(!SearchRule.matches(["මිල"], query: "මා"))
    }

    @Test("two words AND, in any order, across an item's texts")
    func twoWords() {
        #expect(SearchRule.matches(["Rock and Roll"], query: "roll rock"))
        #expect(!SearchRule.matches(["Rock and Roll"], query: "rock jazz"))
        #expect(SearchRule.matches(["Lemonade", "Beyoncé"], query: "beyo lemo"))
        #expect(SearchRule.matches(["Lemonade", "Beyoncé"], query: "lemo beyo"))
    }

    @Test("², Ⅳ and private-use characters read alike in the text and the query")
    func compatibilityAndPrivateUse() {
        #expect(SearchRule.matches(["E=mc²"], query: "mc2"))
        #expect(SearchRule.matches(["E=mc2"], query: "mc²"))
        #expect(SearchRule.matches(["Symphony Ⅳ"], query: "iv"))
        #expect(SearchRule.matches(["Symphony IV"], query: "Ⅳ"))
        #expect(SearchRule.matches(["Song \u{E000}\u{E001}"], query: "\u{E000}"))
        #expect(SearchRule.words(of: "Ｊａｐａｎ") == ["japan"])
    }

    @Test("a query with no word — punctuation, a lone accent — finds nothing, never everything")
    func noWordNoMatch() {
        for query in ["!!!", "— * ( )", "\u{301}\u{301} \u{301}", "   ", ""] {
            #expect(SearchRule.Query(query).isEmpty, "“\(query)”")
            #expect(!SearchRule.matches(["Anything at all"], query: query), "“\(query)”")
        }
    }

    @Test("type-to-select keeps its own shape: the title's START, folded by the rule")
    func titleStart() {
        #expect(SearchRule.text("The Beatles", startsWith: "the b"))
        #expect(SearchRule.text("Beyoncé", startsWith: "BEYO"))
        #expect(!SearchRule.text("The Beatles", startsWith: "beat"))
        #expect(SearchRule.text("මාල", startsWith: "ම")) // typed mid-syllable, before its vowel sign
        #expect(SearchRule.text("\(sriWithJoiner) ලංකා", startsWith: sriWithoutJoiner))
    }
}
