// Council P4 — adversarial review of the D41 design (d41-design.md) on the REAL VM sources with the
// design's VM side applied (patch_vm.py) and the design's engine contract modelled (EngineModel.swift).

import Foundation
import PlaybackQueueKit

@MainActor
func check(_ ok: Bool, _ id: String, _ msg: String) {
    if !ok { failures += 1 }
    print("\(ok ? "HOLDS " : "BROKEN") \(id): \(msg)")
}

func url(_ i: Int) -> URL { URL(fileURLWithPath: "/nonexistent/p4/t\(i).flac") }
func nm(_ u: URL?) -> String { u.map { $0.deletingPathExtension().lastPathComponent } ?? "none" }
func file(_ i: Int) -> AudioFile {
    AudioFile(name: "t\(i)", relativePath: "", absoluteURL: url(i), format: "FLAC", durationSeconds: 200, trackID: Int64(i + 1))
}

@MainActor func drain() async { for _ in 0 ..< 60 { await Task.yield() } }

@MainActor
func makeVM(_ count: Int) -> (AudioViewModel, AudioEngineBridge) {
    let engine = AudioEngineBridge()
    engine.mode = armMode
    engine.epochScopedCount = scopedCount
    let defaults = UserDefaults(suiteName: "council.p4.d41.unused") ?? .standard
    let model = AudioViewModel(defaults: defaults, engine: engine)
    model.isEngineReady = true
    model.queue = (0 ..< count).map { QueueItem(file: file($0)) }
    return (model, engine)
}

@MainActor
func settle(_ e: AudioEngineBridge) async {
    for _ in 0 ..< 80 {
        await drain()
        if e.idle { break }
        while e.deliver() {}
        while e.finishPureOpen() {}
        while e.runEngineOp() {}
        while e.runResampleWrite() {}
    }
    await drain()
}

@MainActor func tick(_ m: AudioViewModel, _ e: AudioEngineBridge) { e.clockTick(); m.tickTransport() }
@MainActor func shown(_ m: AudioViewModel) -> URL? {
    m.selectedTrackIndex.flatMap { $0 < m.queue.count ? m.queue[$0].file.absoluteURL : nil }
}
@MainActor func pendingURL(_ m: AudioViewModel) -> URL? {
    m.pendingNextIndex.flatMap { $0 < m.queue.count ? m.queue[$0].file.absoluteURL : nil }
}
@MainActor
func startPlaying(_ m: AudioViewModel, _ e: AudioEngineBridge, at i: Int, pure: Bool) async {
    m.pureModeEnabled = pure
    m.playTrack(at: i)
    await settle(e)
    tick(m, e)
}
/// A's audio runs out; the VM's ticks and tasks then run to quiescence.
@MainActor
func endAndFollow(_ m: AudioViewModel, _ e: AudioEngineBridge) async -> Bool {
    let a2 = e.trackEnds()
    tick(m, e)
    await settle(e)
    tick(m, e)
    await settle(e)
    tick(m, e)
    return a2
}

var modeLabel: String {
    switch armMode {
    case .refuse: "today"
    case .clearThenArm: "clearThenArm"
    case .gatedReplaceAfterOpen: "gatedReplaceAfterOpen"
    case let .gatedRetract(endFinal): "gatedRetractFirst(endFinal:\(endFinal))"
    }
}

// MARK: - 1. The six D41 cases, both paths

@MainActor
func d41(_ label: String, pure: Bool, shuffle: Bool = false, repeatMode: Int = 0, action: (AudioViewModel) -> Void) async {
    let (m, e) = makeVM(6)
    m.shuffleEnabled = shuffle
    m.repeatMode = repeatMode
    await startPlaying(m, e, at: 0, pure: pure)
    action(m)
    let promised = pendingURL(m)
    await settle(e)
    let armedAfter = e.armed
    _ = await endAndFollow(m, e)
    check(e.current == shown(m) && armedAfter == promised, "D41/\(modeLabel)/\(pure ? "Pure" : "Enh")/\(label)",
          "promised \(nm(promised)) armed \(nm(armedAfter)) → HEARS \(nm(e.current)) / SHOWS \(nm(shown(m)))")
}

// MARK: - 2. The races, every delivery order × every open order

@MainActor
func rearmOrder() async {
    var bad: [String] = []
    for deliverOrder in [[0, 0], [1, 0]] {
        for openOrder in [[0, 0], [1, 0]] {
            let (m, e) = makeVM(6)
            await startPlaying(m, e, at: 0, pure: true)
            m.playNext([file(10)])
            m.playNext([file(11)])
            await drain()
            let promised = pendingURL(m)
            for i in deliverOrder { e.deliver(i); while e.runEngineOp() {} }
            await drain()
            for i in openOrder where i < e.pureOpening.count { e.finishPureOpen(i); while e.runEngineOp() {} }
            await settle(e)
            if e.armed != promised {
                bad.append("deliver\(deliverOrder) open\(openOrder): promised \(nm(promised)) armed \(nm(e.armed))")
            }
        }
    }
    check(bad.isEmpty, "PURE-REARM-ORDER/\(modeLabel)", bad.isEmpty ? "all 4 delivery×open orders arm the newest" : "\(bad)")
}

@MainActor
func nextNext(pure: Bool, staleStillInbound: Bool) async {
    let (m, e) = makeVM(6)
    await startPlaying(m, e, at: 0, pure: pure)
    m.nextTrack() // → t1
    await drain()
    e.runEngineOp() // start t1 (session e2)
    await drain() // prime: request (e2, n) for t2 sent
    if !staleStillInbound {
        e.deliver(0)
        e.runEngineOp() // admitted; on Pure its open is now in flight
    }
    m.nextTrack() // → t2
    await drain()
    // run the new start BEFORE the stale request / open lands
    while let i = e.engineQueue.firstIndex(where: { if case .start = $0.kind { return true }; return false }) {
        let op = e.engineQueue.remove(at: i)
        e.engineQueue.insert(op, at: 0)
        e.runEngineOp()
    }
    await drain()
    // now the stale pieces land last
    while e.deliver(e.inbound.count - 1) { while e.runEngineOp() {} }
    while e.finishPureOpen(e.pureOpening.count - 1) { while e.runEngineOp() {} }
    await settle(e)
    let armedNow = e.armed
    _ = await endAndFollow(m, e)
    check(e.current == shown(m) && e.heard.filter { $0 == url(2) }.count == 1, "NEXT-NEXT/\(modeLabel)/\(pure ? "Pure" : "Enh")\(staleStillInbound ? "/stale-inbound" : "/stale-open")",
          "armed under t2 = \(nm(armedNow)); heard \(e.heard.map(nm)) shows \(nm(shown(m)))")
}

// MARK: - 3. Ends, late arms, repeat-one, removal, queue of 1, latency, seek after end

@MainActor
func retractThenEnd() async {
    let (m, e) = makeVM(6)
    await startPlaying(m, e, at: 0, pure: true)
    m.playNext([file(9)])
    await drain()
    e.deliver(); e.runEngineOp() // admitted: t1 taken off, t9 opening
    _ = e.trackEnds() // t0 ends while t9 opens → ended
    tick(m, e) // VM: ended + pending → fresh start of t9
    await drain()
    e.finishPureOpen(); while e.runEngineOp() {} // the late arm of t9 (old session or ended)
    await settle(e)
    tick(m, e)
    await settle(e)
    tick(m, e)
    let t9plays = e.heard.filter { $0 == url(9) }.count
    check(e.current == shown(m) && t9plays == 1 && !e.heard.contains(url(1)), "RETRACT-THEN-END/\(modeLabel)",
          "heard \(e.heard.map(nm)) shows \(nm(shown(m))) log \(e.log.suffix(3))")
}

@MainActor
func lateArmSameSession() async {
    // The open completes AFTER the end but BEFORE the VM's fresh start reaches the engine (same session).
    let (m, e) = makeVM(6)
    await startPlaying(m, e, at: 0, pure: true)
    m.playNext([file(9)])
    await drain()
    e.deliver(); e.runEngineOp()
    _ = e.trackEnds()
    e.finishPureOpen(); e.runEngineOp() // lands while the session is still t0's
    tick(m, e)
    await settle(e)
    tick(m, e)
    await settle(e)
    tick(m, e)
    let t9plays = e.heard.filter { $0 == url(9) }.count
    check(e.current == shown(m) && t9plays == 1, "LATE-ARM-AFTER-END/\(modeLabel)",
          "heard \(e.heard.map(nm)) (t9 started \(t9plays)×) shows \(nm(shown(m))) log \(e.log.suffix(2))")
}

@MainActor
func repeatOne(pure: Bool) async {
    let (m, e) = makeVM(3)
    m.repeatMode = 2
    await startPlaying(m, e, at: 0, pure: pure)
    for _ in 0 ..< 3 { _ = await endAndFollow(m, e) }
    m.cycleRepeatMode() // one → off, mid-song
    await settle(e)
    _ = await endAndFollow(m, e)
    check(e.heard.map(nm) == ["t0", "t0", "t0", "t0", "t1"] && shown(m) == e.current, "REPEAT-ONE/\(modeLabel)/\(pure ? "Pure" : "Enh")",
          "heard \(e.heard.map(nm)) shows \(nm(shown(m)))")
}

@MainActor
func removePlaying(pure: Bool) async {
    let (m, e) = makeVM(4)
    await startPlaying(m, e, at: 1, pure: pure)
    m.removeTrack(at: 1) // the playing row
    await settle(e)
    tick(m, e)
    let silent = e.current == nil
    _ = e.trackEnds()
    await settle(e)
    tick(m, e)
    check(silent && e.current == nil && !m.isPlaying && e.armed == nil, "REMOVE-PLAYING/\(modeLabel)/\(pure ? "Pure" : "Enh")",
          "engine \(nm(e.current)) armed \(nm(e.armed)) app playing=\(m.isPlaying) selected \(nm(shown(m)))")
}

@MainActor
func queueOfOne(pure: Bool, repeatMode: Int) async {
    let (m, e) = makeVM(1)
    m.repeatMode = repeatMode
    await startPlaying(m, e, at: 0, pure: pure)
    _ = await endAndFollow(m, e)
    let expectPlaying = repeatMode != 0
    check((e.current != nil) == expectPlaying && m.isPlaying == expectPlaying && shown(m) == url(0),
          "QUEUE-OF-1/\(modeLabel)/\(pure ? "Pure" : "Enh")/repeat\(repeatMode)",
          "after the end: engine \(nm(e.current)) ended=\(e.ended) app playing=\(m.isPlaying) heard \(e.heard.map(nm))")
}

@MainActor
func lateRequest(pure: Bool) async {
    // Play Next C while engineQueue is busy (device enumeration, a clock read blocked on the HAL): the
    // request is not admitted yet when A runs out.
    let (m, e) = makeVM(6)
    await startPlaying(m, e, at: 0, pure: pure)
    m.playNext([file(9)])
    await drain() // request sent, sits behind the busy queue (not delivered)
    let a2 = await endAndFollow(m, e)
    check(e.current == shown(m), "LATE-REQUEST/\(modeLabel)/\(pure ? "Pure" : "Enh")",
          "request unadmitted at the end (A2=\(a2)): HEARS \(nm(e.current)) / SHOWS \(nm(shown(m))) — design §6 risk 2 says \"a gap, never a wrong song\"")
}

@MainActor
func seekAfterEnd() async {
    // Last-moment Play Next leaves the slot empty → t0 ends; the user scrubs back in t0 at that moment.
    let (m, e) = makeVM(6)
    await startPlaying(m, e, at: 0, pure: true)
    m.playNext([file(9)])
    await drain()
    e.deliver(); e.runEngineOp() // admitted, t1 off, t9 opening
    m.seek(to: 30) // numbered E; queued
    await drain()
    _ = e.trackEnds() // t0's EOF before the seek op runs → ended (latched)
    while e.runEngineOp() {} // the seek runs: t0 audible again from 30 s, ended still latched
    tick(m, e)
    let afterSeek = "engine \(nm(e.current))@\(e.position ?? -1) ended=\(e.ended) app \(nm(shown(m))) playing=\(m.isPlaying)"
    await settle(e)
    tick(m, e)
    await settle(e)
    tick(m, e)
    check(e.current == shown(m), "SEEK-AFTER-END/\(modeLabel)",
          "after seek: \(afterSeek); final HEARS \(nm(e.current)) / SHOWS \(nm(shown(m))) heard \(e.heard.map(nm))")
}

// MARK: - 4. Explorer: arbitrary delivery and open orders, on-deck verbs interleaved with pause/stop/seek

@MainActor
func explore(runs: Int, seed: UInt64) async -> [String: Int] {
    var rng = SplitMix(seed: seed)
    var classes: [String: Int] = [:]
    var firsts: [String: String] = [:]
    let verbs = ["playNext", "shuffle", "repeat", "removeDeck", "removePlaying", "append", "next", "pause", "play", "stop", "seek"]
    for _ in 0 ..< runs {
        let (m, e) = makeVM(2 + Int(rng.next() % 5))
        let pure = rng.next() % 3 != 0
        if rng.next() % 4 == 0 { m.shuffleEnabled = true }
        m.repeatMode = Int(rng.next() % 3)
        await startPlaying(m, e, at: 0, pure: pure)
        var script = (0 ..< (1 + Int(rng.next() % 4))).map { _ in verbs[Int(rng.next() % UInt64(verbs.count))] }[...]
        var trace: [String] = []
        var steps: [String] = []
        var seams = 0
        var a2Seen = false
        var seamSeq: UInt64?
        var fresh = 50
        func doVerb(_ v: String) {
            trace.append(v)
            switch v {
            case "playNext": fresh += 1; m.playNext([file(fresh)])
            case "shuffle": m.toggleShuffle()
            case "repeat": m.cycleRepeatMode()
            case "removeDeck": if let p = m.pendingNextIndex, p < m.queue.count { m.removeTrack(at: p) }
            case "removePlaying": if let s = m.selectedTrackIndex { m.removeTrack(at: s) }
            case "append": fresh += 1; m.appendToQueue([file(fresh)])
            case "next": m.nextTrack()
            case "pause": m.pause()
            case "play": m.play()
            case "stop": m.stopPlayback()
            default: m.seek(to: 42)
            }
        }
        for _ in 0 ..< 45 {
            var moves: [String] = ["D", "T"]
            if !script.isEmpty { moves += ["U", "U"] }
            if !e.inbound.isEmpty { moves.append("V") }
            if !e.engineQueue.isEmpty { moves += ["E", "E"] }
            if !e.resampleWrites.isEmpty { moves.append("R") }
            if !e.pureOpening.isEmpty { moves.append("O") }
            if seams < 2, e.current != nil, !e.ended { moves.append("S") }
            if script.isEmpty, e.idle, rng.next() % 5 == 0 { break }
            defer {
                steps.append("  \(trace.last ?? "?"): eng=\(nm(e.current))/arm=\(nm(e.armed))/end=\(e.ended) q=\(e.engineQueue.map(\.kind.description)) in=\(e.inbound.map(\.kind.description)) "
                    + "| vm sel=\(nm(shown(m))) pend=\(nm(pendingURL(m))) play=\(m.isPlaying) ep=\(m.transportEpoch) last=\(m.lastTransitionCount) pub=\(e.published.epoch):\(e.published.transitionCount)")
            }
            switch moves[Int(rng.next() % UInt64(moves.count))] {
            case "U": doVerb(script.removeFirst())
            case "V": e.deliver(Int(rng.next() % UInt64(e.inbound.count))); trace.append("V")
            case "E": e.runEngineOp(); trace.append("E")
            case "R": e.runResampleWrite(); trace.append("R")
            case "O": e.finishPureOpen(Int(rng.next() % UInt64(e.pureOpening.count))); trace.append("O")
            case "S":
                // A2: the VM has made an on-deck request the engine has not resolved yet (still in the
                // VM's Task, inbound, or queued) — the window the design accepts until F1.
                if m.onDeckSequence > e.resolvedMax { a2Seen = true }
                seamSeq = m.onDeckSequence
                e.trackEnds(); seams += 1; trace.append("S")
            case "T":
                let before = m.lastTransitionCount
                let reqBeforeTick = m.onDeckSequence
                tick(m, e); trace.append("T")
                // A2': the VM made an on-deck request AFTER the seam and before this tick saw it.
                if m.lastTransitionCount != before, let s0 = seamSeq, reqBeforeTick > s0 {
                    a2Seen = true
                }
                if m.lastTransitionCount != before { seamSeq = nil }
            default: await drain(); trace.append("D")
            }
        }
        while !script.isEmpty { doVerb(script.removeFirst()) }
        if let s0 = seamSeq, m.onDeckSequence > s0 { a2Seen = true } // requests after a seam the VM has not seen
        await settle(e)
        for _ in 0 ..< 4 { tick(m, e); await settle(e) }
        let plays = e.current != nil && !e.ended
        var kind: String?
        if plays != m.isPlaying {
            kind = plays ? "P4-2: engine plays, app stopped" : "P4-2: app playing, engine silent"
        } else if plays, shown(m) != e.current {
            kind = a2Seen ? "wrong song (A2 residual: a seam beat an unadmitted request)" : "wrong song (NOT A2)"
        } else if plays, pendingURL(m) != e.armed {
            kind = "idle: app next != engine armed"
        }
        if let kind {
            if kind.contains("NOT A2") || kind.contains("idle"), (classes[kind] ?? 0) < 3, CommandLine.arguments.contains("verbose") {
                print("--- NOT-A2 example: pure=\(pure) shuffle=\(m.shuffleEnabled) repeat=\(m.repeatMode) heard=\(e.heard.map(nm)) shows=\(nm(shown(m)))")
                print(steps.joined(separator: "\n"))
            }
            classes[kind, default: 0] += 1
            if firsts[kind] == nil {
                firsts[kind] = "pure=\(pure) shuffle=\(m.shuffleEnabled) repeat=\(m.repeatMode) trace=\(trace.joined(separator: ",")) "
                    + "heard=\(e.heard.map(nm)) shows=\(nm(shown(m))) armed=\(nm(e.armed)) pending=\(nm(pendingURL(m))) log=\(e.log.suffix(3))"
            }
        }
    }
    for (k, v) in classes.sorted(by: { $0.key < $1.key }) {
        print("   [\(modeLabel)] \(v)/\(runs) \(k)\n      first: \(firsts[k]!)")
    }
    return classes
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

// MARK: - run

let args = CommandLine.arguments.dropFirst()
let modes: [ArmMode] = args.contains("ablate")
    ? [.refuse, .clearThenArm, .gatedReplaceAfterOpen, .gatedRetract(endFinal: false), .gatedRetract(endFinal: true)]
    : [.gatedRetract(endFinal: true)]
for mode in modes {
    armMode = mode
    print("===== \(modeLabel)")
    if args.isEmpty || args.contains("cases") || args.contains("monocases") || args.contains("ablate") {
        for pure in [true, false] {
            await d41("playNext", pure: pure) { $0.playNext([file(9)]) }
            await d41("shuffle-on", pure: pure) { $0.toggleShuffle() }
            await d41("shuffle-off", pure: pure, shuffle: true) { $0.toggleShuffle() }
            await d41("repeat-all→one", pure: pure, repeatMode: 1) { $0.cycleRepeatMode() }
            await d41("repeat-one→off", pure: pure, repeatMode: 2) { $0.cycleRepeatMode() }
            await d41("remove-on-deck", pure: pure) { $0.removeTrack(at: 1) }
        }
        await rearmOrder()
        for pure in [true, false] {
            await nextNext(pure: pure, staleStillInbound: false)
            await nextNext(pure: pure, staleStillInbound: true)
        }
        await retractThenEnd()
        await lateArmSameSession()
        for pure in [true, false] {
            await repeatOne(pure: pure)
            await removePlaying(pure: pure)
            for r in 0 ... 2 { await queueOfOne(pure: pure, repeatMode: r) }
            await lateRequest(pure: pure)
        }
        await seekAfterEnd()
    }
    if args.contains("explore") || args.contains("ablate") {
        _ = await explore(runs: 3000, seed: 0xD41D41)
    }
}
if args.contains("overtake") {
    for (mode, mono) in [(ArmMode.refuse, false), (.gatedRetract(endFinal: true), false), (.gatedRetract(endFinal: true), true)] {
        armMode = mode
        for pure in [true, false] {
            let (m, e) = makeVM(6)
            await startPlaying(m, e, at: 0, pure: pure)
            m.playTrack(at: 1)
            m.playTrack(at: 3) // two quick clicks; their start ops reach engineQueue in the other order
            await drain()
            if e.engineQueue.count >= 2 { e.engineQueue.swapAt(0, 1) }
            await settle(e)
            tick(m, e)
            let mid = "after the starts: HEARS \(nm(e.current)) / SHOWS \(nm(shown(m))) armed=\(nm(e.armed)) pending=\(nm(pendingURL(m)))"
            _ = await endAndFollow(m, e)
            print("INFO   START-OVERTAKE/\(modeLabel)\(mono ? "+monotonicSession" : "")/\(pure ? "Pure" : "Enh"): \(mid); after the end: HEARS \(nm(e.current)) / SHOWS \(nm(shown(m))) heard \(e.heard.map(nm))")
        }
    }
}
if args.contains("prime") {
    for pure in [true, false] {
        let (m, e) = makeVM(5)
        m.pureModeEnabled = pure
        m.play() // from stopped: start t0
        await drain()
        e.runEngineOp() // the start lands
        await drain() // the prime: armOnDeck(t1) → request sent
        e.deliver(); e.runEngineOp() // admitted; Pure: t1 opening (Enhanced: slot write queued)
        await drain()
        let playingDuringPrime = m.isPlaying
        m.playNext([file(9)]) // the user: "play t9 next" while the prime's open is in flight
        await drain()
        await settle(e)
        tick(m, e)
        let armedNow = e.armed, pendNow = pendingURL(m)
        _ = await endAndFollow(m, e)
        check(e.current == shown(m) && e.current == url(9), "PLAYNEXT-DURING-PRIME/\(pure ? "Pure" : "Enh")",
              "isPlaying during the prime=\(playingDuringPrime); queue \(m.queue.prefix(4).map { nm($0.file.absoluteURL) }); "
                  + "engine armed \(nm(armedNow)) app next \(nm(pendNow)) → HEARS \(nm(e.current)) / SHOWS \(nm(shown(m)))")
    }
}
if args.contains("verbose") {
    armMode = .gatedRetract(endFinal: true)
    scopedCount = !args.contains("unscoped")
    let seed = UInt64(ProcessInfo.processInfo.environment["P4SEED"] ?? "") ?? 0xD41D41
    _ = await explore(runs: 3000, seed: seed)
}
if args.contains("mono") {
    armMode = .gatedRetract(endFinal: true)
    for scoped in [false, true] {
        scopedCount = scoped
        print("===== explorer \(modeLabel)+monotonicSession epochScopedCount=\(scoped)")
        _ = await explore(runs: 3000, seed: 0xD41D41)
    }
    print("===== cases +monotonicSession")
}
if args.contains("scoped") {
    for mode: ArmMode in [.refuse, .gatedRetract(endFinal: true)] {
        armMode = mode
        for scoped in [false, true] {
            scopedCount = scoped
            print("===== explorer \(modeLabel) epochScopedCount=\(scoped)")
            _ = await explore(runs: 3000, seed: 0xD41D41)
        }
    }
}
print("p4 d41 shipped-code break: \(failures) BROKEN")
