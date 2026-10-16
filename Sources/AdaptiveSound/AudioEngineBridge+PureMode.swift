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

    /// Why Pure can't play `fileURL` on `deviceID`, or nil when it can (decision FullBitPerfect or
    /// RateMatchedFloat). The file is read by Pure's own decoder — Apple first, FFmpeg only when it is
    /// on — so a file only FFmpeg reads is judged as Pure would play it, and one it can't is named
    /// (`fileUnreadable`, `needsFFmpeg`) rather than refused silently (`pureModeEvaluateFile`).
    func pureDeclineReason(fileURL: URL, deviceID: UInt32) -> PureModeReason? {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        var evaluation = CPureModeEvaluation()
        let filled = fileURL.path.withCString { pureModeEvaluateFile(deviceID, $0, &evaluation) }
        // 2 = FallbackEnhanced (PureModeBridge.h); 0 and 1 play.
        guard filled == 1, evaluation.decision == 2 else { return nil }
        let reason = PureModeReason(code: evaluation.reason) ?? .deviceWouldNotStart
        NSLog("[PureMode] Not viable for \(fileURL.lastPathComponent) on device \(deviceID): \(reason)")
        return reason
    }

    // MARK: - Pure Engine Start

    /// Create (lazily) and start the Pure-Mode engine. Returns nil when the engine confirms
    /// `running == 1` in `pureModeEngineAchievedState`, else why it would not start.
    ///
    /// - Parameters:
    ///   - fileURL:  The file to play (security-scoped access is managed here).
    ///   - deviceID: The CoreAudio device to open in exclusive / integer mode.
    ///   - startAt:  Where in the file to start, in seconds (a resume, a move to another device):
    ///               the source is positioned before render starts, so nothing from 0:00 is heard.
    /// - Returns: nil on success; on any failure the reason (the caller falls back to Enhanced).
    func startPure(fileURL: URL, deviceID: UInt32, startAt: Double) -> PureModeReason? {
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
            return .deviceWouldNotStart
        }

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        var startResult: Int32 = 0
        var reasonCode: UInt8 = 0
        fileURL.path.withCString { pathPtr in
            startResult = pureModeEngineStart(engine, deviceID, pathPtr, max(startAt, 0), &reasonCode)
        }

        guard startResult == 1 else {
            let reason = PureModeReason(code: reasonCode) ?? .deviceWouldNotStart
            NSLog("[PureMode] pureModeEngineStart failed: \(reason)")
            // activePath is still .enhanced (not set to .pure until below), so no poll is borrowing
            // this session. Detach (nils the field UNDER the lock) and let the returned wrapper drop
            // HERE on engineQueue — its deinit runs pureModeEngineDestroy OUTSIDE stateLock.
            detachPureEngineForTeardown()
            return reason
        }

        let state = pureModeEngineAchievedState(engine)
        guard state.running == 1 else {
            NSLog("[PureMode] Engine started but running==0 — aborting Pure path")
            // Detach under the lock, stop() (control-plane), then let the returned wrapper drop at
            // the end of this statement — deinit → pureModeEngineDestroy, OUTSIDE stateLock.
            detachPureEngineForTeardown()?.stop()
            return .deviceWouldNotStart
        }

        // Publish the handle-then-path invariant: pureEngine is already set (above), so the instant
        // activePath becomes .pure a `withPureEngine` borrow finds it.
        setActivePath(.pure)
        var pureInfo = makeSignalPathInfo(from: state)
        // Master Gain steers the device's own volume on Pure (`enterPureVolume` already lowered it by
        // the cut): read it into the snapshot that turns the path Pure — `.fixed` holds the slider at
        // 0 dB — and follow it, so the listener's own change is seen.
        pureInfo.deviceVolume = watchDeviceVolume(deviceID: deviceID)
        storeSignalPath(pureInfo)
        // No listener of its own: Pure plays on the app's device, which the output monitor already
        // watches (and pauses for, on loss) on both paths.

        let info = pureInfo
        NSLog(
            "[PureMode] Started — decision=\(info.decision), " +
                "rate=\(state.achievedRate) Hz, bits=\(state.achievedBitsPerChannel), " +
                "hog=\(state.didHog), decoder=\(info.decoder as Any), "
                + "\(info.pureReason.map { "\($0)" } ?? "bit-perfect")"
        )
        return nil
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
                // A seek a newer command overtook was meant for the playback that command replaced (or a
                // place a newer seek moved on from): dropped, not failed.
                guard self.beginTransportOperation(epoch: epoch, position: place) else {
                    continuation.resume()
                    return
                }
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

    /// Stop and destroy the Pure-Mode engine. This releases hog mode and restores the device's nominal
    /// sample rate — and, once the render has stopped, its own volume (`leavePureVolume`: Master Gain
    /// plays in the app again). Safe to call when pureEngine is nil.
    func tearDownPure() {
        defer { leavePureVolume() }
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
            sourceBitDepth: state.sourceBitsPerChannel,
            isFloat: state.achievedIsFloat == 1,
            decoder: decoderUI,
            pureReason: PureModeReason(code: state.reason) // 6: not bit-perfect (C-33); else nil
        )
    }
}
