@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - What plays next stays right after the queue is edited (council C-17, P4-4, P4-5)

//
// The shipped `AudioViewModel` against `OnDeckEngineModel`: a song plays, the user edits the queue,
// the song ends. What plays next must be what the queue now says — in order, the row after the
// playing one (VLC and foobar2000 compute it at the track's end) — and what the app shows.

/// A queue edit while t0 (or the last song) plays.
enum QueueEdit: String, CaseIterable, Sendable, CustomStringConvertible {
    /// Drag t3 in under the playing t0: `[t0, t3, t1, t2, …]`; t3 is next.
    case dragUnderPlaying = "drag a song in under the playing one"
    /// Drag the next song (t1) to the bottom: t2 is next.
    case dragNextAway = "drag the next song to the bottom"
    /// Repeat All on the last song, then Add to Queue t7: t7 is next, not the first song.
    case appendOnLastUnderRepeatAll = "Repeat All on the last song, then Add to Queue"
    /// Shuffle on a one-song queue, then Add to Queue t7: t7 is next, the queue does not stop.
    case appendToOneSongShuffle = "shuffle on one song, then Add to Queue"

    var description: String {
        rawValue
    }

    /// The song that must play next.
    var expectedNext: URL {
        switch self {
        case .dragUnderPlaying: track(3)
        case .dragNextAway: track(2)
        case .appendOnLastUnderRepeatAll, .appendToOneSongShuffle: track(7)
        }
    }

    @MainActor
    func rig(pure: Bool) async throws -> Rig {
        switch self {
        case .dragUnderPlaying, .dragNextAway: try await Rig.playing(tracks: 6, pure: pure)
        case .appendOnLastUnderRepeatAll: try await Rig.playing(tracks: 3, at: 2, pure: pure, repeatMode: 1)
        case .appendToOneSongShuffle: try await Rig.playing(tracks: 1, pure: pure, shuffle: true)
        }
    }

    @MainActor
    func perform(on model: AudioViewModel) {
        switch self {
        case .dragUnderPlaying: model.moveByDrop(fromID: model.queue[3].id, toIndex: 1)
        case .dragNextAway: model.moveByDrop(fromID: model.queue[1].id, toIndex: model.queue.count - 1)
        case .appendOnLastUnderRepeatAll, .appendToOneSongShuffle: model.appendToQueue([audioFile(7)])
        }
    }
}

@MainActor
enum QueueEditScenarios {
    /// A song plays, the user edits the queue, the song ends: the queue's next song plays, and shows.
    static func editWhilePlaying(_ edit: QueueEdit, pure: Bool) async throws -> Outcome {
        let rig = try await edit.rig(pure: pure)
        let armedBefore = rig.engine.armed
        edit.perform(on: rig.vm)
        try await rig.settle()
        rig.engine.drain()
        let promised = rig.pending
        let armed = rig.engine.armed
        try await rig.endTrackAndFollow()
        let ok = promised == edit.expectedNext && armed == edit.expectedNext
            && rig.engine.current == edit.expectedNext && rig.shown == edit.expectedNext
        return Outcome(ok: ok, detail: "\(edit) on \(OnDeckScenarios.pathName(pure)): armed \(name(armedBefore)) → "
            + "\(name(armed)), promised \(name(promised)); after the end " + rig.state)
    }

    /// APPEND-DURING-PRIME (the F-P4-1 sibling): Play the last song; while the start's prime is still
    /// settling its pick (none: it is the last song) — `isPlaying` still false — Add to Queue t9. t9
    /// must be what plays next: the append was not armed (`guard isPlaying`), and the queue stopped.
    static func appendDuringPrime(pure: Bool) async throws -> Outcome {
        let rig = Rig(tracks: 3)
        rig.vm.pureModeEnabled = pure
        rig.vm.playTrack(at: 2)
        try await rig.settle() // the start ran; its prime's request (nothing next) is not settled yet
        let playingDuringPrime = rig.vm.isPlaying
        rig.vm.appendToQueue([audioFile(9)])
        try await rig.settle()
        rig.engine.drain()
        try await rig.waitUntil("the start to finish its prime") { rig.vm.isPlaying }
        rig.tick()
        let promised = rig.pending
        let armed = rig.engine.armed
        try await rig.endTrackAndFollow()
        let ok = !playingDuringPrime && promised == track(9) && armed == track(9)
            && rig.engine.current == track(9) && rig.shown == track(9)
        return Outcome(ok: ok, detail: "APPEND-DURING-PRIME on \(OnDeckScenarios.pathName(pure)): playing during "
            + "the prime \(playingDuringPrime); promised \(name(promised)), armed \(name(armed)); after the end "
            + rig.state)
    }

    /// PLAY-NOW-BY-SLOT (N6): the queue holds t0 twice; the second copy plays. Play-now t0 again (the
    /// Songs list's double-click) restarts the PLAYING slot in place — it used to move the earlier copy
    /// to after the current one and play that.
    static func playNowThePlayingSong(pure: Bool) async throws -> Outcome {
        let rig = Rig(tracks: 0)
        rig.vm.pureModeEnabled = pure
        rig.vm.queue = [QueueItem(file: audioFile(0)), QueueItem(file: audioFile(1)), QueueItem(file: audioFile(0))]
        rig.vm.playTrack(at: 2)
        try await rig.settle()
        rig.engine.drain()
        try await rig.waitUntil("the start to play") { rig.vm.isPlaying }
        let slots = rig.vm.queue.map(\.id)
        let playingSlot = rig.vm.selectedSlotID
        let startsBefore = rig.engine.heard.count(where: \.isStart)
        rig.vm.playTrackNextNow(audioFile(0))
        try await rig.settle()
        rig.engine.drain()
        try await rig.waitUntil("the restart to play") { rig.vm.isPlaying }
        let restarted = rig.engine.heard.count(where: \.isStart) == startsBefore + 1
        let ok = rig.vm.queue.map(\.id) == slots && rig.vm.selectedSlotID == playingSlot && restarted
            && rig.engine.current == track(0)
        let order = rig.vm.queue.map { slot in "\(name(slot.file.absoluteURL))#\(slots.firstIndex(of: slot.id) ?? -1)" }
        return Outcome(ok: ok, detail: "PLAY-NOW-BY-SLOT on \(OnDeckScenarios.pathName(pure)): queue \(order), "
            + "plays slot #\(rig.vm.selectedSlotID.flatMap { slots.firstIndex(of: $0) } ?? -1) (was #2), "
            + "restarted \(restarted)")
    }
}
