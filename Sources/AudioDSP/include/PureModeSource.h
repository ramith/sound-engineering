#pragma once

//
// PureModeSource.h — RT-safe pull-source interface for the HAL output engine.
//
// CoreAudio-FREE: a plain virtual interface the engine pulls float PCM from — implemented by the
// file decoder (FileDecodeSource) and the gapless concatenator over it (GaplessSource).
// -fno-exceptions / -fno-rtti clean (no throw / dynamic_cast / typeid).
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

      protected:
        // Protected (not public) copy/move: a polymorphic base must not be sliced through a base
        // reference (C.67/C.130). Concrete leaves define their own copy/move (Stage-2 review OWN-5).
        PureModeSource(const PureModeSource&) = default;
        PureModeSource& operator=(const PureModeSource&) = default;
        PureModeSource(PureModeSource&&) = default;
        PureModeSource& operator=(PureModeSource&&) = default;
    };

} // namespace AdaptiveSound
