// SESSION — the EQ's decisions, gated (review fix round): what an output switch sends and toasts (E2),
// that a discrete edit ends a drag, that Compare lets go on any change to what plays (and only then),
// that Esc during a drag puts back the curve AND the Bring back offer, that a drag whose end never came
// is ended by the next, and what each verb asks to send, write and log.

@testable import EQEditKit
import Testing

@Suite("EQSession — the decisions the view model carries out")
struct EQSessionTests {
    private static let speakers = EQOutputKey(uid: "BuiltInSpeakerDevice", modelUID: nil, name: "Speakers")
    private static let pods = EQOutputKey(uid: "A4-C3:output", modelUID: "AirPods Pro,2", name: "AirPods Pro")
    private static let dac = EQOutputKey(uid: "USB:Modi:1", modelUID: nil, name: "Modi+")

    /// Speakers and the DAC unpinned on Warm; the AirPods pinned to Vocal.
    private static func world() -> EQSession {
        var store = EQStore(shared: EQState(preset: .builtIn(.warm), curve: nil))
        store.pin(pods)
        store[slot: pods.uid] = EQState(preset: .builtIn(.vocal), curve: nil)
        return EQSession(store: store, myPresets: [:])
    }

    // MARK: The output switch (Edge 5; break-it E2)

    @Test("SESSION-01: the launch's first output sends what it plays but never toasts")
    func launchNeverToasts() {
        var session = Self.world()
        let first = session.outputDidChange(to: Self.pods)
        #expect(first.effects.contains(.send) && first.toast == nil)
        #expect(session.current.preset == .builtIn(.vocal))
    }

    @Test("SESSION-02: a switch to an output that plays otherwise toasts; one that plays the same doesn't")
    func switchToasts() {
        var session = Self.world()
        _ = session.outputDidChange(to: Self.speakers)
        let toPods = session.outputDidChange(to: Self.pods)
        #expect(toPods.effects.contains(.send) && toPods.toast == "AirPods Pro · Vocal")
        _ = session.outputDidChange(to: Self.speakers)
        let toDac = session.outputDidChange(to: Self.dac) // shared → shared: nothing changes
        #expect(!toDac.effects.contains(.send) && toDac.toast == nil)
    }

    @Test("SESSION-03: after a gap with no output, the next output toasts when it plays otherwise (E2)")
    func gapStillToasts() {
        // Pinned AirPods, then every output gone, then the speakers (shared): the slot current during
        // the gap is shared, but what was HEARD last was the AirPods' Vocal.
        var session = Self.world()
        _ = session.outputDidChange(to: Self.pods)
        let gone = session.outputDidChange(to: nil)
        #expect(gone.effects.contains(.send) && gone.toast == nil, "no output: sent, never toasted")
        let back = session.outputDidChange(to: Self.speakers)
        #expect(back.toast == "Speakers · Warm", "Warm differs from the Vocal last heard")
        #expect(!back.effects.contains(.send), "the current slot didn't change across the gap")
        // Speakers, a gap, the speakers again: the same sound as last heard — no toast.
        _ = session.outputDidChange(to: nil)
        #expect(session.outputDidChange(to: Self.speakers).toast == nil)
    }

    @Test("SESSION-04: the rule itself — send on a slot change, toast on arriving at a different sound")
    func outputSwitchRule() {
        let warm = EQState(preset: .builtIn(.warm), curve: nil)
        let vocal = EQState(preset: .builtIn(.vocal), curve: nil)
        let rule = EQOutputSwitch(before: warm, now: warm, lastHeard: vocal, arrives: true)
        #expect(!rule.sends && rule.toasts)
        #expect(!EQOutputSwitch(before: warm, now: vocal, lastHeard: nil, arrives: true).toasts, "launch")
        #expect(!EQOutputSwitch(before: warm, now: vocal, lastHeard: warm, arrives: false).toasts, "no output")
        #expect(EQOutputSwitch(before: warm, now: vocal, lastHeard: warm, arrives: false).sends)
    }

    @Test("SESSION-05: an output switch lets a held Compare go and drops edits set aside")
    func switchReleasesCompare() {
        var session = Self.world()
        _ = session.outputDidChange(to: Self.speakers)
        _ = session.beginCompare(when: .playing)
        _ = session.choose(.builtIn(.flat)) // releases Compare (an edit) — hold it again
        _ = session.beginCompare(when: .playing)
        #expect(session.isComparing)
        _ = session.outputDidChange(to: Self.pods)
        #expect(!session.isComparing && session.bringBack == nil)
    }

    // MARK: Drags

    @Test("SESSION-06: a discrete edit ends a drag first — kept and written — and the rest of the drag is ignored")
    func discreteEditEndsTheDrag() {
        var session = Self.world()
        _ = session.outputDidChange(to: Self.speakers)
        _ = session.beginStroke()
        _ = session.updateStroke(band: 20, db: 6)
        let step = session.nudge(band: 3, by: 0.5)
        #expect(step.effects.contains(.saveSlots))
        #expect(!session.isStroking)
        #expect(abs(session.points[20] - 6) < 1e-5, "the drag's sample is kept")
        let late = session.updateStroke(band: 20, db: -6)
        #expect(late.isNone && abs(session.points[20] - 6) < 1e-5, "the rest of the drag is ignored")
    }

    @Test("SESSION-07: Esc during a drag puts back the curve AND the Bring back offer it cleared")
    func escRestoresTheOffer() {
        var session = Self.world()
        _ = session.outputDidChange(to: Self.speakers)
        _ = session.nudge(band: 10, by: 3) // edited Warm
        _ = session.choose(.builtIn(.clarity)) // sets the edits aside
        let offer = session.bringBack
        #expect(offer != nil)
        let before = session.current
        _ = session.beginStroke()
        _ = session.updateStroke(band: 15, db: 9)
        #expect(session.bringBack == nil, "a drag is an edit: the offer goes")
        let cancelled = session.cancelStroke()
        #expect(!cancelled.isNone && cancelled.effects.contains(.send))
        #expect(session.current == before && session.bringBack == offer)
        #expect(session.cancelStroke().isNone, "no stroke: Esc is the caller's")
    }

    @Test("SESSION-08: a drag whose end never came is ended by the next mouse-down, kept")
    func staleStrokeEnds() {
        var session = Self.world()
        _ = session.outputDidChange(to: Self.speakers)
        _ = session.beginStroke()
        _ = session.updateStroke(tone: .presence, to: 4)
        let next = session.beginStroke() // the slider's cancelled drag sent no end
        #expect(next.effects.contains(.saveSlots), "the first drag is written")
        #expect(session.tone(of: .presence) == 4)
        _ = session.cancelStroke()
        #expect(session.tone(of: .presence) == 4, "Esc on the second drag doesn't undo the first")
    }

    @Test("SESSION-09: a drag across an output change that keeps its slot draws on; one that changes it ends")
    func dragStaysWithItsSlot() {
        var session = Self.world()
        _ = session.outputDidChange(to: Self.speakers)
        _ = session.beginStroke()
        _ = session.outputDidChange(to: Self.dac) // shared → shared
        #expect(session.isStroking)
        _ = session.outputDidChange(to: Self.pods) // shared → the AirPods' pin
        #expect(!session.isStroking)
    }

    // MARK: Compare

    @Test("SESSION-10: Compare holds only while the EQ plays, lets go on any change to what plays, never on a pin")
    func compareRelease() {
        var session = Self.world()
        _ = session.outputDidChange(to: Self.speakers)
        #expect(session.beginCompare(when: .off).isNone && !session.isComparing)
        #expect(session.beginCompare(when: .playing).effects.contains(.send))
        #expect(!session.plays, "held: the engine plays without the EQ")
        _ = session.togglePin() // keeps the sound
        #expect(session.isComparing)
        _ = session.setTone(.air, to: 2) // an edit
        #expect(!session.isComparing && session.plays)
        _ = session.beginCompare(when: .playing)
        _ = session.setOn(false)
        #expect(!session.isComparing)
        #expect(session.endCompare().isNone, "a second release does nothing")
    }

    // MARK: What a verb asks

    @Test("SESSION-11: each verb asks for exactly its writes — a preset choice, Save, a pin, a refused name")
    func verbEffects() {
        var session = Self.world()
        _ = session.outputDidChange(to: Self.speakers)
        let chosen = session.choose(.builtIn(.vocal))
        #expect(chosen.effects == [.send, .saveSlots] && chosen.log == ["EQ preset → 'Vocal'"])
        _ = session.nudge(band: 12, by: 2)
        let saved = session.save(session.saveSource(), as: "Mine")
        #expect(saved.effects == [.send, .saveSlots, .saveMyPresets])
        #expect(session.current.preset == .mine("Mine") && session.bringBack == nil)
        #expect(session.save(session.saveSource(), as: "warm").isNone, "a refused name saves nothing")
        let pinned = session.togglePin()
        #expect(pinned.effects == [.send, .saveSlots] && session.outputPin == .pinned(Self.speakers))
        #expect(session.setOn(true).isNone, "already on")
        #expect(session.choose(.mine("Gone")).isNone)
    }
}
