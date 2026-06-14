# Sprint 2 Team Review Briefing
**Phase 1: Mix-Based Core (EQ, Clarity, Loudness, BRIR, Intensity)**

---

## 🎯 What We're Building

Transform the AdaptiveSound app from a bare-bones audio engine into a **professional DSP signal chain** that makes music sound noticeably better:

1. **EQ Module** — 31-band parametric EQ (±12 dB per band) with interactive frequency graph
2. **Clarity Module** — Smart transient shaping + selective compression in the presence band (1–4 kHz)
3. **Loudness Compensation** — ISO 226 equal-loudness curves + makeup gain to -16 LUFS reference
4. **Binaural Rendering (BRIR)** — SADIE II HRTF dataset for spatial immersion on headphones
5. **Intensity Knob** — 0% = bit-faithful bypass → 100% = full processing (crossfadeable)
6. **True-Peak Limiter** — Prevents clipping (-1 dBTP), responds in <1 ms

## 📋 Key Numbers

| Metric | Value |
|--------|-------|
| **Story Points** | 8 sp |
| **Days** | ~10 business days (2 weeks) |
| **Phases** | 5 (EQ, Clarity+Loudness, BRIR+Intensity, Limiter+Chain, QA) |
| **Unit Tests** | 25+ (EQ freq response, Clarity gating, Loudness LUFS, HRTF convolution, Limiter peaks) |
| **Integration Tests** | 8 (signal chain sweeps, null-test, music loops, edge cases) |
| **Manual QA** | A/B listening on 2 headphone pairs + 1 speaker pair, 3 reference tracks, ≥2 listeners |

---

## 🎨 Signal Flow

```
File/Device Audio Input
    ↓
[EQ: 31-band parametric, min-phase]
    ↓
[Clarity: Transient shaping + selective compression (1–4 kHz)]
    ↓
[Loudness: ISO 226 makeup to -16 LUFS]
    ↓
[BRIR/HRTF: Binaural rendering (SADIE II)]
    ↓
[True-Peak Limiter: Clamp to -1 dBTP]
    ↓
[Intensity Knob: 0% bypass ↔ 100% processing crossfade]
    ↓
Audio Output to Headphones/Speakers
```

---

## ⚙️ Technical Decisions

### Why These Modules?
- **EQ** — user-visible control; essential for personal tuning
- **Clarity** — unmasks overlapping sources (e.g., vocals buried in mix) via transient sharpening + compression
- **Loudness** — normalizes per-track loudness (Spotify is -14 LUFS, jazz might be -8 LUFS) for consistent listening
- **BRIR** — spatial immersion key differentiator vs. stock audio (Phase 0 was stereo-only)
- **Intensity** — smooth crossfade between dry (bit-faithful) and wet (processed) lets user find their sweet spot
- **Limiter** — prevents clipping from makeup gains or user EQ boost; transparent true-peak metering

### Why Minimum-Phase EQ by Default?
- No pre-ringing artifacts (linear-phase EQ rings before transients)
- Acceptable for music (transient-dense sources); user can toggle linear-phase if needed
- Lower CPU / latency overhead

### Why SADIE II HRTF (Not AVAudioEnvironmentNode)?
- **SADIE II:** Apache-2.0, customizable room IR, control over reverb tail (Phase 1.5)
- **AVAudioEnvironmentNode:** Apple's HRTF is baked-in (non-replaceable), no room control

### Why Band Approximation (Not Real-Time Stem Separation)?
- Stem separation (Demucs/MLX) adds >1 sec latency → not suitable for real-time playback in Phase 1
- Phase 1 uses band-region EQ for instrument requests (e.g., "guitar too quiet" → boost 2–4 kHz)
- Full stem separation deferred to Phase 1.5 (offline analysis + cached FLAC stems)

---

## 🚨 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Convolution latency >5 ms | Medium | Audible delay | Pre-profile with partition convolution; defer full BRIR if needed |
| Clarity false positives (gating noise) | Medium | Artifacts on noise-heavy music | Use confidence mask (spectral flatness); manual tuning on reference tracks |
| Loudness makeup pumping | Low | Audible modulation | Rate-limit makeup to fader-change events only |
| Phase artifacts (min-phase) | Low | Subtle on transient-heavy music | Add linear-phase toggle for edge cases |
| RT-safety violations (malloc on audio thread) | Low | Dropouts | ASAN + static analysis + code review gates |
| HRTF rendering off-center | Low | Lost spatialization | Defer head-tracking to Phase 1.5; Phase 1 = fixed front-center |

---

## ✅ Definition of Done

**Before Merge to Main:**
1. ✅ All 25+ unit tests passing
2. ✅ All 8 integration tests passing
3. ✅ Null-test verified (bit-identical bypass)
4. ✅ Manual listening QA sign-off (≥2 listeners, ≥3 tracks)
5. ✅ Zero compiler warnings
6. ✅ ASAN clean (no memory safety issues)
7. ✅ Real-time safety audit passed (code review + static analysis)
8. ✅ No audio dropouts @ 48 kHz / 512 frames (≤5 ms added latency)
9. ✅ Documentation updated (README, architecture, API comments)
10. ✅ Sprint retrospective completed

---

## 📅 Timeline

| Milestone | Duration | Owner |
|-----------|----------|-------|
| **Team Review & Kickoff** | 0.5 days | Founder + Team |
| **Phase 1a: EQ Module** | 2.5 days | Audio DSP Engineer |
| **Phase 1b: Clarity + Loudness** | 2.5 days | Audio DSP Engineer |
| **Phase 1c: BRIR + Intensity** | 2.5 days | Audio DSP Engineer |
| **Phase 1d: Limiter + Chain** | 2 days | Audio DSP Engineer |
| **Phase 1e: Manual QA + Retro** | 1 day | QA + Audio Engineer |
| **Total** | ~10 days (2 weeks) | — |

---

## 🎓 Learning Outcomes

After Sprint 2, the team will have:
- ✅ Deep understanding of perceptual audio processing (ERB, masking, ISO 226 loudness)
- ✅ Real-time DSP implementation experience (vDSP, biquad cascades, convolution)
- ✅ Testing best practices for audio (frequency-response validation, null-test protocols, A/B listening)
- ✅ Confidence in shipping Phase 1 without regressing to Phase 0

---

## ❓ Open Questions for Team Discussion

1. **BRIR full implementation or minimal-mode HRTF in Phase 1?**
   - Full BRIR (early reflections + late reverb) adds ~3 ms latency + complexity
   - Minimal-mode HRTF (dry, 45 azimuths) works today, Phase 1.5 adds full BRIR
   - **Recommendation:** Minimal-mode HRTF now; full BRIR in Phase 1.5

2. **UI: Interactive EQ graph or preset-only?**
   - Interactive: more powerful, more development effort
   - Preset-only: simpler MVP, still tuneable
   - **Recommendation:** Presets + single tweakable "Presence" band for Phase 1; interactive graph in Phase 1.5

3. **File export (render to .m4a) in Phase 1 or Phase 1.5?**
   - Export requires file I/O + rendering pipeline
   - Live playback alone is sufficient for MVP
   - **Recommendation:** Live playback only in Phase 1; export in Phase 1.5

4. **Genre/mood Create ML model in Phase 1?**
   - ML training requires >1000 labeled clips + compute time
   - Heuristic approach (spectral shape) simpler, sufficient for Phase 1
   - **Recommendation:** Heuristics now; Create ML model in Phase 1.5

---

## 🏆 Success Criteria

**Phase 1 is a success if:**
1. ✅ Ship on main without blocking Phase 1.5 / Phase 2
2. ✅ Zero audio dropouts on target hardware (M1 Pro / 16 GB)
3. ✅ Listening tests show measurable improvement (A/B null tests + blind feedback)
4. ✅ Velocity ≥7 sp / sprint (for future planning)
5. ✅ Team confidence high (retro feedback positive)

---

## 📚 Reference Documents

- **Implementation Plan:** [02-mix-core-plan.md](02-mix-core-plan.md)
- **Test & QA Strategy:** [02-mix-core-test-plan.md](02-mix-core-test-plan.md)
- **Product Requirements:** [../../product/requirements.md](../../product/requirements.md)
- **Architecture:** [../../architecture/architecture.md](../../architecture/architecture.md)

---

## 🚀 Next Steps (Today's Team Review)

1. **Understand** the signal chain and module breakdown
2. **Discuss** risks, open questions, and mitigation strategies
3. **Review** test strategy (coverage, manual QA protocol)
4. **Agree** on timeline, success criteria, and definition of done
5. **Identify** any blockers or dependencies
6. **Kick off** implementation (start Phase 1a tomorrow)

---

**Prepared by:** Audio DSP Team  
**Date:** 2026-06-14  
**Status:** Ready for Team Review Meeting
