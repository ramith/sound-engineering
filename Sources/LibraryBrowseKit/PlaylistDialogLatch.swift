// MARK: - PlaylistDialogLatch (S10.8 E fix round — the playlist dialogs' state machine; pure + testable)

/// The Library tab's playlist dialog as ONE latched value: which `PlaylistDialog` is up, and the only
/// moves between them. The sheet shows `dialog` and nothing else decides it, so a destructive
/// confirmation can never appear by default (Remove Missing's used to be the sheet's `else` branch),
/// two dialogs never ask for the window at once, a press can never act twice, and what a confirmation
/// acts on is what it asked about.
///
/// - **A confirmation is asked only while nothing is up,** and its Delete / Remove returns what to act
///   on exactly once. Cancel closes it.
/// - **A failure takes the sheet.** A confirmation that was up is DROPPED, not brought back after OK:
///   a destructive question is never re-asked by surprise. A newer failure replaces an older one.
/// - **Remove Missing is asked for exactly the entries missing at that moment.** The set never grows
///   while the confirmation is up; it shrinks as files come back, and the confirmation closes when
///   none are left.
/// - **Remove Missing never during a scan.** While the library is being scanned files flicker
///   "missing", so the confirmation isn't raised then and its Remove does nothing (it stays up, to
///   cancel or wait).
public struct PlaylistDialogLatch: Equatable, Sendable {
    /// The dialog up now, or nil.
    public private(set) var dialog: PlaylistDialog?

    public init() {}

    // MARK: Failure

    /// A playlist action failed: its notice takes the sheet.
    public mutating func fail(_ message: String) {
        dialog = .failure(message)
    }

    /// The notice's OK. Closes a failure, and only a failure.
    public mutating func dismissFailure() {
        if case .failure = dialog {
            dialog = nil
        }
    }

    /// The action behind the failure `message` has since succeeded: its notice goes, if it is still
    /// the one up.
    public mutating func withdrawFailure(_ message: String) {
        if dialog == .failure(message) {
            dialog = nil
        }
    }

    // MARK: Confirmations

    /// A confirmation's Cancel. Closes a confirmation — never a failure.
    public mutating func cancel() {
        switch dialog {
        case .confirmDelete, .confirmRemoveMissing: dialog = nil
        case .failure, nil: break
        }
    }

    /// Delete… on a playlist: ask to delete it. Only while nothing else is up.
    public mutating func askToDelete(playlistID: Int64, name: String) {
        guard dialog == nil else { return }
        dialog = .confirmDelete(playlistID: playlistID, name: name)
    }

    /// The confirmation's Delete: closes it and returns the playlist to delete. Nil while no delete
    /// confirmation is up (a second press; a failure took the sheet).
    public mutating func confirmDelete() -> Int64? {
        guard case let .confirmDelete(playlistID, _) = dialog else { return nil }
        dialog = nil
        return playlistID
    }

    /// Remove Missing… was chosen: raise the confirmation for `missing`, the entries missing now.
    /// Only while nothing else is up, there is something to remove, and no scan is running.
    public mutating func askToRemoveMissing(_ missing: [Int64], isLibraryPopulating: Bool) {
        guard dialog == nil, !missing.isEmpty, !isLibraryPopulating else { return }
        dialog = .confirmRemoveMissing(missing)
    }

    /// The confirmation's Remove: closes it and returns the entries to remove — the confirmed ones,
    /// exactly. Nil while no Remove Missing confirmation is up (a second press; a failure took the
    /// sheet), and during a scan, when the confirmation stays up and nothing is removed.
    public mutating func confirmRemoveMissing(isLibraryPopulating: Bool) -> [Int64]? {
        guard case let .confirmRemoveMissing(entries) = dialog, !isLibraryPopulating else { return nil }
        dialog = nil
        return entries
    }

    /// The open playlist was re-read: `missing` are its missing entries now. A Remove Missing
    /// confirmation keeps the entries that are STILL missing — never a new one — and closes when none
    /// are. (`missing` is read only while that confirmation is up.)
    public mutating func missingChanged(to missing: @autoclosure () -> Set<Int64>) {
        guard case let .confirmRemoveMissing(entries) = dialog else { return }
        let nowMissing = missing()
        let stillMissing = entries.filter(nowMissing.contains)
        dialog = stillMissing.isEmpty ? nil : .confirmRemoveMissing(stillMissing)
    }
}
