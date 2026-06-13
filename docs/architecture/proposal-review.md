# Architecture Proposal — Panel Review (synthesis)

**Date:** 2026-06-13 · **Reviewers:** PM (product), BA (requirements), DSP/Psychoacoustics (literature), Spatial/Adaptive/NL (literature).
**Inputs:** [proposal.md](proposal.md) v0.1. **All four verdicts: ENDORSE-WITH-CHANGES.**

## Validated — keep as-is
The two literature reviewers and the BA all endorse the **backbone**: control plane / data plane split; **off-RT Realizer** (RT kernel only ramps/runs finished coefficients); native-first stack (vDSP/Accelerate, AudioToolbox, Audio Workgroups, BNNS Graph); the prior-art reuse/license map; process-taps for Phase 2; own-player-first. *"Ship the backbone."* The changes below are about **what the DSP does**, not how it's wired.

---

## Convergent must-change findings (multiple reviewers + literature)

### P0 — architectural

**1. Minimum-phase by default, not linear-phase FIR.** The cost of linear-phase isn't latency — it's **pre-ringing**, a non-maskable pre-transient artifact that's *worse* than min-phase smear on exactly the percussive/transient material we want to render with "detail." SOTA EQ (FabFilter Pro-Q) ships **min/"natural" phase as default** and warns against linear-phase pre-ring. → Default = minimum-phase; offer mixed / band-limited low-latency-linear-phase as opt-in; **select phase mode by *content* (transient density from pre-analysis), not by session type.** (DSP C1, Spatial P6, PM Contradiction 1) — *FabFilter Pro-Q help; audiomasterclass.*

**2. BRIR / virtual-room is the default headphone immersion — dry HRTF is the degenerate case.** Dry anechoic HRTF reliably sounds **in-head and colored** with non-individualized data; **reverberation carrying interaural differences** is what externalizes — *not* headphone-correction EQ. And: good **non-individualized BRIRs ≈ individualized** for externalization, so a quality BRIR set sidesteps per-user measurement. → Rewrite ADR-003 around BRIR (HRTF + early reflections + late reverb, synthesized via image-source + FDN or CC0 IRs); SADIE dry-HRIR becomes the anechoic core *inside* the BRIR. Headphone correction = timbre only. **Co-ship BRIR with HRTF in Phase 1 (M, not S).** (Spatial C1/P0, DSP cross-cutting, PM Refinement 1/Contradiction 2) — *Leclère et al. 2019 JASA; Nature Sci Rep 2021.*

**3. Demote the single dB-curve from "the tonal model" to "the EQ realization/interchange format."** A summed dB-on-log curve can't express what actually drives perceived clarity — **masking relief, spectral contrast, partial loudness** — nor transient/dynamics/spatial moves. → Keep the curve for *realizing* tonal EQ, but compute **adaptive/clarity/masking decisions in ERB/Bark against a masking + partial-loudness model** (Moore-Glasberg), and **extend contributors to *typed* moves** (static-EQ curve **+** per-band dynamic gain **+** transient **+** spatial), not one magnitude curve. (DSP C2, Spatial C3/C4, PM Contradiction 3, BA Refinement 6) — *Moore-Glasberg loudness; Hafezi & Reiss masking EQ; Wilson & Fazenda clarity model.*

### P1

**4. NL = a typed multi-band "macro", not a single-region clamp.** Descriptor→DSP maps (SAFE/SocialEQ) are **multi-band, often non-monotonic, and frequently non-tonal** ("punch"=transient/dynamics, "harsh"=dynamic/sibilance). Cross-user agreement on "warm/bright" is **low** → mappings must be **per-user-adaptable**. → `interpret(text,context) → {eq_bands[], dynamics?, transient?, spatial?, confidence}`; seed from SAFE-DB/SocialEQ priors; CLAP/LLM back-ends (Text2FX, LLM2Fx, Population-Aligned LLM-EQ) **behind a validation harness** (some CLAP embeddings *invert* "warm"). Keep the "user intent outranks auto-contributors in the regions it touches" rule. (Spatial P4/C3, PM Refinement 3) — *SAFE; SocialEQ/SocialFX; Text2FX (ICASSP'25); arXiv 2510.14249; 2601.09448.*

**5. "Vocals are buried" can't be solved by EQ on a finished mix — it's inter-source masking.** True unmasking needs per-source data. → Either (a) scope it to an honest **presence/clarity macro** (controlled 1–4 kHz presence + ~200–500 Hz de-mask dip + optional vocal-band dynamic EQ) labeled as an approximation, or (b) **gate true unmasking behind the offline Demucs path**. Don't silently map it to a tonal clamp. (Spatial P1/C3) — *Ronan et al.; iZotope Neutron masking meter requires stems.*

**6. Loudness compensation: not raw ISO 226 deltas.** Correct comp is a **fraction of the *difference*** between reference and playback contours, with **per-device SPL calibration** + **loudness-matched makeup**, **rate-limited to volume changes** (not program dynamics). Absolute SPL is unknowable without calibration — the reason the hi-fi "loudness button" died. Cap LF boost. (DSP topic 4/C4, Spatial P5) — *APU Loudness Contour; ISO 226:2023≈2003.*

**7. Dynamics: no program DRC by default.** For fidelity on good sources, listeners can't reliably detect ≤12 dB of DRC and don't prefer compressed masters → adding it is risk without reward. → **Transparent LUFS normalization + true-peak safety limiter only** (4× oversampling, −1 dBTP, ~1 ms look-ahead, ITU-R BS.1770-5). Prefer **dynamic EQ over multiband compression** if any is added. (DSP topic 5/C5)

**8. Add a speaker-immersion contributor (currently missing) with mono-compatibility as a hard constraint.** Crossfeed is headphones-only. For speakers: **M/S width + ambience extraction (preserve M)**; offer **crosstalk-cancellation/transaural only as an opt-in "centered near-field desk" mode** (stereo-dipole narrow span) — never aggressive XTC blind on laptop speakers. (Spatial P2/C, PM Risk 2)

### P2

**9. Crossfeed → opt-in, off by default** (subsumed by BRIR; weak evidentiary support). (DSP C6, Spatial)
**10. Head-tracking → opt-in for stereo music** (often unwanted/"weird"; its externalization benefit is already covered by good BRIR). (Spatial C5)
**11. Biquad fitting — name a method + error budget:** NLLS/Levenberg-Marquardt parametric fit (or IIRNet, MIT), **ERB/masking-weighted**, fit the **min-phase target**; define max audible deviation (e.g., ±1 dB). (DSP topic 2/refinement 9)
**12. Virtual bass — multiband + transient/steady-state hybrid, device/SPL-gated, mono-sum** (gate to transducers that can't reproduce the fundamental). (DSP topic 6)
**13. Ear-photo HRTF personalization — name it as a Phase 2 feature** (Apple ships free ear-scan personalization; the gap widens otherwise). (PM Refinement 4)

---

## Requirements rigor (BA) — actions to capture

- **LD-11 (new):** source-quality assumption + **audio-repair is a non-goal** + network optional/offline-capable core. (Founder-confirmed; lock it.)
- **Fix LD-6 drift:** the proposal's adaptivity section implies continuous mic; make **on-demand (~3 s, then release)** explicit.
- **Governing-principle enforcement:** Arbiter holds **locked-band/macro records** (region + floor/ceiling) written on NLT confirm, cleared on undo/session-end; clamp the aggregate there.
- **Privacy section (missing):** mic→scalar-only never transmitted; hearing profile encrypted/on-device; **cloud-LLM `context` must exclude audio buffers + hearing data**; graceful offline fallback.
- **NFR-QUAL gaps:** THD+N budget across the chain; a **bit-transparent hard-bypass** path; validate at 44.1/48/88.2/96 kHz.
- **NFR-PERF-05:** Phase-2 latency budget — 256-frame aggregate buffer, ≤50% period, loopback-IR acceptance test.
- **Hearing Profile Service:** name it as a component (calibration, safe-volume guard, encrypted store, per-ear contributor curve).
- **Gate Phase-1 eng on OQ-15b/c**; add **OQ-18** (min-phase vs linear-phase per content).
- **Testability ACs** for: QualityProfile auto-selection, biquad-fit tolerance, governing-principle clamping, pre-scan-completes-before-playback.

## Product (PM) — strategic notes
- **Apple ASAF (WWDC 2025)** narrows the spatial-format moat → our defensible edge is the **content-adaptive + personalized + system-responsive** combination Apple doesn't do (their spatial is static post-decode). Lead messaging there.
- **Conservative adaptation cadence** (min inter-update interval / max dB-per-second / no fighting intentional musical contrast) + a **Phase-0 KPI: users must NOT perceive the EQ "moving."**
- Market SOTA references: Sonarworks Virtual Monitoring PRO (in-situ BRIR), dSONIQ Realphones, Audeze Reveal+ (all ship room sim, not dry HRTF).

---

## Open judgment calls for the founder
1. **Accept the dB-curve demotion + ERB/Bark masking model?** (Bigger build, but LD-10 "quality-first, ample resources" supports it; it's where real clarity gains live.)
2. **"Vocals buried":** ship the presence/clarity *macro* approximation now, or invest earlier in **offline source separation** for true unmasking?
3. **NL Phase-1 default:** name the two-tier architecture (deterministic rule lookup + off-RT CLAP/small-LLM macro) now, or keep the mechanism deferred (OQ-11) while adopting the typed-macro *interface*?
4. **BRIR-first spatial:** confirm Phase-1 spatial ships BRIR (bundled/synthesized) rather than dry HRTF.

> Net: backbone is SOTA-aligned — ship it. Flip phase-default to min-phase, make BRIR the spatial default, do clarity/masking decisions in ERB/Bark with typed (not curve-only) contributors, and rebuild NL as a learnable typed-macro. Those four moves take it from "good engineering on a partly-mismatched model" to "SOTA-grounded."
