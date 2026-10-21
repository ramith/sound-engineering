// CPUTime — what a component COSTS, measured as the CPU time this process spends on it, never the
// wall time the machine takes to schedule it. A loaded runner stretches the wall clock of every
// check; it does not stretch the CPU time of the code under test (much). Budgets that use this are
// tripwires set at least 10× above what the code measures, so only an algorithmic blow-up trips them.

import Darwin

/// CPU seconds this process (all its threads) has used so far.
func processCPUSeconds() -> Double {
    Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1_000_000_000
}

/// The CPU seconds `body` costs (sequential code only: other threads' work would be counted too).
func cpuSeconds(of body: () async throws -> Void) async rethrows -> Double {
    let start = processCPUSeconds()
    try await body()
    return processCPUSeconds() - start
}
