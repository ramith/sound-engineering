// The device-volume loans Pure has out, kept so a crash gives them back (R1.1-A close-out break-it, H-2):
// written ahead of every change Pure makes to a device — synchronously, from the engine's device-volume
// queue — and read one by one at the next launch. Over a defaults suite of its own, emptied before each test.

import EQEditKit
import Foundation
import SettingsKit
import Testing

@Suite("PureVolumeLoanJournal — Pure's loans, kept ahead of every change", .serialized)
struct PureVolumeLoanJournalTests {
    private static let suiteName = "SettingsKitTests.PureVolumeLoanJournal"
    private static let key = "pureVolumeLoansV1"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    private static let dacA = PureVolumeLoan(deviceUID: "DAC-A", ceiling: -20, anchor: -20, lastSet: -32)
    private static let dacB = PureVolumeLoan(
        deviceUID: "DAC-B", ceiling: -10, anchor: -15, lastSet: -25, mutedByPure: true, pending: -27
    )

    @Test("a new install keeps nothing")
    func newInstall() {
        #expect(PureVolumeLoanJournal(defaults: defaults).loans().isEmpty)
    }

    @Test("what is kept is what the next launch reads — the pending level and the mute too")
    func roundTrip() {
        PureVolumeLoanJournal(defaults: defaults).keep([Self.dacA, Self.dacB])
        #expect(PureVolumeLoanJournal(defaults: defaults).loans() == [Self.dacA, Self.dacB])
        PureVolumeLoanJournal(defaults: defaults).keep([])
        #expect(defaults.object(forKey: Self.key) == nil, "nothing out: nothing kept")
    }

    /// Each kept loan is a device left turned down: one bad entry must not cost the others, and a damaged
    /// one is not kept (SET-3, SET-4). Good loans read; one of a wrong type, with a field missing, a field
    /// that is not a number, an empty device, its anchor above its ceiling, or a pending level above it, is
    /// dropped on its own.
    @Test("loans are read one by one — a bad one is dropped, the good ones kept")
    func readLeniently() {
        let good = #"{"deviceUID":"DAC-A","ceiling":-20,"anchor":-20,"lastSet":-32}"#
        let alsoGood = #"{"deviceUID":"DAC-G","ceiling":-10,"anchor":-15,"lastSet":-25,"pending":-27}"#
        let bad = [
            #"{"deviceUID":"DAC-B","ceiling":"oops","anchor":-20,"lastSet":-32}"#,
            #"{"deviceUID":"DAC-C","ceiling":-20,"lastSet":-32}"#,
            #"{"deviceUID":"DAC-D","ceiling":-20,"anchor":"NaN","lastSet":-32}"#,
            #"{"deviceUID":"DAC-E","ceiling":"+Infinity","anchor":-20,"lastSet":-32}"#,
            #"{"deviceUID":"DAC-F","ceiling":-30,"anchor":0,"lastSet":-40}"#,
            #"{"deviceUID":"DAC-H","ceiling":-30,"anchor":-30,"lastSet":-40,"pending":0}"#,
            #"{"deviceUID":"","ceiling":-20,"anchor":-20,"lastSet":-32}"#,
            #""a string""#, "7", "null",
        ]
        defaults.set(Data(("[" + ([good] + bad + [alsoGood]).joined(separator: ",") + "]").utf8), forKey: Self.key)
        #expect(PureVolumeLoanJournal(defaults: defaults).loans().map(\.deviceUID) == ["DAC-A", "DAC-G"])
    }

    @Test("a kept value of another type reads as nothing kept", arguments: [0, 1, 2])
    func wrongType(which: Int) {
        let values: [Any] = ["garbage", 42, ["deviceUID": "DAC-A"]]
        defaults.set(values[which], forKey: Self.key)
        #expect(PureVolumeLoanJournal(defaults: defaults).loans().isEmpty)
    }

    /// The engine writes from its device-volume queue while the app reads at launch; any thread may write.
    @Test("kept from many threads at once: every read is one whole value that was written")
    func concurrentKeeps() {
        let journal = PureVolumeLoanJournal(defaults: defaults)
        let written = (0 ..< 64).map { index in
            [PureVolumeLoan(deviceUID: "DAC-\(index)", ceiling: -20, anchor: -20, lastSet: Float(-21 - index % 40))]
        }
        DispatchQueue.concurrentPerform(iterations: written.count) { index in
            journal.keep(written[index])
            _ = journal.loans()
        }
        #expect(written.contains(PureVolumeLoanJournal(defaults: defaults).loans()))
    }
}
