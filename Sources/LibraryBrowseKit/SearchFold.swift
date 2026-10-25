import LibraryStore

// MARK: - SearchFold — the one search rule, as the selection kit reads it (R1.1-B, US-R1F-14)

/// The Library's one search rule (`SearchRule`, LibraryStore) for the selection kit, which may not import
/// the store (COL-01, semgrep `selection-kit-no-columns`): type-to-select (`TypeSelectBuffer`) compares a
/// title's start by it — case, width and a Latin letter's accents ignored, every other script's marks
/// kept, the zero-width joiners folded away — exactly as the Songs search and the Filters read a word.
enum SearchFold {
    /// Whether `text` begins with `prefix`, both read by the rule (`SearchRule.text(_:startsWith:)`).
    static func text(_ text: String, startsWith prefix: String) -> Bool {
        SearchRule.text(text, startsWith: prefix)
    }
}
