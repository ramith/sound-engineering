# Sprint Planning & Kanban Model — AdaptiveSound

**Document ID:** SPRINT-ASE-001  
**Version:** 1.0 — locked (2026-06-13)  
**Status:** Authoritative; governs development workflow

This document defines the sprint methodology, done-done criteria, and dependency ordering that governs all development sprints.

---

## Sprint Model (BA-2)

### Core Principles

**Kanban with sprint structure.** Work is organized into **sprints of 5–10 story points**, sized to be implementable and testable within ~1 week. Each sprint ships a locally-testable binary. GitHub releases are shipped manually by the founder when a meaningful feature set is ready.

- **Independently testable:** Each sprint is a complete, shippable work chunk. No incomplete half-features.
- **Enablers before features:** Engineering infrastructure (audio engine, biquad fitting, masking model) ships before feature work that depends on it.
- **Manual testing:** Brief testing at sprint end, before team retro. Done-done criteria are validated per sprint.
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
- **Regression tracking:** Keep a running list of known issues; resolve or defer.

### GitHub Release Decision

The founder manually decides when to ship a GitHub release based on:
- Feature set completeness (e.g., "Phase 0 player is playable and stable")
- Testing sign-off (no known blockers)
- User feedback readiness

**No automatic release per sprint.** Multiple sprints may accumulate before a release.

---

## Enabler-First Sequencing

### Dependency Graph

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
├─ SPIKE-PERF-BUDGET (multi-core scheduling)
├─ SPIKE-SEP-QUALITY (6-stem separation validation)
└─ SPIKE-REIMAGINE-MAP (intensity knob → parameter mapping)

AFTER enablers complete, features proceed in parallel:
├─ US-TONAL-* (EQ, device correction, loudness)
├─ US-PERC-* (clarity, masking-aware adjustment)
├─ US-NLT-* (natural-language tuning)
├─ US-REIMAGINE-* (intensity control)
└─ US-STEM-* (Phase 1.5 stem engine)

System-wide last:
└─ US-SYS-* (process tap or virtual device)
```

### Sequencing Rules

1. **Phase 0 (Player MVP):** US-ENG-01 only. Establishes audio playback.
2. **Phase 1 (Mix-Based Core):** US-ENG-02, spikes, then feature stories. Features depend on masking model + biquad fitting.
3. **Phase 1.5 (Stem Engine):** Parallel with Phase 1; depends on separation quality validation.
4. **Phase 2 (System-Wide):** Only after Phase 1 + 1.5 stabilize.

### Story Dependencies

- **US-PERC-02 depends on:** SPIKE-MASKING-MODEL, US-ENG-02
- **US-SPAT-01 depends on:** SPIKE-BRIR, US-ENG-02
- **US-STEM-01 depends on:** SPIKE-SEP-QUALITY, US-ENG-02, US-PERC-01

See `docs/product/backlog.md` for full dependency list.

---

## Team Cadence

- **Sprint Planning:** Monday or sprint start (~30 min, async in Slack or sync call)
- **Daily Standups:** Async (Slack updates) or brief (~15 min)
- **Code Review:** Continuous (target: <1 hour turnaround)
- **Sprint Testing:** Friday afternoon (~1–2 hours)
- **Sprint Retro:** Friday EOD (~30 min)

---

## Velocity & Future Planning

After each sprint, record:
- **Story points completed**
- **Actual duration vs. estimate**
- **Blockers or surprises**

Use velocity data to refine estimates for future sprints. Typical velocity: 8–13 sp/week, but adjust based on project maturity and team capacity.

---

## Related Documents

- [Sprint 0: Project Bootstrap](00-bootstrap-plan.md)
- [Sprint 1: Real Audio Engine](01-engine-plan.md)
- [Sprint 1: Test Strategy](01-engine-test-plan.md)

For current backlog and story details, see `docs/product/backlog.md`.

---

**Last Updated:** 2026-06-13  
**Maintained By:** AdaptiveSound Team
