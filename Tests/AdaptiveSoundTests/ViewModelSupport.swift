@testable import AdaptiveSound
import Foundation
import RigKit
import Testing

// MARK: - What every test of the real view model shares (test-rig redesign)

/// The product's `[UX]` log, kept quietly in memory while tests run: parallel tests wrote some 200,000
/// lines per CI run to stderr, which both slows them and buries the one failure line. A suite that wants
/// the tail on failure carries `.attachingLogTail` (RigKit).
enum QuietLog {
    private static let installed: Void = {
        UXLog.sink.withLock { $0 = UXLog.Sink { LogTail.shared.append($0) } }
    }()

    /// Point the product's log at `LogTail.shared`. Idempotent; call it wherever a test builds a view
    /// model or a bridge.
    static func install() {
        _ = installed
    }
}

/// A transport ticker a test fires by hand: a tick happens when the test says so, never because a run
/// loop got round to it.
@MainActor
final class ManualTicker: TransportTicker {
    private let tick: @MainActor () -> Void
    /// Whether the view model still has this ticker going.
    private(set) var isRunning = true
    /// How many ticks the test has fired.
    private(set) var fired = 0

    init(tick: @escaping @MainActor () -> Void) {
        self.tick = tick
    }

    /// One tick, as the 20 Hz timer would deliver it. A stopped ticker delivers none.
    func fire() {
        guard isRunning else { return }
        fired += 1
        tick()
    }

    func stop() {
        isRunning = false
    }
}

/// The tickers a view model asked for, so the test can fire the current one.
@MainActor
final class TickerBench {
    /// Every ticker made, oldest first.
    private(set) var tickers: [ManualTicker] = []

    /// The ticker the view model has going now, if any.
    var current: ManualTicker? {
        tickers.last(where: \.isRunning)
    }

    /// The `makeTicker` to give the view model.
    var maker: TransportTickerMaker {
        { [self] _, tick in
            let ticker = ManualTicker(tick: tick)
            tickers.append(ticker)
            return ticker
        }
    }
}

extension AudioViewModel {
    /// Wait until everything this view model set going has finished: the tasks it spawned (a start, a device
    /// read), and the settings' write at the end of the turn. Replaces "50 yields and hope".
    func settled() async throws {
        try await until("the view model's tasks and the settings' write to finish") {
            work.isIdle && settingsStore.pendingWrite == nil
        }
    }
}
