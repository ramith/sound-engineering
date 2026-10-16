import AudioDSP
import AudioToolbox
import AVFoundation
import Testing

// MARK: - An in-process AU with nothing upstream says so (council C-87)

//
// Both of the app's in-process v3 effect AUs pull their input through the pull block the host hands
// their render block. With nothing connected upstream, that block is nil: there is nothing to render,
// and the AU must answer kAudioUnitErr_NoConnection — not call through the nil block. The two AUs'
// copies of the AU scaffolding had diverged: the spatial renderer guarded it, the effects AU called
// it (a latent crash). Each AU is made, allocated and rendered the way a host does it, through its
// own render block — no engine, no device, nothing heard.

@Suite("An in-process AU with nothing upstream says so (council C-87)")
struct InProcessAUNoUpstreamTests {
    /// One of the app's two in-process effect AUs.
    enum Unit: String, CaseIterable, CustomTestStringConvertible {
        case effects
        case spatial

        var testDescription: String {
            rawValue
        }

        /// The AU's component description, registered first (once per process), as the engine does.
        var componentDescription: AudioComponentDescription {
            switch self {
            case .effects:
                registerAdaptiveAudioUnitSubclass()
                return adaptiveAudioUnitComponentDescription()
            case .spatial:
                registerSpatialRendererAUSubclass()
                return spatialRendererComponentDescription()
            }
        }
    }

    @Test("a render with no upstream answers kAudioUnitErr_NoConnection", arguments: Unit.allCases)
    func noUpstreamAnswersNoConnection(_ unit: Unit) throws {
        let audioUnit = try AUAudioUnit(componentDescription: unit.componentDescription)
        try audioUnit.allocateRenderResources()
        defer { audioUnit.deallocateRenderResources() }
        let frames = audioUnit.maximumFramesToRender
        let output = try #require(AVAudioPCMBuffer(pcmFormat: audioUnit.outputBusses[0].format,
                                                   frameCapacity: frames))
        output.frameLength = frames
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()

        let status = audioUnit.internalRenderBlock(&flags, &timestamp, frames, 0, output.mutableAudioBufferList,
                                                   nil, nil)

        #expect(status == kAudioUnitErr_NoConnection)
    }
}
