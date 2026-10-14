@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge playback transport

extension AudioEngineBridge {
    func startAudio(fileURL: URL?, pureMode: Bool, startAt: Double, epoch: UInt64) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.engineQueue.async {
                // First, before any slow work (a Pure rate change can take seconds): this start's
                // transitional sample — its place, no end flag — so the view model's next tick
                // never acts on the end of the playback this start replaces.
                self.beginTransportOperation(epoch: epoch, position: startAt > 0 ? startAt : nil)
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

        if let url = fileURL {
            // playFile emits the mode-specific "Enhanced started ... (passthrough|resample)"
            // line. Append only the Pure-fallback note here so it isn't double-logged.
            try playFile(at: url, engine: engine, playerNode: playerNode, startAt: startAt)
            if loadSignalPath().fellBackToEnhanced {
                logUX("Enhanced started '\(url.lastPathComponent)' (fell back from Pure)")
            }
        } else {
            playReferenceTone(on: playerNode)
            logUX("Enhanced started reference tone")
        }

        setActivePath(.enhanced)
        enhancedPlayIntent = true
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

    /// Open `fileURL`, drive the multichannel load sequence, then schedule + play it.
    ///
    /// Sequence: read N + the source channel layout from the opened file,
    /// `configureGraphForSource` (reconfigure the graph to N — a same-count no-op for stereo —
    /// THEN publish the layout tag to the kernel for correct BS.1770-5 weights), and only AFTER
    /// that stop the player + schedule + play. Reconfiguring before scheduling means the file is
    /// queued onto the graph already settled at its width. `startAt` (seconds) starts the file
    /// there — a resume from Pause, a move to another device — rather than playing from 0 and
    /// seeking.
    func playFile(at fileURL: URL, engine _: AVAudioEngine, playerNode: AVAudioPlayerNode,
                  startAt: Double = 0) throws {
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

        // 1. Read the source width N and (optional) layout tag from the processing format.
        let processingFormat = audioFile.processingFormat
        let channelCount = processingFormat.channelCount
        let channelLayout = processingFormat.channelLayout

        // 2. Reconfigure the graph to N, THEN publish the layout to the kernel. Stereo
        //    sources hit the same-count no-op, so the existing stereo path is unchanged.
        configureGraphForSource(channelCount: channelCount, channelLayout: channelLayout)

        // A fresh start: this file is the audible track now (the loudness-neutral EQ gain).
        trackBecameAudible(fileURL, gaplessSeam: false)

        // 3. Stop + reset the player before scheduling so the new file replaces (not queues after)
        //    the current one — ALWAYS, playing or not (S10.8 G): a node that is not playing can
        //    still hold a queued segment (one scheduled while its engine was stopped), and skipping
        //    the stop played it ahead of the new file. Also stop any prior streaming-resampler
        //    session first: that bumps both epochs, so its in-flight buffers abandon themselves and
        //    the `.dataPlayedBack` completions this stop fires don't roll a gapless seam.
        stopEnhancedResampler()
        playerNode.stop()
        // The player's sampleTime restarts at 0, so the position base is where the file starts
        // (0 on a fresh play; a later seek sets it to its target — see liveEnhancedPosition).
        let startFrame = Self.startFrame(startAt, in: audioFile)
        setEnhancedPositionBaseSeconds(Double(startFrame) / processingFormat.sampleRate)

        // 4. Branch on rate. When the file is already 48 kHz the existing `scheduleFile` path is an
        //    exact passthrough (the engine performs no SRC), so keep it BYTE-IDENTICAL. Only when the
        //    file rate differs from the 48 kHz graph rate do we engage the high-quality streaming
        //    resampler — bounding the new code's blast radius to rate-mismatched files. If the
        //    converter can't be created / primes nothing, fall back to `scheduleFile` (default SRC).
        let fileRate = processingFormat.sampleRate
        let graphRate = playerNode.outputFormat(forBus: 0).sampleRate
        if fileRate == graphRate {
            // 48 kHz passthrough: byte-identical to the pre-gapless path. The completion callback
            // type `.dataPlayedBack` fires after the hardware has played the last sample, which is
            // the correct seam point for gapless. When no next track is armed the handler is nil and
            // the player simply stops at end-of-file (pre-gapless behaviour, unchanged).
            //
            // NOTE: AVAudioFile / ExtAudioFile trims AAC priming silence and MP3 LAME
            // delay/padding via the file's edit list (kExtAudioFileProperty_ClientDataFormat +
            // kAFInfoDictionary_ApproximateDuration). Apple handles this automatically on this
            // path; we must NOT disable or override it. Pure/FFmpeg trim is Stage 2.
            // Capture the passthrough epoch this schedule is installed under (the
            // `stopEnhancedResampler()` above bumped it, abandoning any completion the
            // `playerNode.stop()` fired): a later stop/seek/reschedule bumps again, and this
            // completion must then abandon instead of rolling the gapless seam (wrong-song bug).
            let passthroughGen: UInt64 = resampleQueue.sync { passthroughGeneration }
            playerNode.scheduleSegment(
                audioFile,
                startingFrame: startFrame,
                frameCount: AVAudioFrameCount(audioFile.length - startFrame),
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self, weak playerNode] _ in
                guard let self, let livePlayer = playerNode else { return }
                self.resampleQueue.async {
                    guard passthroughGen == self.passthroughGeneration else { return } // superseded
                    self.firePassthroughEOFOrEnd(player: livePlayer)
                }
            }
            playerNode.play()
            logUX("Enhanced started '\(fileURL.lastPathComponent)' (\(Int(graphRate)) passthrough)")
            return
        }

        let started = startEnhancedResampler(audioFile: audioFile, player: playerNode, startFrame: startFrame)
        if started {
            logUX("Enhanced started '\(fileURL.lastPathComponent)' "
                + "(resample \(Int(fileRate))→\(Int(graphRate)) mastering)")
        } else {
            // Converter unavailable / primed nothing → keep playback working via the proven path.
            playerNode.scheduleSegment(audioFile, startingFrame: startFrame,
                                       frameCount: AVAudioFrameCount(audioFile.length - startFrame), at: nil)
            playerNode.play()
            logUX("Enhanced started '\(fileURL.lastPathComponent)' "
                + "(resample \(Int(fileRate))→\(Int(graphRate)) FELL BACK to default SRC)")
        }
    }

    func stopAudio(epoch: UInt64) async throws {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                self.beginTransportOperation(epoch: epoch, position: nil)
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

    /// The frame `seconds` falls on in `file`, kept inside the file (so a segment from it is never
    /// empty; a place at or past the end starts on the last frame and ends at once).
    private static func startFrame(_ seconds: Double, in file: AVAudioFile) -> AVAudioFramePosition {
        let rate = file.processingFormat.sampleRate
        guard seconds > 0, seconds.isFinite, rate > 0, file.length > 0 else { return 0 }
        return min(AVAudioFramePosition(seconds * rate), file.length - 1)
    }

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
