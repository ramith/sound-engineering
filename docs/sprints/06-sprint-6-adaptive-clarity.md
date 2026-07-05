# SPRINT 6: Adaptive Clarity & Loudness Compensation

> **⚠️ SUPERSEDED by [sprint-plan.md](sprint-plan.md) (2026-06-19).** This pre-pivot "Sprint 6" spec is retained for design detail only. Its scope is now re-sequenced under the new plan: **loudness compensation → S14 (Phase 1)**, **masking-aware adaptive clarity → S16 (Phase 2, spike S15)**. ⚠️ Note: "Sprint 6" in this document is NOT the new plan's **S6** (which is DSP-gate hardening) — the numbering schemes differ.

**Theme:** Intelligent, content-aware, conversationally-steerable DSP  
**Effort:** 5–10 story points  
**Owner:** Audio DSP Agent + SwiftUI Pro  
**Prerequisite:** Sprint 4 (limiter) + Sprint 5 (EQ wiring)

---

## Vision

**Adaptive DSP that understands your music and your ears.** This sprint implements masking-aware clarity (unmasks detail without sibilance), fractional loudness compensation (makes soft passages intelligible without aggressive dynamics), and conversational tuning (user says "make it brighter" → Claude suggests EQ → user accepts). All wired through the Arbiter control plane.

**Why Industry-Best:**
- Masking-aware clarity unmasks detail without artifacts (reference: FabFilter Pro-Q Dynamic EQ, iZotope RX)
- Fractional loudness compensation is transparent (reference: Apple Music Sound Check, Nuendo)
- Conversational tuning brings accessibility + power-user depth (two-tier UX, unique to Adaptive Sound)

---

## Core Deliverable

### 1. Clarity Module (Masking-Aware Spectral Enhancement)

**Specification:**
- **Input:** Per-buffer FFT (pre-DSP tap, already available)
- **Processing:** Masking threshold calculation (Moore-Glasberg roex, ERB-rate grid)
- **Output:** Per-band dynamic gain (≤ +3 dB per-band, < +2 dB cumulative for Phase 1)
- **Update Rate:** Every 50–100 ms (off-RT; coefficients published lock-free)

**Masking Model:**
- **Auditory Filter:** Roex(p) filter + excitation pattern
- **Grid:** ERB-rate (Bark-like, but improved fit for masking)
- **Threshold:** Absolute hearing threshold + masking from surrounding frequencies
- **Gain:** Conservative unmask (boost only truly masked bands; avoid sibilance boost)

**RT Implementation (Kernel):**
- Clarity gains pre-computed off-RT (not per-sample)
- Applied as per-band level adjustment (similar to EQ)
- Bypass at low intensity (Reimagine < 30%)
- Conservative: if masking confidence < 50%, skip clarity gain

**Intensity Control (Reimagine Knob):**
- 0% (off) → no clarity gain
- 30–70% (typical) → conservative clarity (≤ +1.5 dB per-band)
- 70%+ (aggressive) → full clarity (≤ +3 dB per-band; Phase 1.5 unlocks more)

**Example Scenario:**
```
Input: Piano + cello duet (low masking)
  → Masking threshold low (wide dynamic range)
  → Clarity gain minimal (instrument already clear)

Input: Orchestral tutti (high masking in mid-range)
  → Masking threshold high at 2–5 kHz (masked by strings + brass)
  → Clarity gain +1–2 dB at 3–4 kHz (unmask vocals)
  → No gain at 8–12 kHz (already bright cymbals)
```

### 2. Loudness Compensation (Fractional Contour-Diff, LD-17)

**Specification:**
- **Standard:** ISO 226 equal-loudness contour
- **Mechanism:** Measure output LUFS (from Sprint 4) → compute delta to reference level
- **Compensation:** Apply 40% of contour diff as EQ curve (not full DRC)
- **Clamp:** Hearing-safety limits (proportional scaling)

**Algorithm:**
```
1. Measure output LUFS (e.g., −16 LUFS)
2. Reference level: −16 LUFS (85 dBSPL @ 1 kHz)
3. Loudness delta: current − reference
   E.g., if playing at −10 LUFS: delta = (−10) − (−16) = +6 LU (louder)
4. Contour diff at each frequency: ISO 226 @ current level − ISO 226 @ reference level
   E.g., at 100 Hz: 85 dBSPL contour is −3 dB, 91 dBSPL contour is +2 dB
   → diff = 2 − (−3) = +5 dB
5. Fractional compensation: 40% of diff
   E.g., −2 dB (boost bass to compensate for higher playback level)
```

**Perceptual Effect:**
- At loud levels (≥ −6 LUFS, ~95 dBSPL): treble cut (protects from fatigue)
- At soft levels (≤ −30 LUFS, < 60 dBSPL): bass/treble boost (brings out detail)
- **Key:** Compensation is gentle, fractional, not a full dynamic range compressor

**RT Implementation:**
- LUFS measurement from Sprint 4 (off-RT)
- Contour-diff lookup table (pre-computed for common LUFS values)
- Apply ≤ 0.4× contour as EQ curve (publish to Arbiter)
- Clamp by hearing-safety limits

### 3. Arbiter (Control Plane Composition)

**Specification:**
- **Role:** Composes all DSP contributors (device, loudness, clarity, content, user NL macros) into unified per-band TargetState
- **Execution:** Off-RT (50–100 ms update rate)
- **Output:** Per-band EQ gains (TargetState), published lock-free to RT kernel

**Composition Logic:**
```
TargetState = device_profile_gains
            + loudness_compensation_gains
            + clarity_gains
            + content_aware_boosts
            + user_nl_macro_gains (if applicable)

All gains clipped by hearing_safety_clamp(cumulative_gain)
```

**Example Composition:**
```
Device (Sony WH-1000XM5): {+2 @ 2kHz, +1 @ 8kHz}
Loudness (−14 LUFS, warm): {−0.5 @ 100Hz, +0.3 @ 4kHz}
Clarity (orchestral tutti): {+1.5 @ 3kHz, +1 @ 8kHz}
Content (warm ballad): {+1 @ 100Hz}
User NL ("Make it brighter"): {+3 @ 8kHz, +2 @ 10kHz} [governing principle, locks bands]

Arbiter compose:
  100Hz: −0.5 + 1 = +0.5 dB (loudness + content)
  2kHz: +2 (device only)
  3kHz: +1.5 (clarity)
  4kHz: +0.3 (loudness)
  8kHz: +1 + 1 + 3 = +5 dB (clarity + content + user, user governs)
  10kHz: +2 (user governs)

Final TargetState: {0.5, 0, 2, 0, ..., 1.5, 0.3, ..., 5, 2}
```

**Governing Principles:**
- Device + loudness + clarity are auto-contributors (suggest magnitude)
- User NL is governing (locks the direction, auto-contributors refine magnitude)
- Example: user says "brighter" (locks 8–12 kHz boosted); clarity may refine how much

**Lock-Free Handoff:**
- Arbiter publishes TargetState to DoubleBuffer
- RT kernel reads latest TargetState atomically
- No locks, no audio-thread blocking

### 4. Conversational Tuning (Text → Claude → EQ)

**Specification:**
- **Input:** Text field ("Make this warmer", "Boost vocals", "Reduce harshness", etc.)
- **Processing:** Send to Claude API → parse response → extract EQ adjustments
- **Output:** Spline-interpolated 31-band curve → apply to sliders programmatically

**Interaction Flow:**
```
User types: "Make the vocals pop"
  ↓ (send to Claude)
Claude responds: "Boost the presence region (2–4 kHz) by 3–5 dB. Add a touch of air (8–10 kHz) for clarity."
  ↓ (parse response)
System extracts: {2kHz: +4, 3kHz: +5, 4kHz: +4, 8kHz: +2, 10kHz: +1.5}
  ↓ (spline interpolate to 31 bands)
Interpolator fills gaps: {2k: +4, 2.5k: +4.5, 3k: +5, 3.15k: +4.8, 4k: +4, ...}
  ↓ (apply to sliders)
UI updates 31 sliders smoothly (ramp ≥100ms)
  ↓ (user hears/sees result)
Before/after spectrum updates; user hears change
  ↓ (user feedback)
"Perfect" → saves, or "More warmth" → loop back to step 1
```

**Claude Prompt Template:**
```
You are an audio EQ expert. User request: "{user_input}"
Current track: {track_name} by {artist}
Current EQ curve: {current_eq_summary} (e.g., "flat", "presence peak")

Suggest a specific EQ adjustment (sparse, 3–5 key frequencies):
- List frequencies (Hz) and dB adjustments (±dB)
- Provide rationale (e.g., "2–4 kHz presence region for vocal clarity")
- Keep magnitudes realistic (±3 to ±6 dB typical)
- If confidence low, say so
```

**Confidence Gating:**
- Ask Claude for confidence score (0–1)
- If confidence ≥ 0.7: apply full suggestion
- If 0.5–0.7: apply 70% of suggestion (conservative)
- If < 0.5: suggest manual control ("I'm not sure, try adjusting sliders yourself")

**UI Display:**
- Show Claude's suggestion (text + preview curve) before applying
- "Apply" button → confirms
- "Adjust" button → tweaks with sliders
- "More/Less" shortcuts → increase/decrease by 20%

### 5. Content-Aware Adaptation

**Specification:**
- **FFT Analysis:** Per-buffer spectral profile (brightness, balance, density)
- **Genre Detection:** Infer genre from spectrum (lo-fi dark, rock bright, pop balanced, etc.)
- **EQ Adaptation:** Smooth curve transitions as music changes
- **Hysteresis:** Prevent hunting (small spectral changes don't trigger large EQ swings)

**Spectral Profile Metrics:**
```
Brightness: RMS energy ratio (8–20 kHz) / (20 Hz–20 kHz)
Balance: RMS energy (50–500 Hz) vs. (500 Hz–5 kHz) vs. (5–20 kHz)
Density: Peak count in FFT (high = busy, low = sparse)
```

**Genre Mapping (Heuristic):**
```
Dark + sparse → lo-fi (maybe slight bass boost to add weight)
Bright + dense → rock/pop (maybe presence peak for punch)
Balanced + smooth → classical/acoustic (minimal adjustment)
```

**EQ Adaptation Logic:**
- Detect spectral profile every 1–2 seconds
- Compute recommended EQ shift (off-RT)
- Apply smooth transition (≥500 ms ramp, no jarring mid-song jumps)
- User can disable auto-adapt if they prefer static curve

**Hysteresis Example:**
```
Current curve: {flat}
New spectral profile: "bright pop"
Recommended shift: {+2 @ 3kHz, +1 @ 10kHz}
Hysteresis: only apply if brightness increase > 3 dB threshold
  → if increase = +5 dB, apply shift
  → if increase = +0.5 dB, don't apply (too small)
```

---

## Validation Plan

### Unit Tests (Automated)

**Test Suite:** `AudioDSPTests/ClarityTests.swift` + `AudioDSPTests/LoudnessCompTests.swift` + `AudioDSPTests/ArbiterTests.swift`

#### Clarity Module Tests
1. **Masking threshold accuracy:** Compare vs. Moore-Glasberg reference
   - Synthetic masking scenario (1 kHz + 4 kHz tones)
   - Compute masking threshold at 2 kHz
   - Assert: threshold ≤ ±1 dB vs. reference

2. **Clarity gain conservatism:** Ensure ≤ +3 dB per-band
   - Generate 100 random audio frames
   - Compute clarity gains for each
   - Assert: all gains ≤ +3 dB/band, < +2 dB cumulative

3. **Bypass at low intensity:** Clarity off @ Reimagine 0–20%
   - Set Reimagine = 10%
   - Assert: clarity gains = 0 (no adjustment)

4. **Confidence gating:** Low-confidence macros trigger tighter clamps
   - Test: confidence = 0.3
   - Assert: clarity clamped to ≤ ±1.5 dB per-band (stricter than high-confidence)

#### Loudness Compensation Tests
1. **Contour-diff accuracy:** ISO 226 interpolation correct
   - Reference LUFS: −16 (85 dBSPL)
   - Test LUFS: −10 (91 dBSPL)
   - Compute contour diff at 100 Hz, 1 kHz, 10 kHz
   - Assert: computed diff ≤ ±1 dB vs. ISO 226 lookup

2. **Fractional scaling:** 40% of contour applied
   - Contour diff: −5 dB (bass boost needed at loud levels)
   - Applied compensation: 40% × (−5) = −2 dB
   - Assert: compensation = −2 dB

3. **Clamp interaction:** Hearing-safety clamp doesn't break compensation
   - Compensation + clarity + device profile → sum > +12 dB
   - Assert: proportional scaling maintains all three contributors' direction

#### Arbiter Composition Tests
1. **Multi-contributor composition:** Device + loudness + clarity + user
   - Inputs: device {+2}, loudness {+0.5}, clarity {+1}, user {+2}
   - Assert: output = {+5.5} before clamp

2. **User governing principle:** User intent locks direction, auto-contributors refine
   - User says "brighter" (locks 8–12 kHz up)
   - Device wants +1 @ 10 kHz
   - Clarity wants +1.5 @ 10 kHz
   - Assert: final = +1.5 @ 10 kHz (clarity's value, but all boost 10 kHz)

3. **Lock-free handoff:** TargetState published atomically
   - Arbiter updates state 10 times / second
   - RT thread reads atomically
   - Assert: no torn reads, no data corruption

#### Conversational Tuning Tests
1. **Claude response parsing:** Extract frequencies + gains from text
   - Claude: "Boost 2–4 kHz by +3 dB"
   - Parsed: {2000: +3, 4000: +3}
   - Assert: parsing succeeds, values correct

2. **Spline interpolation:** Sparse suggestions → 31 bands
   - Input: {2000: +4, 4000: +4, 8000: +1}
   - Interpolated: smooth curve through 31 bands
   - Assert: no kinks, monotonicity preserved where expected

3. **Confidence gating:** High confidence vs. low
   - High conf (0.9): apply full suggestion
   - Low conf (0.4): apply 70% (conservative)
   - Assert: magnitude scaling correct

#### Content-Aware Tests
1. **Spectral profile metrics:** Brightness, balance, density computed correctly
   - Synthetic test signals (dark lo-fi, bright pop, balanced classical)
   - Compute metrics
   - Assert: metrics match expected ranges

2. **Genre mapping:** Spectral profile → genre → recommended EQ
   - Bright + dense → pop (expect presence peak)
   - Dark + sparse → lo-fi (expect bass boost)
   - Assert: mapping matches heuristic

3. **Hysteresis:** Small spectral changes don't trigger EQ swaps
   - Brightness increases by +0.5 dB (below threshold)
   - Assert: no EQ change
   - Brightness increases by +5 dB (above threshold)
   - Assert: EQ changes

### Integration Tests (Manual + Scripted)

#### Clarity Perceptual Test
- **Setup:** Play masking-heavy passage (orchestral tutti)
- **Procedure:**
  1. Play at Reimagine 0% (no clarity)
  2. Play at Reimagine 50% (clarity engaged)
  3. A/B: Does the 50% version reveal more detail without sibilance?
- **Assert:** ≥80% of listeners notice detail improvement without harshness

#### Loudness Compensation A/B
- **Setup:** Play ballad, vary playback volume
- **Procedure:**
  1. Play at 85 dBSPL (reference)
  2. Play at 75 dBSPL without compensation → sounds quiet
  3. Play at 75 dBSPL with compensation → should sound similar to 85 dBSPL
- **Assert:** With compensation, perceived loudness @ 75 ≈ 85 dBSPL

#### Conversational Tuning Accuracy
- **Setup:** 20 diverse user requests
- **Procedure:**
  1. Type request: "Make it warmer"
  2. Claude suggests EQ
  3. Apply curve
  4. Listen: does it sound warmer?
  5. Rate success: Yes / Somewhat / No
- **Assert:** ≥18/20 (90%) success rate

#### Arbiter Composition (End-to-End)
- **Setup:** Simulate full stack
- **Procedure:**
  1. Load device profile (Sony WH-1000XM5)
  2. Play at −10 LUFS (loudness compensation engages)
  3. Orchestral passage (clarity engages)
  4. User NL: "Make it brighter" (user macro applies)
  5. Listen: all four layers compose coherently
- **Assert:** No weird interactions, balanced processing

#### Content-Aware Transition
- **Setup:** Play 2-song playlist (lo-fi → pop)
- **Procedure:**
  1. Play lo-fi track (dark spectrum) → EQ curve adapts (bass boost)
  2. Skip to pop track (bright spectrum) → EQ curve transitions smoothly (no jarring jump)
  3. Listen for glitching or odd swells
- **Assert:** Smooth transition, no perceptual artifacts

#### 2-Hour Adaptive Soak Test
- **Setup:** 2-hour diverse playlist
- **Config:** Clarity on, loudness comp on, content-aware on, random user NL macros every 10 min
- **Metrics:**
  - XRun count (assert: 0)
  - Metering stability (LUFS variance < 0.5 LU)
  - Memory growth (assert: stable, no leak)
  - CPU usage (assert: < 10% headroom)
- **Result:** Pass/Fail, logged

### Listening Panel (5–10 Audio Engineers)

**Protocol:** MUSHRA-style blind A/B + subjective ratings

#### Test 1: Clarity Unmask (Orchestral Passage)
- Candidate A: No clarity (Reimagine 0%)
- Candidate B: With clarity (Reimagine 50%)
- Question: Which reveals more orchestral detail?
- Pass: ≥70% prefer B, ≤10% report sibilance artifacts

#### Test 2: Loudness Compensation Transparency
- Candidate A: Loud (−6 LUFS)
- Candidate B: Soft (−30 LUFS) with compensation
- Question: Which sounds more natural? (prefer A / prefer B / same)
- Pass: ≥70% rate compensation as transparent (same perceived loudness & balance)

#### Test 3: Conversational Tuning Naturalness
- Play 3 tracks with Claude-suggested EQ curves
- Question: Do the EQ adjustments sound natural? (Natural / Slightly colored / Obvious EQ / Artifacts)
- Pass: ≥80% rate "Natural" or "Slightly colored"

#### Test 4: Arbiter Composition Coherence
- Play track with all 4 layers enabled (device + loudness + clarity + content-aware)
- Question: Do the DSP layers interact smoothly? (Seamless / Slight conflicts / Obvious issues)
- Pass: ≥80% rate "Seamless" or "Slight conflicts"

#### Test 5: Overall Adaptive Experience
- Use app for 30 min (varied tracks, user NL macros, volume changes)
- Question: Does the app feel adaptive to your music and ears? (Highly adaptive / Somewhat / Not really)
- Pass: ≥75% rate "Highly adaptive"

---

## Open Questions & Design Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| **Clarity intensity curve: linear or exponential?** | Linear (simpler, more predictable) | Easier for user to understand knob behavior |
| **Masking model: full roex(p) or simplified?** | Full roex(p) (more accurate) | Only ~50 ms off-RT; accuracy matters |
| **Loudness compensation: per-band or global with contour?** | Per-band contour (more sophisticated) | Industry standard (Nuendo, WAVES) |
| **Content-aware update rate: 1 sec or 2 sec?** | 2 sec (balance responsiveness + CPU) | Avoids hunting, catches genre changes |
| **User NL confidence threshold: 0.7 or 0.5?** | 0.7 (conservative for Phase 1) | Phase 1.5 can be more aggressive |
| **Conversational tuning: single-turn or iterative?** | Iterative (More/Less/Try Again buttons) | Matches user mental model of refinement |

---

## Acceptance Criteria (Done-Done)

- [ ] Clarity module vDSP code compiles, passes unit tests (4/4 clarity tests)
- [ ] Loudness compensation off-RT, accurate ±1 dB contour (3/3 comp tests)
- [ ] Arbiter composition functional, lock-free DoubleBuffer working (3/3 arbiter tests)
- [ ] Conversational tuning parsing + spline working (3/3 tuning tests)
- [ ] Content-aware spectral analysis + EQ adaptation working (3/3 content tests)
- [ ] Clarity perceptual test: ≥80% notice detail, ≤10% sibilance complaints
- [ ] Loudness compensation A/B: ≥70% rate transparent
- [ ] Conversational tuning: ≥90% phrase success (18/20)
- [ ] Arbiter composition end-to-end: coherent, no weird interactions
- [ ] 2-hour soak test: zero XRuns, metering stable, no CPU overruns
- [ ] Listening panel: ≥75% rate "Highly adaptive," ≥80% rate naturalness
- [ ] Code review: ASAN/TSan clean, no data races
- [ ] Documentation: Clarity, Compensation, Arbiter, Conversational Tuning READMEs

---

## Dependencies & Blockers

**Unblocked By:**
- ✅ Sprint 4 (limiter + LUFS metering)
- ✅ Sprint 5 (EQ wiring)

**Blocks:**
- 🟡 Phase 1c release (complete MVP)
- 🟡 Phase 1.5 (per-stem processing builds on Arbiter)

---

## Success Story (What "Done" Looks Like)

> **User launches Adaptive Sound, plays a lo-fi track at quiet level (−25 LUFS).**
>
> Loudness compensation engages (subtle bass + treble boost). Clarity unmasks vocal detail. Content-aware detects lo-fi spectrum, adds warmth. All four layers (device + loudness + clarity + content) compose transparently.
>
> **User types: "Make the vocals shine."**
>
> Claude suggests presence peak (2–4 kHz) + air (8–12 kHz). Spline interpolates to 31 bands. Spectrum shows change. User hears vocals pop. "Perfect."
>
> **Later, user skips to orchestral piece at loud level (−6 LUFS).**
>
> App auto-detects genre (bright + dense). EQ transitions smoothly to orchestral balance. Loudness compensation scales back (high level). User perceives seamless adaptation, no jarring.
>
> **Listening panel of 8 audio engineers evaluates.** All agree: "The DSP layers work together beautifully. No conflicts. Sounds professional and adaptive."

---

**Status:** Ready for implementation  
**Next:** Begin Sprint 6 coding after Sprint 5 ships
