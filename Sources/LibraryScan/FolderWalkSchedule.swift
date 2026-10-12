// FolderWalkSchedule — which walks of the library's music folders may start now (S10.8 G).
//
// A walk is one `LibraryScanner.scan` of one registered folder, and it ends with a sweep of what it
// didn't see. Two kinds:
//   • ADD — the walk that follows registering a folder (adding it, or re-adding it: the manual
//     rescan). It shows scan progress and hands its generation to the library-wide metadata pass.
//   • RECONCILE — a change in the folder, a volume mount, the launch catch-up, or the re-run a
//     cancelled walk is owed. It runs that folder's own metadata pass.
//
// The rules (Sprint G break-it, G-LIB-01 / 05 / 06):
//   • ONE walk per folder at a time. A request for a folder that is walking waits and runs once
//     after it; requests coalesce while they wait, and an add covers a reconcile. Two walks of one
//     folder at once is how songs on disk got swept (the store now also refuses to lower a stamp).
//   • ONE add at a time (scan progress is one line). A second folder's add waits for the first
//     add's walk; it never cancels it. A reconcile of another folder never waits for an add.
//   • A launch CATCH-UP is satisfied by any walk already running or waiting for that folder.
//   • A walk that was CANCELLED is owed a reconcile, unless its folder is being removed or the
//     library is shutting down.
// Waiting walks start in request order.
//
// Pure value logic, with no store, file or task: LibraryModel holds one, starts the walks each call
// returns, and reports every walk's end — so the rules are testable without the app.

import Foundation

/// The two kinds of walk over a registered music folder (see `FolderWalkSchedule`).
public enum FolderWalk: Sendable {
    /// A change in the folder, a volume mount, the launch catch-up, or a cancelled walk's re-run.
    case reconcile
    /// The walk that follows registering the folder; it covers a reconcile.
    case add
}

/// Decides which folder walks may start now: one per folder, one add at a time, in request order.
public struct FolderWalkSchedule: Sendable {
    /// A walk to start now.
    public struct Start: Sendable {
        public let folderID: Int64
        public let walk: FolderWalk
    }

    /// The walk in flight for each folder.
    private var running: [Int64: FolderWalk] = [:]
    /// Walks waiting for their turn, oldest first — at most one per folder.
    private var waiting: [Start] = []
    /// Folders being removed: they start nothing, and their cancelled walk is owed nothing.
    private var removing: Set<Int64> = []
    /// The library is shutting down: nothing more starts.
    private var stopped = false

    public init() {}

    /// Whether any folder is reconciling (the "Updating library…" status).
    public var isReconciling: Bool {
        running.values.contains { $0 == .reconcile }
    }

    /// Ask for a walk of `folderID`. Returns the walks to start now — this one, unless the folder
    /// is walking (it then runs once after), or it is an add and another add is walking.
    public mutating func request(_ walk: FolderWalk, of folderID: Int64) -> [Start] {
        guard !stopped, !removing.contains(folderID) else { return [] }
        if let index = waiting.firstIndex(where: { $0.folderID == folderID }) {
            if walk == .add {
                waiting[index] = Start(folderID: folderID, walk: .add) // an add covers a reconcile
            }
            return []
        }
        waiting.append(Start(folderID: folderID, walk: walk))
        return startable()
    }

    /// Ask for a launch catch-up of `folderID`: a reconcile, unless a walk of it is already running
    /// or waiting — any walk that starts after launch catches the folder up.
    public mutating func requestCatchUp(of folderID: Int64) -> [Start] {
        guard running[folderID] == nil, !waiting.contains(where: { $0.folderID == folderID }) else { return [] }
        return request(.reconcile, of: folderID)
    }

    /// The walk of `folderID` ended. A cancelled walk is owed a reconcile (unless its folder is being
    /// removed or the library is stopping). Returns the walks to start now.
    public mutating func finish(_ folderID: Int64, cancelled: Bool) -> [Start] {
        running[folderID] = nil
        if cancelled, !stopped, !removing.contains(folderID),
           !waiting.contains(where: { $0.folderID == folderID }) {
            waiting.append(Start(folderID: folderID, walk: .reconcile))
        }
        return startable()
    }

    /// `folderID` is being removed: drop its waiting walk and start nothing for it; its running walk
    /// (which the caller cancels) is owed no re-run. Ends with `endRemoving`.
    public mutating func beginRemoving(_ folderID: Int64) {
        removing.insert(folderID)
        waiting.removeAll { $0.folderID == folderID }
    }

    /// The removal of `folderID` is over (done or failed): its id may come back — a folder added
    /// later can reuse it.
    public mutating func endRemoving(_ folderID: Int64) {
        removing.remove(folderID)
    }

    /// The library is shutting down: drop every waiting walk and start nothing more.
    public mutating func stop() {
        stopped = true
        waiting.removeAll()
    }

    /// Move every waiting walk that may start now into `running`, oldest first.
    private mutating func startable() -> [Start] {
        guard !stopped else { return [] }
        var starts: [Start] = []
        var index = waiting.startIndex
        while index < waiting.endIndex {
            let next = waiting[index]
            if canStart(next) {
                waiting.remove(at: index)
                running[next.folderID] = next.walk
                starts.append(next)
            } else {
                index += 1
            }
        }
        return starts
    }

    /// A walk may start when its folder isn't walking and, for an add, no other add is.
    private func canStart(_ start: Start) -> Bool {
        guard running[start.folderID] == nil else { return false }
        return start.walk == .reconcile || !running.values.contains { $0 == .add }
    }
}
