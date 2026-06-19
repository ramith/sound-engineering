import AVFoundation
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
            self?.configChangeQueue.async {
                guard let self, let engine = self.avEngine else { return }
                let intentSnap = self.resampleQueue.sync { self.enhancedPlayIntent }
                logUX("config-change fired: path=\(self.activePath == .pure ? "Pure" : "Enhanced") "
                    + "engineRunning=\(engine.isRunning) playerPlaying=\(self.playerNode?.isPlaying ?? false) "
                    + "intent=\(intentSnap) default=\(getDefaultOutputDeviceID()) "
                    + "selected=\(self.currentDeviceID)")
                // While Pure Mode owns the device (hog mode + a per-track nominal-rate change),
                // those very changes fire this notification. The Enhanced AVAudioEngine is
                // intentionally stopped and must NOT try to restart on the hogged device — doing so
                // fails with -10875 (invalid output HW format) and contends for the device. The
                // Pure path runs its own HAL engine; leave it alone. Device loss for the Pure path
                // is handled (paused) by the CoreAudio device-alive listener in
                // AudioEngineBridge+PureModeDeviceMonitor.swift.
                guard self.activePath != .pure else { return }
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

        guard wasPlaying, let player = playerNode else { return }

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
