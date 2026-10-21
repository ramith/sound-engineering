import Foundation

// MARK: - The transport tick's clock source (test seam)

/// A repeating tick the view model has scheduled and can stop. The product's is a `Timer` on the main
/// run loop (`RunLoopTicker`); a test hands the view model one it fires by hand, so a tick happens when
/// the test says and never because a run loop got round to it.
@MainActor
protocol TransportTicker: AnyObject {
    /// No tick fires from here on.
    func stop()
}

/// Schedules `tick` to run on the main actor every `interval` seconds, until the ticker it returns stops.
typealias TransportTickerMaker = @MainActor (_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void)
    -> any TransportTicker

/// The product's ticker: a repeating `Timer` on `RunLoop.main`, in common modes so the tick fires during
/// tracking (a slider drag, a scroll) too.
@MainActor
final class RunLoopTicker: TransportTicker {
    let timer: Timer

    init(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
        timer = Timer(timeInterval: interval, repeats: true) { _ in
            // Scheduled on RunLoop.main (below), so this always fires on the main thread:
            // assumeIsolated proves it to the compiler with no per-tick Task allocation.
            MainActor.assumeIsolated {
                tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer.invalidate()
    }

    /// The product's `TransportTickerMaker`.
    static let make: TransportTickerMaker = { interval, tick in
        RunLoopTicker(interval: interval, tick: tick)
    }
}
