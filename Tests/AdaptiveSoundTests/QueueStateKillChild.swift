@testable import AdaptiveSound
import Foundation
import LibraryStore
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - The kill harness's child, and what it shares with the parent (R1.1-B; council C-65) (VM-KILL)

//
// `QueueStateKillTests` spawns this bundle again with only `QueueStateKillChild` selected: the real view model
// over the harness's store, restoring, then changing the queue at random and logging each state it reaches,
// until the parent kills it. Outside a run the parent spawned, the suite is disabled.

/// The environment that makes a run of this bundle the harness's child, and what it tells the child. Every
/// change the child makes changes the record synchronously, so each state the writer can write is one the
/// log names before the writer next runs (the writer runs only when the child awaits).
enum KillHarness {
    static let storeKey = "AS_QUEUE_KILL_STORE"
    static let logKey = "AS_QUEUE_KILL_LOG"
    static let seedKey = "AS_QUEUE_KILL_SEED"
    static let defaultsKey = "AS_QUEUE_KILL_DEFAULTS"
    static let opsKey = "AS_QUEUE_KILL_OPS"
    static let songs = 1000

    static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    /// FNV-1a 64 of a record's text: the log names a state by it.
    static func hash(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}

/// One state the child reached, as the log names it: the record's hash and the playhead.
struct LoggedState: Hashable, CustomStringConvertible {
    let hash: String
    let offset: Double

    var description: String {
        "\(hash) @\(offset)"
    }

    /// The state stored in `state`.
    init(_ state: StoredQueueState) {
        hash = KillHarness.hash(state.record)
        offset = state.offset ?? -1
    }

    init(hash: String, offset: Double) {
        self.hash = hash
        self.offset = offset
    }
}

/// A child's log, read back: the state it restored, the states it reached in order, and where flushes were.
struct ChildLog {
    var restored: LoggedState?
    var states: [LoggedState] = []
    /// For each "flushed" line, the number of states logged before it.
    var flushedAt: [Int] = []

    init(_ text: String) {
        for line in text.split(separator: "\n") {
            let words = line.split(separator: " ")
            switch words.first {
            case "restored", "state":
                guard words.count == 3, let offset = Double(words[2]) else { continue }
                let state = LoggedState(hash: String(words[1]), offset: offset)
                if words[0] == "restored" {
                    restored = state
                } else {
                    states.append(state)
                }
            case "flushed": flushedAt.append(states.count)
            default: continue
            }
        }
    }
}

// MARK: - The child

/// The harness's child: enabled only in a process the parent spawned (`AS_QUEUE_KILL_STORE` set).
@MainActor
@Suite("The queue kill harness's child (runs only when VM-KILL-01 spawns it)",
       .enabled(if: ProcessInfo.processInfo.environment[KillHarness.storeKey] != nil))
struct QueueStateKillChild {
    /// Launch the real view model over the store, restore, log the restored state, then change the queue at
    /// random — logging each state reached — until killed (or `AS_QUEUE_KILL_OPS` changes made).
    @Test("the child: restore, then change the queue at random until killed")
    func queueStateKillChild() async throws {
        let environment = KillHarness.environment
        guard let storePath = environment[KillHarness.storeKey], let logPath = environment[KillHarness.logKey],
              let suite = environment[KillHarness.defaultsKey], let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("the child was started without its store, log or defaults")
            return
        }
        let storeURL = URL(fileURLWithPath: storePath)
        let log = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        var rng = KillRandom(seed: UInt64(environment[KillHarness.seedKey] ?? "") ?? 1)
        let ops = Int(environment[KillHarness.opsKey] ?? "") ?? Int.max

        let child = try await KillChild(storeURL: storeURL, defaults: defaults)
        try log.write(contentsOf: Data("restored \(child.loggedState())\n".utf8))
        var done = 0
        while done < ops, getppid() != 1 {
            child.change(&rng)
            done += 1
            try log.write(contentsOf: Data("state \(child.loggedState())\n".utf8))
            if rng.below(5) == 0 {
                await child.vm.queueStateWriter.flush()
                try log.write(contentsOf: Data("flushed\n".utf8))
            } else {
                try await child.vm.settled()
            }
        }
        await child.vm.queueStateWriter.flush()
    }
}

/// The child's world: the real view model over `FakeEngine` and the store, launched as the app launches.
@MainActor
private final class KillChild {
    let vm: AudioViewModel
    let engine = FakeEngine()
    let bench = TickerBench()
    let library = LibraryModel(storeless: ())
    let directory: URL
    private var seams: UInt64 = 0
    private var looseFiles = 0

    init(storeURL: URL, defaults: UserDefaults) async throws {
        QuietLog.install()
        directory = storeURL.deletingLastPathComponent()
        vm = AudioViewModel(defaults: defaults, engine: engine, makeTicker: bench.maker)
        vm.initializeEngine()
        try await vm.settled()
        let store = try await LibraryStore(url: storeURL, appBuild: "kill-child")
        // Shuffle is a listening setting, kept apart from the record: on when the stored queue has a pass.
        let stored = try await store.queueState()
        vm.shuffleEnabled = stored.flatMap { try? QueueResumeRecord(storedQueue: $0.record, offset: 0) }?.shuffle != nil
        library.store = store
        vm.library = library
        vm.hydrateQueueOnLaunch()
        try await vm.settled()
        await vm.queueStateWriter.flush()
    }

    /// The state the writer would write now, as the log names it.
    func loggedState() -> String {
        let (record, offset) = vm.queueStateNow()
        let text = (try? record?.encodedQueue()) ?? "none"
        return "\(KillHarness.hash(text)) \(offset)"
    }

    /// One random change, as a listener or the engine makes it: an edit of the queue, a change of the
    /// order, or the transport moving.
    func change(_ rng: inout KillRandom) {
        switch rng.below(10) {
        case 0 ..< 4: editQueue(&rng)
        case 4 ..< 6: changeOrder(&rng)
        default: moveTransport(&rng)
        }
    }

    private func editQueue(_ rng: inout KillRandom) {
        let count = vm.queue.count
        switch rng.below(10) {
        case 0:
            let songs = (0 ... rng.below(KillHarness.songs)).map { _ in audioFile(rng.below(KillHarness.songs)) }
            vm.playNow(songs, startAt: rng.below(songs.count))
        case 1 ..< 4: vm.appendToQueue([file(&rng)])
        case 4 ..< 6: _ = vm.playNext([file(&rng)])
        case 6 ..< 8 where count > 0:
            // Not the song playing: its stop zeroes the playhead in a task of its own, after this change is
            // logged, and every state the writer may write must be one the log names.
            let row = rng.below(count)
            if row != vm.selectedTrackIndex || !vm.playIntent {
                vm.removeTrack(at: row)
            }
        case 8 where count > 1: vm.moveTrackDown(rng.below(count - 1))
        default: vm.playNow([audioFile(rng.below(KillHarness.songs))], startAt: 0)
        }
    }

    private func changeOrder(_ rng: inout KillRandom) {
        switch rng.below(10) {
        case 0 ..< 3: vm.toggleShuffle()
        case 3 ..< 5: vm.cycleRepeatMode()
        case 5 ..< 8: vm.nextTrack()
        default: vm.previousTrack()
        }
    }

    private func moveTransport(_ rng: inout KillRandom) {
        let count = vm.queue.count
        switch rng.below(10) {
        case 0 ..< 3 where vm.isPlaying && vm.pendingNextIndex != nil:
            seams += 1 // the engine seams into the song armed
            report(position: 0)
        case 3 ..< 7: report(position: Double(rng.below(6000)) / 10)
        case 7: vm.togglePlayPause()
        case 8: vm.seek(to: Double(rng.below(3000)) / 10)
        case 9 where count > 0: vm.playTrack(at: rng.below(count))
        default: vm.togglePlayPause()
        }
    }

    /// A library song, or now and then a loose file (seam S5: kept by its path, no `tracks` row).
    private func file(_ rng: inout KillRandom) -> AudioFile {
        guard rng.below(4) == 0 else { return audioFile(rng.below(KillHarness.songs)) }
        looseFiles += 1
        let url = directory.appendingPathComponent("loose \(looseFiles) — \(rng.below(1000)).flac")
        return AudioFile(name: url.deletingPathExtension().lastPathComponent, relativePath: "", absoluteURL: url,
                         format: "FLAC", durationSeconds: 0)
    }

    /// The engine's clock at `position` (with the seams so far), read by one tick — when a tick is going.
    private func report(position: Double) {
        let sample = TransportSnapshot(epoch: vm.transportEpoch, position: position, transitionCount: seams,
                                       ended: false)
        engine.state.withLock { $0.transport = sample }
        bench.current?.fire()
    }
}

/// SplitMix64, so a run replays from its printed seed.
struct KillRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// A number in `0 ..< bound` (bound > 0).
    mutating func below(_ bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}
