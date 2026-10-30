// METER-LISTEN — the loudness readout's "Integrated" follows the listen (R1.1-B fix round, item 11): a resume of the
// song playing carries its measurement on; a new play of it (Play after Stop, Previous restarting it) measures from
// its start. The REAL bridge on the offline rig (`EnhancedTransportRig`): each start goes through `playFile` with its
// decision and listen held, as `startAudio` does. The rig installs no mixer tap and renders nothing here, so the test
// feeds the bridge's own meter as the tap would, and is its only feeder.

@testable import AdaptiveSound
import AudioDSP
import Foundation
import LevelingKit
import RigKit
import Testing

@Suite("The loudness readout follows the listen: a new play measures afresh, a resume carries on", .serialized,
       .timeLimit(.minutes(3)), .attachingLogTail)
struct LoudnessReadoutListenTests {
    typealias Rig = EnhancedTransportRig

    /// Start the rig's track again through the bridge's own start (`playFile`), as `startAudio` does: its decision
    /// and `listen` held first.
    private static func start(_ rig: Rig, listen: LevelingStart.Listen) async throws {
        let bridge = rig.bridge
        let url = rig.url
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bridge.engineQueue.async {
                do {
                    guard let engine = bridge.avEngineRef, let player = bridge.playerNodeRef else {
                        throw AudioBridgeError.engineNotInitialized
                    }
                    bridge.holdStartDecision(LevelingStart(decision: .off, listen: listen), for: url)
                    try bridge.playFile(at: url, engine: engine, playerNode: player, startAt: 0.5)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// `seconds` of a stereo 997 Hz tone at `amplitude` into `meter`, in the tap's 4800-frame buffers: BS.1770 reads
    /// it at 20·log10(amplitude) LUFS.
    private static func feed(_ meter: UnsafeMutableRawPointer, amplitude: Float, seconds: Double) {
        let rate = Rig.graphRate
        let chunk = 4800
        var frame = 0
        var samples = [Float](repeating: 0, count: chunk)
        while frame < Int(seconds * rate) {
            for index in 0 ..< chunk {
                samples[index] = amplitude * Float(sin(2 * Double.pi * 997 * Double(frame + index) / rate))
            }
            samples.withUnsafeBufferPointer { tone in
                loudnessMeterAddStereo(meter, tone.baseAddress, tone.baseAddress, UInt32(chunk))
            }
            frame += chunk
        }
    }

    @Test("METER-LISTEN-01: a resume carries the Integrated on; a new play of the same song starts it afresh")
    func newPlayMeasuresAfresh() async throws {
        let rig = try await Rig(path: .passthrough, name: "meter-listen")
        let meter = try #require(rig.bridge.tapAnalysis.meter?.handle)
        Self.feed(meter, amplitude: 0.5, seconds: 4) // −6 LUFS
        let loud = loudnessMeterRead(meter).integratedLufs
        #expect(abs(loud + 6.02) < 0.3, "the fixture reads \(loud) LUFS")

        // Pause → Play: the same listen. The quiet part is 20 LU under it, below the relative gate: Integrated stays.
        try await Self.start(rig, listen: .resume)
        Self.feed(meter, amplitude: 0.05, seconds: 3) // −26 LUFS
        let resumed = loudnessMeterRead(meter).integratedLufs
        #expect(abs(resumed - loud) < 0.3, "a resume restarted the measurement: \(resumed) LUFS")

        // Play after Stop: a new listen of the same song, measured from its start.
        try await Self.start(rig, listen: .newPlay)
        Self.feed(meter, amplitude: 0.05, seconds: 3)
        let fresh = loudnessMeterRead(meter).integratedLufs
        #expect(abs(fresh + 26.02) < 0.3, "a new play carried the last one's measurement on: \(fresh) LUFS")
        await rig.finish()
    }
}
