// What counts as the user's choice (R1 follow-ups to N92): the device the app starts on is not one
// (founder decision), a re-initialization keeps the one the user made, a chosen device is back only
// once it has an output to play on, and a pick the system refuses takes back only itself.

import OutputDeviceKit
import Testing

@Suite("Output device — what counts as the user's choice")
struct OutputDeviceChoiceTests {
    private static let headphones: UInt32 = 41
    private static let speakers: UInt32 = 42
    private static let other: UInt32 = 43
    private static let headphonesUID = "AA-BB-CC-DD-EE-FF:output"
    private static let speakersUID = "BuiltInSpeakerDevice"

    @Test("launched on the speakers, headphones connect: Play plays on the headphones (nothing chosen yet)")
    func launchDeviceIsNotAChoice() {
        var world = OutputWorld(devices: [Self.speakers: Self.speakersUID], systemDefault: Self.speakers)
        world.start()
        #expect(world.chosenUID.isEmpty, "starting on a device is not a pick")
        #expect(world.selection.pinned, "the switch is on, as shipped")
        world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: true)
        let connected = world.settle()
        #expect(connected[0].adoptTarget == Self.headphones, "pinned with nothing chosen follows the default")
        #expect(connected.allSatisfy { !$0.reassertTarget })
        let play = world.playEnhanced()
        #expect(!play.reassertTarget, "Play never forces the speakers back")
        #expect(world.soundsOn == Self.headphones)
    }

    @Test("launched on the speakers and playing, headphones connect: playback follows them")
    func launchDeviceIsNotAChoiceWhilePlaying() {
        var world = OutputWorld(devices: [Self.speakers: Self.speakersUID], systemDefault: Self.speakers)
        world.start()
        world.playEnhanced()
        world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: true)
        let connected = world.handle(.defaultChanged)
        #expect(connected.adoptTarget == Self.headphones)
        #expect(!connected.reassertTarget)
        #expect(connected.reestablishEnhanced)
        #expect(world.soundsOn == Self.headphones)
    }

    @Test("a re-initialization while the chosen device is away keeps the choice; it returns to it")
    func reinitializationKeepsTheChoice() {
        var world = OutputWorld(devices: [Self.headphones: Self.headphonesUID, Self.speakers: Self.speakersUID],
                                systemDefault: Self.headphones)
        world.pick(Self.headphones)
        world.disconnect(Self.headphones, defaultMovesTo: Self.speakers)
        world.settle()
        world.start() // the Retry banner, or the engine-not-initialized self-heal
        #expect(world.selection.target == Self.speakers)
        #expect(world.chosenUID == Self.headphonesUID, "the fallback at re-init is not a pick")
        world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: false)
        #expect(world.settle()[0].adoptTarget == Self.headphones)
        #expect(world.playEnhanced().reassertTarget)
        #expect(world.soundsOn == Self.headphones)
    }

    /// Headphones chosen, lost; the app is on the speakers, `playing` or paused.
    private static func lostHeadphones(playing: Bool) -> OutputWorld {
        var world = OutputWorld(devices: [headphones: headphonesUID, speakers: speakersUID], systemDefault: headphones)
        world.pick(headphones)
        world.disconnect(headphones, defaultMovesTo: speakers)
        world.settle()
        if playing {
            world.playEnhanced() // resumed on the fallback
        }
        return world
    }

    @Test("chosen headphones back without an output stream yet: not targeted, not re-asserted, until it exists")
    func chosenDeviceWithoutOutputIsNotBack() {
        // Playing on the fallback: nothing moves until the output exists and macOS switches to it.
        var playing = Self.lostHeadphones(playing: true)
        playing.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: false, outputReady: false)
        #expect(playing.settle().allSatisfy { $0.description == "nothing" })
        #expect(playing.selection.target == Self.speakers)
        #expect(playing.soundsOn == Self.speakers, "never silent on a device with no output")
        playing.outputAppears(Self.headphones)
        playing.systemDefault = Self.headphones // macOS switches once the headphones are ready
        let ready = playing.handle(.defaultChanged)
        #expect(ready.adoptTarget == Self.headphones && ready.reestablishEnhanced)
        #expect(playing.soundsOn == Self.headphones)

        // Paused: Play before the output exists stays on the speakers; Play after it plays on them.
        var paused = Self.lostHeadphones(playing: false)
        paused.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: false, outputReady: false)
        #expect(paused.settle().allSatisfy { $0.description == "nothing" })
        let early = paused.playEnhanced()
        #expect(!early.reassertTarget && early.adoptTarget == nil)
        #expect(paused.soundsOn == Self.speakers)
        paused.playback = .idle // paused again
        paused.outputAppears(Self.headphones)
        let late = paused.playEnhanced()
        #expect(late.adoptTarget == Self.headphones && late.reassertTarget)
        #expect(paused.soundsOn == Self.headphones)
    }

    @Test("the chosen device's id counts only when it is alive and listed")
    func chosenDeviceNeedsLifeAndAnOutput() {
        #expect(OutputDevicePolicy.chosenDevice(Self.headphones, alive: true, listed: true) == Self.headphones)
        #expect(OutputDevicePolicy.chosenDevice(Self.headphones, alive: true, listed: false) == 0)
        #expect(OutputDevicePolicy.chosenDevice(Self.headphones, alive: false, listed: true) == 0)
        #expect(OutputDevicePolicy.chosenDevice(0, alive: false, listed: false) == 0)
    }

    @Test("a refused pick takes back only itself: the rule's move and the switch made meanwhile stay")
    func failedPickTakesBackOnlyItself() {
        var selection = OutputDeviceSelection()
        selection.choose(Self.headphones, uid: Self.headphonesUID)
        let before = selection
        // Refused, nothing in between: as if it never happened.
        let refused = selection.choose(Self.speakers, uid: Self.speakersUID)
        selection.undo(refused)
        #expect(selection == before)
        // Refused while the output rule moved the app (a loss on configChangeQueue): the move stays.
        let racedByRule = selection.choose(Self.speakers, uid: Self.speakersUID)
        selection.adopt(Self.other, uid: "other")
        selection.undo(racedByRule)
        #expect(selection.target == Self.other, "the rule's move survives")
        #expect(selection.chosenUID == Self.headphonesUID, "the refused pick is taken back")
        // Refused while the switch went off: it stays off.
        let racedBySwitch = selection.choose(Self.speakers, uid: Self.speakersUID)
        selection.pin(false)
        selection.undo(racedBySwitch)
        #expect(!selection.pinned, "the switch survives")
        #expect(selection.target == Self.other && selection.chosenUID == Self.headphonesUID)
    }
}
