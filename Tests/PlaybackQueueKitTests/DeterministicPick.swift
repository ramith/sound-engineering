// MARK: - The shuffle stand-in the Kit's suites share

/// A deterministic shuffle picker: a linear walk that avoids `current`, so an exact-value case is
/// reproducible while the rule under test is the shipped one. The app injects
/// `QueueAdvance.uniformRandomExcluding`; the shuffle cases assert the property both satisfy ("≠ current,
/// in range").
let deterministicPick: @Sendable (Int, Int) -> Int = { current, count in (current + 1) % count }
