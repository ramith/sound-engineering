import AVFoundation
import Foundation

// MARK: - AudioViewModel

// AudioDeviceModel is defined in Models/AudioDeviceModel.swift.

@MainActor
@Observable
final class AudioViewModel {
    var isEngineReady = false
    var isPlaying = false
    /// Selected top-level tab. Owned here (not in `ContentView` `@State`) so deep views — e.g.
    /// a double-click on the Now Playing spectrum — can navigate without binding-plumbing.
    var selectedTab: TabSelection = .nowPlaying {
        didSet { logUX("tab → \(selectedTab.rawValue)") }
    }

    /// Live playhead position in seconds (polled at the spectrum-timer rate).
    var playbackPosition: Double = 0
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

    /// Scratch array — reused each tick, never reallocated.
    /// Internal (not private) so `AudioViewModel+SpectrumTimer.swift` can write into it.
    var spectrumScratch: [Float] = .init(repeating: 0, count: SpectrumConstants.bandCount)

    // MARK: - Playlist State

    var musicFolderURL: URL? {
        didSet {
            // Update folder monitoring when folder changes
            stopFolderMonitoring()
            if let url = musicFolderURL {
                startFolderMonitoring(url)
            }
        }
    }

    var playlist: [AudioFile] = []
    var folderPathDisplay: String = ""
    /// Track selection (does NOT auto-play). Selection and playback are separate.
    /// Use playTrack() or startPlayback() to actually play the selected track.
    var selectedTrackIndex: Int?

    // MARK: - Directory Monitoring

    /// Internal (not private) so `AudioViewModel+FolderMonitor.swift` can access them.
    var folderMonitorSource: DispatchSourceFileSystemObject?
    var monitoringQueue = DispatchQueue(label: "com.adaptivesound.folder-monitor", qos: .default)
    var folderMonitorDebounceTask: Task<Void, Never>?

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

    // MARK: - Engine Lifecycle

    func initializeEngine() {
        Task {
            do {
                let success = try await engine.initialize()
                if !success {
                    logUX("initializeEngine: failed (engine returned false)")
                    errorMessage = "Failed to initialize audio engine"
                    isEngineReady = false
                    return
                }

                // Enumerate real output devices from CoreAudio
                let devices = try await engine.enumerateOutputDevices()

                availableDevices = devices
                // Select the device that is ACTUALLY the engine's current target (the system default
                // captured at init), not blindly "first" — otherwise the UI selection and the
                // engine's currentDeviceID diverge, and the app-authority re-assert later tries to
                // re-pin a stale id ("device gone"). Fall back to first if the default isn't listed.
                let engineDeviceID = engine.currentOutputDeviceID()
                let chosen = devices.first { $0.id == engineDeviceID } ?? devices.first
                selectedDevice = chosen
                // Assert the chosen device so currentDeviceID == selectedDevice == system default
                // from the start. A valid default re-asserts to itself (no change); a stale/phantom
                // default is corrected to the chosen device.
                if let chosen {
                    _ = try? await engine.selectDevice(chosen.id)
                }
                // Push the connect-behaviour preference so the engine acts on it from the first
                // device change (its default matches, but this keeps them explicitly in step).
                engine.setPinPlaybackToSelectedDevice(pinPlaybackToSelectedDevice)
                // Keep the picker current when devices connect/disconnect (e.g. Bluetooth).
                engine.onOutputDevicesChanged = { [weak self] in self?.refreshDevices() }
                isEngineReady = true
                errorMessage = nil
                logUX("initializeEngine: ready — \(devices.count) device(s), "
                    + "selected='\(selectedDevice?.name ?? "none")'")
                startSpectrumTimer()
            } catch {
                logUX("initializeEngine: error — \(error.localizedDescription)")
                errorMessage = "Engine initialization failed: \(error.localizedDescription)"
                isEngineReady = false
            }
        }
    }

    func shutdown() {
        logUX("shutdown — was playing=\(isPlaying)")
        stopSpectrumTimer()
        stopFolderMonitoring()
        stopPlayback()
        Task {
            do {
                try await engine.shutdown()
            } catch {
                errorMessage = "Engine shutdown failed: \(error.localizedDescription)"
            }
            isEngineReady = false
        }
    }

    // Spectrum timer + tickSpectrum live in AudioViewModel+SpectrumTimer.swift.

    // Device management (selectDevice, refreshDevices, retryInitialization) lives in AudioViewModel+Devices.swift.

    // MARK: - Playback Control

    func startPlayback() {
        guard isEngineReady else {
            errorMessage = "Engine not ready"
            return
        }

        guard let selectedIndex = selectedTrackIndex, selectedIndex < playlist.count else {
            errorMessage = "No track selected"
            return
        }

        let fileURL = playlist[selectedIndex].absoluteURL
        playbackPosition = 0
        logUX("play: track[\(selectedIndex)] '\(playlist[selectedIndex].name)' "
            + "pureMode=\(pureModeEnabled) device='\(selectedDevice?.name ?? "none")'")

        // Compute duration off-main from AVAudioFile; more reliable than the metadata
        // scan's durationSeconds for M4A (which can read 0).
        Task.detached(priority: .userInitiated) { [weak self] in
            var computedDuration: Double = 0
            if let file = try? AVAudioFile(forReading: fileURL) {
                let rate = file.processingFormat.sampleRate
                if rate > 0 {
                    computedDuration = Double(file.length) / rate
                }
            }
            await MainActor.run {
                self?.duration = computedDuration
                logUX("duration = \(secs(computedDuration))s")
            }
        }

        // Snapshot index and mode for use inside the Task (avoids capturing `self` for
        // values that could change between now and when the Task body runs).
        let startIndex = selectedTrackIndex
        let pureModeSnapshot = pureModeEnabled

        Task {
            do {
                try await engine.startAudio(fileURL: fileURL, pureMode: pureModeSnapshot)

                // Prime the gapless pipeline: reset the transition counter baseline
                // and supply the on-deck track so the engine can pre-schedule it.
                let freshCount = engine.trackTransitionCount()
                await MainActor.run {
                    lastTransitionCount = freshCount
                }

                let currentIdx = await MainActor.run { startIndex ?? self.selectedTrackIndex }
                let count = await MainActor.run { self.playlist.count }
                let nextIdx = await MainActor.run { [weak self] () -> Int? in
                    guard let self else { return nil }
                    return self.computeNextIndex(
                        current: currentIdx ?? 0,
                        playlistCount: count
                    )
                }
                await MainActor.run { pendingNextIndex = nextIdx }

                if let idx = nextIdx, idx < (await MainActor.run { playlist.count }) {
                    let nextURL = await MainActor.run { playlist[idx].absoluteURL }
                    await engine.setNextTrack(nextURL)
                    logUX("startPlayback: primed next index=\(idx) pureMode=\(pureModeSnapshot)")
                } else {
                    await engine.setNextTrack(nil)
                    logUX("startPlayback: no next track to prime (single-track or end of playlist)")
                }

                await MainActor.run {
                    isPlaying = true
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Playback failed: \(error.localizedDescription)"
                    isPlaying = false
                    pendingNextIndex = nil
                }
            }
        }
    }

    func stopPlayback() {
        logUX("stop (was at \(secs(playbackPosition))s)")
        // Clear the on-deck state synchronously so `tickSpectrum` won't react after stop.
        pendingNextIndex = nil
        Task {
            do {
                await engine.setNextTrack(nil)
                try await engine.stopAudio()
                isPlaying = false
                playbackPosition = 0
                duration = 0
            } catch {
                errorMessage = "Stop playback failed: \(error.localizedDescription)"
            }
        }
    }

    /// Seek to `seconds` from the start of the current file.
    /// Updates `playbackPosition` immediately to avoid UI jitter while the engine seeks.
    func seek(to seconds: Double) {
        logUX("seek → \(secs(seconds))s "
            + "(from \(secs(playbackPosition))s, dur \(secs(duration))s, "
            + "path=\(signalPath.path == .pure ? "Pure" : "Enhanced"))")
        playbackPosition = seconds
        Task {
            await engine.seek(to: seconds)
        }
    }

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
        folderPathDisplay = Self.makeDisplayPath(folderURL)
        playlist = []

        let files = await Task.detached(priority: .userInitiated) {
            AudioFileEnumerator.enumerate(folderURL: folderURL)
        }.value

        playlist = files
        logUX("loadMusicFolder: loaded \(files.count) file(s) from '\(folderPathDisplay)'")
    }

    // MARK: - Playback

    /// Play the track at the given playlist index.
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        selectedTrackIndex = index
        startPlayback()
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

// Folder monitoring lives in AudioViewModel+FolderMonitor.swift.
// Playlist editing (movePlaylistItems, removeTrack, clearPlaylist, toggleShuffle, cycleRepeatMode)
// lives in AudioViewModel+Playlist.swift.
// Gapless/auto-advance (handleTrackTransition, computeNextIndex) lives in AudioViewModel+AutoAdvance.swift.
