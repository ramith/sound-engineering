import Foundation
import LibraryScan
import UniformTypeIdentifiers

// MARK: - Loose files (R1.1-B, US-LIB-02 / US-PLIST-02 — a file outside every music folder)

/// What the app makes of files handed to it from outside the library — Open…, a drop, Open With: which it
/// plays (or adds to a playlist) and which it passes over. A file plays when it is an audio file of a kind
/// the library admits (`LibraryScanner.supportedExtensions` — the one list); a folder, or a file of another
/// kind, is passed over and said so. Playing a loose file never adds it to the library (no `tracks` row);
/// adding it to a playlist does, as a song in no music folder (`LibraryStore.addLooseFileToPlaylist`).
public enum LooseFiles {
    /// The files an open plays, in the order given (each once), and the ones it passes over.
    public struct Plan: Equatable, Sendable {
        public let playable: [URL]
        public let skipped: [URL]
    }

    /// An open read off the caller's actor: its plan, and what to say of what it passed over.
    public struct Opened: Equatable, Sendable {
        public let plan: Plan
        public let skippedMessage: String?
    }

    /// `plan` and `skippedMessage` for `urls`, read off the caller's actor: each file needs a look at the disk
    /// (is it a folder?), and 300 files dropped from a spun-down disk or a network share must never stall
    /// the main thread (R1.1-B fix round, review S2).
    @concurrent
    public static func planned(_ urls: [URL]) async -> Opened {
        let plan = plan(urls)
        return Opened(plan: plan, skippedMessage: skippedMessage(plan.skipped))
    }

    /// The files among `urls` that may play, judged by name alone — no look at the disk, so a drop target
    /// can answer at once whether it takes a drop: the audio files the library admits, in the order given,
    /// each once. What is not a file after all (a folder named "x.flac") is passed over by the add that
    /// reads it (`LibraryScanner.makeScannedFile`).
    public static func candidates(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { isPlayable($0) && seen.insert($0.standardizedFileURL).inserted }
    }

    /// Sort `urls` into what plays and what does not. `isDirectory` reads the disk (a seam for tests): never
    /// call this on the main actor with the default — use `planned`.
    public static func plan(_ urls: [URL], isDirectory: (URL) -> Bool = LooseFiles.isDirectory) -> Plan {
        var seen = Set<URL>()
        var playable: [URL] = []
        var skipped: [URL] = []
        for url in urls where seen.insert(url.standardizedFileURL).inserted {
            if !isDirectory(url), isPlayable(url) {
                playable.append(url)
            } else {
                skipped.append(url)
            }
        }
        return Plan(playable: playable, skipped: skipped)
    }

    /// Whether `url` names an audio file of a kind the library admits (by its extension, as a walk judges).
    public static func isPlayable(_ url: URL) -> Bool {
        LibraryScanner.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// The kinds of file Open… offers: one per extension the library admits that the system knows as audio
    /// (FLAC, MP3, WAV, AAC, M4A, AIFF, Ogg — "Opus" and "Oga" are Ogg audio to it).
    public static var contentTypes: [UTType] {
        var types: [UTType] = []
        for ext in LibraryScanner.supportedExtensions.sorted() {
            if let type = UTType(filenameExtension: ext), type.conforms(to: .audio), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    /// Whether a directory is at `url`.
    public static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// What the app says about the files an open passed over — nil when it passed over none.
    public static func skippedMessage(_ skipped: [URL], isDirectory: (URL) -> Bool = LooseFiles.isDirectory)
        -> String? {
        guard let first = skipped.first else { return nil }
        if skipped.count == 1 {
            return isDirectory(first)
                ? "“\(first.lastPathComponent)” is a folder — add it under Music Folders to play it."
                : "Can’t play “\(first.lastPathComponent)” — it isn’t an audio file this app plays."
        }
        return "Skipped \(skipped.count.formatted()) items that aren’t audio files this app plays."
    }
}

// MARK: - What a playlist add holds

/// One thing to add to a playlist: a library song, by its id, or a file outside the library, by its URL —
/// which the add makes a song in no music folder (US-PLIST-02). Either way a REFERENCE-add: nothing on
/// disk moves (US-PLIST-04).
public enum PlaylistAddItem: Hashable, Sendable {
    case track(Int64)
    case file(URL)

    /// A file from outside the library (its tags are read once it is added).
    public var isFile: Bool {
        if case .file = self {
            true
        } else {
            false
        }
    }
}
