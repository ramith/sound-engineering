#pragma once

#include <cstdint>

namespace AdaptiveSound
{

    // enableFlushToZero() — enable flush-to-zero (denormals-are-zero) on the CALLING thread.
    //
    // Denormal arithmetic on the audio path causes large, unpredictable RT CPU spikes (IIR
    // tails decaying into subnormals), so every thread that runs DSP must flush subnormals.
    //
    // On AArch64 (Apple Silicon) a single FPCR.FZ flag (bit 24) flushes BOTH input and output
    // subnormals to zero — equivalent to the combined x86 FTZ + DAZ pair. The x86 MXCSR.DAZ
    // (denormals-are-zero for inputs) has no separate AArch64 counterpart; FPCR.FZ covers both.
    //
    // FPCR is a PER-THREAD register, so this MUST be called on EVERY thread that runs DSP: the
    // control/init thread (kernel initialize()), the AU render thread and the spatial render
    // thread (at render-block entry), and any Audio-Workgroup / loudness-measurement worker.
    //
    // On x86_64 (CI / simulator) Accelerate/vDSP already sets FTZ/DAZ internally; we leave
    // MXCSR alone rather than depend on <xmmintrin.h> / _MM_SET_FLUSH_ZERO_MODE.
    //
    // Reference: ARM DDI 0487 §A1.4.3 (FPCR); Apple Silicon LLVM inline-asm guide.
    //
    // This is the single definition; it replaces the five hand-maintained copies that had
    // drifted to two names and two constant encodings (Stage-1 review AR-1).
    inline void enableFlushToZero() noexcept
    {
#ifdef __aarch64__
        constexpr uint64_t kFpcrFlushToZeroBit = 1ULL << 24U; // FPCR.FZ
        uint64_t fpcr = 0U;
        __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
        fpcr |= kFpcrFlushToZeroBit; // flush subnormal inputs and outputs to zero
        __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
#endif
    }

} // namespace AdaptiveSound
