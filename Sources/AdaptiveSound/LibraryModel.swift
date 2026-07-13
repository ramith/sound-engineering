import Foundation
import LibraryScan
import LibraryStore

// MARK: - LibraryModel (S3 F5 — extracted from AudioViewModel)

/// Owns the persistent-library subsystem: the store, folder scans, the metadata-enrichment pass,
/// the live FSEvents reconcile, and the NSWorkspace volume monitor. A `@MainActor @Observable`
/// PEER of `AudioViewModel` (and `EQViewModel`) — NOT a sub-object of it. Extracted from
/// `AudioViewModel` so the library concern is independently testable and file-cohesive (S3 F5;
/// the @Observable "over-invalidation" argument for splitting is false — @Observable tracks
/// per-keypath — so the real payoff is boundary/testability, per the-fool's steer).
///
/// ## Boundaries
/// - Depends on NOTHING in the audio/engine layer (no `AudioViewModel` reference), so it can be
///   built and driven headless in tests.
/// - Errors are surfaced through the `onError` hook (wired by the composition root to the shell
///   error banner), mirroring the existing `AudioViewModel.onEngineReady` seam — this is what
///   keeps LibraryModel free of a back-reference to the audio VM.
/// - The single audio→library edge is the play-count write-back: `AudioViewModel` holds a
///   (non-owning) `library` reference and reads `library.store` in `countPlayCompletion`. The play
///   VERBS (playNow / playNext / appendToQueue) stay on `AudioViewModel`; `LibraryBrowseModel`
///   depends on BOTH peers and routes reads here and plays there.
///
/// ## Lifecycle
/// The async store build is kicked from `init` (design §7); teardown (`shutdown()`) is awaited by
/// the app-lifecycle owner (`AppDelegate`) BEFORE the engine teardown, so no scan/reconcile writes
/// to the store while the C audio handles are being freed (the P2-C ordering, preserved from the
/// pre-F5 single-model shutdown).
@MainActor
@Observable
final class LibraryModel {
    /// Surfaces a library failure (scan / metadata / reconcile / remove) to the shell error
    /// banner. Wired by the composition root to `AudioViewModel.errorMessage`; `nil` in tests.
    /// Set + invoked on the main actor (`@MainActor` isolation), so no `@Sendable` is required —
    /// the same contract as `AudioViewModel.onEngineReady`.
    var onError: ((String) -> Void)?

    /// Fired once, on the main actor, when the persistent store finishes construction and `store`
    /// is non-nil (S10.2 2c). Wired by the composition root to `AudioViewModel.hydrateQueueOnLaunch`
    /// so the queue restores from the "current" playlist as soon as the store is available; `nil`
    /// in tests. Same set-and-invoke-on-`@MainActor` contract as `onError`.
    var onStoreReady: (() -> Void)?

    // MARK: - Library Store + Scan State (S8.2b)

    /// The persistent library store (S8.1). Constructed off-main at init from
    /// `LibraryStore.defaultStoreURL()`. `nil` until construction completes (or if it
    /// failed — the app still runs; the queue is unaffected). The browse UI's source of
    /// truth (`LibraryBrowseModel` reads it); a folder scan populates it.
    var store: LibraryStore?

    /// Latest scan progress snapshot (indeterminate count-up), published from the
    /// off-main scan via a `@MainActor` hop. `nil` when no scan is running.
    var scanProgress: ScanProgress?

    /// The outcome of the most recently COMPLETED scan (files seen/skipped, orphans
    /// swept, track ids). `nil` until the first scan finishes.
    var lastScanResult: ScanResult?

    /// Monotonic "browsable library content changed" counter (S9.4). Bumped ONCE each time
    /// the store's browsable facets change: at the tail of a completed metadata pass (which
    /// is what actually creates album/artist rows + links artwork) — and therefore on BOTH
    /// the folder-add scan AND the live FSEvents reconcile, since both funnel through
    /// `runMetadataPass`. Coarse by design (once per pass, NOT per `metadataProgress` tick).
    /// The browse layer reloads its facets when this changes (`LibraryBrowseModel`); without
    /// it a fresh scan's albums never appear until a tab-switch re-runs the grid's load
    /// (review B1 — `lastScanResult` is set BEFORE metadata builds the album rows).
    var libraryRevision = 0

    /// The in-flight scan `Task`, held so a re-trigger can cancel the prior scan
    /// before starting the next (mirrors the folder-monitor debounce). Cancelling it
    /// makes the scanner throw `CancellationError` mid-walk and SKIP its sweep.
    var scanTask: Task<Void, Never>?

    /// The artwork cache (S8.3), built alongside `store` in `makeLibraryStore` from
    /// `LibraryStore.defaultArtworkCacheURL()`. `nil` if the store failed to construct.
    var metadataArtworkCache: ArtworkCache?

    /// Non-nil while a metadata pass is running — a presence signal (`MetadataProgress` no longer
    /// carries counts after the dead-code pass; kept as a re-population seam for an S9.5 progress
    /// bar). Published from the off-main pass via a `@MainActor` hop; `nil` when idle.
    var metadataProgress: MetadataProgress?

    // MARK: - Directory Monitoring (S8.4 — recursive FSEvents LibraryWatcher)

    /// The recursive FSEvents watcher. Replaces the old non-recursive DispatchSource monitor:
    /// it watches the registered store roots and drives the persistent-store reconcile. The queue
    /// is not folder-bound (S9 IA change), so a disk change never rewrites it. Built in
    /// `makeLibraryStore`; live-reconcile wiring lives in `LibraryModel+Reconcile.swift`.
    var libraryWatcher: LibraryWatcher?
    let libraryWatcherQueue = DispatchQueue(label: "com.adaptivesound.library-watcher", qos: .utility)
    /// The store roots the watcher currently covers, for attributing an event path to the root
    /// that must be reconciled.
    var watchedRoots: [WatchedRoot] = []
    /// Per-root reconcile debounce tasks (coalesce a burst → one reconcile ~1 s after the last event).
    var reconcileDebounce: [Int64: Task<Void, Never>] = [:]
    /// Roots with a reconcile in flight, and roots whose reconcile must re-run (a burst arrived
    /// mid-reconcile) — so same-root reconciles never overlap and a late change is not lost.
    var reconcilingRoots: Set<Int64> = []
    var pendingReconcile: Set<Int64> = []

    // MARK: - Reconcile observability (S8.4 slice 5b — coarse state for the S9 browse UI)

    /// True while any root is reconciling — bind for a subtle "updating…" affordance at S9.
    var isReconciling = false
    /// When the last reconcile completed (a freshness indicator).
    var lastReconciledAt: Date?
    /// Last reconcile error message (a quiet inline notice at S9 — never a modal).
    var lastReconcileError: String?
    /// Per-root live state (watching / on-demand-only / paused / catching-up).
    var reconcileState: [Int64: ReconcileState] = [:]
    /// Roots on network volumes: FSEvents can't watch them, so they reconcile on-demand + at launch.
    var networkRoots: [WatchedRoot] = []
    /// NSWorkspace mount/unmount observer tokens (removed in `shutdown()`).
    var volumeMonitorTokens: [any NSObjectProtocol] = []

    init() {
        // Construct the persistent library store off-main (S8.2b). The initializer is async, so —
        // per design §7 — it runs in an init-time Task; failure leaves `store` nil and the audio
        // path (which no longer owns any of this state) fully intact.
        Task { await self.makeLibraryStore() }
    }

    /// Ordered library teardown: stop the FSEvents watcher + NSWorkspace volume monitor and cancel
    /// every in-flight reconcile + scan, so nothing writes to the store after this returns. Awaited
    /// by `AppDelegate.applicationShouldTerminate` BEFORE `AudioViewModel.shutdown()` tears the
    /// engine down (P2-C ordering — the detached scan/reconcile observe per-file cancellation and
    /// skip their sweeps, so the store is quiescent by the time the C audio handles are freed).
    func shutdown() {
        logUX("libraryModel shutdown")
        libraryWatcher?.stop()
        stopVolumeMonitor()
        for task in reconcileDebounce.values {
            task.cancel()
        }
        scanTask?.cancel()
    }

    // MARK: - Helpers

    /// Home-relative (`~/…`) display path for a library log line. Lives here (not on the audio VM)
    /// because the library scan seam is now its only caller.
    static func makeDisplayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let raw = url.path
        if raw.hasPrefix(home) {
            return "~" + raw.dropFirst(home.count)
        }
        return raw
    }
}
