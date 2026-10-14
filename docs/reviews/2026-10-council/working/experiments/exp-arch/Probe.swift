// Architecture-review probe (council, not product code): can a LIBRARY target reach the whole
// C bridge through `import AudioDSP` (the module map), with no -import-objc-header flag, and host
// both a @MainActor @Observable model and an engine-domain actor on a DispatchSerialQueue?
import AudioDSP
import Dispatch
import Observation

/// One symbol from each sub-header DeviceBridge.h re-exports.
public enum BridgeReach {
    public static func touchAll() -> Int {
        var reached = 0
        if let meter = loudnessMeterCreate(48000) { loudnessMeterDestroy(meter); reached += 1 } // DeviceBridge.h
        if let pure = pureModeEngineCreate() { pureModeEngineDestroy(pure); reached += 1 }      // PureModeBridge.h
        let desc = adaptiveAudioUnitComponentDescription()                                       // AudioUnitRegistrationBridge.h
        if desc.componentType != 0 { reached += 1 }
        if let designer = asEqDesignerCreate() { asEqDesignerDestroy(designer); reached += 1 }   // EQDesignBridge.h
        _ = eqDesignSampleRate(nil) // NULL-safe accessor, AudioUnitRegistrationBridge.h
        return reached
    }
}

/// The engine control domain: an actor whose executor IS the serial queue.
public actor EngineDomain {
    public let queue: DispatchSerialQueue
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private(set) var epoch: UInt64 = 0
    public init(queue: DispatchSerialQueue) { self.queue = queue }
    public func begin(_ requested: UInt64) -> UInt64 { epoch = max(epoch, requested); return epoch }
}

/// A view-model-shaped type in the library.
@MainActor @Observable
public final class ProbeTransportModel {
    public private(set) var lastEpoch: UInt64 = 0
    let engine: EngineDomain
    public init(engine: EngineDomain) { self.engine = engine }
    public func play(_ n: UInt64) async { lastEpoch = await engine.begin(n) }
}
