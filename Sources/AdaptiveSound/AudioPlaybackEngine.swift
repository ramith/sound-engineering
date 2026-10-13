import AVFoundation
import Foundation
import PlaybackQueueKit

// MARK: - AudioPlaybackEngine Protocol + Default Implementations

/// Protocol boundary between AudioViewModel and the live audio engine.
///
/// Conforming types provide all I/O operations needed by AudioViewModel.
/// The protocol enables unit-testing of AudioViewModel without a live
/// AVAudioEngine: tests inject a `MockAudioEngine` instead.
///
/// Concurrency contract: all methods may be called from a background Task.
/// Implementations are responsible for dispatching UI-bound side-effects to
/// the main actor if needed; the protocol itself is actor-agnostic.
///
/// MAIN-THREAD RULE (S10.8 G, the disconnect freeze): the view model calls every SYNCHRONOUS
/// requirement on the main thread, so none of them may call into AVFAudio (a node, the engine, its
/// I/O unit) or the CoreAudio HAL, take a lock held across such a call, or `.sync` onto a queue that
/// makes one. They return a copy (`transportSnapshot`, `currentSignalPath`), an atomic, or a value
/// read under a lock held only for the read. Anything that must touch the hardware is `async`, or
/// hands its work to an engine queue and answers through a snapshot (`requestDeviceVolume`).
extension AudioPlaybackEngine {
    // MARK: Gapless defaults (overridden by the live engine + the mock)

    //
    // Declared as protocol requirements (below) for dynamic dispatch, with these no-op /
    // neutral defaults so a conformer that does not implement gapless still builds and behaves
    // as "one track then stop" — the pre-gapless behaviour.

    /// Supply (or clear, with `nil`) the track to play gaplessly after the current one. Default: no-op.
    func setNextTrack(_: URL?) async {}

    /// Default: no device targeted (0). The live engine overrides with its `currentDeviceID`.
    func currentOutputDeviceID() -> UInt32 {
        0
    }

    /// Default: no-op. The live engine stores the preference and consults it on device changes.
    func setPinPlaybackToSelectedDevice(_: Bool) {}

    /// Default: no-op. Conformers that host the DSP AU override this.
    func publishIntensity(_: Float) {}

    /// Default: no-op. Conformers that host the DSP AU override this.
    func publishCrossfeed(enabled _: Bool, strength _: CrossfeedStrength) {}

    /// Default: no-op. Conformers that host the DSP AU override this.
    func publishOutputTransport(_: UInt32) {}

    /// Default: no-op. Conformers with a player override this.
    func publishMasterGain(decibels _: Float) {}

    /// Default: no-op — nothing plays on Pure, so there is no device volume to set.
    func requestDeviceVolume(decibels _: Float) {}
}

protocol AudioPlaybackEngine: AnyObject, Sendable {
    // MARK: Lifecycle

    /// Initialize the engine and prepare for playback.
    /// Returns `true` on success.
    func initialize() async throws -> Bool

    /// Tear down the engine, release hardware resources.
    func shutdown() async throws

    // MARK: Playback

    /// Start playback of the audio file at `fileURL`, or a reference tone if nil.
    /// When `pureMode` is `true` and the device + file support it, the bit-perfect
    /// HAL path is used; otherwise the Enhanced AVAudioEngine path is used.
    func startAudio(fileURL: URL?, pureMode: Bool) async throws

    /// Stop all playback immediately.
    func stopAudio() async throws

    // MARK: Gapless / continuous playback (poll-based — the view model reads a snapshot at 20 Hz)

    //
    // # GaplessController contract (S6 Tier-3 §4)
    //
    // `setNextTrack` plus the transport snapshot (`transitionCount`, `ended`, `position`) form the
    // GaplessController behavioural contract that BOTH live paths — the Enhanced bridge
    // (`AudioEngineBridge+Gapless.swift` / `+GaplessRoll.swift`) and the Pure HAL C-ABI
    // (`PureModeBridge.h` → `GaplessSource`) — must satisfy identically. The view model drives every
    // transition off the snapshot's `transitionCount`.
    //
    // Invariants (asserted by the shared conformance suite):
    //   1. Arm → seam → `transitionCount` increments by EXACTLY ONE per seam.
    //   2. `setNextTrack(nil)` cancels the on-deck track (no seam occurs from a cleared deck).
    //   3. End-of-queue (a seam with nothing on deck) sets `ended`.
    //   4. `position` RE-ZEROES at the seam: the first sample of the new track reports ~0.0, NOT
    //      cumulative time across the seam. VERIFIED PARITY: Pure re-zeroes per track natively
    //      (`PureModeBridge.h` `pureModeEnginePositionSeconds`: "RESTARTS at 0 at each gapless seam");
    //      Enhanced re-bases at every seam in `bumpTransitionCount` (sets
    //      `enhancedPositionBaseSeconds = -(sampleTime/rate)`), called from EVERY seam path in
    //      `+GaplessRoll.swift`.
    //
    // ## Pure's polling side effect (S6 Tier-3 §4.4)
    //
    // Polling the Pure seam counter (`pureModeEnginePollTrackAdvance`) also reaps the seam-retired
    // decode source off-RT (joins its decode thread), so it must be polled regularly. The live
    // engine's own transport clock does that, off the main thread (AudioEngineBridge+TransportClock).

    /// Supply the track to play gaplessly after the current one finishes, or `nil` to clear the
    /// on-deck track. The engine pre-schedules (Enhanced) / arms (Pure) it so the transition is
    /// seamless — no `stop()`, no inserted silence. Re-supply after each transition to keep one
    /// track on deck. Reuses the current path (Enhanced/Pure) and mode. Default impl: no-op.
    ///
    /// Contract: `setNextTrack(nil)` CANCELS the on-deck track — it clears the armed slot and disarms
    /// any seam hook so no queued track silently begins later. A subsequent end-of-current-track with
    /// an empty deck sets `ended` rather than seaming. (Enhanced: clears `onDeckURL` + the EOF hooks
    /// on `resampleQueue`; Pure: `pureModeEngineClearNextTrack`, which joins the dropped source off-RT.)
    func setNextTrack(_ fileURL: URL?) async

    /// The transport as the engine last sampled it, off the main thread: the playhead within the
    /// current track (re-zeroed at each seam), the seam count, and whether the queue ran out. A copy —
    /// it never waits on the player, the engine or the hardware, however long they are stuck; it may
    /// be a frame stale. After `startAudio`, `stopAudio` and `seek` return, it reflects them.
    func transportSnapshot() -> TransportSnapshot

    /// Seek to `seconds` from the start of the current file.
    /// In the Pure path this is handled natively by the HAL engine. In the
    /// Enhanced path this is a best-effort re-schedule (see `AudioEngineBridge+PureMode.swift`).
    func seek(to seconds: Double) async

    /// Snapshot of the active signal path (path kind, achieved rate, bit depth, etc.).
    /// Lock-free; safe to poll from the UI at 20 Hz.
    func currentSignalPath() -> SignalPathInfo

    /// Latest BS.1770-5 loudness measurement (LUFS + sample-peak), measured on the
    /// playback tap. Lock-free; safe to poll from the UI. `.unmeasured` if unavailable.
    func currentLoudness() -> LoudnessSnapshot

    // MARK: Master Gain

    /// Publish Master Gain — the app's own level in dB, ≤ 0 (−∞ = silent; `MasterGainLaw`). The
    /// player plays it at its linear gain from then on, on every Enhanced start and after a rebuild
    /// too. Never reaches Pure: the bit-perfect stream is not scaled (see `setDeviceVolume`).
    /// Synchronous and off-RT; calls apply in the order made. Default impl: no-op.
    func publishMasterGain(decibels: Float)

    /// While Pure plays, set the output device's own volume to `decibels` (clamped to the device's
    /// range and to 0 dB at most; −∞ is its minimum). Returns at once: the engine sets the device off
    /// the main thread and puts what it reads back into the signal-path snapshot
    /// (`deviceVolume`, and `deviceVolumeSet` for this request). Calls apply in the order made. A
    /// no-op when Pure is not playing. Default impl: no-op.
    func requestDeviceVolume(decibels: Float)

    // MARK: DSP Parameters

    /// Publish the EQ to the live DSP AU (the engine side of the Sprint EQ contract): the 31
    /// `points` (dB, one per band, `EQBands`) that are drawn, and whether the EQ plays at all.
    /// `isOn == false` plays the flat curve whatever `points` hold. Synchronous, off-RT,
    /// non-throwing; the engine validates its input (count, finite, ±12 dB) and coalesces bursts.
    /// No-op if no live AU (e.g. engine not initialized).
    func publishEQ(points: [Float], isOn: Bool)

    /// The sample rate (Hz) the EQ is designed at — the live DSP AU's, else the graph's 48 kHz before
    /// it exists — so the graph's played curve (`EQDesigner`) is designed exactly as the engine plays
    /// it. Synchronous, off-RT, cheap enough to read on every redraw.
    func eqSampleRate() -> Double

    /// Publish a new Reimagine intensity value ([0, 1]) to the live DSP AU.
    /// No-op if the AU is not yet instantiated. Default impl: no-op.
    func publishIntensity(_ intensity: Float)

    /// Tell the live DSP AU which kind of output it plays on: the device's
    /// `kAudioDevicePropertyTransportType` (0 = unknown). Founder decision 29: the EQ-only path's
    /// limiter ceiling is −0.1 dBTP on a wired or built-in output and −1 dBTP on Bluetooth.
    /// Synchronous, off-RT. No-op if the AU is not yet instantiated. Default impl: no-op.
    func publishOutputTransport(_ transportType: UInt32)

    /// Publish a crossfeed state change to the live DSP AU (QW1 §3).
    /// No-op if the AU is not yet instantiated. Default impl: no-op. Synchronous + off-RT: it
    /// borrows the AU under the leaf lock and hands the state to the kernel (no suspension point).
    func publishCrossfeed(enabled: Bool, strength: CrossfeedStrength)

    // MARK: Device Enumeration

    /// Return the full list of available output devices with real CoreAudio data.
    func enumerateOutputDevices() async throws -> [AudioDeviceModel]

    /// Select an output device by its CoreAudio device ID.
    /// Returns `true` on success.
    func selectDevice(_ deviceID: UInt32) async throws -> Bool

    /// The output device the engine is currently targeting (the app-selected / default-at-launch
    /// device id), so the view model can select the matching `AudioDeviceModel` on launch and keep
    /// its selection in step with the bridge's `currentDeviceID`. `0` if none. Default impl: `0`.
    func currentOutputDeviceID() -> UInt32

    /// Set "Keep playback on this device". `true` = the selected device wins over the system default
    /// (re-asserted while Enhanced plays or starts). `false` = follow the system default. Default: no-op.
    func setPinPlaybackToSelectedDevice(_ pin: Bool)

    /// Invoked on the main thread when the output changed: a device was added or removed, the
    /// engine adopted the system default (follow), or it paused for a lost device. The view model
    /// re-reads the devices and the engine's device (`currentOutputDeviceID`) in response.
    var onOutputDevicesChanged: (@MainActor () -> Void)? { get set }

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
