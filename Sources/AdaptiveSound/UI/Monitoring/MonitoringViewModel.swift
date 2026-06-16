import Foundation

// MARK: - Monitoring View Model

/// Owns the per-channel before/after band arrays for the Monitoring tab.
///
/// Polling lifecycle is controlled by the tab's visibility: call `startPolling()`
/// when the Monitoring tab becomes visible and `stopPolling()` when it leaves, so
/// that FFT reads only occur while the data is actually being displayed.
///
/// Concurrency: all mutations happen on the MainActor — the arrays are read-only
/// from SwiftUI body closures, which also run on the main thread.
@MainActor
@Observable
final class MonitoringViewModel {
    // MARK: Published State

    /// Number of channels reported by the engine (0 until the engine is ready).
    private(set) var channelCount: Int = 0

    /// Per-channel BEFORE bands: `beforeBands[ch]` has `SpectrumConstants.bandCount` floats.
    private(set) var beforeBands: [[Float]] = []

    /// Per-channel AFTER bands: `afterBands[ch]` has `SpectrumConstants.bandCount` floats.
    private(set) var afterBands: [[Float]] = []

    // MARK: Private State

    private var pollingTask: Task<Void, Never>?

    /// Scratch buffers – one per channel; resized when `channelCount` changes.
    private var beforeScratch: [[Float]] = []
    private var afterScratch: [[Float]] = []

    // MARK: Dependencies

    private let engine: any AudioPlaybackEngine

    // MARK: Init

    init(engine: any AudioPlaybackEngine) {
        self.engine = engine
    }

    // MARK: Polling Lifecycle

    /// Begin polling the engine at ~20 Hz. Safe to call multiple times.
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(50)) // ~20 Hz
            }
        }
    }

    /// Stop polling. Idempotent.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: Private

    /// Called at ~20 Hz. Reads the latest bands from the engine's lock-free double buffers.
    private func tick() {
        let count = engine.monitorChannelCount
        if count != channelCount {
            channelCount = count
            resizeScratch(to: count)
        }

        guard count > 0 else { return }

        var didChange = false
        for channelIndex in 0 ..< count {
            let gotBefore = engine.readMonitorBands(.before, channel: channelIndex, into: &beforeScratch[channelIndex])
            let gotAfter = engine.readMonitorBands(.after, channel: channelIndex, into: &afterScratch[channelIndex])
            didChange = didChange || gotBefore || gotAfter
        }

        if didChange {
            // Copy scratch buffers into the published arrays in one assignment so
            // SwiftUI sees a single change notification per tick.
            beforeBands = beforeScratch
            afterBands = afterScratch
        }
    }

    private func resizeScratch(to count: Int) {
        let emptyBand = [Float](repeating: 0, count: SpectrumConstants.bandCount)
        beforeScratch = (0 ..< count).map { _ in emptyBand }
        afterScratch = (0 ..< count).map { _ in emptyBand }
        beforeBands = beforeScratch
        afterBands = afterScratch
    }
}
