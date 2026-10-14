# AdaptiveSound product council: charter (agreed with the founder, 2026-10-13)

## Purpose
An honest, independent assessment of AdaptiveSound after R1 (v1.0.0-alpha) and before R2. It covers product,
sprint / process, architecture, roadmap, the coordinator's Claude memory, and a multi-stage code review.

## Ground truth
**The current code is the state of the product.** Documents describe the code, not the other way round.

## Outputs
1. **Code: review only.** Findings traced to their ROOT CAUSE, each with evidence (file:line), why it matters, the
   structural remedy, effort (S / M / L) and risk. Ranked into a plan of waves, with a decision list for the founder.
   No code changes until the founder decides.
2. **Documents: reconciled to the code, as ONE docs PR.**
   - Compare every product / roadmap / architecture / design doc with the code: PRD, requirements, user-journeys,
     roadmap, backlog, known-issues, sprint-plan, architecture.md, design docs. Each claim is matches / stale / wrong.
   - Rewrite them to describe the CURRENT state.
     - Reversed decisions are annotated, not deleted (the docs rule: code + git = status; docs carry the forward plan
       plus the non-recoverable rationale; sprint-plan §Status is the ONE prose status line).
     - Fix BACK-links (current feature → the design doc / sprint ledger / PR where and why it was decided) and
       FORWARD-links (current gap → the roadmap / backlog item that will close it), so requirement ↔ feature ↔ sprint
       ↔ PR traces both ways.
     - De-stale the roadmap: delivered, cut, superseded or overtaken items are updated.
   - Rule: where code and doc disagree and the CODE looks like a BUG (not a deliberate change), update the doc to
     describe the code AND raise the gap as a finding. Never silently rewrite a requirement to match broken code.

## The code review's bar: design maturity, NOT "it works" or "it passes lint"
1. **Architectural elegance, not brittle, not tactical.**
   - One owner per piece of state; dependencies flow one way; a few concepts reused consistently; rules enforced by
     TYPES and STRUCTURE, not by comments or convention.
   - Brittle = works only while unenforced assumptions hold (e.g. a resume point keyed by row index; a magic number
     copied into 3 places; queue-ordering rules living only in comments; a mock that claims to "match exactly" but
     has drifted; a state machine spread across 20 extension files with implicit transitions).
   - Tactical = patching a symptom where it showed up instead of its cause or the design (a flag to suppress a race
     instead of fixing ownership; special-casing one call site; sleeps / retries; "workaround" comments that became
     permanent; per-screen copies of the same logic, slightly different).
2. **Design patterns WHERE REQUIRED.** Recurring problems use the established pattern (e.g. an explicit state machine
   for transport; one publish / subscribe channel for engine state; strategy for decoders; repository for the store;
   command for transport requests). Flag missing patterns AND pattern-for-its-own-sake over-engineering.
3. **No duplicated code or functionality:** copy-paste logic, and also two ways of doing the same job (e.g. two
   playhead derivations, several device-volume paths, per-view copies of a control).
4. **Algorithmic correctness.** Every algorithm checked against a reference (literature / spec / an oracle) and
   PROVEN by tests:
   - DSP: the EQ solver, loudness, limiter, resampling, gapless seams;
   - non-DSP: folder-walk scheduling, frecency, transport epochs / snapshots, the render gate, device policy, the
     Master Gain law, identity / move-match.
5. **State of the art:** compared against OPENED sources (Apple docs / headers, SFBAudioEngine, Cog, VLC, JUCE,
   cubeb, GRDB docs, the literature) and modern practice (Swift 6 actors / structured concurrency / Synchronization;
   C++20/23 / the Core Guidelines). Dated approaches are flagged with the modern alternative.
6. **Maturity:** testability (logic reachable by tests without copying sources), explicit error handling, no "trust
   me" escapes (`@unchecked Sendable`, `nonisolated(unsafe)`, `assumeIsolated`) without a structural justification.

Drop lint-level nits. Severity: **STRUCTURAL** (a design flaw with wide blast radius) / **SIGNIFICANT** (a real
brittleness or correctness risk in one area) / **LOCAL** (contained).

## Stages
1. **Map**, plus docs ↔ code reconciliation, product, process and memory (in parallel).
2. Architecture review, plus area deep reviews against all six criteria.
3. The duplication pass (tool-assisted copy-paste plus semantic duplicated capability).
4. Algorithm-correctness panels (an adversarial breaker with its own prototype, plus a state-of-the-art challenger).
5. Cross-examination (architect plus pre-mortem challenger): drop the noise, merge duplicates, find the shared root causes.
6. Synthesis: the council report (`docs/reviews/2026-10-council/`), the re-planned roadmap, the founder's decision
   list, and the docs PR.

## Rules for every reviewer
- Read-only on Sources / Tests (a reviewer never edits code). Never launch the app or play audio. Never build in
  `/Users/ramith/code/sound-engineering` itself; use your own worktree if you must build.
- Ground claims in the code (file:line) and in OPENED sources (links).
- Don't re-report known items without new insight. See `docs/architecture/main-thread-audio-audit-2026-10.md`,
  `docs/architecture/evidence/main-thread-stall-2026-10/`, `docs/sprints/s10-8-g-breakit-*.md` and the "Logged
  post-R1" lists in `docs/sprints/s10-8-sweep-ledger.md`. Reference them instead.
- Skip any context-manager step.
