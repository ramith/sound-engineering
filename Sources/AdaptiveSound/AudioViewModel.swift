import Accelerate
import AVFoundation
import Darwin
import Foundation

// MARK: - Audio Device Model

struct AudioDeviceModel: Identifiable, Equatable, Hashable {
    let id: UInt32
    let name: String
    let sampleRate: UInt32
    let bufferFrameSize: UInt32

    enum DeviceType: Hashable {
        case builtin
        case usb
        case wireless
        case unknown

        /// Map from the uint8_t sent by `CDeviceInfo.deviceType`.
        /// 0=Unknown, 1=Builtin, 2=USB, 3=Wireless (matches `AUAudioUnit.mm`).
        init(rawValue: UInt8) {
            switch rawValue {
            case 1: self = .builtin
            case 2: self = .usb
            case 3: self = .wireless
            default: self = .unknown
            }
        }
    }

    let type: DeviceType

    /// Returns the sample rate as a human-readable kHz string.
    /// Uses integer display when the rate is an exact multiple of 1000 Hz (e.g. "48 kHz"),
    /// and one decimal place otherwise (e.g. "44.1 kHz").
    var displayKHz: String {
        let khz = Double(sampleRate) / 1000.0
        if sampleRate % 1000 == 0 {
            return "\(sampleRate / 1000) kHz"
        }
        return String(format: "%.1f kHz", khz)
    }

    var displayName: String {
        let typeLabel: String
        switch type {
        case .builtin:
            typeLabel = "Built-in"
        case .usb:
            typeLabel = "USB"
        case .wireless:
            typeLabel = "Wireless"
        case .unknown:
            typeLabel = "Unknown"
        }
        return "\(name) (\(typeLabel))"
    }

    var systemIcon: String {
        switch type {
        case .builtin:
            return "speaker.wave.2.circle"
        case .usb:
            return "cable.connector"
        case .wireless:
            return "airpodspro"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// MARK: - AudioViewModel

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
    private var spectrumTimer: Timer?

    /// Scratch array — reused each tick, never reallocated.
    private var spectrumScratch: [Float] = .init(repeating: 0, count: SpectrumConstants.bandCount)

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

    private var folderMonitorSource: DispatchSourceFileSystemObject?
    private var monitoringQueue = DispatchQueue(label: "com.adaptivesound.folder-monitor", qos: .default)
    private var folderMonitorDebounceTask: Task<Void, Never>?

    // MARK: - Playback Modes (WinAmp Style)

    /// Shuffle mode: when enabled, plays tracks in random order
    var shuffleEnabled = false

    /// Repeat mode: 0 = no repeat, 1 = repeat all, 2 = repeat one
    var repeatMode: Int = 0

    // MARK: - Gapless / Auto-Advance State

    /// Last observed `trackTransitionCount()` value. An increase means the on-deck
    /// track has become the current track (a gapless seam just completed).
    private var lastTransitionCount: UInt64 = 0

    /// Playlist index of the track currently on deck (supplied via `setNextTrack`).
    /// `nil` means no track is queued (end of playlist, repeat-one handled inline,
    /// or playback has not started yet).
    private var pendingNextIndex: Int?

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

    // MARK: - Spectrum Timer

    /// Start polling the spectrum double-buffer at 20 Hz.
    /// Safe to call multiple times — guards against duplicate timers.
    func startSpectrumTimer() {
        guard spectrumTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tickSpectrum()
        }
        spectrumTimer = timer
        // Include in common run-loop modes so the timer fires during tracking
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopSpectrumTimer() {
        spectrumTimer?.invalidate()
        spectrumTimer = nil
    }

    /// Called at 20 Hz on the main thread. Reads the latest band magnitudes
    /// from the double-buffer, interpolates 44 bands → 88 display bars, and
    /// writes into `spectrumBars` to trigger SwiftUI observation.
    @MainActor
    private func tickSpectrum() {
        // Poll the playhead + loudness + signal path every tick (independent of spectrum).
        playbackPosition = isPlaying ? (engine.currentPlaybackPosition() ?? playbackPosition) : 0
        loudness = engine.currentLoudness()
        signalPath = engine.currentSignalPath()

        // The output device disappeared (e.g. Bluetooth disconnected) and the engine paused —
        // reflect it in the UI and prompt the user to pick a device.
        if signalPath.interrupted, isPlaying {
            logUX("device-loss interrupt — stopping playback")
            isPlaying = false
            playbackPosition = 0
            errorMessage = "Output device disconnected — playback paused. Pick a device to resume."
            // Clear pending on-deck track; device loss invalidates the gapless queue.
            pendingNextIndex = nil
            Task { await engine.setNextTrack(nil) }
        }

        // --- Gapless auto-advance poll ---
        if isPlaying {
            let currentCount = engine.trackTransitionCount()
            if currentCount > lastTransitionCount {
                // A gapless seam completed: the on-deck track is now current.
                // Intentional: we advance by exactly ONE track per tick even if the count
                // jumped by more than one (e.g. two back-to-back very-short tracks in a
                // single 50 ms interval). The VM records the new baseline and calls
                // handleTrackTransition once; the next tick catches any remaining delta.
                // This keeps selectedTrackIndex in sync with pendingNextIndex at all times.
                lastTransitionCount = currentCount
                handleTrackTransition()
            } else if engine.playbackEnded() {
                // Current track ended with no next track — stop the transport.
                logUX("playbackEnded — no next track, stopping")
                isPlaying = false
                playbackPosition = 0
            }
        }

        guard engine.readSpectrumBands(into: &spectrumScratch) else { return }
        // Upsample 44 bands → 88 bars by linear interpolation between adjacent bands.
        // Bar i maps to fractional band position i / 2.0 (even bars fall on band centres).
        let bandCount = SpectrumConstants.bandCount
        let barCount = SpectrumConstants.displayBarCount
        for bar in 0 ..< barCount {
            let frac = Float(bar) / Float(barCount - 1) * Float(bandCount - 1)
            let lower = Int(frac)
            let upper = min(lower + 1, bandCount - 1)
            let weight = frac - Float(lower)
            spectrumBars[bar] = spectrumScratch[lower] * (1 - weight) + spectrumScratch[upper] * weight
        }
    }

    // MARK: - Device Management

    func selectDevice(_ device: AudioDeviceModel) {
        logUX("selectDevice: '\(device.name)' id=\(device.id)")
        Task {
            do {
                let success = try await engine.selectDevice(device.id)
                if !success {
                    logUX("selectDevice: failed for '\(device.name)' id=\(device.id)")
                    errorMessage = "Failed to select device: \(device.name)"
                    return
                }

                selectedDevice = device
                sampleRate = device.sampleRate
                bufferFrameSize = device.bufferFrameSize
                errorMessage = nil
                logUX("selectDevice: ok '\(device.name)' id=\(device.id) "
                    + "\(device.displayKHz) buf=\(device.bufferFrameSize)")
            } catch {
                logUX("selectDevice: error '\(device.name)' — \(error.localizedDescription)")
                errorMessage = "Device selection failed: \(error.localizedDescription)"
            }
        }
    }

    /// Re-enumerate output devices after the device set changes (connect/disconnect), preserving the
    /// current selection when it still exists. Invoked on the main actor via `onOutputDevicesChanged`.
    func refreshDevices() {
        Task {
            guard let devices = try? await engine.enumerateOutputDevices() else { return }
            availableDevices = devices
            // Reflect the engine's ACTUAL target after the connect-behaviour handler ran: PIN mode
            // re-pinned the selected device; FOLLOW mode adopted the newly-connected one. If that
            // target isn't listed, keep the current selection when still present, else fall to first.
            let engineDeviceID = engine.currentOutputDeviceID()
            if let target = devices.first(where: { $0.id == engineDeviceID }) {
                selectedDevice = target
            } else if !(selectedDevice.map { sel in devices.contains { $0.id == sel.id } } ?? false) {
                selectedDevice = devices.first
            }
            logUX("refreshDevices: \(devices.count) device(s), "
                + "selected='\(selectedDevice?.name ?? "none")'")
        }
    }

    func retryInitialization() {
        errorMessage = nil
        isEngineReady = false
        initializeEngine()
    }

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

    // MARK: - Monitoring (per-channel before/after; Sprint 5 M3)

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

// MARK: - Folder Monitoring (private extension)

private extension AudioViewModel {
    func startFolderMonitoring(_ folderURL: URL) {
        let fileDescriptor = open(folderURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: monitoringQueue
        )

        source.setEventHandler { [weak self] in
            self?.folderMonitorDebounceTask?.cancel()
            self?.folderMonitorDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                if let url = self.musicFolderURL {
                    await self.loadMusicFolder(url)
                }
            }
        }

        source.setCancelHandler { close(fileDescriptor) }
        folderMonitorSource = source
        source.resume()
    }

    func stopFolderMonitoring() {
        folderMonitorDebounceTask?.cancel()
        folderMonitorSource?.cancel()
        folderMonitorSource = nil
    }
}

// MARK: - Playlist Editing (extension)

extension AudioViewModel {
    /// Reorder playlist items via drag-and-drop.
    func movePlaylistItems(from source: IndexSet, to destination: Int) {
        logUX("movePlaylistItems: \(source.map { $0 }) → \(destination)")
        let movedID = selectedTrackIndex.flatMap { current in
            source.contains(current) ? playlist[current].id : nil
        }
        playlist.move(fromOffsets: source, toOffset: destination)
        if let movedID {
            selectedTrackIndex = playlist.firstIndex(where: { $0.id == movedID })
        }
    }

    /// Remove a track from the playlist.
    func removeTrack(at index: Int) {
        guard index >= 0, index < playlist.count else { return }
        logUX("removeTrack: index=\(index) '\(playlist[index].name)'")

        let removingCurrent = (selectedTrackIndex == index)
        playlist.remove(at: index)

        if let pending = pendingNextIndex {
            if pending == index {
                // The on-deck track was removed. Re-compute the next index from the current
                // playing track so the engine stays primed (rather than leaving it with nil).
                let currentIdx = selectedTrackIndex ?? 0
                let newNextIdx = computeNextIndex(current: currentIdx, playlistCount: playlist.count)
                pendingNextIndex = newNextIdx
                Task { [weak self] in
                    guard let self else { return }
                    if let newIdx = newNextIdx, newIdx < playlist.count {
                        await engine.setNextTrack(playlist[newIdx].absoluteURL)
                    } else {
                        await engine.setNextTrack(nil)
                    }
                }
            } else if pending > index {
                pendingNextIndex = pending - 1
            }
        }

        if removingCurrent, isPlaying {
            logUX("removeTrack: removed currently-playing track, stopping")
            pendingNextIndex = nil
            stopPlayback()
            selectedTrackIndex = index < playlist.count ? index : (index > 0 ? index - 1 : nil)
            return
        }

        if selectedTrackIndex == index {
            selectedTrackIndex = index < playlist.count ? index : (index > 0 ? index - 1 : nil)
        } else if let cur = selectedTrackIndex, cur > index {
            selectedTrackIndex = cur - 1
        }
    }

    /// Clear the entire playlist. Stops playback and clears the on-deck track.
    func clearPlaylist() {
        logUX("clearPlaylist: removing \(playlist.count) track(s)")
        playlist.removeAll()
        selectedTrackIndex = nil
        pendingNextIndex = nil
        stopPlayback()
    }

    /// Toggle shuffle mode.
    func toggleShuffle() {
        shuffleEnabled.toggle()
        logUX("shuffle → \(shuffleEnabled)")
    }

    /// Cycle through repeat modes: 0 (off) → 1 (all) → 2 (one) → 0
    func cycleRepeatMode() {
        repeatMode = (repeatMode + 1) % 3
        let label = ["off", "all", "one"][repeatMode]
        logUX("repeat → \(label) (\(repeatMode))")
    }
}

// MARK: - Gapless / Auto-Advance (private extension)

@MainActor
private extension AudioViewModel {
    /// Invoked when `trackTransitionCount()` increases (a gapless seam completed).
    /// Advances the highlighted index, resets the scrubber, refreshes duration,
    /// and queues the NEW next track on-deck.
    func handleTrackTransition() {
        guard let nextIdx = pendingNextIndex else {
            logUX("trackTransition: pendingNextIndex is nil, ignoring")
            return
        }
        guard nextIdx < playlist.count else {
            logUX("trackTransition: pendingNextIndex \(nextIdx) out of range, stopping")
            pendingNextIndex = nil
            isPlaying = false
            playbackPosition = 0
            return
        }

        let advancedTrack = playlist[nextIdx]
        logUX("trackTransition: advancing to index=\(nextIdx) '\(advancedTrack.name)'")

        selectedTrackIndex = nextIdx
        playbackPosition = 0
        duration = 0 // zeroed now; async Task below refreshes from AVAudioFile

        let newNextIdx = computeNextIndex(current: nextIdx, playlistCount: playlist.count)
        pendingNextIndex = newNextIdx

        let fileURL = advancedTrack.absoluteURL
        let pureModeSnap = pureModeEnabled

        Task.detached(priority: .userInitiated) { [weak self] in
            var computedDuration: Double = 0
            if let file = try? AVAudioFile(forReading: fileURL) {
                let rate = file.processingFormat.sampleRate
                if rate > 0 { computedDuration = Double(file.length) / rate }
            }
            await MainActor.run {
                self?.duration = computedDuration
                logUX("trackTransition: duration = \(secs(computedDuration))s")
            }
        }

        Task { [weak self] in
            guard let self else { return }
            if let newIdx = newNextIdx, newIdx < playlist.count {
                let nextURL = playlist[newIdx].absoluteURL
                await engine.setNextTrack(nextURL)
                logUX("trackTransition: primed next index=\(newIdx) pureMode=\(pureModeSnap)")
            } else {
                await engine.setNextTrack(nil)
                logUX("trackTransition: no further track to queue")
            }
        }
    }
}

// MARK: - Next-Index Computation (internal — consumed by tests via local mirror)

extension AudioViewModel {
    /// Compute the playlist index that should play after `current`, honouring
    /// `shuffleEnabled` and `repeatMode`.
    ///
    /// - Returns: the next index, or `nil` when playback should stop after `current`.
    func computeNextIndex(current: Int, playlistCount: Int) -> Int? {
        guard playlistCount > 0 else { return nil }
        if repeatMode == 2 { return current } // repeat-one

        if shuffleEnabled, playlistCount > 1 {
            var candidate = Int.random(in: 0 ..< playlistCount)
            while candidate == current {
                candidate = Int.random(in: 0 ..< playlistCount)
            }
            return candidate
        }

        let nextLinear = current + 1
        if nextLinear < playlistCount { return nextLinear }
        return repeatMode == 1 ? 0 : nil
    }
}
