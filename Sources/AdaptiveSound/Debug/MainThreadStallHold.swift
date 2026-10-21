#if DEBUG
    import Foundation
    import Synchronization

    // MARK: - The hold, its release, and the caps that break a hang (`make main-thread-stall`)

    //
    // The check is judged by BEHAVIOUR. The rig holds AVFAudio's engine-wide lock on purpose, until the
    // TEST releases it, and the verdict is whether the main thread keeps finishing its work meanwhile.
    // A main thread that touches the lock cannot finish until the release — so it never gets there, and
    // `StallHangCap` (a generous, loud cap on a separate thread) names what main was doing. No
    // millisecond threshold decides anything; timings are printed as information only.

    /// How a run ends when something does not happen: print what, name it, exit non-zero.
    enum StallVerdict {
        /// A generous cap that only breaks a hang: the states below happen in tens of milliseconds.
        static let hangCap = 20.0 // seconds

        static func fail(_ message: String) -> Never {
            print("main-thread-stall FAIL: \(message)")
            fflush(stdout)
            exit(1)
        }

        /// Wait for `semaphore`'s signal — the state named `state` — or fail naming it at the cap.
        static func wait(_ semaphore: DispatchSemaphore, for state: String, cap: Double = hangCap) {
            guard semaphore.wait(timeout: .now() + cap) == .timedOut else { return }
            fail("\(state) did not happen within \(Int(cap)) s")
        }
    }

    /// What the main thread is doing right now, for the failure message: the entry it is inside.
    final class StallProgress: Sendable {
        private let entry = Mutex<String?>(nil)

        func enter(_ name: String) {
            entry.withLock { $0 = name }
        }

        func leave() {
            entry.withLock { $0 = nil }
        }

        var description: String {
            entry.withLock { $0.map { "main was inside '\($0)'" } ?? "main was between entries" }
        }
    }

    /// The hang cap of a phase in which the engine lock is held: if the phase has not ended `cap` seconds
    /// after `begin`, the main thread is stuck (a main thread waiting on the lock cannot run the test's
    /// own release), and the cap fails the run naming the phase and what main was doing.
    final class StallHangCap: Sendable {
        private let current = Mutex<DispatchSemaphore?>(nil)

        func begin(_ phase: String, progress: StallProgress, cap: Double = StallVerdict.hangCap) {
            let ended = DispatchSemaphore(value: 0)
            current.withLock { $0 = ended }
            Thread.detachNewThread {
                guard ended.wait(timeout: .now() + cap) == .timedOut else { return }
                StallVerdict.fail("\(phase) did not finish within \(Int(cap)) s with the engine lock held — "
                    + "\(progress.description), so the main thread waits on the engine lock")
            }
        }

        func end() {
            current.withLock { $0 }?.signal()
        }
    }

    /// The engine lock, held until the test releases it. The holder — inside the lock, on whatever
    /// thread AVFAudio runs it — calls `holdIfArmed()`: it says it is INSIDE (a handshake, not a guess)
    /// and waits for `release()`. The holder's own cap is a backstop for a test that never releases.
    final class StallHold: Sendable {
        static let shared = StallHold()
        private let armed = Atomic<Bool>(false)
        private let insideLock = Atomic<Bool>(false)
        private let released = DispatchSemaphore(value: 0)

        /// The next holder to run takes the hold.
        func arm() {
            insideLock.store(false, ordering: .releasing)
            armed.store(true, ordering: .releasing)
        }

        /// Called by the holder INSIDE the lock.
        func holdIfArmed() {
            guard armed.exchange(false, ordering: .acquiringAndReleasing) else { return }
            insideLock.store(true, ordering: .releasing)
            StallVerdict.wait(released, for: "the test's release of the engine lock",
                              cap: StallVerdict.hangCap * 2)
        }

        /// True once the holder is inside the lock.
        var isInside: Bool {
            insideLock.load(ordering: .acquiring)
        }

        /// Let the holder go: the lock is released.
        func release() {
            released.signal()
        }
    }

    /// A live AVFAudio read on a BACKGROUND thread: it takes the engine lock, so it cannot finish while
    /// the hold lasts. That is the proof the lock really was held — by behaviour, not by a timer.
    final class StallControlRead: Sendable {
        private let started = Atomic<Bool>(false)
        private let finished = Atomic<Bool>(false)

        func start(_ read: @escaping @Sendable () -> Void) {
            Thread.detachNewThread { [self] in
                started.store(true, ordering: .releasing)
                read()
                finished.store(true, ordering: .releasing)
            }
        }

        var isWaiting: Bool {
            started.load(ordering: .acquiring) && !finished.load(ordering: .acquiring)
        }

        var isDone: Bool {
            finished.load(ordering: .acquiring)
        }
    }
#endif
