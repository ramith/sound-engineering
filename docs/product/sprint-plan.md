# Sprint Planning & Kanban Model — Adaptive Sound

**Document ID:** SPRINT-ASE-001  
**Version:** 1.0 — locked (2026-06-13)  
**Date:** 2026-06-13  
**Author:** Business Analyst + Founder  
**Status:** Authoritative; governs development workflow

---

## Sprint Model (BA-2)

### Core Principles

**Kanban with sprint structure.** Work is organized into **sprints of 5–10 story points**, sized to be implementable and testable within ~1 week. Each sprint ships a locally-testable binary. GitHub releases are shipped manually by the founder when a meaningful feature set is ready.

- **Independently testable:** Each sprint is a complete, shippable work chunk. No incomplete half-features.
- **Enablers before features:** Engineering infrastructure (audio engine, biquad fitting, masking model) ships before feature work that depends on it.
- **Manual testing:** Brief testing at sprint end, before team retro. Done-done criteria are validated per sprint (Claude asks, user picks acceptance).
- **Dependency ordering:** Respect technical dependencies; don't block on unrelated stories.
- **Epics span sprints:** A feature (e.g., "Clarity via masking") may take 2–3 sprints; each sprint is independently done-done.

### Done-Done Definition Template

Before each sprint, the team validates the acceptance criteria using this template:

```
Sprint [N]: [Title]
Story Points: [5–10]

Done-Done Checklist:
☐ Code merged to main
☐ Unit tests pass (coverage: [required %])
☐ Integration tests pass (list key scenarios)
☐ Manual testing completed by founder (see testing checklist below)
☐ No known regressions in related features
☐ [Repo-specific test] (e.g., frequency-response < ±1 dB, latency < X ms)
☐ Documentation updated (architecture.md? requirements.md? user-journeys.md?)
☐ Team retro completed

Manual Testing Checklist (brief):
- [ ] Feature loads / initializes without crash
- [ ] [User interaction 1]: … (describe the action)
- [ ] [Expected outcome]: … (what should happen)
- [ ] [User interaction 2]: …
- [ ] A/B test (if applicable): compare [old] vs [new]
- [ ] No audio artifacts / glitches
- [ ] Performance acceptable (list measured metrics if applicable)

Approval:
Founder sign-off: [ ] Pass  [ ] Fail  [ ] Needs more testing
If Fail: list blockers below.
```

### Testing Schedule

- **Per sprint:** Brief manual testing at sprint end (30 min–1 hour for small features).
- **Before retro:** Founder confirms done-done via the checklist above.
- **Before GitHub release:** Extended listening test (full album, A/B vs. prior version).
- **Regression tracking:** Keep a running list of known issues / regressions; resolve or defer to future sprint.

### GitHub Release Decision

The founder manually decides when to ship a GitHub release based on:
- Feature set completeness (e.g., "Phase 0 player is playable and stable").
- Testing sign-off (no known blockers).
- User feedback readiness (e.g., "I want to share this with friends").

**No automatic release per sprint.** Multiple sprints may accumulate before a release; conversely, a single major feature (unlikely in the 5–10 sp range) might warrant its own release.

---

## Enabler-First Sequencing

### Dependency Graph (Simplified)

```
┌─ US-ENG-01 (Audio engine foundation)
│  └─ US-ENG-02 (DSP scaffold + biquads)
│     ├─ SPIKE-MASKING-MODEL (roex masking + arbitration)
│     │  ├─ US-PERC-01 (Arbiter logic)
│     │  └─ US-PERC-02 (Realizer + biquad fitting)
│     │
│     └─ SPIKE-BRIR (binaural impulse response)
│        └─ US-SPAT-01 (BRIR spatial rendering)
│
├─ SPIKE-PERF-BUDGET (multi-core scheduling, QualityProfile tuning)
├─ SPIKE-SEP-QUALITY (6-stem separation quality gates + MLX vs. Core ML decision)
└─ SPIKE-REIMAGINE-MAP (intensity knob → parameter mapping)

AFTER enablers complete, feature sprints can proceed in parallel:
├─ US-TONAL-* (EQ, device correction, loudness compensation)
├─ US-PERC-* (clarity, masking-aware adjustment)
├─ US-NLT-* (natural-language tuning, if OQ-11 resolved)
├─ US-REIMAGINE-* (intensity control)
└─ US-STEM-* (Phase 1.5 stem engine, depends on sep-quality validation)

System-wide (Phase 2) last:
└─ US-SYS-* (process tap or virtual device)
```

### Sprint Sequencing (Proposed)

**The following is a proposal. Actual sprints will be determined sprint-by-sprint based on founder priorities and team feedback.**

| Sprint | Title | Stories | SP | Duration | Dependencies |
|---|---|---|---|---|---|
| **0** | **Project bootstrap** | (Xcode project, Swift/C++ interop, build system) | **3** | **~1 day** | **None (first sprint)** |
| 1 | Audio engine foundation | US-ENG-01 | 8 | ~1 wk | Sprint 0 |
| 2 | DSP scaffold + biquad framework | US-ENG-02 | 8 | ~1 wk | US-ENG-01 |
| (parallel) | SPIKE-MASKING-MODEL (roex masking) | SPIKE-MASKING-MODEL | 5 | ~3–4 days | US-ENG-02 |
| (parallel) | SPIKE-BRIR (SOFA convolution integration) | SPIKE-BRIR | 5 | ~3–4 days | US-ENG-02 |
| 3 | Arbiter + Realizer + biquad fitting | US-PERC-01, US-PERC-02 | 16 | ~2 wks (or split across 2 sprints) | SPIKE-MASKING-MODEL |
| 4 | BRIR spatial rendering | US-SPAT-01 | 8 | ~1 wk | SPIKE-BRIR, US-PERC-02 |
| 5 | Device correction EQ | US-TONAL-02 | 5 | ~1 wk | US-ENG-02, US-PERC-02 |
| 6 | Loudness compensation (Fletcher-Munson) | US-TONAL-03 | 8 | ~1 wk | US-ENG-02, US-PERC-02 |
| 7 | Reimagine knob (mix-level range) | US-REIMAGINE-01, US-REIMAGINE-02 | 8 | ~1 wk | US-PERC-02, US-SPAT-01 |
| (parallel) | SPIKE-SEP-QUALITY (6-stem quality gates) | SPIKE-SEP-QUALITY | 5 | ~4–5 days | US-TONAL-03 |
| 8 | Content-adaptive clarity (masking-aware) | US-PERC-03 | 8 | ~1 wk | US-PERC-02, SPIKE-MASKING-MODEL |
| 9–N | Phase 1.5 & Phase 2 features | US-STEM-*, US-SYS-* | Varies | Varies | Earlier stages |

**Notes:**
- Spikes (SPIKE-*) are investigation/design work; they unblock feature stories but are not user-facing features themselves.
- Some sprints may be split (e.g., US-PERC-01 + US-PERC-02 = 16 sp could become 2× 8-sp sprints).
- The founder can reorder or reprioritize at any sprint boundary.

---

## Sprint 0: Project Bootstrap (Locked Plan)

**Goal:** Set up a buildable Xcode project with Swift/C++ interop working, so Sprint 1 can start audio code on day 1.

**Project Details:**
- **Name:** AdaptiveSound
- **Language:** Swift UI (app shell) + C++ (audio DSP kernel)
- **Target macOS:** Current version - 1 (e.g., macOS 14 Sonoma if current is 15)
- **Minimum Deployment:** Same as target
- **Signing:** No Apple Developer ID needed for local dev (unsigned, runs locally only)
- **Build System:** Xcode, Swift Package Manager optional (use plain Xcode project for audio, simpler)

**Done-Done Checklist:**

```
☐ Xcode project created and committed to git
☐ Frameworks linked: CoreAudio, AudioToolbox, Accelerate, os (Audio Workgroups)
☐ Swift/C++ interop set up:
  - Bridging header (ObjC++ wrapper if needed)
  - C++ module compiles with -Wall -Wextra -fno-exceptions
  - Swift can call C++ functions
☐ Dummy "Hello Audio" app:
  - AppDelegate or main App struct initializes an AudioEngine stub
  - Logs "Audio engine initialized" to console on launch
  - Does not crash; AVAudioEngine object exists in memory
☐ README.md with build/run instructions:
  - Xcode version requirement (15.0+)
  - macOS version tested
  - How to build & run locally
  - Where to find the app output
☐ Project structure organized:
  - Sources/AdaptiveSound/ (Swift app code)
  - Sources/AudioDSP/ (C++ code)
  - Tests/ (empty, ready for US-ENG-01)
  - docs/ (pointer to project docs)
☐ Manual testing by founder:
  - App launches without crash
  - Console output shows initialization messages
  - No compiler warnings
☐ Code is committed to main branch

Acceptance: App builds, runs, and logs a message. That's it.
```

**Success Measure:**
You can run the app on your M1 Mac, see "Audio engine initialized" in the console, and know that Sprint 1 (US-ENG-01) can start writing real AVAudioEngine code in the next sprint.

**Estimate:** 3 sp | **Duration:** ~1 day | **Timeline:** Ready whenever you say "start Sprint 0"

---

---

## Team Cadence

- **Sprint planning:** 30 min (Claude + founder) — discuss stories, estimate SPs, validate dependencies.
- **Sprint work:** ~1 week of development (continuous integration).
- **Sprint review/testing:** Friday end-of-day (founder tests, signs off on done-done).
- **Sprint retrospective:** Friday 30 min — what went well, what to improve next sprint.
- **GitHub release:** Ad-hoc, when feature set is ready.

---

## Tracking & Visibility

- **Sprint tracking:** Backlog.md will list stories organized by epic and (eventually) sprint milestone.
- **In-progress work:** Claude will track which sprint is active in memory and in conversation context.
- **Blockers:** Any blocker encountered mid-sprint is escalated to the founder immediately (not deferred to retro).
- **Scope creep:** If a sprint grows beyond 10 SPs, defer overage stories to the next sprint.

---

## Cross-References

- **Backlog.md:** Stories, epics, spikes, dependencies.
- **Architecture.md § 0:** Sprint model decision (BA-2).
- **Requirements.md:** Functional requirements that stories implement.
- **User-journeys.md:** User flows that sprints enable.

---

## Glossary

- **Done-done:** Implemented, unit-tested, integrated, manually verified by founder. Ready for user feedback or next sprint's dependent work.
- **Epic:** A large feature that spans multiple sprints (e.g., "Clarity enhancement" includes masking model, Arbiter, clarity contributor).
- **Spike:** A time-boxed investigation or design sprint that unblocks feature work (e.g., "Determine masking model choice").
- **Story point:** Relative size estimate (5–10 sp per sprint = ~1 week).
- **GitHub release:** A versioned binary (.dmg) published to GitHub Releases for external users to download.
