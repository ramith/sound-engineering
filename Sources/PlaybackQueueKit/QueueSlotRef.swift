// PlaybackQueueKit — how a persisted queue slot names what it plays (R1.1-B, seam S5).
//
// The queue's mirror in the store keeps only slots that have a library track; a loose file — one
// outside every scan folder, opened by Open…, a drop or Open With — has none, so it was dropped from
// the persisted queue (plan check §0.7). The crash-restore record and the loose-file entry points
// both name a slot through this one type, so a loose file survives a relaunch without a `tracks` row.

/// What a persisted queue slot plays: a library track by its id, or a loose file by its path.
///
/// The encoded form is part of the persisted queue state, so the case and label names are frozen:
/// `{"track":{"id":42}}` and `{"loose":{"path":"/Volumes/T7/a.flac"}}`. Add a case; never rename one.
public enum QueueSlotRef: Codable, Equatable, Hashable, Sendable {
    /// A song in the library, by its `tracks.id`.
    case track(id: Int64)
    /// A file outside every scan folder, by its absolute path. It has no `tracks` row.
    case loose(path: String)
}
