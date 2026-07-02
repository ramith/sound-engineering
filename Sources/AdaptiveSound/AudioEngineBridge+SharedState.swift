import Foundation
import os

// MARK: - AudioEngineBridge shared playback-context state (one leaf lock)

/// One `os_unfair_lock` (`stateLock`) guarding the small set of playback-context fields that are
/// READ on the MainActor 20 Hz poll (`currentSignalPath()` / `currentPlaybackPosition()`) while
/// being WRITTEN from `engineQueue` / `configChangeQueue` / `resampleQueue` / the CoreAudio
/// listener queues. Before this change those fields (`cachedSignalPath`,
/// `enhancedPositionBaseSeconds`, `lastKnownEnhancedPositionSeconds`, `currentDeviceID`,
/// `lastFileURL`) were read and written with no synchronization at all (S6 finding P1-C).
///
/// ## Lock discipline — LEAF ONLY
///
/// `stateLock` is the innermost lock in the bridge. It is acquired ONLY for the duration of a
/// trivial field get / set / struct-field mutation and released immediately. The closure passed to
/// `withStateLock { }` MUST NOT:
///   - dispatch onto / `sync` into any queue (`engineQueue`, `resampleQueue`, `configChangeQueue`),
///   - call any engine method (AVAudioEngine, CoreAudio), or
///   - call out to any other closure that could re-enter the lock.
///
/// The ONE sanctioned exception is `withPureEngine` (below): it runs a Pure C-ABI *read* under the
/// lock so the handle cannot be destroyed mid-call. That is deadlock-free because those C-ABI reads
/// operate purely on the C++ session struct — they never re-enter the bridge, take `stateLock`, or
/// dispatch onto a bridge queue — so no edge from `stateLock` back to any queue/lock exists. Every
/// other closure obeys the no-call-out rule, so `stateLock` can never participate in a deadlock
/// cycle. (Teardown deliberately does its slow HAL work — destroy/stop — OUTSIDE the lock; see
/// `detachPureEngineForTeardown`.)
///
/// `os_unfair_lock` is non-recursive; the leaf-only rule guarantees we never re-enter it — no
/// closure passed to `withStateLock` / `withPureEngine` calls another `stateLock` accessor.
extension AudioEngineBridge {
    /// Run `body` while holding `stateLock`. `body` must be a trivial, non-blocking field
    /// operation (see the lock-discipline note above). The pointer-based lock/unlock is the
    /// supported `os_unfair_lock` usage from Swift.
    @inline(__always)
    func withStateLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(stateLockPtr)
        defer { os_unfair_lock_unlock(stateLockPtr) }
        return body()
    }

    // MARK: - cachedSignalPath

    /// Thread-safe snapshot read of the cached signal path (MainActor poll + others).
    func loadSignalPath() -> SignalPathInfo {
        withStateLock { storedCachedSignalPath }
    }

    /// Thread-safe replacement of the cached signal path.
    func storeSignalPath(_ value: SignalPathInfo) {
        withStateLock { storedCachedSignalPath = value }
    }

    /// Thread-safe read-modify-write of the cached signal path. `mutate` runs UNDER the leaf lock
    /// and so must only touch the struct's fields (no call-outs) — callers pass a simple closure
    /// such as `{ $0.fellBackToEnhanced = true }`.
    func mutateSignalPath(_ mutate: (inout SignalPathInfo) -> Void) {
        withStateLock { mutate(&storedCachedSignalPath) }
    }

    // MARK: - currentDeviceID

    /// Thread-safe read of the current target device ID.
    var currentDeviceID: UInt32 {
        withStateLock { storedCurrentDeviceID }
    }

    /// Thread-safe write of the current target device ID.
    func setCurrentDeviceID(_ value: UInt32) {
        withStateLock { storedCurrentDeviceID = value }
    }

    // MARK: - lastFileURL

    /// Thread-safe read of the last successfully scheduled file URL.
    var lastFileURL: URL? {
        withStateLock { storedLastFileURL }
    }

    /// Thread-safe write of the last successfully scheduled file URL.
    func setLastFileURL(_ value: URL?) {
        withStateLock { storedLastFileURL = value }
    }

    // MARK: - enhancedPositionBaseSeconds

    /// Thread-safe read of the Enhanced position base offset (seconds).
    var enhancedPositionBaseSeconds: Double {
        withStateLock { storedEnhancedPositionBaseSeconds }
    }

    /// Thread-safe write of the Enhanced position base offset (seconds).
    func setEnhancedPositionBaseSeconds(_ value: Double) {
        withStateLock { storedEnhancedPositionBaseSeconds = value }
    }

    // MARK: - lastKnownEnhancedPositionSeconds

    /// Thread-safe read of the last known Enhanced playhead (seconds).
    var lastKnownEnhancedPositionSeconds: Double {
        withStateLock { storedLastKnownEnhancedPositionSeconds }
    }

    /// Thread-safe write of the last known Enhanced playhead (seconds).
    func setLastKnownEnhancedPositionSeconds(_ value: Double) {
        withStateLock { storedLastKnownEnhancedPositionSeconds = value }
    }

    // MARK: - activePath / pureEngine (Pure-Mode lifecycle fields)

    // `activePath` and `pureEngine` are declared on the main class body (extensions cannot add
    // stored properties) but — like the `stored*` fields above — must be touched ONLY through these
    // accessors. They are written from `engineQueue` (start/stop/seek/shutdown) AND
    // `configChangeQueue` (device-loss `pauseForDeviceLoss` → `tearDownPure`), and read from the
    // MainActor 20 Hz poll (`currentPlaybackPosition` / `trackTransitionCount` / `playbackEnded`),
    // so every access is serialized on the leaf lock. Direct field access outside these accessors is
    // a data race (S6 finding UAF-1).

    /// Thread-safe snapshot of the active output path. When you also need the Pure engine handle,
    /// prefer `withPureEngine` so the path check and the handle read are one atomic operation.
    var activePathKind: OutputPathKind {
        withStateLock { activePath }
    }

    /// Thread-safe write of the active output path.
    func setActivePath(_ value: OutputPathKind) {
        withStateLock { activePath = value }
    }

    /// Thread-safe snapshot of the Pure engine handle (nil when not created). For lifecycle
    /// bookkeeping only (e.g. the lazy-create check in `startPure`); to USE the handle, go through
    /// `withPureEngine` so it cannot be destroyed mid-call.
    var pureEngineHandle: UnsafeMutableRawPointer? {
        withStateLock { pureEngine }
    }

    /// Thread-safe write of the Pure engine handle.
    func setPureEngine(_ value: UnsafeMutableRawPointer?) {
        withStateLock { pureEngine = value }
    }

    /// Borrow the live Pure engine handle for the duration of `body`, holding `stateLock` so a
    /// concurrent teardown cannot destroy it mid-call. Returns `nil` WITHOUT invoking `body` when
    /// the Pure path is not active (or no handle exists) — callers treat that as "not on the Pure
    /// path" (e.g. the poll falls through to the Enhanced branch).
    ///
    /// SAFE by construction (see the leaf-lock note at the top of this file):
    ///   1. `body` may ONLY call the non-re-entrant Pure C-ABI reads
    ///      (`pureModeEnginePositionSeconds` / `pureModeEnginePollTrackAdvance` /
    ///      `pureModeEnginePlaybackEnded` / `pureModeEngineSeek` / `pureModeEngineSetNextTrack` /
    ///      `pureModeEngineClearNextTrack`). Those touch only the C++ session; they never take
    ///      `stateLock` or hop a bridge queue, so no lock cycle forms. Do NOT call `logUX`/`NSLog`
    ///      or any `withStateLock` accessor inside `body`; log the returned result afterwards.
    ///   2. Teardown detaches the handle UNDER this same lock (`detachPureEngineForTeardown`) and
    ///      destroys it OUTSIDE the lock, so a borrower either finished its C-ABI call before the
    ///      detach returned, or observes `activePath != .pure` here and skips — it can never
    ///      dereference a freed handle.
    func withPureEngine<T>(_ body: (UnsafeMutableRawPointer) -> T) -> T? {
        withStateLock {
            guard activePath == .pure, let engine = pureEngine else { return nil }
            return body(engine)
        }
    }

    /// Atomically (under `stateLock`) detach the Pure engine handle for teardown: nil the field and
    /// reset `activePath` to `.enhanced`, returning the previous handle for the caller to
    /// `pureModeEngineStop` / `pureModeEngineDestroy` OUTSIDE the lock. Returns `nil` when no handle
    /// was set. Idempotent across the two teardown domains: if `engineQueue` (stop/shutdown) and
    /// `configChangeQueue` (device-loss) race, exactly one caller gets the handle and destroys it;
    /// the loser gets `nil` and skips — no double-free.
    @discardableResult
    func detachPureEngineForTeardown() -> UnsafeMutableRawPointer? {
        withStateLock {
            let handle = pureEngine
            pureEngine = nil
            activePath = .enhanced
            return handle
        }
    }
}
