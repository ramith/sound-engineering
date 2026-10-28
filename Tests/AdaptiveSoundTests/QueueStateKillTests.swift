@testable import AdaptiveSound
import Foundation
import LibraryStore
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - kill -9 at random points while the app writes its queue (R1.1-B; council C-65, KI-PB-21) (VM-KILL)

//
// The process-level proof of the atomic queue restore. The parent test spawns a CHILD process — this same
// test bundle, re-run with only `QueueStateKillChild` selected — that launches the real `AudioViewModel` over
// a real `LibraryStore` file, restores the queue the last child left, then changes it at random (play verbs,
// edits, shuffle, repeat, seams, Next, Previous, playhead moves, pauses, seeks), its one writer writing all the
// while. Before each wait it logs the state it reached: the hash of the record the writer would write and the
// playhead beside it (`queueStateNow`, the sink's own function), and "flushed" once a checkpoint returned: the
// queue as it is asked for and written, as the quit does (`KillHarness.checkpoint`; a flush alone leaves a
// playhead moved under the 5 s cadence unwritten — VM-KILL-02). At a random point — 0 to 80 changes in — the
// parent sends SIGKILL, then opens the store through the real open path and checks that what is stored is WHOLE
// (integrity, the playhead of the record's own revision, a record that decodes and holds together), is a state
// the child reached — never a mix — and is no older than the last checkpoint (nothing written was lost). The
// next child must restore exactly that: the same queue, song, place, permutation, position and history, loose
// files included.
//
// `AS_QUEUE_KILLS` kills per run (default 100, ~10 s); `make stress TEST=QueueStateKillTests N=…` repeats the
// run under load. Before the store is opened after a kill, its WAL is read: a kill that cut a write
// transaction short leaves frames no commit frame closes, which SQLite's recovery then ignores — the run's
// last line counts them, so the kills are seen landing inside writes, not only between them.
// `AS_QUEUE_KILL_SEED` replays a run (each run prints its seed).

// MARK: - The parent

@MainActor
@Suite("The queue's state survives kill -9 at any instant (VM-KILL)", .serialized, .timeLimit(.minutes(10)),
       .attachingLogTail)
struct QueueStateKillTests {
    /// The parent's world: a folder with the store and the children's logs, a defaults suite the children share
    /// (removed with the world, so a killed child leaves no settings behind), and how to re-run this bundle.
    @MainActor
    private final class World {
        let directory: URL
        let storeURL: URL
        let defaults = IsolatedDefaults("QueueKill")
        let helper: URL
        let testBundle: String

        init() async throws {
            let arguments = CommandLine.arguments
            guard let flag = arguments.firstIndex(of: "--test-bundle-path"), flag + 1 < arguments.count else {
                throw HarnessError(what: "this run has no --test-bundle-path to re-run (arguments: \(arguments))")
            }
            helper = URL(fileURLWithPath: arguments[0])
            testBundle = arguments[flag + 1]
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("queue-kill-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            storeURL = directory.appendingPathComponent("library.sqlite3")
            let store = try await LibraryStore(url: storeURL, appBuild: "kill-harness")
            let files = (0 ..< KillHarness.songs).map {
                ScannedFile(url: track($0), name: "t\($0)", format: "FLAC", fileSize: 1, mtime: 1)
            }
            _ = try await store.upsert(files, folderID: nil, generation: store.beginScanGeneration())
        }

        /// Start child `number`: `ops` changes at most (nil: until it is killed), drawn from `seed`.
        func spawn(_ number: Int, seed: UInt64, ops: Int?) throws -> Child {
            let child = Child(process: Process(), log: directory.appendingPathComponent("child-\(number).log"),
                              output: directory.appendingPathComponent("child-\(number).out"))
            FileManager.default.createFile(atPath: child.log.path, contents: nil)
            FileManager.default.createFile(atPath: child.output.path, contents: nil)
            child.process.executableURL = helper
            child.process.arguments = ["--test-bundle-path", testBundle, testBundle, "--testing-library",
                                       "swift-testing", "--filter", "QueueStateKillChild"]
            var environment = KillHarness.environment
            environment[KillHarness.storeKey] = storeURL.path
            environment[KillHarness.logKey] = child.log.path
            environment[KillHarness.seedKey] = String(seed)
            environment[KillHarness.defaultsKey] = defaults.suiteName
            environment[KillHarness.opsKey] = ops.map(String.init)
            child.process.environment = environment
            let sink = try FileHandle(forWritingTo: child.output)
            child.process.standardOutput = sink
            child.process.standardError = sink
            try child.process.run()
            return child
        }

        /// The store's write-ahead log.
        var walPath: String {
            storeURL.path + "-wal"
        }

        /// What the store holds now, read through the real open path, after a check that the file is whole.
        func stored() async throws -> StoredQueueState? {
            let store = try await LibraryStore(url: storeURL, appBuild: "kill-harness")
            #expect(try await store.integrityCheck(), "the store is damaged after a kill")
            #expect(store.quarantinedFrom == nil, "the store was quarantined after a kill")
            return try await store.queueState()
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// A spawned child: its process, the log it writes, and its own output (for a failure's message).
    private struct Child {
        let process: Process
        let log: URL
        let output: URL

        var isRunning: Bool {
            process.isRunning
        }

        /// Its log, read now.
        var logged: ChildLog {
            ChildLog((try? String(contentsOf: log, encoding: .utf8)) ?? "")
        }

        /// The end of what it printed.
        var tail: String {
            String(((try? String(contentsOf: output, encoding: .utf8)) ?? "").suffix(3000))
        }

        func killIfRunning() {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private struct HarnessError: Error, CustomStringConvertible {
        let what: String
        var description: String {
            what
        }
    }

    private func fileSize(_ path: String) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? -1
    }

    @Test("VM-KILL-01: SIGKILL at random points as the one writer writes — the previous state or the next, never a mix")
    func killsLeaveWholeStates() async throws {
        let kills = Int(KillHarness.environment["AS_QUEUE_KILLS"] ?? "") ?? 100
        let seed = UInt64(KillHarness.environment[KillHarness.seedKey] ?? "") ?? .random(in: 1 ... .max)
        print("VM-KILL-01: \(kills) kills, seed \(seed) (AS_QUEUE_KILL_SEED=\(seed) replays it)")
        var rng = KillRandom(seed: seed)
        let world = try await World()
        var expected: LoggedState? // what the next child must restore
        var tally = KillTally()
        for number in 0 ..< kills {
            let child = try world.spawn(number, seed: rng.next(), ops: nil)
            defer { child.killIfRunning() }
            let restored = try await restore(child, number, expecting: expected)
            try await killAtRandomPoint(child, number, rng: &rng, world: world)
            tally.torn += uncommittedFrames(inWAL: URL(fileURLWithPath: world.walPath)) > 0 ? 1 : 0
            expected = try await checkStore(after: number, child.logged, restored: restored, world: world,
                                            tally: &tally)
        }
        // A last child restores what the last kill left, and ends by itself.
        let last = try world.spawn(kills, seed: rng.next(), ops: 0)
        defer { last.killIfRunning() }
        _ = try await restore(last, kills, expecting: expected)
        try await until("the last child to end by itself") { !last.isRunning }
        #expect(last.process.terminationStatus == 0, "the last child failed: \(last.tail)")
        print("VM-KILL-01: \(kills) kills, every stored state whole and one the child reached; \(tally)")
    }

    @Test("VM-KILL-02: a checkpoint leaves stored the state the child logged — a playhead under the cadence too")
    func checkpointStoresTheLoggedState() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let player = try await world.launch()
        player.vm.playNow((0 ..< 3).map(audioFile), startAt: 0)
        try await playing(player)
        // The second move of each pair is under the cadence from the first, so it asks for no write: forward from
        // a start, and back after a seek — the shapes VM-KILL-01 once failed on (stored @0.0 with @4.7 logged at
        // the checkpoint; stored @61.5 with @58.8).
        for (asked, moved) in [(0.0, 4.7), (61.5, 58.8)] {
            try movePlayhead(player, to: asked)
            await KillHarness.checkpoint(player.vm)
            try movePlayhead(player, to: moved)
            await KillHarness.checkpoint(player.vm)
            let stored = try LoggedState(#require(try await world.store.queueState()))
            let logged = KillHarness.state(of: player.vm)
            #expect(stored == logged, "at \(moved) s (from \(asked) s): stored \(stored), logged \(logged)")
        }
    }

    /// Wait for `child` to restore the queue, and check it restored `expected` — what the last kill left.
    private func restore(_ child: Child, _ number: Int, expecting expected: LoggedState?) async throws -> LoggedState {
        try await until("child \(number) to restore the queue") { child.logged.restored != nil || !child.isRunning }
        let restored = try #require(child.logged.restored, "child \(number) ended before restoring: \(child.tail)")
        if let expected {
            #expect(restored == expected, "child \(number) restored another state than the kill left")
        }
        return restored
    }

    /// Let `child` make 0 to 80 changes — and every other time, wait on until a write is under way (its WAL
    /// changing) — then SIGKILL it.
    private func killAtRandomPoint(_ child: Child, _ number: Int, rng: inout KillRandom, world: World) async throws {
        let changes = rng.below(81)
        try await until("child \(number) to make \(changes) changes") {
            child.logged.states.count >= changes || !child.isRunning
        }
        if rng.below(2) == 0 {
            let before = fileSize(world.walPath)
            try await until("child \(number)'s WAL to change — a write under way") {
                fileSize(world.walPath) != before || !child.isRunning
            }
        }
        #expect(child.isRunning, "child \(number) ended before its kill: \(child.tail)")
        child.killIfRunning()
        try await until("child \(number) to die") { !child.isRunning }
        #expect(child.process.terminationReason == .uncaughtSignal && child.process.terminationStatus == SIGKILL)
    }

    /// What kill `number` left: whole — the record's own playhead, a record that decodes and holds together —
    /// a state the child reached, and none older than its last checkpoint (nothing written was lost). Returns
    /// it: what the next child must restore.
    private func checkStore(after number: Int, _ log: ChildLog, restored: LoggedState, world: World,
                            tally: inout KillTally) async throws -> LoggedState {
        guard let stored = try await world.stored() else {
            // Nothing written yet: so no checkpoint returned — each one writes the queue as it is.
            #expect(log.flushedAt.isEmpty, "kill \(number): nothing stored after a checkpoint returned")
            return restored
        }
        let state = LoggedState(stored)
        #expect(stored.offset != nil, "kill \(number): a record with another record's playhead")
        let record = try? QueueResumeRecord(storedQueue: stored.record, offset: stored.offset ?? 0)
        #expect(record != nil, "kill \(number): the stored record does not decode or hold together")
        let lastFlush = log.flushedAt.last.map { max(0, $0 - 1) }
        let since = lastFlush.map { Array(log.states[$0...]) } ?? [restored] + log.states
        let lost = "kill \(number): stored \(state) is no state reached since the last checkpoint "
            + "(\(log.states.count) states, checkpoints at \(log.flushedAt))"
        #expect(since.contains(state), Comment(rawValue: lost))
        tally.count(log, stored: state, record: record)
        return state
    }
}

/// What the kills hit, for the run's last line: evidence that they landed at random points.
private struct KillTally: CustomStringConvertible {
    var changes = 0
    var flushes = 0
    /// Kills after which the store held a state older than the child's last: a write in flight or waiting.
    var behind = 0
    /// Kills that cut a write transaction short: its frames in the WAL with no commit frame after them.
    var torn = 0
    var withLooseFile = 0
    var withShufflePass = 0
    var songs = 0

    mutating func count(_ log: ChildLog, stored: LoggedState, record: QueueResumeRecord?) {
        changes += log.states.count
        flushes += log.flushedAt.count
        behind += stored == log.states.last ? 0 : 1
        withLooseFile += record?.slots.contains {
            if case .loose = $0 {
                true
            } else {
                false
            }
        } == true ? 1 : 0
        withShufflePass += record?.shuffle != nil ? 1 : 0
        songs = max(songs, record?.slots.count ?? 0)
    }

    var description: String {
        "\(changes) changes and \(flushes) checkpoints logged; \(torn) kills cut a write transaction short (its "
            + "frames in the WAL, uncommitted); \(behind) kills left a state behind the child's last "
            + "(a write in flight or waiting); stored queues held a loose file after \(withLooseFile) kills and a "
            + "shuffle pass after \(withShufflePass); the longest queue \(songs) songs"
    }
}

/// The frames at the end of a WAL file (sqlite.org/fileformat2.html §4.1) that no commit frame closes: a write
/// transaction a kill cut short. Frames of an older WAL generation (other salts) end the count.
private func uncommittedFrames(inWAL url: URL) -> Int {
    guard let wal = try? Data(contentsOf: url), wal.count >= 32 else { return 0 }
    func word(_ offset: Int) -> UInt32 {
        wal[offset ..< offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }
    let pageSize = word(8) == 1 ? 65536 : Int(word(8))
    let frameSize = 24 + pageSize
    var offset = 32
    var sinceCommit = 0
    let salts = (word(16), word(20))
    while pageSize >= 512, offset + frameSize <= wal.count, (word(offset + 8), word(offset + 12)) == salts {
        sinceCommit = word(offset + 4) != 0 ? 0 : sinceCommit + 1
        offset += frameSize
    }
    return sinceCommit
}
