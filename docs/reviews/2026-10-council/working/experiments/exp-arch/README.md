# exp-arch — architecture reviewer experiments (council Stage 2)

E1 (`e1/main.swift`, standalone `swiftc -swift-version 6`): an `actor` whose `unownedExecutor` is an
existing `DispatchSerialQueue`. Result: compiles in Swift 6 mode; GCD blocks already on the queue reach
isolated state via `assumeIsolated` (no hop); the `otherQueue -> queue.sync { assumeIsolated }` shape
works; a `DispatchSourceTimer` on the queue reaches isolated state; 20 concurrent `await`ed synchronous
transport steps never overlapped (overlaps=0); an off-queue `assumeIsolated` TRAPS (signal 5), i.e. the
type now carries today's `dispatchPrecondition`. Output: "epoch=119 ops=22 overlaps=0 clockTicks=2 /
wrong-queue access: TRAP / E1 OK".

E2 (`e2/`, in worktree `.claude/worktrees/rev-arch` @ a206107): a LIBRARY target `ArchProbeCore`
depending only on `AudioDSP` reaches one symbol from every C sub-header (DeviceBridge, PureModeBridge,
AudioUnitRegistrationBridge, EQDesignBridge) through `import AudioDSP` — no `-import-objc-header` — and
hosts a `@MainActor @Observable` model plus a queue-backed actor; a swift-testing target
`@testable import`s it. `swift build --target ArchProbeCoreTests` 33 s; `swift test --filter
ArchProbeTests`: 2/2 passed.
