@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit

// MARK: - The real view model on the engine model (council D41)

/// A track that never exists on disk: the engine model plays names, not files.
func track(_ index: Int) -> URL {
    URL(fileURLWithPath: "/nonexistent/ondeck/t\(index).flac")
}

func audioFile(_ index: Int) -> AudioFile {
    AudioFile(name: "t\(index)", relativePath: "", absoluteURL: track(index), format: "FLAC",
              durationSeconds: 200, trackID: Int64(index + 1))
}

/// `t3`, or `none`.
func name(_ url: URL?) -> String {
    url?.trackName ?? "none"
}

struct RigTimeout: Error, CustomStringConvertible {
    let what: String

    var description: String {
        "timed out waiting for \(what)"
    }
}

/// A scenario's verdict: whether the user hears what the app shows, and what happened.
struct Outcome: CustomStringConvertible {
    let ok: Bool
    let detail: String

    var description: String {
        detail
    }
}

/// The shipped `AudioViewModel`, driven against `OnDeckEngineModel`.
@MainActor
struct Rig {
    let vm: AudioViewModel
    let engine: OnDeckEngineModel

    init(tracks: Int, semantics: ArmSemantics = .design, commands: CommandSemantics = .dropsOvertaken,
         incompatible: Set<URL> = [], unreadable: Set<URL> = []) {
        engine = OnDeckEngineModel(semantics: semantics, commands: commands, incompatible: incompatible,
                                   unreadable: unreadable)
        vm = AudioViewModel(defaults: UserDefaults(suiteName: "AdaptiveSoundTests.OnDeck") ?? .standard,
                            engine: engine)
        // The view model restores the listener's settings from its defaults, which every rig shares
        // and rigs in parallel tests write: each rig starts from the modes its scenario assumes.
        vm.shuffleEnabled = false
        vm.repeatMode = 0
        vm.pureModeEnabled = false
        vm.isEngineReady = true
        vm.queue = (0 ..< tracks).map { QueueItem(file: audioFile($0)) }
    }

    /// Track `index` playing, its on-deck armed, everything settled.
    static func playing(tracks: Int = 6, at index: Int = 0, pure: Bool, semantics: ArmSemantics = .design,
                        commands: CommandSemantics = .dropsOvertaken, shuffle: Bool = false, repeatMode: Int = 0,
                        incompatible: Set<URL> = [], unreadable: Set<URL> = []) async throws -> Rig {
        let rig = Rig(tracks: tracks, semantics: semantics, commands: commands, incompatible: incompatible,
                      unreadable: unreadable)
        rig.vm.shuffleEnabled = shuffle
        rig.vm.repeatMode = repeatMode
        rig.vm.pureModeEnabled = pure
        rig.vm.playTrack(at: index)
        try await rig.settle()
        rig.engine.drain()
        try await rig.waitUntil("the first start to play") { rig.vm.isPlaying }
        rig.tick()
        return rig
    }

    /// The song the app shows as playing.
    var shown: URL? {
        vm.selectedTrackIndex.flatMap { $0 < vm.queue.count ? vm.queue[$0].file.absoluteURL : nil }
    }

    /// The song the app promises next.
    var pending: URL? {
        vm.pendingNextIndex.flatMap { $0 < vm.queue.count ? vm.queue[$0].file.absoluteURL : nil }
    }

    /// Wait until every request and transport op the view model made reached the engine, and its
    /// newest start — unless it waits held — has gone on to prime its on-deck (sending that request
    /// too), or taken its failure in.
    func settle() async throws {
        try await waitUntil("the view model's requests to reach the engine") {
            engine.hasReceivedEverything(sequence: vm.onDeckSequence, epoch: vm.transportEpoch) && !startToPrime
        }
    }

    /// The newest start ran, and the view model has not begun its prime yet (or not taken its failure in).
    private var startToPrime: Bool {
        guard case let .start(epoch) = vm.transportCommand else { return false }
        return !engine.heldEpochs.contains(epoch)
    }

    func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        var spins = 0
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RigTimeout(what: what) }
            spins += 1
            if spins < 200 {
                await Task.yield()
            } else {
                try await Task.sleep(for: .microseconds(50))
            }
        }
    }

    /// The clock samples, and the view model's 20 Hz tick reads the sample.
    func tick() {
        engine.clockTick()
        vm.tickTransport()
    }

    /// What a tick made of a seam the engine reported (the explorers' accounting, council D41).
    enum SeamVerdict {
        /// The tick took no seam.
        case none
        /// The app shows what plays.
        case shown
        /// The documented residual A2 / A2′ (KI-PB-16): a request the engine had not applied when the
        /// seam fired — made before it and still in flight, or made after it, before this tick — moved
        /// the app's pick. The seam carries no identity until the Engine sprint's seam identity (F1).
        case residual
        /// The seam went into a pick other than the newest request the engine had applied.
        case intoStalePick
        /// The app shows another song, and no request explains it.
        case wrongSong
    }

    /// One tick, and what it made of a seam: when it takes one, the app must show what plays — or
    /// the seam is the residual A2 / A2′.
    func tickJudgingSeam() -> SeamVerdict {
        let sequenceAtTick = vm.onDeckSequence
        let countBefore = vm.lastTransitionCount
        let hadSeam = engine.hasUnprocessedSeam
        tick()
        guard hadSeam, vm.lastTransitionCount != countBefore, let seam = engine.takeProcessedSeam() else {
            return .none
        }
        if !seam.intoNewestApplied {
            return .intoStalePick
        }
        if engine.current == shown {
            return .shown
        }
        return sequenceAtTick > seam.newestApplied ? .residual : .wrongSong
    }

    /// A few ticks, each followed by everything it sent landing: a seam's re-arm, an end's fresh start.
    /// The tick acts only once no start or stop is on its way (council C-15), so each waits for the
    /// view model to finish one first. Ends settled: no request is left with its caller waiting.
    func follow() async throws {
        for _ in 0 ..< 4 {
            try await waitUntil("the view model's start or stop to finish") { viewModelSettled }
            tick()
            try await settle()
            engine.drain()
        }
    }

    /// The current track runs out, and the app follows.
    func endTrackAndFollow() async throws {
        engine.trackEnds()
        try await follow()
    }

    // MARK: Transport commands (council C-15)

    /// Let the view model's tasks run as far as they can before the engine does anything.
    func yieldToViewModel(_ yields: Int = 40) async {
        for _ in 0 ..< yields {
            await Task.yield()
        }
    }

    /// Wait until the view model's next call (a command or an on-deck request) has reached the engine
    /// since `calls` were counted.
    func waitForEngineCall(after calls: Int) async throws {
        try await waitUntil("the view model's call to reach the engine") { engine.callCount > calls }
    }

    /// Wait until every transport command the view model numbered has reached the engine.
    func waitForCommands() async throws {
        try await waitUntil("the view model's commands to reach the engine") {
            engine.receivedCount == Int(vm.transportEpoch)
        }
    }

    /// The view model has no start or stop of its own still running.
    var viewModelSettled: Bool {
        vm.transportCommand == nil
    }

    /// The end state: everything the view model sent lands — held commands in the order they reached
    /// the engine (`engineQueue` is FIFO), every request and open — and the view model's tasks finish,
    /// again and again until nothing moves.
    func quiesce() async throws {
        var last: [String] = []
        var stableRounds = 0
        for round in 0 ..< 4000 {
            engine.runAllHeld()
            engine.drain()
            await yieldToViewModel(4)
            let now = fingerprint
            let landed = engine.isIdle && viewModelSettled
                && engine.hasReceivedEverything(sequence: vm.onDeckSequence, epoch: vm.transportEpoch)
            stableRounds = landed && now == last ? stableRounds + 1 : 0
            if stableRounds >= 2 {
                return
            }
            last = now
            if !landed, round >= 50 { // a call is still on its hop to the engine, or back: a slow one
                try await Task.sleep(for: .microseconds(50))
            }
        }
        throw RigTimeout(what: "the end state (everything landed, the view model settled)")
    }

    /// What a view-model task that has not finished could still change.
    private var fingerprint: [String] {
        ["\(vm.isPlaying)", "\(vm.selectedTrackIndex ?? -1)", "\(vm.pendingNextIndex ?? -1)", "\(vm.transportEpoch)",
         "\(vm.onDeckSequence)", "\(vm.pausedResumePosition ?? -1)", "\(vm.errorMessage ?? "")",
         "\(engine.callCount)"]
    }

    /// Whether the user hears what the app shows: playing ⇔ the engine plays, the same song, and the
    /// app's next is the engine's armed pick (`nil`: they agree).
    var disagreement: String? {
        let enginePlays = engine.current != nil && !engine.ended
        if vm.isPlaying, !enginePlays {
            return "app shows playing, engine silent"
        }
        if enginePlays, !vm.isPlaying {
            return "engine plays, app shows stopped/paused"
        }
        if enginePlays, engine.current != shown {
            return "wrong song shown"
        }
        if enginePlays, vm.pendingNextIndex != nil, pending != engine.armed {
            return "app's next ≠ engine's armed"
        }
        return nil
    }

    /// HEARS / SHOWS, for a scenario's detail.
    var state: String {
        "HEARS \(engine.ended ? "end" : name(engine.current)) / SHOWS \(name(shown)), app playing \(vm.isPlaying), "
            + "resume \(vm.pausedResumePosition.map { secs($0) } ?? "none"), armed \(name(engine.armed)) / promised "
            + "\(name(pending)); heard \(engine.heard), dropped as overtaken \(engine.droppedEpochs.map { "e\($0)" })"
    }
}
