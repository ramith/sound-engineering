@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - Enhanced seek on the real bridge (council C-25, KI-PB-18; R1.1-A, US-R1F-11)

//
// The scrubber sends `seek(to: dragFraction * duration)`; at the end that is `seconds == duration`,
// which truncated to the file's length and was refused — after the position base had moved and the
// resampler's chain had been abandoned: silence that never ended, a playhead counting past the
// duration (P3 breaker D37, 93 % of track lengths). These run the real bridge on an offline engine
// (`EnhancedTransportRig`) on BOTH Enhanced sub-paths and read what the view model reads.

@Suite("Enhanced seek — the real bridge, both sub-paths (C-25)", .serialized)
struct EnhancedSeekTests {
    typealias SubPath = EnhancedTransportRig.SubPath

    /// Whether a seek threw "did not move" (`AudioBridgeError.seekFailed`).
    static func isSeekFailed(_ error: Error?) -> Bool {
        if case .seekFailed? = error as? AudioBridgeError {
            return true
        }
        return false
    }

    // MARK: The end

    @Test("a seek to exactly the end ends the track: the end flag, then silence, never past the end",
          arguments: SubPath.allCases)
    func seekToTheEndEndsTheTrack(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "seek-end")
        _ = try await rig.render(seconds: 0.3)
        let (error, epoch) = await rig.seek(to: rig.duration) // the scrubber at 100 %
        #expect(error == nil)
        let transport = rig.transport
        #expect(transport.isCurrent(for: epoch))
        #expect(transport.ended, "the track must end, so the view model advances or stops")
        let after = try #require(await rig.render(seconds: 0.6, skipping: 0.1))
        #expect(after < EnhancedTransportRig.silence, "nothing of the track plays after its end")
        #expect(rig.bridge.gaplessPlaybackEnded)
        #expect((rig.position ?? 0) <= rig.duration, "the playhead never runs past the end")
        await rig.finish()
    }

    @Test("a seek past the end ends the track too", arguments: SubPath.allCases)
    func seekPastTheEndEndsTheTrack(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "seek-past-end")
        _ = try await rig.render(seconds: 0.3)
        let (error, _) = await rig.seek(to: rig.duration + 7.5)
        #expect(error == nil)
        #expect(rig.transport.ended)
        let after = try #require(await rig.render(seconds: 0.4, skipping: 0.1))
        #expect(after < EnhancedTransportRig.silence)
        await rig.finish()
    }

    @Test("a seek to the end with a track on deck still ends this one: no seam, the view model starts the next",
          arguments: SubPath.allCases)
    func seekToTheEndWithATrackOnDeck(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "seek-end-armed")
        await rig.bridge.setNextTrack(rig.url, ticket: OnDeckTicket(session: 0, sequence: 1))
        _ = try await rig.render(seconds: 0.3)
        let seams = rig.transport.transitionCount
        let (error, _) = await rig.seek(to: rig.duration)
        #expect(error == nil)
        #expect(rig.transport.ended)
        #expect(rig.transport.transitionCount == seams)
        let after = try #require(await rig.render(seconds: 0.6, skipping: 0.1))
        #expect(after < EnhancedTransportRig.silence, "the next track is the view model's fresh start")
        await rig.finish()
    }

    // MARK: Not a place

    @Test("a target that is not a number is refused, and playback carries on exactly where it was",
          arguments: SubPath.allCases, [Double.nan, .infinity, -.infinity])
    func nonFiniteTargetIsRefused(_ path: SubPath, _ target: Double) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "seek-nonfinite")
        _ = try await rig.render(seconds: 0.25)
        let before = try #require(rig.position)
        let (error, epoch) = await rig.seek(to: target)
        #expect(Self.isSeekFailed(error), "the engine says the seek did not happen")
        #expect(rig.transport.isCurrent(for: epoch), "a refused seek still answers its request")
        #expect(!rig.transport.ended)
        let playing = try #require(await rig.render(seconds: 0.15))
        #expect(playing > 0.01, "still playing")
        let after = try #require(rig.position)
        #expect(abs(after - (before + 0.15)) < 0.02, "the playhead did not move: \(before) → \(after)")
        await rig.finish()
    }

    @Test("a negative target plays from the top", arguments: SubPath.allCases)
    func negativeTargetPlaysFromTheTop(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "seek-negative")
        _ = try await rig.render(seconds: 0.4)
        let (error, _) = await rig.seek(to: -3)
        #expect(error == nil)
        let playing = try #require(await rig.render(seconds: 0.2))
        #expect(playing > 0.01)
        let after = try #require(rig.position)
        #expect(abs(after - 0.2) < 0.02, "from 0:00: \(after)")
        #expect(!rig.transport.ended)
        await rig.finish()
    }

    // MARK: Transactional

    @Test("a seek that cannot reopen the file changes nothing: same place, same sound",
          arguments: SubPath.allCases)
    func failedSeekLeavesPlaybackAsItWas(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "seek-unreadable")
        _ = try await rig.render(seconds: 0.25)
        let before = try #require(rig.position)
        try FileManager.default.removeItem(at: rig.url) // the open handle plays on; a reopen fails
        let (error, _) = await rig.seek(to: 1.0)
        #expect(Self.isSeekFailed(error))
        #expect(!rig.transport.ended)
        let playing = try #require(await rig.render(seconds: 0.15))
        #expect(playing > 0.01, "still playing")
        let after = try #require(rig.position)
        #expect(abs(after - (before + 0.15)) < 0.02, "the playhead did not move: \(before) → \(after)")
        await rig.finish()
    }

    // MARK: The ordinary seek (the unified path must keep it)

    @Test("a seek inside the song moves the playhead there and keeps playing", arguments: SubPath.allCases)
    func seekInsideTheSong(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "seek-inside")
        _ = try await rig.render(seconds: 0.3)
        let (error, epoch) = await rig.seek(to: 1.25)
        #expect(error == nil)
        #expect(rig.transport.isCurrent(for: epoch))
        let playing = try #require(await rig.render(seconds: 0.2))
        #expect(playing > 0.01)
        let after = try #require(rig.position)
        #expect(abs(after - 1.45) < 0.02, "\(after)")
        #expect(!rig.transport.ended)
        await rig.finish()
    }

    @Test("a seek keeps the gapless next track armed: a seek is not a transition", arguments: SubPath.allCases)
    func seekKeepsTheTrackOnDeck(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "seek-keeps-deck")
        await rig.bridge.setNextTrack(rig.url, ticket: OnDeckTicket(session: 0, sequence: 1))
        _ = try await rig.render(seconds: 0.2)
        _ = await rig.seek(to: 0.9)
        let bridge = rig.bridge
        let armed = bridge.resampleQueue.sync {
            (deck: bridge.onDeckURL != nil, hook: bridge.onResamplerEOF != nil || bridge.onPassthroughEOF != nil)
        }
        #expect(armed.deck, "the on-deck track survives a seek")
        #expect(armed.hook, "the seam's end-of-track hook survives a seek")
        await rig.finish()
    }

    @Test("a device change re-establishes playback at the playhead", arguments: SubPath.allCases)
    func reestablishResumesAtThePlayhead(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "reestablish")
        _ = try await rig.render(seconds: 0.4)
        let bridge = rig.bridge
        // On configChangeQueue, as the output rule runs it after an AVAudioEngineConfigurationChange.
        let reestablished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            bridge.configChangeQueue.async {
                guard let engine = bridge.avEngineRef else {
                    continuation.resume(returning: false)
                    return
                }
                bridge.reestablishEnhancedAfterConfigChange(engine: engine)
                continuation.resume(returning: true)
            }
        }
        try #require(reestablished)
        let playing = try #require(await rig.render(seconds: 0.2))
        #expect(playing > 0.01)
        let after = try #require(rig.position)
        #expect(abs(after - 0.6) < 0.03, "resumed where it was: \(after)")
        #expect(!rig.transport.ended)
        await rig.finish()
    }
}
