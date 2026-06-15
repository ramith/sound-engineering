# Sprint Planning & Documentation

This directory contains planning, test strategies, and retrospectives for each sprint of AdaptiveSound development.

## Organization

Files are named with numeric prefixes (`00-`, `01-`, etc.) for sorting in editors:

### Sprint 0: Project Bootstrap
- **00-bootstrap-plan.md** — Sprint 0 plan (Xcode project, Swift/C++ interop, guardrails)
- **00-bootstrap-checklist.md** — Done-done criteria (build, test, commit, zero warnings)

### Sprint 1: Real Audio Engine
- **01-engine-plan.md** — Sprint 1 implementation plan (US-ENG-01, AUHAL, device enumeration)
- **01-engine-test-plan.md** — QA strategy (unit/integration tests, RT safety, manual checks)

### Sprint 2: Phase 1a → Phase 1b Handoff
- **02-phase-1a-kickoff.md** — Phase 1a architecture review + team sign-off
- **02-phase-1b-ui-redesign.md** — UI spec for Phase 1b (design-driven architecture)
- **02-mix-core-plan.md** — EQ + audio infrastructure
- **02-mix-core-test-plan.md** — Audio testing strategy
- **02-mix-core-briefing.md** — Team coordination
- **02-blocker-resolutions.md** — Critical issue fixes

### Sprint 3: Music Playback Implementation
- **03-KICKOFF.md** — Sprint 3 launch plan (solo execution model)
- **03-music-playback-implementation.md** — Full spec + breakdown (Parts 1–4)
- **PHASE-1B-PART-A-POSTMORTEM.md** — Post-audit retrospective (2026-06-15)
  - Scope delta analysis (planned vs. actual delivery)
  - Root cause analysis (why Part B deferred)
  - Time allocation breakdown
  - Lessons learned for next sprint
  - Quality assessment (code, testing, accessibility, design compliance)
  - Recommendations (Phase 1b Part B scope, Phase 1c blockers)

### Future Sprints
- **03-PHASE-1B-PART-B-PLAN.md** *(2026-06-18, 2 days, ~8 sp)*
  - Seek implementation, progress bar, metadata, persistence
- **04-PHASE-1C-PLAN.md** *(2026-06-22, 3 days, ~12 sp)*
  - AU wiring, conversational tuning, real-time DSP validation
- **05-PHASE-1.5-PLAN.md** *(2026-07-01, 5–7 days, ~20 sp)*
  - Stem separation, spatial audio, per-stem processing

---

## Naming Convention

**Format:** `{SPRINT_NUMBER}-{FEATURE}-{DOCUMENT_TYPE}.md`

- **{SPRINT_NUMBER}:** `00`, `01`, `02`, etc. (numeric prefix for sorting)
- **{FEATURE}:** Short descriptor (`bootstrap`, `engine`, `stem-separation`, `dsp-core`, etc.)
- **{DOCUMENT_TYPE}:** (optional)
  - `-plan.md` — Implementation plan, architecture, acceptance criteria
  - `-test-plan.md` — QA strategy, test breakdown, pass criteria
  - `-retro.md` — Post-sprint retrospective (lessons learned)

**Examples:**
```
00-bootstrap-plan.md
00-bootstrap-retro.md
01-engine-plan.md
01-engine-test-plan.md
01-engine-retro.md
02-stem-separation-plan.md
02-stem-separation-test-plan.md
```

**Why numeric prefixes?**
- Sorts naturally in file explorers (VSCode, Finder, etc.)
- Prevents accidental sorting like "Sprint 10" before "Sprint 2"
- Consistent across all sprints

---

## Accessing Sprint Documentation

### In VSCode
File → Open → `docs/sprints/01-engine-plan.md`
Or: Ctrl+P (Quick Open) → type `01-engine`

### Cross-references from other docs
Link format:
```markdown
See [Sprint 1 Implementation Plan](../sprints/01-engine-plan.md)
See [Sprint 1 Test Strategy](../sprints/01-engine-test-plan.md)
```

### In README
```markdown
## Active Sprint

**Sprint 1:** [Engine Bootstrap](docs/sprints/01-engine-plan.md)
```

---

## Sprint Lifecycle

Each sprint includes three documents:

1. **`-plan.md`** (pre-sprint)
   - Story, acceptance criteria, scope, estimates
   - Architecture & design decisions
   - Implementation breakdown (phase by phase)
   - Dependencies, risks, mitigations
   - Definition of Done

2. **`-test-plan.md`** (pre-sprint)
   - QA strategy, test breakdown
   - Unit, integration, E2E test scope
   - Real-time safety validation
   - Manual testing checklist
   - Pass criteria for each gate

3. **`-retro.md`** (post-sprint)
   - What went well?
   - What was harder than expected?
   - Velocity vs. estimate (velocity for future planning)
   - Improvements for next sprint
   - Blockers or tech debt to address

---

## Template: Sprint Plan

```markdown
# Sprint {N}: {Feature Name}

**Story:** {Story code} — {Title}  
**Estimate:** {X} sp / {Days} days  
**Status:** Ready for Implementation

## Executive Summary
{Brief 2–3 sentence goal}

## Acceptance Criteria
- ✅ {Criterion 1}
- ✅ {Criterion 2}

## Architecture & Design
{Design decisions, diagrams, class structures}

## Implementation Breakdown
### Phase 1: {Task A} ({X} sp)
...

## Dependencies & Blockers
{List any blockers or pre-requisites}

## Risk Mitigation
| Risk | Severity | Mitigation |
...

## Definition of Done
- [ ] All code committed
- [ ] Tests pass
- [ ] Manual testing complete
- [ ] Retro scheduled

## Timeline
- Day 1: ...
- Day 2: ...
```

---

**Last Updated:** 2026-06-13  
**Maintainer:** AdaptiveSound Team
