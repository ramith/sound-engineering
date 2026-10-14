import Foundation
import PlaybackQueueKit

// MARK: - AudioViewModel: numbering what it asks of the engine (council C-15, D41)

/// Every start, seek and stop is numbered in the turn the user asks for it (`transportEpoch`), never
/// later in its task: the numbers are the order the user asked in. The engine runs a command only if
/// it has not begun a newer one (`AudioEngineBridge.beginTransportOperation`), so whatever order the
/// commands reach it in — their hops keep none — the newest stands, and the tick ignores the samples
/// of the playback it replaces (`TransportSnapshot.isCurrent(for:)`). The view model's side is the
/// start or stop still on its way (`transportCommand`): a press while it runs acts on it, and only the
/// newest command's outcome is applied when it finishes. On-deck requests carry their own ticket
/// (`OnDeckTicket`), in the playback of the newest start.
@MainActor
extension AudioViewModel {
    /// A start or a stop on its way to the engine, by its epoch.
    enum TransportCommand: Equatable {
        /// A start the engine has not begun yet (or whose return has not reached the view model).
        case start(UInt64)
        /// The start has begun: its prime is picking what plays after it (`primeGaplessPipeline`).
        case prime(UInt64)
        /// A Stop, or a Pause: the engine has no pause, so a pause is a stop that keeps the place.
        case stop(UInt64)
    }

    /// Playing, as the user last asked: a start on its way counts as playing, a playback with a stop or
    /// a pause on its way does not. What the play / pause control shows and toggles, and what Next and
    /// Previous follow (council C-15).
    var playIntent: Bool {
        switch transportCommand {
        case .start, .prime: true
        case .stop: false
        case nil: isPlaying
        }
    }

    /// Whether what plays next is the view model's to keep now: a song plays with nothing on its way,
    /// or a start's prime is picking it. Queue edits, Play Next and a shuffle / repeat change re-arm the
    /// on-deck only then (council C-15, C-17). Before the prime, the start's prime picks from the queue
    /// as it is then, and arms first: nothing is armed for a new playback before it takes its seam
    /// baseline, so no seam can hide in that baseline.
    var onDeckIsLive: Bool {
        switch transportCommand {
        case .prime: true
        case .start, .stop: false
        case nil: isPlaying
        }
    }

    /// Number the next transport request (see `transportEpoch`). Call it synchronously, before the
    /// request's `Task`, so no tick in between reads the replaced playback as current.
    func nextTransportEpoch() -> UInt64 {
        transportEpoch &+= 1
        return transportEpoch
    }

    /// Number a start: it owns the transport, and the on-deck requests belong to its playback, from now
    /// on — a start or stop still on its way is superseded.
    func nextStartEpoch() -> UInt64 {
        let epoch = nextTransportEpoch()
        onDeckSession = epoch
        transportCommand = .start(epoch)
        return epoch
    }

    /// Number a stop or a pause: it owns the transport from now on — a start still on its way is
    /// superseded, and neither primes nor marks playing.
    func nextStopEpoch() -> UInt64 {
        let epoch = nextTransportEpoch()
        transportCommand = .stop(epoch)
        return epoch
    }

    /// `command` finished. `true` when it is still the newest start or stop: nothing is on its way any
    /// more, and its outcome is the transport's. `false` when a newer one was asked meanwhile: that one
    /// owns the transport, and this outcome is dropped.
    func finish(_ command: TransportCommand) -> Bool {
        guard transportCommand == command else { return false }
        transportCommand = nil
        return true
    }

    /// Number the next on-deck request: the newest start's playback, and the next place in the
    /// order requests are made. Call it synchronously, in the turn that decides the request.
    func nextOnDeckTicket() -> OnDeckTicket {
        onDeckSequence &+= 1
        return OnDeckTicket(session: onDeckSession, sequence: onDeckSequence)
    }
}
