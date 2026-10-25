import EQEditKit
import Foundation
import LibraryBrowseKit
import LibraryScan
import PlaybackQueueKit
import SettingsKit

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
            runTransportTickIfLive()
        }
    }

    /// Selected top-level tab. Owned here (not in `ContentView` `@State`) so deep views — e.g.
    /// a double-click on the Now Playing spectrum — can navigate without binding-plumbing.
    var selectedTab: TabSelection = .nowPlaying {
        didSet { logUX("tab → \(selectedTab.rawValue)") }
    }

    /// Live playhead position in seconds (polled at the transport tick's rate).
    var playbackPosition: Double = 0 {
        didSet {
            let whole = playbackPosition.isFinite ? Int(max(0, playbackPosition)) : 0
            if whole != elapsedSeconds {
                elapsedSeconds = whole
            }
            queuePlayheadMoved(cadenced: true) // kept every few seconds of the song (+QueueMirror)
        }
    }

    /// The playhead in whole seconds — what the scrubber's time and its VoiceOver value show — written
    /// only when the second changes (council C-53, VM-4): the readouts that show it re-evaluate once a
    /// second, not with each of the tick's 20 playhead writes.
    private(set) var elapsedSeconds = 0
    /// Resume point for a position-preserving Pause (D2 / UI-3): set by `pause()` to the playhead
    /// at the moment of pausing, moved by a scrub while paused, consumed + cleared by `play()` to
    /// resume from there via a seek. It belongs to the paused song's queue SLOT, not its row
    /// (S10.8 G): a queue edit that shifts the row keeps it. Any explicit new-track action
    /// (playTrack/next/previous/stop) clears it. Read it through `pausedResumePosition`. When it
    /// moves or goes while nothing plays, the scrubber follows at once (`placePlayhead`): no tick runs
    /// then to carry it over (council C-52).
    var resumePoint: ResumePoint<UUID>? {
        didSet {
            placePlayhead(nil)
            queuePlayheadMoved(cadenced: false) // a pause, a scrub while paused, a stop: kept at once
        }
    }

    /// The number of the latest transport request (start, seek, stop) sent to the engine. The tick
    /// ignores engine samples older than it (`TransportSnapshot.isCurrent(for:)`): until the engine
    /// reaches the request — it can queue behind a slow device start — they describe the playback
    /// the request replaces. Not UI-bound.
    @ObservationIgnored var transportEpoch: UInt64 = 0
    /// The start or the stop (Stop, or Pause) still on its way to the engine: numbered, not finished
    /// (council C-15, `+TransportCommands`). Set in the turn the user asks, so a press while it runs
    /// acts on it — Space during a start pauses it, Next starts the next song, a second Play joins it —
    /// and only the newest one's outcome is applied. `nil`: none; `isPlaying` says what plays. The play
    /// / pause control reads it (`playIntent`). The transport tick runs while one is on its way.
    var transportCommand: TransportCommand? {
        didSet { runTransportTickIfLive() }
    }

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
            followHeadphones(from: oldValue)
        }
    }

    var availableDevices: [AudioDeviceModel] = []
    var sampleRate: UInt32 = 0
    var bufferFrameSize: UInt32 = 0
    /// User intent: whether to attempt the bit-perfect Pure HAL path on next playback start.
    /// Pure is mutually exclusive with DSP/EQ by construction (the bit-perfect stream is
    /// untouched). Setting this to `true` does NOT immediately affect running playback —
    /// it takes effect on the next `startPlayback()` call (not at a gapless join, KI-PB-05); there
    /// Master Gain turns the device's own volume down instead (`+MasterGain`). Kept across launches
    /// (`ListeningSettings`).
    var pureModeEnabled: Bool = false {
        didSet {
            logUX("pureMode → \(pureModeEnabled)")
            rememberListeningSettings()
        }
    }

    /// "Use FFmpeg for other formats" (R1.1-A, founder decision FD-3): FFmpeg may read a file Apple's
    /// decoder can't — its tags, and its sound in Pure Mode. Off by default: FFmpeg is an in-process
    /// parser for files from anywhere, and while this is off nothing loads it. Sets the process's one
    /// switch (`FFmpegOptIn`) — at launch from the kept setting, before the library starts any work.
    /// Kept across launches (`ListeningSettings`).
    var useFFmpeg: Bool = false {
        didSet {
            FFmpegOptIn.isOn = useFFmpeg
            logUX("useFFmpeg → \(useFFmpeg)")
            rememberListeningSettings()
        }
    }

    /// "Keep playback on this device". `true` (default): the device the user picks wins over the
    /// system default (a device that connects, or Control Center ▸ Sound, doesn't move playback),
    /// and playback goes back to it when it reconnects; until they pick one (in the menu, or by
    /// turning this on), the app follows the default. `false`: the app follows the system default.
    /// Pushed to the engine, whose output rule (`OutputDevicePolicy`) acts on it; a lost device
    /// pauses either way. Kept across launches, with the device it holds (`rememberOutputChoice`).
    var pinPlaybackToSelectedDevice: Bool = true {
        didSet {
            engine.setPinPlaybackToSelectedDevice(pinPlaybackToSelectedDevice)
            logUX("pinPlaybackToSelectedDevice → \(pinPlaybackToSelectedDevice)")
            rememberOutputChoice() // turning it on chooses the device in use
        }
    }

    /// The UID of the output device the user chose, as the engine holds it (`OutputDeviceSelection`):
    /// read back after a pick or the switch turned on, kept across launches, and handed back to the
    /// engine at engine-ready (DEV-1). `nil` when nothing is chosen — the device the app launches on is
    /// never a choice. Not UI-bound.
    @ObservationIgnored var chosenOutputUID: String?

    /// Live signal-path snapshot: which path is active, achieved rate, bit depth, etc.
    /// Updated by the transport tick (`pollEngineReadouts`) and when an intent it carries changes.
    var signalPath: SignalPathInfo = .init()

    /// Convenience derived property: `true` when the Pure HAL path is actually rendering.
    var pureModeEngaged: Bool {
        signalPath.path == .pure
    }

    // MARK: - Reimagine Intensity (QW-A)

    /// Whether the Intensity control is offered. Not until its effects are real (founder decision
    /// FD-2, 2026-10-14): Clarity and BRIR are pass-through stubs, so today the blend changes loudness,
    /// not sound (council C-41, C-40) — it returns with S17. Until then Intensity is held at 0, its
    /// default, and never restored; the inspector leaves its control (`ReimagineSectionView`) out.
    static let offersIntensity = false

    /// Reimagine's wet/dry blend of the coloration stages (clarity, spatial). The EQ sits AHEAD of
    /// the blend and plays at every Intensity (Sprint EQ decision 25), and crossfeed after it, at its
    /// own full strength (founder decision 2026-10-14): 0.0 =
    /// Reimagine off — the EQ alone, bit-perfect when the EQ is Off or flat; 1.0 = full blend.
    /// Default 0 — a faithful default (FD-2): the kernel's P0 / P1 path, so no leveller, no blend
    /// and, with the EQ off, no limiter (it was 0.20, which turned all three on). Published at
    /// engine-ready (`publishPlaybackIntents()`); hidden and held at 0 (`offersIntensity`).
    /// The slider binds this in 0...1, so the stored value is always in range; the engine call
    /// is clamped defensively with a LOCAL — NEVER re-assign `intensity` inside its own `didSet`
    /// (under @Observable a self-assignment re-fires the setter → infinite recursion → crash).
    /// Ops dispatched via `+IntensityControl`.
    var intensity: Float = 0 {
        didSet {
            logUX("intensity → \(Int(max(0, min(1, intensity)) * 100)) %")
            publishIntensity()
        }
    }

    // MARK: - Crossfeed (QW-C)

    /// Crossfeed as the listener chose it — the intent, kept across launches. It plays only on
    /// headphones (`crossfeedPlays`): an output that isn't holds it off without switching the choice
    /// off, so it plays again when headphones are back (council C-12: the effective value used to
    /// overwrite the intent).
    var crossfeedEnabled: Bool = false {
        didSet {
            logUX("crossfeed → \(crossfeedEnabled ? "on" : "off") [\(crossfeedStrength.displayName)]")
            publishCrossfeed()
            rememberListeningSettings()
        }
    }

    /// Crossfeed strength preset. Changes take effect immediately while crossfeed plays.
    var crossfeedStrength: CrossfeedStrength = .defaultStrength {
        didSet {
            rememberListeningSettings()
            guard crossfeedPlays else { return }
            logUX("crossfeed strength → \(crossfeedStrength.displayName)")
            publishCrossfeed()
        }
    }

    /// Whether crossfeed plays: chosen, and the output is headphones. What the engine gets.
    var crossfeedPlays: Bool {
        crossfeedEnabled && deviceIsHeadphones
    }

    /// `true` when the selected output device is a headphone-class device (`isHeadphones`).
    var deviceIsHeadphones: Bool {
        Self.isHeadphones(selectedDevice)
    }

    // MARK: - Master Gain

    /// Last Master Gain readout logged, so a slider DRAG coalesces to one line per distinct displayed
    /// level instead of ~25 identical lines (`logMasterGain`).
    var lastMasterGainLogged: String = ""

    /// Master Gain: the app's own level in dB (S10.8 G; founder decision 2026-10-12, "Show the real
    /// level"). Turn-down only — 0 dB, unity, at the top and on a new install; `MasterGainLaw` maps
    /// it to the slider and to the player's linear gain, and the inspector reads it back as it plays.
    /// Published on every change and at engine-ready. On Pure the bit-perfect stream is never scaled:
    /// the engine turns the output device's own volume down by it instead (`+MasterGain`). Kept across
    /// launches and never restored louder than it was left (council C-102; `ListeningSettings`).
    var masterGain: Float = MasterGainLaw.unity {
        didSet {
            logMasterGain("master gain → \(MasterGainLaw.text(masterGain))")
            publishMasterGain()
            rememberListeningSettings()
        }
    }

    // MARK: - Live spectrum and the transport tick

    /// The one reader of the analysers for every live view — the lens, the EQ's silhouette,
    /// Monitoring (council C-52). Not observable: the live views draw it on their own clock
    /// (`LiveTimeline`), so the analyser's stream never passes through Observation.
    @ObservationIgnored let spectrum: SpectrumSampler

    /// Drives TRANSPORT polling (playhead, gapless auto-advance, device-loss, the readouts) at 20 Hz
    /// while a song plays or a start, pause or stop is on its way (`transportTickIsLive`); it stops
    /// itself once nothing is (council C-52). Internal (not private) for `+TransportTick`.
    @ObservationIgnored var transportTicker: (any TransportTicker)?

    /// Test seams, each defaulting to what the app uses: the tick's ticker (the main run loop's timer), the
    /// clock the debounces sleep on, and the fire-and-forget work the view model spawns (`WorkTracker`).
    @ObservationIgnored let makeTicker: TransportTickerMaker
    @ObservationIgnored let clock: any Clock<Duration>
    @ObservationIgnored let work = WorkTracker()

    /// Whether the transport tick may run: from engine-ready (`armTransportTick`) to shutdown. Off in
    /// a view model whose engine was never started (tests that tick by hand, the picture sheets).
    @ObservationIgnored var transportTickArmed = false

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
            shufflePass?.follow(queue.map(\.id)) // an added song goes into the pass, a removed one leaves it
            queueStateChanged()
        }
    }

    /// Shuffle's pass through the queue (R1.1-B, council C-16): every song once, what played, where the
    /// listener is (`ShufflePass`). Present exactly while shuffle is on and a song is selected, its song
    /// playing always the selected one (`followSelectionInShufflePass`, +Playlist); it decides Next,
    /// Previous and the on-deck pick under shuffle. Not shown: Up Next keeps the queue's own order
    /// (founder, 2026-10-25). Kept with the queue's resume record (+QueueMirror). Not UI-bound.
    @ObservationIgnored var shufflePass: ShufflePass<UUID>? {
        didSet { queueStateChanged() }
    }

    /// The queue's ONE writer (R1.1-B, council C-65): the queue, the selected song, the shuffle pass and the
    /// playhead are written through it, each write one store transaction (+QueueMirror). Not UI-bound.
    @ObservationIgnored let queueStateWriter: CoalescingWriter<QueueStateKey, Void>
    /// What the writer has written and may write (+QueueMirror). Not UI-bound.
    @ObservationIgnored var queueStateBook = QueueStateBook()

    /// One-level snapshot of the queue captured just before a destructive "Play (replace queue)"
    /// (S10.3 D-play), so the UI can offer a transient "Restore previous queue" undo. Cleared once
    /// restored; the next undoable replace supersedes it — unless that replace only replaced this
    /// one's untouched queue (`QueueRestorePoint.afterReplace`). Not UI-bound beyond the undo affordance.
    var queueRestorePoint: QueueRestorePoint<QueueItem>?

    /// One-shot guard so launch hydration (`+QueueHydration`) runs at most once. What the user queued before
    /// it joins the restored queue. Not UI-bound.
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
            // By slot, not row: removing the selected song slides another into the same row (+Playlist).
            followSelectionInShufflePass()
            queueStateChanged()
        }
    }

    // Numbering what the view model asks of the engine (transport requests, on-deck requests) lives
    // in AudioViewModel+TransportCommands.swift. The selected slot, where a pause resumes and whether
    // Next / Previous would move live in AudioViewModel+Transport.swift.

    // MARK: - Library (S3 F5 — extracted to the LibraryModel peer)

    /// Non-owning back-reference to the library subsystem (a `@MainActor @Observable` PEER, owned by
    /// the composition root and injected here after construction). This is the ONLY audio→library
    /// edge: `countPlayCompletion` reads `library?.store` to write play counts. All library STATE
    /// (store, scan / reconcile / FSEvents watcher / volume monitor) now lives on `LibraryModel`;
    /// the browse UI reads it there. `weak` because the app's `@State` owns it for the whole process
    /// lifetime — it is still alive at every use — and to make the non-ownership explicit.
    weak var library: LibraryModel?

    // MARK: - Playback Modes (WinAmp Style)

    /// Shuffle mode: when enabled, plays every song once in a random order (`shufflePass`). Kept across
    /// launches. didSet: shuffle/repeat flip `canGoNext`/`canGoPrevious`, so refresh the remote-command
    /// enable state (S10.4 QA #1) — else Control Center's Next/Prev stay stale until the next play.
    var shuffleEnabled = false {
        didSet {
            if shuffleEnabled != oldValue {
                onNowPlayingRefresh?()
                followSelectionInShufflePass() // on: a pass begins at the selected song; off: it ends
            }
            rememberListeningSettings()
        }
    }

    /// Repeat mode: 0 = no repeat, 1 = repeat all, 2 = repeat one. Kept across launches.
    var repeatMode: Int = 0 {
        didSet {
            if repeatMode != oldValue {
                onNowPlayingRefresh?()
            }
            rememberListeningSettings()
        }
    }

    // MARK: - Gapless / Auto-Advance State

    /// Last observed seam count (the snapshot's `transitionCount`). An increase means the on-deck
    /// track has become the current track (a gapless seam just completed).
    /// Internal (not private) so the transport-tick and auto-advance extensions can read/write it.
    var lastTransitionCount: UInt64 = 0

    /// Playlist index of the track currently on deck (set with the engine's request by `armOnDeck`).
    /// `nil` means no track is queued (end of playlist, repeat-one handled inline,
    /// or playback has not started yet).
    /// Internal (not private) so the transport-tick and auto-advance extensions can read/write it.
    var pendingNextIndex: Int?

    let engine: any AudioPlaybackEngine
    /// The launch's `AppDataLocation.defaults`: the listener's settings, and the cursor a build before
    /// the queue's resume record kept (`+QueueHydration` reads it once). The picture-sheet renderer
    /// injects its own suite.
    let defaults: UserDefaults
    /// The listener's settings, kept in `defaults` (`+ListeningSettings`).
    let settingsStore: SettingsStore

    /// A view model over `defaults` that starts with the settings the listener left there — on a new
    /// install, the faithful default (FD-2).
    init(defaults: UserDefaults, engine: any AudioPlaybackEngine = AudioEngineBridge(),
         makeTicker: @escaping TransportTickerMaker = RunLoopTicker.make,
         clock: any Clock<Duration> = ContinuousClock()) {
        self.defaults = defaults
        self.engine = engine
        self.makeTicker = makeTicker
        self.clock = clock
        settingsStore = SettingsStore(defaults: defaults)
        spectrum = SpectrumSampler(engine: engine)
        eqDesignRate = engine.snapshot().eqDesignRate
        // The sink reaches the view model weakly; `self` exists only once every stored property is set.
        weak var model: AudioViewModel?
        queueStateWriter = CoalescingWriter { _, _ in await model?.writeQueueState() }
        model = self
        restoreListeningSettings()
    }

    // Engine lifecycle (initializeEngine, shutdown, stopPlayback, performStop) lives in
    // AudioViewModel+Lifecycle.swift.

    // The transport tick (tickTransport) lives in AudioViewModel+TransportTick.swift.

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
