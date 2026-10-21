import AudioDSP
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
/// adopt the default (follow, or the chosen device away) or the chosen device back, put the chosen
/// device back as the default (pinned), restart the Enhanced engine. The rule moves only the target;
/// the device the user chose moves only with the user (`OutputDeviceSelection`). The view model is
/// then told to re-read the device state (`refreshDevices`), which is where the pill, the per-output
/// EQ, the limiter ceiling and the crossfeed check follow, and where a Pure session moves to a new
/// device.
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
            self?.returnPureVolumeLoansOnReappearance() // a device Pure lowered may be back (H-3)
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

    /// Change the app's output devices (a pick, an adopt, an undone pick) and watch the target for
    /// going away. `change` runs under the leaf lock (`updateOutputSelection`). Any queue.
    func changeOutputSelection<T>(_ change: (inout OutputDeviceSelection) -> T) -> T {
        let result = updateOutputSelection(change)
        configChangeQueue.async { [weak self] in
            self?.bindTargetAliveListener()
        }
        // Pure is left on a device the output moved away from (a pause on a DAC, then a pick of the
        // speakers): its own level comes back. While Pure renders, its restart on the new device does
        // that, after the old render stopped (`enterPureVolume`).
        engineQueue.async { [weak self] in
            guard let self, activePathKind != .pure else { return }
            pureVolumeEvent(.outputMoved(toUID: Self.deviceUID(currentDeviceID)))
        }
        return result
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
            self?.targetAliveDidChange(target)
        }
    }

    /// The app's device reported a change of its alive state. While something plays on it, that
    /// change is its death (a device we play on is alive), so pause FIRST, right here, before any
    /// HAL read: the reads on a dying device can wait seconds behind macOS's teardown, and the
    /// play intent and `interrupted` are a non-blocking atomic and a leaf-locked store (review M1;
    /// SFBAudioEngine clears its play flags first too). The output rule then runs as for any event,
    /// on `configChangeQueue`, to adopt the new default and confirm.
    private func targetAliveDidChange(_ device: UInt32) {
        if device == currentDeviceID, enhancedPlayIntent || activePathKind == .pure {
            pauseForDeviceLoss()
        }
        outputDeviceDidChange(.targetAliveChanged)
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

    /// Adopt a new target and/or put the (new) target back as the system default. An adopt moves
    /// the target only: the device the user chose stays the choice. The default change this causes
    /// comes back as `.defaultChanged` with the default already on the app's device, which the rule
    /// answers with nothing — so the app's own changes don't loop.
    private func applyTargetChange(_ action: OutputDeviceAction, facts: OutputDeviceFacts) {
        if let adopted = action.adoptTarget {
            let uid = Self.deviceUID(adopted)
            changeOutputSelection { $0.adopt(adopted, uid: uid) }
        }
        if action.reassertTarget {
            // Best effort (selectOutputDeviceC logs a refused default, e.g. a device that can't be one).
            let target = action.adoptTarget ?? facts.target
            let reasserted = selectOutputDeviceC(target) != 0
            logUX("output: re-assert \(target) as default \(reasserted ? "ok" : "failed (device gone?)")")
        }
    }

    /// The facts the rule decides from, read now. Any bridge queue except `resampleQueue`.
    private func readOutputDeviceFacts() -> OutputDeviceFacts {
        let selection = outputSelection
        let playback: OutputPlayback
        if activePathKind == .pure {
            playback = .pure
        } else {
            playback = enhancedPlayIntent ? .enhanced : .idle
        }
        return OutputDeviceFacts(
            target: selection.target,
            targetAlive: Self.isDeviceAlive(selection.target),
            systemDefault: getDefaultOutputDeviceID(),
            playback: playback,
            pinned: selection.pinned,
            chosen: Self.liveDevice(uid: selection.chosenUID)
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
    /// never carry on from another device), on Enhanced and Pure alike. From any queue — the alive
    /// listener's (first) or `configChangeQueue` (the output rule) — and once: a second call finds
    /// the pause already published. The play intent and the `interrupted` flag are set here, first,
    /// with no HAL call and no wait, so every later event sees nothing playing and restarts nothing
    /// (P1-B); the view model reads `interrupted`, clears `isPlaying` and keeps the song's place.
    /// The engines stop on `engineQueue`, serialized with start / seek / stop, so this can't free a
    /// Pure session that a start is using.
    private func pauseForDeviceLoss() {
        guard !loadSignalPath().interrupted else { return }
        logUX("output device lost during playback — pausing")
        enhancedPlayIntent = false
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
        pureVolumeEvent(.deviceLost) // nothing asked of a dying device: its loan stays held
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
        stopTransportClock() // nothing plays: the final sample below is the last
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

    /// The chosen device, found by its UID, when it is here to play on: alive, and listed by the
    /// device menu's own rule (`isListedOutputDeviceC` — a Bluetooth device mid-handshake has no
    /// output stream yet). 0 if not, or no UID. Its id may differ from the one it had when chosen: a
    /// reconnect can give a device a new id, never a new UID.
    private static func liveDevice(uid: String) -> UInt32 {
        guard let deviceID = deviceID(forUID: uid) else { return 0 }
        return OutputDevicePolicy.chosenDevice(deviceID, alive: isDeviceAlive(deviceID),
                                               listed: isListedOutputDeviceC(deviceID) != 0)
    }

    /// The device with this UID as it is connected now (`kAudioHardwarePropertyTranslateUIDToDevice`),
    /// or nil when none is — a reconnect can give a device a new id, never a new UID. A HAL read: off
    /// the main thread.
    static func deviceID(forUID uid: String) -> AudioObjectID? {
        guard !uid.isEmpty else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var qualifier = uid as CFString
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), uidPointer, &size, &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func describe(_ facts: OutputDeviceFacts) -> String {
        "target=\(facts.target) alive=\(facts.targetAlive) default=\(facts.systemDefault) "
            + "playback=\(facts.playback) pinned=\(facts.pinned) chosen=\(facts.chosen)"
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
