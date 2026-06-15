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

    // MARK: DSP Parameters

    /// Set a DSP parameter by ID (e.g. master gain = 0).
    func setParameter(_ id: UInt32, value: Float) async throws

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
}
