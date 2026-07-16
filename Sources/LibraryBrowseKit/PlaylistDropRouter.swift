// MARK: - PlaylistDropRouter (S10.3 US-PLIST-03/04 — a drop onto a playlist is ADD-ONLY)

/// What a drop of library tracks onto a playlist resolves to. There is EXACTLY ONE case: adding
/// track ids by reference. The absence of any `moveFile`/`copyFile` case makes "a drop can never
/// touch the filesystem" a TYPE-LEVEL guarantee (US-PLIST-04), not just a convention — the drop
/// handler can only ever hand these ids to `appendEntries`.
public enum PlaylistDropOutcome: Equatable {
    case addTracks([Int64])
}

/// Routes a library-track drop onto a playlist. Pure + testable so the add-only contract is provable
/// without SwiftUI or the store. The drop destination is typed to `LibraryTrackDragItem` (a track
/// id), so a file-URL / audio-file drag never matches in the first place; this collapses whatever
/// track ids arrived into the reference-add, de-duplicated in first-seen order.
public enum PlaylistDropRouter {
    public static func route(droppedTrackIDs ids: [Int64]) -> PlaylistDropOutcome {
        .addTracks(PlaylistAddDecision.trackIDsToAdd(ids))
    }
}
