# Adaptive Sound — documentation

A macOS app that turns good-quality music into a **personal, perceptually-tuned, spatially-rendered mix you can steer in plain language** — immersive on headphones & speakers, adaptive, and (in its own player) stem-aware. Personal / open-source.

## Reading order

| # | Doc | What it is |
|---|---|---|
| 1 | [architecture/architecture.md](architecture/architecture.md) | **Canonical architecture** — start here. Spine, signal model, stem engine, Reimagine knob, ADRs + locked decisions (LD-*). |
| 2 | [product/PRD.md](product/PRD.md) | Vision, personas, positioning, locked decisions (LD-*), KPIs, risks — the *why*. (Its "Phase 0/1/1.5/2" is the product-capability axis; see the Phase Rosetta note in the PRD.) |
| 3 | [product/roadmap.md](product/roadmap.md) | High-altitude product arc + the R1/R2/R3 release milestones (defers detailed sequencing to sprint-plan.md). |
| 4 | [sprints/sprint-plan.md](sprints/sprint-plan.md) | **Authoritative forward schedule (S6–S18) — start here for "what's next."** |
| 5 | [product/requirements.md](product/requirements.md) | Functional + non-functional requirements, adaptivity decision matrix, constraints/deps, the open-questions register. |
| 6 | [product/backlog.md](product/backlog.md) | Epics, user stories, spikes. |
| 7 | [sprints/](sprints/) (+ [00-sprint-model.md](sprints/00-sprint-model.md)) | Sprint methodology + the per-sprint plans/designs/retros (implementation provenance; rationale, not live status). |
| 8 | [development/DEVELOPMENT.md](development/DEVELOPMENT.md) | Build, test (the C++ null-test harness gate), and coding-standard notes. |
| – | [session-notes/](session-notes/) ; [architecture/](architecture/) surveys | Historical / superseded provenance (early engine/mix-core plans, [prior-art](session-notes/prior-art.md), [proposal-review](session-notes/proposal-review.md), postmortems, handoffs); plus live decision-support surveys ([dsp-apple-silicon-survey.md](architecture/dsp-apple-silicon-survey.md)). |

## Phasing at a glance
- **Phase 0** — local-file player MVP (the DSP spine, passthrough → first DSP)
- **Phase 1** — mix-based core: perceptual clarity + correction + loudness-comp + adaptive engine + **BRIR immersion** + the **Reimagine** knob (mix range)
- **Phase 1.5** — **stem-based object engine**: offline 6-stem separation, per-stem chains + spatial placement, between-stem unmasking (Reimagine knob, stem range)
- **Phase 2** — system-wide via Core Audio process taps (mix-level), virtual-device fallback

## Status
**Active development** (branch `main`). Personal / open-source; OSS license deferred to post-MVP. **Current status is the source + git, not this doc** — for what has shipped vs. what's next, see [sprints/sprint-plan.md](sprints/sprint-plan.md) (§Status + the forward schedule S6–S18). The DSP correctness gate is the C++ null-test golden-master harness (`bash scripts/build-null-test.sh`); `make gate` also runs `VerifyAUGraph` + `VerifyLibraryStore`; the Swift suites run headless via `swift test` inside `make strict-gate`.

> **Note:** `architecture.md` describes both the shipped pipeline and the still-unbuilt design — design-only sections are banner-marked as such. Where a doc and the source disagree, the source wins.
