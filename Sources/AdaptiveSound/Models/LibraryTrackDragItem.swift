import CoreTransferable

/// Transferable payload for dragging a LIBRARY track onto a playlist (S10.3 US-PLIST-03/04). Carries
/// only the track's stable `tracks.id` — a reference-ADD by id, which by construction can NEVER move
/// or copy a file (US-PLIST-04). Same plain-text `ProxyRepresentation` rationale as the other drag
/// items (a custom UTType not declared in Info.plist silently fails drop-type matching); a foreign
/// text drop imports to a nonexistent id that the DAO's FK rejects, so it safely no-ops.
struct LibraryTrackDragItem: Transferable {
    let trackID: Int64

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { (item: LibraryTrackDragItem) in String(item.trackID) },
            importing: { (string: String) in LibraryTrackDragItem(trackID: Int64(string) ?? -1) }
        )
    }
}
