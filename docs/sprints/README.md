# Sprint Planning & Documentation

This directory contains the sprint methodology, the forward sprint schedule, and the historical per-sprint records (plans, test strategies, retrospectives) for AdaptiveSound development.

## The two authoritative docs

- **[`sprint-plan.md`](sprint-plan.md) — the authoritative forward sprint schedule (S6–S18).** What we build next and in what order: Phase 1 (player maturity / competitive parity) → Phase 2 (the Adaptive Sound differentiation pivot). Encodes the founder's 2026-06-19 strategy. **Start here for "what's next."**
- **[`00-sprint-model.md`](00-sprint-model.md) — the authoritative sprint / Kanban methodology** (5–10 SP sprints, done-done criteria, enabler-first ordering). The *how*, not the *what-next*.

> **Sprint-numbering note:** `sprint-plan.md` opens a fresh forward sequence at **S6**. The older per-sprint docs below use their own historical numbers (Sprint 4 / 5 / 5b / "Sprint 6"). These do **not** map onto the new S6+ scheme — in particular the old **`06-sprint-6-adaptive-clarity`** ("Sprint 6") is **not** the new plan's **S6** (DSP-gate hardening). The old docs are historical records, not current plans.

## Organization

Files are named with numeric prefixes (`00-`, `01-`, …) for natural sorting. Early-sprint material (Sprint 0–3 plans/test-plans, kickoffs, the Phase-0 team sprints, the team fixing plans, the Phase-1b-Part-A postmortem) lives in [`../session-notes/`](../session-notes/), where it is date-prefixed (`YYYY-MM-DD-*.md`). This directory holds the methodology, the forward schedule, and the shipped-sprint records.

### Sprint & design records (this directory)

> **Current status is not narrated here** — a doc's ✅/⏸/⚠️ marker is a coarse *provenance* tag, not a live status board. What actually shipped and works is the source + git; what's next is [`sprint-plan.md`](sprint-plan.md). These records exist for their **design rationale and decisions**, which code does not carry.

**Old-numbering per-sprint records** (`{NN}-…`, the historical 04/05/06 scheme):
- **04-sprint-4-loudness-safety{,-plan,-test-plan,-retro}.md** — Loudness safety (BS.1770-5 meter + true-peak limiter) — ✅ shipped
- **05-sprint-5-eq-foundation{,-plan}.md**, **05-sprint-5-monitoring-tab-design.md**, **05-sprint-5-au-graph-spike-notes.md** — EQ foundation + Monitoring tab — ✅ shipped
- **05-sprint-5b-multichannel-{epic-plan,pipeline-plan,qa-plan}.md** — N-channel multichannel pipeline — ✅ shipped
- **05-sprint-5b-s4-binaural-design.md** — Apple-native binaural design — ⏸ deferred → `sprint-plan.md` Phase 2 (S18 BRIR)
- **06-sprint-6-adaptive-clarity.md** — pre-pivot "Sprint 6" adaptive-clarity spec — ⚠️ superseded (loudness-comp → S14; clarity → S16, spike S15). **Not** the forward-plan S6.
- **07-phase-1b-part-b-kickoff.md** — critical-path kickoff — ✅ historical
- **08-gui-design-review.md** — GUI design review — ✅ historical (superseded by the Stage-4 GUI review + layout redesign)
- **09-phase-b-bit-perfect-pure-mode.md** — bit-perfect "Pure Mode" + gapless: learnings (incl. the "AVAudioEngine cannot be bit-perfect" finding) — ✅ shipped

**Forward S-series records** (`s{N}[.{sub}]-…`, the sprint-plan S6+ scheme):
- **s6-architecture-review-findings.md**, **s6-tier3-spine-design.md** — S6 arch-review gate + Tier-3 DSP-spine rework — ✅ shipped (rationale-bearing; do not lose)
- **s7-soak-instruments-procedure.md** — on-hardware RT-allocation soak procedure (reusable how-to) — ✅ live procedure
- **s8-1-persistent-store-design.md**, **s8-2-folder-scan-design.md**, **s8-3-metadata-art-design.md**, **s8-4-live-watch-move-match-design.md** — S8 library-spine design (store now **GRDB-backed** — see the SUPERSEDED note in s8-1) — ✅ shipped
- **s9-browse-search-ui-design.md**, **s9-library-ia-queue-design.md**, **s9-5-songs-search-design.md** (+ `-test-plan`), **s9-6-artists-genres-design.md** — S9 browse/search design — ✅ shipped
- **s9-implementation-plan.md**, **s9-5-search-sort-design.md**, **s9-5-queue-toast-design.md**, **s9-5-customizable-columns-plan.md** — S9.5 execution/companion fragments — ⚠️ superseded/folded into `s9-5-songs-search-design.md`
- **qw1-quick-win-differentiators-design.md** — QW1 crossfeed + Reimagine-intensity + tonal presets (crossfeed↔BRIR exclusivity invariant) — ✅ shipped

**Cross-sprint topical design docs** (`{feature}-{design|plan}.md`, not owned by one sprint):
- **layout-architecture-design.md**, **layout-implementation-plan.md**, **l3-footer-transport-design.md**, **eq-controls-redesign.md**, **music-folders-accordion.md** — GUI layout / control designs

### How tests actually run
The DSP gate is the **C++ null-test harness**: `bash scripts/build-null-test.sh` (golden master `0xE7267654BA01D315`). `swift test` runs the Swift suites headless (native swift-testing) as part of `make strict-gate`. The Swift/XCTest suites described in the older `*-test-plan.md` docs (in `session-notes/`) were never built that way; treat those as historical.

The **library store** (S8+) has its own headless gate — `swift run VerifyLibraryStore` (mirrors the `VerifyAUGraph` idiom). **`make gate`** runs all three: the C++ null test, `VerifyAUGraph`, and `VerifyLibraryStore`.

---

## Naming Convention

The naming has evolved across three eras. **All three are sanctioned** — do not mass-rename older files to a newer scheme (it breaks cross-links + `git blame` for cosmetic gain). Rename a file only when its name asserts something **false** (e.g. `s9-6-artists-genres-years-design` → `…-artists-genres-design` after the Years tab was cut). New docs use the era that fits.

**Era 1 — old-numbering per-sprint records:** `{NN}-{feature}-{type}.md`
- **{NN}:** `00`–`09` numeric prefix (sorts naturally; avoids "Sprint 10 before Sprint 2"). This numbering is **frozen** — the forward plan restarted at `S6` (see the sprint-numbering note above; the old `06-sprint-6` is *not* the forward-plan S6).
- **{type}** ∈ `-plan` (implementation plan / AC) · `-test-plan` (QA strategy) · `-retro` (retrospective). Examples: `04-sprint-4-loudness-safety-plan.md`, `04-sprint-4-loudness-safety-retro.md`.

**Era 2 — forward S-series records:** `s{N}[.{sub}]-{feature}-{doctype}.md`
- Matches the forward `sprint-plan.md` numbering (`s6`, `s8-1`, `s9-5`, …). `{doctype}` in practice ∈ `-design` · `-plan` · `-test-plan` · `-findings` · `-procedure`. Examples: `s6-architecture-review-findings.md`, `s8-1-persistent-store-design.md`, `s9-5-songs-search-test-plan.md`.

**Era 3 — cross-sprint topical design docs:** `{feature}-{design|plan}.md`
- For designs not owned by a single sprint (GUI layout, controls). Examples: `layout-architecture-design.md`, `eq-controls-redesign.md`.

**Special files:** `sprint-plan.md` (authoritative forward schedule), `00-sprint-model.md` (methodology), `qw1-quick-win-differentiators-design.md` (the QW1 exception burst).

---

## Accessing Sprint Documentation

### In VSCode
File → Open → `docs/sprints/04-sprint-4-loudness-safety-plan.md`
Or: Ctrl+P (Quick Open) → type `04-sprint-4`

### Cross-references from other docs
Link format:
```markdown
See [Sprint 4 Implementation Plan](../sprints/04-sprint-4-loudness-safety-plan.md)
See [Sprint 4 Test Strategy](../sprints/04-sprint-4-loudness-safety-test-plan.md)
```

### In README
```markdown
## Active Sprint

**Sprint 4:** [Loudness Safety](docs/sprints/04-sprint-4-loudness-safety-plan.md)
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

**Last Updated:** 2026-07-12  
**Maintainer:** AdaptiveSound Team
