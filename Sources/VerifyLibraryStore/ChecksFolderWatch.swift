// ChecksFolderWatch — S8.4 Slice 4 FSEvents-watcher plumbing checks.
//
// The reconcile LOGIC is tested elsewhere by calling LibraryScanner.scan directly; here we
// test only the thin PLUMBING — that the watcher decodes FSEvents flags/paths correctly and
// routes RootChanged/MustScanSubDirs — DETERMINISTICALLY via the `ingest` seam (no real
// stream, no OS scheduler, no sleep). The real end-to-end stream gets a MANUAL subcommand
// (`--fsevents-smoke <dir>`), never the default gate (it would flake CI).

import CoreServices
import Foundation
import LibraryScan

/// Thread-safe capture for the watcher's non-isolated `@Sendable` sink.
private final class BatchBox: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [WatcherEventBatch] = []
    func append(_ batch: WatcherEventBatch) {
        lock.lock(); batches.append(batch); lock.unlock()
    }

    var all: [WatcherEventBatch] {
        lock.lock(); defer { lock.unlock() }; return batches
    }
}

/// Build an `FSEventStreamEventFlags` bitmask from the k-constants.
private func flags(_ values: Int...) -> FSEventStreamEventFlags {
    values.reduce(0) { $0 | FSEventStreamEventFlags($1) }
}

func checkWatcherIngest(number: Int, url _: URL) async -> Bool {
    let box = BatchBox()
    let watcher = LibraryWatcher(queue: DispatchQueue(label: "verify.watcher"), onEvents: { box.append($0) })

    // W1 — a synthetic burst decodes to the expected paths + flag bools.
    watcher.ingest(rawEvents: [
        (path: "/music/a.flac", flags: flags(kFSEventStreamEventFlagItemCreated)),
        (path: "/music/b.flac", flags: flags(kFSEventStreamEventFlagItemRenamed)),
        (path: "/music/Old Sub", flags: flags(kFSEventStreamEventFlagItemRemoved, kFSEventStreamEventFlagItemIsDir)),
    ])
    guard let first = box.all.first, first.events.count == 3 else {
        printFail(number, "watcher-ingest: expected a 3-event batch"); return false
    }
    guard first.events[0].path == "/music/a.flac", first.events[0].isCreated,
          first.events[1].isRenamed, first.events[2].isRemoved, first.events[2].isDir else {
        printFail(number, "watcher-ingest: flag/path decode wrong"); return false
    }

    // W2 — RootChanged / MustScanSubDirs surface (slice-5 policy keys off these).
    watcher.ingest(rawEvents: [
        (path: "/music", flags: flags(kFSEventStreamEventFlagRootChanged)),
        (path: "/music/Deep", flags: flags(kFSEventStreamEventFlagMustScanSubDirs)),
    ])
    guard box.all.count == 2, let second = box.all.last, second.events.count == 2,
          second.events[0].rootChanged, second.events[1].mustScanSubdirs else {
        printFail(number, "watcher-ingest: RootChanged/MustScanSubDirs not surfaced, or batch bled"); return false
    }
    printPass(number, "watcher ingest/decode: a synthetic FSEvents burst decodes to the right paths + flag "
        + "bools (create/rename/delete/dir); RootChanged/MustScanSubDirs surface for slice-5 policy — "
        + "deterministic via the ingest seam (no real stream)")
    return true
}

/// MANUAL real-stream smoke (NOT a default CheckCase — FSEvents latency would flake the gate):
/// `swift run VerifyLibraryStore --fsevents-smoke <dir>` arms a real watcher on <dir>, writes a
/// probe file, and waits (bounded) for the OS to deliver the event. The founder's "does the real
/// stream actually fire end-to-end" check, run by hand — mirrors the `--restart-*` subcommands.
func runFSEventsSmokeIfRequested() async {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3, arguments[1] == "--fsevents-smoke" else { return }
    let dir = URL(fileURLWithPath: arguments[2])
    let box = BatchBox()
    let queue = DispatchQueue(label: "smoke.watcher", qos: .utility)
    let watcher = LibraryWatcher(queue: queue, onEvents: { box.append($0) })
    watcher.setRoots([dir])
    watcher.start()
    try? await Task.sleep(for: .milliseconds(600)) // let the stream arm before we write
    let probe = dir.appendingPathComponent("fsevents-smoke-\(UUID().uuidString).flac")
    // Write via a CHILD process: kFSEventStreamCreateFlagIgnoreSelf filters events from THIS
    // process, so a same-process write would never be delivered. In production the app never
    // writes to watched roots (external taggers/Finder do — a different PID, "not self"), so
    // spawning `touch` faithfully mimics a real external change.
    let touch = Process()
    touch.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
    touch.arguments = [probe.path]
    try? touch.run()
    touch.waitUntilExit()
    var delivered = false
    for _ in 0 ..< 60 { // up to ~12 s of 200 ms polls
        if !box.all.isEmpty { delivered = true; break }
        try? await Task.sleep(for: .milliseconds(200))
    }
    watcher.stop()
    try? FileManager.default.removeItem(at: probe)
    if delivered {
        print("fsevents-smoke ok: real stream delivered \(box.all.count) batch(es) for a write under \(dir.path)")
        exit(0)
    }
    print("fsevents-smoke FAIL: no event within ~12s (is \(dir.path) a local volume? FSEvents skips network shares)")
    exit(1)
}
