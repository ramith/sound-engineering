import CoreTransferable

/// Transferable payload for dragging a queue row to reorder it. Carries the row's stable
/// `QueueItem.id` (not its index), so the drop resolves the CURRENT position even if the queue
/// shifted mid-drag. Used with `.draggable` on the row's grip handle + `.dropDestination` on the
/// row — the reliable macOS reorder path, since a `List` row's `.dropDestination` never fires.
///
/// Transferred as the id's UUID string (`ProxyRepresentation` over `String`): a plain-text
/// representation is ALWAYS registered, whereas a custom `UTType(exportedAs:)` that isn't declared
/// in Info.plist silently fails drop-type matching (the drop target never activates — observed).
/// A foreign text drop imports to a random UUID that matches no row, so `moveByDrop` safely no-ops.
struct QueueDragItem: Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { (item: QueueDragItem) in item.id.uuidString },
            importing: { (string: String) in QueueDragItem(id: UUID(uuidString: string) ?? UUID()) }
        )
    }
}
