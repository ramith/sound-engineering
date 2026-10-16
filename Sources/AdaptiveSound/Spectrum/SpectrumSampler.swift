import DesignTokenKit
import Foundation
import SwiftUI

// MARK: - The live spectrum views' one sampler (council C-52; VM-3, VM-4)

/// What the Now Playing lens draws at one instant: the 88 bars as they move, and their peak caps.
struct SpectrumLensFrame: Equatable {
    let bars: [Float]
    let caps: [Float]
}

/// What Monitoring draws at one instant: each channel's bands before and after the DSP.
struct MonitorFrame: Equatable {
    var before: [[Float]] = []
    var after: [[Float]] = []

    var channelCount: Int {
        before.count
    }
}

/// The one reader of the analysers' frames for every live view — the Now Playing lens, the EQ's
/// silhouette, Monitoring — and the one place their motion is decided.
///
/// Live views draw on the display's clock (`LiveTimeline`), which runs only while a song plays and
/// the view is on screen, and ask this sampler what to draw at that instant. So nothing samples the
/// spectrum while paused, on another tab, or with the window closed, hidden or minimised; and the
/// 20 Hz stream never passes through Observation — this is a plain class, not `@Observable`, held
/// by `AudioViewModel` (before R1.1: a main-thread timer at 20 Hz from engine-ready to quit wrote 88
/// bars into the observable view model, and Monitoring polled on a timer of its own).
///
/// Motion, in real time (council C-51 D57):
/// - A bar eases to each new frame over `easeSeconds` (the shipped `.easeOut(duration: 0.08)`),
///   from wherever it stood; Reduce Motion — and a paused lens, which draws once — shows each frame
///   as it is.
/// - The peak caps ride the bars as drawn. `PeakHoldTracker` is fed the real time between draws
///   while a song plays: a cap holds 0.6 s, then falls 1.25 of full scale a second. (Before: each
///   new frame fed a nominal 1/20 s, but frames arrive every ~100 ms — caps held 1.2 s and fell at
///   half speed.) Paused, nothing is fed: the caps freeze, and the next feed starts afresh.
/// - On Pure the analyser has no tap: the lens shows nothing, not the last Enhanced frame.
///
/// Main thread only. Every call is idempotent for one instant, so two views drawing in one frame
/// read one frame. Monitoring's analysers run only while Monitoring shows (`showMonitoring`).
@MainActor
final class SpectrumSampler {
    /// The bars' ease toward each new frame: the shipped `.easeOut(duration: 0.08)`.
    static let easeSeconds = 0.08

    private let engine: any AudioPlaybackEngine

    /// The output analyser's latest frame (44 bands) and its 88 display bars.
    private var bands = [Float](repeating: 0, count: SpectrumConstants.bandCount)
    private var targets = [Float](repeating: 0, count: SpectrumConstants.displayBarCount)
    /// Where each bar stood when the latest frame arrived, and when it arrived.
    private var easeFrom = [Float](repeating: 0, count: SpectrumConstants.displayBarCount)
    private var easeStart = Date.distantPast
    private var peaks = PeakHoldTracker(bandCount: SpectrumConstants.displayBarCount)
    /// The caps' last feed: `nil` while paused, so the next feed starts with no elapsed time.
    private var lastFed: Date?
    private var peakFeed = [Double](repeating: 0, count: SpectrumConstants.displayBarCount)

    /// Monitoring: the latest per-channel frames, the instant they were read, and who shows them.
    private var monitor = MonitorFrame()
    private var monitorRead: Date?
    private var monitorScratch = [Float](repeating: 0, count: SpectrumConstants.bandCount)
    private var monitorViewers = 0

    #if DEBUG
        /// A still frame for the picture sheets (`SheetFixture`): drawn instead of the engine's.
        private var still: SpectrumLensFrame?
    #endif

    init(engine: any AudioPlaybackEngine) {
        self.engine = engine
    }

    // MARK: Now Playing and the EQ

    /// What the lens draws at `date`: the bars as they move, and their peak caps.
    func lens(at date: Date, isPlaying: Bool, isPure: Bool, reduceMotion: Bool) -> SpectrumLensFrame {
        #if DEBUG
            if let still {
                return still
            }
        #endif
        guard !isPure else {
            clearOutput()
            return SpectrumLensFrame(bars: targets, caps: targets)
        }
        pullOutput(at: date)
        // Paused, the lens draws once and holds: it shows the latest frame as it is, not part-way there.
        let shown = reduceMotion || !isPlaying ? targets : eased(at: date)
        if isPlaying {
            for bar in shown.indices {
                peakFeed[bar] = Double(shown[bar])
            }
            peaks.update(bars: peakFeed, elapsed: lastFed.map { date.timeIntervalSince($0) } ?? 0)
            lastFed = date
        } else {
            lastFed = nil
        }
        return SpectrumLensFrame(bars: shown, caps: peaks.caps.map(Float.init))
    }

    /// The bars as the latest frame has them, unmoved: the EQ graph's silhouette.
    func bars(at date: Date) -> [Float] {
        #if DEBUG
            if let still {
                return still.bars
            }
        #endif
        pullOutput(at: date)
        return targets
    }

    /// Take the output analyser's frame if a new one arrived: the bars ease to it from where they
    /// stand at `date`.
    private func pullOutput(at date: Date) {
        guard engine.readSpectrumBands(into: &bands) else { return }
        easeFrom = eased(at: date)
        easeStart = date
        // 44 bands → 88 bars, linear between neighbours (even bars fall on band centres).
        let lastBand = SpectrumConstants.bandCount - 1
        let lastBar = SpectrumConstants.displayBarCount - 1
        for bar in targets.indices {
            let position = Float(bar) / Float(lastBar) * Float(lastBand)
            let lower = Int(position)
            let upper = min(lower + 1, lastBand)
            let weight = position - Float(lower)
            targets[bar] = bands[lower] * (1 - weight) + bands[upper] * weight
        }
    }

    /// The bars at `date`, part-way along their ease to the latest frame.
    private func eased(at date: Date) -> [Float] {
        let progress = date.timeIntervalSince(easeStart) / Self.easeSeconds
        guard progress < 1 else { return targets }
        let curve = Float(UnitCurve.easeOut.value(at: max(0, progress)))
        return targets.indices.map { bar in easeFrom[bar] + (targets[bar] - easeFrom[bar]) * curve }
    }

    /// Nothing to show (Pure has no tap): every bar and cap at rest, once.
    private func clearOutput() {
        guard targets.contains(where: { $0 > 0 }) || peaks.caps.contains(where: { $0 > 0 }) else { return }
        targets = [Float](repeating: 0, count: SpectrumConstants.displayBarCount)
        easeFrom = targets
        peaks.reset()
        lastFed = nil
    }

    // MARK: Monitoring

    /// Each channel's before / after bands at `date` (the last frames, until new ones arrive).
    func monitorFrame(at date: Date) -> MonitorFrame {
        guard monitorRead != date else { return monitor }
        monitorRead = date
        let count = engine.monitorChannelCount
        if count != monitor.channelCount {
            let silent = [[Float]](repeating: [Float](repeating: 0, count: SpectrumConstants.bandCount), count: count)
            monitor = MonitorFrame(before: silent, after: silent)
        }
        for channel in 0 ..< count {
            if engine.readMonitorBands(.before, channel: channel, into: &monitorScratch) {
                monitor.before[channel] = monitorScratch
            }
            if engine.readMonitorBands(.after, channel: channel, into: &monitorScratch) {
                monitor.after[channel] = monitorScratch
            }
        }
        return monitor
    }

    /// Monitoring appeared (`true`) or went away (`false`). Its per-channel analysers — two per
    /// channel — run only while it shows; when it goes, its last frames go too, so it never comes
    /// back showing old ones.
    func showMonitoring(_ shown: Bool) {
        monitorViewers = max(0, monitorViewers + (shown ? 1 : -1))
        engine.setMonitorAnalysis(monitorViewers > 0)
        if monitorViewers == 0 {
            monitor = MonitorFrame()
            monitorRead = nil
        }
    }

    // MARK: Picture sheets

    #if DEBUG
        /// Draw `bars` and `caps` (88 each, 0…1), still, until the end: the picture sheets' frame.
        func showStill(bars: [Float], caps: [Float]) {
            still = SpectrumLensFrame(bars: bars, caps: caps)
        }
    #endif
}
