// S10.8 G break-it (playback/shell lane) - scenarios run against the REAL AudioViewModel sources
// (run.sh copies them verbatim next to HarnessStubs.swift). Each scenario prints HOLDS or BROKEN with
// what was expected and what the view model did. The run exits 1 when anything is BROKEN.
// Nothing plays: the engine is the recording fake in HarnessStubs. No UserDefaults domain is written.

import Foundation
import PlaybackQueueKit

var broken = 0

@MainActor
func report(_ holds: Bool, _ id: String, _ claim: String, expected: String, actual: String) {
    if holds {
        print("HOLDS  \(id): \(claim)")
    } else {
        broken += 1
        print("BROKEN \(id): \(claim)\n         expected: \(expected)\n         actual:   \(actual)")
    }
}

func both(_ first: Bool, _ second: Bool) -> Bool {
    first ? second : false
}

func text(_ value: Int?) -> String {
    value.map(String.init) ?? "nil"
}

func name(_ value: URL?) -> String {
    value?.lastPathComponent ?? "none"
}

/// Lets every main-actor Task the view model spawned run to completion (the fake engine never blocks).
@MainActor
func settle() async {
    for _ in 0 ..< 50 {
        await Task.yield()
    }
    try? await Task.sleep(for: .milliseconds(60))
    for _ in 0 ..< 50 {
        await Task.yield()
    }
}

func url(_ index: Int) -> URL {
    URL(fileURLWithPath: "/nonexistent/breakit-g/track\(index).flac")
}

@MainActor
func makeVM(tracks count: Int) -> (AudioViewModel, AudioEngineBridge) {
    let engine = AudioEngineBridge()
    // A suite that is never written (hydration and cursor persistence are stand-ins).
    let defaults = UserDefaults(suiteName: "breakit.g.vmharness.unused") ?? .standard
    let model = AudioViewModel(defaults: defaults, engine: engine)
    model.isEngineReady = true
    model.queue = (0 ..< count).map { index in
        QueueItem(file: AudioFile(name: "Track \(index)", relativePath: "", absoluteURL: url(index),
                                  format: "FLAC", durationSeconds: 200, trackID: Int64(index + 1)))
    }
    return (model, engine)
}

/// Plays `index`, lets the start land, then pins a known duration (the fake files cannot be measured).
@MainActor
func playAndSettle(_ model: AudioViewModel, at index: Int, duration: Double = 200) async {
    model.playTrack(at: index)
    await settle()
    model.duration = duration
}

/// Pauses at `seconds` (the playhead the 20 Hz tick last read).
@MainActor
func pause(_ model: AudioViewModel, _ engine: AudioEngineBridge, at seconds: Double) async {
    engine.position = seconds
    model.tickTransport()
    model.pause()
    await settle()
}

await repeatOneTurnedOn()
await repeatAllTurnedOnOnLastSong()
await repeatOneTurnedOff()
await removePausedCurrent()
await removeAbovePausedCurrent()
await reorderAcrossPausedCurrent()
await scrubWhilePaused()
await scrubAfterQueueEnded()
await secondPressDuringStart()
await clearDuringStart()
await masterGainAtLaunch()
print(broken == 0 ? "vmharness: all scenarios hold" : "vmharness: \(broken) scenario(s) BROKEN")
exit(broken == 0 ? 0 : 1)
