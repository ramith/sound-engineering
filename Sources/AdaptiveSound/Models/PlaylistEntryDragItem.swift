import CoreTransferable

/// Transferable payload for dragging a playlist-entry row to reorder it within its playlist (S10.3).
/// Carries the entry's stable `PlaylistEntry.id` (not its index), so the drop resolves the CURRENT
/// position even if the list shifted mid-drag. Same rationale as `QueueDragItem`: a plain-text
/// `ProxyRepresentation` (an undeclared custom UTType silently fails drop-type matching); a foreign
/// text drop imports to an id that matches no entry, so the reorder safely no-ops.
struct PlaylistEntryDragItem: Transferable {
    let entryID: Int64

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { (item: PlaylistEntryDragItem) in String(item.entryID) },
            importing: { (string: String) in PlaylistEntryDragItem(entryID: Int64(string) ?? -1) }
        )
    }
}
