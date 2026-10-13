@preconcurrency import AVFoundation
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
/// There is NO exception (S10.8 G, the disconnect freeze): the main thread takes this lock 20 times
/// a second (`currentSignalPath`, the device and AU borrows), so holding it across any call into
/// AVFAudio, the CoreAudio HAL or the Pure C-ABI — which can wait seconds while macOS tears a device
/// down — would freeze the app. `withPureEngine` used to run Pure's C-ABI (seek's HAL stop/start
/// included) under it; it now borrows the session under the lock and calls OUTSIDE it, on
/// `engineQueue`, where every Pure call and the Pure teardown are serialized. Teardown likewise does
/// its slow HAL work outside the lock (see `detachPureEngineForTeardown`).
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

    // MARK: - "Keep playback on this device"

    /// Thread-safe read of the pin preference (the output rule's `pinned` fact).
    var pinsPlaybackToSelectedDevice: Bool {
        withStateLock { storedPinPlaybackToSelectedDevice }
    }

    /// Thread-safe write of the pin preference (the `AudioPlaybackEngine` requirement; the view
    /// model pushes its Settings switch here).
    func setPinPlaybackToSelectedDevice(_ pin: Bool) {
        withStateLock { storedPinPlaybackToSelectedDevice = pin }
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
    // accessors. They are written from `engineQueue` (start/stop/seek/shutdown and the device-loss
    // teardown), and read from the MainActor 20 Hz poll (`currentPlaybackPosition` /
    // `trackTransitionCount` / `playbackEnded`) and the output rule on `configChangeQueue`, so every
    // access is serialized on the leaf lock. Direct field access outside these accessors is a data
    // race (S6 finding UAF-1).

    /// Thread-safe snapshot of the active output path. When you also need the Pure engine handle,
    /// prefer `withPureEngine` so the path check and the handle read are one atomic operation.
    var activePathKind: OutputPathKind {
        withStateLock { activePath }
    }

    /// Thread-safe write of the active output path.
    func setActivePath(_ value: OutputPathKind) {
        withStateLock { activePath = value }
    }

    /// Thread-safe snapshot of the Pure engine session (nil when not created). For lifecycle
    /// bookkeeping only (e.g. the lazy-create check in `startPure`); to USE the handle, go through
    /// `withPureEngine` so it cannot be destroyed mid-call.
    var pureEngineHandle: PureModeSession? {
        withStateLock { pureEngine }
    }

    /// Thread-safe write of the Pure engine session. Per the RT-safety invariant this is used ONLY
    /// to set a previously-`nil` field to a freshly-created session (the lazy create in `startPure`);
    /// clearing a live session goes through `detachPureEngineForTeardown` so the wrapper's `deinit`
    /// (slow HAL destroy) never runs while `stateLock` is held.
    func setPureEngine(_ value: PureModeSession?) {
        withStateLock {
            // RT-safety invariant: only ever SET onto a nil field; cleared only via detachPureEngineForTeardown.
            assert(pureEngine == nil, "setPureEngine must only set onto a nil field; clear via "
                + "detachPureEngineForTeardown to keep destroy off stateLock")
            pureEngine = value
        }
    }

    /// Borrow the live Pure engine handle for the duration of `body`. Returns `nil` WITHOUT invoking
    /// `body` when the Pure path is not active (or no handle exists) — callers treat that as "not on
    /// the Pure path" (e.g. the clock falls through to the Enhanced branch).
    ///
    /// ON `engineQueue` ONLY (enforced): every Pure C-ABI call (position, seam poll, end flag, seek,
    /// arm, clear) and every Pure teardown run there, so they are serialized with each other. The
    /// session is borrowed STRONGLY under `stateLock` and `body` runs OUTSIDE it: a seek's HAL
    /// stop/start or a clear's thread join can take long, and the main thread must never wait on the
    /// lock meanwhile. No teardown can run mid-call (same queue), and the strong borrow would keep the
    /// handle alive anyway.
    func withPureEngine<T>(_ body: (UnsafeMutableRawPointer) -> T) -> T? {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        guard let session = withStateLock({ activePath == .pure ? pureEngine : nil }) else { return nil }
        return body(session.handle)
    }

    /// Atomically (under `stateLock`) detach the Pure engine session for teardown: nil the field and
    /// reset `activePath` to `.enhanced`, returning the previous SESSION WRAPPER for the caller to
    /// `stop()` and then DROP OUTSIDE the lock (its `deinit` runs `pureModeEngineDestroy`). Returning
    /// the wrapper — rather than dropping it here — is what keeps the slow HAL destroy off `stateLock`:
    /// the field is nil under the lock, but the wrapper's release (and thus `deinit`) happens in the
    /// caller's controlled scope on `engineQueue`. Returns `nil` when no session was set. Idempotent:
    /// a second teardown (a stop after the device-loss pause) gets `nil` and skips — no double-free.
    @discardableResult
    func detachPureEngineForTeardown() -> PureModeSession? {
        withStateLock {
            let session = pureEngine
            pureEngine = nil
            activePath = .enhanced
            return session
        }
    }

    // MARK: - dspAudioUnit (cross-domain effects-AU reference)

    // `dspAudioUnit` is declared on the main class body. It is WRITTEN on the arbitrary
    // `AVAudioUnit.instantiate` completion queue (`+Graph`) and nil'd on `engineQueue` teardown
    // (`+Lifecycle`), while the MainActor control-plane publishers (publishEQ /
    // publishIntensity / publishCrossfeed / publishChannelLayout) read it. Those accesses MUST go
    // through the accessors below so the field is serialized on the leaf lock AND the reader holds a
    // STRONG ref for the whole C-ABI publish — otherwise a teardown-nil that drops the last ref
    // between the reader's load and its use is a use-after-free (S3 review finding F1). The
    // engineQueue-local reads (tap install/remove, teardown detach) stay direct: they are the owning
    // domain and are already ordered after the instantiate write and serialized with the nil.

    /// Thread-safe write of the effects-AU reference (instantiate-completion + teardown).
    func setDspAudioUnit(_ value: AVAudioUnit?) {
        withStateLock { dspAudioUnit = value }
    }

    /// Thread-safe strong borrow of the effects AU (nil when not instantiated). The returned strong
    /// ref keeps the AU alive across the caller's C-ABI publish even if teardown nils the field.
    var dspAudioUnitRef: AVAudioUnit? {
        withStateLock { dspAudioUnit }
    }

    // MARK: - avEngine / playerNode (cross-domain graph references)

    // Like `dspAudioUnit`, these are WRITTEN on `engineQueue` (initialize / teardown) but READ from
    // OFF-domain paths — the `AVAudioEngineConfigurationChange` handler and the CoreAudio device
    // listeners (configChangeQueue / the device-list listener queue). Those off-domain reads MUST go
    // through the strong-borrow accessors so a teardown-nil cannot free the engine/player between an
    // already-enqueued block's load and its use (S3 review finding BS1). engineQueue-local reads
    // (Graph/Lifecycle/Playback/...) stay direct: the owning domain, serialized with the writes.

    /// Thread-safe write of the AVAudioEngine reference (initialize / teardown).
    func setAvEngine(_ value: AVAudioEngine?) {
        withStateLock { avEngine = value }
    }

    /// Thread-safe strong borrow of the AVAudioEngine (nil when torn down). Held for the caller's use.
    var avEngineRef: AVAudioEngine? {
        withStateLock { avEngine }
    }

    /// Thread-safe write of the player-node reference (initialize / teardown).
    func setPlayerNode(_ value: AVAudioPlayerNode?) {
        withStateLock { playerNode = value }
    }

    /// Thread-safe strong borrow of the player node (nil when torn down). Held for the caller's use.
    var playerNodeRef: AVAudioPlayerNode? {
        withStateLock { playerNode }
    }
}
