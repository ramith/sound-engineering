// PlaybackQueueKit — which "what plays next" request the engine applies (council D41).
//
// While a song plays, the view model changes what plays after it — Play Next, a shuffle or repeat
// change, removing the next song, the seam's own re-arm — and tells the engine each time
// (`AudioPlaybackEngine.setNextTrack`). The requests reach the engine's queue after a hop that can
// reorder two of them, and on Pure each one then opens its file off that queue before it arms, so
// opens can finish in either order too. And a request made for a start the user has already left
// must never arm behind the next one. So every request carries a ticket — the start it follows and
// its place in the order the view model made requests — and the engine admits only the newest
// request of the playback it is in, dropping the rest whatever order they arrive in.
//
// SFBAudioEngine's idiom: every decoder has a sequence number, and events carry the playback
// generation they belong to, stale generations dropped (`AudioPlayer.mm`). Pure + `Sendable`, so
// the rule is unit-tested without the engine or the view model (`OnDeckGateTests`).

/// The number on one on-deck request.
public struct OnDeckTicket: Sendable, Equatable {
    /// The playback the request belongs to: the transport epoch of the start it follows.
    public let session: UInt64
    /// Its place in the order the view model made requests: from 1, never reset.
    public let sequence: UInt64

    public init(session: UInt64, sequence: UInt64) {
        self.session = session
        self.sequence = sequence
    }
}

extension OnDeckTicket: CustomStringConvertible {
    /// `e<session> #<sequence>`, for the engine's log lines.
    public var description: String {
        "e\(session) #\(sequence)"
    }
}

/// The engine's side of the tickets: the playback it is in, and the newest request admitted in it.
/// A value confined to one serial queue (the bridge's `engineQueue`).
public struct OnDeckGate: Sendable, Equatable {
    private var session: UInt64 = 0
    private var newest: UInt64 = 0

    public init() {}

    /// A start or a stop numbered `epoch` began a new playback: every request made before it is
    /// stale, and so is one made for a start this engine has not begun yet. Playbacks only move
    /// forward: a start or stop that reaches the engine after a newer one (their hops keep no order)
    /// changes nothing — as the transport epoch, which only grows.
    public mutating func beginSession(_ epoch: UInt64) {
        guard epoch > session else { return }
        session = epoch
        newest = 0
    }

    /// Admit `ticket` when it belongs to the current playback and is newer than every request
    /// admitted in it. A refused request must have no effect at all.
    public mutating func admit(_ ticket: OnDeckTicket) -> Bool {
        guard ticket.session == session, ticket.sequence > newest else { return false }
        newest = ticket.sequence
        return true
    }

    /// Whether `ticket` is still the newest request admitted in the current playback. An admitted
    /// pick whose file took a while to open arms only if this still holds when the open lands.
    public func isCurrent(_ ticket: OnDeckTicket) -> Bool {
        ticket.session == session && newest != 0 && ticket.sequence == newest
    }
}
