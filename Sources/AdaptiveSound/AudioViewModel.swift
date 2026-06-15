import Accelerate
import AVFoundation
import Darwin
import Foundation

// MARK: - Audio Device Model

struct AudioDeviceModel: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let sampleRate: UInt32
    let bufferFrameSize: UInt32

    enum DeviceType {
        case builtin
        case usb
        case wireless
        case unknown
    }

    let type: DeviceType

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

    private let audioEngine: AudioEngineBridge
    private let masterGainParameterID: UInt32 = 0

    init(audioEngine: AudioEngineBridge = AudioEngineBridge()) {
        self.audioEngine = audioEngine
    }

    // MARK: - Engine Lifecycle

    func initializeEngine() {
        Task.detached { [weak self] in
            do {
                let success = try await self?.audioEngine.initialize() ?? false
                if !success {
                    await MainActor.run {
                        self?.errorMessage = "Failed to initialize audio engine"
                        self?.isEngineReady = false
                    }
                    return
                }

                // Enumerate devices
                let deviceNames = try await self?.audioEngine.getOutputDeviceNames() ?? []
                let devices = deviceNames.enumerated().map { index, name in
                    AudioDeviceModel(
                        id: UInt32(index),
                        name: name,
                        sampleRate: 48000,
                        bufferFrameSize: 512,
                        type: .unknown
                    )
                }

                await MainActor.run {
                    self?.availableDevices = devices
                    self?.selectedDevice = devices.first
                    self?.isEngineReady = true
                    self?.errorMessage = nil
                    self?.startSpectrumTimer()
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Engine initialization failed: \(error.localizedDescription)"
                    self?.isEngineReady = false
                }
            }
        }
    }

    func shutdown() {
        stopSpectrumTimer()
        stopFolderMonitoring()
        stopPlayback()
        Task.detached { [weak self] in
            try await self?.audioEngine.shutdown()
            await MainActor.run {
                self?.isEngineReady = false
            }
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
        guard audioEngine.readSpectrumBands(into: &spectrumScratch) else { return }
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
        Task.detached { [weak self] in
            do {
                let success = try await self?.audioEngine.selectDevice(device.id) ?? false
                if !success {
                    await MainActor.run {
                        self?.errorMessage = "Failed to select device: \(device.name)"
                    }
                    return
                }

                await MainActor.run {
                    self?.selectedDevice = device
                    self?.sampleRate = device.sampleRate
                    self?.bufferFrameSize = device.bufferFrameSize
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Device selection failed: \(error.localizedDescription)"
                }
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

        Task.detached { [weak self] in
            do {
                try await self?.audioEngine.startAudio(fileURL: fileURL)
                await MainActor.run {
                    self?.isPlaying = true
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Playback failed: \(error.localizedDescription)"
                    self?.isPlaying = false
                }
            }
        }
    }

    func stopPlayback() {
        Task.detached { [weak self] in
            do {
                try await self?.audioEngine.stopAudio()
                await MainActor.run {
                    self?.isPlaying = false
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Stop playback failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Parameter Control

    func setParameter(_ id: UInt32, value: Float) {
        Task.detached { [weak self] in
            try await self?.audioEngine.setParameter(id, value: value)
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
            self?.folderMonitorDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if !Task.isCancelled {
                    await MainActor.run {
                        if let folderURL = self?.musicFolderURL {
                            Task {
                                await self?.loadMusicFolder(folderURL)
                            }
                        }
                    }
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

// MARK: - C++ Bridge

class AudioEngineBridge {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var referenceToneBuffer: AVAudioPCMBuffer?

    // MARK: - Spectrum Analyzer

    /// Owns the FFT state and the lock-free double-buffer.
    /// Created on initialize() (off the audio thread) so all buffers are
    /// pre-allocated before the tap fires.
    private var spectrumAnalyzer: SpectrumAnalyzer?

    /// Tap is installed on mainMixerNode's output; the node's format fixes
    /// the sample rate that `SpectrumAnalyzer` must be initialised with.
    private var tapInstalled = false

    // MARK: - Initialize

    func initialize() async throws -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    self.audioEngine = AVAudioEngine()
                    guard let engine = self.audioEngine else {
                        continuation.resume(returning: false)
                        return
                    }

                    // Use stereo 48 kHz format to support any input file (mono, stereo, WebM, etc).
                    // AVAudio will automatically convert any file format to match this.
                    let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2) ??
                        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000.0, channels: 2, interleaved: false)

                    self.playerNode = AVAudioPlayerNode()
                    if let playerNode = self.playerNode, let format = audioFormat {
                        engine.attach(playerNode)
                        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
                    }

                    // Pre-allocate the spectrum analyzer using the mixer's output sample rate.
                    // This MUST happen off the audio thread (vDSP_create_fftsetup allocates).
                    let mixerSampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
                    let sampleRate = mixerSampleRate > 0 ? mixerSampleRate : 48000.0
                    self.spectrumAnalyzer = SpectrumAnalyzer(
                        fftSize: SpectrumConstants.fftSize,
                        sampleRate: sampleRate
                    )

                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Spectrum tap

    /// Install a single output tap on `mainMixerNode`.
    ///
    /// The tap block runs on the audio thread (or a CoreAudio I/O thread).
    /// It may NOT allocate, lock, log, or call Obj-C/Swift runtime.
    ///
    /// Buffer size of 4096 aligns with `SpectrumConstants.fftSize` so the
    /// analyzer can process one tap delivery per FFT frame. AVAudioEngine
    /// will round up to a power-of-two multiple of the hardware buffer size
    /// automatically if needed.
    private func installSpectrumTap() {
        guard let engine = audioEngine, !tapInstalled else { return }
        let mixer = engine.mainMixerNode
        let mixerFormat = mixer.outputFormat(forBus: 0)

        mixer.installTap(onBus: 0,
                         bufferSize: AVAudioFrameCount(SpectrumConstants.fftSize),
                         format: mixerFormat)
        { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            // --- AUDIO THREAD ---
            // Access only pre-allocated state through the analyzer pointer.
            guard let analyzer = self?.spectrumAnalyzer else { return }
            let abl = buffer.mutableAudioBufferList
            analyzer.processTapBuffer(
                abl,
                frameCount: buffer.frameLength,
                channelCount: buffer.format.channelCount
            )
        }
        tapInstalled = true
    }

    private func removeSpectrumTap() {
        guard let engine = audioEngine, tapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    // MARK: - Public spectrum read (called from main thread via ViewModel)

    /// Copy the latest 44 band magnitudes into `out`. Returns `false` if no
    /// data has been published yet (engine not running or no signal).
    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool {
        return spectrumAnalyzer?.doubleBuffer.read(into: &out) ?? false
    }

    // MARK: - Shutdown

    func shutdown() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.removeSpectrumTap()
                if let playerNode = self.playerNode, playerNode.isPlaying {
                    playerNode.stop()
                }
                if let engine = self.audioEngine, engine.isRunning {
                    engine.stop()
                }
                self.audioEngine = nil
                self.playerNode = nil
                self.referenceToneBuffer = nil
                self.spectrumAnalyzer = nil
                continuation.resume()
            }
        }
    }

    func getOutputDeviceNames() async throws -> [String] {
        // Bridge to C++ AudioEngine::getOutputDeviceNames()
        // Mock implementation for now
        return ["Built-in Speaker", "AirPods Pro", "USB Audio Interface"]
    }

    func selectDevice(_: UInt32) async throws -> Bool {
        // Bridge to C++ AudioEngine::selectOutputDevice()
        return true
    }

    func startAudio(fileURL: URL? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    guard let engine = self.audioEngine, let playerNode = self.playerNode else {
                        throw AudioBridgeError.engineNotInitialized
                    }

                    // Start the engine first
                    if !engine.isRunning {
                        try engine.start()
                    }

                    // Install the spectrum tap once the engine is running.
                    // installSpectrumTap is idempotent (guarded by tapInstalled flag).
                    self.installSpectrumTap()

                    if let fileURL = fileURL {
                        // Establish security-scoped access for sandboxed macOS file access
                        let didAccess = fileURL.startAccessingSecurityScopedResource()
                        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

                        // Load and schedule the audio file (AVAudioFile handles format conversion)
                        do {
                            // CRITICAL: Stop and reset the player before scheduling a new file.
                            // If we don't stop, the new file queues AFTER the old one instead of replacing it.
                            // This ensures track switching happens immediately, not after current track finishes.
                            if playerNode.isPlaying {
                                playerNode.stop()
                            }

                            let audioFile = try AVAudioFile(forReading: fileURL)
                            playerNode.scheduleFile(audioFile, at: nil)
                            playerNode.play()
                        } catch {
                            throw AudioBridgeError.unsupportedFormat(fileURL.pathExtension)
                        }
                    } else {
                        // Fallback to reference tone if no file provided
                        self.referenceToneBuffer = self.generateReferenceTone(
                            frequency: 1000.0,
                            duration: 5.0,
                            sampleRate: 48000.0
                        )

                        if let buffer = self.referenceToneBuffer {
                            if !playerNode.isPlaying {
                                playerNode.play()
                            }
                            playerNode.scheduleBuffer(buffer, at: nil)
                        }
                    }

                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopAudio() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if let playerNode = self.playerNode, playerNode.isPlaying {
                    playerNode.stop()
                }
                if let engine = self.audioEngine, engine.isRunning {
                    engine.stop()
                }
                self.removeSpectrumTap()
                self.referenceToneBuffer = nil
                continuation.resume()
            }
        }
    }

    func setParameter(_ id: UInt32, value: Float) async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if id == 0 {
                    // Master gain parameter
                    if let playerNode = self.playerNode {
                        playerNode.volume = value
                    }
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Reference Tone Generation (using vDSP)

    func generateReferenceTone(
        frequency: Float,
        duration: Float,
        sampleRate: Float
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }

        let floatData = floatChannelData[0]

        // Generate sine wave using vDSP
        // Phase increment per sample: 2π * frequency / sampleRate
        let phaseIncrement = 2.0 * Float.pi * frequency / sampleRate

        // Build angle array: angle[i] = phaseIncrement * i
        var angles = [Float](repeating: 0, count: Int(frameCount))
        for sampleIndex in 0 ..< Int(frameCount) {
            angles[sampleIndex] = phaseIncrement * Float(sampleIndex)
        }

        // Compute sine using vForce.sin (Accelerate, vectorised single-precision)
        let sineValues = vForce.sin(angles)
        sineValues.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            UnsafeMutableBufferPointer(start: floatData, count: Int(frameCount))
                .baseAddress
                .map { dst in
                    cblas_scopy(Int32(frameCount), srcBase, 1, dst, 1)
                }
        }

        // Apply gain
        var gain = Float(0.3)
        vDSP_vsmul(floatData, 1, &gain, floatData, 1, vDSP_Length(frameCount))

        return buffer
    }
}

// MARK: - AudioEngineBridge Error

enum AudioBridgeError: Error {
    case engineNotInitialized
    case auInitializationFailed
    case parameterSetFailed
    case unsupportedFormat(String)

    var localizedDescription: String {
        switch self {
        case .engineNotInitialized:
            return "Audio engine not initialized"
        case .auInitializationFailed:
            return "Audio unit initialization failed"
        case .parameterSetFailed:
            return "Parameter setting failed"
        case let .unsupportedFormat(ext):
            return "Unsupported file format: .\(ext). Supported: MP3, WAV, AAC, M4A, FLAC, AIFF, OGG"
        }
    }
}
