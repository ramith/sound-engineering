import Foundation

// MARK: - TypeSelectBuffer (S10.8 E1 — the search text behind a list's type-to-select)

/// The search text of a list's type-to-select, kept the way a macOS list keeps it: each typed
/// character extends the search, and a pause longer than `resetInterval` starts a new one — so
/// "b", "e" typed quickly finds "Beatles", while "b" … (pause) … "e" finds "Eagles". Any other
/// selection change (a click, an arrow) ends the search at once (`reset`).
struct TypeSelectBuffer: Sendable {
    /// The pause that ends a search — about a second, as in a macOS list.
    static let resetInterval: Duration = .seconds(1)

    private var text = ""
    private var lastKey: ContinuousClock.Instant?

    /// Adds `typed` to the search, first starting over if the last key is older than
    /// `resetInterval`; returns the whole search text.
    mutating func append(_ typed: String, at now: ContinuousClock.Instant) -> String {
        if let lastKey, lastKey.duration(to: now) > Self.resetInterval {
            text = ""
        }
        text += typed
        lastKey = now
        return text
    }

    mutating func reset() {
        text = ""
        lastKey = nil
    }

    /// Whether `title` starts with `search`, ignoring case and diacritics in the user's locale —
    /// "beyo" finds "Beyoncé", the type-select twin of the filters' `localizedStandardContains`.
    static func title(_ title: String, startsWith search: String) -> Bool {
        title.range(of: search, options: [.anchored, .caseInsensitive, .diacriticInsensitive],
                    locale: .current) != nil
    }
}
