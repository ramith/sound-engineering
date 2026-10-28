@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge configuration-change resilience

extension AudioEngineBridge {
    /// Resume rendering after a hardware configuration change (route / default-device / format
    /// change), which stops `AVAudioEngine` — otherwise the app silently goes quiet on a Bluetooth
    /// or USB change (incl. a device merely *connecting* and stealing the system default). Whether
    /// to restart, and on which device, is the output rule's call
    /// (AudioEngineBridge+OutputDeviceMonitor): a lost device pauses instead of carrying on from the
    /// fallback (break-it B3), a pinned device is put back as the default first (B4), Pure and idle
    /// are left alone (Pure runs its own HAL engine; an idle engine must not seize a device).
    func observeConfigurationChanges(of engine: AVAudioEngine) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.outputDeviceDidChange(.engineReconfigured)
        }
    }

    /// Re-establish the Enhanced path after a route / default-device / format change.
    ///
    /// A configuration change stops `AVAudioEngine` AND flushes every buffer queued on the player
    /// node. Restarting the engine + calling `play()` is enough for the 48 kHz `scheduleFile`
    /// passthrough, but it does NOT refill the streaming-resampler's `scheduleBuffer` chain (the
    /// completion chain that was feeding the player is broken when its buffers are flushed) — which
    /// is why a device switch on a rate-mismatched file went intermittently silent. So we re-drive
    /// the scheduler from the current playhead, reusing the seek machinery, on the now-current
    /// output device. Runs on `configChangeQueue`, called by the output rule
    /// (AudioEngineBridge+OutputDeviceMonitor) on a configuration change or a followed device.
    func reestablishEnhancedAfterConfigChange(engine: AVAudioEngine) {
        // Re-entrancy guard: a nested re-establish must early-return rather than run a second
        // restart that abandons the first re-prime → audible dropout. The flag and
        // all callers are confined to configChangeQueue — no atomics needed.
        guard !isReestablishing else {
            logUX("reestablish: skipping re-entrant call (already in progress)")
            return
        }
        isReestablishing = true
        defer { isReestablishing = false }

        // Use the durable play-INTENT, not `playerNode.isPlaying`: a reconfiguration (a device
        // connecting/disconnecting) can momentarily report the node as not-playing, and gating on
        // that left playback silently dead after e.g. a Bluetooth device connected mid-track.
        let wasPlaying = enhancedPlayIntent

        // Idle (nothing playing, or a deliberate stop): do NOT start the engine. A config change
        // ALSO fires when a device merely CONNECTS and steals the system default (e.g. a Bluetooth
        // headphone). Starting the idle AVAudioEngine here would seize that just-connected device —
        // route-flipping / disconnecting a BT headset the user isn't even playing to (the reported
        // "connect Sony WH-1000XM4 → it disconnects" bug). The engine is (re)started only when there
        // is a live play intent to resume; idle == engine-stopped is the launch invariant, and
        // nothing renders or meters when idle anyway. Guard MUST precede engine.start().
        guard wasPlaying, let player = playerNodeRef else {
            logUX("config-change: idle (no play intent) — leaving engine stopped, not seizing the device")
            return
        }

        // Capture the playhead BEFORE restarting (the player may stop reporting a render time across
        // the reconfiguration; `lastKnownEnhancedPositionSeconds` is the freshest reliable value).
        let resumePos = liveEnhancedPosition() ?? lastKnownEnhancedPositionSeconds

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                NSLog("[AudioEngineBridge] engine restart after configuration change failed: \(error)")
                return
            }
        }

        // Refresh the device rate: a config change can be a switch to a device running at a
        // different rate, so the stored Enhanced snapshot's achievedSampleRate would otherwise
        // go stale. One field only (mutate, not store) so pureReason/interrupted stand.
        // On configChangeQueue here — the engine is settled, so this outputNode read is safe.
        // Read the rate BEFORE taking the lock: the main thread takes `stateLock` every tick, and this
        // AVFAudio read waits on the engine's lock (the leaf-lock rule, AudioEngineBridge+SharedState).
        let deviceRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        mutateSignalPath { $0.achievedSampleRate = deviceRate }

        // Re-validate the play INTENT immediately before touching the player (break-it
        // MAJOR-2): a user Stop can complete on engineQueue between the read at the top of
        // this function and here — re-scheduling after a deliberate stop is zombie audio
        // under a stopped UI. The stop already tore playback down; undo our engine restart.
        let intentStillLive = enhancedPlayIntent
        guard intentStillLive else {
            engine.stop()
            logUX("config-change: play intent cleared mid-reestablish — engine stopped, not resuming")
            return
        }

        resumeEnhancedAfterReestablish(player: player, resumePos: resumePos)
    }

    /// The resume tail of `reestablishEnhancedAfterConfigChange` (split for the complexity
    /// limit when the intent re-check joined): play the current file again from the playhead, through
    /// the one Enhanced restart (`restartEnhanced`) — the same playback at the same place, its
    /// on-deck track still armed. Runs on `configChangeQueue` with the engine already restarted.
    private func resumeEnhancedAfterReestablish(player: AVAudioPlayerNode, resumePos: Double) {
        guard lastFileURL != nil else { return } // every start names its file: none, nothing played
        // The configuration change flushed the player's queue: only a re-schedule makes sound again.
        refreshOutputState() // M2: the planner re-plans protectively against the output as it is now (F5)
        let outcome = restartEnhanced(at: resumePos, player: player)
        if outcome == .unchanged {
            // The file no longer opens, so nothing can refill the player: end the track rather than
            // leave a silent player that still says "playing" (the view model advances or stops).
            endEnhancedTrackNow(player: player, reason: "re-establish: the file would not reopen")
        }
        logUX("Enhanced re-established after configuration change at \(secs(resumePos))s → \(outcome)")
    }
}
