import Foundation
import PlaybackQueueKit

// MARK: - AudioFile Model

struct AudioFile: Identifiable {
    /// STABLE identity = the file's URL. A folder re-scan of unchanged files produces the SAME
    /// ids, so `ForEach(id: \.element.id)` keeps row identity and SwiftUI updates only what
    /// actually changed. (A per-construction `UUID()` made every row "new" on each folder-monitor
    /// refresh → the whole playlist — and the window — rebuilt/flickered on any folder change.)
    var id: URL {
        absoluteURL
    }

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

    /// Durable `tracks.id` of the backing library row, when this file came from the library
    /// (`nil` for a file with no store row — e.g. a loose file). Carried so the queue can be
    /// mirrored to the persistent "current" playlist and play-counts attributed by id (S10.2).
    /// Does NOT affect `id` (still the URL) — purely metadata; defaulted so existing callers
    /// that build an `AudioFile` without a library row are unaffected.
    var trackID: Int64? = nil
}

// MARK: - Loose files (R1.1-B, US-LIB-02) and the persisted slot (seam S5)

extension AudioFile {
    /// A file outside every music folder — opened by Open…, a drop or Open With — as the queue plays it:
    /// named by its file name (its tags are read for Now Playing, `EmbeddedMetadataReader`), with no
    /// library row (`trackID` nil): playing it alone never adds it to the library (US-LIB-02).
    init(looseFileAt url: URL) {
        self.init(
            name: url.deletingPathExtension().lastPathComponent,
            relativePath: "",
            absoluteURL: url,
            format: url.pathExtension.uppercased(),
            durationSeconds: 0
        )
    }

    /// How a persisted queue names this slot (PlaybackQueueKit `QueueSlotRef`, seam S5): a library song by
    /// its `tracks.id` — so it re-resolves after its folder moves drive ("Use this drive") — and a loose
    /// file by its path, with no `tracks` row.
    var slotRef: QueueSlotRef {
        if let trackID {
            return .track(id: trackID)
        }
        return .loose(path: absoluteURL.path)
    }
}

// MARK: - Comparable (locale-aware name sort)

extension AudioFile: Comparable {
    static func < (lhs: AudioFile, rhs: AudioFile) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
