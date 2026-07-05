import AVFoundation
import Foundation
import LibraryScan
import LibraryStore

// MARK: - AudioViewModel

// AudioDeviceModel is defined in Models/AudioDeviceModel.swift.

@MainActor
@Observable
final class AudioViewModel {
    var isEngineReady = false
    /// Re-entrant `initialize()` guard. `true` from the moment an init is kicked off
    /// (`initializeEngine()` / `retryInitialization()`) until its `Task` finishes (success OR
    /// failure). A second init while one is in-flight would race the retry's teardown over the
    /// same ARC class refs (`avEngine` / `loudnessMeter` / `pureEngine`) → retain-count corruption.
    /// Internal (NOT private) so the `+Lifecycle` / `+Devices` extensions (separate files) can
    /// read/write it; `@MainActor` isolation makes the flag check/set race-free. Not UI-bound.
    var isInitializing = false
    var isPlaying = false
    /// Selected top-level tab. Owned here (not in `ContentView` `@State`) so deep views — e.g.
    /// a double-click on the Now Playing spectrum — can navigate without binding-plumbing.
    var selectedTab: TabSelection = .nowPlaying {
        didSet { logUX("tab → \(selectedTab.rawValue)") }
    }

    /// Live playhead position in seconds (polled at the spectrum-timer rate).
    var playbackPosition: Double = 0
    /// Resume point for a position-preserving Pause (D2 / UI-3): set by `pause()` to the playhead
    /// at the moment of pausing, consumed + cleared by `play()` to resume from there via a seek.
    /// `nil` means "not paused" — any explicit new-track action (playTrack/next/previous/stop)
    /// clears it. Internal (not `@Observable`-bound to UI); it only gates the resume logic.
    var pausedResumePosition: Double?
    /// Duration of the currently loaded file in seconds. Computed from `AVAudioFile`
    /// after `startPlayback()` resolves the URL, so it is accurate for M4A files where
    /// `AudioFile.durationSeconds` (from the metadata scan) can read 0.
    var duration: Double = 0
    /// Live BS.1770-5 loudness readout for the meters (polled at the timer rate).
    var loudness: LoudnessSnapshot = .unmeasured
    var errorMessage: String?
    var selectedDevice: AudioDeviceModel?
    var availableDevices: [AudioDeviceModel] = []
    var sampleRate: UInt32 = 0
    var bufferFrameSize: UInt32 = 0
    /// User intent: whether to attempt the bit-perfect Pure HAL path on next playback start.
    /// Pure is mutually exclusive with DSP/EQ by construction (the bit-perfect stream is
    /// untouched). Setting this to `true` does NOT immediately affect running playback —
    /// it takes effect on the next `startPlayback()` call.
    var pureModeEnabled: Bool = false {
        didSet { logUX("pureMode → \(pureModeEnabled)") }
    }

    /// When a new output device connects mid-playback: `true` (default) keeps playback on the
    /// currently-selected device (app-authoritative — you switch deliberately in the picker);
    /// `false` follows the newly-connected device. Pushed to the engine, which acts on it when the
    /// device set changes.
    var pinPlaybackToSelectedDevice: Bool = true {
        didSet {
            engine.setPinPlaybackToSelectedDevice(pinPlaybackToSelectedDevice)
            logUX("pinPlaybackToSelectedDevice → \(pinPlaybackToSelectedDevice)")
        }
    }

    /// Live signal-path snapshot: which path is active, achieved rate, bit depth, etc.
    /// Updated at 20 Hz in `tickSpectrum()`.
    var signalPath: SignalPathInfo = .init()

    /// Convenience derived property: `true` when the Pure HAL path is actually rendering.
    var pureModeEngaged: Bool {
        signalPath.path == .pure
    }

    // MARK: - Reimagine Intensity (QW-A)

    /// Wet/dry blend for all DSP enhancement stages (EQ, clarity, crossfeed).
    /// 0.0 = bit-perfect bypass; 1.0 = full blend. Default 0.20.
    /// The slider binds this in 0...1, so the stored value is always in range; the engine call
    /// is clamped defensively with a LOCAL — NEVER re-assign `intensity` inside its own `didSet`
    /// (under @Observable a self-assignment re-fires the setter → infinite recursion → crash).
    /// Ops dispatched via `+IntensityControl`.
    var intensity: Float = 0.20 {
        didSet {
            let clamped = max(0, min(1, intensity))
            logUX("intensity → \(Int(clamped * 100)) %")
            Task { engine.publishIntensity(clamped) }
        }
    }

    // MARK: - Crossfeed (QW-C)

    /// Whether the headphone crossfeed stage is active. Auto-disabled on switch to
    /// a non-headphone device (see `AudioViewModel+Devices.swift`).
    var crossfeedEnabled: Bool = false {
        didSet {
            logUX("crossfeed → \(crossfeedEnabled ? "on" : "off") [\(crossfeedStrength.displayName)]")
            Task { await engine.publishCrossfeed(enabled: crossfeedEnabled, strength: crossfeedStrength) }
        }
    }

    /// Crossfeed strength preset. Changes take effect immediately when crossfeed is on.
    var crossfeedStrength: CrossfeedStrength = .defaultStrength {
        didSet {
            guard crossfeedEnabled else { return }
            logUX("crossfeed strength → \(crossfeedStrength.displayName)")
            Task { await engine.publishCrossfeed(enabled: true, strength: crossfeedStrength) }
        }
    }

    /// `true` when the selected output device is a headphone-class device (wireless or USB).
    ///
    /// Note: USB also matches USB audio interfaces connected to monitor speakers — a known
    /// heuristic false-positive. Precise detection requires `kAudioDevicePropertyTransportType`
    /// / DataSource queries (tracked for a future story). On a non-headphone device with
    /// crossfeed accidentally enabled, the only audible consequence is a mild centre-image
    /// change from the LPF cross path — benign and fully reversible by toggling crossfeed off.
    var deviceIsHeadphones: Bool {
        switch selectedDevice?.type {
        case .wireless, .usb: true
        default: false
        }
    }

    // MARK: - Master Gain

    /// Last volume value logged (formatted), so a slider DRAG coalesces to one line per distinct
    /// displayed value instead of ~25 identical lines.
    private var lastVolLogged: String = ""

    var masterGain: Float = 0.7 {
        didSet {
            let volStr = secs(Double(masterGain))
            if volStr != lastVolLogged {
                logUX("vol → \(volStr) (\(pureModeEngaged ? "Pure HW" : "Enhanced"))")
                lastVolLogged = volStr
            }
            setParameter(masterGainParameterID, value: masterGain)
        }
    }

    // MARK: - Spectrum Analyzer State

    /// 88 normalised bar heights in [0, 1] for the spectrum display.
    /// Updated on the main thread at ~20 Hz by `spectrumTimer`.
    /// Index 0 = lowest frequency band; index 87 = highest.
    var spectrumBars: [Float] = .init(repeating: 0, count: SpectrumConstants.displayBarCount)

    /// Retained so we can invalidate on shutdown.
    /// Internal (not private) so `AudioViewModel+SpectrumTimer.swift` can read and invalidate it.
    var spectrumTimer: Timer?

    /// Drives TRANSPORT polling (playhead, gapless auto-advance, device-loss) at ~20 Hz — a
    /// SEPARATE timer from `spectrumTimer` so auto-advance never shares fate with the spectrum
    /// visualizer (VM-3). The visualizer timer may one day be gated on view visibility; transport
    /// must keep polling whenever the engine is alive, so it has its own always-on timer.
    var transportTimer: Timer?

    /// Scratch array — reused each tick, never reallocated.
    /// Internal (not private) so `AudioViewModel+SpectrumTimer.swift` can write into it.
    var spectrumScratch: [Float] = .init(repeating: 0, count: SpectrumConstants.bandCount)

    // MARK: - Playlist State

    var musicFolderURL: URL? {
        didSet {
            // S8.4: the recursive FSEvents `LibraryWatcher` replaces the old non-recursive
            // DispatchSource monitor. Re-point it at the current folder set so a newly chosen
            // folder is watched promptly (for both the visible playlist refresh and the store
            // reconcile). refreshWatchedRoots is async, so hop through a Task.
            Task { @MainActor [weak self] in await self?.refreshWatchedRoots() }
        }
    }

    var playlist: [AudioFile] = []
    var folderPathDisplay: String = ""
    /// Track selection (does NOT auto-play). Selection and playback are separate.
    /// Use playTrack() or startPlayback() to actually play the selected track.
    var selectedTrackIndex: Int?

    // MARK: - Library Store + Scan State (S8.2b — additive)

    /// The persistent library store (S8.1). Constructed off-main at init from
    /// `LibraryStore.defaultStoreURL()`. `nil` until construction completes (or if it
    /// failed — the app still runs; the in-memory playlist is unaffected). ADDITIVE:
    /// the store populates in PARALLEL with `loadMusicFolder`; the UI's source swaps
    /// to store-reads at S9.
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

    /// Latest metadata-pass progress (determinate — the pass knows its total up front),
    /// published from the off-main pass via a `@MainActor` hop. `nil` when idle.
    var metadataProgress: MetadataProgress?

    // MARK: - Directory Monitoring (S8.4 — recursive FSEvents LibraryWatcher)

    /// The recursive FSEvents watcher. Replaces the old non-recursive DispatchSource monitor:
    /// it watches the registered store roots (+ the visible folder) and drives BOTH the store
    /// reconcile AND the in-memory playlist refresh. Built in `makeLibraryStore`. Live-reconcile
    /// wiring lives in `AudioViewModel+Reconcile.swift`.
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
    /// Debounce for the visible in-memory playlist refresh (replaces the old monitor's reload).
    var playlistRefreshTask: Task<Void, Never>?

    // MARK: - Reconcile observability (S8.4 slice 5b — coarse state for the future S9 browse UI)

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

    // MARK: - Playback Modes (WinAmp Style)

    /// Shuffle mode: when enabled, plays tracks in random order
    var shuffleEnabled = false

    /// Repeat mode: 0 = no repeat, 1 = repeat all, 2 = repeat one
    var repeatMode: Int = 0

    // MARK: - Gapless / Auto-Advance State

    /// Last observed `trackTransitionCount()` value. An increase means the on-deck
    /// track has become the current track (a gapless seam just completed).
    /// Internal (not private) so the spectrum-timer and auto-advance extensions can read/write it.
    var lastTransitionCount: UInt64 = 0

    /// Playlist index of the track currently on deck (supplied via `setNextTrack`).
    /// `nil` means no track is queued (end of playlist, repeat-one handled inline,
    /// or playback has not started yet).
    /// Internal (not private) so the spectrum-timer and auto-advance extensions can read/write it.
    var pendingNextIndex: Int?

    let engine: any AudioPlaybackEngine
    private let masterGainParameterID: UInt32 = 0

    init(engine: any AudioPlaybackEngine = AudioEngineBridge()) {
        self.engine = engine
        // Construct the persistent library store off-main (S8.2b, additive). The
        // initializer is async, so — per design §7 — it runs in an init-time Task;
        // failure leaves `store` nil and the in-memory playlist path fully intact.
        Task { await self.makeLibraryStore() }
    }

    // Engine lifecycle (initializeEngine, shutdown, stopPlayback, performStop) lives in
    // AudioViewModel+Lifecycle.swift.

    // Spectrum timer + tickSpectrum live in AudioViewModel+SpectrumTimer.swift.

    // Device management (selectDevice, refreshDevices, retryInitialization) lives in AudioViewModel+Devices.swift.

    // Playback control (startPlayback / seek / gapless priming) lives in
    // AudioViewModel+Playback.swift.

    // MARK: - Parameter Control

    func setParameter(_ id: UInt32, value: Float) {
        Task {
            do {
                try await engine.setParameter(id, value: value)
            } catch {
                errorMessage = "Parameter update failed: \(error.localizedDescription)"
            }
        }
    }

    /// Publish the 31-band EQ gain vector (dB) to the live DSP AU. Synchronous + off-RT;
    /// called once per EQ change by `EQViewModel.dispatchAllBands()`.
    func publishEQGains(_ gainsDb: [Float]) {
        engine.publishEQGains(gainsDb)
    }

    // MARK: - Monitoring (per-channel before/after)

    /// Channels available to monitor (= the graph's channel count). 0 until the engine is ready.
    var monitorChannelCount: Int {
        engine.monitorChannelCount
    }

    /// Read one tap point + channel's latest band magnitudes into `out` (polled by the
    /// Monitoring tab while it is visible).
    @discardableResult
    func readMonitorBands(_ tap: MonitorTap, channel: Int, into out: inout [Float]) -> Bool {
        engine.readMonitorBands(tap, channel: channel, into: &out)
    }

    // MARK: - Folder Loading & Monitoring

    /// Enumerate all audio files under `folderURL` recursively and update `playlist`.
    func loadMusicFolder(_ folderURL: URL) async {
        logUX("loadMusicFolder: '\(Self.makeDisplayPath(folderURL))'")
        let displayPath = Self.makeDisplayPath(folderURL)
        if folderPathDisplay != displayPath { folderPathDisplay = displayPath }

        // Enumerate FIRST, then swap the result in atomically. Do NOT clear `playlist` to []
        // before the async scan — that empties the list for the scan's duration, so every
        // folder-monitor re-scan flashed empty→full (a window flicker, worst during a copy burst
        // that fires repeated FSEvents). Keeping the current list visible until the new one is
        // ready, plus stable AudioFile.id, makes the update diff cleanly with no flash.
        let files = await Task.detached(priority: .userInitiated) {
            AudioFileEnumerator.enumerate(folderURL: folderURL)
        }.value

        playlist = files
        logUX("loadMusicFolder: loaded \(files.count) file(s) from '\(displayPath)'")
    }

    // MARK: - Helpers

    static func makeDisplayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let raw = url.path
        if raw.hasPrefix(home) {
            return "~" + raw.dropFirst(home.count)
        }
        return raw
    }
}

// Engine lifecycle (initializeEngine, shutdown, stopPlayback, performStop) lives in
// AudioViewModel+Lifecycle.swift.
// Live folder-watch + reconcile (FSEvents) lives in AudioViewModel+Reconcile.swift.
// Playlist editing (movePlaylistItems, removeTrack, clearPlaylist, toggleShuffle, cycleRepeatMode)
// lives in AudioViewModel+Playlist.swift.
// Gapless/auto-advance (handleTrackTransition, computeNextIndex) lives in AudioViewModel+AutoAdvance.swift.
