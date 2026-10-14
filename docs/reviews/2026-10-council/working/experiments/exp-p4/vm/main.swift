// Council P4 — scenarios against the REAL AudioViewModel (see run.sh). Each scenario prints what the
// user HEARS (the engine model's ground truth) vs what the app SHOWS (selectedTrackIndex's track).

import Foundation
import PlaybackQueueKit


@MainActor
func check(_ ok: Bool, _ id: String, _ msg: String) {
    if !ok { failures += 1 }
    print("\(ok ? "HOLDS " : "BROKEN") \(id): \(msg)")
}

func url(_ index: Int) -> URL { URL(fileURLWithPath: "/nonexistent/p4/t\(index).flac") }
func nm(_ value: URL?) -> String { value.map { $0.deletingPathExtension().lastPathComponent } ?? "none" }

@MainActor
func drain() async {
    for _ in 0 ..< 60 { await Task.yield() }
}

@MainActor
func makeVM(_ count: Int) -> (AudioViewModel, AudioEngineBridge) {
    let engine = AudioEngineBridge()
    let defaults = UserDefaults(suiteName: "council.p4.vm.unused") ?? .standard
    let model = AudioViewModel(defaults: defaults, engine: engine)
    model.isEngineReady = true
    model.queue = (0 ..< count).map { index in
        QueueItem(file: AudioFile(name: "t\(index)", relativePath: "", absoluteURL: url(index), format: "FLAC",
                                  durationSeconds: 200, trackID: Int64(index + 1)))
    }
    return (model, engine)
}

/// Let every queue run until nothing is pending (FIFO, the "nothing races" schedule).
@MainActor
func settle(_ engine: AudioEngineBridge) async {
    for _ in 0 ..< 50 {
        await drain()
        if engine.idle { break }
        while engine.finishPureOpen() {}
        while engine.runEngineOp() {}
        while engine.runResampleOp() {}
    }
    await drain()
}

@MainActor
func tick(_ model: AudioViewModel, _ engine: AudioEngineBridge) {
    engine.clockTick()
    model.tickTransport()
}

@MainActor
func shown(_ model: AudioViewModel) -> URL? {
    model.selectedTrackIndex.flatMap { $0 < model.queue.count ? model.queue[$0].file.absoluteURL : nil }
}

@MainActor
func pendingURL(_ model: AudioViewModel) -> URL? {
    model.pendingNextIndex.flatMap { $0 < model.queue.count ? model.queue[$0].file.absoluteURL : nil }
}

@MainActor
func startPlaying(_ model: AudioViewModel, _ engine: AudioEngineBridge, at index: Int, pure: Bool) async {
    model.pureModeEnabled = pure
    model.playTrack(at: index)
    await settle(engine)
    tick(model, engine)
}

// MARK: - 1. D41 at the transport level: which app sequences reach "arm while armed" on Pure


@MainActor
func d41(_ label: String, pure: Bool, shuffle: Bool = false, repeatMode: Int = 0,
         action: (AudioViewModel) -> Void) async {
    let (model, engine) = makeVM(6)
    engine.pureArmReplaces = remedyOn
    model.shuffleEnabled = shuffle
    model.repeatMode = repeatMode
    await startPlaying(model, engine, at: 0, pure: pure)
    let armedBefore = engine.armed
    action(model)
    let promised = pendingURL(model) // what the app now says plays next
    await settle(engine)
    let armedAfter = engine.armed
    engine.trackEnds() // A's audio runs out
    tick(model, engine)
    await settle(engine)
    tick(model, engine)
    let heard = engine.current
    let shownNow = shown(model)
    let ok = heard == shownNow
    check(ok, "D41/\(pure ? "Pure" : "Enh")\(remedyOn ? "+remedy" : "")/\(label)",
          "armed before=\(nm(armedBefore)) app promised next=\(nm(promised)) engine armed after=\(nm(armedAfter))"
              + " refused=\(engine.refusedArms.map(nm)) → HEARS \(nm(heard)) / SHOWS \(nm(shownNow))"
              + " queue=\(model.queue.map { nm($0.file.absoluteURL) })")
}

// MARK: - 2. A seam the view model never saw, carried into the next start's samples

@MainActor
func spuriousSeamAtStart(pure: Bool) async {
    let (model, engine) = makeVM(6)
    await startPlaying(model, engine, at: 0, pure: pure)
    // t0 → t1 seam happens and the clock publishes it (epoch of the t0 start)...
    engine.trackEnds()
    engine.clockTick()
    // ...but before the VM's next 20 Hz tick, the user presses Next (t1 is what's audible; the app
    // still shows t0, so Next goes to t0+1 = t1 in linear order — use a click on t3 instead).
    model.playTrack(at: 3)
    await drain() // the start Task reaches the engine
    // The engine begins the start: transitional sample (epoch current, LAST PUBLISHED count).
    // A tick lands while the start is slow (Pure rate change) or before the continuation runs.
    engine.beginHeadOp()
    tick(model, engine)
    let shownMid = shown(model)
    await settle(engine)
    tick(model, engine)
    check(shown(model) == engine.current, "SEAM-AT-START/\(pure ? "Pure" : "Enh")",
          "user clicked t3 as the t0→t1 seam landed; mid-start tick showed \(nm(shownMid)); "
              + "HEARS \(nm(engine.current)) / SHOWS \(nm(shown(model))) pending=\(nm(pendingURL(model)))")
}

/// Pure → Enhanced: the two paths publish seam counts from different counters.
@MainActor
func pathSwitchCountJump() async {
    let (model, engine) = makeVM(6)
    engine.enhancedCount = 4 // four Enhanced seams earlier this session
    engine.pureViable = { $0 != url(3) } // t3 cannot play on Pure (e.g. a rate the device lacks)
    await startPlaying(model, engine, at: 0, pure: true)
    model.playTrack(at: 3) // a click: falls back to Enhanced
    await drain()
    engine.runEngineOp() // the start completes and publishes its settled sample...
    tick(model, engine) // ...and a tick runs before the start Task's continuation primes the baseline
    let shownMid = shown(model)
    await settle(engine)
    tick(model, engine)
    check(shownMid == url(3) && shown(model) == engine.current, "COUNT-DOMAIN/Pure→Enh",
          "click t3 (falls back to Enhanced, cumulative count 4 vs Pure baseline 0): tick before the "
              + "prime showed \(nm(shownMid)); final HEARS \(nm(engine.current)) / SHOWS \(nm(shown(model)))")
}

// MARK: - 3. Pure: two re-arms in flight; the opens finish in the other order

@MainActor
func pureRearmRace(remedy: Bool) async {
    let (model, engine) = makeVM(6)
    engine.pureArmReplaces = remedy
    model.repeatMode = 0
    await startPlaying(model, engine, at: 0, pure: true)
    // Clear first (as the D41 remedy proposes), then two quick arms: Play Next t4, then Play Next t5.
    model.playNext([AudioFile(name: "x", relativePath: "", absoluteURL: url(10), format: "FLAC",
                              durationSeconds: 200, trackID: 11)])
    model.playNext([AudioFile(name: "y", relativePath: "", absoluteURL: url(11), format: "FLAC",
                              durationSeconds: 200, trackID: 12)])
    await drain()
    let promised = pendingURL(model)
    // The second open (t11) finishes first.
    engine.finishPureOpen(1)
    engine.finishPureOpen(0)
    await settle(engine)
    check(engine.armed == promised, "PURE-REARM-ORDER/\(remedy ? "with P3a clear+arm remedy" : "today")",
          "two Play Next while t1 armed: app promises \(nm(promised)); engine armed \(nm(engine.armed)); "
              + "refused \(engine.refusedArms.map(nm))")
}

@MainActor
func pauseNearEndMidQueue() async {
    let (model, engine) = makeVM(4)
    await startPlaying(model, engine, at: 0, pure: true)
    engine.armed = nil // t1 needs a rate change: kNextTrackNeedsReconfigure, nothing armed (the gap path)
    engine.position = 199.9
    tick(model, engine)
    model.pause()
    engine.trackEnds() // t0's end flag
    tick(model, engine) // before the pause Task has numbered its stop
    await settle(engine)
    tick(model, engine)
    check(model.pausedResumePosition != nil && model.selectedTrackIndex == 0, "PAUSE-NEAR-END/mid-queue",
          "pause at 199.9 s of t0 (t1 not armable): resume point="
              + "\(model.pausedResumePosition.map { String($0) } ?? "nil") selected=\(nm(shown(model))) "
              + "isPlaying=\(model.isPlaying) — Play now starts \(nm(shown(model))) from "
              + "\(model.pausedResumePosition.map { String($0) } ?? "0")")
}

// MARK: - 4. Linear order after a reorder: the armed pick is kept, not the row after the current

@MainActor
func reorderLinear() async {
    let (model, engine) = makeVM(4) // t0* t1 t2 t3, repeat off, shuffle off
    await startPlaying(model, engine, at: 0, pure: false)
    model.moveTrackToTop(3) // t3 t0* t1 t2  (current re-anchored to row 1)
    model.moveTrackToBottom(2) // t3 t0* t2 t1 → the row after t0 is now t2; armed is still t1
    await settle(engine)
    var heard: [String] = [nm(engine.current)]
    var shownSeq: [String] = [nm(shown(model))]
    for _ in 0 ..< 4 {
        engine.trackEnds()
        tick(model, engine)
        await settle(engine)
        tick(model, engine)
        if engine.current == nil || engine.ended { break }
        heard.append(nm(engine.current))
        shownSeq.append(nm(shown(model)))
    }
    let queueOrder = model.queue.map { nm($0.file.absoluteURL) }
    check(heard == ["t0", "t2", "t1"], "REORDER-LINEAR",
          "queue now \(queueOrder) (t0 current): linear play should be t0,t2,t1; HEARD \(heard) SHOWN \(shownSeq)")
}

@MainActor
func reorderPlayNextByDrag(pure: Bool) async {
    let (model, engine) = makeVM(6)
    await startPlaying(model, engine, at: 0, pure: pure)
    model.moveByDrop(fromID: model.queue[3].id, toIndex: 1) // drag t3 to the row after the current song
    await settle(engine)
    var heard: [String] = [nm(engine.current)]
    for _ in 0 ..< 10 {
        engine.trackEnds()
        tick(model, engine)
        await settle(engine)
        tick(model, engine)
        if engine.current == nil || engine.ended || !model.isPlaying { break }
        heard.append(nm(engine.current))
    }
    let order = model.queue.map { nm($0.file.absoluteURL) }
    check(heard == order, "REORDER-DRAG-NEXT/\(pure ? "Pure" : "Enh")",
          "drag t3 under the playing t0 → queue \(order); HEARD to the end \(heard)")
}

// MARK: - 5. Shuffle: does a shuffled queue with repeat OFF ever end? Previous under shuffle?

@MainActor
func shuffleNeverEnds() async {
    let (model, engine) = makeVM(5)
    model.shuffleEnabled = true
    await startPlaying(model, engine, at: 0, pure: false)
    var heard: [String] = [nm(engine.current)]
    for _ in 0 ..< 40 {
        engine.trackEnds()
        tick(model, engine)
        await settle(engine)
        tick(model, engine)
        if engine.ended || !model.isPlaying { break }
        heard.append(nm(engine.current))
    }
    let distinct = Set(heard).count
    let repeats = heard.count - distinct
    check(heard.count <= 5 && distinct == heard.count, "SHUFFLE-ENDS",
          "5-track queue, shuffle on, repeat off: played \(heard.count) tracks before stopping (cap 40), "
              + "\(distinct) distinct, \(repeats) repeats; first 12: \(heard.prefix(12))")
    // Previous after Next under shuffle: is it the song we came from?
    let (m2, e2) = makeVM(8)
    m2.shuffleEnabled = true
    await startPlaying(m2, e2, at: 0, pure: false)
    var back = 0
    for _ in 0 ..< 200 {
        let from = m2.selectedTrackIndex
        m2.nextTrack()
        await settle(e2)
        m2.previousTrack()
        await settle(e2)
        if m2.selectedTrackIndex == from { back += 1 }
    }
    check(back == 200, "SHUFFLE-PREVIOUS",
          "8 tracks, shuffle: Next then Previous returned to the song we came from \(back)/200 times")
}

// MARK: - 6. Pause / play races against a slow start

@MainActor
func playThenPauseFast() async {
    // From stopped: Play, then Pause (Space twice) before the start completes.
    let (model, engine) = makeVM(4)
    model.pureModeEnabled = true
    model.togglePlayPause() // play
    await drain()
    model.togglePlayPause() // the user means pause: isPlaying is still false → play() again
    await settle(engine)
    tick(model, engine)
    let starts = engine.heard.count
    check(!model.isPlaying && engine.current == nil, "PLAY-THEN-PAUSE",
          "Space, Space during a start: engine \(engine.current == nil ? "stopped" : "plays \(nm(engine.current))") "
              + "(\(starts) start(s)), app isPlaying=\(model.isPlaying)")
}

@MainActor
func pauseDuringSkip() async {
    // Playing t0; Next (start t1 in flight); Pause; the start completes BEFORE the pause Task runs.
    let (model, engine) = makeVM(4)
    await startPlaying(model, engine, at: 0, pure: true)
    model.nextTrack()
    await drain() // the start Task is now awaiting the engine
    model.pause() // a Task: numbers its stop epoch only when it runs
    engine.runEngineOp() // the start of t1 finishes first
    await drain()
    await settle(engine)
    tick(model, engine)
    check(!model.isPlaying && engine.current == nil && model.pausedResumePosition != nil, "PAUSE-DURING-SKIP",
          "Next then Pause: engine \(nm(engine.current)) app isPlaying=\(model.isPlaying) "
              + "resume=\(model.pausedResumePosition.map { String($0) } ?? "nil") pending=\(nm(pendingURL(model)))")
}

@MainActor
func pauseAtTrackEnd() async {
    // Pause pressed in the last moments of the LAST track (nothing armed): the end flag lands before
    // the pause's stop op runs.
    let (model, engine) = makeVM(2)
    await startPlaying(model, engine, at: 1, pure: false)
    engine.position = 199.9
    tick(model, engine)
    model.pause()
    engine.trackEnds() // the end flag (nothing armed)
    tick(model, engine) // the tick runs before the pause Task numbers its epoch
    await settle(engine)
    tick(model, engine)
    check(model.pausedResumePosition != nil, "PAUSE-AT-END",
          "pause at 199.9 s of the last track, end flag in the same tick: resume point="
              + "\(model.pausedResumePosition.map { String($0) } ?? "nil (pause became a STOP)") "
              + "position=\(model.playbackPosition)")
}

// MARK: - 6b. Targeted repros of the explorer's four classes

/// Pure: Next, Next fast. The first start's prime opens t2 (global queue); the second start (t2) runs
/// before that open lands, so the stale arm lands on the NEW session.
@MainActor
func nextNextPure() async {
    let (model, engine) = makeVM(6)
    await startPlaying(model, engine, at: 0, pure: true)
    model.nextTrack() // → t1
    await drain()
    engine.runEngineOp() // start t1
    await drain() // prime: open of t2 in flight (pureOpening)
    model.nextTrack() // → t2, before the open finished
    await drain()
    engine.runEngineOp() // start t2 (fresh GaplessSource: nothing armed)
    await drain() // t2's prime: open of t3 in flight
    engine.finishPureOpen(0) // the STALE open (t2, from t1's prime) lands first
    await settle(engine)
    let armedNow = engine.armed
    engine.trackEnds()
    tick(model, engine)
    await settle(engine)
    tick(model, engine)
    check(shown(model) == engine.current, "NEXT-NEXT/Pure",
          "Next, Next while the first prime's file open was in flight: engine armed \(nm(armedNow)) under "
              + "current t2 (refused \(engine.refusedArms.map(nm))); after t2 ends HEARS \(nm(engine.current)) / "
              + "SHOWS \(nm(shown(model)))")
}

/// Stop, then a click on another song while the engine queue is busy (a slow Pure start, a device lock).
@MainActor
func stopThenPlayBusy(pure: Bool, resampleFree: Bool = false) async {
    let (model, engine) = makeVM(4)
    await startPlaying(model, engine, at: 0, pure: pure)
    model.stopPlayback() // ⌘. Stop
    await drain() // its Task numbers the stop and sends setNextTrack(nil); the queue is busy, so it waits
    if resampleFree { engine.runResampleOp(); await drain() } // Enhanced: the clear hops on a FREE resampleQueue
    model.playTrack(at: 2) // the user double-clicks t2
    await drain() // the start is queued
    // The engine queue frees: FIFO from here on.
    await settle(engine)
    tick(model, engine)
    tick(model, engine)
    let ok = model.isPlaying == (engine.current != nil) && (engine.current == nil || shown(model) == engine.current)
    check(ok && engine.current == url(2), "STOP-THEN-PLAY/\(pure ? "Pure" : "Enh")\(resampleFree ? "(resampleQueue free)" : "")",
          "Stop, then double-click t2 while the engine was busy: engine \(engine.current == nil ? "SILENT" : "plays \(nm(engine.current))")"
              + ", app isPlaying=\(model.isPlaying) shows \(nm(shown(model))) position=\(model.playbackPosition)")
}

/// From stopped: Play, then Next before the start lands (media keys; a Pure DAC rate change).
@MainActor
func playThenNextDuringStart(pure: Bool) async {
    let (model, engine) = makeVM(4)
    model.pureModeEnabled = pure
    model.play()
    await drain()
    model.nextTrack() // isPlaying is still false → only re-selects
    await settle(engine)
    tick(model, engine)
    check(shown(model) == engine.current, "PLAY-THEN-NEXT/\(pure ? "Pure" : "Enh")",
          "Play then Next during the start: HEARS \(nm(engine.current)) / SHOWS \(nm(shown(model))) isPlaying=\(model.isPlaying)")
}

/// Pause, then Play while the engine queue is busy.
@MainActor
func pauseThenPlayBusy(pure: Bool, resampleFree: Bool = false) async {
    let (model, engine) = makeVM(4)
    await startPlaying(model, engine, at: 0, pure: pure)
    engine.position = 80
    tick(model, engine)
    model.pause()
    await drain() // pause's stop numbered; setNextTrack(nil) waits on the busy queue
    if resampleFree { engine.runResampleOp(); await drain() }
    model.play() // resume from 80
    await settle(engine)
    tick(model, engine)
    check(model.isPlaying && engine.current == url(0), "PAUSE-THEN-PLAY/\(pure ? "Pure" : "Enh")\(resampleFree ? "(resampleQueue free)" : "")",
          "Pause at 80 s, then Play while busy: engine \(engine.current == nil ? "SILENT" : "plays \(nm(engine.current)) at \(engine.position ?? -1)")"
              + ", app isPlaying=\(model.isPlaying) resume=\(model.pausedResumePosition.map { String($0) } ?? "nil") "
              + "position=\(model.playbackPosition)")
}

// MARK: - 7. Random-schedule exploration of start / seek / stop / pause / next against lagging samples

@MainActor
func explore(runs: Int, seed: UInt64) async {
    var rng = SplitMix(seed: seed)
    var violations: [String: (Int, String)] = [:]
    let verbs = ["play", "pause", "seek", "stop", "next", "toggle"]
    for run in 0 ..< runs {
        let (model, engine) = makeVM(5)
        let pure = rng.next() % 2 == 0
        model.pureModeEnabled = pure
        if rng.next() % 2 == 0 { await startPlaying(model, engine, at: 0, pure: pure) }
        let script = (0 ..< (2 + Int(rng.next() % 3))).map { _ in verbs[Int(rng.next() % UInt64(verbs.count))] }
        var pendingVerbs = script[...]
        var trace: [String] = []
        var steps: [String] = ["start: started=\(engine.current != nil) eng=\(nm(engine.current))"]
        var seams = 0
        for _ in 0 ..< 40 {
            var moves: [String] = []
            if !pendingVerbs.isEmpty { moves.append("U") }
            if !engine.engineQueue.isEmpty { moves.append("E") }
            if !engine.resampleQueue.isEmpty { moves.append("R") }
            if !engine.pureOpening.isEmpty { moves.append("O") }
            moves.append("D")
            moves.append("T")
            if seams < 1, engine.current != nil { moves.append("S") }
            if pendingVerbs.isEmpty, engine.idle, rng.next() % 4 == 0 { break }
            let move = moves[Int(rng.next() % UInt64(moves.count))]
            defer {
                steps.append("\(trace.last ?? "?"): eng=\(nm(engine.current))/armed=\(nm(engine.armed))/q=\(engine.engineQueue.map(\.kind.description)) "
                    + "vm sel=\(nm(shown(model))) playing=\(model.isPlaying) ep=\(model.transportEpoch)/stop=\(model.transportStopEpoch)")
            }
            switch move {
            case "U":
                let verb = pendingVerbs.removeFirst()
                trace.append(verb)
                switch verb {
                case "play": model.play()
                case "pause": model.pause()
                case "seek": model.seek(to: 42)
                case "stop": model.stopPlayback()
                case "next": model.nextTrack()
                default: model.togglePlayPause()
                }
            case "E": engine.runEngineOp(); trace.append("E")
            case "R": engine.runResampleOp(); trace.append("R")
            case "O": engine.finishPureOpen(Int(rng.next() % UInt64(engine.pureOpening.count))); trace.append("O")
            case "D": await drain(); trace.append("D")
            case "T": tick(model, engine); trace.append("T")
            default: engine.trackEnds(); seams += 1; trace.append("S")
            }
        }
        while !pendingVerbs.isEmpty { // finish the script, FIFO
            let verb = pendingVerbs.removeFirst()
            trace.append(verb)
            switch verb {
            case "play": model.play()
            case "pause": model.pause()
            case "seek": model.seek(to: 42)
            case "stop": model.stopPlayback()
            case "next": model.nextTrack()
            default: model.togglePlayPause()
            }
        }
        await settle(engine)
        for _ in 0 ..< 3 {
            tick(model, engine)
            await settle(engine)
        }
        let enginePlays = engine.current != nil && !engine.ended
        var kind: String?
        if enginePlays != model.isPlaying {
            kind = enginePlays ? "engine plays, app shows stopped/paused" : "app shows playing, engine silent"
        } else if enginePlays, shown(model) != engine.current {
            kind = "wrong song shown"
        } else if enginePlays, model.pendingNextIndex != nil, pendingURL(model) != engine.armed {
            kind = "app's next != engine's armed"
        }
        if let kind {
            let detail = "pure=\(pure) script=\(script) trace=\(trace.joined(separator: ",")) → hears \(nm(engine.current)) "
                + "shows \(nm(shown(model))) isPlaying=\(model.isPlaying) armed=\(nm(engine.armed)) pending=\(nm(pendingURL(model)))"
            if violations[kind] == nil, CommandLine.arguments.contains("verbose") {
                print("=== first '\(kind)':\n" + steps.joined(separator: "\n"))
            }
            let prev = violations[kind]
            violations[kind] = (prev?.0 ?? 0) + 1 > 0 ? ((prev?.0 ?? 0) + 1, prev?.1 ?? detail) : (1, detail)
        }
        _ = run
    }
    if violations.isEmpty {
        check(true, "EXPLORE", "\(runs) random schedules: UI and engine agree after every one")
    }
    for (kind, value) in violations.sorted(by: { $0.key < $1.key }) {
        check(false, "EXPLORE", "\(value.0)/\(runs) schedules end with '\(kind)'. First: \(value.1)")
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - 8. Play-through accrual while the engine is not producing audio

@MainActor
func accrualDuringSilence() async {
    let (model, engine) = makeVM(3)
    await startPlaying(model, engine, at: 0, pure: false)
    model.duration = 200
    model.resetPlayTracking()
    tick(model, engine) // seed
    // The device dies: the engine stops producing audio, but `interrupted` reaches the snapshot only
    // after the engine's device-loss handler runs (it can wait ~7 s on the dying device's lock).
    let start = Date()
    while Date().timeIntervalSince(start) < 1.0 {
        try? await Task.sleep(for: .milliseconds(50))
        tick(model, engine)
    }
    let heardSilent = model.playThroughTracker.heardSeconds
    check(heardSilent < 0.2, "ACCRUE-SILENCE",
          "1.0 s of ticks while the engine produced nothing (device gone, interrupted not yet published): "
              + "heard \(String(format: "%.2f", heardSilent)) s credited")
    // A slow Pure start (a DAC rate change takes seconds): ticks during the start of a skip.
    let (m2, e2) = makeVM(3)
    await startPlaying(m2, e2, at: 0, pure: true)
    m2.duration = 200
    m2.nextTrack()
    await drain()
    let s2 = Date()
    while Date().timeIntervalSince(s2) < 0.6 {
        try? await Task.sleep(for: .milliseconds(50))
        m2.duration = 200 // the next song's length resolves in ms (AVAudioFile), long before a DAC switch ends
        tick(m2, e2)
    }
    check(m2.playThroughTracker.heardSeconds < 0.2, "ACCRUE-START",
          "0.6 s of a slow start (nothing audible yet): heard \(String(format: "%.2f", m2.playThroughTracker.heardSeconds)) s "
              + "credited to \(nm(shown(m2)))")
}

// MARK: - 9. Id-stability of selection / on-deck / resume point under arbitrary queue edits (N18)

@MainActor
func idStability(runs: Int, seed: UInt64) async {
    var rng = SplitMix(seed: seed)
    var bad: [String: (Int, String)] = [:]
    var fresh = 100
    for _ in 0 ..< runs {
        let (model, engine) = makeVM(2 + Int(rng.next() % 6))
        let paused = rng.next() % 2 == 0
        await startPlaying(model, engine, at: Int(rng.next() % UInt64(model.queue.count)), pure: false)
        if paused {
            engine.position = 50
            tick(model, engine)
            model.pause()
            await settle(engine)
        }
        var log: [String] = []
        for _ in 0 ..< 6 {
            let selID = model.selectedSlotID
            let pendID = model.pendingNextIndex.flatMap { $0 < model.queue.count ? model.queue[$0].id : nil }
            let resumeBefore = model.pausedResumePosition
            let count = model.queue.count
            guard count > 0 else { break }
            var removed: UUID?
            var inserted = false
            switch rng.next() % 6 {
            case 0:
                let at = Int(rng.next() % UInt64(count))
                removed = model.queue[at].id
                log.append("remove(\(at))")
                model.removeTrack(at: at)
            case 1:
                let from = Int(rng.next() % UInt64(count)), to = Int(rng.next() % UInt64(count))
                log.append("drop(\(from)→\(to))")
                model.moveByDrop(fromID: model.queue[from].id, toIndex: to)
            case 2:
                let at = Int(rng.next() % UInt64(count))
                log.append("up/down(\(at))")
                if rng.next() % 2 == 0 { model.moveTrackUp(at) } else { model.moveTrackDown(at) }
            case 3:
                let at = Int(rng.next() % UInt64(count))
                log.append("top/bottom(\(at))")
                if rng.next() % 2 == 0 { model.moveTrackToTop(at) } else { model.moveTrackToBottom(at) }
            case 4:
                fresh += 1
                log.append("playNext")
                inserted = true
                model.playNext([AudioFile(name: "n", relativePath: "", absoluteURL: url(fresh), format: "FLAC",
                                          durationSeconds: 200, trackID: Int64(fresh))])
            default:
                fresh += 1
                log.append("append")
                model.appendToQueue([AudioFile(name: "a", relativePath: "", absoluteURL: url(fresh), format: "FLAC",
                                               durationSeconds: 200, trackID: Int64(fresh))])
            }
            await settle(engine)
            func note(_ kind: String) {
                let detail = "paused=\(paused) ops=\(log)"
                bad[kind] = ((bad[kind]?.0 ?? 0) + 1, bad[kind]?.1 ?? detail)
            }
            if removed == nil || removed != selID {
                if model.selectedSlotID != selID { note("selection lost its slot") }
                if paused, resumeBefore != nil, model.pausedResumePosition != resumeBefore { note("resume point lost") }
            }
            if !paused, !inserted, let pendID, removed != pendID, removed != selID {
                let now = model.pendingNextIndex.flatMap { $0 < model.queue.count ? model.queue[$0].id : nil }
                if now != pendID { note("on-deck lost its slot") }
            }
            if !paused, model.isPlaying, pendingURL(model) != engine.armed { note("app next != engine armed") }
            if let sel = model.selectedTrackIndex, sel >= model.queue.count { note("selection out of range") }
        }
    }
    if bad.isEmpty { check(true, "ID-STABILITY", "\(runs) random edit sequences: slots keep selection, on-deck, resume point") }
    for (kind, value) in bad.sorted(by: { $0.key < $1.key }) {
        check(false, "ID-STABILITY", "\(value.0) edits: '\(kind)'. First: \(value.1)")
    }
}

// MARK: - run

let only = CommandLine.arguments.dropFirst().first
if only == nil || only == "d41" {
    for pure in [true, false] {
        await d41("playNext", pure: pure) { $0.playNext([AudioFile(name: "n", relativePath: "", absoluteURL: url(9),
                                                                    format: "FLAC", durationSeconds: 200, trackID: 10)]) }
        await d41("shuffle-on", pure: pure) { $0.toggleShuffle() }
        await d41("shuffle-off", pure: pure, shuffle: true) { $0.toggleShuffle() }
        await d41("repeat-off→all(mid)", pure: pure) { $0.cycleRepeatMode() }
        await d41("repeat-all→one", pure: pure, repeatMode: 1) { $0.cycleRepeatMode() }
        await d41("repeat-one→off", pure: pure, repeatMode: 2) { $0.cycleRepeatMode() }
        await d41("remove-on-deck", pure: pure) { $0.removeTrack(at: 1) }
        await d41("remove-row-before-deck", pure: pure) { $0.removeTrack(at: 2) }
        await d41("append", pure: pure) { $0.appendToQueue([AudioFile(name: "a", relativePath: "", absoluteURL: url(8),
                                                                        format: "FLAC", durationSeconds: 200, trackID: 9)]) }
        await d41("move-t3-to-next", pure: pure) { $0.moveByDrop(fromID: $0.queue[3].id, toIndex: 1) }
        await d41("next-skip", pure: pure) { $0.nextTrack() }
    }
}
if only == "d41remedy" {
    remedyOn = true
    for pure in [true] {
        await d41("playNext", pure: pure) { $0.playNext([AudioFile(name: "n", relativePath: "", absoluteURL: url(9),
                                                                    format: "FLAC", durationSeconds: 200, trackID: 10)]) }
        await d41("shuffle-on", pure: pure) { $0.toggleShuffle() }
        await d41("shuffle-off", pure: pure, shuffle: true) { $0.toggleShuffle() }
        await d41("repeat-all→one", pure: pure, repeatMode: 1) { $0.cycleRepeatMode() }
        await d41("repeat-one→off", pure: pure, repeatMode: 2) { $0.cycleRepeatMode() }
        await d41("remove-on-deck", pure: pure) { $0.removeTrack(at: 1) }
    }
}
if only == "append" {
    for (label, count, startAt, shuffle, rep) in [("shuffle, 1-track queue", 1, 0, true, 0),
                                                   ("repeat-all, playing the last", 3, 2, false, 1),
                                                   ("linear, playing the last", 3, 2, false, 0)] {
        let (model, engine) = makeVM(count)
        model.shuffleEnabled = shuffle
        model.repeatMode = rep
        await startPlaying(model, engine, at: startAt, pure: false)
        model.appendToQueue([AudioFile(name: "d", relativePath: "", absoluteURL: url(7), format: "FLAC",
                                       durationSeconds: 200, trackID: 8)])
        await settle(engine)
        engine.trackEnds()
        tick(model, engine)
        await settle(engine)
        tick(model, engine)
        let after = engine.ended ? "STOPPED" : nm(engine.current)
        check(engine.current == url(7) && !engine.ended, "APPEND/\(label)",
              "append t7 while the last song plays: next heard = \(after) (app shows \(nm(shown(model))))")
    }
}
if only == "syncstop" {
    let (model, engine) = makeVM(4)
    await startPlaying(model, engine, at: 0, pure: false)
    model.stopPlayback()
    model.playTrack(at: 2) // same main-actor turn (e.g. two queued commands)
    await settle(engine)
    tick(model, engine)
    check(engine.current == url(2) && model.isPlaying, "STOP+PLAY-SAME-TURN",
          "stop then play t2 in one turn: engine \(nm(engine.current)) app isPlaying=\(model.isPlaying) "
              + "(stop epoch numbered in its Task AFTER the start's: the start is abandoned)")
}
if only == nil || only == "seam" {
    await spuriousSeamAtStart(pure: false)
    await spuriousSeamAtStart(pure: true)
    await pathSwitchCountJump()
}
if only == nil || only == "race" {
    await pureRearmRace(remedy: false)
    await pureRearmRace(remedy: true)
    await pauseNearEndMidQueue()
    await playThenPauseFast()
    await pauseDuringSkip()
    await pauseAtTrackEnd()
}
if only == nil || only == "order" {
    await reorderLinear()
    await reorderPlayNextByDrag(pure: false)
    await reorderPlayNextByDrag(pure: true)
    await shuffleNeverEnds()
}
if only == nil || only == "repro" {
    await nextNextPure()
    for pure in [false, true] {
        await stopThenPlayBusy(pure: pure)
        await playThenNextDuringStart(pure: pure)
        await pauseThenPlayBusy(pure: pure)
    }
    await stopThenPlayBusy(pure: false, resampleFree: true)
    await pauseThenPlayBusy(pure: false, resampleFree: true)
}
if only == nil || only == "explore" {
    await explore(runs: 3000, seed: 0xC0FFEE)
}
if only == nil || only == "ids" {
    await idStability(runs: 1500, seed: 0x5EED)
}
if only == nil || only == "accrue" {
    await accrualDuringSilence()
}
print("p4 vm harness: \(failures) BROKEN")
