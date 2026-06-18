import AVFoundation
import CoreAudio
import Foundation

// MARK: - AudioEngineBridge Pure-Mode device monitoring (CoreAudio listeners + fallback)

/// CoreAudio property-listener registration and the device-change / device-alive handlers
/// that implement Pure-Mode's runtime resilience. Extracted from `AudioEngineBridge+PureMode.swift`
/// so that the orchestration (evaluation, engine lifecycle, transport) and the monitoring
/// (listener setup + event handling + fallback) each occupy a focused, reviewable file.
///
/// Listener ordering invariant:
///   - `registerDeviceAliveListener` is called from `startPure` AFTER `activePath` is set
///     to `.pure`, so the alive callback's `fallBackToEnhanced` fires only while truly in
///     Pure mode.
///   - `tearDownPure` calls `unregisterDeviceAliveListener` BEFORE destroying the engine
///     handle, so no callback references a dangling pointer.
extension AudioEngineBridge {
    // MARK: - Default-output-device change listener

    /// Register an `AudioObjectPropertyListenerBlock` on `kAudioObjectSystemObject` for
    /// `kAudioHardwarePropertyDefaultOutputDevice`. When the default output device changes
    /// while Pure mode is active the bridge re-evaluates capability and either:
    ///   - falls back to Enhanced (capability lost), or
    ///   - restarts Pure on the new device (capability retained).
    ///
    /// Registration happens at `initialize()` time and the listener is removed in `shutdown()`.
    func registerDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listenerQueue = DispatchQueue.global(qos: .userInteractive)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            listenerQueue.async {
                guard let self else { return }
                self.handleDefaultDeviceChanged()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            block
        )
        if status == noErr {
            defaultDeviceListenerBlock = block
        } else {
            NSLog("[PureMode] Failed to register default-device listener: \(status)")
        }
    }

    func unregisterDeviceChangeListener() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.global(qos: .userInteractive),
            block
        )
        defaultDeviceListenerBlock = nil
    }

    // MARK: - Device-alive listener

    /// Register a `kAudioDevicePropertyDeviceIsAlive` listener for the currently hogged device.
    /// If the device disappears while we hold hog mode, fall back to Enhanced immediately.
    ///
    /// Called by `startPure` immediately after the engine achieves its running state.
    /// `unregisterDeviceAliveListener` must be called before the engine handle is destroyed.
    func registerDeviceAliveListener(deviceID: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listenerQueue = DispatchQueue.global(qos: .userInteractive)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            listenerQueue.async {
                guard let self else { return }
                NSLog("[PureMode] Hogged device disappeared — forcing Enhanced fallback")
                self.fallBackToEnhanced(position: 0)
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(deviceID),
            &address,
            listenerQueue,
            block
        )
        if status == noErr {
            deviceAliveListenerBlock = block
            aliveListenerDeviceID = deviceID
        } else {
            NSLog("[PureMode] Failed to register device-alive listener for device \(deviceID): \(status)")
        }
    }

    func unregisterDeviceAliveListener() {
        guard let block = deviceAliveListenerBlock else { return }
        // Unregister from the device the listener was REGISTERED on (aliveListenerDeviceID), NOT
        // currentDeviceID — a default-device change updates currentDeviceID to the new device
        // before teardown, so using it here would remove from the wrong device and leak the old
        // listener. If the device is already gone the remove may return non-zero — harmless.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(aliveListenerDeviceID),
            &address,
            DispatchQueue.global(qos: .userInteractive),
            block
        )
        deviceAliveListenerBlock = nil
        aliveListenerDeviceID = 0
    }

    // MARK: - Default-device change handler

    /// Called on a global queue when the CoreAudio default output device changes.
    /// Never hard-fails: any failure produces an Enhanced fallback.
    private func handleDefaultDeviceChanged() {
        let newDeviceID = getDefaultOutputDeviceID()
        guard newDeviceID != 0 else { return }

        // Update the stored device ID regardless of the active path.
        let previousDeviceID = currentDeviceID
        currentDeviceID = newDeviceID

        guard activePath == .pure, let url = lastFileURL else {
            // Enhanced path or no file: nothing to re-route.
            return
        }

        // If the device didn't actually change (spurious notification), skip.
        guard newDeviceID != previousDeviceID else { return }

        NSLog("[PureMode] Default device changed \(previousDeviceID) → \(newDeviceID) while Pure is active")

        // Save position before tearing down.
        let savedPosition: Double = pureEngine.map { pureModeEnginePositionSeconds($0) } ?? 0

        // Re-evaluate capability for the new device.
        let viable = evaluatePureViable(fileURL: url, deviceID: newDeviceID)
        if viable {
            // New device can run Pure: tear down the old engine, start on the new one.
            tearDownPure()
            let started = startPure(fileURL: url, deviceID: newDeviceID)
            if started {
                // Seek to the saved position on the new engine.
                if savedPosition > 0, let engine = pureEngine {
                    let result = pureModeEngineSeek(engine, savedPosition)
                    if result != 1 {
                        NSLog("[PureMode] Seek after device-change failed")
                    }
                }
                NSLog("[PureMode] Re-routed to new device \(newDeviceID) — Pure maintained")
                return
            }
            // Pure start failed on new device — fall through to Enhanced.
            NSLog("[PureMode] Pure re-start on new device failed — falling back to Enhanced")
        } else {
            NSLog("[PureMode] New device \(newDeviceID) not Pure-capable — falling back to Enhanced")
        }

        fallBackToEnhanced(position: savedPosition)
    }

    // MARK: - Enhanced fallback

    /// Tear down Pure, start the Enhanced path, and seek to `position`.
    /// Never hard-fails — any individual step failure is logged and skipped.
    ///
    /// Called from both `handleDefaultDeviceChanged` (device swap) and the
    /// device-alive listener (device removal). After this returns, `activePath == .enhanced`
    /// and `cachedSignalPath.fellBackToEnhanced == true`.
    func fallBackToEnhanced(position: Double) {
        tearDownPure()

        guard let url = lastFileURL,
              let engine = avEngine,
              let player = playerNode
        else {
            NSLog("[PureMode] fallBackToEnhanced: engine/player not available")
            return
        }

        do {
            if !engine.isRunning {
                try engine.start()
            }
            installSpectrumTap()
            try playFile(at: url, engine: engine, playerNode: player)
            activePath = .enhanced
            cachedSignalPath = SignalPathInfo(
                path: .enhanced,
                decision: .fallbackEnhanced,
                fellBackToEnhanced: true
            )
            NSLog("[PureMode] Enhanced fallback active — attempting seek to \(position)s")
            // Best-effort seek to the saved position (Enhanced seek is best-effort per spec).
            if position > 0 {
                seekEnhancedBestEffort(url: url, player: player, to: position)
            }
        } catch {
            NSLog("[PureMode] fallBackToEnhanced error: \(error)")
        }
    }
}
