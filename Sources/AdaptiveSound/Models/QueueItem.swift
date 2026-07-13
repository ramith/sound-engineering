import Foundation

// MARK: - QueueItem

/// One slot in the play queue (S10.2).
///
/// Wraps the URL-keyed `AudioFile` the engine actually plays with a **stable `UUID` identity**,
/// so the SAME track can appear more than once in the queue without breaking SwiftUI's id-keyed
/// `ForEach` (the S9 URL-identity contract forbade duplicates; S10.2 lifts that). The `id` is
/// assigned once at creation and never changes.
///
/// (Sub-step 2b adds a `trackID: Int64?` here to mirror the queue to the persistent "current"
/// playlist and attribute play counts by durable id.)
struct QueueItem: Identifiable {
    /// Stable per-slot identity for SwiftUI. Decoupled from the file URL and from the DB id.
    let id: UUID
    /// What the engine plays (URL-keyed; unchanged).
    let file: AudioFile

    init(file: AudioFile, id: UUID = UUID()) {
        self.id = id
        self.file = file
    }
}
