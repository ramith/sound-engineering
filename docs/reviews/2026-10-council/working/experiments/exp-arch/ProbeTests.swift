@testable import ArchProbeCore
import Dispatch
import Testing

@Suite struct ArchProbeTests {
    @Test func bridgeReachableFromLibrary() {
        #expect(BridgeReach.touchAll() >= 3)
    }

    @MainActor @Test func modelDrivesEngineDomain() async {
        let model = ProbeTransportModel(engine: EngineDomain(queue: DispatchSerialQueue(label: "probe.engine")))
        await model.play(3)
        await model.play(2)
        #expect(model.lastEpoch == 3)
    }
}
