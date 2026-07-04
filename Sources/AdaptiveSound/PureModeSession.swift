import Foundation

// MARK: - PureModeSession

/// RAII owner for the opaque Pure-Mode engine handle (`void*` from `pureModeEngineCreate()`).
///
/// The handle used to be a bare `UnsafeMutableRawPointer?` on `AudioEngineBridge`, destroyed by hand
/// at each teardown site. That leaked whenever a bridge was released without a matching `shutdown()`
/// (LEAK #2). Wrapping the handle in a class makes destruction automatic: the last `deinit`
/// guarantees `pureModeEngineDestroy` runs even on the abandonment path.
///
/// ## `@unchecked Sendable` justification
///
/// The wrapper carries a raw C pointer, which is not `Sendable` on its own. It is safe to mark the
/// class `@unchecked Sendable` because the instance is ONLY ever touched under `AudioEngineBridge`'s
/// existing isolation discipline: the field that holds it is written under the bridge's `stateLock`
/// (via `setPureEngine` / `detachPureEngineForTeardown`) and the handle is used only from the serial
/// `engineQueue` / `configChangeQueue` or borrowed under `stateLock` (`withPureEngine`). No two
/// domains touch the same instance without that discipline, so the compiler-invisible confinement
/// holds. The wrapper adds no state of its own beyond the immutable `handle`.
///
/// ## `deinit` is a BACKSTOP, not the primary teardown
///
/// The controlled teardown path (`detachPureEngineForTeardown` → `stop()` → drop on `engineQueue`,
/// OUTSIDE `stateLock`) is what normally relinquishes ownership: it nils the bridge's field under
/// the lock and returns THIS wrapper so the caller drops it in a controlled scope, keeping the slow
/// HAL teardown (`pureModeEngineDestroy` releases hog mode + restores the device nominal rate) off
/// the lock. By the time an ownerless `deinit` runs, that explicit teardown must already have
/// happened; `deinit` only exists to close the leak on the abandonment path (a bridge released
/// without `shutdown()`). `pureModeEngineDestroy` is NULL-safe + idempotent, so a wrapper that was
/// already `stop()`'d and detached destroys cleanly here.
final class PureModeSession: @unchecked Sendable {
    /// The opaque Pure-Mode engine handle. Immutable for the wrapper's lifetime, so reading it
    /// (e.g. the raw pointer captured by callers before a C-ABI call) never races the owner.
    let handle: UnsafeMutableRawPointer

    /// Create + own a Pure-Mode engine. Returns `nil` when `pureModeEngineCreate` fails to allocate,
    /// so the field stays `nil` and the caller can fall back to the Enhanced path.
    init?() {
        guard let handle = pureModeEngineCreate() else { return nil }
        self.handle = handle
    }

    /// Stop the engine (control-plane): releases hog mode + restores the device nominal rate. Called
    /// by the controlled teardown BEFORE the wrapper is dropped, so `deinit`'s destroy joins an
    /// already-stopped engine. Idempotent + NULL-safe on the C++ side.
    func stop() {
        pureModeEngineStop(handle)
    }

    deinit {
        // BACKSTOP (see the type doc): the controlled teardown normally stops the engine and drops
        // this wrapper on engineQueue outside stateLock. Destroy here is NULL-safe + idempotent.
        pureModeEngineDestroy(handle)
    }
}
