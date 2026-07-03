# Sprint 5b — S4 Binaural Finale: Design (Apple-native)

> **⏸ DEFERRED — folded into [sprint-plan.md](sprint-plan.md) Phase 2 (S17 — BRIR spatial render).** This Apple-native binaural design is retained as the reference design for that future sprint.

**Status:** DESIGN — founder-approved direction · **Date:** 2026-06-17 · **Branch:** `feat/sprint-5-eq-wiring`

> **This revision supersedes the two earlier S4 cores** (per-channel HRIR convolution; and the
> Ambisonic-rotation + MagLS re-spec). After a design pass (4 experts) + research pass (prior art +
> literature) + a library evaluation (2 experts), the founder set two postures —
> **"prefer a well-established library over hand-rolling"** and **"prefer Apple-native platform
> features"** — plus **"mind the Apple-Silicon M1→M5 capability profile even for what we build."**
> These converge on one answer: **use Apple's native spatial-audio engine for the binaural render.**
> The full DSP analysis (HRIR convolution, MagLS, BS.775, externalization, timbre — Pike & Melchior)
> remains valid background and is preserved in git history of this file; it now informs how we *drive*
> Apple's node, not a hand-rolled kernel.

---

## 1. Decision

For the `device < N` case (5.1/7.1 source on stereo headphones — the only audible-multichannel path on
the founder's hardware), render binaural with **Apple's native spatial audio**:
`AVAudioEnvironmentNode` / `AUSpatialMixer` with the **`HRTFHQ`** algorithm. No hand-rolled spherical
-harmonic math, no MagLS solver, no vendored spatial library, no SOFA/libmysofa.

**Why this honors all three postures at once:**
- *Established library* — Apple's spatializer is the most established + battle-tested option (Apple
  Music Spatial Audio, every Atmos title on Apple platforms run through it).
- *Apple-native* — zero third-party dependency, no LGPL/vendoring/build burden, Apple-maintained.
- *M1→M5 capability* — the expensive binaural convolution runs on Apple's natively-optimized path, not
  in our M1 render thread; our own RT DSP stays within the "Yes on M1" set (EQ/limiter/spectrum).
- *Bonus* — head-tracking via `CMHeadphoneMotionManager` and **Personalized Spatial Audio** (per-user
  HRTF on AirPods) come essentially for free; no library matches the latter.

**Trade accepted (supersedes the earlier runtime-SOFA/MagLS choice):** Apple's HRTF is used (opaque,
but personalizable) instead of a custom SOFA; no MagLS tuning; no *measured* pre-binaural ceiling (Apple
manages internal level — our true-peak limiter remains the downstream safety net). Quality is
Apple-Music-grade and validated at scale.

---

## 2. Topology

Keep the N-channel effects in our C++/Accelerate kernel; hand the device-boundary binaural to Apple.

```
device >= N (multichannel device):
  player → AdaptiveSoundAU (N→N: EQ·Clarity·Loudness·Limiter) → SpatialRendererAU (N→N passthrough) → mixer → output   [M3, unchanged]

device <  N (headphones/stereo — binaural):
  player → AdaptiveSoundAU (N→N effects) → split to N positioned virtual loudspeakers
         → AVAudioEnvironmentNode (HRTFHQ, sources placed at ITU-R BS.775 az/el; LFE handled per Apple)
         → 2-ch true-peak limiter (our LimiterModule) → output
```

- **Upstream unchanged:** our N-channel EQ/Clarity/Loudness/Limiter run exactly as today in
  `DSPKernel` (Accelerate). The N-channel pipeline (S1) and the loudness BS.1770 weights (M1) are
  untouched.
- **Virtual loudspeakers:** the N processed channels are placed as N positioned mono sources at their
  `ChannelLayout` BS.775 azimuth/elevation (already decoded in M1). `soundField` mode is the fallback
  if feeding a multichannel/Ambisonic bed directly proves cleaner (open question §5).
- **Our limiter stays:** a 2-ch −1 dBTP `LimiterModule` downstream of the environment node (true-peak
  safety net; Apple's internal level handling is not a guaranteed true-peak ceiling).
- **Reuse from M2-d/M3:** the device-width `M = min(N, device)` logic, the engage state machine, and
  the `AVAudioEngineConfigurationChange` handling carry over — they decide passthrough vs binaural.

---

## 3. Head-tracking + immersive (the founder's earlier picks, now via Apple)

- **Head-tracking (opt-in):** `CMHeadphoneMotionManager` attitude → `AVAudioEnvironmentNode
  .listenerAngularOrientation`, updated per motion callback (~60–100 Hz, off-RT). Apple does the
  rotation internally. Graceful static-front fallback when no motion-capable headphones. Recentre
  control. On AirPods with Personalized Spatial Audio enrolled, Apple substitutes the user's HRTF
  automatically — a free quality win.
- **Immersive default:** `AVAudioEnvironmentReverbParameters` (room preset + blend) for the
  "more dramatic" default — but **user-dialable**, defaulting moderate, reconciling Pike & Melchior
  (timbre dominates; over-coloration scored below stereo). The reverb amount maps to the existing
  Reimagine/intensity dial.

---

## 4. Milestones (much smaller than the hand-rolled plan)

Stereo stays bit-exact throughout (Apple's node is only on the `device < N` branch; `device == N == 2`
on a stereo device is untouched → golden master `0xE7267654BA01D315` holds).

- **S4-1 — Graph wiring** [swift-expert]: on `device < N`, route the effects-AU output through an
  `AVAudioEnvironmentNode` as N BS.775-positioned virtual loudspeakers (HRTFHQ); keep `device ≥ N`
  passthrough; insert the 2-ch limiter downstream. Engage/disengage via the existing state machine +
  `AVAudioEngineConfigurationChange`.
- **S4-2 — Head-tracking** [swift-expert]: `CMHeadphoneMotionManager` → `listenerAngularOrientation`,
  opt-in toggle, recentre, static-front fallback.
- **S4-3 — Immersive/room controls** [swift]: reverb params + dialable amount; conservative-but-
  immersive default; verify tonal neutrality at low settings.
- **S4-4 — Verify + founder listen**: graph/engage offline checks in `VerifyAUGraph` (binaural branch
  builds, device<N renders 2-ch non-silent, stereo passthrough bit-exact); then the **founder
  headphone L3 checklist** (engages on 5.1, spatial placement sane, head-tracking on/off + recentre,
  no distortion, A/B vs stereo). Note: Apple's HRTF render isn't fully unit-testable headlessly, so L3
  founder listening is the primary quality gate here.

---

## 5. Open questions (for the S4-1 wiring spec)

1. **Environment-node input mode:** N positioned **mono** sources (the documented "multichannel stream
   → spatial" pattern) vs the node's `soundField` multichannel-bed mode. Which gives cleaner BS.775
   placement + head-tracking and fits feeding from our custom AU's N-channel output?
2. **Feeding the custom AU into the node:** how to split the `AdaptiveSoundAU` N-channel output into N
   positioned inputs within `AVAudioEngine` (an N-way splitter / per-channel source nodes), and the
   format negotiation.
3. **Limiter insertion point** downstream of the environment node (a 2-ch effect AU vs a tap-based
   stage) without breaking the engine graph.
4. **Reverb realism** — does Apple's built-in reverb satisfy "immersive but timbre-safe," or do we keep
   it near-off and rely on HRTF + early reflections only?

---

## 6. What changed vs the superseded designs

Dropped (no longer built): hand-rolled SH encode/rotation, MagLS decoder + solver, `PartitionedConvolver`,
`BinauralRenderer`, libmysofa/SOFA runtime loading, the vendored spatial lib (SAF/libspatialaudio/etc.),
the offline HRIR-bake + measured-ceiling tooling. Kept: the N-channel effects kernel + loudness weights
(S1/M1), the two-AU topology for `device ≥ N` passthrough (M3), the device-width/engage/config-change
Swift logic (M2-d/M3), and the 2-ch true-peak limiter as the downstream safety net. Net: S4 becomes a
**graph-wiring + head-tracking** effort on Apple's engine, not a DSP-kernel build.
