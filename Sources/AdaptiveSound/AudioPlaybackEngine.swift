import AVFoundation
import Foundation

// MARK: - AudioPlaybackEngine Protocol

/// Protocol boundary between AudioViewModel and the live audio engine.
///
/// Conforming types provide all I/O operations needed by AudioViewModel.
/// The protocol enables unit-testing of AudioViewModel without a live
/// AVAudioEngine: tests inject a `MockAudioEngine` instead.
///
/// Concurrency contract: all methods may be called from a background Task.
/// Implementations are responsible for dispatching UI-bound side-effects to
/// the main actor if needed; the protocol itself is actor-agnostic.
protocol AudioPlaybackEngine: AnyObject {
    // MARK: Lifecycle

    /// Initialize the engine and prepare for playback.
    /// Returns `true` on success.
    func initialize() async throws -> Bool

    /// Tear down the engine, release hardware resources.
    func shutdown() async throws

    // MARK: Playback

    /// Start playback of the audio file at `fileURL`, or a reference tone if nil.
    func startAudio(fileURL: URL?) async throws

    /// Stop all playback immediately.
    func stopAudio() async throws

    /// Current playhead position in seconds since playback started, or `nil` when
    /// not playing / unavailable. A fast, lock-free query safe to poll from the UI.
    func currentPlaybackPosition() -> Double?

    /// Latest BS.1770-5 loudness measurement (LUFS + sample-peak), measured on the
    /// playback tap. Lock-free; safe to poll from the UI. `.unmeasured` if unavailable.
    func currentLoudness() -> LoudnessSnapshot

    // MARK: DSP Parameters

    /// Set a DSP parameter by ID (e.g. master gain = 0).
    func setParameter(_ id: UInt32, value: Float) async throws

    /// Publish a 31-band EQ gain vector (dB) to the live DSP AU. `gainsDb` must have 31
    /// elements. Synchronous, off-RT, non-throwing: it computes the biquad cascade and
    /// atomically hands it to the kernel. No-op if no live AU (e.g. engine not initialized).
    func publishEQGains(_ gainsDb: [Float])

    // MARK: Device Enumeration

    /// Return the full list of available output devices with real CoreAudio data.
    func enumerateOutputDevices() async throws -> [AudioDeviceModel]

    /// Select an output device by its CoreAudio device ID.
    /// Returns `true` on success.
    func selectDevice(_ deviceID: UInt32) async throws -> Bool

    // MARK: Spectrum

    /// Read the latest 44 spectrum band magnitudes into `out`.
    /// Returns `false` if no data has been published yet.
    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool

    // MARK: Monitoring (per-channel before/after spectra)

    /// Number of channels being monitored (the graph's channel count). 0 until the engine is ready.
    var monitorChannelCount: Int { get }

    /// Read the latest per-channel band magnitudes for the given tap point + channel into `out`.
    /// Returns `false` if unavailable (not ready, channel out of range, or no data yet).
    @discardableResult
    func readMonitorBands(_ tap: MonitorTap, channel: Int, into out: inout [Float]) -> Bool
}
