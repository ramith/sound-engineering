import DesignTokenKit
import EQEditKit
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

    /// Fired (on the main actor) when the output CHANGES IDENTITY — `selectedDevice` moves to a
    /// device with another UID, appears (launch) or goes away — with the new output's key (`nil` =
    /// none). Never for a re-read of the same output (a rate or buffer change; `refreshDevices`
    /// re-selecting it). One-directional hook like `onEngineReady`, so whatever keys state per
    /// output follows it with the window closed too. `nil` in tests.
    var onOutputIdentityChanged: ((EQOutputKey?) -> Void)?
    /// Re-entrant `initialize()` guard. `true` from the moment an init is kicked off
    /// (`initializeEngine()` / `retryInitialization()`) until its `Task` finishes (success OR
    /// failure). A second init while one is in-flight would race the retry's teardown over the
    /// same ARC class refs (the engine, the loudness meter, the Pure session) → retain-count corruption.
    /// Internal (NOT private) so the `+Lifecycle` / `+Devices` extensions (separate files) can
    /// read/write it; `@MainActor` isolation makes the flag check/set race-free. Not UI-bound.
    var isInitializing = false
    var isPlaying = false {
        didSet {
            // Every play/pause/stop/end-of-queue/device-loss transition → refresh Now Playing
            // (rate + elapsed + playbackState). Guarded on change; not self-assignment (S10.4).
            if isPlaying != oldValue {
                onNowPlayingRefresh?()
            }
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
    /// at the moment of pausing, moved by a scrub while paused, consumed + cleared by `play()` to
    /// resume from there via a seek. It belongs to the paused song's queue SLOT, not its row
    /// (S10.8 G): a queue edit that shifts the row keeps it. Any explicit new-track action
    /// (playTrack/next/previous/stop) clears it. Read it through `pausedResumePosition`.
    var resumePoint: ResumePoint<UUID>?
    /// The number of the latest transport request (start, seek, stop) sent to the engine. The tick
    /// ignores engine samples older than it (`TransportSnapshot.isCurrent(for:)`): until the engine
    /// reaches the request — it can queue behind a slow device start — they describe the playback
    /// the request replaces. Not UI-bound.
    @ObservationIgnored var transportEpoch: UInt64 = 0
    /// The number of the latest stop or pause request (`nextStopEpoch()`). A start numbered before
    /// it was abandoned while it ran, so its `Task` neither primes the queue nor marks playing over
    /// the stop (the UI showed Playing over a stopped engine — S10.8 G review). Not UI-bound.
    @ObservationIgnored var transportStopEpoch: UInt64 = 0
    /// The playback the on-deck requests belong to (`OnDeckTicket.session`): the epoch of the newest
    /// start. The engine applies only the newest request of the playback it is in (council D41).
    /// Not UI-bound.
    @ObservationIgnored var onDeckSession: UInt64 = 0
    /// The number of the latest on-deck request (`OnDeckTicket.sequence`, `nextOnDeckTicket()`):
    /// never reset, so the engine tells the newest request apart whatever order they reach it in.
    /// Not UI-bound.
    @ObservationIgnored var onDeckSequence: UInt64 = 0
    /// Duration of the currently loaded file in seconds. Computed from `AVAudioFile`
    /// after `startPlayback()` resolves the URL, so it is accurate for M4A files where
    /// `AudioFile.durationSeconds` (from the metadata scan) can read 0.
    var duration: Double = 0
    /// Live BS.1770-5 loudness readout for the meters (polled at the timer rate).
    var loudness: LoudnessSnapshot = .unmeasured
    var errorMessage: String?
    /// The output the app plays on. Moving it to another output (by UID) fires
    /// `onOutputIdentityChanged`; re-reading the same output does not.
    var selectedDevice: AudioDeviceModel? {
        didSet {
            announceOutputIdentityChange(from: oldValue)
            publishOutputTransport()
        }
    }

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

    /// "Keep playback on this device". `true` (default): the device the user picks wins over the
    /// system default (a device that connects, or Control Center ▸ Sound, doesn't move playback),
    /// and playback goes back to it when it reconnects; until they pick one (in the menu, or by
    /// turning this on), the app follows the default. `false`: the app follows the system default.
    /// Pushed to the engine, whose output rule (`OutputDevicePolicy`) acts on it; a lost device
    /// pauses either way.
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

    /// Reimagine's wet/dry blend of the coloration stages (clarity, spatial, crossfeed). The EQ
    /// sits AHEAD of the blend and plays at every Intensity (Sprint EQ decision 25): 0.0 =
    /// Reimagine off — the EQ alone, bit-perfect when the EQ is Off or flat; 1.0 = full blend.
    /// Default 0.20, published at engine-ready (`publishPlaybackIntents()`).
    /// The slider binds this in 0...1, so the stored value is always in range; the engine call
    /// is clamped defensively with a LOCAL — NEVER re-assign `intensity` inside its own `didSet`
    /// (under @Observable a self-assignment re-fires the setter → infinite recursion → crash).
    /// Ops dispatched via `+IntensityControl`.
    var intensity: Float = 0.20 {
        didSet {
            logUX("intensity → \(Int(max(0, min(1, intensity)) * 100)) %")
            publishIntensity()
        }
    }

    // MARK: - Crossfeed (QW-C)

    /// Whether the headphone crossfeed stage is active. Auto-disabled on switch to
    /// a non-headphone device (see `AudioViewModel+Devices.swift`).
    var crossfeedEnabled: Bool = false {
        didSet {
            logUX("crossfeed → \(crossfeedEnabled ? "on" : "off") [\(crossfeedStrength.displayName)]")
            publishCrossfeed()
        }
    }

    /// Crossfeed strength preset. Changes take effect immediately when crossfeed is on.
    var crossfeedStrength: CrossfeedStrength = .defaultStrength {
        didSet {
            guard crossfeedEnabled else { return }
            logUX("crossfeed strength → \(crossfeedStrength.displayName)")
            publishCrossfeed()
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

    /// Last Master Gain readout logged, so a slider DRAG coalesces to one line per distinct displayed
    /// level instead of ~25 identical lines (`logMasterGain`).
    var lastMasterGainLogged: String = ""

    /// Master Gain: the app's own level in dB (S10.8 G; founder decision 2026-10-12, "Show the real
    /// level"). Turn-down only — 0 dB, unity, at the top and by default (what plays at launch);
    /// `MasterGainLaw` maps it to the slider and to the player's linear gain, and the inspector reads
    /// it back as it plays. Published on every change and at engine-ready. On Pure the bit-perfect
    /// stream is never scaled: the slider shows and sets the output device's own volume instead
    /// (`+MasterGain`). Not kept across launches (a post-R1 item).
    var masterGain: Float = MasterGainLaw.unity {
        didSet {
            logMasterGain("master gain → \(MasterGainLaw.text(masterGain))")
            publishMasterGain()
        }
    }

    /// The last level the user asked of the output device while Pure plays — so the knob holds it
    /// until the device answers, and while the device still reads that answer (`masterGainControl`).
    var deviceVolumeAsked: Float?

    // MARK: - Spectrum Analyzer State

    /// 88 normalised bar heights in [0, 1] for the spectrum display.
    /// Updated on the main thread at ~20 Hz by `spectrumTimer`.
    /// Index 0 = lowest frequency band; index 87 = highest.
    var spectrumBars: [Float] = .init(repeating: 0, count: SpectrumConstants.displayBarCount)
    /// Peak-hold caps above the bars (S10.7 PR 3): published beside `spectrumBars` from the
    /// same 20 Hz tick so `@Observable` coalesces both into ONE view invalidation. Values
    /// resolve in `DesignTokenKit.PeakHoldTracker` (pure, time-fed — freeze-on-pause is
    /// structural: no feed, no decay).
    var peakCaps: [Float] = .init(repeating: 0, count: SpectrumConstants.displayBarCount)
    var peakTracker = PeakHoldTracker(bandCount: SpectrumConstants.displayBarCount)

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
    var queue: [QueueItem] = [] {
        // A size change can flip `canGoNext`/`canGoPrevious` (the remote-command enable state)
        // without touching `selectedTrackIndex`/`isPlaying` — e.g. append/remove-after-current
        // while paused (S10.4 QA #1). Refresh so Control Center's enable flags don't go stale. A
        // pure reorder keeps the count and re-anchors `selectedTrackIndex` (whose didSet fires), so
        // count is the right, non-spammy trigger.
        didSet {
            if queue.count != oldValue.count {
                onNowPlayingRefresh?()
            }
        }
    }

    /// Read-only view of the queue as plain `AudioFile`s, for cold display consumers that don't
    /// need slot identity (menu-bar, now-playing widget, transport). Queue *edits* go through the
    /// `queue`-mutating verbs; this shim just keeps the many read sites working unchanged.
    var playlist: [AudioFile] {
        queue.map(\.file)
    }

    /// One-level snapshot of the queue captured just before a destructive "Play (replace queue)"
    /// (S10.3 D-play), so the UI can offer a transient "Restore previous queue" undo. Cleared once
    /// restored; the next undoable replace supersedes it — unless that replace only replaced this
    /// one's untouched queue (`QueueRestorePoint.afterReplace`). Not UI-bound beyond the undo affordance.
    var queueRestorePoint: QueueRestorePoint<QueueItem>?

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
            // Selecting a DIFFERENT slot drops the position-preserving resume point (D2): the paused
            // offset belonged to the previously-selected song, so it must not seek the newly-selected
            // one. Centralizes the "explicit new-track action clears the resume point" contract that
            // arrow-key reselection previously skipped — and which S10.2 2c's launch RESTORE-PAUSED
            // would otherwise let leak onto whatever the user arrows to before pressing Play (QA
            // break-it #1). Compared by SLOT, not row (S10.8 G): removing or moving another row
            // re-anchors the index and keeps the point; removing the paused song slides another slot
            // into the same row and drops it. Not self-assignment → no @Observable didSet recursion.
            if resumePoint != nil, pausedResumePosition == nil {
                resumePoint = nil
            }
            if selectedTrackIndex != oldValue {
                onNowPlayingRefresh?() // track change (incl. gapless advance) → refresh Now Playing (S10.4)
            }
        }
    }

    /// Number the next transport request (see `transportEpoch`). Call it synchronously, before the
    /// request's `Task`, so no tick in between reads the replaced playback as current.
    func nextTransportEpoch() -> UInt64 {
        transportEpoch &+= 1
        return transportEpoch
    }

    /// Number the next STOP or PAUSE request: a transport request (`nextTransportEpoch()`) that
    /// also ends any start still in flight (`transportStopEpoch`).
    func nextStopEpoch() -> UInt64 {
        transportStopEpoch = nextTransportEpoch()
        return transportStopEpoch
    }

    /// Number the next on-deck request: the newest start's playback, and the next place in the
    /// order requests are made. Call it synchronously, in the turn that decides the request.
    func nextOnDeckTicket() -> OnDeckTicket {
        onDeckSequence &+= 1
        return OnDeckTicket(session: onDeckSession, sequence: onDeckSequence)
    }

    /// The queue slot of the selected song (`nil` = none, or an index out of range).
    var selectedSlotID: UUID? {
        selectedTrackIndex.flatMap { $0 >= 0 && $0 < queue.count ? queue[$0].id : nil }
    }

    /// Where Play resumes the selected song: the resume point when it belongs to the selected slot.
    /// `nil` means "not paused" (the scrubber and Now Playing read it as such).
    var pausedResumePosition: Double? {
        resumePoint?.seconds(resuming: selectedSlotID)
    }

    /// Whether a manual Next would advance (honors shuffle / repeat / end-of-queue) — the single
    /// source of truth with `nextTrack()`, used for the remote command's `.isEnabled` (S10.4).
    var canGoNext: Bool {
        // No selection → `nextTrack()` no-ops, so Next must read as disabled too (single source of
        // truth with the verb — S10.4 CG-4; matches `canGoPrevious`).
        guard let current = selectedTrackIndex else { return false }
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

    /// Shuffle mode: when enabled, plays tracks in random order.
    /// didSet: shuffle/repeat flip `canGoNext`/`canGoPrevious`, so refresh the remote-command
    /// enable state (S10.4 QA #1) — else Control Center's Next/Prev stay stale until the next play.
    var shuffleEnabled = false {
        didSet {
            if shuffleEnabled != oldValue {
                onNowPlayingRefresh?()
            }
        }
    }

    /// Repeat mode: 0 = no repeat, 1 = repeat all, 2 = repeat one
    var repeatMode: Int = 0 {
        didSet {
            if repeatMode != oldValue {
                onNowPlayingRefresh?()
            }
        }
    }

    // MARK: - Gapless / Auto-Advance State

    /// Last observed seam count (the snapshot's `transitionCount`). An increase means the on-deck
    /// track has become the current track (a gapless seam just completed).
    /// Internal (not private) so the spectrum-timer and auto-advance extensions can read/write it.
    var lastTransitionCount: UInt64 = 0

    /// Playlist index of the track currently on deck (set with the engine's request by `armOnDeck`).
    /// `nil` means no track is queued (end of playlist, repeat-one handled inline,
    /// or playback has not started yet).
    /// Internal (not private) so the spectrum-timer and auto-advance extensions can read/write it.
    var pendingNextIndex: Int?

    let engine: any AudioPlaybackEngine
    /// Where the now-playing cursor persists (`+QueueHydration`): the launch's
    /// `AppDataLocation.defaults`. The picture-sheet renderer injects its own suite.
    let defaults: UserDefaults

    init(defaults: UserDefaults, engine: any AudioPlaybackEngine = AudioEngineBridge()) {
        self.defaults = defaults
        self.engine = engine
        eqDesignRate = engine.snapshot().eqDesignRate
    }

    // Engine lifecycle (initializeEngine, shutdown, stopPlayback, performStop) lives in
    // AudioViewModel+Lifecycle.swift.

    // Spectrum timer + tickSpectrum live in AudioViewModel+SpectrumTimer.swift.

    // Device management (selectDevice, refreshDevices, retryInitialization) lives in AudioViewModel+Devices.swift.

    // Playback control (startPlayback / seek / gapless priming) lives in
    // AudioViewModel+Playback.swift.

    // MARK: - Parameter Control

    /// Publish the EQ (its 31 points, dB, and whether it plays) to the live DSP AU. Synchronous +
    /// off-RT; called by `EQViewModel.publish()`, the EQ's one dispatch, on every change.
    func publishEQ(points: [Float], isOn: Bool) {
        engine.publishEQ(points: points, isOn: isOn)
    }

    /// The rate the engine designs the EQ at, polled with the other readouts (`pollEngineReadouts`) and
    /// observed: the EQ graph's played curve is designed at it, and redraws when the output's rate moves.
    private(set) var eqDesignRate: Double

    /// Takes the EQ's design rate from the tick's snapshot, writing only on a change (Observation has
    /// no equality gate).
    func refreshEQDesignRate(_ rate: Double) {
        if eqDesignRate != rate {
            eqDesignRate = rate
        }
    }
}

// Engine lifecycle (initializeEngine, shutdown, stopPlayback, performStop) lives in
// AudioViewModel+Lifecycle.swift.
// The persistent-library subsystem (store / scan / metadata / FSEvents reconcile / volume monitor)
// lives on the LibraryModel peer (LibraryModel.swift + LibraryModel+*), NOT here (S3 F5).
// Playlist editing (movePlaylistItems, removeTrack, clearPlaylist, toggleShuffle, cycleRepeatMode)
// lives in AudioViewModel+Playlist.swift.
// Gapless/auto-advance (handleTrackTransition, computeNextIndex) lives in AudioViewModel+AutoAdvance.swift.
