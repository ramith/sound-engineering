#include "SpatialRenderKernel.h"
#include "../include/FlushToZero.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cstdint>

// SpatialRenderKernel — implementation.
//
// All real-time-safe (RT) code in process() satisfies the audio-thread contract:
//   - No malloc / free / new / delete.
//   - No locks, no Obj-C runtime, no syscalls.
//   - All scratch buffers are pre-allocated off-RT in initialize().
//   - vDSP_mmov and vDSP_vclr are documented RT-safe; they loop internally with
//     no allocations or locks (Apple Accelerate framework source notes, v2023).

namespace AdaptiveSound
{

    // Flush-to-zero (FPCR.FZ) is shared: include/FlushToZero.h. The spatial render thread sets
    // it at render-block entry (SpatialRendererAU.mm); initialize() covers the control thread.

    // ---------------------------------------------------------------------------
    // Private RT-safe helpers — file-scope static (no Accelerate in the header,
    // no class-member indirection, extracted to satisfy the cognitive-complexity
    // threshold of 25 on process()).
    // ---------------------------------------------------------------------------

    // Copy `numIn` channels from `input` to `output` (vDSP_mmov, bit-exact),
    // then zero-fill output channels [numIn, numOut) with vDSP_vclr.
    // Used for the out >= in passthrough route.
    static void routePassthrough(const MultichannelView& input,
                                 const MultichannelView& output,
                                 uint32_t numIn,
                                 uint32_t numOut,
                                 vDSP_Length vLen) noexcept
    {
        // vDSP_mmov: (src, dest, numCols, numRows, srcColStride, destColStride).
        // One-row copy: numCols = vLen, numRows = 1.  RT-safe, no allocation.
        for (uint32_t ch = 0U; ch < numIn; ++ch)
        {
            const float* inPtr = input.channel(ch);
            float* outPtr = output.channel(ch);
            if (inPtr != nullptr && outPtr != nullptr)
            {
                vDSP_mmov(inPtr, outPtr, vLen, 1, vLen, vLen);
            }
        }
        // Zero-fill the extra output channels that have no corresponding input.
        for (uint32_t ch = numIn; ch < numOut; ++ch)
        {
            float* outPtr = output.channel(ch);
            if (outPtr != nullptr)
            {
                vDSP_vclr(outPtr, 1, vLen);
            }
        }
    }

    // S4 binaural STUB for the out < in path.
    //
    // TODO(S4): Replace this entire function with per-channel HRIR convolution
    // N->2 (binaural rendering).  Each output channel accumulates the sum of
    // all input channels convolved with their respective HRIRs (partitioned FFT
    // convolution via vDSP / FFTConvolver, SADIE II / SOFA loaded off-RT by a
    // new configureBIR() entry point in SpatialRenderKernel).
    //
    // THIS IS NOT THE FINAL BINAURAL BEHAVIOUR.  It is a temporary channel-truncation
    // stub so the chain is exercisable end-to-end.  It is explicitly NOT a
    // matrix downmix (which violates the no-naive-downmix mandate — architecture
    // §5b epic).  The comment is the guard; do not remove it before S4 ships.
    //
    // `numOut` channels of input are copied to output; input channels [numOut, numIn)
    // are intentionally discarded (they represent source channels that S4 will
    // HRIR-convolve and accumulate).
    static void routeBinauralStub(const MultichannelView& input,
                                  const MultichannelView& output,
                                  uint32_t numOut,
                                  vDSP_Length vLen) noexcept
    {
        // Stub body: copy first numOut input channels verbatim.
        // (S4 replaces this with HRIR accumulation over ALL numIn channels.)
        for (uint32_t ch = 0U; ch < numOut; ++ch)
        {
            const float* inPtr = input.channel(ch);
            float* outPtr = output.channel(ch);
            if (inPtr != nullptr && outPtr != nullptr)
            {
                vDSP_mmov(inPtr, outPtr, vLen, 1, vLen, vLen);
            }
        }
    }

    // Zero all channels in `output` that MultichannelView reports as present.
    static void zeroOutputChannels(const MultichannelView& output, vDSP_Length vLen) noexcept
    {
        const uint32_t viewCh = output.channels();
        for (uint32_t ch = 0U; ch < viewCh; ++ch)
        {
            float* outPtr = output.channel(ch);
            if (outPtr != nullptr)
            {
                vDSP_vclr(outPtr, 1, vLen);
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Off-RT: initialize
    // ---------------------------------------------------------------------------

    auto SpatialRenderKernel::initialize(uint32_t sampleRate, uint32_t maxFramesToRender) noexcept
        -> void
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFramesToRender;

        // FTZ on the control/init thread.  The AU render block sets it independently
        // on the render thread (matching DSPKernel's pattern).
        enableFlushToZero();
    }

    // ---------------------------------------------------------------------------
    // Off-RT: configure
    // ---------------------------------------------------------------------------

    auto SpatialRenderKernel::configure(uint32_t numInChannels, uint32_t numOutChannels) noexcept
        -> void
    {
        inChannels_ = std::min(numInChannels, kMaxChannels);
        outChannels_ = std::min(numOutChannels, kMaxChannels);
    }

    // ---------------------------------------------------------------------------
    // RT: process  (NON-IN-PLACE; input and output are SEPARATE ABLs)
    // ---------------------------------------------------------------------------

    auto SpatialRenderKernel::process(const MultichannelView& input,
                                      const MultichannelView& output) const noexcept -> void
    {
        // Guard: frame-count mismatch or zero frames — nothing to render.
        const uint32_t inFrames = input.frames();
        const uint32_t outFrames = output.frames();
        if (inFrames == 0U || inFrames != outFrames)
        {
            return;
        }
        // Guard: frame count must not exceed the capacity established in initialize().
        // Over-budget frames would access out-of-range output memory; silently skip.
        if (inFrames > maxFrames_)
        {
            return;
        }

        const uint32_t numIn = inChannels_;
        const uint32_t numOut = outChannels_;
        const vDSP_Length vLen = static_cast<vDSP_Length>(inFrames);

        // Guard: zero-channel config — silence all output channels and return.
        if (numIn == 0U || numOut == 0U)
        {
            zeroOutputChannels(output, vLen);
            return;
        }

        if (numOut >= numIn)
        {
            // Identity / passthrough route: out >= in.
            // Route each source channel to the same-indexed device channel;
            // extra device channels are zeroed.
            routePassthrough(input, output, numIn, numOut, vLen);
        }
        else
        {
            // out < in: S4 binaural rendering path.
            // Stub: copy first numOut source channels; discard the rest.
            // S4 replaces this with full HRIR convolution N->2.
            routeBinauralStub(input, output, numOut, vLen);
        }
    }

} // namespace AdaptiveSound
