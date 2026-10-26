import Foundation

// MARK: - Search filter decisions (S9.5 — pure filter logic)

/// Monotonic newest-wins guard for the async Songs-filter read. Extracted from `LibraryBrowseModel`
/// so the H2 "no stale phantom publish" contract is unit-testable. Usage: the model calls
/// `invalidate()` **synchronously on every `searchQuery` edit** (before the ~120 ms debounce), and each
/// read takes its token from `beginRead()` and publishes its result only if `isCurrent(token)` still
/// holds — so an in-flight read for an older query can never overwrite a newer edit (review LOW-1), and
/// of two reads of the SAME query the newer always wins (council C-58 / P5B-01: a filtered reload re-runs
/// the read with no edit, once per library change, and the store reads concurrently, so two reads can
/// finish in either order — the older snapshot, without the newly scanned song, must not land last).
public struct SearchEpoch: Sendable, Equatable {
    private var value = 0

    public init() {}

    /// Invalidate every read begun so far. Call synchronously on every edit — NOT inside the debounce,
    /// or a fast read can resolve and publish before the invalidation lands.
    public mutating func invalidate() {
        value &+= 1
    }

    /// Begin a read: it supersedes every read begun before it. Returns its token for `isCurrent`.
    public mutating func beginRead() -> Int {
        invalidate()
        return value
    }

    /// Whether the read holding `token` may still publish: no edit and no newer read since it began.
    public func isCurrent(_ token: Int) -> Bool {
        token == value
    }
}

/// The one search gate — every tab's Filter (Songs, Albums, Artists, Genres, Playlists, the queue's), ⌘F and
/// the playlist picker narrow by a query only past it; below it, a list shows everything (the Songs model
/// restores the full list, nil `matchedIDs`), and ⌘F shows nothing (R1.1-B fix round, break-it BI-P09: one
/// letter used to narrow three tabs, show every song and find nothing in ⌘F).
///
/// A trimmed query is past the gate at two characters (grapheme clusters, as the user sees them) — or at
/// ONE when that one is a syllable or a word in itself: a CJK ideograph ("東"), kana ("あ"), a Hangul syllable
/// ("한"), or a syllable of a Brahmic script ("මා", "क", "ก"). A single Latin, Greek or Cyrillic letter,
/// or a digit, stays below: it would keep nearly every item. Length only — tokenizable-but-junk input
/// (`"!!!"`) passes, and finds nothing.
public enum SearchQueryGate {
    /// The characters a query needs to be searched, unless its one character is a syllable.
    public static let minimumLength = 2

    public static func shouldQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let only = trimmed.first else { return false }
        return trimmed.count >= minimumLength || isSyllable(only)
    }

    /// Whether `character` is a syllable or a word in itself: a CJK ideograph, kana, a Hangul syllable, or a
    /// letter (with its vowel signs) of a Brahmic script — read on its composed form, its first scalar.
    static func isSyllable(_ character: Character) -> Bool {
        guard let base = String(character).precomposedStringWithCanonicalMapping.unicodeScalars.first else {
            return false
        }
        let properties = base.properties
        if properties.isIdeographic || hangulSyllables.contains(base.value) {
            return true
        }
        guard properties.generalCategory == .otherLetter else { return false }
        return (kana + brahmic).contains { $0.contains(base.value) }
    }

    /// The precomposed Hangul syllables (가 … 힣).
    private static let hangulSyllables: ClosedRange<UInt32> = 0xAC00 ... 0xD7A3

    /// Hiragana, Katakana and their extensions, halfwidth Katakana, and the Kana supplements.
    private static let kana: [ClosedRange<UInt32>] = [
        0x3040 ... 0x30FF, 0x31F0 ... 0x31FF, 0xFF66 ... 0xFF9D, 0x1B000 ... 0x1B16F,
    ]

    /// The Brahmic scripts' blocks: Devanagari to Sinhala (the Indic scripts of India and Sri Lanka), Thai,
    /// Lao, Tibetan, Myanmar, Khmer, the Southeast Asian and Himalayan Brahmic blocks, and the supplementary
    /// Brahmic blocks (Brahmi to Kawi).
    private static let brahmic: [ClosedRange<UInt32>] = [
        0x0900 ... 0x0DFF, 0x0E00 ... 0x0EFF, 0x0F00 ... 0x0FFF, 0x1000 ... 0x109F, 0x1780 ... 0x17FF,
        0x1900 ... 0x194F, 0x1950 ... 0x19DF, 0x1A00 ... 0x1AAF, 0x1B00 ... 0x1BFF, 0x1C00 ... 0x1C4F,
        0xA800 ... 0xA82F, 0xA840 ... 0xA87F, 0xA880 ... 0xA8FF, 0xA900 ... 0xA9FF, 0xAA00 ... 0xAADF,
        0xAAE0 ... 0xAAFF, 0xABC0 ... 0xABFF, 0x11000 ... 0x11F5F,
    ]
}
