import LibraryBrowseKit
import Testing

// MARK: - PlaylistDialogLatch — the playlist dialogs' state machine (S10.8 E fix round, PL-DLG)

@Suite("PlaylistDialogLatch — one latched playlist dialog (PL-DLG)")
struct PlaylistDialogLatchTests {
    /// A latch with the Remove Missing confirmation up for `entries`.
    private static func confirming(_ entries: [Int64]) -> PlaylistDialogLatch {
        var latch = PlaylistDialogLatch()
        latch.askToRemoveMissing(entries, isLibraryPopulating: false)
        return latch
    }

    // MARK: Nothing shows by default

    @Test("PL-DLG-01: a new latch shows nothing — the confirmation is never the default")
    func startsClosed() {
        #expect(PlaylistDialogLatch().dialog == nil)
    }

    @Test("PL-DLG-02: with nothing up, Delete, Remove, Cancel, OK and a re-read do nothing and return nothing")
    func verbsOnAClosedLatchAreInert() {
        var latch = PlaylistDialogLatch()
        #expect(latch.confirmDelete() == nil)
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == nil)
        latch.cancel()
        latch.dismissFailure()
        latch.withdrawFailure("x")
        latch.missingChanged(to: [1, 2])
        #expect(latch.dialog == nil)
    }

    // MARK: Asking

    @Test("PL-DLG-03: asking raises the confirmation for exactly the entries missing then, in order")
    func askCapturesTheEntries() {
        #expect(Self.confirming([7, 3, 9]).dialog == .confirmRemoveMissing([7, 3, 9]))
    }

    @Test("PL-DLG-04: nothing missing, or a scan running → no confirmation")
    func askIsGuarded() {
        var latch = PlaylistDialogLatch()
        latch.askToRemoveMissing([], isLibraryPopulating: false)
        #expect(latch.dialog == nil)
        latch.askToRemoveMissing([1, 2], isLibraryPopulating: true)
        #expect(latch.dialog == nil)
    }

    @Test("PL-DLG-05: asking while a dialog is up changes nothing — not a failure, not the confirmed set")
    func askWhileUpIsIgnored() {
        var failed = PlaylistDialogLatch()
        failed.fail("no")
        failed.askToRemoveMissing([1], isLibraryPopulating: false)
        #expect(failed.dialog == .failure("no"))

        var confirming = Self.confirming([1, 2])
        confirming.askToRemoveMissing([1, 2, 3, 4], isLibraryPopulating: false)
        #expect(confirming.dialog == .confirmRemoveMissing([1, 2]))
    }

    // MARK: Confirming

    @Test("PL-DLG-06: Remove returns the confirmed entries once and closes; a second press returns nothing")
    func confirmIsLatched() {
        var latch = Self.confirming([4, 5])
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == [4, 5])
        #expect(latch.dialog == nil)
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == nil)
    }

    @Test("PL-DLG-07: during a scan Remove removes nothing and the confirmation stays up, to cancel or wait")
    func confirmDuringAScan() {
        var latch = Self.confirming([4, 5])
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: true) == nil)
        #expect(latch.dialog == .confirmRemoveMissing([4, 5]))
        // The scan ends: the same confirmation removes the same entries.
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == [4, 5])
    }

    @Test("PL-DLG-08: Cancel closes the confirmation and removes nothing afterwards")
    func cancel() {
        var latch = Self.confirming([4, 5])
        latch.cancel()
        #expect(latch.dialog == nil)
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == nil)
    }

    // MARK: The missing set changes under an open confirmation

    @Test("PL-DLG-09: more files go missing while it is up → the confirmed set does not grow")
    func confirmedSetNeverGrows() {
        var latch = Self.confirming([1, 2])
        latch.missingChanged(to: [1, 2, 3, 4, 5])
        #expect(latch.dialog == .confirmRemoveMissing([1, 2]))
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == [1, 2])
    }

    @Test("PL-DLG-10: a file comes back → its entry leaves the confirmed set; a new missing one never joins")
    func confirmedSetShrinks() {
        var latch = Self.confirming([1, 2, 3])
        latch.missingChanged(to: [3, 1, 8])
        #expect(latch.dialog == .confirmRemoveMissing([1, 3]))
    }

    @Test("PL-DLG-11: none of the confirmed entries is missing any more → the confirmation closes")
    func closesWhenNothingIsLeft() {
        var latch = Self.confirming([1, 2])
        latch.missingChanged(to: [9])
        #expect(latch.dialog == nil)

        var emptied = Self.confirming([1, 2])
        emptied.missingChanged(to: [])
        #expect(emptied.dialog == nil)
    }

    @Test("PL-DLG-12: the missing set is read only while a confirmation is up")
    func missingIsReadLazily() {
        var reads = 0
        func missing() -> Set<Int64> {
            reads += 1
            return [1]
        }
        var closed = PlaylistDialogLatch()
        closed.missingChanged(to: missing())
        var failed = PlaylistDialogLatch()
        failed.fail("no")
        failed.missingChanged(to: missing())
        #expect(reads == 0)
        #expect(failed.dialog == .failure("no"))

        var confirming = Self.confirming([1])
        confirming.missingChanged(to: missing())
        #expect(reads == 1)
    }

    // MARK: Failures

    @Test("PL-DLG-13: a failure takes the sheet and DROPS an open confirmation — OK does not bring it back")
    func failureDropsTheConfirmation() {
        var latch = Self.confirming([1, 2])
        latch.fail("Couldn’t save the new order")
        #expect(latch.dialog == .failure("Couldn’t save the new order"))
        // The dropped confirmation's buttons do nothing now.
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == nil)
        latch.cancel()
        #expect(latch.dialog == .failure("Couldn’t save the new order"))
        latch.dismissFailure()
        #expect(latch.dialog == nil)
    }

    @Test("PL-DLG-14: a newer failure replaces an older one, as a new notice")
    func newerFailureReplaces() {
        var latch = PlaylistDialogLatch()
        latch.fail("first")
        let first = latch.dialog?.id
        latch.fail("second")
        #expect(latch.dialog == .failure("second"))
        #expect(latch.dialog?.id != first)
    }

    @Test("PL-DLG-15: OK closes a failure only — never a confirmation; Cancel closes a confirmation only")
    func dismissAndCancelAreScoped() {
        var latch = Self.confirming([1])
        latch.dismissFailure()
        #expect(latch.dialog == .confirmRemoveMissing([1]))

        var deleting = PlaylistDialogLatch()
        deleting.askToDelete(playlistID: 4, name: "Focus")
        deleting.dismissFailure()
        #expect(deleting.dialog == .confirmDelete(playlistID: 4, name: "Focus"))

        var failed = PlaylistDialogLatch()
        failed.fail("no")
        failed.cancel()
        #expect(failed.dialog == .failure("no"))
    }

    @Test("PL-DLG-16: a failure is withdrawn only while it is the one up")
    func withdrawFailure() {
        var latch = PlaylistDialogLatch()
        latch.fail("order of A")
        latch.withdrawFailure("order of B")
        #expect(latch.dialog == .failure("order of A"))
        latch.withdrawFailure("order of A")
        #expect(latch.dialog == nil)

        var confirming = Self.confirming([1])
        confirming.withdrawFailure("order of A")
        #expect(confirming.dialog == .confirmRemoveMissing([1]))
    }

    @Test("PL-DLG-17: the confirmation keeps one sheet identity as its set shrinks; a failure's is its own")
    func sheetIdentity() {
        var latch = Self.confirming([1, 2])
        let before = latch.dialog?.id
        latch.missingChanged(to: [2])
        #expect(latch.dialog?.id == before)
        latch.fail("no")
        #expect(latch.dialog?.id != before)
    }

    // MARK: Delete a playlist

    @Test("PL-DLG-18: Delete… asks for that playlist; its Delete returns it once and closes")
    func deleteIsLatched() {
        var latch = PlaylistDialogLatch()
        latch.askToDelete(playlistID: 4, name: "Focus")
        #expect(latch.dialog == .confirmDelete(playlistID: 4, name: "Focus"))
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == nil) // not this confirmation's verb
        #expect(latch.confirmDelete() == 4)
        #expect(latch.dialog == nil)
        #expect(latch.confirmDelete() == nil)
    }

    @Test("PL-DLG-19: Cancel closes the delete confirmation and deletes nothing afterwards")
    func cancelDelete() {
        var latch = PlaylistDialogLatch()
        latch.askToDelete(playlistID: 4, name: "Focus")
        latch.cancel()
        #expect(latch.dialog == nil)
        #expect(latch.confirmDelete() == nil)
    }

    @Test("PL-DLG-20: one dialog at a time — Delete… while another is up changes nothing, and vice versa")
    func oneDialogAtATime() {
        var latch = Self.confirming([1])
        latch.askToDelete(playlistID: 4, name: "Focus")
        #expect(latch.dialog == .confirmRemoveMissing([1]))

        var deleting = PlaylistDialogLatch()
        deleting.askToDelete(playlistID: 4, name: "Focus")
        deleting.askToDelete(playlistID: 5, name: "Sunday")
        deleting.askToRemoveMissing([1], isLibraryPopulating: false)
        #expect(deleting.dialog == .confirmDelete(playlistID: 4, name: "Focus"))
        deleting.missingChanged(to: [])
        #expect(deleting.dialog == .confirmDelete(playlistID: 4, name: "Focus"))
    }

    @Test("PL-DLG-21: a failure drops an open delete confirmation; its Delete then deletes nothing")
    func failureDropsTheDeleteConfirmation() {
        var latch = PlaylistDialogLatch()
        latch.askToDelete(playlistID: 4, name: "Focus")
        latch.fail("Couldn’t save the new order")
        #expect(latch.confirmDelete() == nil)
        latch.dismissFailure()
        #expect(latch.dialog == nil)
    }

    @Test("PL-DLG-22 (break-it 13): a double-press across the swap — OK, then Remove's place — removes nothing")
    func doublePressAcrossTheSwap() {
        // The Remove Missing confirmation is up when a late reorder-save failure takes the sheet; OK
        // sits where Remove sat, and a double-click lands on both.
        var latch = Self.confirming([1, 2])
        latch.fail("Couldn’t save the new order of “Focus”")
        latch.dismissFailure() // the first click: OK
        #expect(latch.dialog == nil) // the confirmation is not brought back under the pointer
        #expect(latch.confirmRemoveMissing(isLibraryPopulating: false) == nil) // the second click
        latch.cancel()
        #expect(latch.dialog == nil)

        // The same with the delete confirmation under the notice.
        var deleting = PlaylistDialogLatch()
        deleting.askToDelete(playlistID: 4, name: "Focus")
        deleting.fail("Couldn’t save the new order of “Focus”")
        deleting.dismissFailure()
        #expect(deleting.confirmDelete() == nil)
        #expect(deleting.dialog == nil)
    }
}
