# Adaptive Sound — Product Roadmap
## Phase Timeline & Release Plan

**Status:** 🟢 READY FOR EXECUTION  
**Last Updated:** 2026-06-16 (Team Review Complete)  
**Release Target:** ~2026-07-10 (Internal MVP), Phase 1.5 TBD

---

## Overview

**Vision shift:** Away from Phase-based terminology toward **Sprint 4-6 DSP-First Model**

- **Phase 1a (✅ Shipped):** Audio engine core + reference tone
- **Phase 1b Part A (✅ Shipped):** Music playback UI + spectrum
- **Phase 1b Part B (🟡 In Progress):** Critical path (progress, seek, auto-play, test suite)
- **Phase 1c (Sprint 4-6, 🟡 Backlog):** Bundled DSP-first MVP (loudness → EQ → clarity)
- **Phase 1.5 (🔄 Planning):** Stem separation + advanced DSP
- **Phase 2 (🔄 Planning):** System-wide audio via virtual device

---

## Phase 1b Part B: Critical Path (Unblocks Phase 1c)

**Timeline:** 2026-06-18 → 2026-06-21 (effort-driven, not calendar-driven)  
**Owner:** You (solo)  
**Must-Have (2.5 days):**
1. Progress bar + polling (1 day)
2. Seek implementation (1 day)
3. Auto-play next track (0.5 day)
4. Fix test suite (0.5 day)

**Details:** See [../sprints/07-phase-1b-part-b-kickoff.md](../sprints/07-phase-1b-part-b-kickoff.md)

---

## Phase 1c: Sprints 4-6 DSP Bundle (MVP Release)

**Timeline:** TBD (effort-driven, no calendar pressure)  
**Scope:** Three integrated sprints, bundled into one Phase 1c MVP release  
**Target Internal Demo:** ~2026-07-10

### SPRINT 4: Loudness Safety & Transparent Dynamics
**Effort:** 5–10 story points

**High-level:** True-peak limiter (−1 dBTP, ≥4× OS) + LUFS normalization (ITU-R BS.1770-5) + hearing-safety clamps (≤ +12 dB cumulative)

**Why industry-best:** Hearing safety non-negotiable. Transparent loudness normalization (no artifacts). Safe floor for adaptive DSP.

**Validation:** Loudness ±0.1 LUFS, true-peak enforcement, 1-hour soak, listening panel

**Details:**
- Architecture: [../architecture/architecture.md §16 — Sprint 4](../architecture/architecture.md#phase-1--sprint-based-breakdown-mix-level-dsp-core)
- Full spec: [../sprints/04-sprint-4-loudness-safety.md](../sprints/04-sprint-4-loudness-safety.md) (design, C++ implementation, acceptance criteria)

---

### SPRINT 5: Minimum-Phase EQ Wiring & Spectral Correction
**Effort:** 5–10 story points

**High-level:** 31-band EQ wired to RT chain + before/after spectrum taps + AutoEq device profiles (5 headphones) + master gain post-DSP

**Why industry-best:** Minimum-phase avoids pre-ringing. Biquad cascade RT-efficient. AutoEq scientifically grounded.

**Validation:** Frequency response ±1 dB, null-test bit-exact @ 0 dB, THD+N ≤ −90 dB, device-profile accuracy, perceptual listening panel

**Details:**
- Architecture: [../architecture/architecture.md §16 — Sprint 5](../architecture/architecture.md#phase-1--sprint-based-breakdown-mix-level-dsp-core)
- Full spec: [../sprints/05-sprint-5-eq-foundation.md](../sprints/05-sprint-5-eq-foundation.md) (design, EQ realization, acceptance criteria)

---

### SPRINT 6: Adaptive Clarity & Loudness Compensation
**Effort:** 5–10 story points

**High-level:** Masking-aware clarity (ERB-rate roex model, ≤ +3 dB/band) + fractional loudness compensation (ISO 226, 40% contour-diff) + Arbiter (control-plane composition) + conversational tuning (text → Claude → EQ) + content-aware adaptation

**Why industry-best:** Masking-aware clarity distinguishes professional from static EQ. Fractional loudness compensation transparent. Per-buffer adaptation is competitive moat. Conversational tuning brings accessibility + power-user depth.

**Validation:** Masking model ±1 dB, clarity conservative, conversational tuning ≥75% phrase accuracy, listening panel A/B, 2-hour adaptive soak

**Details:**
- Architecture: [../architecture/architecture.md §16 — Sprint 6](../architecture/architecture.md#phase-1--sprint-based-breakdown-mix-level-dsp-core)
- Full spec: [../sprints/06-sprint-6-adaptive-clarity.md](../sprints/06-sprint-6-adaptive-clarity.md) (design, Arbiter composition, acceptance criteria)

---

## Minimal UI Strategy (Phase 1c MVP)

**Principle:** "UI as Support Layer" — 70% DSP, 30% UI

**Phase 1c Minimal (3 days):**
- ✅ 31-band EQ sliders (direct control)
- ✅ Before/after spectrum (visual proof)
- ✅ Conversational text input
- ❌ Graphical curve editor (defer to Phase 1.5)
- ❌ Multichannel spectrum (defer to Phase 1.5)
- ❌ Preset save/load (defer to Phase 1.5)

**Rationale:** Sliders + spectrum sufficient for MVP. Graphical curves are polish. Phase 1c ships faster; Phase 1.5 adds UI refinements.

---

## Validation Framework

**Three pillars:** Automated testing + integration tests + listening panel (professional audio engineers)

**Per-merge gates (< 15 min):**
- Unit tests ≥80% coverage
- Null-test: MD5 bit-exact bypass @ intensity 0
- ASAN/TSan/clang-tidy clean

**Nightly regression (~30 min):**
- Biquad fitting stress (1000 random curves)
- 20-track corpus end-to-end
- Masking model accuracy
- RT-safety metrics (p99.9 ≤ 5 ms, xruns = 0)

**Per-sprint final validation:**
- Sprint 4: Loudness ±0.1 LUFS, true-peak ≤ −1 dBTP, listening panel
- Sprint 5: EQ frequency response ±1 dB, null-test, device-profile accuracy, listening panel
- Sprint 6: Masking model ±1 dB, clarity gains conservative, conversational tuning accuracy ≥75%, listening panel

**Details:** [../architecture/validation-strategy.md](../architecture/validation-strategy.md) (full QA framework, listening panel protocol, lab setup)

---

## Release Milestones

| Milestone | Target | Content | Status |
|-----------|--------|---------|--------|
| **Phase 1b Part A Ship** | 2026-06-15 ✅ | Playback UI + spectrum | SHIPPED |
| **Phase 1b Part B Complete** | 2026-06-21 | Progress, seek, auto-play, test suite | IN PROGRESS |
| **Sprint 4 Complete** | TBD | Loudness safety | BACKLOG |
| **Sprint 5 Complete** | TBD | EQ foundation | BACKLOG |
| **Sprint 6 Complete** | TBD | Adaptive clarity | BACKLOG |
| **Phase 1c MVP Ship** | ~2026-07-10 | Sprints 4–6 bundled (internal demo) | PLANNED |
| **Phase 1.5 Complete** | ~2026-08-01 | Stem separation + spatial audio | PLANNING |
| **Phase 2 Complete** | ~2026-09-01 | System-wide via virtual device | PLANNING |

---

## Success Criteria (Phase 1c MVP)

**Functional:**
- Music playback (file picker, play/pause, next/previous, auto-play)
- Real-time EQ (31 sliders, immediate audio feedback)
- Before/after spectrum (visual proof DSP works)
- Conversational tuning (text → Claude → EQ changes)
- Seek + progress bar (playback position control)

**Quality:**
- No xruns or dropouts (soak tests pass)
- Seek accurate ±100 ms (imperceptible)
- ASAN + TSan clean (no leaks, data races)
- Unit tests passing (EQ math verified)
- Listening panel consensus (≥80% rate naturalness)

**Performance:**
- Sub-500 ms playback latency
- Real-time slider feedback (no lag)
- Conversational tuning responsive (< 500 ms API latency)

---

## Cross-References

**For detailed DSP design & architecture:** [../architecture/architecture.md](../architecture/architecture.md) (complete system design, locked decisions, ADRs)

**For detailed sprint specs & implementation:** 
- [../sprints/04-sprint-4-loudness-safety.md](../sprints/04-sprint-4-loudness-safety.md)
- [../sprints/05-sprint-5-eq-foundation.md](../sprints/05-sprint-5-eq-foundation.md)
- [../sprints/06-sprint-6-adaptive-clarity.md](../sprints/06-sprint-6-adaptive-clarity.md)
- [../sprints/07-phase-1b-part-b-kickoff.md](../sprints/07-phase-1b-part-b-kickoff.md) (critical path action items)

**For QA framework & validation procedures:** [../architecture/validation-strategy.md](../architecture/validation-strategy.md) (per-merge gates, nightly regression, listening panel protocol)

**For product requirements & features:** [requirements.md](requirements.md) (what we're building, user needs, feature breakdown)

**For backlog & prioritization:** [backlog.md](backlog.md) (features ranked by priority, Phase dependencies)

---

**Status:** 🟢 Ready for execution  
**Next step:** Phase 1b Part B kickoff (2026-06-18)
