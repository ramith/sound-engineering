import PlaybackQueueKit
import Testing

// MARK: - OnDeckGate — the engine applies only the newest "play next" request of its playback (VM-OD)

//
// Imports the shipped `PlaybackQueueKit` target, so the gate the bridge runs on `engineQueue` is the
// gate under test (council D41). The property test checks it against an independent oracle that
// keeps the whole history of the playback instead of a running maximum.

@Suite("PlaybackQueueKit — OnDeckGate, newest request per playback (VM-OD)")
struct OnDeckGateTests {
    private static let session: UInt64 = 7

    private static func ticket(_ sequence: UInt64, session: UInt64 = session) -> OnDeckTicket {
        OnDeckTicket(session: session, sequence: sequence)
    }

    private static func gate(in session: UInt64 = session) -> OnDeckGate {
        var gate = OnDeckGate()
        gate.beginSession(session)
        return gate
    }

    /// All orderings of `values` (Heap's algorithm).
    private static func permutations(_ values: [UInt64]) -> [[UInt64]] {
        var result: [[UInt64]] = []
        var array = values
        func generate(_ count: Int) {
            guard count > 1 else {
                result.append(array)
                return
            }
            for index in 0 ..< count {
                generate(count - 1)
                array.swapAt(count.isMultiple(of: 2) ? index : 0, count - 1)
            }
        }
        generate(array.count)
        return result
    }

    @Test("VM-OD-01: in every order five requests arrive, the newest is applied and only newer ones are admitted")
    func everyPermutationAppliesTheNewest() {
        let orders = Self.permutations([1, 2, 3, 4, 5])
        #expect(orders.count == 120)
        for order in orders {
            var gate = Self.gate()
            var highest: UInt64 = 0
            for sequence in order {
                let admitted = gate.admit(Self.ticket(sequence))
                // Admitted exactly when it is newer than everything that arrived before it.
                #expect(admitted == (sequence > highest), "order \(order): #\(sequence)")
                highest = max(highest, sequence)
            }
            #expect(gate.isCurrent(Self.ticket(5)), "order \(order): the newest is not the one applied")
            for older in 1 ... 4 {
                #expect(!gate.isCurrent(Self.ticket(UInt64(older))), "order \(order): #\(older) still current")
            }
        }
    }

    @Test("VM-OD-02: a request for an earlier playback, or for a start the engine has not begun, is refused")
    func otherPlaybacksAreRefused() {
        var gate = Self.gate()
        let earlier = gate.admit(Self.ticket(10, session: Self.session - 1))
        let notBegun = gate.admit(Self.ticket(11, session: Self.session + 1))
        let current = gate.admit(Self.ticket(12))
        #expect(!earlier, "an earlier playback's request")
        #expect(!notBegun, "a start not begun yet")
        #expect(current)
        #expect(!gate.isCurrent(Self.ticket(12, session: Self.session + 1)))
        #expect(gate.isCurrent(Self.ticket(12)))
    }

    @Test("VM-OD-03: beginning a playback makes the previous one's request stale")
    func beginSessionMakesThePreviousRequestStale() {
        var gate = Self.gate()
        let admitted = gate.admit(Self.ticket(3))
        #expect(admitted)
        #expect(gate.isCurrent(Self.ticket(3)))
        gate.beginSession(Self.session + 1)
        #expect(!gate.isCurrent(Self.ticket(3)), "an open that lands after the next start must not arm")
        let previous = gate.admit(Self.ticket(4))
        let next = gate.admit(Self.ticket(5, session: Self.session + 1))
        #expect(!previous, "a request made for the previous playback")
        #expect(next)
        #expect(gate.isCurrent(Self.ticket(5, session: Self.session + 1)))
        // Nothing admitted yet in a fresh playback: no request is current.
        var fresh = OnDeckGate()
        fresh.beginSession(9)
        #expect(!fresh.isCurrent(Self.ticket(0, session: 9)))
    }

    @Test("VM-OD-04: 20 000 random interleavings of starts, stops and requests agree with a history oracle")
    func randomInterleavingsAgreeWithTheOracle() {
        var rng = SplitMix64(seed: 0xD41)
        var checked = 0
        for _ in 0 ..< 20000 {
            var run = InterleavingRun()
            for _ in 0 ..< 16 {
                checked += run.step(&rng)
            }
            run.drain()
            checked += run.checkNewestWins()
        }
        #expect(checked > 100_000, "the property test checked too little")
    }

    @Test("VM-OD-06: a start or stop older than the playback the engine is in changes nothing")
    func anOlderBeginChangesNothing() {
        var gate = Self.gate()
        let admitted = gate.admit(Self.ticket(4))
        #expect(admitted)
        let before = gate
        // START-OVERTAKE: two starts reach the engine in reverse order (the newer one first).
        gate.beginSession(Self.session - 1)
        gate.beginSession(Self.session)
        #expect(gate == before, "an older (or the same) playback rolled the gate back")
        #expect(gate.isCurrent(Self.ticket(4)))
        let newer = gate.admit(Self.ticket(5))
        let older = gate.admit(Self.ticket(6, session: Self.session - 1))
        #expect(newer, "a request for the newest playback was refused after a stale begin")
        #expect(!older, "a request for the overtaken playback was admitted")
    }

    @Test("VM-OD-05: a refused request changes nothing")
    func aRefusedRequestChangesNothing() {
        var gate = Self.gate()
        let admitted = gate.admit(Self.ticket(4))
        #expect(admitted)
        let before = gate
        for stale in [Self.ticket(2), Self.ticket(4), Self.ticket(9, session: Self.session - 1),
                      Self.ticket(9, session: Self.session + 1)] {
            let refused = !gate.admit(stale)
            #expect(refused, "\(stale) was admitted")
            #expect(gate == before, "refusing \(stale) changed the gate")
        }
        #expect(gate.isCurrent(Self.ticket(4)))
        let newer = gate.admit(Self.ticket(5))
        #expect(newer)
    }
}

// MARK: - The property test's world and oracle

/// One random interleaving: the view model numbers starts, stops and requests in order; the engine
/// receives all of them in any order (each hops to its queue on its own).
private struct InterleavingRun {
    // The view model's side.
    private var epoch: UInt64 = 0
    private var vmSession: UInt64 = 0
    private var sequence: UInt64 = 0
    private var issued: [OnDeckTicket] = []

    // In flight to the engine, in any order.
    private var transportInFlight: [UInt64] = []
    private var requestsInFlight: [OnDeckTicket] = []

    // The engine, and the oracle: the whole history of the playback the engine is in.
    private var gate = OnDeckGate()
    private var engineSession: UInt64 = 0
    private var admittedThisSession: [OnDeckTicket] = []
    private var deliveredAfterBegin: [OnDeckTicket] = []

    /// One random step; returns the number of assertions it made.
    mutating func step(_ rng: inout SplitMix64) -> Int {
        switch rng.next() % 6 {
        case 0: // a start: it numbers the playback its later requests belong to
            epoch += 1
            vmSession = epoch
            transportInFlight.append(epoch)
            return 0
        case 1: // a stop: a new engine playback no request belongs to
            epoch += 1
            transportInFlight.append(epoch)
            return 0
        case 2: // a request
            sequence += 1
            let ticket = OnDeckTicket(session: vmSession, sequence: sequence)
            issued.append(ticket)
            requestsInFlight.append(ticket)
            return 0
        case 3:
            guard !transportInFlight.isEmpty else { return 0 }
            begin(transportInFlight.remove(at: Int(rng.next() % UInt64(transportInFlight.count))))
            return checkCurrent(rng: &rng)
        default:
            guard !requestsInFlight.isEmpty else { return 0 }
            let ticket = requestsInFlight.remove(at: Int(rng.next() % UInt64(requestsInFlight.count)))
            return deliver(ticket) + checkCurrent(rng: &rng)
        }
    }

    /// Everything still in flight arrives: the starts and stops first, then the requests.
    mutating func drain() {
        while !transportInFlight.isEmpty {
            begin(transportInFlight.removeFirst())
        }
        for ticket in requestsInFlight {
            _ = deliver(ticket)
        }
        requestsInFlight.removeAll()
    }

    /// Newest wins: of the requests that reached the engine's current playback, the newest is the
    /// one applied, whatever order they came in.
    func checkNewestWins() -> Int {
        guard let newest = deliveredAfterBegin.filter({ $0.session == engineSession })
            .max(by: { $0.sequence < $1.sequence }) else { return 0 }
        #expect(gate.isCurrent(newest), "the newest request \(newest) is not the one applied")
        return 1
    }

    private mutating func begin(_ epoch: UInt64) {
        gate.beginSession(epoch)
        // The oracle: the engine's playback is the newest start or stop it has begun.
        let session = max(engineSession, epoch)
        guard session != engineSession else { return }
        engineSession = session
        admittedThisSession.removeAll()
        deliveredAfterBegin.removeAll()
    }

    private mutating func deliver(_ ticket: OnDeckTicket) -> Int {
        deliveredAfterBegin.append(ticket)
        // The oracle: admitted iff it belongs to this playback and no request admitted in it is as new.
        let expected = ticket.session == engineSession
            && admittedThisSession.allSatisfy { $0.sequence < ticket.sequence }
        let admitted = gate.admit(ticket)
        #expect(admitted == expected, "admit \(ticket) in e\(engineSession): got \(admitted)")
        if expected {
            admittedThisSession.append(ticket)
        }
        return 1
    }

    /// The applied request is the newest one admitted in this playback, and only it.
    private func checkCurrent(rng: inout SplitMix64) -> Int {
        guard !issued.isEmpty else { return 0 }
        let probe = issued[Int(rng.next() % UInt64(issued.count))]
        let applied = admittedThisSession.max { $0.sequence < $1.sequence }
        #expect(gate.isCurrent(probe) == (probe == applied), "isCurrent(\(probe)) in e\(engineSession)")
        return 1
    }
}

/// A small deterministic generator (splitmix64), so a failing interleaving reproduces.
private struct SplitMix64 {
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
}
