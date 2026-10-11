import LibraryStore

// MARK: - Detail row model (S10.3 — one row of an open playlist; moved out of `PlaylistsModel.swift`)

/// One row of an open playlist: its `PlaylistEntry` (the stable id + position — the reorder/remove
/// key Chunk C needs) plus the resolved library track, or nil when the track can't be resolved
/// (moved/deleted — Chunk F renders the "unavailable" state + Locate). `Identifiable` on the ENTRY
/// id (not the track) so duplicates of the same track in one playlist stay distinct rows.
struct PlaylistDetailEntry: Identifiable {
    let entry: PlaylistEntry
    let display: LibraryTrackDisplay?
    /// True when the track resolved AND its file exists on disk (S10.3 F). False = "unavailable":
    /// the file moved/was deleted (a loose file gone, or a move not yet reconciled) or the track row
    /// is absent — the row is badged, SKIPPED on play (never halts), and offered Locate / Remove.
    let isAvailable: Bool

    var id: Int64 {
        entry.id
    }
}
