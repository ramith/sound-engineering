// The ONE way a test here waits (test-rig redesign, rule 1: time only ever breaks hangs).
//
// A wait waits for a STATE. Its cap is a hang breaker, generous enough that no busy runner reaches it,
// and when it IS reached the wait THROWS, naming the state that never held and the line that waited
// for it. It never returns normally past a deadline, so no test can go on to assert on a half-finished
// state (the ANALYZER-05 bug). The cap is cooperative: a task cancelled by `.timeLimit` ends the wait.

import Foundation
import Testing

/// What a wait threw at its cap: the state that never held.
public struct RigTimeout: Error, CustomStringConvertible, Sendable {
    /// The state the test waited for.
    public let what: String
    /// How long it waited.
    public let cap: Duration
    /// Where the test waited.
    public let location: SourceLocation

    public var description: String {
        "never reached: \(what) — gave up after \(cap) (waited at \(location.fileID):\(location.line))"
    }
}

// The caps run on `SuspendingClock`: it does not count the time the Mac sleeps, so a nap in the middle of a run
// (a closed lid, an idle display) cannot make a wait give up on a state it had every chance to reach.

/// How many times a wait yields to the other tasks before it starts to nap between looks.
private let yieldsBeforeNapping = 64

/// Wait until `condition` holds. Looks at once, then yields to the other tasks (so work already
/// runnable lands first), then naps a millisecond between looks, cancellation-aware.
///
/// - Parameters:
///   - what: the STATE waited for, in words ("the engine to come up"); it is what a failure names.
///   - cap: a hang breaker, never a pass/fail line. Throws `RigTimeout` when it passes.
///   - isolation: the caller's actor. `condition` is `nonisolated(nonsending)`, so it runs ON that actor and
///     may read its state: a plain async closure would hop to the global executor to be evaluated, and a
///     test's main-actor model would be read from another thread.
public func until(
    _ what: String,
    cap: Duration = .seconds(120),
    isolation _: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: nonisolated(nonsending) () async throws -> Bool
) async throws {
    let deadline = SuspendingClock.now + cap
    var looks = 0
    while try await !condition() {
        guard SuspendingClock.now < deadline else {
            throw RigTimeout(what: what, cap: cap, location: sourceLocation)
        }
        looks += 1
        if looks < yieldsBeforeNapping {
            await Task.yield()
        } else {
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// Wait until `condition` holds while the MAIN RUN LOOP runs, for a state that only a main-thread timer
/// or a main-queue block can bring about (a `Timer` on `RunLoop.main`, `DispatchQueue.main.async`).
///
/// A main-actor test that only `await`s runs those too; this is for the case it cannot, where the state
/// is made by a run-loop source. It spins the loop in short slices and yields between them: the main
/// actor's own jobs do NOT run during a nested `RunLoop.run` while the test's job is executing, so the
/// yield is what lets them run (LiveReadoutsTests, PR #93).
@MainActor
public func untilOnMainRunLoop(
    _ what: String,
    cap: Duration = .seconds(120),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async throws {
    let deadline = SuspendingClock.now + cap
    while !condition() {
        guard SuspendingClock.now < deadline else {
            throw RigTimeout(what: what, cap: cap, location: sourceLocation)
        }
        spinMainRunLoop()
        await Task.yield()
    }
}

/// One slice of the main run loop. A plain synchronous function: `RunLoop.run(until:)` is unavailable in
/// an async context.
private func spinMainRunLoop() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
}
