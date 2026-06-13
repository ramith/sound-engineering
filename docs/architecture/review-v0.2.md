# Architecture v0.2 — Expert Panel Review (synthesis)

**Date:** 2026-06-13 · **Reviewers:** Real-time systems/perf · ML/source-separation · Mastering/audio-engineer · Security/privacy (all literature-grounded, web-cited).
**Input:** [architecture.md](architecture.md) v0.2. **Net verdict: feasible / endorse-with-changes — no showstoppers, but several must-fix items, two of them factual/blocking.**

## Verdicts
- **RT/perf:** Feasible-with-changes; one internal contradiction (§15 pressure-response is backwards). The chief risk is real and hinges on **one unmeasured number** (BRIR length × stem count).
- **ML:** Directionally sound; **one factual blocker** (Demucs weights license) + two over-confident claims (masking cost, Core ML/MLX interchangeability).
- **Mastering:** Fidelity skeleton is sound; the failure mode is the **re-sum bus** and **spatial spreading** of separated stems — endpoints are well-defended, the *middle of the Reimagine knob* is not.
- **Security:** Minor blockers; the **global tap is a high-consent, captures-everything capability** (not a transparent reroute), and LLM output must be treated as untrusted.

---

## Critical / convergent must-fixes

**C1 — 🔴 Demucs 6-stem *weights* are not cleanly redistributable (factual fix).** Code is MIT, but `htdemucs_6s` weights are trained on **MUSDB18-HQ** (educational/NC-tainted; MedleyDB CC-BY-NC-SA). "MIT incl. weights" in §12/prior-art is **false**. Fix: **download-on-first-run** from upstream (shifts the fetch to the user) and/or prefer cleaner-provenance options (e.g., **Mel-Band-RoFormer, MIT, for vocals**); accept there is **no clean MIT 6-stem (guitar/piano)** model. Gate any commercial path on this. *(ML reviewer; MUSDB18 license.)*

**C2 — 🔴 Don't run 6 independent full BRIRs — share the reverb tail.** A full BRIR is ~15–20k+ taps; six of them × 2 ears is the budget-buster (and the cost spread vs. a 256–512-tap dry HRIR is ~30–60×). **Decompose:** per-stem short HRIR/early-reflection filter (placement) + **one shared late-reverb** (FDN or single convolution) fed by per-stem sends. This is standard auralization, is the difference between feasible and not on a base Apple-Silicon laptop, **and sounds more coherent** (one room). *(RT reviewer; mastering reviewer concurs.)*

**C3 — 🔴 The re-sum bus is unmanaged — make it a real mixbus.** Six independently EQ'd/dynamics'd/BRIR'd stems do **not** re-sum to unity gain/phase. Without discipline: tonal centroid climbs (correlated low-mids), the safety limiter starts doing de-facto DRC (defeating "no program DRC"), and the center image combs. **Fix:** per-stem makeup ≤ GR removed; **loudness-matched per-stem trim** so the sum ≈ the intensity-0 reference; explicit headroom budget (~−6…−3 dBFS pre-limiter); **meter + surface limiter GR**. *(Mastering reviewer — the single biggest hole.)*

**C4 — 🔴 Spatial exemptions: bass and lead vocal must not be spread.** **Bass:** high-pass (~120 Hz) out of the BRIR path and sum **mono-center** — a BRIR on bass is wrong physics (comb filtering, not localization). **Lead vocal:** keep centered (allow depth/early-reflections, not L/R spread) — it's the most artifact-sensitive, phantom-center-critical element. Hard clamps in the Arbiter at all intensities. *(Mastering reviewer.)*

**C5 — 🟠 §15 pressure-response is backwards (RT contradiction).** Audio Workgroups don't add cores or guarantee P-core scheduling — and **≥512-frame buffers demote threads to E-cores**. So "grow partition size under pressure" makes the deadline *harder*. **Fix:** under thermal/battery pressure, **reduce stem count + reverb-tail length**, keep buffers small (≤256 frames) for P-core residency. *(RT reviewer; Apple Forums 726096.)*

**C6 — 🟠 Gate stems on a *perceptual artifact* estimate, not SDR.** SDR ~9 dB doesn't predict perceived artifacts, and **spatial spreading amplifies separation artifacts** (spatial release from masking exposes bleed/"musical noise"). Guitar/piano are author-flagged "not working great" with **no public quality metric**. Gate on energy/inter-stem-correlation/transient-smear proxies; **clamp Reimagine intensity per track** by confidence; 6s→4s→mix fallback. *(ML + mastering reviewers.)*

**C7 — 🟠 Memory is the likely *first* failure on 8 GB.** Demucs needs ~3–6 GB (+swap); plus 6 cached stems (~120–160 MB/track FLAC, ~6× the source) + BRIR kernels. **Fix:** never run separation concurrent with playback on 8 GB; memory-map streamed stems; **capped LRU stem cache**; make the **8 GB base model a distinct QualityProfile tier with a lower stem cap (likely 4 stems)**. "Ample RAM" (LD-10) is false on the base Air. *(RT + ML reviewers.)*

**C8 — 🟠 Re-scope the masking model.** Full Moore-Glasberg time-varying partial loudness is **~50× slower than real time per channel** and has **no shippable OSS implementation**. **Fix:** use the cheaper **excitation-pattern / masked-threshold (ERB) subset** on coarse frames over cached pre-analysis — enough to decide between-stem unmasking. Resolves the "Moore-Glasberg vs MPEG" OQ toward the affordable subset. *(ML reviewer.)*

**C9 — 🟠 Reframe the global tap as a high-consent capability + harden the LLM path (security).** The muted global tap triggers a **TCC prompt + purple recording indicator** and **captures every app's audio (incl. calls)** — same class as screen recording, *not* a transparent reroute. Add explicit consent UX, **auto-exclude/skip comms apps**, and a hard rule that **tapped audio never persists**. Separately: treat **LLM output as untrusted** — constrained decoding + schema validation + **numeric clamping** (bounds prompt-injection *and* enforces hearing-safety limits); cloud `context` uses a **field allowlist** that also excludes track identity/listening history. *(Security reviewer.)*

## Secondary refinements (P1)
- **NL: lean on-device.** Evidence now: CLAP-optimization (Text2FX) ≈ random for EQ (0.55 vs 0.53); a small on-device LLM + SAFE/SocialEQ few-shot beats it (Mistral-7B 0.18). Make **on-device LLM + priors the primary** deferred mechanism; CLAP a retrieval/reranker; rules the floor; cloud opt-in. Monotonicity/schema **validation harness is mandatory**. *(ML.)*
- **Demote ADR-004 (RT ML) to "reserved/contingent."** Everything ML is off-RT by construction; no RT ML is actually needed. Keep BNNS Graph as a documented escape hatch only. *(ML.)*
- **Loudness-match the Reimagine knob** (else A/B is level-biased → users pick high intensity for the wrong reason); **default intensity low-to-lower-mid**; **defer stem-render onset** above 0 to avoid the bit-perfect→imperfect-phase discontinuity and a non-monotonic "valley" mid-knob. *(Mastering.)*
- **Content-adaptive room amount** keyed on the source's *existing* reverberation (dry → more room, already-wet → less) to avoid reverb-on-reverb wash that *reduces* clarity. *(Mastering.)*
- **Loudness-comp defaults to 0 when SPL calibration is missing/stale** — never assume a reference SPL. *(Mastering.)*
- **MLX is the primary separation runtime; Core ML secondary** (STFT/complex won't convert cleanly; transformer won't reliably hit ANE — don't claim ANE). *(ML.)*
- **IR hot-swap** needs double-buffered convolvers + crossfade (hide transitions under the Reimagine crossfade). *(RT.)*
- **Hearing data at rest:** anchor on FileVault + Keychain/Data-Protection + **crypto-shred**; reconsider blanket backup-exclusion (data-loss footgun) — guarantee "never leaves device / never cloud-synced" instead. *(Security.)*
- **Verify in SDK headers** (not docs): exact tap Info.plist key (`NSAudioCaptureUsageDescription`?) + min-OS (14.2 vs 14.4). *(Security; prior-art already flagged.)*
- **Stems-only-from-local-files** as an enforced **code invariant** (never from taps/DRM) — ToS/derivative-copy safety. *(Security.)*

## Spike scopes sharpened
- **SPIKE-PERF-BUDGET (gates Phase 1.5):** BRIR-length-vs-cost curve; **independent vs shared-tail** head-to-head; p99.9 render time as % of deadline at 1–6 stems; P-core residency telemetry; workgroup speedup knee; memory high-water (Demucs + 6 stems on 8 GB); **thermally-soaked** (not cold) sustained budget. Likely outcome: **cap base-hardware own-player to 4 stems**. *(RT.)*
- **SPIKE-SEP-QUALITY:** weights-license resolution (C1); measured guitar/piano quality on real content (no public SDR); the **artifact-based gate signal** + 6s→4s→mix thresholds + per-track Reimagine clamp; MLX vs Core ML path + base-chip sec/track + cache size.
- **SPIKE-MASKING-MODEL:** confirm excitation-pattern subset suffices; A/B masking-aware unmask vs naive level-match; robustness to separation artifacts (don't "unmask" leaked content).

## Encouraging cross-cut
The mastering fixes (fewer/closer-placed stems, bass out of the spatial path, less room on wet material) **also reduce compute** — the sound-quality and feasibility pressures point the same way. And every reviewer endorsed the **spine** (off-RT realizer, intensity-0 bit-faithful anchor, no-program-DRC, BRIR-over-dry-HRTF, typed-macro NL). The changes are about the *flesh*, not the skeleton.
