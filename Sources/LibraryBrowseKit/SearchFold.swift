import Foundation

// MARK: - SearchFold (R1.1-A, council C-61 / N81 — the Library's word rule, on the Swift side)

/// How the grids' Filter and type-to-select read a word: by the rule the Songs search index applies
/// (`LibraryStore`'s tokenizer and its `searchText`), so one query finds the same words wherever it is
/// typed. They compared with Foundation's diacritic-insensitive options, which drop EVERY combining
/// sign — a Sinhala vowel sign vanished, and "මා" landed on "මිල" (price) rather than "මාල" (necklace).
///
/// - Compatibility-composed (NFKC): a decomposed spelling meets the composed one, and a width or
///   ligature variant its plain letters (ＪＡＰＡＮ = JAPAN).
/// - A Latin letter's accents don't count (Beyoncé = beyonce) — and nothing else's: another script's
///   mark is part of its letter (මාල ≠ මිල, й ≠ и, ά ≠ α), as in the index.
/// - Case doesn't count.
///
/// Text is compared code point by code point, as the index compares it — so a prefix typed in the middle
/// of a syllable ("ම" before its vowel sign) still matches. What a matcher looks for — the title's start,
/// a substring — is its own; the one search rule (R1.1-B) settles the shapes.
enum SearchFold {
    /// Whether `text` begins with `prefix`, both read by the rule (type-to-select). A UTF-8 byte prefix
    /// is a code-point prefix.
    static func text(_ text: String, startsWith prefix: String) -> Bool {
        folded(text).utf8.starts(with: folded(prefix).utf8)
    }

    /// Whether `text` contains `query` anywhere, both read by the rule (the grids' Filter). `.literal`:
    /// code unit for code unit, with no further folding — and as fast as the comparison it replaced.
    static func text(_ text: String, contains query: String) -> Bool {
        folded(text).range(of: folded(query), options: .literal) != nil
    }

    /// The combining accents the index folds away (U+0300–U+036F, the Combining Diacritical Marks).
    private static let accents: ClosedRange<UInt32> = 0x300 ... 0x36F

    /// The precomposed Latin letters that can carry accents (Latin-1 Supplement through Latin
    /// Extended-B, and Latin Extended Additional) — the only scalars worth decomposing.
    private static let accentedLatin: [ClosedRange<UInt32>] = [0xC0 ... 0x24F, 0x1E00 ... 0x1EFF]

    /// `text` as the rule reads it. Plain ASCII — most titles — is only lowercased.
    private static func folded(_ text: String) -> String {
        guard !text.utf8.allSatisfy({ $0 < 0x80 }) else { return text.lowercased() }
        var scalars = String.UnicodeScalarView()
        for scalar in text.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if accents.contains(scalar.value) {
                continue // a free-standing accent is dropped, as the index drops it
            }
            scalars.append(latinLetter(under: scalar) ?? scalar)
        }
        return String(scalars).lowercased()
    }

    /// The ASCII letter under `scalar` when `scalar` is that letter with accents ("é" → "e", "ễ" → "e"),
    /// else nil — "ø", "й", "ά" and every other script's letter keep their marks.
    private static func latinLetter(under scalar: Unicode.Scalar) -> Unicode.Scalar? {
        guard accentedLatin.contains(where: { $0.contains(scalar.value) }) else { return nil }
        let parts = String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars
        guard let base = parts.first, base.isASCII, base.properties.isAlphabetic,
              parts.dropFirst().allSatisfy({ accents.contains($0.value) }) else { return nil }
        return base
    }
}
