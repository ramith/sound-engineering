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
///   - call any engine method (Pure C-ABI, AVAudioEngine, CoreAudio), or
///   - call out to any other closure that could re-enter the lock.
/// Because nothing is ever called while the lock is held, `stateLock` can never participate in a
/// deadlock cycle: there is no edge from `stateLock` to any queue or other lock in the wait-graph.
///
/// `os_unfair_lock` is non-recursive; the leaf-only rule guarantees we never re-enter it.
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
}
