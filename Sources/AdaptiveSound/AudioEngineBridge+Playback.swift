@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge playback transport

extension AudioEngineBridge {
    func startAudio(fileURL: URL?, pureMode: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.engineQueue.async {
                do {
                    // Record the intent for the device-change fallback restart path.
                    self.setLastFileURL(fileURL)

                    // A fresh startAudio always begins a new playback context: clear the end-of-queue
                    // sentinel and the on-deck slot so the new play starts clean (the caller must
                    // re-arm on-deck after startAudio if it wants gapless from the first track).
                    // P2-3: the 20 Hz VM timer can call playbackEnded() (which reads gaplessPlaybackEnded
                    // via resampleQueue.sync) concurrently with this startAudio body — write under
                    // resampleQueue to prevent a race. stopEnhancedResampler() below also acquires
                    // resampleQueue.sync; these two syncs are sequential (not nested) — safe.
                    self.resampleQueue.sync {
                        self.gaplessPlaybackEnded = false
                        self.onDeckURL = nil
                    }

                    // Try the Pure path first; if it fully starts we're done. Otherwise it records
                    // the fall-back flag and we continue to the Enhanced path below.
                    if self.attemptPureStart(fileURL: fileURL, pureMode: pureMode) {
                        continuation.resume(returning: ())
                        return
                    }

                    try self.startEnhancedPlayback(fileURL: fileURL)
                    continuation.resume(returning: ())
                } catch {
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
    private func attemptPureStart(fileURL: URL?, pureMode: Bool) -> Bool {
        // Attempt Pure path when requested, a file is provided, and capability allows.
        if pureMode, let url = fileURL {
            let viable = evaluatePureViable(fileURL: url, deviceID: currentDeviceID)
            if viable {
                // Tear down any live Enhanced playback before entering Pure
                // (keep the graph intact for fast fallback — just stop the player).
                stopEnhancedPlayback()
                let started = startPure(fileURL: url, deviceID: currentDeviceID)
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
    /// the `resampleQueue.sync` for `enhancedPlayIntent` is unchanged.
    private func startEnhancedPlayback(fileURL: URL?) throws {
        // If Pure was active, stop+destroy it before entering Enhanced
        // (releases hog mode + restores device rate).
        if activePathKind == .pure {
            tearDownPure()
        }

        // Enhanced path (original startAudio body).
        guard let engine = avEngine, let playerNode else {
            throw AudioBridgeError.engineNotInitialized
        }

        if !engine.isRunning {
            try engine.start()
        }

        installSpectrumTap()

        if let url = fileURL {
            // playFile emits the mode-specific "Enhanced started ... (passthrough|resample)"
            // line. Append only the Pure-fallback note here so it isn't double-logged.
            try playFile(at: url, engine: engine, playerNode: playerNode)
            if loadSignalPath().fellBackToEnhanced {
                logUX("Enhanced started '\(url.lastPathComponent)' (fell back from Pure)")
            }
        } else {
            playReferenceTone(on: playerNode)
            logUX("Enhanced started reference tone")
        }

        setActivePath(.enhanced)
        resampleQueue.sync { enhancedPlayIntent = true }
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
    /// queued onto the graph already settled at its width.
    func playFile(at fileURL: URL, engine _: AVAudioEngine, playerNode: AVAudioPlayerNode) throws {
        // Establish security-scoped access for sandboxed macOS file access.
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

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

        // 3. Stop + reset the player before scheduling so the new file replaces (not queues after)
        //    the current one. Also stop any prior streaming-resampler session (bumps the generation
        //    so its in-flight buffers abandon themselves) before this new track supersedes it.
        stopEnhancedResampler()
        if playerNode.isPlaying {
            playerNode.stop()
        }
        // Fresh play schedules the whole file from frame 0 → no position offset. (A later seek sets
        // this to the seek target; see currentPlaybackPosition.)
        setEnhancedPositionBaseSeconds(0)

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
            playerNode.scheduleFile(
                audioFile,
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

        let started = startEnhancedResampler(audioFile: audioFile, player: playerNode, startFrame: 0)
        if started {
            logUX("Enhanced started '\(fileURL.lastPathComponent)' "
                + "(resample \(Int(fileRate))→\(Int(graphRate)) max)")
        } else {
            // Converter unavailable / primed nothing → keep playback working via the proven path.
            playerNode.scheduleFile(audioFile, at: nil)
            playerNode.play()
            logUX("Enhanced started '\(fileURL.lastPathComponent)' "
                + "(resample \(Int(fileRate))→\(Int(graphRate)) FELL BACK to default SRC)")
        }
    }

    func stopAudio() async throws {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
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
                self.setActivePath(.enhanced)
                self.storeSignalPath(.init())
                continuation.resume()
            }
        }
    }

    func currentPlaybackPosition() -> Double? {
        // Route to the active path. `withPureEngine` reads the position C-ABI UNDER stateLock so a
        // concurrent teardown (engineQueue stop/shutdown OR configChangeQueue device-loss) cannot
        // free the handle mid-call (S6 UAF-1). Returns nil when not on the Pure path → fall through
        // to Enhanced.
        if let pos = withPureEngine({ pureModeEnginePositionSeconds($0) }) {
            return pos > 0 ? pos : nil
        }
        // Enhanced path: AVAudioPlayerNode's sampleTime counts from 0 at EACH play() — it is
        // time-since-play, not absolute file position. A seek does stop()+scheduleSegment(from:)+
        // play(), which restarts sampleTime at 0, so we add the seek target (enhancedPositionBaseSeconds,
        // 0 on a fresh play) to report the true playhead.
        guard let playerNode, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            return nil
        }
        let position = enhancedPositionBaseSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate
        // Cache the freshest reliable playhead for the config-change re-establish path.
        setLastKnownEnhancedPositionSeconds(position)
        return position
    }

    func setParameter(_ id: UInt32, value: Float) async throws {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                if id == 0 {
                    // Pure path: never apply software gain to the bit-perfect stream. Instead drive
                    // the device's HARDWARE master volume (analog/HW domain → stays bit-perfect), so
                    // the in-app slider controls volume even without exclusive hog mode. A device with
                    // no settable master volume returns 0 (volume then via the OS / device only).
                    if self.activePathKind == .pure {
                        // Volume routing is logged once at the view-model layer (coalesced); not
                        // here — setParameter fires per slider tick and would spam the log.
                        _ = pureModeSetDeviceVolume(self.currentDeviceID, value)
                        continuation.resume()
                        return
                    }
                    // Enhanced path: master gain parameter → player node volume.
                    if let playerNode = self.playerNode {
                        playerNode.volume = value
                    }
                }
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
