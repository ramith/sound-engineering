#pragma once

#include <cstdint>

namespace AdaptiveSound
{

    // ScopedFlushToZero — flush subnormals to zero on the CALLING thread for the guard's lifetime,
    // then give the thread its floating-point mode back.
    //
    // Denormal arithmetic on the audio path causes large, unpredictable RT CPU spikes (IIR tails
    // decaying into subnormals), so our DSP runs with subnormals flushed. But the threads it runs
    // on are mostly not ours: the render block runs on AVAudioEngine's I/O thread, which Apple's
    // own nodes share (they render inside our pull()), and initialize() runs on a libdispatch pool
    // thread that later runs unrelated work. So flush-to-zero is SCOPED to our own calls — set at
    // the entry of each render call and each worker loop, restored when it returns — never left
    // set behind us (council C-50, DSP-11). This is JUCE's ScopedNoDenormals
    // (juce_FloatVectorOperations.h/.cpp: save the status register, OR in the flush bit — mask
    // 1 << 24 on AArch64 — restore it in the destructor).
    //
    // On AArch64 (Apple Silicon) a single FPCR.FZ flag (bit 24) flushes BOTH input and output
    // subnormals to zero — the x86 FTZ + DAZ pair in one bit — for single AND double precision
    // alike (measured on M-series by council D67: a double 1e-310 flushes to 0). FPCR is a
    // per-thread register. It is read and written through Clang's AArch64 system-register builtins
    // (__builtin_arm_rsr64 / __builtin_arm_wsr64): the same mrs/msr, visible to the compiler and
    // clean under portability-no-assembler. A guard writes only when FZ was clear, so a nested
    // guard (the kernel inside a caller's) costs one read.
    //
    // On x86_64 (CI / simulator) Accelerate/vDSP sets FTZ/DAZ internally; the guard is a no-op
    // there rather than depending on <xmmintrin.h> / _MM_SET_FLUSH_ZERO_MODE.
    //
    // Reference: ARM DDI 0487 §A1.4.3 (FPCR); Clang "ARM/AArch64 system register builtins".
    class ScopedFlushToZero
    {
      public:
        ScopedFlushToZero() noexcept : saved_(readFpcr())
        {
            if ((saved_ & kFpcrFlushToZeroBit) == 0U)
            {
                writeFpcr(saved_ | kFpcrFlushToZeroBit);
            }
        }

        ~ScopedFlushToZero() noexcept
        {
            if ((saved_ & kFpcrFlushToZeroBit) == 0U)
            {
                writeFpcr(saved_);
            }
        }

        ScopedFlushToZero(const ScopedFlushToZero&) = delete;
        ScopedFlushToZero& operator=(const ScopedFlushToZero&) = delete;
        ScopedFlushToZero(ScopedFlushToZero&&) = delete;
        ScopedFlushToZero& operator=(ScopedFlushToZero&&) = delete;

      private:
        static constexpr uint64_t kFpcrFlushToZeroBit = 1ULL << 24U; // FPCR.FZ

        // Off AArch64 there is no FPCR: read as "already flushing", so the guard never writes.
        [[nodiscard]] static uint64_t readFpcr() noexcept
        {
#ifdef __aarch64__
            return __builtin_arm_rsr64("fpcr");
#else
            return kFpcrFlushToZeroBit;
#endif
        }

        static void writeFpcr(uint64_t value) noexcept
        {
#ifdef __aarch64__
            __builtin_arm_wsr64("fpcr", value);
#else
            (void)value;
#endif
        }

        uint64_t saved_; // the caller's FPCR
    };

} // namespace AdaptiveSound
