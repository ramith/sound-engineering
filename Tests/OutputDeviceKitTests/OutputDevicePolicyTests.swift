// OUTDEV — the output-device rule (Sprint G break-it blockers 3, 4 and 5): a lost device pauses on
// both paths; a system-default change is re-asserted (pinned) or adopted (follow); a device change
// under Pure moves playback; and the app's own default changes converge instead of looping.

import OutputDeviceKit
import Testing

@Suite("OutputDevicePolicy — what happens when the output changes")
struct OutputDevicePolicyTests {
    private static let deviceA: UInt32 = 82 // the app's device (MacBook Pro Speakers on the test Mac)
    private static let deviceB: UInt32 = 94 // another output (WH-1000XM4)

    private static let allEvents: [OutputDeviceEvent] = [
        .devicesChanged, .defaultChanged, .targetAliveChanged, .engineReconfigured, .enhancedStarting,
    ]

    /// The app's device is the one the user chose, so the chosen device is connected exactly while
    /// it is alive (the N92 cases, where they differ, are in OutputDeviceReturnTests).
    private static func facts(
        target: UInt32 = deviceA,
        alive: Bool = true,
        systemDefault: UInt32 = deviceA,
        playback: OutputPlayback,
        pinned: Bool
    ) -> OutputDeviceFacts {
        OutputDeviceFacts(target: target, targetAlive: alive, systemDefault: systemDefault,
                          playback: playback, pinned: pinned, chosen: alive ? target : 0)
    }

    private static func isNothing(_ action: OutputDeviceAction) -> Bool {
        !action.pauseForDeviceLoss && action.adoptTarget == nil && !action.reassertTarget && !action.reestablishEnhanced
    }

    // MARK: - Blocker 3: the device the app plays on goes away

    @Test("OUTDEV-01: a lost device pauses Enhanced and Pure alike, pinned or not, whatever event says so first")
    func lostDevicePausesBothPaths() {
        for playback in [OutputPlayback.enhanced, .pure] {
            for pinned in [true, false] {
                for event in Self.allEvents where event != .enhancedStarting {
                    // macOS has already moved the default to B (the usual order) …
                    let moved = OutputDevicePolicy.action(
                        for: event,
                        facts: Self.facts(alive: false, systemDefault: Self.deviceB, playback: playback, pinned: pinned)
                    )
                    #expect(moved.pauseForDeviceLoss, "\(event) \(playback) pinned=\(pinned)")
                    #expect(!moved.reestablishEnhanced, "never carries on from the fallback device")
                    #expect(!moved.reassertTarget)
                    // … the dead device can't be kept: the default becomes the app's device (the pill follows).
                    #expect(moved.adoptTarget == Self.deviceB)

                    // … or not yet: still pause, nothing to adopt.
                    let notYet = OutputDevicePolicy.action(
                        for: event, facts: Self.facts(alive: false, playback: playback, pinned: pinned)
                    )
                    #expect(notYet.pauseForDeviceLoss)
                    #expect(notYet.adoptTarget == nil)
                    #expect(!notYet.reestablishEnhanced)
                }
            }
        }
    }

    @Test("OUTDEV-02: a lost device while idle doesn't pause; the pill moves to the system default")
    func lostDeviceWhileIdle() {
        let action = OutputDevicePolicy.action(
            for: .targetAliveChanged,
            facts: Self.facts(alive: false, systemDefault: Self.deviceB, playback: .idle, pinned: true)
        )
        #expect(!action.pauseForDeviceLoss)
        #expect(action.adoptTarget == Self.deviceB)
        #expect(!action.reestablishEnhanced)
    }

    @Test("OUTDEV-03: after the pause (idle), the configuration change the disconnect fires restarts nothing")
    func configChangeAfterPauseStaysStopped() {
        let action = OutputDevicePolicy.action(
            for: .engineReconfigured,
            facts: Self.facts(target: Self.deviceB, systemDefault: Self.deviceB, playback: .idle, pinned: true)
        )
        #expect(Self.isNothing(action))
    }

    // MARK: - Blocker 4: the system default changes outside the app

    @Test("OUTDEV-04: pinned, Enhanced playing: the app's device is put back as the default")
    func pinnedEnhancedReasserts() {
        for event in [OutputDeviceEvent.defaultChanged, .devicesChanged, .targetAliveChanged] {
            let action = OutputDevicePolicy.action(
                for: event,
                facts: Self.facts(systemDefault: Self.deviceB, playback: .enhanced, pinned: true)
            )
            #expect(action.reassertTarget, "\(event)")
            #expect(action.adoptTarget == nil)
            #expect(!action.pauseForDeviceLoss)
            #expect(!action.reestablishEnhanced, "only the configuration change restarts the engine")
        }
        let reconfigured = OutputDevicePolicy.action(
            for: .engineReconfigured,
            facts: Self.facts(systemDefault: Self.deviceB, playback: .enhanced, pinned: true)
        )
        #expect(reconfigured.reassertTarget)
        #expect(reconfigured.reestablishEnhanced)
    }

    @Test("OUTDEV-05: pinned, idle: nothing now (another app's headphones are not undone) …")
    func pinnedIdleWaits() {
        for event in Self.allEvents where event != .enhancedStarting {
            let action = OutputDevicePolicy.action(
                for: event, facts: Self.facts(systemDefault: Self.deviceB, playback: .idle, pinned: true)
            )
            #expect(Self.isNothing(action), "\(event)")
        }
    }

    @Test("OUTDEV-06: … but pressing Play puts the pinned device back before Enhanced starts")
    func pinnedReassertsAtStart() {
        let action = OutputDevicePolicy.action(
            for: .enhancedStarting, facts: Self.facts(systemDefault: Self.deviceB, playback: .idle, pinned: true)
        )
        #expect(action.reassertTarget)
        #expect(action.adoptTarget == nil)
        #expect(!action.pauseForDeviceLoss)
        #expect(!action.reestablishEnhanced)
    }

    @Test("OUTDEV-07: pinned, Pure playing: Pure plays on its device directly — no default fight")
    func pinnedPureLeavesDefault() {
        for event in Self.allEvents where event != .enhancedStarting {
            let action = OutputDevicePolicy.action(
                for: event, facts: Self.facts(systemDefault: Self.deviceB, playback: .pure, pinned: true)
            )
            #expect(Self.isNothing(action), "\(event)")
        }
    }

    @Test("OUTDEV-08: follow: the new default becomes the app's device on every path; Enhanced restarts on it")
    func followAdopts() {
        for playback in [OutputPlayback.idle, .enhanced, .pure] {
            for event in Self.allEvents where event != .enhancedStarting {
                let action = OutputDevicePolicy.action(
                    for: event, facts: Self.facts(systemDefault: Self.deviceB, playback: playback, pinned: false)
                )
                #expect(action.adoptTarget == Self.deviceB, "\(event) \(playback)")
                #expect(!action.reassertTarget)
                #expect(!action.pauseForDeviceLoss)
                // Enhanced must move even if no configuration change is posted; Pure moves through
                // the view model (playbackMovesWithOutput); idle has nothing to restart.
                #expect(action.reestablishEnhanced == (playback == .enhanced), "\(event) \(playback)")
            }
        }
    }

    @Test("OUTDEV-09: follow, about to start: the default is adopted and the start plays on it")
    func followAdoptsAtStart() {
        let action = OutputDevicePolicy.action(
            for: .enhancedStarting, facts: Self.facts(systemDefault: Self.deviceB, playback: .idle, pinned: false)
        )
        #expect(action.adoptTarget == Self.deviceB)
        #expect(!action.reestablishEnhanced)
        #expect(!action.pauseForDeviceLoss)
    }

    @Test("OUTDEV-10: starting on a device that's gone plays on the default instead of pausing")
    func startingOnDeadDevice() {
        for pinned in [true, false] {
            let action = OutputDevicePolicy.action(
                for: .enhancedStarting,
                facts: Self.facts(alive: false, systemDefault: Self.deviceB, playback: .idle, pinned: pinned)
            )
            #expect(!action.pauseForDeviceLoss)
            #expect(action.adoptTarget == Self.deviceB)
            #expect(!action.reestablishEnhanced)
        }
    }

    // MARK: - Convergence: the app's own default changes never loop

    @Test("OUTDEV-11: once the default is the app's device, nothing more is asked for (no loop)")
    func ownChangesConverge() {
        for playback in [OutputPlayback.idle, .enhanced, .pure] {
            for pinned in [true, false] {
                for event in Self.allEvents where event != .engineReconfigured {
                    let action = OutputDevicePolicy.action(
                        for: event, facts: Self.facts(playback: playback, pinned: pinned)
                    )
                    #expect(Self.isNothing(action), "\(event) \(playback) pinned=\(pinned)")
                }
            }
        }
    }

    @Test("OUTDEV-12: applying the action and deciding again asks for nothing more")
    func actionThenSettled() {
        for playback in [OutputPlayback.idle, .enhanced, .pure] {
            for pinned in [true, false] {
                let before = Self.facts(systemDefault: Self.deviceB, playback: playback, pinned: pinned)
                let action = OutputDevicePolicy.action(for: .defaultChanged, facts: before)
                var after = before
                if let adopted = action.adoptTarget {
                    after.target = adopted
                }
                if action.reassertTarget {
                    after.systemDefault = after.target
                }
                // The default change the action itself causes, decided again.
                let again = OutputDevicePolicy.action(for: .defaultChanged, facts: after)
                let settled = !again.reassertTarget && again.adoptTarget == nil && !again.pauseForDeviceLoss
                // Pinned idle/Pure leaves the default elsewhere on purpose — still nothing to do.
                #expect(settled, "\(playback) pinned=\(pinned)")
            }
        }
    }

    @Test("OUTDEV-13: a configuration change with the default on the app's device restarts Enhanced, only")
    func configChangeRestartsEnhancedOnly() {
        for pinned in [true, false] {
            let enhanced = OutputDevicePolicy.action(
                for: .engineReconfigured, facts: Self.facts(playback: .enhanced, pinned: pinned)
            )
            #expect(enhanced.reestablishEnhanced)
            #expect(!enhanced.reassertTarget && enhanced.adoptTarget == nil && !enhanced.pauseForDeviceLoss)
            for playback in [OutputPlayback.idle, .pure] {
                let other = OutputDevicePolicy.action(
                    for: .engineReconfigured, facts: Self.facts(playback: playback, pinned: pinned)
                )
                #expect(Self.isNothing(other), "\(playback): Pure ignores it, idle never seizes the device")
            }
        }
    }

    @Test("OUTDEV-14: no system default at all is never a reason to move")
    func noDefault() {
        for playback in [OutputPlayback.idle, .enhanced, .pure] {
            for pinned in [true, false] {
                let action = OutputDevicePolicy.action(
                    for: .defaultChanged, facts: Self.facts(systemDefault: 0, playback: playback, pinned: pinned)
                )
                #expect(Self.isNothing(action), "\(playback) pinned=\(pinned)")
            }
        }
    }

    // MARK: - Blocker 5: the app's device changes while Pure plays

    @Test("OUTDEV-15: a device change moves playback only for Pure, playing, not after a lost device")
    func pureMovesWithOutput() {
        #expect(OutputDevicePolicy.playbackMovesWithOutput(isPlaying: true, onPure: true, interrupted: false))
        #expect(!OutputDevicePolicy.playbackMovesWithOutput(isPlaying: true, onPure: false, interrupted: false))
        #expect(!OutputDevicePolicy.playbackMovesWithOutput(isPlaying: false, onPure: true, interrupted: false))
        #expect(!OutputDevicePolicy.playbackMovesWithOutput(isPlaying: true, onPure: true, interrupted: true))
    }

    @Test("OUTDEV-16: the action reads in the log")
    func actionDescription() {
        let nothing = OutputDevicePolicy.action(for: .defaultChanged, facts: Self.facts(playback: .idle, pinned: true))
        #expect(nothing.description == "nothing")
        let lost = OutputDevicePolicy.action(
            for: .targetAliveChanged,
            facts: Self.facts(alive: false, systemDefault: Self.deviceB, playback: .enhanced, pinned: true)
        )
        #expect(lost.description == "pause (device lost), adopt \(Self.deviceB)")
    }

    // MARK: - A device-loss pause keeps the song's place

    @Test("OUTDEV-17: a device lost at 1:30 pauses at 1:30, not 0:00")
    func lossKeepsThePlace() {
        #expect(OutputDevicePolicy.resumeAfterDeviceLoss(isPlaying: true, lastPlayhead: 90, duration: 240) == 90)
        // A duration not known yet (an M4A still measuring) keeps the playhead as it is.
        #expect(OutputDevicePolicy.resumeAfterDeviceLoss(isPlaying: true, lastPlayhead: 90, duration: 0) == 90)
    }

    @Test("OUTDEV-18: the kept place stays within the song")
    func lossPlaceClamped() {
        #expect(OutputDevicePolicy.resumeAfterDeviceLoss(isPlaying: true, lastPlayhead: -1, duration: 240) == 0)
        #expect(OutputDevicePolicy.resumeAfterDeviceLoss(isPlaying: true, lastPlayhead: 250, duration: 240) == 240)
        #expect(OutputDevicePolicy.resumeAfterDeviceLoss(isPlaying: true, lastPlayhead: .nan, duration: 240) == 0)
    }

    @Test("OUTDEV-19: nothing playing → no pause to keep; and no device event resumes a lost-device pause")
    func lossWhileStoppedAndNoAutoResume() {
        #expect(OutputDevicePolicy.resumeAfterDeviceLoss(isPlaying: false, lastPlayhead: 90, duration: 240) == nil)
        // After the pause the view model is not playing: a device choice or an adopted default
        // never restarts it (only Play does) — on Pure or not, interrupted or not.
        for onPure in [true, false] {
            for interrupted in [true, false] {
                #expect(!OutputDevicePolicy.playbackMovesWithOutput(isPlaying: false, onPure: onPure,
                                                                    interrupted: interrupted))
            }
        }
        // And the engine's rule asks for no restart while idle, whatever the event (a reconnect too).
        for event in Self.allEvents where event != .enhancedStarting {
            let action = OutputDevicePolicy.action(
                for: event, facts: Self.facts(target: Self.deviceB, systemDefault: Self.deviceB, playback: .idle,
                                              pinned: false)
            )
            #expect(!action.reestablishEnhanced, "\(event)")
        }
    }
}
