// SearchRule — the Library's one search rule (R1.1-B, US-R1F-14; founder 2026-10-25: "one word-start rule
// everywhere").
//
// A query finds an item when EVERY word of the query starts a word of the item, in any order. Songs search
// asks the full-text index (`tracks_fts`); the Albums, Artists, Genres and Playlists filters, type-to-select
// and ⌘F's facet sections match in memory. Both halves read text through THIS file, so one query finds the
// same items wherever it is typed:
//   • TEXT — `normalized`: compatibility-composed (NFKC: a decomposed spelling meets the composed one, a width
//     or ligature variant its plain letters), with what shapes a character's look but is no part of a word
//     folded away — the zero-width joiner and non-joiner (a Sinhala conjunct typed with or without its
//     joiner, "ශ්‍රී" / "ශ්රී", is one word), variation selectors and emoji skin-tone modifiers — and with every
//     combining mark that follows no word character dropped: an emoji's keycap or enclosing circle, a mark
//     after a space or a symbol belongs to no word ("❤️" is no word; it used to find every emoji title — break-it
//     BI-P08). The index stores every row in this form (`LibraryStore.rebuildSearchIndex`; the re-index
//     migrations v9, v11 and v13 wrote it — `indexFormVersion`) and every query is put in it.
//   • WORDS — maximal runs of word characters (`isWordScalar`): exactly the characters the index's tokenizer
//     keeps in a token (`unicode61 … categories 'L* N* Co M*'`, Schema+SearchTokens.swift). Its character
//     tables are Unicode 6.1's, so a character assigned since reads to it as unassigned — which it keeps in
//     a token — and this rule says the same.
//   • FOLDING — `fold`: what the tokenizer folds (`remove_diacritics 2`): case, by its simple case-folding
//     table; a Latin letter's accents, by its own table; and 25 free-standing accents dropped. Another
//     script's marks are part of its letter ("මාල" ≠ "මිල", й ≠ и).
//   • MATCHING — a word matches a query word it starts with, code point by code point (`Query`).
// VerifyLibraryStore's search-rule parity check (`ChecksSearchRule`) runs every Unicode scalar through the
// app's own SQLite tokenizer and this rule, and fails on the first that differs — so the two halves cannot
// drift, and a future SQLite with newer tables is caught there.

import Foundation

/// The Library's one search rule: how text is normalised, split into words, folded and matched.
public enum SearchRule {
    // MARK: - Text

    /// The form the search index holds its text in — what `normalized` writes. Every change to `normalized`
    /// is a new form: it bumps this, and lands with a re-index migration that names it
    /// (`Schema.searchIndexForms`), or every upgraded library keeps rows in the old form while the queries
    /// use the new one. VerifyLibraryStore fails when this is ahead of the latest re-index migration, and
    /// when `normalized` writes another form than this one's golden (`ChecksSearchForm`).
    ///   1 — NFKC (v9, R1.1-A);  2 — + the zero-width joiners folded away (v11);  3 — + variation selectors and
    ///   emoji modifiers folded away, stray combining marks dropped (v13, R1.1-B fix round).
    public static let indexFormVersion = 3

    /// `text` as search reads and stores it: what only shapes a character's look folded away (`isFoldedAway`),
    /// compatibility-composed (NFKC), and every combining mark that follows no word character dropped. Plain
    /// ASCII is returned as it is.
    public static func normalized(_ text: String) -> String {
        guard !text.utf8.allSatisfy({ $0 < 0x80 }) else { return text }
        let unshaped: String
        if text.unicodeScalars.contains(where: isFoldedAway) {
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: text.unicodeScalars.lazy.filter { !isFoldedAway($0) })
            unshaped = String(scalars)
        } else {
            unshaped = text
        }
        return droppingStrayMarks(unshaped.precomposedStringWithCompatibilityMapping)
    }

    /// Whether `scalar` only shapes how its neighbours look and is no part of a word: the zero-width joiner
    /// (U+200D) and non-joiner (U+200C), which shape a conjunct; a variation selector, which picks a glyph
    /// (an emoji's colour form, a CJK ideograph's variant); an emoji skin-tone modifier.
    private static func isFoldedAway(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            return false
        }
        return scalar.value == 0x200D || scalar.value == 0x200C
            || scalar.properties.isVariationSelector || scalar.properties.isEmojiModifier
    }

    /// `text` less every combining mark that follows no word character — at the start, or after a space, a
    /// symbol or punctuation (a keycap's U+20E3 after "#", an enclosing circle, a combining low line): such
    /// a mark belongs to no word, and the index's tokenizer would read it as a word of its own.
    private static func droppingStrayMarks(_ text: String) -> String {
        guard hasStrayMark(text) else { return text }
        var afterWord = false
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !isCombiningMark(scalar) || afterWord {
            kept.append(scalar)
            afterWord = isWordScalar(scalar)
        }
        return String(kept)
    }

    /// Whether `text` holds a combining mark that follows no word character (`droppingStrayMarks`).
    private static func hasStrayMark(_ text: String) -> Bool {
        var afterWord = false
        for scalar in text.unicodeScalars {
            if isCombiningMark(scalar), !afterWord {
                return true
            }
            afterWord = isWordScalar(scalar)
        }
        return false
    }

    /// Whether `scalar` is a combining mark (Unicode category M: nonspacing, spacing or enclosing).
    private static func isCombiningMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    // MARK: - Words

    /// The words of `text`, each folded (`fold`), in order. A run that folds to nothing — a free-standing
    /// accent — is no word: the index finds nothing by it, and a query of it alone is no query.
    public static func words(of text: String) -> [String] {
        if text.utf8.allSatisfy({ $0 < 0x80 }) {
            return asciiWords(of: text)
        }
        var words: [String] = []
        var word = String.UnicodeScalarView()
        for scalar in normalized(text).unicodeScalars {
            if isWordScalar(scalar) {
                fold(scalar, into: &word)
            } else if !word.isEmpty {
                words.append(String(word))
                word = String.UnicodeScalarView()
            }
        }
        if !word.isEmpty {
            words.append(String(word))
        }
        return words
    }

    /// `words(of:)` for plain ASCII — most titles: runs of letters and digits, lowercased.
    private static func asciiWords(of text: String) -> [String] {
        text.utf8.split { !isASCIIWordByte($0) }.compactMap { bytes in
            String(bytes: bytes.map { (0x41 ... 0x5A).contains($0) ? $0 + 0x20 : $0 }, encoding: .ascii)
        }
    }

    /// An ASCII digit or Latin letter.
    private static func isASCIIWordByte(_ byte: UInt8) -> Bool {
        (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte) || (0x61 ... 0x7A).contains(byte)
    }

    /// The query's terms for the full-text index: each word of the normalised query AS TYPED (the index's
    /// tokenizer folds it as it folded the rows), keeping only those that fold to something.
    static func indexTerms(of query: String) -> [String] {
        var terms: [String] = []
        var term = String.UnicodeScalarView()
        var folded = String.UnicodeScalarView()
        func endTerm() {
            if !folded.isEmpty {
                terms.append(String(term))
            }
            term = String.UnicodeScalarView()
            folded = String.UnicodeScalarView()
        }
        for scalar in normalized(query).unicodeScalars {
            if isWordScalar(scalar) {
                term.append(scalar)
                fold(scalar, into: &folded)
            } else {
                endTerm()
            }
        }
        endTerm()
        return terms
    }

    /// Whether `scalar` is part of a word — a character the index's tokenizer keeps in a token: a letter, a
    /// mark, a number or a private-use character, or one its Unicode 6.1 tables do not know (unassigned to
    /// it). Punctuation, symbols, spaces, controls and format characters (once joiners are folded away)
    /// separate words.
    public static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            return isASCIIWordByte(UInt8(scalar.value))
        }
        if noncharacterSeparators.contains(scalar.value) {
            return false
        }
        guard isKnownToIndex(scalar) else { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber,
             .privateUse, .unassigned:
            return true
        default:
            return false
        }
    }

    /// The two noncharacters the tokenizer's table lists as separators.
    private static let noncharacterSeparators: Set<UInt32> = [0xFFFE, 0xFFFF]

    /// The Unicode version of the index tokenizer's character tables (SQLite FTS5 `unicode61`).
    static let indexUnicodeVersion = Unicode.Version(major: 6, minor: 1)

    /// Whether `scalar` was assigned by the index tokenizer's Unicode version — else it reads to the
    /// tokenizer as unassigned: a word character, never folded.
    static func isKnownToIndex(_ scalar: Unicode.Scalar) -> Bool {
        guard let age = scalar.properties.age else { return false }
        return (age.major, age.minor) <= (indexUnicodeVersion.major, indexUnicodeVersion.minor)
    }

    // MARK: - Folding

    /// Append `scalar` (a word character) to `word` as the index folds it: case folded and a Latin letter's
    /// accents removed, a free-standing accent dropped. Anything else is kept as it is.
    public static func fold(_ scalar: Unicode.Scalar, into word: inout String.UnicodeScalarView) {
        if scalar.isASCII {
            word.append(asciiLowercased(scalar))
            return
        }
        guard isKnownToIndex(scalar) else {
            word.append(scalar)
            return
        }
        if let folded = SearchRuleFolds.special[scalar.value] {
            if let folded {
                word.append(folded)
            }
            return
        }
        for lowered in caseFolded(scalar) {
            if SearchRuleFolds.droppedAccents.contains(lowered.value) {
                continue
            }
            word.append(SearchRuleFolds.latinBase(of: lowered) ?? lowered)
        }
    }

    /// `scalar`'s lowercase mapping, when every scalar of it is known to the index's tables — else
    /// `scalar` itself (a case pair assigned since, such as Cherokee's lowercase, is not one to it).
    private static func caseFolded(_ scalar: Unicode.Scalar) -> String.UnicodeScalarView {
        let mapping = scalar.properties.lowercaseMapping.unicodeScalars
        guard mapping.allSatisfy(isKnownToIndex) else { return String(scalar).unicodeScalars }
        return mapping
    }

    private static func asciiLowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard (0x41 ... 0x5A).contains(scalar.value), let lower = Unicode.Scalar(scalar.value + 0x20) else {
            return scalar
        }
        return lower
    }
}
