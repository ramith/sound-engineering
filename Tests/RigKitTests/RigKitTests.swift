// RIG — the test rig's primitives, each shown to fail LOUDLY (test-rig redesign, rule 1): a wait that
// reaches its cap throws and names the state; a hold that is left held, never reached or gave up fails
// the test that opened it. A rig that could pass silently past a deadline would be the bug it exists to
// stop, so each of these is a `withKnownIssue` proof.

import Foundation
@testable import RigKit
import Synchronization
import Testing

@Suite("RigKit — until, blocking, Hold and the log tail", .timeLimit(.minutes(3)))
struct RigKitTests {
    // MARK: until

    @Test("RIG-01: until returns once the state holds, and not before")
    func untilReturnsWhenTheStateHolds() async throws {
        let flag = Atomic<Bool>(false)
        let looks = Atomic<Int>(0)
        let raiser = Task {
            // Rises only once the wait has looked a few times and found it down.
            try await until("the wait to have looked") { looks.load(ordering: .acquiring) >= 5 }
            flag.store(true, ordering: .releasing)
        }
        try await until("the flag to rise") {
            looks.add(1, ordering: .acquiringAndReleasing)
            return flag.load(ordering: .acquiring)
        }
        let risen = flag.load(ordering: .acquiring)
        #expect(risen)
        try await raiser.value
    }

    @Test("RIG-02: until at its cap THROWS, naming the state and the line that waited")
    func untilThrowsAtItsCapNamingTheState() async {
        do {
            try await until("the moon to be cheese", cap: .milliseconds(30)) { false }
            Issue.record("until returned although its state never held")
        } catch let timeout as RigTimeout {
            #expect(timeout.what == "the moon to be cheese")
            #expect(timeout.description.contains("never reached: the moon to be cheese"))
            #expect(timeout.description.contains("RigKitTests.swift"))
        } catch {
            Issue.record("until threw something else: \(error)")
        }
    }

    @Test("RIG-03: until ends when its task is cancelled — a .timeLimit can end a wait")
    func untilEndsOnCancellation() async {
        let looks = Atomic<Int>(0)
        let waiting = Task {
            try await until("a state that never holds", cap: .seconds(120)) {
                looks.add(1, ordering: .acquiringAndReleasing)
                return false
            }
        }
        // Once it is looking, cancel: the wait ends with the cancellation, not at its cap.
        try? await until("the wait to be looking") { looks.load(ordering: .acquiring) >= 100 }
        waiting.cancel()
        do {
            try await waiting.value
            Issue.record("a cancelled wait returned normally")
        } catch is CancellationError {
            // as expected
        } catch {
            Issue.record("a cancelled wait threw \(error)")
        }
    }

    /// A main-actor helper that FORWARDS a condition it was given, as `Rig.waitUntil` does: a closure written
    /// inline in a main-actor test is main-actor-isolated anyway, one handed on as a value is not.
    @MainActor
    private func forwarding(_ condition: () -> Bool) async throws {
        try await until("a condition that is read three times", condition)
    }

    @MainActor
    @Test("RIG-15: until evaluates its condition on the CALLER's actor — a main-actor model is never read from another thread")
    func untilRunsItsConditionOnTheCallersActor() async throws {
        var looks = 0
        var offMainLooks = 0
        try await forwarding {
            looks += 1
            if pthread_main_np() == 0 {
                offMainLooks += 1
            }
            return looks >= 3
        }
        #expect(offMainLooks == 0, "the condition ran off the main thread \(offMainLooks) of \(looks) times")
    }

    @MainActor
    @Test("RIG-04: untilOnMainRunLoop sees a main-queue block run, and throws at its cap otherwise")
    func untilOnMainRunLoopSeesMainQueueWork() async throws {
        var ran = false
        DispatchQueue.main.async { ran = true }
        try await untilOnMainRunLoop("the main-queue block to run") { ran }
        do {
            try await untilOnMainRunLoop("a state that never holds", cap: .milliseconds(30)) { false }
            Issue.record("untilOnMainRunLoop returned although its state never held")
        } catch is RigTimeout {
            // as expected
        }
    }

    // MARK: blocking

    @Test("RIG-05: blocking runs on a thread of its own, named for it, and returns what the work returns")
    func blockingRunsOffThePool() async throws {
        let name = try await blocking("probe") { Thread.current.name ?? "" }
        #expect(name == "rig.blocking.probe")
        let sum = try await blocking("sum") { (1 ... 100).reduce(0, +) }
        #expect(sum == 5050)
    }

    @Test("RIG-06: blocking rethrows what its work throws")
    func blockingRethrows() async {
        struct Boom: Error {}
        do {
            try await blocking("throws") { throw Boom() }
            Issue.record("blocking swallowed the error")
        } catch is Boom {
            // as expected
        } catch {
            Issue.record("blocking threw \(error)")
        }
    }

    @Test("RIG-07: more blocked work than the pool has threads still lets a plain task run")
    func blockingDoesNotStarveThePool() async throws {
        // Twice as many blocked jobs as cores: on the cooperative pool they would hold every thread.
        let release = Hold("the blocked jobs")
        let jobs = (0 ..< ProcessInfo.processInfo.activeProcessorCount * 2).map { index in
            Task { try await blocking("job\(index)") { release.wait() } }
        }
        let ran = Atomic<Bool>(false)
        await Task { ran.store(true, ordering: .releasing) }.value
        let didRun = ran.load(ordering: .acquiring)
        #expect(didRun, "a plain task could not run beside the blocked jobs")
        release.release()
        for job in jobs {
            try await job.value
        }
    }

    // MARK: Hold

    @Test("RIG-08: a producer waits at the hold until the test releases it")
    func holdKeepsTheProducerUntilReleased() async throws {
        let progress = Atomic<Int>(0)
        try await withHold("the producer's first step") { hold in
            let producer = Task {
                try await blocking("producer") {
                    progress.store(1, ordering: .releasing)
                    hold.wait()
                    progress.store(2, ordering: .releasing)
                }
            }
            try await hold.arrived()
            let atHold = progress.load(ordering: .acquiring)
            #expect(atHold == 1, "the producer went past the hold")
            hold.release()
            try await producer.value
            let pastHold = progress.load(ordering: .acquiring)
            #expect(pastHold == 2)
        }
    }

    @Test("RIG-09: a hold the producer never reaches fails the test, unless the test says it may not")
    func holdNeverReached() async throws {
        await withKnownIssue("a hold nobody reaches is the premise failing") {
            try? await withHold("an unreached point") { _ in }
        }
        try await withHold("an optional point", mayNotArrive: true) { _ in }
    }

    @Test("RIG-10: a hold reached but never released by the test fails the test")
    func holdLeftHeld() async throws {
        await withKnownIssue("a hold left held is the test forgetting to release") {
            try? await withHold("a forgotten point") { hold in
                let producer = Task { try await blocking("forgotten") { hold.wait() } }
                try await hold.arrived()
                _ = producer // never released inside the body: the scope ends with the producer waiting
            }
        }
    }

    @Test("RIG-11: a hold whose producer gave up at the hang cap fails the test — it never goes quietly")
    func holdExpired() async throws {
        await withKnownIssue("a producer that gave up at the cap proved nothing") {
            try? await withHold("a short-capped point", cap: .milliseconds(50)) { hold in
                try await blocking("expires") { hold.wait() } // the cap frees it
                // the test is late: the producer is already past the hold
            }
        }
    }

    // MARK: Log tail

    @Test("RIG-12: the log tail keeps the most recent lines, oldest first, and is bounded")
    func logTailIsBounded() {
        let tail = LogTail()
        for index in 0 ..< 5000 {
            tail.append("line \(index)")
        }
        let last = tail.tail(3).split(separator: "\n").map(String.init)
        #expect(last == ["line 4997", "line 4998", "line 4999"])
        #expect(tail.tail(100_000).split(separator: "\n").count == 2000)
    }
}

@Suite("RigKit — a failing test shows the log tail", .timeLimit(.minutes(1)), .attachingLogTail)
struct LogTailAttachmentTests {
    @Test("RIG-13: an issue in a suite with .attachingLogTail attaches the tail without breaking the issue")
    func attachesOnFailure() {
        LogTail.shared.append("[UX] something the app did before the failure")
        withKnownIssue("the issue still counts, with the tail attached") {
            Issue.record("a failing check")
        }
    }
}

@Suite("RigKit — OffPoolExecutor", .timeLimit(.minutes(1)))
struct OffPoolExecutorTests {
    @Test("RIG-14: a task on an OffPoolExecutor runs, and blocking it starves nothing else")
    func offPoolTaskBlocksOnlyItself() async throws {
        let executor = OffPoolExecutor("probe")
        let hold = Hold("the off-pool task")
        let ranOnItsQueue = Atomic<Bool>(false)
        let task = Task(executorPreference: executor) {
            ranOnItsQueue.store(true, ordering: .releasing)
            hold.wait() // blocks the executor's thread, not the cooperative pool
        }
        try await hold.arrived()
        let plain = Atomic<Bool>(false)
        await Task { plain.store(true, ordering: .releasing) }.value
        let plainRan = plain.load(ordering: .acquiring)
        #expect(plainRan, "a plain task could not run beside the blocked off-pool task")
        hold.release()
        await task.value
        let onItsQueue = ranOnItsQueue.load(ordering: .acquiring)
        #expect(onItsQueue)
    }
}
