import AVFoundation
import Foundation

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
extension AudioPlaybackEngine {
    /// Convenience overload: start playback without Pure-mode (Enhanced path).
    /// Non-Pure callers — including legacy call sites — use this rather than the
    /// full `startAudio(fileURL:pureMode:)` signature.
    func startAudio(fileURL: URL?) async throws {
        try await startAudio(fileURL: fileURL, pureMode: false)
    }

    // MARK: Gapless defaults (overridden by the live engine + the mock)

    //
    // Declared as protocol requirements (below) for dynamic dispatch, with these no-op /
    // neutral defaults so a conformer that does not implement gapless still builds and behaves
    // as "one track then stop" — the pre-gapless behaviour.

    /// Supply (or clear, with `nil`) the track to play gaplessly after the current one. Default: no-op.
    func setNextTrack(_: URL?) async {}

    /// Monotonic count of completed gapless seams. Default: 0 (never advances).
    func trackTransitionCount() -> UInt64 {
        0
    }

    /// True once the current track ended with no next track on deck. Default: false.
    func playbackEnded() -> Bool {
        false
    }

    /// Default: no device targeted (0). The live engine overrides with its `currentDeviceID`.
    func currentOutputDeviceID() -> UInt32 {
        0
    }

    /// Default: no-op. The live engine stores the preference and consults it on device changes.
    func setPinPlaybackToSelectedDevice(_: Bool) {}

    /// Default: no-op. Conformers that host the DSP AU override this.
    func publishIntensity(_: Float) {}

    /// Default: no-op. Conformers that host the DSP AU override this.
    func publishCrossfeed(enabled _: Bool, strength _: CrossfeedStrength) async {}
}

protocol AudioPlaybackEngine: AnyObject {
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

    // MARK: Gapless / continuous playback (poll-based — the view model already polls at 20 Hz)

    //
    // # GaplessController contract (S6 Tier-3 §4)
    //
    // The three gapless requirements below (`setNextTrack`, `trackTransitionCount`, `playbackEnded`)
    // plus `currentPlaybackPosition()` form the GaplessController behavioural contract that BOTH live
    // paths — the Enhanced bridge (`AudioEngineBridge+Gapless.swift` / `+GaplessRoll.swift`) and the
    // Pure HAL C-ABI (`PureModeBridge.h` → `GaplessSource`) — must satisfy identically. The contract
    // is intentionally poll-based: the view model already polls at 20 Hz and drives every transition
    // off the polled counter (`trackTransitionCount()`).
    //
    // Invariants (asserted by the shared conformance suite):
    //   1. Arm → seam → `trackTransitionCount()` increments by EXACTLY ONE per seam.
    //   2. `setNextTrack(nil)` cancels the on-deck track (no seam occurs from a cleared deck).
    //   3. End-of-queue (a seam with nothing on deck) signals `playbackEnded()`.
    //   4. Position RE-ZEROES at the seam (see `currentPlaybackPosition()` below): the first sample of
    //      the new track reports ~0.0, NOT cumulative time across the seam. VERIFIED PARITY: both
    //      paths comply — Pure re-zeroes per track natively (`PureModeBridge.h` `pureModeEnginePosition`
    //      `Seconds`: "RESTARTS at 0 at each gapless seam"); Enhanced re-bases its position at every
    //      seam in `bumpTransitionCount` (sets `enhancedPositionBaseSeconds = -(sampleTime/rate)`),
    //      which is called from EVERY seam path in `+GaplessRoll.swift`.
    //
    // ## Path asymmetry — polling side effect (S6 Tier-3 §4.4)
    //
    // `trackTransitionCount()` MUST be polled regularly on the PURE path: each call to the underlying
    // `pureModeEnginePollTrackAdvance` ALSO reaps the seam-retired decode source off-RT (joins its
    // decode thread). If the caller stops polling, retired decode threads leak — so the counter is NOT
    // a pure observer on Pure. The ENHANCED path has NO such coupling (its counter is a plain read of
    // `gaplessTransitionCount` on `resampleQueue`; the retired resampler session is torn down inline at
    // the seam, not on the next poll). The view model satisfies both by polling every 20 Hz tick.
    // Treat regular polling as a contract REQUIREMENT, not an optimization, because of the Pure path.

    /// Supply the track to play gaplessly after the current one finishes, or `nil` to clear the
    /// on-deck track. The engine pre-schedules (Enhanced) / arms (Pure) it so the transition is
    /// seamless — no `stop()`, no inserted silence. Re-supply after each transition to keep one
    /// track on deck. Reuses the current path (Enhanced/Pure) and mode. Default impl: no-op.
    ///
    /// Contract: `setNextTrack(nil)` CANCELS the on-deck track — it clears the armed slot and disarms
    /// any seam hook so no queued track silently begins later. A subsequent end-of-current-track with
    /// an empty deck signals `playbackEnded()` rather than seaming. (Enhanced: clears `onDeckURL` +
    /// the EOF hooks on `resampleQueue`; Pure: `pureModeEngineClearNextTrack`, which joins the dropped
    /// source off-RT.)
    func setNextTrack(_ fileURL: URL?) async

    /// Monotonic count of completed gapless track transitions (seams). The view model polls this;
    /// an increase means the on-deck track is now current → advance the highlighted index, re-zero
    /// the scrubber, refresh duration, and supply the next on-deck track. Default impl: 0.
    ///
    /// Contract: increments by EXACTLY ONE per completed seam. MUST be polled regularly: on the PURE
    /// path the poll also reaps the seam-retired decode source off-RT — stop polling and decode
    /// threads leak (it is not a pure observer there). The ENHANCED path has no such coupling (see the
    /// "Path asymmetry" note above). Treat regular polling as a requirement of the contract.
    func trackTransitionCount() -> UInt64

    /// `true` once playback reached the end of the current track with NO next track on deck (queue
    /// exhausted). The view model polls this to stop the transport. Cleared on the next
    /// `startAudio`. Default impl: `false`.
    func playbackEnded() -> Bool

    /// Seek to `seconds` from the start of the current file.
    /// In the Pure path this is handled natively by the HAL engine. In the
    /// Enhanced path this is a best-effort re-schedule (see `AudioEngineBridge+PureMode.swift`).
    func seek(to seconds: Double) async

    /// Current playhead position in seconds since playback started, or `nil` when
    /// not playing / unavailable. A fast, lock-free query safe to poll from the UI.
    ///
    /// Contract — position RE-ZEROES PER TRACK at the gapless seam (VERIFIED PARITY, both paths): the
    /// returned value is position WITHIN the current track, not cumulative across seams. At a seam the
    /// first sample of the new track reports ~0.0 and grows from there. Pure re-zeroes natively
    /// (`PureModeBridge.h` `pureModeEnginePositionSeconds`); Enhanced re-bases at every seam in
    /// `bumpTransitionCount` (`enhancedPositionBaseSeconds = -(sampleTime/rate)`, so
    /// `base + sampleTime/rate ≈ 0` for the new track even though the gapless player node is never
    /// stopped and its `sampleTime` keeps accumulating). A seek jumps within the current track and
    /// does NOT count as a seam.
    func currentPlaybackPosition() -> Double?

    /// Snapshot of the active signal path (path kind, achieved rate, bit depth, etc.).
    /// Lock-free; safe to poll from the UI at 20 Hz.
    func currentSignalPath() -> SignalPathInfo

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

    /// Publish a new Reimagine intensity value ([0, 1]) to the live DSP AU.
    /// No-op if the AU is not yet instantiated. Default impl: no-op.
    func publishIntensity(_ intensity: Float)

    /// Publish a crossfeed state change to the live DSP AU (QW1 §3).
    /// No-op if the AU is not yet instantiated. Default impl: no-op.
    func publishCrossfeed(enabled: Bool, strength: CrossfeedStrength) async

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

    /// Set the "when a new device connects" preference. `true` = keep playback on the selected device
    /// (app-authoritative; re-pin it). `false` = follow the newly-connected device. Default: no-op.
    func setPinPlaybackToSelectedDevice(_ pin: Bool)

    /// Invoked on the main thread when the set of available output devices changes (a device was
    /// added or removed, e.g. Bluetooth connect/disconnect). The view model re-enumerates in
    /// response so the picker stays current.
    var onOutputDevicesChanged: (() -> Void)? { get set }

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
