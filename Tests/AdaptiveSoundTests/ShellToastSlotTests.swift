@testable import AdaptiveSound
import Clocks
import Foundation
import RigKit
import Testing

// MARK: - The shell toast's lifetime runs on the slot's clock (test-rig seam, R1.1-A)

//
// `ShellToastSlot` (the queue-add toast, the EQ's output-switch toast) clears itself after its lifetime,
// through ONE cancellable timer. Its clock is injected; the app's is `ContinuousClock`. Here an
// `ImmediateClock` makes the lifetime a no-op, and a `TestClock` lets the test say when time passes.

@MainActor
@Suite("Shell toast: its lifetime on an injected clock", .timeLimit(.minutes(3)))
struct ShellToastSlotTests {
    @Test("a raised message clears itself after its lifetime — on the slot's clock, not a real 2 s")
    func aToastClearsItself() async throws {
        let slot = ShellToastSlot(lifetime: .seconds(2), clock: ImmediateClock())
        slot.show("Added to Queue")
        #expect(slot.toast?.message == "Added to Queue", "shown at once, in the turn it was raised")
        try await until("the toast to clear itself") { slot.toast == nil }
    }

    @Test("a re-raise of the same message is a new toast (the host re-announces it); dismiss clears at once")
    func aReRaiseIsANewToast() {
        let slot = ShellToastSlot(lifetime: .seconds(2), clock: TestClock())
        slot.show("Playing Next")
        let first = slot.toast
        slot.show("Playing Next")
        #expect(slot.toast?.message == "Playing Next")
        #expect(slot.toast != first, "an identical message must still be a new toast")
        slot.dismiss()
        #expect(slot.toast == nil)
    }

    @Test("a superseded timer never clears the newer message: it goes a whole lifetime after the newer raise")
    func aSupersededTimerNeverClearsTheNewerMessage() async throws {
        let clock = TestClock()
        let slot = ShellToastSlot(lifetime: .seconds(2), clock: clock)
        slot.show("Added to Queue")
        try await until("the first toast's timer to be sleeping") { await Self.isSleeping(clock) }
        await clock.advance(by: .seconds(1)) // a second into its lifetime, another add
        slot.show("Added 2 to Queue")
        let raised = clock.now
        // Let time pass half a second at a step until the toast clears; it must not clear before the newer
        // message's whole lifetime has passed (the first timer, cancelled, would have fired at 2 s).
        try await until("the newer toast to clear") {
            if slot.toast == nil {
                return true
            }
            await clock.advance(by: .milliseconds(500))
            return false
        }
        let shownFor = raised.duration(to: clock.now)
        #expect(shownFor >= .seconds(2), "cleared \(shownFor) after the newer raise")
    }

    /// Whether a sleep is pending on `clock` (its `checkSuspension` throws while one is).
    private static func isSleeping(_ clock: TestClock<Duration>) async -> Bool {
        do {
            try await clock.checkSuspension()
            return false
        } catch {
            return true
        }
    }
}
