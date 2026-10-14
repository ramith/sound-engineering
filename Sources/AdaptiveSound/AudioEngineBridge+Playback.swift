@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit

// MARK: - AudioEngineBridge playback transport

extension AudioEngineBridge {
    func startAudio(fileURL: URL?, pureMode: Bool, startAt requested: Double, epoch: UInt64) async throws {
        // The one place rule (`SeekTarget`): a start must start somewhere, so a place that is not a
        // number is the top. Pure and Enhanced both take it from here.
        let startAt = SeekTarget.place(requested) ?? 0
        return try await withCheckedThrowingContinuation { continuation in
            self.engineQueue.async {
                // First, before any slow work (a Pure rate change can take seconds): this start's
                // transitional sample — its place, no end flag — so the view model's next tick
                // never acts on the end of the playback this start replaces. A start a newer command
                // overtook is dropped: it never plays over what the user asked since.
                guard self.beginTransportOperation(epoch: epoch, position: startAt > 0 ? startAt : nil) else {
                    continuation.resume(returning: ())
                    return
                }
                // A new playback: an on-deck request made for an earlier one is stale from here on.
                self.onDeckGate.beginSession(epoch)
                do {
                    // Record the intent for the device-change fallback restart path.
                    self.setLastFileURL(fileURL)

                    // A fresh startAudio always begins a new playback context: clear the end-of-queue
                    // sentinel and the on-deck slot so the new play starts clean (the caller must
                    // re-arm on-deck after startAudio if it wants gapless from the first track).
                    // Written on resampleQueue, which owns the gapless state (the seam handlers run
                    // there). stopEnhancedResampler() below also acquires resampleQueue.sync; these
                    // two syncs are sequential (not nested) — safe.
                    self.resampleQueue.sync {
                        self.gaplessPlaybackEnded = false
                        self.onDeckURL = nil
                    }

                    // Try the Pure path first; if it fully starts we're done. Otherwise it records
                    // the fall-back flag and we continue to the Enhanced path below.
                    if self.attemptPureStart(fileURL: fileURL, pureMode: pureMode, startAt: startAt) {
                        self.loudnessAnalyzer.cancel(nil) // Pure Mode bypasses the EQ: no analysis
                    } else {
                        try self.startEnhancedPlayback(fileURL: fileURL, startAt: startAt)
                    }
                    self.startTransportClock()
                    // The settled sample, so the caller's next read (its seam baseline) is this start's.
                    self.sampleTransport()
                    continuation.resume(returning: ())
                } catch {
                    self.sampleTransport()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Attempt the Pure (bit-perfect HAL) path. Returns `true` when Pure fully started (the caller
    /// resumes its continuation and returns); `false` when the caller must continue to the Enhanced
    /// path. In all non-started cases it records the `fellBackToEnhanced` flag exactly as before.
    /// Runs on `engineQueue` (called directly from the `startAudio` body — no new dispatch, and the
    /// `resampleQueue.sync` sequencing inside `startPure`/`stopEnhancedPlayback` is unchanged).
    private func attemptPureStart(fileURL: URL?, pureMode: Bool, startAt: Double) -> Bool {
        // Attempt Pure path when requested, a file is provided, and capability allows.
        if pureMode, let url = fileURL {
            let viable = evaluatePureViable(fileURL: url, deviceID: currentDeviceID)
            if viable {
                // Tear down any live Enhanced playback before entering Pure
                // (keep the graph intact for fast fallback — just stop the player).
                stopEnhancedPlayback()
                let started = startPure(fileURL: url, deviceID: currentDeviceID, startAt: startAt)
                if started {
                    return true
                }
                // Pure engine started but achievedState.running == 0 → fall through
                // to Enhanced. Record that we fell back.
                NSLog("[AudioEngineBridge] Pure Mode start failed — falling back to Enhanced")
                mutateSignalPath { $0.fellBackToEnhanced = true }
            } else {
                mutateSignalPath { $0.fellBackToEnhanced = true }
            }
        } else {
            mutateSignalPath { $0.fellBackToEnhanced = false }
        }
        return false
    }

    /// Start (or re-establish) the Enhanced path: tear down any live Pure engine, start the AV
    /// engine + tap, schedule the file (or reference tone), and publish the Enhanced signal-path
    /// snapshot + play-intent. Runs on `engineQueue` (called directly from the `startAudio` body);
    /// `enhancedPlayIntent` is an atomic, set last.
    private func startEnhancedPlayback(fileURL: URL?, startAt: Double) throws {
        // If Pure was active, stop+destroy it before entering Enhanced
        // (releases hog mode + restores device rate).
        if activePathKind == .pure {
            tearDownPure()
        }

        // Enhanced path (original startAudio body).
        guard let engine = avEngine, let playerNode else {
            throw AudioBridgeError.engineNotInitialized
        }

        // The engine plays on the system default: make it the app's device first (pinned), or
        // take the default as the app's device (follow) — e.g. headphones connected while paused.
        alignOutputForEnhancedStart()

        if !engine.isRunning {
            // A device-loss pause leaves the player's schedule in place (stopping it then waits on
            // the dying device — the disconnect freeze); clear it before the engine renders again.
            playerNode.stop()
            try engine.start()
        }

        installSpectrumTap()
        // Every Enhanced start plays the Master Gain the inspector shows (G-GAIN-1). The player also
        // keeps its volume across graph reconnects; this makes the start not depend on that.
        applyMasterGain()

        // Whether anything plays: a start at or past the end of its file ends the track at once (the
        // end flag is up, the view model advances), and leaves no play intent for a device change to
        // resume.
        var playing = true
        if let url = fileURL {
            // playFile emits the mode-specific "Enhanced started ... (passthrough|resample)"
            // line. Append only the Pure-fallback note here so it isn't double-logged.
            playing = try playFile(at: url, engine: engine, playerNode: playerNode, startAt: startAt) != .ended
            if loadSignalPath().fellBackToEnhanced {
                logUX("Enhanced started '\(url.lastPathComponent)' (fell back from Pure)")
            }
        } else {
            playReferenceTone(on: playerNode)
            logUX("Enhanced started reference tone")
        }

        setActivePath(.enhanced)
        enhancedPlayIntent = playing
        let fellBack = loadSignalPath().fellBackToEnhanced
        // The device's actual output rate (the honest "device is running at" value, per the
        // field's doc + the D5 device-pill readout). Enhanced processes internally at the graph
        // rate; the outputNode format reflects the hardware, so a 48 kHz device reads "48 kHz".
        // Captured on the engine queue (engine settled + playing here) — the same store-time
        // discipline the Pure path uses via makeSignalPathInfo, never a MainActor engine read.
        storeSignalPath(SignalPathInfo(
            path: .enhanced,
            decision: .fallbackEnhanced,
            achievedSampleRate: engine.outputNode.outputFormat(forBus: 0).sampleRate,
            fellBackToEnhanced: fellBack
        ))
    }

    /// Open `fileURL`, drive the multichannel load sequence, then play it from `startAt` (seconds).
    ///
    /// Sequence: read N + the source channel layout from the opened file,
    /// `configureGraphForSource` (reconfigure the graph to N — a same-count no-op for stereo —
    /// THEN publish the layout tag to the kernel for correct BS.1770-5 weights), and only AFTER
    /// that place the start and play through the one Enhanced commit (`commitEnhanced`,
    /// AudioEngineBridge+EnhancedRestart). Reconfiguring first means the file is queued onto the graph
    /// already settled at its width, and its resampler converts to that width. `startAt` starts the
    /// file there — a resume from Pause, a move to another device — rather than playing from 0 and
    /// seeking; at or past the end, the track ends at once (`.ended`).
    @discardableResult
    func playFile(at fileURL: URL, engine _: AVAudioEngine, playerNode: AVAudioPlayerNode,
                  startAt: Double = 0) throws -> EnhancedRestart {
        // Establish security-scoped access for sandboxed macOS file access.
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw AudioBridgeError.unsupportedFormat(fileURL.pathExtension)
        }
        let processingFormat = audioFile.processingFormat
        guard let target = SeekTarget(seconds: startAt, length: audioFile.length,
                                      sampleRate: processingFormat.sampleRate)
        else {
            throw AudioBridgeError.unsupportedFormat(fileURL.pathExtension)
        }

        // 1. Reconfigure the graph to the source width N, THEN publish the layout to the kernel.
        //    Stereo sources hit the same-count no-op, so the existing stereo path is unchanged.
        configureGraphForSource(channelCount: processingFormat.channelCount,
                                channelLayout: processingFormat.channelLayout)

        // A fresh start: this file is the audible track now (the loudness-neutral EQ gain).
        trackBecameAudible(fileURL, gaplessSeam: false)

        // 2. A new playback: end the previous one's seam state (its EOF hooks; the caller re-arms
        //    the on-deck track after the start). The commit then supersedes and stops whatever the
        //    player holds — ALWAYS, playing or not (S10.8 G): a node that is not playing can still
        //    hold a queued segment (one scheduled while its engine was stopped), and skipping the
        //    stop played it ahead of the new file.
        stopEnhancedResampler()

        // 3. Route by rate (after the reconfigure: the player's format is the graph's new width) and
        //    play. A 48 kHz file plays straight through — the engine performs no SRC. Any other rate
        //    streams through the Mastering resampler.
        //
        //    NOTE: AVAudioFile / ExtAudioFile trims AAC priming silence and MP3 LAME delay/padding
        //    via the file's edit list. Apple handles this on both sub-paths; we must NOT disable or
        //    override it. Pure/FFmpeg trim is Stage 2.
        let route = enhancedRoute(for: audioFile, player: playerNode)
        let outcome = commitEnhanced(audioFile, route: route, at: target, player: playerNode)
        let label = route.label(fileRate: processingFormat.sampleRate,
                                graphRate: playerNode.outputFormat(forBus: 0).sampleRate)
        logUX("Enhanced started '\(fileURL.lastPathComponent)' (\(label))"
            + (outcome == .ended ? " — at or past its end: ended" : ""))
        return outcome
    }

    func stopAudio(epoch: UInt64) async throws {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                // A stop a newer command overtook (a Play after a Pause, a click after Stop) is dropped:
                // it never silences what the user asked for since.
                guard self.beginTransportOperation(epoch: epoch, position: nil) else {
                    continuation.resume()
                    return
                }
                // Nothing plays after a stop: every on-deck request made before it is stale.
                self.onDeckGate.beginSession(epoch)
                if self.activePathKind == .pure {
                    self.tearDownPure()
                } else {
                    self.stopEnhancedPlayback()
                }
                // Clear the on-deck slot and play-intent on user stop: a stop is a deliberate
                // abort, not an end-of-queue, so the armed next track must not silently begin
                // playing later. Serialized on resampleQueue so it cannot race with an in-flight
                // seam handler. Both writes are batched in one sync to avoid a second crossing.
                self.resampleQueue.sync {
                    self.onDeckURL = nil
                    self.enhancedPlayIntent = false
                }
                self.removeSpectrumTap()
                self.referenceToneBuffer = nil
                self.loudnessAnalyzer.cancel(nil) // a deliberate stop: nothing left to analyse
                self.setActivePath(.enhanced)
                self.storeSignalPath(.init())
                self.stopTransportClock() // nothing plays: the final sample below is the last
                self.sampleTransport()
                continuation.resume()
            }
        }
    }

    // MARK: - Private helpers

    /// Fallback path when no file is supplied: schedule a 1 kHz reference tone on the player.
    private func playReferenceTone(on playerNode: AVAudioPlayerNode) {
        referenceToneBuffer = generateReferenceTone(
            frequency: 1000.0,
            duration: 5.0,
            sampleRate: 48000.0
        )

        if let buffer = referenceToneBuffer {
            if !playerNode.isPlaying {
                playerNode.play()
            }
            playerNode.scheduleBuffer(buffer, at: nil)
        }
    }
}
