// AlbumGrouping+Names — the names and folders half of the album rule (S10.8 C2, fix round).
//
// How a tag value is normalised (C5), when an artist counts as missing (C4), when two spellings
// are one artist for a credit (NFC/NFD, case, and "X feat. Y" → X — C6), and which subfolders
// fold into their album folder (disc and bonus folders — C2). Pure string functions; the core
// rule is `AlbumGrouping.swift`.

import Foundation

public extension AlbumGrouping {
    /// A tag value as the store keeps it (C5): whitespace-trimmed and NFC-normalised; nil when
    /// that leaves nothing. `TrackMetadata.init` runs every album title through it, so "Abbey Road "
    /// and "Abbey Road", or an NFC and an NFD "Café", are the same bytes in the store's SQL.
    static func normalizedTag(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.precomposedStringWithCanonicalMapping
    }

    /// An artist or album-artist tag, normalised (`normalizedTag`), or nil when the artist is
    /// MISSING (C4): empty, whitespace-only, or a literal "Unknown Artist" in any case or Unicode
    /// form — the ONE missing rule for both. A literal "Unknown Artist" album-artist tag is no tag,
    /// so CD-ripper "Unknown Album"s in different folders never merge into one.
    static func presentArtist(_ value: String?) -> String? {
        guard let name = normalizedTag(value), sameArtistKey(name) != missingArtistKey else { return nil }
        return name
    }

    /// Two spellings are ONE artist for the credit when they differ only by Unicode normalisation
    /// (NFC vs NFD — "Zoë" typed vs read from a decomposed tag) or by case. Artist ROWS keep their
    /// exact spelling (S8 identity); this only stops such variants faking "mixed artists".
    static func sameArtistKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The PRIMARY artist of a credit (C6): the name before " feat. …", " ft. …" or " featuring …"
    /// (also bracketed: " (feat. …)", " [ft. …]"), so "Mara Lind feat. X" and "Mara Lind" are one
    /// artist when deciding shared vs "Various Artists". The artist rows keep the full names.
    static func primaryArtist(_ name: String) -> String {
        let cuts = featuringMarkers.compactMap { name.range(of: $0, options: .caseInsensitive)?.lowerBound }
        guard let cut = cuts.min() else { return name }
        let primary = name[..<cut].trimmingCharacters(in: .whitespaces)
        return primary.isEmpty ? name : primary
    }

    /// The album folder of a song (C2): the folder holding the file, with disc and bonus
    /// subfolders ("CD 1", "Disc 2 of 2", "[CD 1]", "Bonus Tracks", "Extras" …) folded into their
    /// parent — so a set ripped one folder per disc, or with its bonus tracks in a subfolder, is
    /// one album. A REAL album folder named like a disc ("…/X/CD 1" holding the album "CD 1")
    /// still groups: its songs key on (title "CD 1", folder "…/X").
    static func albumFolder(ofTrackPath path: String) -> String {
        var folder = (path as NSString).deletingLastPathComponent
        while isFoldedFolderName((folder as NSString).lastPathComponent) {
            let parent = (folder as NSString).deletingLastPathComponent
            guard parent != folder else { break }
            folder = parent
        }
        return folder
    }

    /// Whether a subfolder name is a disc or bonus folder that folds into its parent (C2). A disc
    /// folder is JUST a disc marker: "cd" / "disc" / "disk", optional separators (space - _ . #), a
    /// small number (below 100, up to 3 digits) or a number word ("One"…"Ten") — then, optionally,
    /// " of N", and optionally a " - subtitle" or a bracketed note ("Disc 1 of 2", "CD1 - Live",
    /// "Disc 1 (Remastered)"); brackets around the whole name ("[CD 1]") are ignored. Anything else
    /// is an album folder of its own: "CD Collection", "Discography", "CD 1234", "CD 100 Hits".
    static func isFoldedFolderName(_ name: String) -> Bool {
        var lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.count >= 2, let first = lower.first, let last = lower.last, "[(".contains(first), "])".contains(last) {
            lower = String(lower.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if bonusFolderNames.contains(lower) {
            return true
        }
        guard let prefix = ["disc", "disk", "cd"].first(where: { lower.hasPrefix($0) }) else { return false }
        let afterPrefix = lower.dropFirst(prefix.count).drop { " -_.#".contains($0) }
        let digits = afterPrefix.prefix { $0.isASCII && $0.isNumber }
        if (1 ... 3).contains(digits.count), let number = Int(digits), number < 100 {
            return isDiscQualifier(afterPrefix.dropFirst(digits.count))
        }
        guard let word = discNumberWords.first(where: { afterPrefix.hasPrefix($0) }) else { return false }
        return isDiscQualifier(afterPrefix.dropFirst(word.count))
    }

    /// What may follow a disc number (C2 final round): nothing; " of N"; then nothing, a " - subtitle"
    /// (any dash or a colon) or a bracketed note. "CD1 - Live" and "Disc 1 (Remastered)" qualify; the
    /// " Hits" of "CD 100 Hits" does not.
    private static func isDiscQualifier(_ rest: Substring) -> Bool {
        var tail = rest.drop { $0 == " " }
        if tail.hasPrefix("of") {
            let afterOf = tail.dropFirst(2).drop { $0 == " " }
            let total = afterOf.prefix { $0.isASCII && $0.isNumber }
            guard (1 ... 3).contains(total.count) else { return false }
            tail = afterOf.dropFirst(total.count).drop { $0 == " " }
        }
        guard let first = tail.first else { return true }
        if "-–—:".contains(first) {
            return !tail.dropFirst().trimmingCharacters(in: .whitespaces).isEmpty
        }
        return "([".contains(first) && tail.last.map { ")]".contains($0) } == true
    }
}

// MARK: - Tables

private extension AlbumGrouping {
    /// `sameArtistKey` of the one missing-artist string (C4).
    static let missingArtistKey = sameArtistKey(unknownArtistName)

    /// " feat. ", " (ft ", " [featuring " … — every way a featured artist is set off (C6).
    static let featuringMarkers: [String] = ["", "(", "["].flatMap { opener in
        ["feat.", "feat", "ft.", "ft", "featuring"].map { " \(opener)\($0) " }
    }

    /// Bonus subfolders that hold an album's extra tracks (C2), lowercased.
    static let bonusFolderNames: Set<String> = [
        "bonus", "bonus tracks", "bonus track", "bonus disc", "bonus cd", "extras",
    ]

    /// Spelled-out disc numbers ("Disc One"), lowercased.
    static let discNumberWords = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
}
