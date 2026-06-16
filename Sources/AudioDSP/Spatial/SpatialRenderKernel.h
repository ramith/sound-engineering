#ifndef ADAPTIVE_SOUND_SPATIAL_RENDER_KERNEL_H
#define ADAPTIVE_SOUND_SPATIAL_RENDER_KERNEL_H

// SpatialRenderKernel — host-agnostic C++ DSP core for SpatialRendererAU.
//
// Topology (M3 scope):
//   The existing AdaptiveSoundAU / DSPKernel is the N->N effects unit
//   (EQ->Clarity->Loudness->Limiter, in-place on source channels).  This kernel
//   is a SEPARATE device-boundary stage that maps N source channels -> M device
//   channels.  It is NOT in-place: input and output are distinct buffer sets with
//   (potentially) different channel counts.  The AU wrapper (M3-2) and graph
//   wiring (M3-3) are separate chunks.
//
// M3 behaviour (identity / passthrough / route):
//   out >= in  — copy input channel ch -> output channel ch for ch in [0, in).
//                Zero-fill output channels [in, out).
//                Implemented with vDSP_mmov per channel (bit-exact copy).
//   out < in   — S4 binaural stub; see TODO(S4) in SpatialRenderKernel.mm.
//
// RT-safety contract:
//   process() is REAL-TIME SAFE: no allocation, no lock, no syscall, no Obj-C
//   runtime.  All scratch is sized in initialize() (off-RT).  vDSP_mmov and
//   vDSP_vclr are RT-safe Accelerate calls (no internal allocation).
//
// Interface design for S4 extensibility:
//   configure() accepts inChannels + outChannels and stores them.  When S4 adds
//   HRIR convolution, it will supply per-channel impulse-response buffers via a
//   new configureBIR() (or equivalent) off-RT entry point; process() already
//   branches on (outChannels_ < inChannels_) so S4 replaces only the stub body
//   without touching the M >= N path.
//
// No Obj-C, no AVFoundation, no AudioUnit headers — fully host-agnostic.
// Callers include only AudioConstants.h and MultichannelView.h.

#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include <cstdint>

namespace AdaptiveSound
{

    class SpatialRenderKernel
    {
      public:
        SpatialRenderKernel() = default;
        ~SpatialRenderKernel() = default;

        SpatialRenderKernel(const SpatialRenderKernel&) = delete;
        auto operator=(const SpatialRenderKernel&) -> SpatialRenderKernel& = delete;
        SpatialRenderKernel(SpatialRenderKernel&&) = delete;
        auto operator=(SpatialRenderKernel&&) -> SpatialRenderKernel& = delete;

        // -----------------------------------------------------------------------
        // Off-RT: store config (sample rate, max frame capacity) and enable
        // flush-to-zero on the init thread. No heap allocation — process() zeroes
        // silent output channels in place via vDSP_vclr. Must be called once from
        // the control/setup thread before any process() call; safe to call again
        // on sample-rate or buffer-size change.
        // -----------------------------------------------------------------------
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // -----------------------------------------------------------------------
        // Off-RT: set channel routing.
        //
        // Clamps both counts to [0, kMaxChannels].  Call from the control thread
        // whenever the source or device channel layout changes.
        // -----------------------------------------------------------------------
        void configure(uint32_t inChannels, uint32_t outChannels) noexcept;

        // -----------------------------------------------------------------------
        // RT: process one block.  NON-IN-PLACE.  const: no mutable state touched.
        //
        // `input`  — source bus (N channels, inChannels_ of which are valid).
        // `output` — device bus (M channels, outChannels_ of which are valid).
        //
        // `input` and `output` MUST be different buffer sets; aliasing is
        // undefined behaviour (the underlying vDSP_mmov is undefined for
        // overlapping regions).
        //
        // Preconditions checked via early return (RT-safe, no assert/throw):
        //   - input.frames() == output.frames() and both > 0.
        //   - inChannels_ == 0 or outChannels_ == 0  → silent output (vDSP_vclr).
        // -----------------------------------------------------------------------
        void process(const MultichannelView& input, const MultichannelView& output) const noexcept;

        // -----------------------------------------------------------------------
        // Read-only accessors (off-RT convenience; not used from process()).
        // -----------------------------------------------------------------------
        [[nodiscard]] auto inChannels() const noexcept -> uint32_t
        {
            return inChannels_;
        }
        [[nodiscard]] auto outChannels() const noexcept -> uint32_t
        {
            return outChannels_;
        }
        [[nodiscard]] auto maxFrames() const noexcept -> uint32_t
        {
            return maxFrames_;
        }

      private:
        // Routing config — written off-RT by configure(), read on-RT by process().
        // No atomic needed: configure() must complete (with a memory barrier at
        // the calling thread's scheduler boundary) before process() is called.
        // The AU wrapper (M3-2) is responsible for this ordering guarantee.
        uint32_t inChannels_ = 0U;
        uint32_t outChannels_ = 0U;
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_SPATIAL_RENDER_KERNEL_H
