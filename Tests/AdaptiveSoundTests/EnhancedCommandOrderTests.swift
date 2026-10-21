@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - An overtaken command on the real bridge (council C-15)

//
// The view model numbers its starts, seeks and stops in the order the user asks; their hops to
// `engineQueue` keep no order. The bridge runs one only if it has not begun a newer one
// (`beginTransportOperation`). These run the REAL bridge on an offline engine (`EnhancedTransportRig`:
// nothing is heard, no device is opened) and send it a command numbered older than one it has begun.
// (No stale start is sent: a start's device step is the one part the rig leaves out.)

@Suite("Enhanced commands on the real bridge — an overtaken one is dropped (C-15)", .serialized)
struct EnhancedCommandOrderTests {
    typealias SubPath = EnhancedTransportRig.SubPath

    @Test("a seek overtaken by a newer seek is dropped: playback stays at the newer place",
          arguments: SubPath.allCases)
    func overtakenSeekIsDropped(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "overtaken-seek")
        _ = try await rig.render(seconds: 0.2)
        let (_, older) = await rig.seek(to: 0.4)
        let (error, newer) = await rig.seek(to: 1.2)
        #expect(error == nil)
        // The older seek's twin reaches the queue last, aimed somewhere else.
        try await rig.bridge.seek(to: 0.1, epoch: older)
        let transport = rig.transport
        #expect(transport.epoch == newer, "a dropped seek publishes nothing")
        let position = try #require(transport.position)
        #expect(abs(position - 1.2) < 0.05, "playback stays where the newer seek put it: \(position)")
        await rig.finish()
    }

    @Test("a stop overtaken by a newer command is dropped: playback goes on", arguments: SubPath.allCases)
    func overtakenStopIsDropped(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "overtaken-stop")
        _ = try await rig.render(seconds: 0.2)
        let (_, older) = await rig.seek(to: 0.3) // stands in for the Stop's number
        let (_, newer) = await rig.seek(to: 0.5) // the Play the user asked after it
        try await rig.bridge.stopAudio(epoch: older, pausing: false) // the Stop reaches the queue last
        #expect(rig.transport.epoch == newer)
        #expect(rig.bridge.enhancedPlayIntent, "a dropped stop leaves the play intent")
        let after = try #require(await rig.render(seconds: 0.3, skipping: 0.1))
        #expect(after > EnhancedTransportRig.silence, "the song the app shows as playing still plays")
        await rig.finish()
    }

    @Test("the newest stop still stops", arguments: SubPath.allCases)
    func newestStopStops(_ path: SubPath) async throws {
        let rig = try await EnhancedTransportRig(path: path, name: "newest-stop")
        _ = try await rig.render(seconds: 0.2)
        let (_, seek) = await rig.seek(to: 0.3)
        try await rig.bridge.stopAudio(epoch: seek + 1, pausing: false)
        #expect(rig.transport.epoch == seek + 1)
        #expect(!rig.bridge.enhancedPlayIntent)
        await rig.finish()
    }
}
