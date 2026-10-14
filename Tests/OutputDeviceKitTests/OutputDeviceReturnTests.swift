// N92 — "Return to headphones" (R1): the pin holds the device the user chose, by UID, not the
// fallback the app moved to when it went away. Each scenario runs the real selection and rule in an
// `OutputWorld`; the headphones drop out, macOS moves the default to the speakers, and they return.

import OutputDeviceKit
import Testing

@Suite("Output device — playback returns to the device the user chose")
struct OutputDeviceReturnTests {
    private static let headphones: UInt32 = 41 // the device the user chose
    private static let speakers: UInt32 = 42 // where macOS falls back
    private static let headphonesUID = "AA-BB-CC-DD-EE-FF:output"
    private static let speakersUID = "BuiltInSpeakerDevice"

    /// The user plays on the headphones (pinned, the shipped default), and they drop out: the app
    /// pauses on the speakers macOS moved the default to.
    private static func lostHeadphones() -> OutputWorld {
        var world = OutputWorld(devices: [headphones: headphonesUID, speakers: speakersUID], systemDefault: headphones)
        world.pick(headphones)
        world.playEnhanced()
        world.disconnect(headphones, defaultMovesTo: speakers)
        let lost = world.settle()
        #expect(lost[0].pauseForDeviceLoss, "a lost device pauses (founder decision)")
        #expect(lost.dropFirst().allSatisfy { $0.description == "nothing" })
        #expect(world.playback == .idle)
        #expect(world.selection.target == speakers, "the app falls back to the new default")
        #expect(world.chosenUID == headphonesUID, "the fallback is temporary: the choice stays")
        return world
    }

    @Test("the headphones come back while paused: Play plays on them, not the speakers")
    func chosenDeviceReturnsBeforePlay() {
        for takesDefault in [true, false] {
            var world = Self.lostHeadphones()
            world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: takesDefault)
            let back = world.settle()
            #expect(back.contains { $0.adoptTarget == Self.headphones }, "takesDefault=\(takesDefault)")
            #expect(back.allSatisfy { !$0.reassertTarget }, "idle: the default is never touched")
            #expect(world.selection.target == Self.headphones, "the pill shows the headphones again")
            #expect(world.playback == .idle, "a device event never resumes playback")
            let play = world.playEnhanced()
            #expect(play.reassertTarget == !takesDefault, "the start puts the headphones back if needed")
            #expect(world.soundsOn == Self.headphones, "takesDefault=\(takesDefault)")
        }
    }

    @Test("resumed on the speakers, then the headphones come back: Enhanced moves back to them")
    func resumedOnFallbackEnhancedMovesBack() {
        for takesDefault in [true, false] {
            var world = Self.lostHeadphones()
            let resume = world.playEnhanced()
            #expect(!resume.reassertTarget && resume.adoptTarget == nil)
            #expect(world.soundsOn == Self.speakers)
            #expect(world.chosenUID == Self.headphonesUID, "Play on a fallback is not a pick")
            world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: takesDefault)
            let back = world.settle()
            #expect(back[0].adoptTarget == Self.headphones)
            #expect(back[0].reassertTarget == !takesDefault, "the default moves to the headphones")
            #expect(back[0].reestablishEnhanced, "the engine restarts on them at the playhead")
            #expect(!back[0].pauseForDeviceLoss)
            #expect(back.dropFirst().allSatisfy { $0.description == "nothing" }, "settled, no loop")
            #expect(world.soundsOn == Self.headphones, "takesDefault=\(takesDefault)")
        }
    }

    @Test("resumed on the speakers on Pure, then the headphones come back: playback moves with the output")
    func resumedOnFallbackPureMovesBack() {
        var world = Self.lostHeadphones()
        world.playPure()
        #expect(world.soundsOn == Self.speakers)
        world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: false)
        let back = world.settle()
        #expect(back[0].adoptTarget == Self.headphones)
        #expect(!back[0].reassertTarget, "Pure plays on its device: no default to fight")
        #expect(!back[0].reestablishEnhanced)
        // The view model's existing path restarts Pure on the adopted device at the playhead.
        #expect(OutputDevicePolicy.playbackMovesWithOutput(isPlaying: true, onPure: true, interrupted: false))
        #expect(world.soundsOn == Self.headphones)
    }

    @Test("the headphones come back under a new device id: the same UID finds them")
    func chosenDeviceReturnsWithNewID() {
        let newID: UInt32 = 57
        var world = Self.lostHeadphones()
        world.playEnhanced() // resumed on the speakers
        world.connect(newID, uid: Self.headphonesUID, takesDefault: true)
        let back = world.settle()
        #expect(back[0].adoptTarget == newID)
        #expect(world.selection.target == newID)
        #expect(world.soundsOn == newID)
        #expect(world.chosenUID == Self.headphonesUID)
    }

    @Test("a pick of the speakers sticks: the headphones coming back don't take playback")
    func explicitPickOfSpeakersSticks() {
        var world = Self.lostHeadphones()
        world.pick(Self.speakers)
        #expect(world.chosenUID == Self.speakersUID)
        world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: true)
        let back = world.settle()
        #expect(back.allSatisfy { $0.adoptTarget == nil }, "pinned to the speakers now")
        #expect(world.selection.target == Self.speakers)
        let play = world.playEnhanced()
        #expect(play.reassertTarget, "Play puts the user's speakers back over the headphones")
        #expect(world.soundsOn == Self.speakers)
        // And while it plays, the headphones taking the default again are answered the same way.
        world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: true)
        #expect(world.handle(.defaultChanged).reassertTarget)
        #expect(world.soundsOn == Self.speakers)
    }

    @Test("while the chosen device is away, a fallback is never put back: the app follows the default")
    func fallbackIsNeverReasserted() {
        let otherHeadphones: UInt32 = 43
        var world = Self.lostHeadphones()
        world.playEnhanced() // resumed on the speakers
        world.connect(otherHeadphones, uid: "other-headphones", takesDefault: true)
        let moved = world.handle(.defaultChanged)
        #expect(!moved.reassertTarget, "the speakers were never the user's pick")
        #expect(moved.adoptTarget == otherHeadphones)
        #expect(moved.reestablishEnhanced, "the pill, the EQ and the engine follow the sound")
        #expect(world.soundsOn == otherHeadphones)
        #expect(world.chosenUID == Self.headphonesUID)
    }

    @Test("the switch keeps the device in use: turning it on chooses it, wherever the app followed to")
    func turningThePinOnKeepsTheDeviceInUse() {
        var world = OutputWorld(devices: [Self.headphones: Self.headphonesUID, Self.speakers: Self.speakersUID],
                                systemDefault: Self.headphones)
        world.pick(Self.headphones)
        world.selection.pin(false) // follow
        world.systemDefault = Self.speakers // Control Center
        #expect(world.handle(.defaultChanged).adoptTarget == Self.speakers)
        world.selection.pin(true) // "Keep playback on this device" — the speakers, shown in the pill
        #expect(world.chosenUID == Self.speakersUID)
        world.systemDefault = Self.headphones
        #expect(world.handle(.defaultChanged).description == "nothing", "idle: the pin doesn't jump")
        #expect(world.playEnhanced().reassertTarget)
        #expect(world.soundsOn == Self.speakers)
        world.selection.pin(true) // already on: nothing changes
        #expect(world.chosenUID == Self.speakersUID)
    }

    @Test("only the user moves the choice: an adopt moves the target and keeps the choice")
    func selectionRoles() {
        var selection = OutputDeviceSelection()
        #expect(selection.pinned && selection.target == 0 && selection.chosenUID.isEmpty)
        selection.choose(Self.headphones, uid: Self.headphonesUID)
        #expect(selection.target == Self.headphones && selection.chosenUID == Self.headphonesUID)
        selection.adopt(Self.speakers, uid: Self.speakersUID)
        #expect(selection.target == Self.speakers && selection.chosenUID == Self.headphonesUID)
        selection.pin(false)
        selection.adopt(Self.headphones, uid: Self.headphonesUID)
        #expect(!selection.pinned && selection.chosenUID == Self.headphonesUID)
    }
}
