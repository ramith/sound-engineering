// The output-device rule over its WHOLE input space (council P5b, extended for N92): every event
// against every combination of facts, checked against rules written from the founder's decisions
// (not from the code); the earlier decisions unchanged wherever the chosen device is the app's
// device; nothing chosen (the launch state) or the choice away answering exactly as follow; device
// 0 never acted on; and a fixed point after every action.

import OutputDeviceKit
import Testing

@Suite("OutputDevicePolicy — the whole input space")
struct OutputDeviceRuleSpaceTests {
    private static let deviceA: UInt32 = 41 // the app's device
    private static let deviceB: UInt32 = 42 // another output, often the new default
    private static let deviceC: UInt32 = 43 // the chosen device back under another id
    private static let events: [OutputDeviceEvent] = [
        .devicesChanged, .defaultChanged, .targetAliveChanged, .engineReconfigured, .enhancedStarting, .choiceRestored,
    ]

    /// playback × pinned × alive × target ∈ {0, A} × default ∈ {0, A, B} × chosen ∈ {0, A, B, C}.
    /// chosen 0 covers both "nothing chosen yet" (the launch state) and "chosen, but away or without
    /// an output stream": the bridge reports both as 0.
    private static var allFacts: [OutputDeviceFacts] {
        var out: [OutputDeviceFacts] = []
        for playback in [OutputPlayback.idle, .enhanced, .pure] {
            for pinned in [false, true] {
                for alive in [false, true] {
                    for target in [0, deviceA] {
                        for systemDefault in [0, deviceA, deviceB] {
                            for chosen in [0, deviceA, deviceB, deviceC] {
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

    private struct Expected: Equatable {
        var pause: Bool
        var adopt: UInt32?
        var reassert: Bool
        var reestablish: Bool
    }

    /// The rules as the founder's decisions state them (OutputDevicePolicy.swift header).
    private static func expected(_ event: OutputDeviceEvent, _ facts: OutputDeviceFacts) -> Expected {
        let starting = event == .enhancedStarting
        // A disconnect pauses what plays (a start isn't playing yet). No device at all is gone too.
        let gone = facts.target == 0 || !facts.targetAlive
        let pause = gone && facts.playback != .idle && !starting
        var want = Expected(pause: pause, adopt: nil, reassert: false, reestablish: false)
        if facts.pinned, facts.chosen != 0 {
            // Pinned with the chosen device here: it is the app's device, put back as the default
            // while Enhanced plays or starts — never idle, never on Pure, never after a pause.
            want.adopt = facts.chosen == facts.target ? nil : facts.chosen
            let enhanced = (starting || facts.playback == .enhanced) && !pause
            want.reassert = enhanced && facts.systemDefault != 0 && facts.systemDefault != facts.chosen
        } else if facts.systemDefault != 0, facts.systemDefault != facts.target {
            // Follow, nothing chosen yet (the device the app starts on is not a choice), or the
            // chosen device away: the system default becomes the app's device.
            want.adopt = facts.systemDefault
        }
        // Enhanced restarts only when its engine stopped (a configuration change) or must move (an
        // adopt) — never on a start (the start runs the engine) and never after a pause.
        want.reestablish = facts.playback == .enhanced && !starting && !pause
            && (event == .engineReconfigured || want.adopt != nil)
        return want
    }

    private static func actual(_ event: OutputDeviceEvent, _ facts: OutputDeviceFacts) -> Expected {
        let action = OutputDevicePolicy.action(for: event, facts: facts)
        return Expected(pause: action.pauseForDeviceLoss, adopt: action.adoptTarget,
                        reassert: action.reassertTarget, reestablish: action.reestablishEnhanced)
    }

    @Test("all 1728 (event × facts) cases agree with the rules written from the founder's decisions")
    func fullInputSpace() {
        var count = 0
        for event in Self.events {
            for facts in Self.allFacts {
                count += 1
                #expect(Self.actual(event, facts) == Self.expected(event, facts), "\(event) \(facts)")
            }
        }
        #expect(count == 1728)
    }

    /// The panel's spec for the rule before N92, verbatim: pinned meant "keep the app's device".
    private static func beforeN92(_ event: OutputDeviceEvent, _ facts: OutputDeviceFacts) -> Expected {
        let starting = event == .enhancedStarting
        let playing = starting || facts.playback != .idle
        let elsewhere = facts.systemDefault != 0 && facts.systemDefault != facts.target
        var want = Expected(pause: false, adopt: nil, reassert: false, reestablish: false)
        if !facts.targetAlive {
            want.pause = playing && !starting
            want.adopt = elsewhere ? facts.systemDefault : nil
        } else if elsewhere, facts.pinned {
            want.reassert = starting || facts.playback == .enhanced
        } else if elsewhere {
            want.adopt = facts.systemDefault
        }
        want.reestablish = facts.targetAlive && !starting && facts.playback == .enhanced
            && (event == .engineReconfigured || want.adopt != nil)
        return want
    }

    @Test("every earlier decision holds where the app's device is the chosen one (or the switch is off)")
    func earlierDecisionsUnchanged() {
        var compared = 0
        for event in Self.events {
            for facts in Self.allFacts where facts.target != 0 {
                // Pinned: the chosen device is the app's device, connected exactly while it is alive.
                if facts.pinned, facts.chosen != (facts.targetAlive ? facts.target : 0) {
                    continue
                }
                compared += 1
                #expect(Self.actual(event, facts) == Self.beforeN92(event, facts), "\(event) \(facts)")
            }
        }
        #expect(compared == 6 * (3 * 2 * 3 * 4 + 3 * 2 * 3)) // follow: any chosen; pinned: one
    }

    @Test("pinned with nothing chosen (the launch state) or the choice away answers exactly as follow")
    func unpickedPinIsFollow() {
        for event in Self.events {
            for facts in Self.allFacts where facts.pinned && facts.chosen == 0 {
                var follow = facts
                follow.pinned = false
                #expect(Self.actual(event, facts) == Self.actual(event, follow), "\(event) \(facts)")
            }
        }
    }

    @Test("device 0 is never adopted, never re-asserted, and only the chosen device is ever re-asserted")
    func deviceZeroNeverAsserted() {
        for event in Self.events {
            for facts in Self.allFacts {
                let action = OutputDevicePolicy.action(for: event, facts: facts)
                #expect(action.adoptTarget != 0, "\(event) \(facts)")
                if action.reassertTarget {
                    let reasserted = action.adoptTarget ?? facts.target
                    #expect(reasserted != 0, "\(event) \(facts)")
                    #expect(facts.pinned && reasserted == facts.chosen, "a fallback put back: \(event) \(facts)")
                }
            }
        }
        // The panel's case: no device, reported alive, pinned, Enhanced, a real default elsewhere.
        let none = OutputDeviceFacts(target: 0, targetAlive: true, systemDefault: Self.deviceB,
                                     playback: .enhanced, pinned: true, chosen: 0)
        for event in Self.events {
            #expect(!OutputDevicePolicy.action(for: event, facts: none).reassertTarget, "\(event)")
        }
    }

    /// What the bridge's acting on `action` changes in the facts the next event sees.
    private static func applied(_ action: OutputDeviceAction, to facts: OutputDeviceFacts) -> OutputDeviceFacts {
        var next = facts
        if action.pauseForDeviceLoss {
            next.playback = .idle
        }
        if let adopted = action.adoptTarget {
            next.target = adopted
            next.targetAlive = true // a default or the chosen device: a live device
        }
        if action.reassertTarget {
            next.systemDefault = next.target
        }
        return next
    }

    @Test("fixed point: after any action, every device event asks for nothing more")
    func fixedPoint() {
        for event in Self.events {
            for facts in Self.allFacts {
                var after = Self.applied(OutputDevicePolicy.action(for: event, facts: facts), to: facts)
                if event == .enhancedStarting {
                    after.playback = .enhanced
                }
                // A start on a dead device with no default to take: it runs, and the next event pauses
                // it (two steps, not a loop).
                let deadStart = event == .enhancedStarting && (after.target == 0 || !after.targetAlive)
                for again in [OutputDeviceEvent.devicesChanged, .defaultChanged, .targetAliveChanged] {
                    let action = OutputDevicePolicy.action(for: again, facts: after)
                    let settled = action.adoptTarget == nil && !action.reassertTarget
                        && (deadStart || !action.pauseForDeviceLoss)
                    #expect(settled, "not settled after \(event) from \(facts): \(again) → \(action)")
                }
            }
        }
    }
}
