// PANEL P1 SCRATCH (never committed): a model-based fuzz of EQSession's verbs. The app sends
// (points, plays) on `.send`, writes the store on `.saveSlots` and My Presets on `.saveMyPresets`.
// Invariants checked after EVERY verb:
//   I1 what plays (points + plays) changed  => the outcome contains .send
//   I2 no stroke open                         => store/myPresets equal what was last written
//   I3 the store round-trips through JSON     (canonical form survives the codec)
//   I4 cancelStroke right after a stroke      => current and bringBack exactly as before it

@testable import EQEditKit
import Foundation
import Testing

private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func float(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * Float(next() % 10001) / 10000 }
}

@Suite("PANEL P1 — EQSession model fuzz")
struct ZZPanelP1FuzzTests {
    static let outputs: [EQOutputKey?] = [
        nil,
        EQOutputKey(uid: "BuiltInSpeakerDevice", modelUID: nil, name: "Speakers"),
        EQOutputKey(uid: "A4:pods1", modelUID: "AirPods Pro,2", name: "Pods 1"),
        EQOutputKey(uid: "B7:pods2", modelUID: "AirPods Pro,2", name: "Pods 2"),
        EQOutputKey(uid: "USB:Modi:1", modelUID: nil, name: "Modi+"),
        EQOutputKey(uid: "CADefaultDeviceAggregate-123-4", modelUID: nil, name: "Aggregate"),
        EQOutputKey(uid: "", modelUID: nil, name: "No UID"),
    ]
    static let names = ["Late Night", "late night", " Late Night\n", "Warm", "Studio", "Bass & Treble", "Mine", "", "x"]

    @Test("FUZZ: I1–I4 over 400 random sessions × 120 verbs")
    func fuzz() throws {
        var failures: [String] = []
        var pinnedSteps = 0, mineSteps = 0, strokeSteps = 0, sends = 0, comparing = 0
        for seed in 0 ..< 400 {
            var rng = SplitMix(state: UInt64(seed) &* 7919 &+ 17)
            var session = EQSession(store: EQStore(shared: .flat), myPresets: [:])
            var sentPoints = session.points
            var sentPlays = session.plays
            var savedStore = session.store
            var savedMine = session.myPresets
            var pendingSource: EQSaveSource?
            var trace: [String] = []
            for step in 0 ..< 120 {
                let before = (session.current, session.bringBack, session.isStroking)
                var verb = ""
                var outcome = EQOutcome.none
                switch rng.int(22) {
                case 0:
                    let rows = session.presetRows
                    let pick = rows[rng.int(rows.count)]
                    verb = "choose \(pick.displayName)"
                    outcome = session.choose(pick)
                case 1: verb = "reset"; outcome = session.reset()
                case 2: let on = rng.int(2) == 0; verb = "setOn \(on)"; outcome = session.setOn(on)
                case 3: let b = rng.int(31); verb = "resetBand \(b)"; outcome = session.resetBand(b)
                case 4: let b = rng.int(33) - 1; let d = rng.float(-6, 6); verb = "nudge \(b) \(d)"; outcome = session.nudge(band: b, by: d)
                case 5: let r = EQToneRegion.allCases[rng.int(5)]; let d = rng.float(-14, 14); verb = "setTone \(r) \(d)"; outcome = session.setTone(r, to: d)
                case 6: verb = "resetTone"; outcome = session.resetTone()
                case 7, 8: verb = "beginStroke"; outcome = session.beginStroke()
                case 9, 10: let b = rng.int(35) - 2; let d = rng.float(-16, 16); verb = "updateStroke \(b) \(d)"; outcome = session.updateStroke(band: b, db: d)
                case 11: let r = EQToneRegion.allCases[rng.int(5)]; let d = rng.float(-14, 14); verb = "updateStrokeTone \(r) \(d)"; outcome = session.updateStroke(tone: r, to: d)
                case 12: verb = "endStroke"; outcome = session.endStroke()
                case 13:
                    verb = "cancelStroke"
                    let wasStroking = session.isStroking
                    let snapshot = session.stroke
                    outcome = session.cancelStroke()
                    if wasStroking, let snapshot, session.current != snapshot.before || session.bringBack != snapshot.bringBack {
                        failures.append("seed \(seed) step \(step): I4 cancel did not restore")
                    }
                case 14:
                    let audible = EQAudibleState(isOn: session.current.isOn, isComparing: session.isComparing,
                                                 pureModeEngaged: false, engineReady: true)
                    verb = "beginCompare"; outcome = session.beginCompare(when: audible)
                case 15: verb = "endCompare"; outcome = session.endCompare()
                case 16: verb = "togglePin"; outcome = session.togglePin()
                case 17: let o = Self.outputs[rng.int(Self.outputs.count)]; verb = "output \(o?.name ?? "nil")"; outcome = session.outputDidChange(to: o)
                case 18:
                    if pendingSource == nil || rng.int(2) == 0 {
                        verb = "openSave"; pendingSource = session.saveSource()
                    } else if let src = pendingSource {
                        let n = Self.names[rng.int(Self.names.count)]
                        verb = "save '\(n)'"; outcome = session.save(src, as: n); pendingSource = nil
                    }
                case 19:
                    let mine = session.myPresetNames
                    if let from = mine.isEmpty ? nil : mine[rng.int(mine.count)] {
                        let n = Self.names[rng.int(Self.names.count)] + (rng.int(2) == 0 ? "" : "2")
                        verb = "rename '\(from)'→'\(n)'"; outcome = session.renameMyPreset(from, to: n)
                    }
                case 20:
                    let mine = session.myPresetNames
                    if let name = mine.isEmpty ? nil : mine[rng.int(mine.count)] {
                        verb = "delete '\(name)'"; outcome = session.deleteMyPreset(name)
                    }
                default: verb = "bringBack"; outcome = session.bringBackEdits()
                }
                trace.append(verb)
                if !session.store.pinned.isEmpty { pinnedSteps += 1 }; if !session.myPresets.isEmpty { mineSteps += 1 }; if session.isStroking { strokeSteps += 1 }; if outcome.effects.contains(.send) { sends += 1 }; if session.isComparing { comparing += 1 }
                _ = before
                // I1
                if (session.points != sentPoints || session.plays != sentPlays) && !outcome.effects.contains(.send) {
                    failures.append("seed \(seed) step \(step): I1 '\(verb)' changed what plays without .send (plays \(sentPlays)→\(session.plays)); trace tail \(trace.suffix(6))")
                }
                if outcome.effects.contains(.send) { sentPoints = session.points; sentPlays = session.plays }
                if outcome.effects.contains(.saveSlots) { savedStore = session.store }
                if outcome.effects.contains(.saveMyPresets) { savedMine = session.myPresets }
                // I2
                if !session.isStroking {
                    if session.store != savedStore {
                        failures.append("seed \(seed) step \(step): I2 '\(verb)' left the store unwritten; trace tail \(trace.suffix(6))")
                        savedStore = session.store
                    }
                    if session.myPresets != savedMine {
                        failures.append("seed \(seed) step \(step): I2 '\(verb)' left My Presets unwritten")
                        savedMine = session.myPresets
                    }
                }
                // I3
                let data = try JSONEncoder().encode(session.store)
                let back = try JSONDecoder().decode(EQStore.self, from: data)
                if back != session.store {
                    failures.append("seed \(seed) step \(step): I3 store did not round-trip after '\(verb)'")
                }
            }
        }
        let unique = Array(Set(failures.map { $0.components(separatedBy: ": ").dropFirst().joined(separator: ": ").prefix(60) }))
        print("PANEL-P1 FUZZ coverage: pinned \(pinnedSteps) mine \(mineSteps) stroking \(strokeSteps) sends \(sends) comparing \(comparing)")
        print("PANEL-P1 FUZZ failures: \(failures.count); distinct kinds: \(unique.count)")
        for f in failures.prefix(12) { print("PANEL-P1 FUZZ: \(f)") }
        #expect(failures.isEmpty)
    }
}
