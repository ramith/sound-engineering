// EQDesignBridge.cpp — the C-ABI over GraphicEQDesigner (see include/EQDesignBridge.h).
//
// Pure C++ (no CoreAudio), so the C++ null test compiles and exercises it directly. The ABI is
// the trust boundary: it rejects NULLs and a wrong count before the designer runs (the designer
// itself rejects non-finite input; engine-plan §7, guard layer 1), and writes nothing unless the
// whole design and read-back succeed.

#include "../include/EQDesignBridge.h"
#include "EQDesignerHandle.h"
#include "GraphicEQDesigner.h"
#include <cstddef>
#include <new>
#include <span>

namespace
{
    using AdaptiveSound::GraphicEQ::kBandCount;
    constexpr auto kBands = static_cast<size_t>(kBandCount);
} // namespace

AsEqDesigner* asEqDesignerCreate(void) AUDIODSP_C_NOEXCEPT
{
    return new (std::nothrow) AsEqDesigner();
}

void asEqDesignerDestroy(AsEqDesigner* designer) AUDIODSP_C_NOEXCEPT
{
    delete designer;
}

bool asEqDesign(AsEqDesigner* designer,
                const float* pointsDb,
                uint32_t pointCount,
                double sampleRate,
                const AsEqDesignOutput* output) AUDIODSP_C_NOEXCEPT
{
    using AdaptiveSound::GraphicEQDesigner;
    if (designer == nullptr || pointsDb == nullptr || output == nullptr ||
        output->centreDb == nullptr || pointCount != static_cast<uint32_t>(kBandCount))
    {
        return false;
    }
    const size_t responseCount = output->responseCount;
    if (responseCount > 0U && (output->responseHz == nullptr || output->responseDb == nullptr))
    {
        return false;
    }

    AdaptiveSound::GraphicEQDesign design{};
    if (!designer->designer.design(
            std::span<const float, kBandCount>(pointsDb, kBands), sampleRate, design))
    {
        return false;
    }
    // The response first: it is the only step that can still fail (a frequency outside
    // [0, fs / 2)), and it writes nothing when it does.
    if (responseCount > 0U && !GraphicEQDesigner::playedResponseDb(
                                  design,
                                  std::span<const double>(output->responseHz, responseCount),
                                  std::span<float>(output->responseDb, responseCount)))
    {
        return false;
    }

    for (size_t band = 0; band < kBands; ++band)
    {
        const double centre = AdaptiveSound::GraphicEQ::centreHz(static_cast<int>(band));
        output->centreDb[band] = static_cast<float>(GraphicEQDesigner::playedDb(design, centre));
        if (output->filterGainDb != nullptr)
        {
            output->filterGainDb[band] = design.filterGainDb[band];
        }
        if (output->svfK != nullptr)
        {
            output->svfK[band] = design.bells[band].k;
        }
        if (output->svfM1 != nullptr)
        {
            output->svfM1[band] = design.bells[band].m1;
        }
    }
    return true;
}
