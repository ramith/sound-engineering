# SPRINT 4: Loudness Safety & Transparent Dynamics

> **✅ SHIPPED — historical record (Sprint 4, shipped & merged).** This is the as-built/as-planned record, retained for provenance and design detail. The authoritative forward sprint schedule is now [sprint-plan.md](sprint-plan.md).

**Theme:** Establish the safety floor — true-peak limiter + LUFS normalization  
**Effort:** 5–10 story points  
**Owner:** Audio DSP Agent + C++ implementation  
**Prerequisite:** Phase 1b Part B (progress, seek, auto-play, test suite)

---

## Vision

**Loudness is the foundation.** Before EQ, before clarity, before spatial processing — all downstream DSP must run inside a protective true-peak limiter that enforces hearing-safe loudness levels. This sprint establishes that floor and proves transparent measurement via LUFS normalization.

**Why Industry-Best:**
- True-peak limiting is non-negotiable (hearing safety, DAC headroom, platform spec)
- LUFS normalization is transparent (no artifacts, no "program dynamics," no listening-level variation)
- Fractional loudness compensation (Sprint 6) will layer on top; this sprint establishes the safe floor it builds on

---

## Core Deliverable

### 1. True-Peak Limiter (≥4× Oversampling)

**Specification:**
- **Ceiling:** −1 dBTP (true peak, with safety margin for floating-point precision)
- **Lookahead:** ~1 ms (prevents transient clipping)
- **Oversampling Factor:** ≥4× (minimum requirement; 8× preferred if CPU permits)
- **Oversampling Method:** FIR-based polyphase (industry standard; linear-interp fallback if CPU overruns)
- **Release Time:** ~100 ms (transparent, doesn't alter program dynamics)
- **Detection:** Full-wave rectified + envelope follower (not RMS)

**Placement:** Final stage before master gain (after all DSP modules)

**Signal Flow:**
```
[Clarity] → [Loudness] → [BRIR] → [Limiter] → [Master Gain] → Device Output
```

> **Implementation reconciliation (Sprint 4 M6).** The chain *actually built and
> verified* in `DSPKernel.mm` (`process()`, in order) is:
> `EQ → Clarity → BRIR → Loudness → Limiter`. Two differences from the diagram above:
> 1. **EQ leads the chain** — it is omitted from this limiter-section diagram but is the
>    first module (the diagram was scoped to the limiter's neighbours, not the full graph).
> 2. **BRIR precedes Loudness** (diagram shows the reverse). This is the intended order:
>    loudness measurement / makeup should observe the *post-spatialization* program so the
>    metered LUFS matches what reaches the limiter and the DAC. The diagram's
>    `Loudness → BRIR` ordering is a spec-doc artifact, not the implemented behaviour.
>
> **True-peak ceiling margin (as implemented).** The −1 dBTP ceiling is enforced with an
> additional **−0.27 dB inter-sample safety margin** (`kIspSafetyMargin ≈ 0.9694`, the
> tightest reliably-achievable headroom at the shipped 8×/24-tap polyphase detector — the
> spec's aspirational −0.1 dB is unreachable at this oversampling/tap count without false
> overs). The detector is sidechain-only; the audio path stays at base rate. See the M3
> survey in the plan doc for the derivation.

> **Live-path caveat (Sprint 4).** The DSP kernel above is **not yet attached to the
> `AVAudioEngine` playback graph** — playback is `AVAudioPlayerNode → mainMixerNode`, and the
> loudness meters are fed by a Swift tap on the mixer (sample-peak + LUFS, not true-peak/GR).
> The limiter, makeup gain, and EQ are fully built and unit-verified but do **not** process
> live audio until the AU is wired into the graph (a future AU-integration task, out of
> Sprint 4 scope). The 1-hour live-soak / founder A-B items below therefore exercise playback,
> not the RT DSP; the DSP's soak coverage is the synthetic `Limiter_HotNoiseSoak` harness test.

**RT Implementation Notes:**
- Pre-allocate oversampling buffer at init (sized for max buffer length)
- No allocations on audio thread
- Lock-free atomic parameter updates (threshold, lookahead time)
- Bypass mode: direct copy (no overhead when ceiling not engaged)

### 2. LUFS Normalization Module

**Specification:**
- **Standard:** ITU-R BS.1770-5 (same as Spotify, Apple Music, Netflix, broadcast)
- **Measurement Points:** Integrated LUFS, short-term LUFS (3 sec), true-peak, gated loudness
- **Accuracy Requirement:** ±0.1 LUFS (industry standard tolerance)
- **Update Rate:** Off-RT metering (not on audio thread); atomic snapshot every 100 ms to UI

**Control-Plane Mechanism:**
- Measure output level (LUFS) asynchronously
- Compute makeup gain: target LUFS (e.g., −14 LUFS) − measured LUFS
- Apply makeup gain to all channels equally
- No listening-level artifacts (makeup is transparent, not dynamic)

**Off-RT Implementation Notes:**
- FFT analysis on background thread every buffer (or every N buffers if CPU tight)
- Use libebur128 algorithm (open-source reference) for coefficient values
- Atomic snapshot to UI: loudness + GR + true-peak (all read-only on RT thread)

### 3. Loudness Metering UI

**Display Elements:**
- **Integrated LUFS:** Current loudness level (e.g., "−16.2 LUFS")
- **Short-Term LUFS:** Last 3 seconds (responsive to dynamics)
- **True-Peak Indicator:** Visual peak level (needle or bar)
- **Gain Reduction Meter:** How much limiter is engaging (dB)
- **Gated Loudness:** Loudness without silence (useful for podcast/voiceover)

**Update Cadence:** 50–100 ms (responsive but not twitchy)

**Interaction Model:**
- Read-only display (user doesn't adjust; app normalizes transparently)
- Optional toggle to show/hide metering (not essential UI, don't clutter)

### 4. Hearing-Safety Numeric Clamps

**Specification:**
- Prevent cumulative EQ boost from exceeding safety threshold (e.g., +12 dB)
- Proportional scaling: if user intent is +20 dB across all bands, scale down all bands proportionally to hit +12 dB
- Preserve user intent (direction, shape) while clipping magnitude
- Confidence-gated: if Claude confidence < 50%, clamp stricter (e.g., ≤±3 dB per-band)

**Placement:** In Arbiter (control plane), before RT parameter publishing

**Example:**
```
User NL: "Boost everything"
  → Claude suggests: {+5 at 80Hz, +5 at 200Hz, ..., +5 at 20kHz} = +25 dB cumulative
  → Clamps scale to: {+2.4 at 80Hz, +2.4 at 200Hz, ..., +2.4 at 20kHz} = +12 dB cumulative
  → Preserves user intent (all bands boosted equally), magnitude clipped
```

**Implementation:** Arbiter sums all EQ band gains → if > threshold, multiply all by (threshold / sum)

---

## Validation Plan

### Unit Tests (Automated)

**Test Suite:** `AudioDSPTests/LimiterTests.swift` + `AudioDSPTests/LoudnessTests.swift`

#### Limiter Tests
1. **Null-test (bypass):** Input without limiting (ceiling not engaged) = output bit-identical
   - Test input: white noise at −6 dBFS (well below threshold)
   - Assert: output MD5 match or ≤ −120 dB THD+N
   
2. **Ceiling enforcement:** Peak input > −1 dBTP → output ≤ −1 dBTP
   - Test input: synthetic peak tone +10 dBFS
   - Assert: output true-peak ≤ −0.99 dBTP (−1 dBTP ± 0.01 dB rounding)
   
3. **Oversampling factor verification:** Measure true-peak before/after downsampling
   - Test: 4× oversampling should catch peaks that naive peak detection misses
   - Assert: without OS, naive peak > −1 dBTP; with 4× OS, output ≤ −1 dBTP
   
4. **GR response time:** Inject sudden +6 dB loudness spike → measure GR onset
   - Assert: GR ramps in < 2 ms (imperceptible, < 96 samples @ 48 kHz)
   
5. **Release linearity:** GR decays after spike removed
   - Assert: release time ≈ 100 ms ± 10% (verifiable by measuring GR amplitude over time)
   
6. **Parameter automation:** Threshold change applies smoothly
   - Test: sweep threshold from −20 dBFS to 0 dBFS
   - Assert: no zipper noise, smooth GR ramp (≥50 ms)

#### Loudness Tests
1. **LUFS measurement accuracy:** Feed reference files → measure LUFS
   - Reference: ffmpeg ebur128 or certified Nuendo measurement
   - Test files: 5 calibrated test tones at −23, −18, −14, −10, −6 LUFS (from ITU)
   - Assert: measured ±0.1 LUFS of ground truth
   
2. **True-peak accuracy:** Synthetic peak test
   - Test: −1 dBTP reference file (known peak)
   - Assert: measured true-peak ≤ −0.99 dBTP
   
3. **Makeup gain correctness:** Measure → compute makeup → apply → re-measure
   - Test: feed −10 LUFS file, target −14 LUFS
   - Step 1: measure input → expect ≈ −10 LUFS
   - Step 2: compute makeup = −14 − (−10) = −4 dB
   - Step 3: apply makeup gain
   - Step 4: re-measure → expect ≈ −14 LUFS ± 0.1 LUFS
   - Assert: all steps pass
   
4. **Gated loudness:** Measure with + without silence
   - Test: music + 10 seconds silence
   - Assert: gated loudness > ungated loudness (silence lowers average)
   - Assert: difference matches expected gate algorithm

#### Clamp Tests
1. **Proportional scaling:** Apply clamp to EQ gains
   - Test: {+20, +20, +20, +20, +20} → clamp to +12 cumulative
   - Step 1: sum = +20 × 5 = +100 dB (exaggerated for test)
   - Step 2: scale factor = +12 / +100 = 0.12
   - Step 3: result = {+2.4, +2.4, +2.4, +2.4, +2.4} = +12 dB cumulative
   - Assert: output matches scaled expectation
   
2. **Direction preservation:** Clamp mixed ±dB gains
   - Test: {+8, −3, +5, −1, +2} → sum +11 dB, no clamp needed
   - Assert: output unchanged
   - Test: {+20, −3, +5, −1, +2} → sum +23 dB, clamp to +12
   - Assert: proportional scale maintains direction (boosts stay up, cuts stay down)

### Integration Tests (Manual + Scripted)

**Test Suite:** Play real music files; validate perceptual behavior

#### Soak Test (1 hour)
- **Setup:** Continuous playback of diverse 20-track playlist
- **Config:** Vary playback loudness (−20, −16, −12, −6 LUFS target)
- **Metrics:**
  - XRun count (assert: 0)
  - Metering stability (LUFS variance < 0.5 LU over 5-min window)
  - Memory growth (assert: stable, no leak)
  - CPU usage (assert: < 10% headroom)
- **Result:** Pass/Fail, logged to file

#### Limiter Perceptual Test
- **Setup:** Play 5 reference tracks (vocal, acoustic, electronic, classical, orchestral)
- **Procedure:**
  1. Play at −6 LUFS (safe zone, limiter off)
  2. Play at −10 LUFS (medium; limiter may engage slightly)
  3. Play at −14 LUFS (hot master; limiter may engage noticeably)
  4. Listen for: pumping, swelling, breathing, artifacts
- **Pass Criteria:** No audible artifacts; transparent dynamics (you don't perceive the limiter)

#### Makeup Gain Transparency
- **Setup:** Play same track at 3 different playback levels with + without makeup gain
- **Procedure:**
  1. Play at 85 dBSPL (calibrated SPL meter)
  2. Play at 75 dBSPL without makeup → should sound quiet
  3. Play at 75 dBSPL with makeup → should sound similar to 85 dBSPL
- **Pass Criteria:** With makeup, perceived loudness at 75 dBSPL ≈ 85 dBSPL

#### Peak Protection Validation
- **Setup:** Synthesize a hot master with intentional peaks
- **Procedure:**
  1. Generate test tone: pink noise at −10 dBFS + brief +10 dBFS clicks
  2. Run through limiter
  3. Measure output true-peak
  4. Verify no clipping, clicks are transparent
- **Pass Criteria:** Output true-peak ≤ −1 dBTP, clicks inaudible

### Listening Panel (5–10 Audio Engineers)

**Protocol:** MUSHRA-style blind A/B on 5 reference tracks (30 sec each)

1. **Reference anchor:** Original (unprocessed)
2. **Hidden candidates:**
   - Candidate A: Original (unprocessed) — anchor
   - Candidate B: Through limiter + makeup gain
3. **Questions:**
   - Do the two sound identical? (Yes/No)
   - If different, which sounds more natural? (A / B)
   - Rate any artifacts: none / subtle / obvious
   - Rate overall transparency: "Inaudible" / "Subtle" / "Obvious"

**Pass Criteria:**
- ≥ 80% of panelists rate Candidate B as "Inaudible" or "Subtle"
- ≥ 80% perceive no audible artifacts
- No panelist reports swelling, pumping, breathing

---

## Open Questions & Design Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| **Oversampling method: FIR polyphase vs. linear-interp?** | FIR polyphase (industry standard); fallback to linear-interp if CPU > 3% | Better alias rejection, cleaner peaks |
| **Update rate for metering (LUFS off-RT)?** | Every 100 ms (10 Hz UI update) | Responsive to dynamics, not CPU-intensive |
| **Makeup gain: per-channel or mix-level?** | Mix-level (all channels equally) | Stereo image not affected |
| **Clamp strictness: ±12 dB or softer?** | ±12 dB (professional standard); tighter for low-confidence macros | Balance between user intent and safety |
| **Limiter color: transparent or subtle musicality?** | Transparent (zero artifacts); Phase 1.5 can add optional character modes | MVP is fidelity-first |

---

## Acceptance Criteria (Done-Done)

- [ ] Limiter vDSP code compiles, passes unit tests (6/6 limiter tests)
- [ ] LUFS measurement accuracy ±0.1 LUFS verified vs. ffmpeg ebur128 (4/4 loudness tests)
- [ ] Hearing-safety clamps functional (2/2 clamp tests)
- [ ] Null-test: bypass = bit-identical (−120 dB THD+N)
- [ ] Soak test: 1 hour, zero XRuns, metering stable
- [ ] Limiter perceptual test: no audible artifacts on 5 reference tracks
- [ ] Makeup gain transparency: blind test imperceptible
- [ ] Peak protection: output ≤ −1 dBTP on synthetic hot master
- [ ] Listening panel: ≥80% "Inaudible" / "Subtle" rating, no artifact complaints
- [ ] Code review: ASAN/TSan clean, no data races or leaks
- [ ] Documentation: README updated with limiter + loudness specs

---

## Dependencies & Blockers

**Unblocked By:**
- ✅ Phase 1b Part B (progress, seek, auto-play, test suite)
- ✅ Limiter scaffold code (exists from Phase 1a)

**Blocks:**
- 🟡 Sprint 5 (EQ wiring assumes limiter is RT-safe)
- 🟡 Sprint 6 (loudness compensation builds on LUFS measurement)

---

## Success Story (What "Done" Looks Like)

> **User launches Adaptive Sound, plays a hot master at 85 dBSPL.**
>
> Limiter is transparent — no swelling, no pumping, no breathing. LUFS meter shows −14 LUFS. Gain reduction taps out at 2 dB during the peak (barely noticeable). Sound is clear, natural, hearing-safe.
>
> **User drops down to 75 dBSPL (quiet room).**
>
> Makeup gain engages transparently. Perceived loudness ≈ 85 dBSPL. No clicking, no digital artifacts. Dynamics feel intact.
>
> **Listening panel of 8 mastering engineers rates both scenarios.** All agree: "Limiter is inaudible. The processing is so transparent I'd trust it on commercial masters."

---

**Status:** Ready for implementation  
**Next:** Begin Sprint 4 coding after Phase 1b Part B ships
