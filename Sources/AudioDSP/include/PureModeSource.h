#pragma once

//
// PureModeSource.h — RT-safe pull-source interface for the HAL output engine.
//
// CoreAudio-FREE: a plain virtual interface the engine pulls float PCM from. B2b will add a
// file-decode source; B2a ships a ToneSource for smoke-testing without a file. -fno-exceptions /
// -fno-rtti clean (no throw / dynamic_cast / typeid).
//

#include <cstdint>

namespace AdaptiveSound
{

    // A pluggable source of interleaved float PCM, pulled from the HAL render thread.
    class PureModeSource
    {
      public:
        PureModeSource() = default;
        virtual ~PureModeSource() = default;

        PureModeSource(const PureModeSource&) = default;
        PureModeSource& operator=(const PureModeSource&) = default;
        PureModeSource(PureModeSource&&) = default;
        PureModeSource& operator=(PureModeSource&&) = default;

        // Fill up to `frames` of interleaved float samples in [-1, 1], `channels` wide, into `out`
        // (out has room for frames*channels floats). Returns the number of frames actually
        // produced.
        //
        // A return < frames means short fill (end-of-stream or underrun); the engine zero-fills the
        // remaining frames so the device never receives stale/garbage samples. Returning 0 means
        // nothing was produced (the engine emits a full buffer of silence).
        //
        // RT CONTRACT: called on the audio render thread. Implementations MUST NOT allocate, take a
        // lock, perform I/O, or throw. noexcept is part of the contract.
        virtual uint32_t pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept = 0;
    };

    // A simple sine-tone source for smoke-testing the engine without a decoded file.
    // Generates the same tone on every channel. Allocation-free and lock-free in pullFloat.
    class ToneSource final : public PureModeSource
    {
      public:
        // freqHz: tone frequency; amplitude: peak in [0, 1]; sampleRate: the device render rate.
        ToneSource(double freqHz, float amplitude, double sampleRate) noexcept;

        uint32_t pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept override;

      private:
        double phase_ = 0.0;    // current phase in radians
        double phaseInc_ = 0.0; // 2*pi*freq / sampleRate
        float amplitude_ = 0.0F;
    };

} // namespace AdaptiveSound
