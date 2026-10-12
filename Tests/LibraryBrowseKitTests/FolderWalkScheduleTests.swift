import LibraryScan
import Testing

// MARK: - FolderWalkSchedule (S10.8 G — G-LIB-01 / 05 / 06)

/// The rules LibraryModel walks the music folders by: one walk per folder at a time, one add at a
/// time, a launch catch-up satisfied by any walk already under way, and a reconcile owed to a
/// cancelled walk. Driven as pure values — the app starts what each call returns.
@Suite("FolderWalkSchedule — which folder walks may start")
struct FolderWalkScheduleTests {
    /// A started walk as `(folder, kind)`, for comparing what a call returned.
    private struct Walk: Equatable, CustomStringConvertible {
        let folder: Int64
        let add: Bool
        var description: String {
            "\(add ? "add" : "reconcile") \(folder)"
        }
    }

    private static func walks(_ starts: [FolderWalkSchedule.Start]) -> [Walk] {
        starts.map { Walk(folder: $0.folderID, add: $0.walk == .add) }
    }

    private static func add(_ folder: Int64) -> Walk {
        Walk(folder: folder, add: true)
    }

    private static func reconcile(_ folder: Int64) -> Walk {
        Walk(folder: folder, add: false)
    }

    // MARK: One walk per folder (G-LIB-01)

    @Test("a reconcile of a folder that is adding waits, and runs once after the add")
    func reconcileWaitsForTheFoldersAdd() {
        var schedule = FolderWalkSchedule()
        #expect(Self.walks(schedule.request(.add, of: 1)) == [Self.add(1)])
        #expect(Self.walks(schedule.request(.reconcile, of: 1)).isEmpty)
        #expect(Self.walks(schedule.request(.reconcile, of: 1)).isEmpty, "a second request coalesces")
        #expect(Self.walks(schedule.finish(1, cancelled: false)) == [Self.reconcile(1)])
        #expect(Self.walks(schedule.finish(1, cancelled: false)).isEmpty, "only one re-run")
    }

    @Test("an add of a folder that is reconciling waits, and the waiting walk becomes the add")
    func addWaitsForTheFoldersReconcile() {
        var schedule = FolderWalkSchedule()
        #expect(Self.walks(schedule.request(.reconcile, of: 1)) == [Self.reconcile(1)])
        #expect(Self.walks(schedule.request(.reconcile, of: 1)).isEmpty)
        #expect(Self.walks(schedule.request(.add, of: 1)).isEmpty)
        #expect(Self.walks(schedule.finish(1, cancelled: false)) == [Self.add(1)])
    }

    // MARK: One add at a time, never a cancel (G-LIB-06)

    @Test("a second folder's add waits for the first add's walk instead of cancelling it")
    func secondAddWaitsForTheFirst() {
        var schedule = FolderWalkSchedule()
        #expect(Self.walks(schedule.request(.add, of: 1)) == [Self.add(1)])
        #expect(Self.walks(schedule.request(.add, of: 2)).isEmpty)
        #expect(Self.walks(schedule.request(.add, of: 3)).isEmpty)
        #expect(Self.walks(schedule.finish(1, cancelled: false)) == [Self.add(2)], "adds start in request order")
        #expect(Self.walks(schedule.finish(2, cancelled: false)) == [Self.add(3)])
    }

    @Test("a reconcile of another folder runs beside an add; walks of different folders overlap")
    func reconcileOfAnotherFolderNeverWaitsForAnAdd() {
        var schedule = FolderWalkSchedule()
        #expect(Self.walks(schedule.request(.add, of: 1)) == [Self.add(1)])
        #expect(Self.walks(schedule.request(.reconcile, of: 2)) == [Self.reconcile(2)])
        #expect(Self.walks(schedule.request(.reconcile, of: 3)) == [Self.reconcile(3)])
        #expect(schedule.isReconciling)
        _ = schedule.finish(2, cancelled: false)
        _ = schedule.finish(3, cancelled: false)
        #expect(!schedule.isReconciling, "an add alone is not reconciling")
    }

    @Test("an add queued behind another add still waits for its own folder's reconcile")
    func queuedAddWaitsForBothRules() {
        var schedule = FolderWalkSchedule()
        _ = schedule.request(.add, of: 1)
        _ = schedule.request(.reconcile, of: 2)
        #expect(Self.walks(schedule.request(.add, of: 2)).isEmpty)
        #expect(Self.walks(schedule.finish(1, cancelled: false)).isEmpty, "folder 2 is still reconciling")
        #expect(Self.walks(schedule.finish(2, cancelled: false)) == [Self.add(2)])
    }

    // MARK: Launch catch-up (G-LIB-05)

    @Test("a launch catch-up reconciles an idle folder, and is satisfied by a walk under way or waiting")
    func catchUpSkipsAFolderAlreadyWalking() {
        var schedule = FolderWalkSchedule()
        #expect(Self.walks(schedule.request(.add, of: 1)) == [Self.add(1)])
        #expect(Self.walks(schedule.request(.add, of: 2)).isEmpty) // waiting behind add 1
        #expect(Self.walks(schedule.requestCatchUp(of: 1)).isEmpty, "the test library's own add covers it")
        #expect(Self.walks(schedule.requestCatchUp(of: 2)).isEmpty, "a waiting add covers it")
        #expect(Self.walks(schedule.requestCatchUp(of: 3)) == [Self.reconcile(3)])
        #expect(Self.walks(schedule.finish(1, cancelled: false)) == [Self.add(2)], "no extra walk of folder 1")
    }

    // MARK: A cancelled walk is owed a reconcile (G-LIB-06)

    @Test("a cancelled walk is owed a reconcile")
    func cancelledWalkIsReconciled() {
        var schedule = FolderWalkSchedule()
        _ = schedule.request(.add, of: 1)
        _ = schedule.request(.add, of: 2)
        #expect(Self.walks(schedule.finish(1, cancelled: true)) == [Self.add(2), Self.reconcile(1)])
    }

    @Test("a cancelled walk with a walk waiting for its folder is owed nothing more")
    func cancelledWalkCoalescesWithAWaitingOne() {
        var schedule = FolderWalkSchedule()
        _ = schedule.request(.reconcile, of: 1)
        _ = schedule.request(.add, of: 1)
        #expect(Self.walks(schedule.finish(1, cancelled: true)) == [Self.add(1)])
    }

    // MARK: Removing a folder, shutting down

    @Test("a folder being removed starts nothing, and its cancelled walk is owed nothing")
    func removingAFolderStopsItsWalks() {
        var schedule = FolderWalkSchedule()
        _ = schedule.request(.reconcile, of: 1)
        _ = schedule.request(.add, of: 1)
        schedule.beginRemoving(1)
        #expect(Self.walks(schedule.request(.reconcile, of: 1)).isEmpty)
        #expect(Self.walks(schedule.finish(1, cancelled: true)).isEmpty, "the waiting add was dropped too")
        schedule.endRemoving(1)
        #expect(Self.walks(schedule.request(.add, of: 1)) == [Self.add(1)], "a folder added later may reuse the id")
    }

    @Test("removing one folder lets the add waiting behind its add start")
    func removingAnAddingFolderFreesTheAddLane() {
        var schedule = FolderWalkSchedule()
        _ = schedule.request(.add, of: 1)
        _ = schedule.request(.add, of: 2)
        schedule.beginRemoving(1)
        #expect(Self.walks(schedule.finish(1, cancelled: true)) == [Self.add(2)])
    }

    @Test("after stop nothing starts, and a cancelled walk is owed nothing")
    func stopStartsNothing() {
        var schedule = FolderWalkSchedule()
        _ = schedule.request(.add, of: 1)
        _ = schedule.request(.reconcile, of: 2)
        _ = schedule.request(.add, of: 3)
        schedule.stop()
        #expect(Self.walks(schedule.finish(1, cancelled: true)).isEmpty)
        #expect(Self.walks(schedule.request(.reconcile, of: 4)).isEmpty)
        #expect(Self.walks(schedule.requestCatchUp(of: 5)).isEmpty)
    }
}
