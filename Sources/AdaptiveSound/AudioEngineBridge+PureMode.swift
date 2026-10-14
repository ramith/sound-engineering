@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import PlaybackQueueKit

// MARK: - AudioEngineBridge Pure-Mode methods (bit-perfect HAL path)

/// Pure-Mode orchestration: capability evaluation, engine lifecycle, transport routing,
/// and seek helpers. All stored properties (pureEngine, activePath,
/// cachedSignalPath, lastFileURL, currentDeviceID) live on the main class body
/// in AudioEngineBridge.swift (Swift extensions cannot add stored properties).
///
/// Device monitoring (the alive listener on the app's device, pause on device loss) is shared
/// with the Enhanced path in AudioEngineBridge+OutputDeviceMonitor.swift.
///
/// Concurrency: the transport entry points (`seek`) run on the serial `engineQueue`; the
/// internal helpers (`startPure`, `tearDownPure`, `stopEnhancedPlayback`) are called from there or
/// from other serial transport bodies, the device-loss pause included. Nothing here runs on the
/// audio thread.
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
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

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

        // 0 = FullBitPerfect, 1 = RateMatchedFloat are both viable. 2 = FallbackEnhanced → reject,
        // and the caller plays Enhanced with the "Pure unavailable" notice. The reason code follows
        // PureModeReason's order (PureModeBridge.h), e.g. 5 = the device stream's channel count is
        // not the file's.
        guard evaluation.decision != 2 else {
            NSLog("[PureMode] Not viable for \(fileURL.lastPathComponent) on device \(deviceID) "
                + "(policy reason \(evaluation.reason))")
            return false
        }
        return true
    }

    // MARK: - Pure Engine Start

    /// Create (lazily) and start the Pure-Mode engine. Returns `true` when the
    /// engine confirms `running == 1` in `pureModeEngineAchievedState`.
    ///
    /// - Parameters:
    ///   - fileURL:  The file to play (security-scoped access is managed here).
    ///   - deviceID: The CoreAudio device to open in exclusive / integer mode.
    ///   - startAt:  Where in the file to start, in seconds (a resume, a move to another device):
    ///               the source is positioned before render starts, so nothing from 0:00 is heard.
    /// - Returns: `true` on success; `false` on any failure (caller falls back to Enhanced).
    @discardableResult
    func startPure(fileURL: URL, deviceID: UInt32, startAt: Double) -> Bool {
        // Lazily create the engine session (create ONLY when the field is nil — the RT-safety
        // invariant). All pureEngine/activePath access goes through the stateLock accessors (S6
        // UAF-1). This runs on engineQueue, where every Pure call and teardown runs (the device-loss
        // one included), so none can free the session mid-start; the guarded writes only keep the
        // field consistent for the other queues' reads. We borrow the RAW `handle` (a POD pointer)
        // for the C-ABI calls; the FIELD remains the
        // sole strong owner of the wrapper, so a failure-path `detachPureEngineForTeardown()` drop is
        // the last reference and destroys deterministically OUTSIDE the lock.
        if pureEngineHandle == nil {
            setPureEngine(PureModeSession())
        }
        guard let engine = pureEngineHandle?.handle else {
            NSLog("[PureMode] pureModeEngineCreate returned nil")
            return false
        }

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        var startResult: Int32 = 0
        fileURL.path.withCString { pathPtr in
            startResult = pureModeEngineStart(engine, deviceID, pathPtr, max(startAt, 0))
        }

        guard startResult == 1 else {
            NSLog("[PureMode] pureModeEngineStart failed (result=\(startResult))")
            // activePath is still .enhanced (not set to .pure until below), so no poll is borrowing
            // this session. Detach (nils the field UNDER the lock) and let the returned wrapper drop
            // HERE on engineQueue — its deinit runs pureModeEngineDestroy OUTSIDE stateLock.
            detachPureEngineForTeardown()
            return false
        }

        let state = pureModeEngineAchievedState(engine)
        guard state.running == 1 else {
            NSLog("[PureMode] Engine started but running==0 — aborting Pure path")
            // Detach under the lock, stop() (control-plane), then let the returned wrapper drop at
            // the end of this statement — deinit → pureModeEngineDestroy, OUTSIDE stateLock.
            detachPureEngineForTeardown()?.stop()
            return false
        }

        // Publish the handle-then-path invariant: pureEngine is already set (above), so the instant
        // activePath becomes .pure a `withPureEngine` borrow finds it.
        setActivePath(.pure)
        var pureInfo = makeSignalPathInfo(from: state)
        // Master Gain shows the device's own volume on Pure: read it (never set it — engaging Pure must
        // not change how loud the device is) into the snapshot that turns the path Pure, and follow it.
        pureInfo.deviceVolume = watchDeviceVolume(deviceID: deviceID)
        storeSignalPath(pureInfo)
        // No listener of its own: Pure plays on the app's device, which the output monitor already
        // watches (and pauses for, on loss) on both paths.

        let info = pureInfo
        NSLog(
            "[PureMode] Started — decision=\(info.decision), " +
                "rate=\(state.achievedRate) Hz, bits=\(state.achievedBitsPerChannel), " +
                "hog=\(state.didHog), decoder=\(info.decoder as Any)"
        )
        return true
    }

    // MARK: - Seek

    /// Seek to `seconds` in the current file — the one seek entry, for both paths.
    ///
    /// First the one place rule (`SeekTarget`): a target that is not a number (NaN, ±∞) reaches no
    /// engine — it throws `AudioBridgeError.seekFailed` and playback carries on where it was; a
    /// negative target is 0. The request still begins its transport operation, so the view model's
    /// numbered tick hears back either way.
    ///
    /// Pure path: `pureModeEngineSeek` holds render (silence; the device keeps running), seeks the
    /// decoder and releases render; a place past the end lands at the end, which ends the track. A
    /// seek that did not move throws `seekFailed`.
    ///
    /// Enhanced path (`restartEnhanced`): the current file, from the place — or, at or past its end,
    /// the end of the track now (the snapshot's `ended`; the view model advances). It changes
    /// nothing until it knows it can play: a seek that can't (the file no longer opens) throws
    /// `seekFailed` and playback carries on where it was. Only with play intent: paused, stopped,
    /// ended or after a device loss the engine is stopped and there is nothing to move — where a
    /// paused song resumes is the view model's resume point (S10.8 G).
    ///
    /// `epoch` numbers the request (see `TransportSnapshot`): a transitional sample at the target is
    /// published first, so the view model's playhead never jumps back to the old place meanwhile.
    func seek(to seconds: Double, epoch: UInt64) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.engineQueue.async {
                let place = SeekTarget.place(seconds)
                self.beginTransportOperation(epoch: epoch, position: place)
                guard let place else {
                    logUX("engine seek: target=\(seconds) refused (not a place)")
                    self.sampleTransport() // the settled sample: still where it plays
                    continuation.resume(throwing: AudioBridgeError.seekFailed)
                    return
                }
                // Pure seek: `withPureEngine` borrows the session on engineQueue, where every Pure
                // call and teardown is serialized, and calls OUTSIDE stateLock (the seek waits for
                // a render pass and joins the decode thread). nil ⇒ not Pure ⇒ fall through to
                // Enhanced.
                if let result = self.withPureEngine({ pureModeEngineSeek($0, place) }) {
                    logUX("engine seek: path=Pure target=\(secs(place))s "
                        + "result=\(result == 1 ? "ok" : "failed(\(result))")")
                    // The settled sample: after a failed seek, the place it really plays from.
                    self.sampleTransport()
                    if result == 1 {
                        continuation.resume()
                    } else {
                        NSLog("[PureMode] seek to \(place)s failed — engine returned \(result)")
                        continuation.resume(throwing: AudioBridgeError.seekFailed)
                    }
                    return
                }

                guard self.enhancedPlayIntent, let player = self.playerNode, self.lastFileURL != nil else {
                    logUX("engine seek: path=Enhanced target=\(secs(place))s result=no-op (no file playing)")
                    self.sampleTransport()
                    continuation.resume()
                    return
                }
                let outcome = self.restartEnhanced(at: place, player: player)
                logUX("engine seek: path=Enhanced target=\(secs(place))s result=\(outcome)")
                self.sampleTransport()
                if outcome == .unchanged {
                    continuation.resume(throwing: AudioBridgeError.seekFailed)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Internal helpers

    /// Stop the Enhanced player node and AVAudioEngine without destroying the graph.
    /// Used when transitioning from Enhanced to Pure (keep the graph for fast fallback).
    func stopEnhancedPlayback() {
        // No longer intending to play the Enhanced path (deliberate stop, or handing the device to
        // Pure) — so a config/device change must not auto-resume it.
        enhancedPlayIntent = false
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
    func tearDownPure() {
        unwatchDeviceVolume()
        // Detach the session + reset activePath to .enhanced under stateLock, then do the SLOW HAL
        // teardown OUTSIDE the lock: `stop()` restores the device rate + releases hog, and dropping
        // the wrapper at the end of this block runs its deinit → pureModeEngineDestroy (joins the
        // decode thread). Every `withPureEngine` borrow runs on engineQueue too, so none is in
        // flight here, and a later one sees activePath == .enhanced and skips (S6 UAF-1).
        // detachPureEngineForTeardown is idempotent, so a second teardown (a stop after the
        // device-loss pause) cannot double-free (it gets nil). The drop runs on the caller's queue
        // (engineQueue — the device-loss pause included), never under stateLock.
        if let session = detachPureEngineForTeardown() {
            session.stop()
            // `session` drops at the end of this scope → deinit → pureModeEngineDestroy, OUTSIDE the
            // lock, on the caller's queue.
        }
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
            decoder: decoderUI,
            fellBackToEnhanced: false
        )
    }
}
