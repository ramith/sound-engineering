@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - What plays next after a queue edit (council C-17)

//
// The shipped `AudioViewModel` against `OnDeckEngineModel`: a song plays, the queue is edited, the
// song ends — the queue's next song plays, and shows. On b5c4cd3 they were council P4's repros: a
// song dragged in under the playing one never played, an append under Repeat All waited a whole
// cycle, a one-song shuffle plus an append stopped, an append during the last song's prime was never
// armed, and play-now of the playing song moved an earlier copy instead of restarting.

@Suite("AudioViewModel × engine — what plays next after a queue edit (council C-17)", .serialized)
@MainActor
struct QueueEditContractTests {
    @Test("An edit while a song plays: the queue's next song plays next, and shows",
          arguments: QueueEdit.allCases, [true, false])
    func editWhilePlaying(_ edit: QueueEdit, pure: Bool) async throws {
        let outcome = try await QueueEditScenarios.editWhilePlaying(edit, pure: pure)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("APPEND-DURING-PRIME: Add to Queue while the last song's start primes — the added song plays next",
          arguments: [true, false])
    func appendDuringPrime(pure: Bool) async throws {
        let outcome = try await QueueEditScenarios.appendDuringPrime(pure: pure)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("PLAY-NOW-BY-SLOT (N6): play-now of the playing song restarts its own slot, never an earlier copy",
          arguments: [true, false])
    func playNowThePlayingSong(pure: Bool) async throws {
        let outcome = try await QueueEditScenarios.playNowThePlayingSong(pure: pure)
        #expect(outcome.ok, "\(outcome)")
    }
}
