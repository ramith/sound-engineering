@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import OutputDeviceKit

// MARK: - AudioEngineBridge output-device monitoring (one device-state path)

/// The ONE path every output change goes through, on both playback paths (Sprint G break-it
/// B3, B4, B5). Four sources feed it:
///   - the device list (`kAudioHardwarePropertyDevices`),
///   - the system default output (`kAudioHardwarePropertyDefaultOutputDevice`): the app's own
///     changes, Control Center ▸ Sound, a device that connects and takes the default,
///   - the app's device staying alive (`kAudioDevicePropertyDeviceIsAlive` on `currentDeviceID`,
///     bound to whichever device that is, on Enhanced and Pure alike),
///   - `AVAudioEngineConfigurationChange` (AudioEngineBridge+ConfigChange.swift).
/// Each is serialized onto `configChangeQueue`, where `reconcileOutputDevice` reads the facts fresh
/// and asks `OutputDevicePolicy` (OutputDeviceKit, unit-tested) what to do: pause on a lost device,
/// adopt the default (follow), put the app's device back as the default (pinned), restart the
/// Enhanced engine. The view model is then told to re-read the device state (`refreshDevices`),
/// which is where the pill, the per-output EQ, the limiter ceiling and the crossfeed check follow,
/// and where a Pure session moves to a new device.
///
/// Queues: the two system listeners are registered and removed on `engineQueue` (initialize /
/// teardown); the alive listener and `isMonitoringOutput` live on `configChangeQueue`; the
/// listener blocks themselves only hop onto `configChangeQueue`. Nothing runs on the audio thread.
extension AudioEngineBridge {
    // MARK: - Listeners

    /// Start watching the output. Runs on `engineQueue` from `initialize()`, after
    /// `currentDeviceID` holds the device the app starts on.
    func registerOutputDeviceListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let queue = DispatchQueue.global(qos: .userInitiated)
        deviceListListener = AudioPropertyListener(
            objectID: system, selector: kAudioHardwarePropertyDevices, queue: queue
        ) { [weak self] in
            self?.outputDeviceDidChange(.devicesChanged)
        }
        defaultOutputListener = AudioPropertyListener(
            objectID: system, selector: kAudioHardwarePropertyDefaultOutputDevice, queue: queue
        ) { [weak self] in
            self?.outputDeviceDidChange(.defaultChanged)
        }
        // engineQueue → configChangeQueue.sync is deadlock-free: configChangeQueue never waits on
        // engineQueue (it only ever dispatches to it asynchronously).
        configChangeQueue.sync {
            isMonitoringOutput = true
            bindTargetAliveListener()
        }
    }

    /// Stop watching (engine teardown, on `engineQueue`). The alive listener goes synchronously on
    /// its own queue, with `isMonitoringOutput` cleared, so a late event can't re-bind it.
    func unregisterOutputDeviceListeners() {
        deviceListListener?.remove()
        deviceListListener = nil
        defaultOutputListener?.remove()
        defaultOutputListener = nil
        configChangeQueue.sync {
            isMonitoringOutput = false
            bindTargetAliveListener() // unbinds: nothing to watch while not monitoring
        }
    }

    /// Make `deviceID` the device the app plays on, and watch that one for going away. Any queue.
    func setOutputTarget(_ deviceID: UInt32) {
        setCurrentDeviceID(deviceID)
        configChangeQueue.async { [weak self] in
            self?.bindTargetAliveListener()
        }
    }

    /// Keep the alive listener on `currentDeviceID` (none while not monitoring). Idempotent. On
    /// `configChangeQueue` only. Replacing the listener here is what ends the old one: the Pure
    /// path used to register a fresh listener on every start and never remove the last (leak).
    private func bindTargetAliveListener() {
        let target = isMonitoringOutput ? currentDeviceID : 0
        if let bound = targetAliveListener, bound.objectID == target {
            return
        }
        targetAliveListener?.remove()
        targetAliveListener = nil
        guard target != 0 else { return }
        targetAliveListener = AudioPropertyListener(
            objectID: AudioObjectID(target), selector: kAudioDevicePropertyDeviceIsAlive,
            queue: DispatchQueue.global(qos: .userInteractive)
        ) { [weak self] in
            self?.outputDeviceDidChange(.targetAliveChanged)
        }
    }

    // MARK: - The device-state path

    /// Entry point for every output event: serialize it onto `configChangeQueue`, where the
    /// Enhanced re-establish also runs, so a pause and a restart can never interleave (P1-B).
    func outputDeviceDidChange(_ event: OutputDeviceEvent) {
        configChangeQueue.async { [weak self] in
            self?.reconcileOutputDevice(after: event)
        }
    }

    /// Decide and act on one event. On `configChangeQueue`.
    private func reconcileOutputDevice(after event: OutputDeviceEvent) {
        guard isMonitoringOutput else { return }
        let facts = readOutputDeviceFacts()
        let action = OutputDevicePolicy.action(for: event, facts: facts)
        logUX("output \(event): \(Self.describe(facts)) → \(action)")
        if action.pauseForDeviceLoss {
            pauseForDeviceLoss()
        }
        applyTargetChange(action, facts: facts)
        if action.reestablishEnhanced, let engine = avEngineRef {
            reestablishEnhancedAfterConfigChange(engine: engine)
        }
        // The picker lists devices; the pill shows the app's device: re-read when either changed.
        if event == .devicesChanged || action.adoptTarget != nil || action.pauseForDeviceLoss {
            notifyOutputDevicesChanged()
        }
    }

    /// Just before the Enhanced engine starts (on `engineQueue`): it plays on the system default,
    /// so pinned puts the app's device back as the default, and follow takes the default as the
    /// app's device. Covers "headphones connected while paused, then Play" (break-it B4).
    func alignOutputForEnhancedStart() {
        let facts = readOutputDeviceFacts()
        let action = OutputDevicePolicy.action(for: .enhancedStarting, facts: facts)
        guard action.adoptTarget != nil || action.reassertTarget else { return }
        logUX("output enhancedStarting: \(Self.describe(facts)) → \(action)")
        applyTargetChange(action, facts: facts)
        if action.adoptTarget != nil {
            notifyOutputDevicesChanged()
        }
    }

    /// Adopt a new target and/or put the target back as the system default. The default change
    /// this causes comes back as `.defaultChanged` with the default already on the app's device,
    /// which the rule answers with nothing — so the app's own changes don't loop.
    private func applyTargetChange(_ action: OutputDeviceAction, facts: OutputDeviceFacts) {
        if let adopted = action.adoptTarget {
            setOutputTarget(adopted)
        }
        if action.reassertTarget {
            // Best effort (selectOutputDeviceC logs a refused default, e.g. a device that can't be one).
            let reasserted = selectOutputDeviceC(facts.target) != 0
            logUX("output: re-assert \(facts.target) as default \(reasserted ? "ok" : "failed (device gone?)")")
        }
    }

    /// The facts the rule decides from, read now. Any bridge queue except `resampleQueue`.
    private func readOutputDeviceFacts() -> OutputDeviceFacts {
        let target = currentDeviceID
        let playback: OutputPlayback
        if activePathKind == .pure {
            playback = .pure
        } else {
            playback = resampleQueue.sync { enhancedPlayIntent } ? .enhanced : .idle
        }
        return OutputDeviceFacts(
            target: target,
            targetAlive: Self.isDeviceAlive(target),
            systemDefault: getDefaultOutputDeviceID(),
            playback: playback,
            pinned: pinsPlaybackToSelectedDevice
        )
    }

    /// Tell the view model (on the main thread) to re-read the devices and the app's device.
    private func notifyOutputDevicesChanged() {
        DispatchQueue.main.async { [weak self] in
            // `DispatchQueue.main` runs on the main thread, the main actor's executor;
            // `assumeIsolated` proves that to the compiler for the @MainActor callback.
            MainActor.assumeIsolated { self?.onOutputDevicesChanged?() }
        }
    }

    // MARK: - Pause on device loss

    /// Pause because the device the app plays on disappeared (founder decision, 94b263c: pause,
    /// never carry on from another device), on Enhanced and Pure alike. On `configChangeQueue`.
    /// The play intent and the `interrupted` flag are set here, first, so every later event on
    /// this queue sees nothing playing and restarts nothing (P1-B); the view model reads
    /// `interrupted`, clears `isPlaying` and asks the user to pick a device. The engines stop on
    /// `engineQueue`, serialized with start / seek / stop, so this can't free a Pure session that
    /// a start is using.
    private func pauseForDeviceLoss() {
        logUX("output device lost during playback — pausing")
        resampleQueue.sync { enhancedPlayIntent = false }
        storeInterruptedSignalPath()
        engineQueue.async { [weak self] in
            self?.stopPlaybackAfterDeviceLoss()
        }
    }

    /// The engine half of `pauseForDeviceLoss`. On `engineQueue`.
    ///
    /// It does NOT stop the player (the disconnect freeze, S10.8 G). The engine has already stopped
    /// itself on the configuration change the loss caused (AVAudioEngine.h,
    /// `AVAudioEngineConfigurationChangeNotification`: "the engine stops itself"), so nothing
    /// renders; and `-[AVAudioPlayerNode stop]` on the dying device waited ~7 s — destroying its
    /// scheduled file asks the output for its latency (`AVAudioIOUnit::GetDeviceLatency`), which
    /// waits until macOS has torn the device down — while holding the player's lock. The schedule it
    /// leaves is cleared at the next Enhanced start, before the engine runs (`startEnhancedPlayback`).
    private func stopPlaybackAfterDeviceLoss() {
        tearDownPure()
        // Abandon in-flight resampler buffers and pending passthrough completions and clear the seam
        // hooks, so nothing the left-over schedule does later can roll a seam (review MINOR-3).
        stopEnhancedResampler()
        // If the engine still runs (the loss was seen before AVFAudio's own configuration change),
        // stop it so nothing plays on a fallback device. That may wait on the HAL as the player did —
        // here, where nothing the user sees waits on it.
        if let engine = avEngineRef, engine.isRunning {
            engine.stop()
        }
        // Again: a start that ran on this queue in between cleared the flag, and has just stopped too.
        storeInterruptedSignalPath()
        sampleTransport()
    }

    private func storeInterruptedSignalPath() {
        storeSignalPath(SignalPathInfo(path: .enhanced, decision: .fallbackEnhanced, interrupted: true))
    }

    // MARK: - Helpers

    /// Whether `deviceID` exists and reports itself alive. A device that has gone reads as an
    /// error (`kAudioHardwareBadObjectError`), so it counts as not alive.
    private static func isDeviceAlive(_ deviceID: UInt32) -> Bool {
        guard deviceID != 0 else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(deviceID), &address, 0, nil, &size, &alive)
        return status == noErr && alive != 0
    }

    private static func describe(_ facts: OutputDeviceFacts) -> String {
        "target=\(facts.target) alive=\(facts.targetAlive) default=\(facts.systemDefault) "
            + "playback=\(facts.playback) pinned=\(facts.pinned)"
    }
}

// MARK: - AudioPropertyListener

/// One CoreAudio property listener (global scope, main element), removable with the exact
/// (object, address, queue, block) it was added with: `AudioObjectRemovePropertyListenerBlock`
/// removes only on an exact match, so a re-derived queue or block would leak it (F5).
struct AudioPropertyListener {
    let objectID: AudioObjectID
    private let selector: AudioObjectPropertySelector
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock

    /// Add the listener; `handler` runs on `queue`. `nil` (logged) when CoreAudio refuses — e.g.
    /// the device is already gone.
    init?(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        queue: DispatchQueue,
        handler: @escaping @Sendable () -> Void
    ) {
        var address = Self.address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
        guard status == noErr else {
            NSLog("[OutputDevice] failed to add listener \(selector) on object \(objectID): \(status)")
            return nil
        }
        self.objectID = objectID
        self.selector = selector
        self.queue = queue
        self.block = block
    }

    /// Remove the listener. A non-zero status (the device is already gone) is harmless.
    func remove() {
        var address = Self.address(selector)
        AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
