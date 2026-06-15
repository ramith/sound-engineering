import Foundation

// MARK: - AudioFile Model

struct AudioFile: Identifiable {
    let id: UUID = .init()

    /// Track name — filename without extension.
    let name: String

    /// Path relative to the chosen folder, e.g. "Indie/2024/".
    let relativePath: String

    /// Full URL used for playback.
    let absoluteURL: URL

    /// File format uppercased, e.g. "FLAC", "MP3".
    let format: String

    /// Duration in seconds. Populated as 0 until Part 2c metadata extraction.
    let durationSeconds: Double
}

// MARK: - Comparable (locale-aware name sort)

extension AudioFile: Comparable {
    static func < (lhs: AudioFile, rhs: AudioFile) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
