import AVFoundation
import CoreAudio
import Foundation

// MARK: - AudioEngineBridge Pure-Mode methods (bit-perfect HAL path)

/// Pure-Mode orchestration: capability evaluation, engine lifecycle, transport routing,
/// and seek helpers. All stored properties (pureEngine, activePath,
/// cachedSignalPath, lastFileURL, pureModeRequested, currentDeviceID,
/// deviceAliveListenerBlock, aliveListenerDeviceID) live on the main class body
/// in AudioEngineBridge.swift (Swift extensions cannot add stored properties).
///
/// Device-monitoring (the device-alive listener + pause-on-device-loss) lives in
/// AudioEngineBridge+PureModeDeviceMonitor.swift.
///
/// Concurrency: all methods are called from `DispatchQueue.global()` continuations,
/// matching the existing bridge pattern. The CoreAudio listener blocks dispatch
/// additional work on a dedicated global queue and are never called on the audio thread.
extension AudioEngineBridge {
    // MARK: - Capability Evaluation

    /// Returns `true` when the device + file combination can run in Pure mode
    /// (decision is FullBitPerfect or RateMatchedFloat). When this returns false,
    /// the caller falls back to the Enhanced path.
    func evaluatePureViable(fileURL: URL, deviceID: UInt32) -> Bool {
        // --- Query device capability ---
        var cap = CDeviceCapability()
        // Up to 16 advertised rates; USB DACs typically advertise ≤ 8.
        let maxRates: UInt32 = 16
        var rates = [Double](repeating: 0, count: Int(maxRates))
        var rateCount: UInt32 = 0

        let queryOK = pureModeQueryCapability(deviceID, &cap, &rates, maxRates, &rateCount)
        guard queryOK == 1 else {
            NSLog("[PureMode] pureModeQueryCapability failed for device \(deviceID)")
            return false
        }

        // --- Build CFileFormat from AVAudioFile ---
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
            NSLog("[PureMode] Cannot open file for capability evaluation: \(fileURL.lastPathComponent)")
            return false
        }

        let processingFormat = audioFile.processingFormat
        let streamDesc = processingFormat.streamDescription.pointee

        // Extract physical bit depth and float flag from the underlying stream description.
        // These inform the policy's integer / float branch but are not mandatory —
        // rate + device booleans drive the primary decision.
        let fileBits: UInt32 = streamDesc.mBitsPerChannel
        let fileIsFloat: UInt8 = (streamDesc.mFormatFlags & kAudioFormatFlagIsFloat) != 0 ? 1 : 0

        var fileFormat = CFileFormat(
            sampleRate: processingFormat.sampleRate,
            bitsPerChannel: fileBits,
            channels: processingFormat.channelCount,
            isFloat: fileIsFloat
        )

        // --- Evaluate policy ---
        var evaluation = CPureModeEvaluation()
        withUnsafePointer(to: &cap) { capPtr in
            rates.withUnsafeBufferPointer { ratesPtr in
                withUnsafePointer(to: &fileFormat) { filePtr in
                    pureModeEvaluate(capPtr, ratesPtr.baseAddress, rateCount, filePtr, &evaluation)
                }
            }
        }

        // 0 = FullBitPerfect, 1 = RateMatchedFloat are both viable. 2 = FallbackEnhanced → reject.
        return evaluation.decision != 2
    }

    // MARK: - Pure Engine Start

    /// Create (lazily) and start the Pure-Mode engine. Returns `true` when the
    /// engine confirms `running == 1` in `pureModeEngineAchievedState`.
    ///
    /// - Parameters:
    ///   - fileURL:  The file to play (security-scoped access is managed here).
    ///   - deviceID: The CoreAudio device to open in exclusive / integer mode.
    /// - Returns: `true` on success; `false` on any failure (caller falls back to Enhanced).
    @discardableResult
    func startPure(fileURL: URL, deviceID: UInt32) -> Bool {
        // Lazily create the engine handle; destroy any stale handle first.
        if pureEngine == nil {
            pureEngine = pureModeEngineCreate()
        }
        guard let engine = pureEngine else {
            NSLog("[PureMode] pureModeEngineCreate returned nil")
            return false
        }

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        var startResult: Int32 = 0
        fileURL.path.withCString { pathPtr in
            startResult = pureModeEngineStart(engine, deviceID, pathPtr)
        }

        guard startResult == 1 else {
            NSLog("[PureMode] pureModeEngineStart failed (result=\(startResult))")
            pureModeEngineDestroy(engine)
            pureEngine = nil
            return false
        }

        let state = pureModeEngineAchievedState(engine)
        guard state.running == 1 else {
            NSLog("[PureMode] Engine started but running==0 — aborting Pure path")
            pureModeEngineStop(engine)
            pureModeEngineDestroy(engine)
            pureEngine = nil
            return false
        }

        activePath = .pure
        cachedSignalPath = makeSignalPathInfo(from: state)

        // Register a device-alive listener for the device we just hogged.
        // Ordering invariant: register AFTER activePath is set to .pure so the
        // alive-listener's fallback fires only while we are actually in Pure mode.
        registerDeviceAliveListener(deviceID: deviceID)

        let info = cachedSignalPath
        NSLog(
            "[PureMode] Started — decision=\(info.decision), " +
                "rate=\(state.achievedRate) Hz, bits=\(state.achievedBitsPerChannel), " +
                "hog=\(state.didHog), decoder=\(info.decoder as Any)"
        )
        return true
    }

    // MARK: - Seek

    /// Seek to `seconds` in the current file.
    ///
    /// Pure path: `pureModeEngineSeek` stops render, seeks, restarts internally.
    ///
    /// Enhanced path: stops the player, reschedules the `AVAudioFile` from the
    /// target frame to end. For rate-mismatched files the streaming resampler is
    /// restarted from the target frame via `seekEnhancedResampler`.
    func seek(to seconds: Double) async {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if self.activePath == .pure, let engine = self.pureEngine {
                    let result = pureModeEngineSeek(engine, seconds)
                    logUX("engine seek: path=Pure target=\(secs(seconds))s "
                        + "result=\(result == 1 ? "ok" : "failed(\(result))")")
                    if result != 1 {
                        NSLog("[PureMode] seek to \(seconds)s failed — engine returned \(result)")
                    }
                    continuation.resume()
                    return
                }

                // Enhanced path: best-effort re-schedule.
                // Stops the player and reschedules from the target frame. Rate-mismatched files
                // use seekEnhancedResampler; 48 kHz passthrough files use seekEnhancedBestEffort.
                guard let player = self.playerNode,
                      let url = self.lastFileURL
                else {
                    logUX("engine seek: path=Enhanced "
                        + "target=\(secs(seconds))s result=no-op (no player/url)")
                    continuation.resume()
                    return
                }

                // The re-scheduled stream restarts the player's sampleTime at 0, so record the seek
                // target as the position base — currentPlaybackPosition adds it to report the true
                // playhead (otherwise the scrubber snaps to 0 and creeps forward after a seek).
                self.enhancedPositionBaseSeconds = max(seconds, 0)

                // If a streaming-resampler session is active (rate-mismatched file), restart the
                // resampler from the target frame (bumps the generation → abandons in-flight buffers,
                // resets the converter, re-primes + plays). Otherwise the 48 kHz `scheduleFile`
                // session uses the existing best-effort segment re-schedule (UNCHANGED).
                // Read resampleSession under the lock for a consistent branch decision (avoids a
                // TOCTOU race with primeEnhancedResamplerLocked / stopEnhancedResampler on
                // resampleQueue).
                let hasResampler = self.resampleQueue.sync { self.resampleSession != nil }
                if hasResampler {
                    let restarted = self.seekEnhancedResampler(to: seconds, player: player)
                    logUX("engine seek: path=Enhanced(resample) target=\(secs(seconds))s "
                        + "result=\(restarted ? "ok" : "failed")")
                } else {
                    self.seekEnhancedBestEffort(url: url, player: player, to: seconds)
                    logUX("engine seek: path=Enhanced target=\(secs(seconds))s result=ok")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Internal helpers

    /// Stop the Enhanced player node and AVAudioEngine without destroying the graph.
    /// Used when transitioning from Enhanced to Pure (keep the graph for fast fallback).
    func stopEnhancedPlayback() {
        // No longer intending to play the Enhanced path (deliberate stop, or handing the device to
        // Pure) — so a config/device change must not auto-resume it.
        // Write under resampleQueue (its designated owner). stopEnhancedResampler() also acquires
        // resampleQueue.sync internally; that's fine — they are sequential, not nested.
        resampleQueue.sync { enhancedPlayIntent = false }
        // Bump the generation + drop the session FIRST so no in-flight resampler buffer schedules
        // onto the player we're about to stop (or onto a graph we're about to hand to Pure mode).
        // stopEnhancedResampler also clears onResamplerEOF and onPassthroughEOF so no stale
        // gapless handlers can fire on the stopped / handed-off player.
        stopEnhancedResampler()
        if let player = playerNode, player.isPlaying {
            player.stop()
        }
        if let engine = avEngine, engine.isRunning {
            engine.stop()
        }
    }

    /// Stop and destroy the Pure-Mode engine. This releases hog mode and restores
    /// the device's nominal sample rate. Safe to call when pureEngine is nil.
    ///
    /// Invariant: `unregisterDeviceAliveListener()` is called first so no alive-listener
    /// callback fires after `pureEngine` is set to nil.
    func tearDownPure() {
        unregisterDeviceAliveListener()
        if let engine = pureEngine {
            pureModeEngineStop(engine)
            pureModeEngineDestroy(engine)
            pureEngine = nil
        }
        activePath = .enhanced
    }

    // MARK: - Private helpers

    /// Build a `SignalPathInfo` snapshot from a `CAchievedOutputState`.
    private func makeSignalPathInfo(from state: CAchievedOutputState) -> SignalPathInfo {
        let decisionUI: PureModeDecisionUI
        switch state.decision {
        case 0: decisionUI = .fullBitPerfect
        case 1: decisionUI = .rateMatchedFloat
        default: decisionUI = .fallbackEnhanced
        }
        let decoderUI: DecoderKindUI = state.decoderBackend == 1 ? .ffmpeg : .apple
        return SignalPathInfo(
            path: .pure,
            decision: decisionUI,
            achievedSampleRate: state.achievedRate,
            bitDepth: state.achievedBitsPerChannel,
            isFloat: state.achievedIsFloat == 1,
            exclusiveHog: state.didHog == 1,
            rateMatched: state.rateChanged == 1,
            decoder: decoderUI,
            fellBackToEnhanced: false
        )
    }

    /// Seek `player` to `seconds` by re-scheduling the remaining segment of `url`.
    ///
    /// Silently returns when the file cannot be opened or the target frame is out of range.
    /// Called from `seek(to:)` and `reestablishEnhancedAfterConfigChange` on the Enhanced path.
    ///
    /// S-2 / S-3 fix: the segment is scheduled with `completionCallbackType: .dataPlayedBack` so
    /// `onPassthroughEOF` fires at the end of the remaining content. Without this the armed
    /// on-deck track is never triggered after a seek or a device reconnect, silently killing the
    /// gapless chain. `onDeckURL` is intentionally NOT cleared here — a seek must NOT consume
    /// the armed next track. The hook is re-armed by whichever path set it (`setNextTrack`
    /// re-arms on the next call; the config-change path leaves the existing hook intact because
    /// `stopEnhancedResampler` is not called on the passthrough config-change branch).
    func seekEnhancedBestEffort(url: URL, player: AVAudioPlayerNode, to seconds: Double) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let audioFile = try? AVAudioFile(forReading: url) else { return }

        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return }

        let targetFrame = AVAudioFramePosition(seconds * sampleRate)
        let totalFrames = audioFile.length
        guard targetFrame >= 0, targetFrame < totalFrames else { return }

        let frameCount = AVAudioFrameCount(totalFrames - targetFrame)
        player.stop()
        audioFile.framePosition = targetFrame
        // swiftlint:disable:next line_length
        player.scheduleSegment(audioFile, startingFrame: targetFrame, frameCount: frameCount, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
            guard let self, let livePlayer = player else { return }
            self.resampleQueue.async { self.onPassthroughEOF?(livePlayer) }
        }
        player.play()
    }
}
