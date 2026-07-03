// LibraryWatcher — the S8.4 FSEvents recursive watcher (slice 4, MECHANISM only).
//
// Watches the registered scan roots and emits decoded, `Sendable` path batches to a sink.
// It contains NO reconcile decisions (that is the VM's policy, slice 5, driving the
// already-verified `LibraryScanner.scan`) and NO store/AppKit dependency — so it is
// headless-testable via the `ingest` seam, and the LOGIC/PLUMBING split keeps ~all of S8.4
// deterministic while isolating the one non-deterministic piece (the real FSEvents stream).
//
// Swift-6 isolation (the SIGTRAP lesson from AudioViewModel+FolderMonitor): the C callback
// runs on the watcher's serial background queue and touches NO @MainActor state — it copies
// the C path/flags arrays into a Sendable value synchronously and hands them to the
// non-isolated `@Sendable` sink; the VM's sink hops to @MainActor FIRST. All mutable state
// (stream, roots, torn) is confined to `queue`; hence `@unchecked Sendable` (justified the
// same way as DispatchSource usage). Ordered Stop→Invalidate→Release teardown on that queue
// guarantees the callback can never fire into freed state.

import CoreServices
import Dispatch
import Foundation

/// One decoded FSEvents change: an absolute path + the flags that matter to reconcile policy.
public struct WatcherEvent: Sendable, Equatable {
    public let path: String
    public let isCreated: Bool
    public let isRemoved: Bool
    public let isRenamed: Bool
    public let isModified: Bool
    public let isDir: Bool
    public let mustScanSubdirs: Bool
    public let rootChanged: Bool

    public init(path: String, flags: FSEventStreamEventFlags) {
        self.path = path
        func has(_ flag: Int) -> Bool {
            flags & FSEventStreamEventFlags(flag) != 0
        }
        isCreated = has(kFSEventStreamEventFlagItemCreated)
        isRemoved = has(kFSEventStreamEventFlagItemRemoved)
        isRenamed = has(kFSEventStreamEventFlagItemRenamed)
        isModified = has(kFSEventStreamEventFlagItemModified)
        isDir = has(kFSEventStreamEventFlagItemIsDir)
        mustScanSubdirs = has(kFSEventStreamEventFlagMustScanSubDirs)
        rootChanged = has(kFSEventStreamEventFlagRootChanged)
    }
}

/// The decoded events from one callback invocation (or one synthetic `ingest`).
public struct WatcherEventBatch: Sendable, Equatable {
    public let events: [WatcherEvent]
    public init(events: [WatcherEvent]) {
        self.events = events
    }
}

/// Recursive FSEvents watcher over a set of roots. Mechanism only; the sink decides policy.
public final class LibraryWatcher: @unchecked Sendable {
    private let queue: DispatchQueue
    private let latency: TimeInterval
    private let onEvents: @Sendable (WatcherEventBatch) -> Void
    private var stream: FSEventStreamRef?
    private var roots: [URL] = []
    private var torn = false

    /// - Parameters:
    ///   - queue: a dedicated SERIAL background queue (callback delivery + teardown are confined here).
    ///   - latency: FSEvents coalescing window (1.0 s — the OS coalesces a burst before waking us).
    ///   - onEvents: the non-isolated `@Sendable` sink; the VM hops to @MainActor inside it.
    public init(
        queue: DispatchQueue, latency: TimeInterval = 1.0,
        onEvents: @escaping @Sendable (WatcherEventBatch) -> Void
    ) {
        self.queue = queue
        self.latency = latency
        self.onEvents = onEvents
    }

    /// Replace the watched root set (async on `queue`). Streams are immutable in their paths,
    /// so this stops→invalidates→releases→recreates — cheap, only on Choose/Remove-folder.
    public func setRoots(_ roots: [URL]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.roots = roots
            self.rebuildStreamLocked()
        }
    }

    /// Start watching (idempotent; no-op with no roots). Safe to call before/after `setRoots`.
    public func start() {
        queue.async { [weak self] in
            guard let self, self.stream == nil, !self.roots.isEmpty else { return }
            self.rebuildStreamLocked()
        }
    }

    /// Ordered teardown (Stop→Invalidate→Release), SYNC on `queue` so it can't race a callback.
    /// Idempotent; safe to call twice (e.g. from `shutdown()`).
    public func stop() {
        queue.sync { [weak self] in
            guard let self else { return }
            self.torn = true
            self.teardownStreamLocked()
        }
    }

    /// TEST SEAM: decode synthetic raw `(path, flags)` events and emit them, exactly as the
    /// real C callback does — so the debounce/decode/routing policy is testable deterministically
    /// with no OS scheduler. Production's callback funnels into `handleCallback` → here.
    public func ingest(rawEvents: [(path: String, flags: FSEventStreamEventFlags)]) {
        onEvents(WatcherEventBatch(events: rawEvents.map { WatcherEvent(path: $0.path, flags: $0.flags) }))
    }

    // MARK: - Private (all queue-confined)

    /// Called by the C callback ON `queue` with the copied-out raw events. No-op once torn.
    private func handleCallback(_ rawEvents: [(path: String, flags: FSEventStreamEventFlags)]) {
        guard !torn else { return }
        ingest(rawEvents: rawEvents)
    }

    private func rebuildStreamLocked() {
        teardownStreamLocked()
        guard !torn, !roots.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagIgnoreSelf
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, LibraryWatcher.eventCallback, &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    private func teardownStreamLocked() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - C callback trampoline

    /// The mandated `FSEventStreamCallback` C signature (6 params — fixed by the API). A
    /// `private static` closure (not a file-scope free function) so it can call the `private`
    /// `handleCallback` directly — same-type access, no `fileprivate` needed. Resolves the
    /// watcher from the context `info` pointer and copies the char** paths + flags into a
    /// Sendable value on the delivery queue, then hands them to `handleCallback`.
    private static let eventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
        guard let info else { return }
        let watcher = Unmanaged<LibraryWatcher>.fromOpaque(info).takeUnretainedValue()
        // Without kFSEventStreamCreateFlagUseCFTypes, eventPaths is a char** of `numEvents` C strings.
        let paths = eventPaths.bindMemory(to: UnsafeMutablePointer<CChar>?.self, capacity: numEvents)
        var raw: [(path: String, flags: FSEventStreamEventFlags)] = []
        raw.reserveCapacity(numEvents)
        for index in 0 ..< numEvents {
            guard let cString = paths[index] else { continue }
            raw.append((path: String(cString: cString), flags: eventFlags[index]))
        }
        watcher.handleCallback(raw)
    }
}
