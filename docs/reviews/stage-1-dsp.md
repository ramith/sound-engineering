# Codebase review — Stage 1: DSP + algorithm correctness

**Scope:** `Sources/AudioDSP` (EQ, Limiting, Loudness, Spatial, Clarity kernels; the `DSPKernel`
orchestrator; the RT-safety primitives; the AU/HAL transport layers).
**Theme:** architectural elegance · reuse · best practices · algorithm correctness.
**Method:** two independent DSP SMEs (algorithm-correctness lens + architecture/reuse lens),
red-teamed by *the-fool*, then reconciled here. Correctness claims are numerically verified in
scratchpad (`checks.py`, `checks2.py`) against ITU-R BS.1770-4, EBU R128 / Tech 3341, the RBJ
Audio-EQ-Cookbook, and the libbs2b/FFmpeg `af_bs2b` sources.

---

## Verdict

The **RT-safety core and the standardized DSP math are excellent** — measurably correct and, in the
concurrency primitives, genuinely exemplary. The findings cluster in two places:

1. **One real correctness gap that degrades the headline feature** — the EQ fitter does not
   reproduce the requested curve for broadband shapes (AC-1), and the test that should have caught
   it is too weak.
2. **A consistent reuse pattern**: the *primitives* were extracted well, but the *idioms built on
   top of them* (gain ramping, settled-checks, flush-to-zero, atomic handoff) were re-implemented
   per module instead of shared.

Nothing here is a crash or an RT-safety violation on the audio path. This is a mature module.

### Genuinely excellent (do not refactor)
- `DoubleBufferSnapshot<T>` — wait-free 3-slot SPSC with a correct permutation-invariant proof; the
  `acq_rel`-on-**both**-exchanges reasoning correctly closes the write-after-read-on-reuse edge that
  release/acquire-only would miss. *The-fool challenged the "we rewrote it for TSan" motive and
  conceded: keeping the most safety-critical primitive inside the sanitizer's provable envelope is
  sound, and the result is simpler than the seqlock it replaced.*
- `RtSwappableResource<T>`, the copy-once RT snapshot (`DSPKernel.mm:141-144`, RACE-1),
  `MultichannelView` (single ABL-decode point), and a clean Obj-C-free DSP core / DSP-free OS-glue
  boundary.
- K-weighting to **≤9e-16** of the BS.1770-4 reference; RBJ biquad coefficients byte-for-byte;
  Schur-Cohn stability + minimum-phase test correct; true-peak **8× polyphase** oversampling
  (exceeds the ≥4× guidance); EBU gating (400 ms / 75 %, −70 LUFS abs, −10 LU rel) correct; the
  MPEG 5.1/7.1 LFE-vs-surround channel-index ordering trap correctly handled.

---

## Findings (ranked)

| # | Sev | Area | Finding | Fix effort |
|---|-----|------|---------|-----------|
| 1 | **HIGH** | correctness | EQ greedy fitter mis-represents broadband/plateau curves (up to ~5.8 dB error); bell placed at run **edge** not center; single-band bleed ±2 bands. Accuracy test too weak to catch it. | S→M |
| 2 | **HIGH** | correctness | Limiter lookahead is a fixed **frame count**, so the −1 dBTP ceiling is exceeded at 96/192 kHz (up to +1.3 dB over). Breaks the Sprint-4 loudness-safety guarantee on hi-res. | S |
| 3 | MED | correctness | Crossfeed **Default ("Bauer")** preset α = 0.355 (−9 dB) instead of the bs2b Default −4.5 dB (α = 0.596) → default is ~2× intended depth, nearly identical to "Relaxed". | XS |
| 4 | MED | design-debt | `RtSwappableResource` leak-freedom is guaranteed by an **external** invariant (Realizer coalescing), not locally. Header flags "revisit for BRIR (large kernels)" — BRIR is a stub **today**, so fix the encapsulation before it gets a body. | M |
| 5 | MED | reuse | Flush-to-zero (`FPCR.FZ`) inline-asm copy-pasted in **5 files under 2 names**, one copy encoding the constant differently (`24U` vs `1ULL<<24U`). Safety-critical; must stay identical. | XS |
| 6 | MED | reuse | Three separate hand-rolled atomic handoff protocols; LoudnessModule's channel-layout handoff is a bespoke **2-slot** buffer — the design the tree already rejected for `DoubleBufferSnapshot`. | M |
| 7 | MED | reuse/orch | `DSPKernel` writes the coloration chain (`eq→clarity→brir→crossfeed`) and safety chain (`loudness→limiter`) **twice** (settled-at-1 branch vs crossfade branch). | S |
| 8 | MED | reuse | Ramped-gain application (ramp→scratch→`vDSP_vmul` fan-out) re-implemented in EQ, Loudness, Limiter; settled-check + endpoint-snap open-coded at 4 sites with **3 different epsilons** (1e-6/1e-4/1e-5). | S→M |
| 9 | LOW | correctness | Equal-**power** crossfade on a correlated dry/wet blend → up to +3 dB midpoint bump at fixed intermediate intensity (mitigated by decorrelating wet chain + downstream loudness normalize). | S |
| 10 | LOW | correctness | Fitter silently drops sign-runs beyond the 10-biquad cap (no clamp/warn). | XS |
| 11 | LOW | hygiene | 32 ms ramp τ magic number declared 3×; no `DspModule` concept to enforce the uniform `initialize`/`process` shape; in-place vs non-in-place kernel contracts diverge (`DSPKernel` vs `SpatialRenderKernel`) with the invariant only in prose. | S |
| 12 | NIT | correctness/docs | Nyquist-Q comment misdiagnosed (near-Nyquist bells **narrow**, not widen); crossfeed strength labels inverted vs bs2b; "bs2b sets" is really bs2b-*inspired*; `ParameterRamp` coeff is matched-Z, not "bilinear". | XS |

---

## The headline: EQ fitter (finding 1) + the test that missed it

The fitter places **one** peaking bell per maximal same-sign run, at the run's extremum-by-magnitude,
Q from `1/(0.5 + 0.1·|gainDb|)`. Measured — a flat **+6 dB across 20–50 Hz**:

| f (Hz) | 20 | 25 | 31.5 | 40 | 50 |
|---|---|---|---|---|---|
| requested | +6.0 | +6.0 | +6.0 | +6.0 | +6.0 |
| realized | +6.0 | +5.1 | +3.5 | +2.1 | **+1.3** |

Two compounding causes:
- **Broadband → single bell.** A ~1.5-octave bell cannot cover a 3-octave plateau. Device-correction
  and perceptual target curves are exactly this shape — not a pathological input.
- **Bell at the run edge.** Tie-break at `EQModuleCoefficients.h:179` seeds `extremeGain` from the
  first band and updates only on strict `>`, so an equal-gain run keeps the extremum at the **first**
  band (20 Hz above, when the run center is ~31.5 Hz), maximizing the asymmetric error.

**Why it slipped review:** the golden master is an **FNV byte-hash** (`TestSupport.h:238-246`) — a fine
*change-detector tripwire*, but not a correctness oracle. The correctness oracle is
`EQ_FrequencyResponseAccuracy` with `kEqFrToleranceDb = 1.0F` measured **at a single band's exact
center** (`TestSupport.h:418-422`) — where AC-1 confirms the gain is exact to ≤0.001 dB. So the test
validates the one case the fitter gets right and is blind to the plateau error. *This is the-fool's
"is the test protecting users or protecting a test?" — reframed: the byte-hash tripwire is fine; the
accuracy test is the thing that's too thin.*

**Fix ladder (cheapest first):**
1. **XS:** place the per-run bell at the run's geometric center / magnitude-weighted centroid, not the
   first extremum. (Removes the edge-placement half of the error immediately.)
2. **S:** allow multiple bells per run (there's headroom — 10 biquads, smooth curves use 1–2); make Q
   band-count-aware so single-band requests stop bleeding ±2 bands.
3. **M / aligned with "quality-first, resources-abundant":** the textbook realization of a 31-band
   graphic EQ is **one 2nd-order peaking biquad per band** (cheap on `vDSP_biquad`) or an
   ERB-weighted least-squares / L-M cascade fit (already flagged "future" in the comment). *The
   10-biquad cap is the thing fighting the project's own stated principle.*
4. **Either way:** strengthen `EQ_FrequencyResponseAccuracy` to sweep a **broadband** target and assert
   the whole curve, not one center bin.

---

## Cross-cutting theme (the "reuse" half of the brief)

The RT primitives were extracted well (`RtSwappableResource` literally documents being *"extracted
from EQModule's open-coded triple-atomic swap"*). But the **idioms layered on top of them were not**:

- **Gain ramping** → 3 re-implementations (finding 8)
- **Settled-check + snap** → 4 sites, 3 epsilons (finding 8)
- **Flush-to-zero** → 5 copies, divergent constant (finding 5)
- **Atomic SPSC handoff** → 3 parallel protocols (finding 6)
- **τ = 32 ms** → 3 declarations (finding 11)

None is a bug today; together they are the maintenance-surface and drift risk that the theme is about.
The clean move is a thin second layer of shared helpers over the (already good) primitives:
`FlushToZero.h`, a `RampedGainStage`, `ParameterRamp::settled(eps)`, folding the Loudness buffer onto
`DoubleBufferSnapshot`, and extracting `runColorationChain`/`runSafetyChain` (or a whole
`IntensityBlender`) from `DSPKernel`. Every one is **golden-master-neutral pure code motion**.

---

## Recommended action order
1. **Finding 2** (limiter lookahead → time-based) — smallest fix, restores a shipped safety guarantee.
2. **Finding 3** (crossfeed Default α) — one-line, corrects the default user experience.
3. **Finding 1 step 1** (bell centering) — one-line, removes half the EQ error; then decide on the
   fuller fitter rework (steps 2–4) as its own scoped task.
4. **Finding 4** (RtSwappable encapsulation) — do before BRIR is implemented.
5. Reuse cluster (5–8, 11) — batch as a "DSP idiom consolidation" pass; all code-motion.

---

## Fix pass — outcomes (post-review)

Gate: **C++ null-test suite 120/120 pass**, `GoldenMaster_StereoN2_v1` hash **unchanged**
(`0xe7267654ba01d315`), `swift build` clean, clang-format clean.

**Fixed:**
- **F2 (limiter, HIGH)** — look-ahead is now a fixed 3 ms converted per sample rate in
  `initialize()` (`lookaheadFrames_ = round(kLimiterLookaheadSeconds·fs)`); the peak-deque is
  sized to the 192 kHz ceiling. Bit-identical at 48 kHz (golden master intact); the −1 dBTP
  ceiling now holds at 96/192 kHz. One transparency test hard-coded the 144-frame delay — updated
  to the actual per-rate look-ahead (a delay-constant correction, not a tolerance loosen).
- **F5 (flush-to-zero, MED reuse)** — 5 copies under 2 names (one with a divergent constant)
  collapsed to a single `include/FlushToZero.h`; 4 call sites + 1 definition.
- **F7 (MED orchestration)** — extracted `DSPKernel::runColorationChain` / `runSafetyChain`; the
  settled-at-1 and crossfade branches now share one chain-order definition.
- **F9 / F12 (LOW/NIT docs)** — documented the equal-power crossfade law choice (AC-5); corrected
  the misdiagnosed Nyquist-Q comment, the matched-Z (not bilinear) `ParameterRamp` attribution, and
  the "bs2b sets" → bs2b-inspired crossfeed comment.

**Reverted after review (the fix was worse than the finding):**
- **F1a (EQ bell centering)** — the magnitude-weighted-centroid change fixed flat plateaus but
  **broke the ratified S6 `[-12,-9,-12]` cut-run regression** (moved the deep-cut bell off its band)
  and only cleanly helped one case. Loosening a ratified regression to bless it would be
  confirmation bias. Reverted; the limitation is now documented in-code, and AC-1's real fix
  (one-biquad-per-band or an ERB-weighted L-M cascade fit) is deferred to a scoped rework.

**Rejected (SME recommendation overridden):**
- **F3 (crossfeed Default α)** — the correctness SME suggested α 0.355 → 0.596, but the three
  coded α's form a deliberate monotonic depth ladder (0.335 < 0.355 < 0.501); 0.596 would exceed
  "Strong" and invert the ladder. Left the value; corrected the false "bs2b coefficients" comment
  and flagged the (real) "Default barely differs from Relaxed" UX question for the founder.

**Deferred (correctly, not now):**
- **RtSwappableResource encapsulation (fool #2)** — fix as the first step of the BRIR work (BRIR is
  a stub today; the header itself flags "revisit for BRIR").
- **AC-1 full EQ fitter rework**; the reuse-consolidation cluster (gain-ramp `RampedGainStage`,
  `ParameterRamp::settled()`, τ-constant hoist, folding Loudness's bespoke buffer onto
  `DoubleBufferSnapshot`, a `DspModule` concept).

> Recommended before merge (heavier gates, not run this pass): `make sanitize` (ASan/UBSan) and
> `make tsan` on the AudioDSP changes.

## Not reviewable this stage
`BRIRModule`, the binaural `out<in` path in `SpatialRenderKernel`, and `ClarityModule` are **explicit
S4 stubs** (empty/passthrough) — no convolution/HRIR/clarity math exists yet. Re-review when
implemented (finding 4 gates the BRIR work).
