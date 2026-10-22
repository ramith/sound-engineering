// A hold that only the TEST releases (test-rig redesign, rule 1: holds are released only by the test).
//
// A producer — a decode, a walk, a completion — is held at a point until the test has seen what it
// needs to see; it is never held "for N seconds". The old ANALYZER-05 hold gave up at 30 s and the
// test's premise broke silently. This one has no way out but `release()` — except a hang cap far above
// any busy runner, which frees the producer so the process can end, and is REPORTED: the scope fails
// the test. The producer never records an issue itself: swift-testing attributes an issue to the
// test of the calling task, and a producer runs on whatever thread the product chose.

public import Testing
import Foundation

/// A point a producer waits at, until the test releases it.
public final class Hold: @unchecked Sendable {
    /// What is held, for failures.
    public let name: String
    private let cap: Duration
    private let condition = NSCondition()
    private var reached = false
    private var released = false
    private var expired = false

    /// - Parameters:
    ///   - name: what is held ("ANALYZER-05's prefix").
    ///   - cap: the producer's hang cap; past it the producer carries on and the scope fails the test.
    public init(_ name: String, cap: Duration = .seconds(300)) {
        self.name = name
        self.cap = cap
    }

    /// PRODUCER side, any thread: arrive, then block until `release()`.
    public func wait() {
        condition.lock()
        defer { condition.unlock() }
        reached = true
        condition.broadcast() // a test polling for the arrival need not wait for its next look
        let (seconds, attoseconds) = cap.components
        let deadline = Date(timeIntervalSinceNow: Double(seconds) + Double(attoseconds) / 1e18)
        while !released {
            if !condition.wait(until: deadline) {
                expired = true
                return
            }
        }
    }

    /// Whether a producer has arrived.
    public var hasArrived: Bool {
        condition.withLock { reached }
    }

    /// Whether the producer gave up waiting at the hang cap.
    public var hasExpired: Bool {
        condition.withLock { expired }
    }

    /// Whether the test has released the hold.
    var wasReleased: Bool {
        condition.withLock { released }
    }

    /// TEST side: wait until a producer has arrived, failing — naming this hold — if none ever does.
    public func arrived(
        cap: Duration = .seconds(120),
        isolation _: isolated (any Actor)? = #isolation,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await until("\(name) to be reached by its producer", cap: cap, sourceLocation: sourceLocation) {
            hasArrived
        }
    }

    /// TEST side: let the producer go on.
    public func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

/// Run `body` with a hold named `name`; checked on the test's own task when the scope ends.
///
/// Fails the test, at the caller's line, when the hold's producer gave up at the hang cap (the test
/// then proved nothing), when a producer arrived and the test never released it before the scope ended,
/// or — unless `mayNotArrive` — when no producer ever arrived (the premise never happened). Whatever
/// the outcome, the hold is released on the way out, so no producer stays blocked.
public func withHold<Result>(
    _ name: String,
    cap: Duration = .seconds(300),
    mayNotArrive: Bool = false,
    isolation _: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: (Hold) async throws -> Result
) async throws -> Result {
    let hold = Hold(name, cap: cap)
    let result: Result
    do {
        result = try await body(hold)
    } catch {
        hold.release()
        throw error
    }
    let leftHeld = hold.hasArrived && !hold.wasReleased
    hold.release()
    if hold.hasExpired {
        Issue.record(
            "hold '\(name)' gave up at its hang cap of \(cap): the producer carried on without the test's release",
            sourceLocation: sourceLocation
        )
    } else if leftHeld {
        Issue.record("hold '\(name)' was reached but the test never released it", sourceLocation: sourceLocation)
    } else if !hold.hasArrived, !mayNotArrive {
        Issue.record("hold '\(name)' was never reached: the premise of the test did not happen",
                     sourceLocation: sourceLocation)
    }
    return result
}
