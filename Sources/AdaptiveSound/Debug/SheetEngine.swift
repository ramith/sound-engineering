#if DEBUG
    import Foundation

    // MARK: - Picture-sheet audio engine

    /// The renderer's `AudioPlaybackEngine`: hardware-free. Every lifecycle, transport and device verb
    /// is a no-op answering "nothing is running", so a render never builds an `AVAudioEngine`, opens a
    /// HAL session or enumerates CoreAudio devices. Its one job is serving the fixture's per-channel
    /// before/after spectra, which the Monitoring tab polls straight from the engine
    /// (`MonitoringViewModel`) rather than through the audio view model.
    final class SheetEngine: AudioPlaybackEngine {
        private let before: [[Float]]
        private let after: [[Float]]

        /// One band array per channel for each tap, `SpectrumConstants.bandCount` values in 0...1.
        init(before: [[Float]], after: [[Float]]) {
            self.before = before
            self.after = after
        }

        func initialize() async throws -> Bool {
            false
        }

        func shutdown() async throws {}

        func startAudio(fileURL _: URL?, pureMode _: Bool) async throws {}

        func stopAudio() async throws {}

        func seek(to _: Double) async {}

        func currentPlaybackPosition() -> Double? {
            nil
        }

        func currentSignalPath() -> SignalPathInfo {
            SignalPathInfo()
        }

        func currentLoudness() -> LoudnessSnapshot {
            .unmeasured
        }

        func setParameter(_: UInt32, value _: Float) async throws {}

        func publishEQGains(_: [Float]) {}

        func enumerateOutputDevices() async throws -> [AudioDeviceModel] {
            []
        }

        func selectDevice(_: UInt32) async throws -> Bool {
            false
        }

        /// Fixture devices never change, so there is never anything to call back.
        var onOutputDevicesChanged: (@MainActor () -> Void)? {
            get { nil }
            set { _ = newValue }
        }

        @discardableResult
        func readSpectrumBands(into _: inout [Float]) -> Bool {
            false
        }

        var monitorChannelCount: Int {
            before.count
        }

        @discardableResult
        func readMonitorBands(_ tap: MonitorTap, channel: Int, into out: inout [Float]) -> Bool {
            let bands = tap == .before ? before : after
            guard bands.indices.contains(channel) else { return false }
            out = bands[channel]
            return true
        }
    }
#endif
