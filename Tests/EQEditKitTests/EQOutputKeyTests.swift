// OUTKEY — the output identity the EQ keys per-output memory by (DEV-UID; review F4/F5). The
// identity-change hook (`AudioViewModel.onOutputIdentityChanged`) fires exactly when
// `isOutputChange` says so: on a new UID, never on a re-read of the same output.

import EQEditKit
import Foundation
import Testing

@Suite("EQOutputKey — output identity")
struct EQOutputKeyTests {
    private let airPods = EQOutputKey(uid: "A4-C3-F0-11-22-33:output", modelUID: "AirPods Pro,2", name: "AirPods Pro")
    private let speakers = EQOutputKey(uid: "BuiltInSpeakerDevice", modelUID: nil, name: "MacBook Pro Speakers")

    @Test("OUTKEY-01: moving to another UID is an output change")
    func newUIDChanges() {
        #expect(EQOutputKey.isOutputChange(from: speakers, to: airPods))
        #expect(EQOutputKey.isOutputChange(from: airPods, to: speakers))
    }

    @Test("OUTKEY-02: an output appearing (launch) or going away is an output change")
    func appearAndDisappear() {
        #expect(EQOutputKey.isOutputChange(from: nil, to: speakers))
        #expect(EQOutputKey.isOutputChange(from: speakers, to: nil))
        #expect(!EQOutputKey.isOutputChange(from: nil, to: nil))
    }

    @Test("OUTKEY-03: a re-read of the same output never is — same UID, other name or model UID")
    func sameUIDNeverChanges() {
        // A rate or buffer change re-reads the device: the key is identical.
        #expect(!EQOutputKey.isOutputChange(from: airPods, to: airPods))
        // A rename, or a model UID read differently, keeps the UID — the same output.
        let renamed = EQOutputKey(uid: airPods.uid, modelUID: nil, name: "Ramith's AirPods")
        #expect(!EQOutputKey.isOutputChange(from: airPods, to: renamed))
    }

    @Test("OUTKEY-04: two units of one model share a model UID but are different outputs")
    func sameModelOtherUnit() {
        let secondPair = EQOutputKey(uid: "B8-00-00-44-55-66:output", modelUID: airPods.modelUID, name: "AirPods Pro")
        #expect(EQOutputKey.isOutputChange(from: airPods, to: secondPair))
    }

    @Test("OUTKEY-05: a key encodes and decodes back equal (a missing model UID included)")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode([airPods, speakers])
        #expect(try JSONDecoder().decode([EQOutputKey].self, from: data) == [airPods, speakers])
    }
}
