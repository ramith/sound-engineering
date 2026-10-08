import Foundation

// MARK: - TypeSelectBuffer (S10.8 — the ONE type-to-select: the Songs selection kit (E1) and the browse grids (decision 20))

/// Type-to-select, the Finder / `NSTableView` way: letters typed in quick succession build one
/// prefix ("j", "ja", "jaz"), and the first item in display order whose title starts with it —
/// ignoring case, accents and width — becomes the cursor. A pause longer than `timeout` starts a
/// new prefix. Only prefixes: no "closest match" guess, so an unsorted (filtered) list never jumps
/// somewhere the user didn't type.
public struct TypeSelectBuffer: Sendable {
    /// The pause that ends a prefix (the system's type-select feel).
    static let timeout: Duration = .seconds(1)

    /// The prefix typed so far.
    private var prefix = ""
    private var lastKey: ContinuousClock.Instant?

    public init() {}

    /// Adds `characters` typed at `now`, starting over after a pause longer than `timeout`, and
    /// returns the prefix to match.
    public mutating func append(_ characters: String, at now: ContinuousClock.Instant) -> String {
        if let lastKey, lastKey.duration(to: now) > Self.timeout {
            prefix = ""
        }
        prefix += characters
        lastKey = now
        return prefix
    }

    /// Ends the prefix at once — any other selection change (a click, an arrow) does.
    public mutating func reset() {
        prefix = ""
        lastKey = nil
    }

    /// The first element in display order whose title starts with `prefix` (case-, diacritic- and
    /// width-insensitive: "beyo" finds "Beyoncé"), or nil — also for an empty prefix.
    public static func firstMatch<Items: Sequence>(
        for prefix: String, in items: Items, title: (Items.Element) -> String
    ) -> Items.Element? {
        guard !prefix.isEmpty else { return nil }
        let options: String.CompareOptions = [.anchored, .caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return items.first { title($0).range(of: prefix, options: options) != nil }
    }
}
