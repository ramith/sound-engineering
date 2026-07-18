@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge configuration-change resilience

extension AudioEngineBridge {
    /// Resume rendering after a hardware configuration change (route / default-device / format
    /// change), which stops `AVAudioEngine` — otherwise the app silently goes quiet on a Bluetooth
    /// or USB change (incl. a device merely *connecting* and stealing the system default).
    func observeConfigurationChanges(of engine: AVAudioEngine) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.configChangeQueue.async {
                guard let engine = self.avEngineRef else { return }
                let intentSnap = self.resampleQueue.sync { self.enhancedPlayIntent }
                logUX("config-change fired: path=\(self.activePathKind == .pure ? "Pure" : "Enhanced") "
                    + "engineRunning=\(engine.isRunning) playerPlaying=\(self.playerNodeRef?.isPlaying ?? false) "
                    + "intent=\(intentSnap) default=\(getDefaultOutputDeviceID()) "
                    + "selected=\(self.currentDeviceID)")
                // While Pure Mode owns the device (hog mode + a per-track nominal-rate change),
                // those very changes fire this notification. The Enhanced AVAudioEngine is
                // intentionally stopped and must NOT try to restart on the hogged device — doing so
                // fails with -10875 (invalid output HW format) and contends for the device. The
                // Pure path runs its own HAL engine; leave it alone. Device loss for the Pure path
                // is handled (paused) by the CoreAudio device-alive listener in
                // AudioEngineBridge+PureModeDeviceMonitor.swift.
                guard self.activePathKind != .pure else { return }
                // After a device-loss pause we are intentionally stopped — don't auto-restart on the
                // config change that the disconnect itself fires. Cleared on the next startAudio.
                guard !self.loadSignalPath().interrupted else { return }
                self.reestablishEnhancedAfterConfigChange(engine: engine)
            }
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
    /// output device. Runs on `configChangeQueue` (serialized — see `observeConfigurationChanges`).
    /// Internal (not private) so the device-set handler in `AudioEngineBridge+Devices.swift` can
    /// drive a re-establish when "follow the newly-connected device" mode adopts a new default.
    func reestablishEnhancedAfterConfigChange(engine: AVAudioEngine) {
        // Re-entrancy guard: a FOLLOW-mode device connect dispatches one re-establish explicitly
        // (handleDeviceSetChange) AND causes AVAudioEngineConfigurationChange to fire a second one
        // on the same configChangeQueue serial queue. The second call must early-return to prevent
        // a double seekEnhancedResampler that abandons the first re-prime → audible dropout.
        // Both this flag and all callers are confined to configChangeQueue — no atomics needed.
        guard !isReestablishing else {
            logUX("reestablish: skipping re-entrant call (already in progress)")
            return
        }
        isReestablishing = true
        defer { isReestablishing = false }

        // Use the durable play-INTENT, not `playerNode.isPlaying`: a reconfiguration (a device
        // connecting/disconnecting) can momentarily report the node as not-playing, and gating on
        // that left playback silently dead after e.g. a Bluetooth device connected mid-track.
        // Read under resampleQueue (its designated owner) for a consistent snapshot.
        let wasPlaying = resampleQueue.sync { enhancedPlayIntent }

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
        let resumePos = currentPlaybackPosition() ?? lastKnownEnhancedPositionSeconds

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
        // go stale. One field only (mutate, not store) so fellBackToEnhanced/interrupted stand.
        // On configChangeQueue here — the engine is settled, so this outputNode read is safe.
        mutateSignalPath { $0.achievedSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate }

        // Re-validate the play INTENT immediately before touching the player (break-it
        // MAJOR-2): a user Stop can complete on engineQueue between the read at the top of
        // this function and here — re-scheduling after a deliberate stop is zombie audio
        // under a stopped UI. The stop already tore playback down; undo our engine restart.
        let intentStillLive = resampleQueue.sync { enhancedPlayIntent }
        guard intentStillLive else {
            engine.stop()
            logUX("config-change: play intent cleared mid-reestablish — engine stopped, not resuming")
            return
        }

        resumeEnhancedAfterReestablish(player: player, resumePos: resumePos)
    }

    /// The resume tail of `reestablishEnhancedAfterConfigChange` (split for the complexity
    /// limit when the intent re-check joined): re-prime/re-schedule from the playhead per
    /// sub-path. Runs on `configChangeQueue` with the engine already restarted.
    private func resumeEnhancedAfterReestablish(player: AVAudioPlayerNode, resumePos: Double) {
        // Read resampleSession under the queue's lock so the branch decision is consistent with
        // any in-flight mutation on resampleQueue (avoids a TOCTOU race with seekEnhancedResampler
        // or primeEnhancedResamplerLocked running concurrently).
        let hasResampler = resampleQueue.sync { resampleSession != nil }

        if hasResampler {
            // Rate-mismatched file: re-prime the streaming resampler from the playhead. (engine.start()
            // + play() alone leave the flushed buffer queue empty → silence.)
            if !seekEnhancedResampler(to: resumePos, player: player), !player.isPlaying {
                player.play()
            }
        } else if let url = lastFileURL {
            // 48 kHz passthrough: re-schedule the remaining segment from the playhead onto the new
            // device, guaranteeing fresh buffers regardless of whether the old schedule survived.
            seekEnhancedBestEffort(url: url, player: player, to: resumePos)
        } else if !player.isPlaying {
            player.play() // reference tone / no source file
        }
        setEnhancedPositionBaseSeconds(resumePos)
        logUX("Enhanced re-established after configuration change at \(secs(resumePos))s")
    }
}
