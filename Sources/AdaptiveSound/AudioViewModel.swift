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
    var errorMessage: String?
    var selectedDevice: AudioDeviceModel?
    var availableDevices: [AudioDeviceModel] = []
    var sampleRate: UInt32 = 0
    var bufferFrameSize: UInt32 = 0
    var masterGain: Float = 0.7 {
        didSet {
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
    var repeatMode: Int = 0 {
        didSet {
            repeatMode = repeatMode % 3 // Cycle 0 → 1 → 2 → 0
        }
    }

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
                    errorMessage = "Failed to initialize audio engine"
                    isEngineReady = false
                    return
                }

                // Enumerate real output devices from CoreAudio
                let devices = try await engine.enumerateOutputDevices()

                availableDevices = devices
                selectedDevice = devices.first
                isEngineReady = true
                errorMessage = nil
                startSpectrumTimer()
            } catch {
                errorMessage = "Engine initialization failed: \(error.localizedDescription)"
                isEngineReady = false
            }
        }
    }

    func shutdown() {
        stopSpectrumTimer()
        stopFolderMonitoring()
        stopPlayback()
        Task {
            try await engine.shutdown()
            isEngineReady = false
        }
    }

    // MARK: - Spectrum Timer

    /// Start polling the spectrum double-buffer at 20 Hz.
    /// Safe to call multiple times — guards against duplicate timers.
    func startSpectrumTimer() {
        guard spectrumTimer == nil else { return }
        spectrumTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tickSpectrum()
        }
        // Include in common run-loop modes so the timer fires during tracking
        RunLoop.main.add(spectrumTimer!, forMode: .common)
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
        guard engine.readSpectrumBands(into: &spectrumScratch) else { return }
        // Upsample 44 bands → 88 bars by linear interpolation between adjacent bands.
        // Bar i maps to fractional band position i / 2.0 (even bars fall on band centres).
        let bandCount = SpectrumConstants.bandCount
        let barCount = SpectrumConstants.displayBarCount
        for bar in 0 ..< barCount {
            let frac = Float(bar) / Float(barCount - 1) * Float(bandCount - 1)
            let lower = Int(frac)
            let upper = min(lower + 1, bandCount - 1)
            let t = frac - Float(lower)
            spectrumBars[bar] = spectrumScratch[lower] * (1 - t) + spectrumScratch[upper] * t
        }
    }

    // MARK: - Device Management

    func selectDevice(_ device: AudioDeviceModel) {
        Task {
            do {
                let success = try await engine.selectDevice(device.id)
                if !success {
                    errorMessage = "Failed to select device: \(device.name)"
                    return
                }

                selectedDevice = device
                sampleRate = device.sampleRate
                bufferFrameSize = device.bufferFrameSize
                errorMessage = nil
            } catch {
                errorMessage = "Device selection failed: \(error.localizedDescription)"
            }
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

        Task {
            do {
                try await engine.startAudio(fileURL: fileURL)
                isPlaying = true
                errorMessage = nil
            } catch {
                errorMessage = "Playback failed: \(error.localizedDescription)"
                isPlaying = false
            }
        }
    }

    func stopPlayback() {
        Task {
            do {
                try await engine.stopAudio()
                isPlaying = false
            } catch {
                errorMessage = "Stop playback failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Parameter Control

    func setParameter(_ id: UInt32, value: Float) {
        Task {
            try await engine.setParameter(id, value: value)
        }
    }

    // MARK: - Folder Loading & Monitoring

    /// Enumerate all audio files under `folderURL` recursively and update `playlist`.
    func loadMusicFolder(_ folderURL: URL) async {
        musicFolderURL = folderURL
        folderPathDisplay = Self.makeDisplayPath(folderURL)
        playlist = []

        let files = await Task.detached(priority: .userInitiated) {
            AudioFileEnumerator.enumerate(folderURL: folderURL)
        }.value

        playlist = files
    }

    /// Start monitoring the folder for changes using FSEvents-style notification.
    /// When files are added/removed/modified, automatically reload the playlist.
    private func startFolderMonitoring(_ folderURL: URL) {
        let fileDescriptor = open(folderURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: monitoringQueue
        )

        source.setEventHandler { [weak self] in
            // Debounce rapid file system changes (100ms)
            self?.folderMonitorDebounceTask?.cancel()
            self?.folderMonitorDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                if let folderURL = self.musicFolderURL {
                    await self.loadMusicFolder(folderURL)
                }
            }
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        folderMonitorSource = source
        source.resume()
    }

    /// Stop monitoring the folder for changes.
    private func stopFolderMonitoring() {
        folderMonitorDebounceTask?.cancel()
        folderMonitorSource?.cancel()
        folderMonitorSource = nil
    }

    // MARK: - Playlist Reordering & Editing

    /// Reorder playlist items via drag-and-drop.
    /// Called when user drags items in the playlist.
    func movePlaylistItems(from source: IndexSet, to destination: Int) {
        playlist.move(fromOffsets: source, toOffset: destination)
        // If the currently selected track was moved, update its index
        if let current = selectedTrackIndex, source.contains(current) {
            if let newIndex = playlist.firstIndex(where: { $0.id == self.playlist[destination].id }) {
                selectedTrackIndex = newIndex
            }
        }
    }

    /// Remove a track from the playlist.
    func removeTrack(at index: Int) {
        guard index >= 0, index < playlist.count else { return }
        playlist.remove(at: index)

        // If we removed the selected track, select the next one (or previous if it was the last)
        if selectedTrackIndex == index {
            if index < playlist.count {
                selectedTrackIndex = index // Next track shifts into this position
            } else if index > 0 {
                selectedTrackIndex = index - 1
            } else {
                selectedTrackIndex = nil
            }
        } else if let current = selectedTrackIndex, current > index {
            // Shift index if a track before the selected one was removed
            selectedTrackIndex = current - 1
        }
    }

    /// Clear the entire playlist.
    func clearPlaylist() {
        playlist.removeAll()
        selectedTrackIndex = nil
        stopPlayback()
    }

    /// Toggle shuffle mode.
    func toggleShuffle() {
        shuffleEnabled.toggle()
    }

    /// Cycle through repeat modes: 0 (off) → 1 (all) → 2 (one) → 0
    func cycleRepeatMode() {
        repeatMode = (repeatMode + 1) % 3
    }

    // MARK: - Playback

    /// Play the track at the given playlist index.
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        selectedTrackIndex = index
        startPlayback()
    }

    // MARK: - Helpers

    private static func makeDisplayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let raw = url.path
        if raw.hasPrefix(home) {
            return "~" + raw.dropFirst(home.count)
        }
        return raw
    }
}
