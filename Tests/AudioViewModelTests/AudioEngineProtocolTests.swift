import Testing

// NOTE: AudioViewModel and AudioPlaybackEngine live in the `AdaptiveSound` executable
// target. SPM does not allow @testable import of executable targets.  These tests
// verify the *protocol contract* by driving MockAudioEngine directly.  When
// AudioViewModel is extracted into a library target (Phase 1.5), replace this
// mirror approach with @testable import AdaptiveSoundCore.

// MARK: - Test helpers

private func makeBuiltin(id: UInt32 = 1, name: String = "Built-in Output") -> AudioDeviceModelMirror {
    AudioDeviceModelMirror(id: id, name: name, sampleRate: 48000, bufferFrameSize: 512, type: .builtin)
}

private func makeWireless(id: UInt32 = 2, name: String = "AirPods Pro") -> AudioDeviceModelMirror {
    AudioDeviceModelMirror(id: id, name: name, sampleRate: 24000, bufferFrameSize: 256, type: .wireless)
}

// MARK: - MockAudioEngine unit tests

@Suite("MockAudioEngine — AudioPlaybackEngine protocol contract")
struct AudioEngineProtocolTests {
    // MARK: initialize()

    @Test("initialize() returns true on success")
    func initializeSuccess() async throws {
        let mock = MockAudioEngine()
        let result = try await mock.initialize()
        #expect(result == true)
        #expect(mock.initializeCallCount == 1)
    }

    @Test("initialize() can be configured to return false")
    func initializeFailure() async throws {
        let mock = MockAudioEngine()
        mock.initializeResult = false
        let result = try await mock.initialize()
        #expect(result == false)
    }

    @Test("initialize() propagates a configured error")
    func initializeError() async {
        struct EngineError: Error {}
        let mock = MockAudioEngine()
        mock.initializeError = EngineError()
        await #expect(throws: EngineError.self) {
            _ = try await mock.initialize()
        }
    }

    // MARK: enumerateOutputDevices()

    @Test("enumerateOutputDevices() returns configured device list")
    func enumerateDevicesReturnsConfiguredList() async throws {
        let mock = MockAudioEngine()
        mock.enumerateResult = [makeBuiltin(), makeWireless()]

        let devices = try await mock.enumerateOutputDevices()

        #expect(devices.count == 2)
        #expect(devices[0].id == 1)
        #expect(devices[0].name == "Built-in Output")
        #expect(devices[0].sampleRate == 48000)
        #expect(devices[0].type == .builtin)
        #expect(devices[1].id == 2)
        #expect(devices[1].type == .wireless)
    }

    @Test("enumerateOutputDevices() increments call counter")
    func enumerateDevicesCallCounter() async throws {
        let mock = MockAudioEngine()
        _ = try await mock.enumerateOutputDevices()
        _ = try await mock.enumerateOutputDevices()
        #expect(mock.enumerateDevicesCallCount == 2)
    }

    @Test("enumerateOutputDevices() can return an empty list")
    func enumerateDevicesEmpty() async throws {
        let mock = MockAudioEngine()
        mock.enumerateResult = []
        let devices = try await mock.enumerateOutputDevices()
        #expect(devices.isEmpty)
    }

    // MARK: selectDevice()

    @Test("selectDevice() forwards the correct device ID")
    func selectDeviceForwardsID() async throws {
        let mock = MockAudioEngine()
        let success = try await mock.selectDevice(73)
        #expect(success == true)
        #expect(mock.lastSelectedDeviceID == 73)
        #expect(mock.selectDeviceCallCount == 1)
    }

    @Test("selectDevice() can be configured to return false")
    func selectDeviceFailure() async throws {
        let mock = MockAudioEngine()
        mock.selectDeviceResult = false
        let success = try await mock.selectDevice(99)
        #expect(success == false)
    }

    // MARK: startAudio / stopAudio

    @Test("startAudio(fileURL:) records the URL")
    func startAudioRecordsURL() async throws {
        let mock = MockAudioEngine()
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        try await mock.startAudio(fileURL: url)
        #expect(mock.lastStartedURL == url)
        #expect(mock.startAudioCallCount == 1)
    }

    @Test("startAudio(fileURL: nil) does not crash")
    func startAudioNilURL() async throws {
        let mock = MockAudioEngine()
        try await mock.startAudio(fileURL: nil)
        #expect(mock.startAudioCallCount == 1)
        #expect(mock.lastStartedURL == nil)
    }

    @Test("stopAudio() increments call counter")
    func stopAudioCallCounter() async throws {
        let mock = MockAudioEngine()
        try await mock.stopAudio()
        try await mock.stopAudio()
        #expect(mock.stopAudioCallCount == 2)
    }

    // MARK: setParameter()

    @Test("setParameter() captures ID and value")
    func setParameterCapturesArgs() async throws {
        let mock = MockAudioEngine()
        try await mock.setParameter(0, value: 0.75)
        #expect(mock.lastSetParameterID == 0)
        #expect(mock.lastSetParameterValue == 0.75)
        #expect(mock.setParameterCallCount == 1)
    }

    // MARK: readSpectrumBands()

    @Test("readSpectrumBands() returns false when no data")
    func readSpectrumNullCase() {
        let mock = MockAudioEngine()
        mock.hasSpectrumData = false
        var bands = [Float](repeating: 0, count: 44)
        let result = mock.readSpectrumBands(into: &bands)
        #expect(result == false)
        #expect(mock.readSpectrumCallCount == 1)
    }

    @Test("readSpectrumBands() copies data and returns true when data is available")
    func readSpectrumWithData() {
        let mock = MockAudioEngine()
        mock.hasSpectrumData = true
        mock.spectrumData = [Float](repeating: 0.5, count: 44)
        var bands = [Float](repeating: 0, count: 44)
        let result = mock.readSpectrumBands(into: &bands)
        #expect(result == true)
        #expect(bands[0] == 0.5)
        #expect(bands[43] == 0.5)
    }

    // MARK: shutdown()

    @Test("shutdown() increments call counter")
    func shutdownCallCounter() async throws {
        let mock = MockAudioEngine()
        try await mock.shutdown()
        #expect(mock.shutdownCallCount == 1)
    }
}

// MARK: - Device model sorting simulation

//
// These tests verify the sorting logic applied in AudioEngineBridge.enumerateOutputDevices()
// without needing a live C++ call.  They document the expected ordering contract.

@Suite("AudioEngineBridge — device sort order contract")
struct DeviceSortOrderTests {
    private func sorted(_ devices: [AudioDeviceModelMirror]) -> [AudioDeviceModelMirror] {
        devices.sorted { lhs, rhs in
            let order: (AudioDeviceModelMirror.DeviceType) -> Int = { type in
                switch type {
                case .builtin: return 0
                case .wireless: return 1
                case .usb: return 2
                case .unknown: return 3
                }
            }
            let lo = order(lhs.type), ro = order(rhs.type)
            if lo != ro { return lo < ro }
            return lhs.name < rhs.name
        }
    }

    @Test("Built-in devices sort before wireless")
    func builtinBeforeWireless() {
        let devices = [makeWireless(id: 2), makeBuiltin(id: 1)]
        let result = sorted(devices)
        #expect(result[0].type == .builtin)
        #expect(result[1].type == .wireless)
    }

    @Test("Within same type, devices sort alphabetically by name")
    func alphabeticalWithinType() {
        let b1 = AudioDeviceModelMirror(id: 1, name: "Zebra Speaker", sampleRate: 48000, bufferFrameSize: 512, type: .usb)
        let b2 = AudioDeviceModelMirror(id: 2, name: "Alpha Headset", sampleRate: 48000, bufferFrameSize: 512, type: .usb)
        let result = sorted([b1, b2])
        #expect(result[0].name == "Alpha Headset")
        #expect(result[1].name == "Zebra Speaker")
    }

    @Test("Unknown type sorts last")
    func unknownTypeSortsLast() {
        let unknown = AudioDeviceModelMirror(id: 9, name: "Mystery Device", sampleRate: 44100, bufferFrameSize: 512, type: .unknown)
        let builtin = makeBuiltin()
        let result = sorted([unknown, builtin])
        #expect(result.last?.type == .unknown)
    }
}
