#ifndef EQ_MODULE_H
#define EQ_MODULE_H
#include "../include/AudioConstants.h"
#include "../include/TargetState.h"
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <vector>

namespace AdaptiveSound
{

    class EQModule
    {
      public:
        EQModule() = default;
        ~EQModule();

        EQModule(const EQModule&) = delete;
        EQModule& operator=(const EQModule&) = delete;
        EQModule(EQModule&&) = delete;
        EQModule& operator=(EQModule&&) = delete;

        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;
        void process(const EQParams& params, AudioBufferList* ioData, uint32_t frameCount) noexcept;

      private:
        // Per-channel delay state for the vDSP_biquad cascade.
        // vDSP requires 2*M + 2 floats for an M-section cascade; size for the max
        // cascade (kMaxBiquads). One independent, non-overlapping buffer per channel
        // (L/R must not share state). Zero-initialized, persists across process()
        // calls (this IS the filter memory). std::array => no heap, RT-safe.
        static constexpr size_t kDelayStateSize = (2 * static_cast<size_t>(kMaxBiquads)) + 2;
        std::array<float, kDelayStateSize> leftDelay_{};
        std::array<float, kDelayStateSize> rightDelay_{};

        // Section count of the last processed cascade; when it changes, the delay
        // state is structurally mismatched and must be re-zeroed.
        uint8_t cachedNumBiquads_ = 0;

        // vDSP_biquad_Setup opaque pointer (defined in Accelerate framework)
        void* cascadeSetup_ = nullptr;

        // Cached coefficient array for vDSP (5 coeffs per stage × kMaxBiquads)
        std::vector<double> cascadeCoeffs_;

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
#endif
