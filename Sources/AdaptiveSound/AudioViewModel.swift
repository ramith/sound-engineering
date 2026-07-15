import Foundation
import PlaybackQueueKit

// MARK: - AudioViewModel

// AudioDeviceModel is defined in Models/AudioDeviceModel.swift.

@MainActor
@Observable
final class AudioViewModel {
    var isEngineReady = false
    /// Lifecycle hook fired ONCE each time the engine transitions to ready (the single
    /// `isEngineReady = true` spot in `initializeEngine`, which also covers device-loss
    /// `retryInitialization` — it re-enters `initializeEngine`). Lets a collaborator that
    /// depends on the live AU act the moment it comes up, even headless (its tab closed) —
    /// e.g. `EQViewModel` re-dispatching its restored "last setting" curve. Analogous to the
    /// engine's `onOutputDevicesChanged`; this is NOT a device-recall callback. Set and
    /// invoked on the main actor (`@MainActor` isolation), so no `@Sendable` is required.
    var onEngineReady: (() -> Void)?

    /// Fired (on the main actor) when Now-Playing–relevant state changes — track / play-pause /
    /// seek / resolved-duration — so the composition-root-wired `NowPlayingController` refreshes
    /// Control Center + the Now Playing widget (S10.4). One-directional hook (mirrors
    /// `onEngineReady`/`onError`); `nil` in tests. NEVER fired from the 20 Hz tick.
    var onNowPlayingRefresh: (() -> Void)?
    /// Re-entrant `initialize()` guard. `true` from the moment an init is kicked off
    /// (`initializeEngine()` / `retryInitialization()`) until its `Task` finishes (success OR
    /// failure). A second init while one is in-flight would race the retry's teardown over the
    /// same ARC class refs (`avEngine` / `loudnessMeter` / `pureEngine`) → retain-count corruption.
    /// Internal (NOT private) so the `+Lifecycle` / `+Devices` extensions (separate files) can
    /// read/write it; `@MainActor` isolation makes the flag check/set race-free. Not UI-bound.
    var isInitializing = false
    var isPlaying = false {
        didSet {
            // Every play/pause/stop/end-of-queue/device-loss transition → refresh Now Playing
            // (rate + elapsed + playbackState). Guarded on change; not self-assignment (S10.4).
            if isPlaying != oldValue { onNowPlayingRefresh?() }
        }
    }

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
            // Synchronous, off-RT control-plane call (borrows the AU under the leaf lock). No Task:
            // publishIntensity has no suspension point, and an unstructured Task only risks applying
            // an earlier value after a later one under rapid slider drags (S3 finding F4).
            engine.publishIntensity(clamped)
        }
    }

    // MARK: - Crossfeed (QW-C)

    /// Whether the headphone crossfeed stage is active. Auto-disabled on switch to
    /// a non-headphone device (see `AudioViewModel+Devices.swift`).
    var crossfeedEnabled: Bool = false {
        didSet {
            logUX("crossfeed → \(crossfeedEnabled ? "on" : "off") [\(crossfeedStrength.displayName)]")
            engine.publishCrossfeed(enabled: crossfeedEnabled, strength: crossfeedStrength)
        }
    }

    /// Crossfeed strength preset. Changes take effect immediately when crossfeed is on.
    var crossfeedStrength: CrossfeedStrength = .defaultStrength {
        didSet {
            guard crossfeedEnabled else { return }
            logUX("crossfeed strength → \(crossfeedStrength.displayName)")
            engine.publishCrossfeed(enabled: true, strength: crossfeedStrength)
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

    /// The play queue (S10.2). Each slot is a `QueueItem` (stable UUID identity), so the same
    /// track may appear more than once. `selectedTrackIndex`/`pendingNextIndex` are plain `Int`
    /// offsets into this array (the engine's index math is unchanged).
    var queue: [QueueItem] = []

    /// Read-only view of the queue as plain `AudioFile`s, for cold display consumers that don't
    /// need slot identity (menu-bar, now-playing widget, transport). Queue *edits* go through the
    /// `queue`-mutating verbs; this shim just keeps the many read sites working unchanged.
    var playlist: [AudioFile] {
        queue.map(\.file)
    }

    /// Debounce handle for the queue→"current"-playlist snapshot mirror (S10.2, `+QueueMirror`).
    /// A queue edit schedules a mirror; a newer edit cancels the pending one so only the settled
    /// queue is written. Advance does NOT mirror (rows don't change). Not UI-bound.
    var queueMirrorTask: Task<Void, Never>?

    /// True once the user has edited the queue this session (any play verb / reorder / remove /
    /// clear — set in `scheduleQueueMirror`). Guards launch hydration: if the user acted BEFORE
    /// the store became ready, their queue wins and the persisted one is NOT restored over it
    /// (the hydration "superseded" state). Not UI-bound.
    var hasUserEditedQueue = false
    /// One-shot guard so launch hydration (`+QueueHydration`) runs at most once. Not UI-bound.
    var queueHydrated = false

    /// The ≥60%-heard play-through detector (S10.6). Pure state (PlaybackQueueKit); the transport
    /// tick feeds it monotonic playback-time deltas. When it crosses the threshold the current
    /// track's play is recorded (once per play-through). Not UI-bound.
    var playThroughTracker = PlayThroughTracker()
    /// Monotonic reference (suspend-stopping uptime nanos) for the play-through accrual — advanced
    /// EVERY tick, consumed only while playing (FIX-3), so a pause/stall/seek never mis-accrues.
    /// `nil` reseeds on the next tick. Not UI-bound.
    var lastPlayThroughMonoNanos: UInt64?
    /// Bumped (on the main actor) AFTER a play-count write commits (S10.6 R4) so the Recently-Played
    /// view can reload without racing the detached store write. UI-bound.
    var playCountRevision = 0

    /// Track selection (does NOT auto-play). Selection and playback are separate.
    /// Use playTrack() or startPlayback() to actually play the selected track.
    var selectedTrackIndex: Int? {
        didSet {
            // Selecting a DIFFERENT track invalidates any position-preserving resume point (D2):
            // the paused offset belonged to the previously-selected track, so it must not seek the
            // newly-selected one. Centralizes the "explicit new-track action clears the resume
            // point" contract that arrow-key reselection previously skipped — and which S10.2 2c's
            // launch RESTORE-PAUSED would otherwise let leak onto whatever the user arrows to
            // before pressing Play (QA break-it #1). A same-value re-assignment (re-selecting the
            // paused track) preserves the resume point. Not self-assignment → no @Observable
            // didSet recursion.
            if selectedTrackIndex != oldValue {
                pausedResumePosition = nil
                onNowPlayingRefresh?() // track change (incl. gapless advance) → refresh Now Playing (S10.4)
            }
        }
    }

    /// Whether a manual Next would advance (honors shuffle / repeat / end-of-queue) — the single
    /// source of truth with `nextTrack()`, used for the remote command's `.isEnabled` (S10.4).
    var canGoNext: Bool {
        guard let current = selectedTrackIndex else { return !queue.isEmpty }
        return computeNextIndex(current: current, playlistCount: queue.count, manualSkip: true) != nil
    }

    /// Whether a manual Previous would move — mirrors `previousTrack()`.
    var canGoPrevious: Bool {
        guard let current = selectedTrackIndex else { return false }
        return computePreviousIndex(current: current, playlistCount: queue.count) != nil
    }

    // MARK: - Library (S3 F5 — extracted to the LibraryModel peer)

    /// Non-owning back-reference to the library subsystem (a `@MainActor @Observable` PEER, owned by
    /// the composition root and injected here after construction). This is the ONLY audio→library
    /// edge: `countPlayCompletion` reads `library?.store` to write play counts. All library STATE
    /// (store, scan / reconcile / FSEvents watcher / volume monitor) now lives on `LibraryModel`;
    /// the browse UI reads it there. `weak` because the app's `@State` owns it for the whole process
    /// lifetime — it is still alive at every use — and to make the non-ownership explicit.
    weak var library: LibraryModel?

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
}

// Engine lifecycle (initializeEngine, shutdown, stopPlayback, performStop) lives in
// AudioViewModel+Lifecycle.swift.
// The persistent-library subsystem (store / scan / metadata / FSEvents reconcile / volume monitor)
// lives on the LibraryModel peer (LibraryModel.swift + LibraryModel+*), NOT here (S3 F5).
// Playlist editing (movePlaylistItems, removeTrack, clearPlaylist, toggleShuffle, cycleRepeatMode)
// lives in AudioViewModel+Playlist.swift.
// Gapless/auto-advance (handleTrackTransition, computeNextIndex) lives in AudioViewModel+AutoAdvance.swift.
