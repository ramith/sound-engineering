import LibraryScan
import LibraryStore

// MARK: - Detail row model (S10.3 — one row of an open playlist; moved out of `PlaylistsModel.swift`)

/// One row of an open playlist: its `PlaylistEntry` (the stable id + position — the reorder/remove
/// key Chunk C needs) plus the resolved library track, or nil when the track can't be resolved
/// (moved/deleted — Chunk F renders the "unavailable" state + Locate). `Identifiable` on the ENTRY
/// id (not the track) so duplicates of the same track in one playlist stay distinct rows.
struct PlaylistDetailEntry: Identifiable {
    let entry: PlaylistEntry
    let display: LibraryTrackDisplay?
    /// Whether the song's file can be played now (`FileAvailability`, S10.3 F; R1.1-A KI-LIB-01). Not
    /// available = "unavailable": the row is badged, SKIPPED on play (never halts), and offered Locate /
    /// Remove. Only a MISSING one — its folder there, on its own drive, the file not (or the track row
    /// gone) — is offered to Remove Missing…; an UNREACHABLE one (its drive unplugged, another drive at
    /// its path) may well be fine, and is kept.
    let availability: FileAvailability

    var id: Int64 {
        entry.id
    }

    /// The song can be played now.
    var isAvailable: Bool {
        availability == .available
    }
}
