// TrackLoudnessProfile.cpp — the band grid and the gated loudness-change predictor. See
// TrackLoudnessProfile.h.

#include "TrackLoudnessProfile.h"
#include "../EQ/GraphicEQDesigner.h"
#include "LufsMeter.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <numbers>
#include <numeric>
#include <vector>

namespace AdaptiveSound
{
    namespace
    {
        // BS.1770's gates as block-energy thresholds: l_j > −70 LUFS ⇔ z_j > 10^((−70 + 0.691)/10),
        // and l_j > L − 10 LU ⇔ z_j > mean · 10^(−10/10). Comparing energies, not loudness, keeps
        // the logarithm out of the per-block loop.
        [[nodiscard]] double absoluteGateEnergy() noexcept
        {
            return std::pow(kDecibelBase, (kAbsoluteGateLufs - kLufsOffset) / kDbPowerScale);
        }

        [[nodiscard]] double relativeGateFactor() noexcept
        {
            return std::pow(kDecibelBase, kRelativeGateOffsetLu / kDbPowerScale);
        }

        // One gated mean in progress.
        struct GateSum
        {
            double energy = 0.0;
            uint32_t blocks = 0U;

            void add(double blockEnergy) noexcept
            {
                energy += blockEnergy;
                ++blocks;
            }
            [[nodiscard]] double mean() const noexcept
            {
                return energy / static_cast<double>(blocks);
            }
        };

        // Block j's energy without (plain) and with (weighted) the curve, over the played bands.
        // The same loop forms both, so a unity gain gives bit-identical sums.
        struct BlockEnergy
        {
            double plain = 0.0;
            double weighted = 0.0;
        };

        [[nodiscard]] BlockEnergy blockEnergy(std::span<const float> bands,
                                              std::span<const double> powerGain) noexcept
        {
            BlockEnergy energy;
            for (size_t band = 0; band < powerGain.size(); ++band)
            {
                const auto power = static_cast<double>(bands[band]);
                energy.plain += power;
                energy.weighted += power * powerGain[band];
            }
            return energy;
        }

        // The two-stage gated loudness of the profile's blocks without and with the curve
        // (`powerGain` covers the played bands). False when either set has no block left after
        // its gates.
        struct GatedPair
        {
            double plainLufs = 0.0;
            double weightedLufs = 0.0;
        };

        [[nodiscard]] bool gatedLoudnessPair(const TrackLoudnessProfile& profile,
                                             std::span<const double> powerGain,
                                             uint32_t blockStep,
                                             GatedPair& out) noexcept
        {
            const double absoluteGate = absoluteGateEnergy();
            // Pass 1: the absolute gate, for each set's relative threshold.
            GateSum plainAbsolute;
            GateSum weightedAbsolute;
            for (uint32_t index = 0; index < profile.blockCount; index += blockStep)
            {
                const BlockEnergy energy = blockEnergy(profile.block(index), powerGain);
                if (energy.plain > absoluteGate)
                {
                    plainAbsolute.add(energy.plain);
                }
                if (energy.weighted > absoluteGate)
                {
                    weightedAbsolute.add(energy.weighted);
                }
            }
            if (plainAbsolute.blocks == 0U || weightedAbsolute.blocks == 0U)
            {
                return false;
            }
            const double plainGate =
                std::max(absoluteGate, plainAbsolute.mean() * relativeGateFactor());
            const double weightedGate =
                std::max(absoluteGate, weightedAbsolute.mean() * relativeGateFactor());
            // Pass 2: both gates. Re-forming the block sums costs a second pass but no scratch.
            GateSum plainGated;
            GateSum weightedGated;
            for (uint32_t index = 0; index < profile.blockCount; index += blockStep)
            {
                const BlockEnergy energy = blockEnergy(profile.block(index), powerGain);
                if (energy.plain > plainGate)
                {
                    plainGated.add(energy.plain);
                }
                if (energy.weighted > weightedGate)
                {
                    weightedGated.add(energy.weighted);
                }
            }
            if (plainGated.blocks == 0U || weightedGated.blocks == 0U)
            {
                return false;
            }
            out.plainLufs = kLufsOffset + (kDbPowerScale * std::log10(plainGated.mean()));
            out.weightedLufs = kLufsOffset + (kDbPowerScale * std::log10(weightedGated.mean()));
            return std::isfinite(out.plainLufs) && std::isfinite(out.weightedLufs);
        }

        // A profile whose shape is internally consistent (it is only ever built by the profiler,
        // but a prediction must never index past its storage).
        [[nodiscard]] bool wellFormed(const TrackLoudnessProfile& profile) noexcept
        {
            return profile.bandCount > 0U && profile.bandCount <= TrackLoudness::kMaxBandCount &&
                   profile.bandPower.size() == static_cast<size_t>(profile.blockCount) *
                                                   static_cast<size_t>(profile.bandCount);
        }
    } // namespace

    namespace TrackLoudness
    {
        double edgeHz(uint32_t edge) noexcept
        {
            return kFirstEdgeHz * std::exp2(static_cast<double>(edge) / kBandsPerOctave);
        }

        uint32_t bandCount(double sampleRate) noexcept
        {
            if (!std::isfinite(sampleRate) || sampleRate < kMinSampleRateHz ||
                sampleRate > kMaxSampleRateHz)
            {
                return 0U;
            }
            const double nyquist = sampleRate / 2.0;
            uint32_t edges = 0U;
            while (edgeHz(edges) < nyquist)
            {
                ++edges;
            }
            return edges + 1U; // band 0 sits below the first edge
        }

        double bandCentreHz(uint32_t band, double sampleRate) noexcept
        {
            const uint32_t count = bandCount(sampleRate);
            const double lower = (band == 0U) ? 0.0 : edgeHz(band - 1U);
            const double upper = (band + 1U >= count) ? (sampleRate / 2.0) : edgeHz(band);
            return std::sqrt(std::max(lower, kLowestCentreFloorHz) * upper);
        }
    } // namespace TrackLoudness

    std::span<const float> TrackLoudnessProfile::block(uint32_t index) const noexcept
    {
        const size_t width = bandCount;
        return std::span<const float>(bandPower).subspan(static_cast<size_t>(index) * width, width);
    }

    size_t TrackLoudnessProfile::memoryBytes() const noexcept
    {
        return sizeof(TrackLoudnessProfile) + (bandPower.capacity() * sizeof(float));
    }

    bool predictLoudnessChangeDb(const TrackLoudnessProfile& profile,
                                 std::span<const double> bandGainDb,
                                 uint32_t blockStep,
                                 double& changeDb) noexcept
    {
        if (!wellFormed(profile) || profile.blockCount == 0U || blockStep == 0U ||
            bandGainDb.empty() || bandGainDb.size() > profile.bandCount)
        {
            return false;
        }
        std::array<double, TrackLoudness::kMaxBandCount> powerGain{};
        for (size_t band = 0; band < bandGainDb.size(); ++band)
        {
            if (!std::isfinite(bandGainDb[band]))
            {
                return false;
            }
            powerGain[band] = std::pow(kDecibelBase, bandGainDb[band] / kDbPowerScale);
        }
        GatedPair loudness;
        if (!gatedLoudnessPair(profile,
                               std::span<const double>(powerGain.data(), bandGainDb.size()),
                               blockStep,
                               loudness))
        {
            return false;
        }
        const double change = loudness.weightedLufs - loudness.plainLufs;
        if (!std::isfinite(change))
        {
            return false;
        }
        changeDb = change;
        return true;
    }

    bool predictLoudnessChangeDb(const TrackLoudnessProfile& profile,
                                 const GraphicEQDesign& design,
                                 uint32_t blockStep,
                                 double& changeDb) noexcept
    {
        if (!std::isfinite(design.sampleRate) || !(design.sampleRate > 0.0) || !wellFormed(profile))
        {
            return false;
        }
        // The played response at each band centre the output can carry: a band at or above the
        // output's Nyquist was removed by the sample-rate converter, so it is not played at all.
        const double outputNyquist = design.sampleRate / 2.0;
        std::array<double, TrackLoudness::kMaxBandCount> responseDb{};
        size_t played = 0U;
        while (played < profile.bandCount)
        {
            const double centre =
                TrackLoudness::bandCentreHz(static_cast<uint32_t>(played), profile.sampleRate);
            if (!(centre < outputNyquist))
            {
                break;
            }
            responseDb[played] = GraphicEQDesigner::playedDb(design, centre);
            ++played;
        }
        return predictLoudnessChangeDb(
            profile, std::span<const double>(responseDb.data(), played), blockStep, changeDb);
    }

    double profileLoudnessLufs(const TrackLoudnessProfile& profile) noexcept
    {
        if (!wellFormed(profile) || profile.blockCount == 0U)
        {
            return kSilenceLufs;
        }
        std::array<double, TrackLoudness::kMaxBandCount> unity{};
        std::fill_n(unity.begin(), profile.bandCount, 1.0);
        GatedPair loudness;
        if (!gatedLoudnessPair(
                profile, std::span<const double>(unity.data(), profile.bandCount), 1U, loudness))
        {
            return kSilenceLufs;
        }
        return loudness.plainLufs;
    }

    double blockLoudnessLufs(const TrackLoudnessProfile& profile, uint32_t index) noexcept
    {
        if (!wellFormed(profile) || index >= profile.blockCount)
        {
            return kSilenceLufs;
        }
        const std::span<const float> bands = profile.block(index);
        const double energy = std::accumulate(bands.begin(),
                                              bands.end(),
                                              0.0,
                                              [](double sum, float power)
                                              { return sum + static_cast<double>(power); });
        return (energy > kTinyEnergy) ? (kLufsOffset + (kDbPowerScale * std::log10(energy)))
                                      : kSilenceLufs;
    }

    namespace
    {
        // |H(e^{jω})|² of one K-weighting stage.
        [[nodiscard]] double biquadPower(const LufsBiquad& stage, double omega) noexcept
        {
            const double c1 = std::cos(omega);
            const double s1 = std::sin(omega);
            const double c2 = std::cos(2.0 * omega);
            const double s2 = std::sin(2.0 * omega);
            const double numRe = stage.b0 + (stage.b1 * c1) + (stage.b2 * c2);
            const double numIm = -((stage.b1 * s1) + (stage.b2 * s2));
            const double denRe = 1.0 + (stage.a1 * c1) + (stage.a2 * c2);
            const double denIm = -((stage.a1 * s1) + (stage.a2 * s2));
            return ((numRe * numRe) + (numIm * numIm)) / ((denRe * denRe) + (denIm * denIm));
        }

        // The pink prior's level: a typical programme loudness, well inside both gates.
        constexpr double kPinkPriorLufs = -23.0;
    } // namespace

    std::shared_ptr<const TrackLoudnessProfile> makePinkPriorProfile(double sampleRate)
    {
        const uint32_t bands = TrackLoudness::bandCount(sampleRate);
        if (bands == 0U)
        {
            return nullptr;
        }
        auto prior = std::make_shared<TrackLoudnessProfile>();
        prior->sampleRate = sampleRate;
        prior->channelCount = 1U;
        prior->bandCount = bands;
        prior->blockCount = 1U;
        prior->bandPower.assign(bands, 0.0F);
        const LufsKWeight kWeight = makeKWeighting(sampleRate);
        std::vector<double> power(bands, 0.0);
        double total = 0.0;
        for (uint32_t band = 0U; band < bands; ++band)
        {
            const double lower = (band == 0U) ? 0.0 : TrackLoudness::edgeHz(band - 1U);
            const double upper =
                (band + 1U >= bands) ? (sampleRate / 2.0) : TrackLoudness::edgeHz(band);
            const double centre = TrackLoudness::bandCentreHz(band, sampleRate);
            const double omega = 2.0 * std::numbers::pi * centre / sampleRate;
            const double octaves =
                std::log(upper / std::max(lower, TrackLoudness::kLowestCentreFloorHz));
            power[band] = std::max(0.0, octaves) * biquadPower(kWeight.shelf, omega) *
                          biquadPower(kWeight.rlb, omega);
            total += power[band];
        }
        const double target =
            std::pow(kDecibelBase, (kPinkPriorLufs - kLufsOffset) / kDbPowerScale);
        const double scale = (total > 0.0) ? (target / total) : 0.0;
        for (uint32_t band = 0U; band < bands; ++band)
        {
            prior->bandPower[band] = static_cast<float>(power[band] * scale);
        }
        prior->sourceLoudnessLufs = profileLoudnessLufs(*prior);
        return prior;
    }
} // namespace AdaptiveSound
