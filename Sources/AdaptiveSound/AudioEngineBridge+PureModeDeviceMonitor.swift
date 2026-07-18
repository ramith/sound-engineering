@preconcurrency import AVFoundation
import CoreAudio
import Foundation

// MARK: - AudioEngineBridge Pure-Mode device monitoring (pause on output-device loss)

/// Model (founder decision): the app-selected device is authoritative (the picker sets the macOS
/// default), so the app does NOT chase external default-device changes. The only runtime resilience
/// we need is: if the device currently rendering disappears (e.g. a Bluetooth device disconnects),
/// PAUSE — never auto-jump to another device. The user re-picks a device and resumes.
///
/// Listener ordering invariant:
///   - `registerDeviceAliveListener` is called from `startPure` AFTER `activePath` is set to `.pure`.
///   - `tearDownPure` calls `unregisterDeviceAliveListener` BEFORE destroying the engine handle,
///     so no callback references a dangling pointer (it also clears `aliveListenerDeviceID`).
extension AudioEngineBridge {
    // MARK: - Device-alive listener

    /// Register a `kAudioDevicePropertyDeviceIsAlive` listener for the device Pure is rendering on.
    /// If that device disappears, pause playback. Called by `startPure` once the engine is running.
    func registerDeviceAliveListener(deviceID: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listenerQueue = DispatchQueue.global(qos: .userInteractive)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // P1-B: run the pause body on configChangeQueue so it SERIALIZES against
            // reestablishEnhancedAfterConfigChange (which also runs there). Routing both onto the
            // one serial queue establishes a happens-before: the `interrupted` write below is
            // visible to any later config-change reader on the same queue, so a disconnect cannot
            // race the re-establish into auto-resuming on a dead device.
            guard let self else { return }
            self.configChangeQueue.async { [weak self] in
                self?.pauseForDeviceLoss()
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
            aliveListenerQueue = listenerQueue // F5: remove on the EXACT queue we added on
        } else {
            NSLog("[PureMode] Failed to register device-alive listener for device \(deviceID): \(status)")
        }
    }

    func unregisterDeviceAliveListener() {
        guard let block = deviceAliveListenerBlock else { return }
        // Unregister from the device the listener was REGISTERED on (aliveListenerDeviceID), not
        // currentDeviceID, which may have moved on. A non-zero status (device already gone) is
        // harmless.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(aliveListenerDeviceID),
            &address,
            aliveListenerQueue ?? DispatchQueue.global(qos: .userInteractive), // F5: exact queue
            block
        )
        deviceAliveListenerBlock = nil
        aliveListenerDeviceID = 0
        aliveListenerQueue = nil
    }

    // MARK: - Pause on device loss

    /// Pause playback because the active output device disappeared. Tears Pure down (releasing the
    /// device), stops the Enhanced engine, and marks the signal path `interrupted` so the view model
    /// clears `isPlaying` and prompts the user to pick a device. Never hard-fails; never auto-jumps.
    /// Runs on `configChangeQueue` (re-dispatched from the alive-listener block) so it serializes
    /// against `reestablishEnhancedAfterConfigChange` on the same queue (P1-B).
    func pauseForDeviceLoss() {
        NSLog("[PureMode] Active output device disappeared — pausing playback")
        // Paused on purpose — a config change that the disconnect fires must not auto-resume.
        // P1-B: write enhancedPlayIntent through its OWNER (resampleQueue) — the same path every
        // other site uses — rather than directly off this queue. We are on configChangeQueue here
        // (off resampleQueue), so the sync is deadlock-safe.
        resampleQueue.sync { enhancedPlayIntent = false }
        tearDownPure() // stops + destroys the Pure engine, unregisters the alive listener
        // Belt-and-braces before the stop (review MINOR-3): normally Pure entry already
        // cleared the hooks + bumped the epochs, but if a queued device-loss callback races
        // a just-started Enhanced session, this player.stop() would fire a live-epoch
        // completion with an armed hook → a stale seam roll while "interrupted". Clearing
        // here makes the stop unconditionally roll-proof (configChangeQueue → sync is the
        // P1-B-safe direction).
        stopEnhancedResampler()
        if let player = playerNodeRef, player.isPlaying {
            player.stop()
        }
        if let engine = avEngineRef, engine.isRunning {
            engine.stop()
        }
        // activePath is .enhanced after tearDownPure; flag the interruption for the view model.
        // Guarded write so the MainActor poll and the configChangeQueue config-change reader see a
        // consistent snapshot; the leaf lock is released immediately (no call-out under it).
        storeSignalPath(SignalPathInfo(
            path: .enhanced,
            decision: .fallbackEnhanced,
            interrupted: true
        ))
    }
}
