// SearchRuleFolds — the index tokenizer's folds that the general rule in `SearchRule.fold` does not derive
// from Unicode properties (R1.1-B, US-R1F-14).
//
// The tokenizer (`unicode61 remove_diacritics 2`) folds case by Unicode's simple CASE FOLDING, which maps a
// few letters a lowercase mapping leaves alone (µ → μ, ſ → s, ς → σ …), and removes a Latin letter's accents
// by a table of its own. `SearchRule.fold` derives both from the scalar's lowercase mapping and canonical
// decomposition; this file holds the scalars where that derivation and the tokenizer differ, each found by
// running every Unicode scalar through the app's SQLite (VerifyLibraryStore, `ChecksSearchRule`).

/// The index tokenizer's folds beyond `SearchRule.fold`'s general rule.
enum SearchRuleFolds {
    /// Scalars the tokenizer folds otherwise than the general rule: to the scalar given, or (nil) to
    /// nothing at all.
    static let special: [UInt32: Unicode.Scalar?] = [
        0x00B5: "\u{03BC}", // µ micro sign → μ (case folding)
        0x017F: "s", // ſ long s → s
        0x01E0: "\u{01E1}", // Ǡ → ǡ: the tokenizer's accent table has no entry for it
        0x01E1: "\u{01E1}", // ǡ stays
        0x0345: "\u{03B9}", // combining ypogegrammeni → ι (case folding)
        0x03C2: "\u{03C3}", // ς final sigma → σ
        0x03D0: "\u{03B2}", // ϐ → β
        0x03D1: "\u{03B8}", // ϑ → θ
        0x03D5: "\u{03C6}", // ϕ → φ
        0x03D6: "\u{03C0}", // ϖ → π
        0x03F0: "\u{03BA}", // ϰ → κ
        0x03F1: "\u{03C1}", // ϱ → ρ
        0x03F5: "\u{03B5}", // ϵ → ε
        0x1E9B: "s", // ẛ → ṡ (case folding) → s (its accent)
        0x1FBE: "\u{03B9}", // prosgegrammeni → ι
    ]

    /// The free-standing combining accents the tokenizer drops (`remove_diacritics`): 25 of the
    /// Combining Diacritical Marks. Every other mark is part of its word.
    static let droppedAccents: Set<UInt32> = [
        0x300, 0x301, 0x302, 0x303, 0x304, 0x306, 0x307, 0x308, 0x309, 0x30A, 0x30B, 0x30C, 0x30F,
        0x311, 0x31B, 0x323, 0x324, 0x325, 0x326, 0x327, 0x328, 0x32D, 0x32E, 0x330, 0x331,
    ]

    /// The precomposed Latin letters the tokenizer's accent table covers: Latin-1 Supplement through
    /// Latin Extended-B, and Latin Extended Additional.
    private static let accentedLatin: [ClosedRange<UInt32>] = [0xC0 ... 0x24F, 0x1E00 ... 0x1EFF]

    /// The ASCII letter under `scalar` when `scalar` is that letter with accents the tokenizer drops ("é"
    /// → "e", "ǖ" → "u"), else nil — "ø", "ł", "й" and every other script's letter keep their marks.
    static func latinBase(of scalar: Unicode.Scalar) -> Unicode.Scalar? {
        guard accentedLatin.contains(where: { $0.contains(scalar.value) }) else { return nil }
        let parts = String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars
        guard let base = parts.first, base.isASCII, base.properties.isAlphabetic, parts.count > 1,
              parts.dropFirst().allSatisfy({ droppedAccents.contains($0.value) }) else { return nil }
        return base
    }
}
