// SearchRule+Query — the word-start match (R1.1-B, US-R1F-14): a query finds an item when every word of the
// query starts a word of the item, in any order ("beyo" finds "Beyoncé"; "eyon" does not — founder,
// 2026-10-25). The full-text index matches the same way (`ftsMatchQuery`: one prefix term per query word,
// all required); this is the in-memory side, for the lists the index does not hold.

import Foundation

public extension SearchRule {
    /// A query read once by the rule — its words, folded — to match many items against.
    struct Query: Sendable, Equatable {
        /// The query's words, folded, in the order typed.
        public let words: [String]

        public init(_ text: String) {
            words = SearchRule.words(of: text)
        }

        /// A query with no word in it (empty, spaces, or only punctuation and symbols) finds nothing.
        public var isEmpty: Bool {
            words.isEmpty
        }

        /// Whether every query word starts a word of one of `texts` — an item's texts are one pool: an
        /// album found by "beyo lemo" may have "Beyoncé" as its artist and "Lemonade" as its title.
        public func matches(_ texts: [String]) -> Bool {
            matches(words: texts.flatMap(SearchRule.words(of:)))
        }

        /// `matches` over an item's words, already read by the rule (`SearchRule.words(of:)`).
        public func matches(words itemWords: [String]) -> Bool {
            guard !words.isEmpty else { return false }
            return words.allSatisfy { queryWord in
                itemWords.contains { SearchRule.word($0, startsWith: queryWord) }
            }
        }
    }

    /// Whether `text` matches `query` by the rule (see `Query.matches`).
    static func matches(_ texts: [String], query: String) -> Bool {
        Query(query).matches(texts)
    }

    /// Whether the folded `word` starts with the folded `prefix`, code point by code point (a UTF-8 byte
    /// prefix is a code-point prefix) — as the index's prefix query compares.
    static func word(_ word: String, startsWith prefix: String) -> Bool {
        word.utf8.starts(with: prefix.utf8)
    }

    /// Whether `text` begins with `prefix`, both folded by the rule (`folded`) — type-to-select's shape:
    /// the title's start ("the b" selects "The Beatles"; "beyo" selects "Beyoncé").
    static func text(_ text: String, startsWith prefix: String) -> Bool {
        folded(text).utf8.starts(with: folded(prefix).utf8)
    }

    /// `text` with every word character folded by the rule and every other character kept — what
    /// type-to-select compares a title's start with. Plain ASCII is only lowercased.
    static func folded(_ text: String) -> String {
        guard !text.utf8.allSatisfy({ $0 < 0x80 }) else { return text.lowercased() }
        var scalars = String.UnicodeScalarView()
        for scalar in normalized(text).unicodeScalars {
            if isWordScalar(scalar) {
                fold(scalar, into: &scalars)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
