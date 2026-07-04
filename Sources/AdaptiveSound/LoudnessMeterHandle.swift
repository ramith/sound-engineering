import Foundation

// MARK: - LoudnessMeterHandle

/// RAII owner for the opaque BS.1770-5 loudness-meter handle (`void*` from `loudnessMeterCreate()`).
///
/// The handle used to be a bare `UnsafeMutableRawPointer?` on `AudioEngineBridge`, destroyed by hand
/// in `shutdown()` and re-created UNCONDITIONALLY in `allocateAnalysisState`. That leaked the prior
/// meter whenever `initialize()` re-ran without a matching `shutdown()` (LEAK #1), and leaked the
/// live meter whenever a bridge was released without `shutdown()` (LEAK #2). Wrapping the handle in a
/// class makes destruction automatic: the last `deinit` guarantees `loudnessMeterDestroy` runs.
///
/// ## `@unchecked Sendable` justification
///
/// The wrapper carries a raw C pointer, which is not `Sendable` on its own. It is safe to mark the
/// class `@unchecked Sendable` because the instance is ONLY ever touched under `AudioEngineBridge`'s
/// existing isolation discipline: the field that holds it is created + released on the serial
/// `engineQueue` (in `allocateAnalysisState` / the graph teardown), and the RAW `handle` — never the
/// class wrapper — is what the RT mixer tap uses (captured once at tap-install time; see
/// `AudioEngineBridge+Graph.swift`). No two domains touch the same instance without that discipline.
/// The wrapper adds no state of its own beyond the immutable `handle`.
///
/// ## `deinit` is a BACKSTOP, not the primary teardown
///
/// The controlled teardown path drops the wrapper (nils `loudnessMeter`) on `engineQueue` AFTER
/// `removeSpectrumTap()` has run, so no RT tap can still hold the raw handle when `deinit` destroys
/// it. `deinit` only exists to close the leak on the abandonment path (a bridge released without
/// `shutdown()`, where the tap is likewise already gone with the engine). `loudnessMeterDestroy` is
/// NULL-safe, so destroying here is always well-formed.
final class LoudnessMeterHandle: @unchecked Sendable {
    /// The opaque loudness-meter handle. Immutable for the wrapper's lifetime, so the raw pointer the
    /// mixer tap captures once at install time never races the owner.
    let handle: UnsafeMutableRawPointer

    /// Create + own a BS.1770-5 loudness meter for `sampleRate`. Returns `nil` when
    /// `loudnessMeterCreate` fails to allocate, so the field stays `nil` and the tap simply skips the
    /// loudness feed (the spectrum path is unaffected).
    init?(sampleRate: Double) {
        guard let handle = loudnessMeterCreate(sampleRate) else { return nil }
        self.handle = handle
    }

    deinit {
        // BACKSTOP (see the type doc): the controlled teardown drops this wrapper only AFTER
        // removeSpectrumTap(), so no RT tap holds the raw handle here. Destroy is NULL-safe.
        loudnessMeterDestroy(handle)
    }
}
