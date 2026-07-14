import Foundation

/// One entry in the session play-history — a stable-identity wrapper around a played file, so the
/// History list has dups-safe `ForEach` identity (the same track can be played repeatedly in a
/// session). Session-scoped + in-memory ONLY: NOT persisted across relaunch, and NOT cleared by
/// Clear Queue (founder §3a: "Session; Clear keeps it"). Mirrors `QueueItem`'s shape but is a
/// distinct type — a history entry is a past play, not a queue slot.
struct HistoryItem: Identifiable {
    let id: UUID
    let file: AudioFile

    init(file: AudioFile, id: UUID = UUID()) {
        self.id = id
        self.file = file
    }
}
