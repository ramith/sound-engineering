import OutputDeviceKit
import Synchronization
import Testing

// P5b council panel — the output-device rule over its WHOLE input space, its fixed point, and the
// monitor's event loop as an interleaving model (uncommitted, panel worktree only).

@Suite("P5b output policy — full input space, fixed point, monitor model")
struct P5bOutputPolicyBreakTests {
    static let deviceA: UInt32 = 41 // the device the user chose (AirPods)
    static let deviceB: UInt32 = 42 // the built-in speakers
    static let reassertZero = Mutex(0)
    static let startOnDeadCases = Mutex<[String]>([])
    static let events: [OutputDeviceEvent] = [.devicesChanged, .defaultChanged, .targetAliveChanged,
                                              .engineReconfigured, .enhancedStarting]

    /// Every fact combination: playback × pinned × alive × target ∈ {0, A} × default ∈ {0, A, B}.
    static var allFacts: [OutputDeviceFacts] {
        var out: [OutputDeviceFacts] = []
        for playback in [OutputPlayback.idle, .enhanced, .pure] {
            for pinned in [false, true] {
                for alive in [false, true] {
                    for target in [UInt32(0), deviceA] {
                        for systemDefault in [UInt32(0), deviceA, deviceB] {
                            out.append(OutputDeviceFacts(target: target, targetAlive: alive,
                                                         systemDefault: systemDefault, playback: playback,
                                                         pinned: pinned))
                        }
                    }
                }
            }
        }
        return out
    }

    /// The founder's rules, written from the file header + Sprint G decisions — NOT from the code.
    static func expected(_ event: OutputDeviceEvent, _ f: OutputDeviceFacts) -> (pause: Bool, adopt: UInt32?, reassert: Bool) {
        let starting = event == .enhancedStarting
        let playing = starting || f.playback != .idle
        let elsewhere = f.systemDefault != 0 && f.systemDefault != f.target
        if !f.targetAlive {
            // Lost: pause what plays (a start isn't playing yet), adopt whatever real default there is.
            return (playing && !starting, elsewhere ? f.systemDefault : nil, false)
        }
        if !elsewhere {
            return (false, nil, false)
        }
        if f.pinned {
            // Re-assert only while Enhanced plays or starts; never idle, never Pure.
            let enhanced = starting || f.playback == .enhanced
            return (false, nil, enhanced)
        }
        return (false, f.systemDefault, false) // follow, playing or not
    }

    @Test("all 360 (event × facts) cases agree with the rules written from the spec")
    func fullInputSpace() {
        var count = 0
        for event in Self.events {
            for facts in Self.allFacts {
                count += 1
                let action = OutputDevicePolicy.action(for: event, facts: facts)
                let want = Self.expected(event, facts)
                #expect(action.pauseForDeviceLoss == want.pause, "\(event) \(facts)")
                #expect(action.adoptTarget == want.adopt, "\(event) \(facts)")
                #expect(action.reassertTarget == want.reassert, "\(event) \(facts)")
                // re-establish: only Enhanced, never on a start, never on a lost device, and only when the
                // engine stopped (config change) or must move (adopt).
                let wantRe = facts.targetAlive && event != .enhancedStarting && facts.playback == .enhanced
                    && (event == .engineReconfigured || want.adopt != nil)
                #expect(action.reestablishEnhanced == wantRe, "\(event) \(facts)")
                // Never both adopt and re-assert; never a re-assert of "no device".
                #expect(!(action.adoptTarget != nil && action.reassertTarget))
                if action.reassertTarget, facts.target == 0 {
                    // Unreachable through the monitor (isDeviceAlive(0) == false), so only counted.
                    Self.reassertZero.withLock { $0 += 1 }
                }
            }
        }
        #expect(count == 360)
        print("P5b N92: cases answering 're-assert device 0' (target 0 reported alive): \(Self.reassertZero.withLock { $0 })")
    }

    /// Apply an action's effects to the facts (what the monitor does), returning the facts the NEXT
    /// event sees and the events the effects themselves cause.
    static func apply(_ action: OutputDeviceAction, to f: OutputDeviceFacts) -> (OutputDeviceFacts, [OutputDeviceEvent]) {
        var next = f
        var caused: [OutputDeviceEvent] = []
        if action.pauseForDeviceLoss {
            next.playback = .idle
        }
        if let adopted = action.adoptTarget {
            next.target = adopted
            next.targetAlive = true // the default is a live device
        }
        if action.reassertTarget, next.targetAlive, next.systemDefault != next.target {
            next.systemDefault = next.target
            caused.append(.defaultChanged)
        }
        return (next, caused)
    }

    @Test("fixed point: for every case, applying the action and replaying every non-engine event asks for nothing more")
    func fixedPoint() {
        for event in Self.events {
            for facts in Self.allFacts {
                var f = facts
                var queue: [OutputDeviceEvent] = [event]
                var steps = 0
                while let e = queue.first, steps < 50 {
                    queue.removeFirst()
                    let action = OutputDevicePolicy.action(for: e, facts: f)
                    let (next, caused) = Self.apply(action, to: f)
                    f = next
                    if e == .enhancedStarting {
                        f.playback = .enhanced
                    }
                    queue += caused
                    steps += 1
                }
                #expect(steps < 50, "loop: \(event) \(facts)")
                // A start on a dead device with no other default: the start runs, and the NEXT event
                // pauses it (two steps, not a loop) — counted separately below.
                if event == .enhancedStarting, !facts.targetAlive, !(facts.systemDefault != 0 && facts.systemDefault != facts.target) {
                    Self.startOnDeadCases.withLock { $0.append("\(facts)") }
                    continue
                }
                for again in [OutputDeviceEvent.devicesChanged, .defaultChanged, .targetAliveChanged] {
                    let action = OutputDevicePolicy.action(for: again, facts: f)
                    #expect(action.adoptTarget == nil && !action.reassertTarget && !action.pauseForDeviceLoss,
                            "not settled after \(event) from \(facts): \(again) → \(action)")
                }
            }
        }
        print("P5b N92: Enhanced start on a dead target with no other default (start runs, next event pauses): \(Self.startOnDeadCases.withLock { $0.count }) cases")
    }

    @Test("SCENARIO pinned (the default) → the chosen device drops out and comes back → Play: where does sound go?")
    func pinnedDeviceReconnect() {
        // The user plays on AirPods (A). Pinned is the shipped default (storedPinPlaybackToSelectedDevice = true).
        var f = OutputDeviceFacts(target: Self.deviceA, targetAlive: true, systemDefault: Self.deviceA,
                                  playback: .enhanced, pinned: true)
        // 1. A drops out; macOS moves the default to the speakers (B).
        f.targetAlive = false
        f.systemDefault = Self.deviceB
        let lost = OutputDevicePolicy.action(for: .targetAliveChanged, facts: f)
        #expect(lost.pauseForDeviceLoss) // the founder's rule: pause, never carry on
        #expect(lost.adoptTarget == Self.deviceB) // the pin moves to the speakers
        f.playback = .idle
        f.target = Self.deviceB
        f.targetAlive = true
        // 2. A reconnects; macOS makes the reconnected headphones the default again.
        f.systemDefault = Self.deviceA
        let back = OutputDevicePolicy.action(for: .defaultChanged, facts: f)
        #expect(back.adoptTarget == nil && !back.reassertTarget) // idle: nothing (correct by itself)
        // 3. The user presses Play.
        let play = OutputDevicePolicy.action(for: .enhancedStarting, facts: f)
        print("P5b N92 scenario: after A returns as the default, Play → \(play)")
        // What the founder's rules ask for: "the user can resume playback after reconnecting" (NFR-REL-02),
        // "nothing carries on from another device by itself", pin = keep THIS (the chosen) device.
        #expect(!play.reassertTarget,
                "Play re-asserts the SPEAKERS as the system default over the reconnected headphones")
    }

    @Test("resumeAfterDeviceLoss: total over hostile doubles")
    func resumeTotal() {
        let values: [Double] = [-.infinity, -1, -0.0, 0, 1e-300, 1, 90, 1e308, .infinity, .nan]
        for playhead in values {
            for duration in values {
                guard let resume = OutputDevicePolicy.resumeAfterDeviceLoss(isPlaying: true, lastPlayhead: playhead,
                                                                            duration: duration) else {
                    Issue.record("nil while playing")
                    continue
                }
                #expect(resume.isFinite, "non-finite resume \(resume) for playhead \(playhead) duration \(duration)")
                #expect(resume >= 0)
                if duration > 0, duration.isFinite {
                    #expect(resume <= duration)
                }
            }
        }
    }

    // MARK: N94 — the monitor as an interleaving model (from AudioEngineBridge+OutputDeviceMonitor,
    // +Playback.startEnhancedPlayback, +ConfigChange): the Enhanced start runs on engineQueue as
    // S1 align (read facts, act) → S2 engine.start() (renders on the CURRENT default) → S3 intent = true;
    // the output events run one at a time on configChangeQueue; X = the default moves to B (Control
    // Center, or headphones connecting), which also stops a running engine and posts a config change.

    struct World: Hashable {
        var target: UInt32 = 41
        var systemDefault: UInt32 = 41
        var pinned: Bool
        var intent = false
        var engineRunning = false
        var playsOn: UInt32 = 0
        var queue: [OutputDeviceEvent] = []
        var startStep = 0
        var externalFired = false
        var trace: [String] = []

        func facts(starting: Bool) -> OutputDeviceFacts {
            OutputDeviceFacts(target: target, targetAlive: true, systemDefault: systemDefault,
                              playback: intent ? .enhanced : .idle, pinned: pinned)
        }

        mutating func setDefault(_ device: UInt32) {
            guard systemDefault != device else { return }
            systemDefault = device
            queue.append(.defaultChanged)
            if engineRunning { // AVAudioEngine stops itself on the route change and posts a config change
                engineRunning = false
                queue.append(.engineReconfigured)
            }
        }

        mutating func apply(_ action: OutputDeviceAction) {
            if let adopted = action.adoptTarget {
                target = adopted
            }
            if action.reassertTarget {
                setDefault(target)
            }
            if action.reestablishEnhanced, intent { // reestablish re-reads the intent first
                engineRunning = true
                playsOn = systemDefault
            }
        }
    }

    static func explore(_ w: World, _ out: inout [World]) {
        var moved = false
        if w.startStep < 3 {
            moved = true
            var n = w
            switch n.startStep {
            case 0:
                n.apply(OutputDevicePolicy.action(for: .enhancedStarting, facts: n.facts(starting: true)))
                n.trace.append("S1 align")
            case 1:
                n.engineRunning = true
                n.playsOn = n.systemDefault
                n.trace.append("S2 engine.start (on \(n.systemDefault))")
            default:
                n.intent = true
                n.trace.append("S3 intent=true")
            }
            n.startStep += 1
            explore(n, &out)
        }
        if !w.externalFired {
            moved = true
            var n = w
            n.externalFired = true
            n.setDefault(42)
            n.trace.append("X default→42")
            explore(n, &out)
        }
        if let event = w.queue.first {
            moved = true
            var n = w
            n.queue.removeFirst()
            let action = OutputDevicePolicy.action(for: event, facts: n.facts(starting: false))
            n.apply(action)
            n.trace.append("R \(event) [\(n.intent ? "enhanced" : "idle")] → \(action)")
            explore(n, &out)
        }
        if !moved {
            out.append(w)
        }
    }

    @Test("N94 interleavings of an Enhanced start with a default change: no silent 'playing', pill = the device that plays")
    func monitorInterleavings() {
        for pinned in [true, false] {
            var finals: [World] = []
            Self.explore(World(pinned: pinned), &finals)
            var silent = 0, wrongDevice = 0, pinBroken = 0
            var examples: [String] = []
            for w in finals {
                let isSilent = w.intent && !w.engineRunning
                let isWrong = w.intent && w.engineRunning && w.playsOn != w.target
                let breaksPin = pinned && w.intent && w.engineRunning && w.playsOn != 41
                silent += isSilent ? 1 : 0
                wrongDevice += isWrong ? 1 : 0
                pinBroken += breaksPin ? 1 : 0
                if (isSilent || isWrong || breaksPin) && examples.count < 3 {
                    examples.append((isSilent ? "SILENT: " : isWrong ? "WRONG DEVICE: " : "PIN BROKEN: ") + w.trace.joined(separator: " · "))
                }
            }
            print("P5b N94 pinned=\(pinned): \(finals.count) interleavings; silent-while-playing \(silent); plays on ≠ app device \(wrongDevice); pinned but not on the pinned device \(pinBroken)")
            examples.forEach { print("   " + $0) }
            #expect(silent == 0 && wrongDevice == 0 && pinBroken == 0, "pinned=\(pinned)")
        }
    }
}
