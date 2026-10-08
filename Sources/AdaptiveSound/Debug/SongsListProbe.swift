#if DEBUG
    import SwiftUI

    // MARK: - Songs list probe (S10.8 E1 — the End-key hang)

    /// The Songs list's debug-only performance hook, for `SongsPerfRun` alone (`nil` in the app, so
    /// the list's two counters cost one nil check). The list registers how to press a navigation
    /// key in it, and counts its own passes and the rows it builds — so the run can tell a move that
    /// settles at once from one that rebuilds thousands of rows, or the list over and over.
    @MainActor
    final class SongsListProbe {
        /// Presses a navigation key (↑ ↓ Home End Page Up / Down) the way the list's `onKeyPress`
        /// does, without ⇧, and returns the cursor's row number after it. Registered by the list when
        /// it appears.
        var press: ((KeyEquivalent) -> Int?)?
        /// Passes of the list's content (its body's geometry closure) since `reset()`.
        private(set) var listPasses = 0
        /// Row views built since `reset()`, and their distinct row numbers.
        private(set) var rowBuilds = 0
        private(set) var builtRows: Set<Int> = []

        /// The built rows as runs — "1…14, 9987…10000".
        var builtRowRuns: String {
            var runs: [ClosedRange<Int>] = []
            for row in builtRows.sorted() {
                if let last = runs.last, last.upperBound + 1 == row {
                    runs[runs.count - 1] = last.lowerBound ... row
                } else {
                    runs.append(row ... row)
                }
            }
            return runs.map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)…\($0.upperBound)" }
                .joined(separator: ", ")
        }

        func countListPass() {
            listPasses += 1
        }

        func countRowBuild(number: Int) {
            rowBuilds += 1
            builtRows.insert(number)
        }

        func reset() {
            listPasses = 0
            rowBuilds = 0
            builtRows = []
        }
    }
#endif
