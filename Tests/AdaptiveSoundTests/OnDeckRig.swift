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

    init(tracks: Int, semantics: ArmSemantics, incompatible: Set<URL> = [], unreadable: Set<URL> = []) {
        engine = OnDeckEngineModel(semantics: semantics, incompatible: incompatible, unreadable: unreadable)
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

    /// Track 0 playing, its on-deck armed, everything settled.
    static func playing(tracks: Int = 6, pure: Bool, semantics: ArmSemantics = .design, shuffle: Bool = false,
                        repeatMode: Int = 0, incompatible: Set<URL> = [],
                        unreadable: Set<URL> = []) async throws -> Rig {
        let rig = Rig(tracks: tracks, semantics: semantics, incompatible: incompatible, unreadable: unreadable)
        rig.vm.shuffleEnabled = shuffle
        rig.vm.repeatMode = repeatMode
        rig.vm.pureModeEnabled = pure
        rig.vm.playTrack(at: 0)
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

    /// Wait until every request and transport op the view model made reached the engine — and, when
    /// its newest start failed, until it has taken the failure in.
    func settle() async throws {
        try await waitUntil("the view model's requests to reach the engine") {
            engine.hasReceivedEverything(sequence: vm.onDeckSequence, epoch: vm.transportEpoch,
                                         session: vm.onDeckSession)
                && (!engine.startFailed(epoch: vm.onDeckSession) || vm.errorMessage != nil)
        }
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

    /// A few ticks, each followed by everything it sent landing: a seam's re-arm, an end's fresh start.
    /// Ends settled: no request is left with its caller waiting.
    func follow() async throws {
        for _ in 0 ..< 4 {
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
}
