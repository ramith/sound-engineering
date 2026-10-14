// DEV-1 (R1.1-A): the device the user chose outlives the session. The app keeps it with the listener's
// settings and hands it back at launch (`OutputDeviceSelection.restoreChoice`, `.choiceRestored`); the
// rule then treats it exactly as a choice made in this session. The device the app launches on is still
// not a choice.

import OutputDeviceKit
import Testing

@Suite("Output device — the choice across a relaunch")
struct OutputDeviceRelaunchTests {
    private static let headphones: UInt32 = 41
    private static let speakers: UInt32 = 42
    private static let headphonesUID = "AA-BB-CC-DD-EE-FF:output"
    private static let speakersUID = "BuiltInSpeakerDevice"

    /// Speakers and headphones connected, macOS sending sound to the headphones.
    private static func bothConnected() -> OutputWorld {
        OutputWorld(devices: [headphones: headphonesUID, speakers: speakersUID], systemDefault: headphones)
    }

    @Test("speakers picked with the headphones connected, then a relaunch: the app is on the speakers again")
    func chosenDeviceComesBack() {
        var world = Self.bothConnected()
        world.start()
        world.pick(Self.speakers)
        world.systemDefault = Self.headphones // something else moved macOS back to the headphones
        let restored = world.relaunch()
        #expect(world.chosenUID == Self.speakersUID, "the choice is the user's, as left")
        #expect(restored.adoptTarget == Self.speakers, "the app's device is the chosen one at launch")
        #expect(!restored.reassertTarget, "idle: the system default is left alone")
        #expect(world.systemDefault == Self.headphones)
        #expect(world.playEnhanced().reassertTarget, "Play puts the chosen device back as the default")
        #expect(world.soundsOn == Self.speakers)
    }

    @Test("Pure plays on the chosen device after a relaunch (it plays on the app's device directly)")
    func pureOnChosenDevice() {
        var world = Self.bothConnected()
        world.start()
        world.pick(Self.speakers)
        world.systemDefault = Self.headphones
        world.relaunch()
        world.playPure()
        #expect(world.soundsOn == Self.speakers)
    }

    @Test("the chosen device away at launch: the app follows the default, and returns to it when it connects")
    func chosenDeviceAwayAtLaunch() {
        var world = Self.bothConnected()
        world.start()
        world.pick(Self.headphones)
        world.disconnect(Self.headphones, defaultMovesTo: Self.speakers)
        world.settle()
        #expect(world.relaunch().description == "nothing")
        #expect(world.selection.target == Self.speakers)
        world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: false)
        #expect(world.settle()[0].adoptTarget == Self.headphones, "back to the chosen headphones")
    }

    @Test("nothing chosen before the quit: the device the app launches on is still not a choice")
    func launchDeviceIsStillNotAChoice() {
        var world = Self.bothConnected()
        world.start()
        #expect(world.relaunch().description == "nothing")
        #expect(world.chosenUID.isEmpty)
        world.connect(Self.headphones, uid: Self.headphonesUID, takesDefault: true)
        world.systemDefault = Self.speakers
        #expect(world.settle().contains { $0.adoptTarget == Self.speakers }, "pinned with nothing chosen follows")
    }

    @Test("\"Keep playback on this device\" off: a kept choice doesn't hold the app — it follows the default")
    func switchOffFollows() {
        var world = Self.bothConnected()
        world.start()
        world.pick(Self.speakers)
        world.systemDefault = Self.headphones
        let restored = world.relaunch(pinned: false)
        #expect(restored.description == "nothing", "it launched on the default, which it follows")
        #expect(world.selection.target == Self.headphones)
    }
}
