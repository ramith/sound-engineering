// EqEngineBreakItMeasure.cpp
//
// The EQ-engine break-it MEASUREMENT harness (Sprint EQ). Not part of `make gate`: one translation
// unit assembled like Tests/DSPKernelNullTest.cpp (TestSupport.h + the area .inc files, so every
// production test helper is reused), plus EqEngineBreakItMeasurements.inc and a main that runs the
// measurements by name.
//
// Build: research/eq-engine-break-it/build-measure.sh -O2
// Run:   research/eq-engine-break-it/measure [name …]   (no name = all; names in the .inc header)

// clang-format off
// Include order is LOAD-BEARING (as in DSPKernelNullTest.cpp): TestSupport.h first.
#include "TestSupport.h"
#include "DspBypassTests.inc"
#include "LimiterTests.inc"
#include "LoudnessTests.inc"
#include "EqTests.inc"
#include "MultichannelTests.inc"
#include "SpatialTests.inc"
#include "PureModeTests.inc"
#include "FileDecodeTests.inc"
#include "GaplessTests.inc"
#include "RoundTripTests.inc"
#include "PureGaplessTests.inc"
#include "GaplessContractTests.inc"
#include "RealizerTests.inc"
#include "IntensityTests.inc"
#include "CrossfeedTests.inc"
#include "LoudnessOracleTests.inc"
#include "LimiterTruePeakTests.inc"
#include "EqFrequencyResponseSweepTests.inc"
#include "EqDesignerTests.inc"
#include "TrackLoudnessTests.inc"
#include "SoakRtAllocTests.inc"
#include "SnapshotConcurrencyTests.inc"
#include "EqTransitionTests.inc"
#include "EqEngineTests.inc"
#include "EqEngineBreakItTests.inc"
#include "EqEngineBreakItMeasurements.inc"
// clang-format on

auto main(int argc, const char* const* argv) -> int
{
    const std::span<const char* const> args(argv, static_cast<size_t>(argc));
    std::vector<std::string_view> wanted(args.begin() + 1, args.end());
    for (const auto& [name, measure] : kBkMeasurements)
    {
        if (wanted.empty() || std::ranges::find(wanted, std::string_view(name)) != wanted.end())
        {
            logInfo(std::format("\n===== {} =====\n", name));
            measure();
            (void)std::fflush(stdout);
        }
    }
    return 0;
}
