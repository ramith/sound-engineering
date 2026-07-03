# Sprint Planning & Documentation

This directory contains the sprint methodology, the forward sprint schedule, and the historical per-sprint records (plans, test strategies, retrospectives) for AdaptiveSound development.

## The two authoritative docs

- **[`sprint-plan.md`](sprint-plan.md) — the authoritative forward sprint schedule (S6–S17).** What we build next and in what order: Phase 1 (player maturity / competitive parity) → Phase 2 (the Adaptive Sound differentiation pivot). Encodes the founder's 2026-06-19 strategy. **Start here for "what's next."**
- **[`00-sprint-model.md`](00-sprint-model.md) — the authoritative sprint / Kanban methodology** (5–10 SP sprints, done-done criteria, enabler-first ordering). The *how*, not the *what-next*.

> **Sprint-numbering note:** `sprint-plan.md` opens a fresh forward sequence at **S6**. The older per-sprint docs below use their own historical numbers (Sprint 4 / 5 / 5b / "Sprint 6"). These do **not** map onto the new S6+ scheme — in particular the old **`06-sprint-6-adaptive-clarity`** ("Sprint 6") is **not** the new plan's **S6** (DSP-gate hardening). The old docs are historical records, not current plans.

## Organization

Files are named with numeric prefixes (`00-`, `01-`, …) for natural sorting. Early-sprint material (Sprint 0–3 plans/test-plans, kickoffs, the Phase-1b-Part-A postmortem) lives in [`../session-notes/`](../session-notes/). This directory holds the methodology, the forward schedule, and the shipped-sprint records.

### Historical per-sprint records (this directory)
- **04-sprint-4-loudness-safety{,-plan,-test-plan,-retro}.md** — Loudness safety (BS.1770-5 meter + true-peak limiter) — ✅ shipped (merged)
- **05-sprint-5-eq-foundation{,-plan}.md**, **05-sprint-5-monitoring-tab-design.md**, **05-sprint-5-au-graph-spike-notes.md** — EQ foundation + Monitoring tab — ✅ shipped
- **05-sprint-5b-multichannel-{epic-plan,pipeline-plan,qa-plan}.md** — N-channel multichannel pipeline (S0–S3 + M4 shipped) — ✅ shipped
- **05-sprint-5b-s4-binaural-design.md** — Apple-native binaural design — ⏸ deferred; folded into `sprint-plan.md` Phase 2 (S17 BRIR)
- **06-sprint-6-adaptive-clarity.md** — pre-pivot "Sprint 6" adaptive-clarity spec — ⚠️ superseded by `sprint-plan.md` (loudness-comp → S13; clarity → S14–S15)
- **07-phase-1b-part-b-kickoff.md** — critical-path kickoff — ✅ completed (historical)
- **08-gui-design-review.md** — GUI design review — ✅ historical
- **09-phase-b-bit-perfect-pure-mode.md** — bit-perfect "Pure Mode" + gapless: status & learnings — ✅ shipped

### How tests actually run
The DSP gate is the **C++ null-test harness**: `bash scripts/build-null-test.sh` (golden master `0xE7267654BA01D315`). **`swift test` is broken** here (toolchain `@Test`/`@Suite` macro skew) — the Swift mock tests compile/lint but run only in Xcode. The Swift/XCTest suites described in the older `*-test-plan.md` docs (in `session-notes/`) were never built that way; treat those as historical.

The **library store** (S8+) has its own headless gate — `swift run VerifyLibraryStore` (mirrors the `VerifyAUGraph` idiom, since `swift test` is broken). **`make gate`** runs all three: the C++ null test, `VerifyAUGraph`, and `VerifyLibraryStore`.

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

**Last Updated:** 2026-06-19  
**Maintainer:** AdaptiveSound Team
