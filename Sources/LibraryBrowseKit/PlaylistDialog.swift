// MARK: - PlaylistDialog (S10.8 E fix round — the Library tab's one playlist dialog)

/// The dialog the Library tab shows for its playlists — one at a time, on one sheet. Held, and moved
/// between, by `PlaylistDialogLatch` alone.
public enum PlaylistDialog: Equatable, Sendable, Identifiable {
    /// A playlist action failed — a delete, a create, an add, a remove, Locate, Remove Missing, saving
    /// an order: the reason, and OK.
    case failure(String)
    /// Deleting this playlist waits on its confirmation.
    case confirmDelete(playlistID: Int64, name: String)
    /// The bulk Remove Missing waits on its confirmation, for exactly these entries: the ones whose
    /// files were missing when it was asked, less any that have come back since.
    case confirmRemoveMissing([Int64])

    /// The sheet's identity: a confirmation's own (the Remove Missing one keeps it as its entries shrink),
    /// and a notice per reason — so a newer failure shows as a new notice.
    public var id: String {
        switch self {
        case let .failure(message): "failure: \(message)"
        case let .confirmDelete(playlistID, _): "confirm-delete: \(playlistID)"
        case .confirmRemoveMissing: "confirm-remove-missing"
        }
    }
}
