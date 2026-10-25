import Foundation

// MARK: - PlaylistDropRouter (S10.3 US-PLIST-03/04 — a drop onto a playlist is ADD-ONLY)

/// What a drop onto a playlist resolves to: adding library songs by id, or files from outside the
/// library by their URL (R1.1-B, US-PLIST-02 — each becomes a song in no music folder). Both are
/// REFERENCE-adds: the absence of any `moveFile`/`copyFile` case makes "a drop can never touch the
/// filesystem" a TYPE-LEVEL guarantee (US-PLIST-04), not just a convention — the drop handler can only
/// ever hand these to the playlist's add.
public enum PlaylistDropOutcome: Equatable {
    case addTracks([Int64])
    case addFiles([URL])
}

/// Routes a drop onto a playlist. Pure + testable so the add-only contract is provable without SwiftUI
/// or the store. A drag of library rows carries track ids (`LibraryTrackDragItem`); a drag from Finder
/// carries file URLs, of which only audio files the library admits are added (`LooseFiles`).
public enum PlaylistDropRouter {
    public static func route(droppedTrackIDs ids: [Int64]) -> PlaylistDropOutcome {
        .addTracks(PlaylistAddDecision.trackIDsToAdd(ids))
    }

    /// A drop of files from Finder: the playable ones, each once, in the order dropped.
    public static func route(droppedFiles urls: [URL],
                             isDirectory: (URL) -> Bool = LooseFiles.isDirectory) -> PlaylistDropOutcome {
        .addFiles(LooseFiles.plan(urls, isDirectory: isDirectory).playable)
    }
}
