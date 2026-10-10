// EQOutputSwitch — what an output change does to the sound (Sprint EQ, Edge 5; ui-plan §4.4; break-it
// E2 and the review's fix round). Two separate questions:
//
// - SEND when the slot now current plays something else than the one before it — that includes
//   leaving for "no output", when the shared slot becomes current.
// - TOAST when the sound ARRIVES on an output and differs from what was last HEARD on one. "No output"
//   is not heard: a pinned output going away and another coming back to the shared slot is a change
//   the listener hears, though the slot current in between (shared) never changed. The launch's first
//   output has nothing heard before it, so it never toasts.

struct EQOutputSwitch: Equatable, Sendable {
    /// Send what now plays to the engine.
    let sends: Bool

    /// Raise the toast naming the output and its EQ.
    let toasts: Bool

    /// - Parameters:
    ///   - before: what the slot current before the change plays.
    ///   - now: what the slot current after it plays.
    ///   - lastHeard: what last played on an output (`nil`: none has played since launch).
    ///   - arrives: the change ends on an output (not on "no output").
    init(before: EQState, now: EQState, lastHeard: EQState?, arrives: Bool) {
        sends = now != before
        toasts = arrives && lastHeard != nil && now != lastHeard
    }
}
