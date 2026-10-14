import OutputDeviceKit
import Synchronization
import Testing

// P5b council panel, round 2: break the N92 fix (013faf0). Uncommitted, panel worktree only.
// The properties below are written from the founder-approved behaviour, not from the new code:
//   loss pauses · never auto-jump · idle and Pure never touch the default · the chosen device (by UID)
//   is the target whenever it is connected and the pin is on · a fallback is never re-asserted ·
//   device 0 is never adopted or asserted · follow (pin off) is unchanged · Play on a fallback is no pick.

@Suite("P5b round 2 — the N92 fix: property space, scenarios, flapping, start interleavings")
struct P5bOutputPolicyBreakTests {
    static let headphones: UInt32 = 41 // A: the device the user chose
    static let speakers: UInt32 = 42 // B: the fallback
    static let usb: UInt32 = 43 // C: a third device
    static let headphonesNewID: UInt32 = 51 // A again, reconnected under a new id
    static let events: [OutputDeviceEvent] = [.devicesChanged, .defaultChanged, .targetAliveChanged,
                                              .engineReconfigured, .enhancedStarting]

    // MARK: The pre-fix rule (a206107), kept verbatim as the baseline for "follow is unchanged"

    static func oldRule(_ event: OutputDeviceEvent, _ f: OutputDeviceFacts) -> (pause: Bool, adopt: UInt32?, reassert: Bool, re: Bool) {
        let starting = event == .enhancedStarting
        let playback = starting ? OutputPlayback.enhanced : f.playback
        let elsewhere = f.systemDefault != 0 && f.systemDefault != f.target
        guard f.targetAlive else {
            return (playback != .idle && !starting, elsewhere ? f.systemDefault : nil, false, false)
        }
        var adopt: UInt32?
        var reassert = false
        if elsewhere {
            if f.pinned {
                reassert = playback == .enhanced
            } else {
                adopt = f.systemDefault
            }
        }
        let re = playback == .enhanced && !starting && (event == .engineReconfigured || adopt != nil)
        return (false, adopt, reassert, re)
    }

    /// Every REACHABLE fact combination: target ∈ {0, A, B}, alive only for a real target, default ∈
    /// {0, A, B, C}, chosen ∈ {0, A, B, C} (connected ⇒ alive), playback × pin.
    static var space: [OutputDeviceFacts] {
        var out: [OutputDeviceFacts] = []
        for target in [UInt32(0), headphones, speakers] {
            for alive in target == 0 ? [false] : [false, true] {
                for systemDefault in [UInt32(0), headphones, speakers, usb] {
                    for chosen in [UInt32(0), headphones, speakers, usb] {
                        // The chosen device is connected and alive; the target is the same device only when alive.
                        if chosen != 0, chosen == target, !alive { continue }
                        for playback in [OutputPlayback.idle, .enhanced, .pure] {
                            for pinned in [false, true] {
                                out.append(OutputDeviceFacts(target: target, targetAlive: alive,
                                                             systemDefault: systemDefault, playback: playback,
                                                             pinned: pinned, chosen: chosen))
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    @Test("properties P1–P11 over every reachable (event × facts) case")
    func propertySpace() {
        var cases = 0
        for event in Self.events {
            for f in Self.space {
                cases += 1
                let a = OutputDevicePolicy.action(for: event, facts: f)
                let starting = event == .enhancedStarting
                let playback = starting ? OutputPlayback.enhanced : f.playback
                let destination = a.adoptTarget ?? f.target
                let tag = "\(event) \(f) → \(a)"
                // P1 a loss pauses exactly what plays (a start is not playing yet).
                #expect(a.pauseForDeviceLoss == (!(f.targetAlive && f.target != 0) && playback != .idle && !starting), "P1 \(tag)")
                // P3/P4 idle and Pure never touch the system default.
                if playback != .enhanced {
                    #expect(!a.reassertTarget, "P3/P4 \(tag)")
                }
                // P5 only the chosen device is ever re-asserted; P6 never device 0.
                if a.reassertTarget {
                    #expect(f.pinned && f.chosen != 0 && destination == f.chosen, "P5 \(tag)")
                    #expect(destination != 0, "P6 \(tag)")
                }
                #expect(a.adoptTarget != 0, "P6 adopt 0: \(tag)")
                // P7 pinned with the chosen device connected: it is the app's device.
                if f.pinned, f.chosen != 0 {
                    #expect(destination == f.chosen, "P7 \(tag)")
                }
                // P13 …and the pin holds it as the default while Enhanced plays or starts.
                if f.pinned, f.chosen != 0, playback == .enhanced, !a.pauseForDeviceLoss,
                   f.systemDefault != 0, f.systemDefault != f.chosen {
                    #expect(a.reassertTarget, "P13 pin not held: \(tag)")
                }
                // P8 follow is unchanged from the pre-fix rule.
                if !f.pinned {
                    let old = Self.oldRule(event, f)
                    #expect(a.pauseForDeviceLoss == old.pause && a.adoptTarget == old.adopt
                        && a.reassertTarget == old.reassert && a.reestablishEnhanced == old.re, "P8 follow changed: \(tag) old \(old)")
                }
                // P9 pinned on the chosen device itself: unchanged from the pre-fix pinned rule.
                if f.pinned, f.chosen != 0, f.chosen == f.target, f.targetAlive {
                    let old = Self.oldRule(event, f)
                    #expect(a.pauseForDeviceLoss == old.pause && a.adoptTarget == old.adopt
                        && a.reassertTarget == old.reassert && a.reestablishEnhanced == old.re, "P9 pinned changed: \(tag) old \(old)")
                }
                // P10 pinned with the chosen device away behaves exactly as follow.
                if f.pinned, f.chosen == 0 {
                    var follow = f
                    follow.pinned = false
                    #expect(a == OutputDevicePolicy.action(for: event, facts: follow), "P10 \(tag)")
                }
                // P11 re-establish: Enhanced only, never on a start or a pause, only when the engine stopped or must move.
                #expect(a.reestablishEnhanced == (playback == .enhanced && !starting && !a.pauseForDeviceLoss
                        && (event == .engineReconfigured || a.adoptTarget != nil)), "P11 \(tag)")
                // P12 a start never pauses or restarts.
                if starting {
                    #expect(!a.pauseForDeviceLoss && !a.reestablishEnhanced)
                }
            }
        }
        print("P5b R2: property space \(cases) cases")
    }

    @Test("fixed point: apply, replay every non-engine event — nothing more, no loop (every reachable case)")
    func fixedPoint() {
        var twoStep = 0
        for event in Self.events {
            for start in Self.space {
                var f = start
                var queue: [OutputDeviceEvent] = [event]
                var steps = 0
                while !queue.isEmpty, steps < 50 {
                    let e = queue.removeFirst()
                    let a = OutputDevicePolicy.action(for: e, facts: f)
                    if a.pauseForDeviceLoss {
                        f.playback = .idle
                    }
                    if let adopted = a.adoptTarget {
                        f.target = adopted
                        f.targetAlive = true // the chosen device or the default: connected
                    }
                    if a.reassertTarget, f.systemDefault != f.target {
                        f.systemDefault = f.target
                        queue.append(.defaultChanged)
                    }
                    if e == .enhancedStarting {
                        f.playback = .enhanced
                    }
                    steps += 1
                }
                #expect(steps < 50, "loop: \(event) \(start)")
                if event == .enhancedStarting, !(f.targetAlive && f.target != 0) {
                    twoStep += 1 // a start with nowhere to go: the next event pauses it
                    continue
                }
                for again in [OutputDeviceEvent.devicesChanged, .defaultChanged, .targetAliveChanged] {
                    let a = OutputDevicePolicy.action(for: again, facts: f)
                    #expect(a.adoptTarget == nil && !a.reassertTarget && !a.pauseForDeviceLoss,
                            "not settled after \(event) from \(start): \(again) → \(a)")
                }
            }
        }
        print("P5b R2: starts with no live device to play on (settle on the next event): \(twoStep)")
    }

    // MARK: A world: CoreAudio by UID + the real OutputDeviceSelection + the real rule

    struct World {
        var devices: [UInt32: String] // connected, alive: id → UID
        var systemDefault: UInt32
        var selection = OutputDeviceSelection()
        var playback = OutputPlayback.idle
        var log: [String] = []
        var reassertedNonChosen = false
        var reassertedZero = false

        var chosenID: UInt32 {
            devices.first { $0.value == selection.chosenUID && !selection.chosenUID.isEmpty }?.key ?? 0
        }

        func facts() -> OutputDeviceFacts {
            OutputDeviceFacts(target: selection.target, targetAlive: devices[selection.target] != nil,
                              systemDefault: systemDefault, playback: playback, pinned: selection.pinned,
                              chosen: chosenID)
        }

        var soundsOn: UInt32 {
            switch playback {
            case .idle: 0
            case .enhanced: systemDefault
            case .pure: selection.target
            }
        }

        @discardableResult
        mutating func handle(_ event: OutputDeviceEvent) -> OutputDeviceAction {
            let before = facts()
            let a = OutputDevicePolicy.action(for: event, facts: before)
            if a.pauseForDeviceLoss {
                playback = .idle
            }
            if let adopted = a.adoptTarget {
                selection.adopt(adopted, uid: devices[adopted] ?? "")
            }
            if a.reassertTarget {
                let t = selection.target
                if t == 0 { reassertedZero = true }
                if devices[t] != selection.chosenUID || selection.chosenUID.isEmpty { reassertedNonChosen = true }
                if devices[t] != nil { systemDefault = t } // a gone device can't become the default
            }
            log.append("\(event): \(a)")
            return a
        }

        mutating func settle() {
            for _ in 0 ..< 3 {
                for e in [OutputDeviceEvent.targetAliveChanged, .devicesChanged, .defaultChanged] {
                    handle(e)
                }
            }
        }

        mutating func pick(_ device: UInt32) {
            selection.choose(device, uid: devices[device] ?? "")
            systemDefault = device
        }

        mutating func play() {
            handle(.enhancedStarting)
            playback = .enhanced
        }
    }

    static func world(chosen: UInt32 = headphones, pinned: Bool = true) -> World {
        var w = World(devices: [headphones: "AirPods-UID", speakers: "BuiltInSpeaker-UID"], systemDefault: chosen)
        w.pick(chosen)
        w.selection.pin(pinned)
        return w
    }

    @Test("S1 the panel's scenario: A drops, comes back as the default, Play → plays on A, default untouched")
    func reconnectThenPlay() {
        var w = Self.world()
        w.play()
        w.devices[Self.headphones] = nil
        w.systemDefault = Self.speakers
        w.settle()
        #expect(w.playback == .idle && w.selection.target == Self.speakers)
        w.devices[Self.headphones] = "AirPods-UID"
        w.systemDefault = Self.headphones
        w.settle()
        w.play()
        #expect(w.soundsOn == Self.headphones && w.systemDefault == Self.headphones, "\(w.log)")
        #expect(!w.reassertedNonChosen)
    }

    @Test("S2 A returns under a NEW id and macOS does NOT make it the default → Play plays on A")
    func reconnectNewIDNoDefault() {
        var w = Self.world()
        w.play()
        w.devices[Self.headphones] = nil
        w.systemDefault = Self.speakers
        w.settle()
        w.devices[Self.headphonesNewID] = "AirPods-UID"
        w.settle()
        #expect(w.selection.target == Self.headphonesNewID)
        w.play()
        #expect(w.soundsOn == Self.headphonesNewID, "\(w.log)")
    }

    @Test("S3 resumed on the fallback (Enhanced), then A returns mid-play: playback moves to A, no pause, no loop")
    func returnsMidPlay() {
        var w = Self.world()
        w.play()
        w.devices[Self.headphones] = nil
        w.systemDefault = Self.speakers
        w.settle()
        w.play() // the user resumes on the speakers — not a pick
        #expect(w.selection.chosenUID == "AirPods-UID")
        #expect(w.soundsOn == Self.speakers)
        w.devices[Self.headphones] = "AirPods-UID" // returns; macOS leaves the default on the speakers
        let a = w.handle(.devicesChanged)
        #expect(a.adoptTarget == Self.headphones && a.reassertTarget && a.reestablishEnhanced && !a.pauseForDeviceLoss)
        w.settle()
        #expect(w.soundsOn == Self.headphones && w.playback == .enhanced, "\(w.log)")
    }

    @Test("S4 an explicit pick of the speakers sticks when the headphones come back")
    func pickOfSpeakersSticks() {
        var w = Self.world()
        w.pick(Self.speakers)
        w.devices[Self.headphones] = nil
        w.settle()
        w.devices[Self.headphones] = "AirPods-UID"
        w.systemDefault = Self.headphones
        w.settle()
        w.play()
        #expect(w.soundsOn == Self.speakers && w.selection.chosenUID == "BuiltInSpeaker-UID")
    }

    @Test("S5 Pure on the fallback, A returns: target moves (the VM restarts Pure there), default untouched")
    func pureReturn() {
        var w = Self.world()
        w.playback = .pure
        w.devices[Self.headphones] = nil
        w.systemDefault = Self.speakers
        w.settle() // pause + adopt speakers
        w.playback = .pure // the user resumes on Pure on the speakers
        w.devices[Self.headphones] = "AirPods-UID"
        let a = w.handle(.devicesChanged)
        #expect(a.adoptTarget == Self.headphones && !a.reassertTarget && !a.reestablishEnhanced && !a.pauseForDeviceLoss)
        #expect(OutputDevicePolicy.playbackMovesWithOutput(isPlaying: true, onPure: true, interrupted: false))
        #expect(w.systemDefault == Self.speakers)
    }

    @Test("S6 pin turned off while the chosen device is away, then on again: the fallback becomes the choice (a user act)")
    func pinToggleWhileAway() {
        var w = Self.world()
        w.devices[Self.headphones] = nil
        w.systemDefault = Self.speakers
        w.settle()
        w.selection.pin(false)
        w.selection.pin(true)
        print("P5b R2 S6: after off→on while away, chosen = \(w.selection.chosenUID)")
        #expect(w.selection.chosenUID == "BuiltInSpeaker-UID") // documented: turning the switch on chooses the device in use
    }

    // MARK: Flapping — random device churn, random Play / Pause / picks, the real rule

    @Test("S7 flapping: 20 000 random histories — never a fallback or 0 re-asserted, settles, chosen wins when present")
    func flapping() {
        var rng = SystemRandomNumberGenerator()
        let uids: [UInt32: String] = [Self.headphones: "A", Self.speakers: "B", Self.usb: "C", Self.headphonesNewID: "A"]
        var violations: [String] = []
        for _ in 0 ..< 20000 {
            var w = World(devices: [Self.speakers: "B"], systemDefault: Self.speakers)
            w.pick([Self.headphones, Self.usb].randomElement(using: &rng)!)
            w.devices[w.selection.target] = uids[w.selection.target]
            if Bool.random(using: &rng) { w.selection.pin(false) }
            let pinnedOn = w.selection.pinned
            for _ in 0 ..< 12 {
                switch Int.random(in: 0 ..< 7, using: &rng) {
                case 0, 1: // A (old or new id) or C leaves; macOS moves the default to a remaining device
                    let gone = [Self.headphones, Self.headphonesNewID, Self.usb].randomElement(using: &rng)!
                    w.devices[gone] = nil
                    if w.devices[w.systemDefault] == nil { w.systemDefault = w.devices.keys.sorted().first ?? 0 }
                case 2, 3: // A (under either id, never both) or C connects; maybe takes the default
                    let back = [Self.headphones, Self.headphonesNewID, Self.usb].randomElement(using: &rng)!
                    if back != Self.usb { w.devices[Self.headphones] = nil; w.devices[Self.headphonesNewID] = nil }
                    w.devices[back] = uids[back]
                    if Bool.random(using: &rng) { w.systemDefault = back }
                case 4: w.play()
                case 5: w.playback = .idle // pause
                default: // Control Center
                    if let any = w.devices.keys.randomElement(using: &rng) { w.systemDefault = any }
                }
                w.settle()
                let f = w.facts()
                if w.reassertedNonChosen || w.reassertedZero { violations.append("re-asserted non-chosen/0: \(w.log.suffix(6))"); break }
                if pinnedOn, f.chosen != 0, w.selection.target != f.chosen { violations.append("chosen present, not target: \(f)"); break }
                if w.playback != .idle, !(f.targetAlive && f.target != 0) { violations.append("playing on a dead target: \(f)"); break }
                if !pinnedOn, f.systemDefault != 0, w.selection.target != f.systemDefault { violations.append("follow off the default: \(f)"); break }
                // settled: one more pass asks for nothing
                let again = OutputDevicePolicy.action(for: .devicesChanged, facts: f)
                if again.adoptTarget != nil || again.reassertTarget { violations.append("unsettled: \(f) → \(again)"); break }
            }
            if violations.count > 5 { break }
        }
        print("P5b R2 flapping violations: \(violations.count)"); violations.prefix(3).forEach { print("   " + $0) }
        #expect(violations.isEmpty)
    }

    // MARK: N94 — does the fix widen the start / monitor window? Old rule vs new rule, same model.

    enum External: CaseIterable { case defaultMoves, chosenLeaves, chosenReturns }

    struct StartWorld: Hashable {
        var alive: Set<UInt32>
        var target: UInt32
        var systemDefault: UInt32
        var pinned: Bool
        var intent = false
        var engineRunning = false
        var playsOn: UInt32 = 0
        var queue: [OutputDeviceEvent] = []
        var step = 0
        var fired = false
        var badAssert = false
        var trace: [String] = []

        var chosen: UInt32 { alive.contains(41) ? 41 : 0 }

        func facts() -> OutputDeviceFacts {
            OutputDeviceFacts(target: target, targetAlive: alive.contains(target), systemDefault: systemDefault,
                              playback: intent ? .enhanced : .idle, pinned: pinned, chosen: chosen)
        }

        mutating func setDefault(_ d: UInt32) {
            guard d != systemDefault, alive.contains(d) else { return }
            systemDefault = d
            queue.append(.defaultChanged)
            if engineRunning { engineRunning = false; queue.append(.engineReconfigured) }
        }

        mutating func apply(_ a: OutputDeviceAction) {
            if a.pauseForDeviceLoss { intent = false; engineRunning = false }
            if let x = a.adoptTarget { target = x }
            if a.reassertTarget {
                if target != 41 || target == 0 { badAssert = true }
                setDefault(target)
            }
            if a.reestablishEnhanced, intent { engineRunning = true; playsOn = systemDefault }
        }

        mutating func fire(_ x: External) {
            switch x {
            case .defaultMoves: setDefault(42)
            case .chosenLeaves:
                alive.remove(41)
                queue.append(.devicesChanged)
                if target == 41 {
                    if intent { intent = false; engineRunning = false } // targetAliveDidChange pauses first
                    queue.append(.targetAliveChanged)
                }
                if systemDefault == 41 { systemDefault = 42; queue.append(.defaultChanged) }
                if engineRunning, playsOn == 41 { engineRunning = false; queue.append(.engineReconfigured) }
            case .chosenReturns:
                alive.insert(41)
                queue.append(.devicesChanged)
                setDefault(41) // macOS auto-switches to the returning headphones
            }
        }
    }

    static func explore(_ w: StartWorld, _ x: External, rule: (OutputDeviceEvent, OutputDeviceFacts) -> OutputDeviceAction,
                        _ out: inout [StartWorld]) {
        var moved = false
        if w.step < 3 {
            moved = true
            var n = w
            switch n.step {
            case 0: n.apply(rule(.enhancedStarting, n.facts())); n.trace.append("S1 align")
            case 1: n.engineRunning = true; n.playsOn = n.systemDefault; n.trace.append("S2 start on \(n.systemDefault)")
            default: n.intent = true; n.trace.append("S3 intent")
            }
            n.step += 1
            explore(n, x, rule: rule, &out)
        }
        if !w.fired {
            moved = true
            var n = w
            n.fired = true
            n.fire(x)
            n.trace.append("X \(x)")
            explore(n, x, rule: rule, &out)
        }
        if let e = w.queue.first {
            moved = true
            var n = w
            n.queue.removeFirst()
            let a = rule(e, n.facts())
            n.apply(a)
            n.trace.append("R \(e)[\(n.intent ? "enh" : "idle")]→\(a)")
            explore(n, x, rule: rule, &out)
        }
        if !moved { out.append(w) }
    }

    struct Outcome {
        var silent = 0, wrongDevice = 0, notChosen = 0, badAssert = 0, total = 0
        var example = ""
    }

    static func run(_ x: External, pinned: Bool, newRule: Bool) -> Outcome {
        var start: StartWorld
        switch x {
        case .defaultMoves: start = StartWorld(alive: [41, 42], target: 41, systemDefault: 41, pinned: pinned)
        case .chosenLeaves: start = StartWorld(alive: [41, 42], target: 41, systemDefault: 41, pinned: pinned)
        case .chosenReturns: start = StartWorld(alive: [42], target: 42, systemDefault: 42, pinned: pinned)
        }
        var finals: [StartWorld] = []
        let rule: (OutputDeviceEvent, OutputDeviceFacts) -> OutputDeviceAction = { e, f in
            if newRule { return OutputDevicePolicy.action(for: e, facts: f) }
            // Pre-fix behaviour through the new rule (valid because P8/P9 prove them equal there):
            // the pin held whatever the target was, while it was alive.
            var old = f
            old.chosen = f.targetAlive ? f.target : 0
            return OutputDevicePolicy.action(for: e, facts: old)
        }
        explore(start, x, rule: rule, &finals)
        var o = Outcome(total: finals.count)
        for w in finals {
            let silent = w.intent && !w.engineRunning
            let wrong = w.intent && w.engineRunning && w.playsOn != w.target
            let notChosen = pinned && w.intent && w.engineRunning && w.chosen != 0 && w.playsOn != w.chosen
            o.silent += silent ? 1 : 0
            o.wrongDevice += wrong ? 1 : 0
            o.notChosen += notChosen ? 1 : 0
            o.badAssert += w.badAssert && newRule ? 1 : 0
            if (silent || wrong || notChosen || (w.badAssert && newRule)), o.example.isEmpty {
                o.example = (silent ? "SILENT " : wrong ? "WRONG " : notChosen ? "NOT-CHOSEN " : "BAD-ASSERT ") + w.trace.joined(separator: " · ")
            }
        }
        return o
    }

    @Test("N94 rerun: start × {default moves, chosen leaves, chosen returns} × pin — pre-fix vs fix")
    func startWindow() {
        for x in External.allCases {
            for pinned in [true, false] {
                let old = Self.run(x, pinned: pinned, newRule: false)
                let new = Self.run(x, pinned: pinned, newRule: true)
                print("P5b R2 N94 \(x) pinned=\(pinned): pre-fix silent \(old.silent) wrong \(old.wrongDevice) not-chosen \(old.notChosen) / \(old.total)  →  fix silent \(new.silent) wrong \(new.wrongDevice) not-chosen \(new.notChosen) bad-assert \(new.badAssert) / \(new.total)")
                if !new.example.isEmpty { print("     fix example: \(new.example)") }
                #expect(new.badAssert == 0, "a non-chosen device or 0 re-asserted during a start")
                #expect(new.silent + new.wrongDevice <= old.silent + old.wrongDevice, "the fix widens the N94 window for \(x) pinned=\(pinned)")
            }
        }
    }
}
