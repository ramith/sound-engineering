// EqTests.inc
//
// EQ audibility tests (Sprint 5 — Milestone 2).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests: EQ_FrequencyResponseAccuracy, EQ_CoefficientSwapNoClick.
// Helpers (goertzelPower, kEqBands, sliceRms, runEqSine, eqSwapRunBlocks,
//          eqSwapNoClickBody) live in TestSupport.h (shared with MultichannelTests.inc).

// ---------------------------------------------------------------------------
// EQ audibility tests (Sprint 5 — Milestone 2): the EQ is now in the live graph
// and driven by computeBiquadCascade -> publishTargetState. These validate that a
// band boost actually changes the signal by the right amount (FR accuracy) and
// that a large coefficient change does not produce an audible boundary click
// (the zipper measurement that the audio-dsp review flagged as make-or-break).
// ---------------------------------------------------------------------------

static auto testEQFrequencyResponseAccuracy() -> void
{
    static const char* const kName = "EQ_FrequencyResponseAccuracy";
    constexpr uint32_t kFrames = TestConstants::kTotalFrames1s;

    std::array<float, kEqBands> flat{};
    std::array<float, kEqBands> boosted{};
    boosted[kBand1kHzIndex] = kEqBoostDb;

    const std::vector<float> flatOut = runEqSine(flat, kFrames);
    const std::vector<float> boostOut = runEqSine(boosted, kFrames);

    // Measure over the settled second half (IIR settles in ms; this is a safe margin).
    const size_t halfFrame = kFrames / 2U;
    const double flatRms = sliceRms(flatOut, halfFrame, kFrames);
    const double boostRms = sliceRms(boostOut, halfFrame, kFrames);

    if (flatRms <= 0.0)
    {
        logFail(kName, "flat-EQ output was silent");
        return;
    }
    const double measuredDb = 20.0 * std::log10(boostRms / flatRms);
    if (std::abs(measuredDb - kEqBoostDb) > kEqFrToleranceDb)
    {
        std::ostringstream oss;
        oss << "measured " << measuredDb << " dB at 1 kHz, expected " << kEqBoostDb << " ± "
            << kEqFrToleranceDb;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

static auto testEQCoefficientSwapNoClick() -> void
{
    static const char* const kName = "EQ_CoefficientSwapNoClick";
    const std::string err = eqSwapNoClickBody(2U, kName);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}
