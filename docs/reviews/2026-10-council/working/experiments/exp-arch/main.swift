// E1 — can the bridge's hand-rolled "state confined to a serial queue" become compiler-checked
// WITHOUT changing a single hop? An actor whose executor IS the existing DispatchSerialQueue.
// Checks, under Swift 6 language mode:
//   (a) GCD blocks already running on the queue reach isolated state with assumeIsolated (no hop);
//   (b) the existing `otherQueue -> queue.sync { }` idiom still works (assumeIsolated inside .sync);
//   (c) a DispatchSourceTimer on the queue (the transport clock) reaches isolated state;
//   (d) a synchronous isolated method called with `await` from the main actor runs to completion
//       before the next one (no reentrancy => the "transport ops are mutually exclusive" rule holds);
//   (e) touching isolated state from the wrong queue traps (the dispatchPrecondition the code has
//       today, now implied by the type).
import Dispatch
import Foundation

actor EngineDomain {
    let queue: DispatchSerialQueue
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    // "engineQueue-confined" state: no lock, no @unchecked, no comment-only rule.
    private var transportEpoch: UInt64 = 0
    private var log: [String] = []
    private var inOp = false
    private(set) var overlaps = 0
    private var clock: DispatchSourceTimer?
    private(set) var clockTicks = 0

    init(queue: DispatchSerialQueue) { self.queue = queue }

    // A transport operation: synchronous inside the domain (no await => no reentrancy).
    func begin(epoch: UInt64, slowMillis: UInt32) {
        if inOp { overlaps += 1 }
        inOp = true
        transportEpoch = max(transportEpoch, epoch)
        usleep(slowMillis * 1000) // "slow HAL work"
        log.append("op \(epoch) on engineQueue=\(onQueue())")
        inOp = false
    }

    func startClock() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            // (c) a GCD callback already on the queue: prove it to the compiler, no hop, no Task.
            self?.assumeIsolated { $0.clockTicks += 1 }
        }
        timer.resume()
        clock = timer
    }

    func stopClock() { clock?.cancel(); clock = nil }

    // Called from legacy GCD code that is ALREADY on the queue.
    nonisolated func legacyCallbackOnQueue() {
        assumeIsolated { $0.log.append("legacy callback epoch=\($0.transportEpoch)") }
    }

    func snapshot() -> (epoch: UInt64, log: [String], overlaps: Int, ticks: Int) {
        (transportEpoch, log, overlaps, clockTicks)
    }

    private func onQueue() -> Bool {
        dispatchPrecondition(condition: .onQueue(queue)); return true
    }
}

let engineQueue = DispatchSerialQueue(label: "exp.engine")
let configQueue = DispatchQueue(label: "exp.config")
let domain = EngineDomain(queue: engineQueue)

// (a) async block posted to the queue by legacy code
let a = DispatchSemaphore(value: 0)
engineQueue.async { domain.legacyCallbackOnQueue(); a.signal() }
a.wait()

// (b) the existing `configChangeQueue -> engineQueue.sync` shape
let b = DispatchSemaphore(value: 0)
configQueue.async {
    let epoch: UInt64 = engineQueue.sync { domain.assumeIsolated { iso in iso.begin(epoch: 7, slowMillis: 1); return 7 } }
    precondition(epoch == 7)
    b.signal()
}
b.wait()

// (c) + (d): from the main actor, fire 20 overlapping "transport requests" as unstructured tasks.
let done = DispatchSemaphore(value: 0)
Task { @MainActor in
    await domain.startClock()
    await withTaskGroup(of: Void.self) { group in
        for i in 0 ..< 20 {
            group.addTask { await domain.begin(epoch: UInt64(100 + i), slowMillis: 3) }
        }
    }
    await domain.stopClock()
    let s = await domain.snapshot()
    print("epoch=\(s.epoch) ops=\(s.log.count) overlaps=\(s.overlaps) clockTicks=\(s.ticks)")
    precondition(s.overlaps == 0, "transport ops interleaved")
    precondition(s.ticks > 0, "clock never reached isolated state")
    precondition(s.log.count == 22)
    done.signal()
}
// Pump the main queue until the task finishes.
while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }

// (e) wrong-queue access must trap. Run in a child process so the parent can report it.
if CommandLine.arguments.contains("--trap") {
    configQueue.sync { domain.legacyCallbackOnQueue() } // NOT on engineQueue
    print("NOT TRAPPED (bad)")
    exit(0)
}
let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
child.arguments = ["--trap"]
child.standardError = FileHandle.nullDevice
child.standardOutput = FileHandle.nullDevice
try child.run(); child.waitUntilExit()
print("wrong-queue access: terminationReason=\(child.terminationReason == .uncaughtSignal ? "TRAP" : "exit") status=\(child.terminationStatus)")
print("E1 OK")
