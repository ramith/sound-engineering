# Adaptive Sound — documentation

A macOS music player for your own library — **bit-perfect playback first**, then **adaptive sound**: a perceptually-tuned, spatially-rendered mix you steer with one *Reimagine* control, on headphones and speakers. Personal / open-source. **R1 = v1.0.0-alpha** (shipped 2026-10-14 — [release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha), [release notes](releases/v1.0.0-alpha.md)).

*(Earlier wording promised a mix "you can steer in plain language" and a stem-aware player: natural-language tuning and hearing personalization were **cut** on 2026-07-12, and the stem engine is **won't, this horizon** — see the [roadmap](product/roadmap.md#deferred--out-of-window).)*

## Reading order

| # | Doc | What it is |
|---|---|---|
| 1 | [architecture/architecture.md](architecture/architecture.md) | **Canonical architecture** — start here. §2.5 is the shipped pipeline (reconciled to the code 2026-10-13, re-checked after R1 on 2026-10-14: the two output paths, the kernel's four paths, the Sprint EQ engine, the device model, the **app ↔ engine threading rules**); the rest is the target design (spine, signal model, stem engine, Reimagine knob, ADRs + locked decisions LD-*). |
| 2 | [product/PRD.md](product/PRD.md) | Vision, personas, positioning, locked decisions (LD-*), KPIs, risks — the *why*. (Its "Phase 0/1/1.5/2" is the product-capability axis; see the Phase Rosetta note in the PRD.) |
| 3 | [product/roadmap.md](product/roadmap.md) | High-altitude product arc, the post-R1 plan (R1.1 → the Engine sprint → R2) and the R1/R1.1/R2/R3 release milestones (defers detailed sequencing to sprint-plan.md). |
| 4 | [sprints/sprint-plan.md](sprints/sprint-plan.md) | **Authoritative forward schedule (S6–S18) — start here for "what's next."** Its §Status is the one prose status line. |
| 5 | [product/requirements.md](product/requirements.md) | Functional + non-functional requirements, adaptivity decision matrix, constraints/deps, the open-questions register. |
| 6 | [product/backlog.md](product/backlog.md) · [product/known-issues.md](product/known-issues.md) | Epics, user stories, spikes · the open known issues. |
| 7 | [sprints/](sprints/README.md) (+ [00-sprint-model.md](sprints/00-sprint-model.md)) | Sprint methodology + the per-sprint plans/designs/ledgers/retros (implementation provenance; rationale, not live status). |
| 8 | [design/](design/) | Design packages and studies: [Now Playing 7a/8a](design/now-playing-7a/README.md) → [Realigned Target](design/now-playing-realigned/README.md), [Library Twin Panels](design/library-twin-panels/README.md), [EQ "The Lens"](design/eq-lens/README.md) (shipped as Sprint EQ), and the [Adaptive Tone](design/adaptive-tone/README.md) proposal (not scheduled). |
| 9 | [development/DEVELOPMENT.md](development/DEVELOPMENT.md) · [architecture/validation-strategy.md](architecture/validation-strategy.md) | Build, test, tooling, coding standards · the validation gates. |
| 10 | [releases/](releases/v1.0.0-alpha.md) | Release notes (v1.0.0-alpha). |
| – | [reviews/](reviews/README.md) | The 2026-07 staged codebase review (Stages 1–6), and the **2026-10 product council** — [report](reviews/2026-10-council/README.md): its findings, the founder's decisions (FD-1…10) and the post-R1 re-plan, with the working papers. |
| – | [product/roadmap-reconciliation-2026-10/](product/roadmap-reconciliation-2026-10/README.md) | The **2026-10-23 sound-roadmap reconciliation** — four blind reviews of the plan against the source, the decision cards ranked by what the listener hears, and the founder's decisions (leveling in both modes at −18, the peak-safe turn-down and the headroom ledger, the fold and its LFE rule, the one EQ program and Compare, the bass-only loudness button, Intensity, one Headphones control, Enhance, the blind ladder): the record of *why*. The roadmap, sprint plan, backlog, requirements, architecture, [known issues](product/known-issues.md) and [validation strategy](architecture/validation-strategy.md#verifying-the-2026-10-23-sound-decisions) carry the *what*. |
| – | [architecture/main-thread-audio-audit-2026-10.md](architecture/main-thread-audio-audit-2026-10.md) + [evidence](architecture/evidence/main-thread-stall-2026-10/README.md) | The disconnect-freeze audit and review evidence (Sprint G, PR #86) — read before changing app ↔ engine threading. |
| – | [session-notes/](session-notes/) ; [architecture/](architecture/) surveys | Historical / superseded provenance (early engine/mix-core plans, [prior-art](session-notes/prior-art.md), [proposal-review](session-notes/proposal-review.md), postmortems, handoffs); plus decision-support surveys ([dsp-apple-silicon-survey.md](architecture/dsp-apple-silicon-survey.md), [audio-pipeline-stage-choices-review.md](architecture/audio-pipeline-stage-choices-review.md)) and the [EQ market research](product/eq-market-research.md). |

## Phasing at a glance (the PRD's product-capability axis)
- **Phase 0** — local-file player MVP (the DSP spine, passthrough → first DSP) — *shipped, and grown into the R1 player (library, queue, playlists, Pure Mode, the honest EQ)*
- **Phase 1** — mix-based core: perceptual clarity + correction + loudness-comp + adaptive engine + **BRIR immersion** + the **Reimagine** knob (mix range) — *mostly ahead: the Reimagine knob and crossfeed shipped early (QW1); correction S12–S13, loudness-comp S14, clarity / mapping / BRIR S15–S18*
- **Phase 1.5** — **stem-based object engine**: offline 6-stem separation, per-stem chains + spatial placement, between-stem unmasking (Reimagine knob, stem range) — *⛔ won't, this horizon*
- **Phase 2** — system-wide via Core Audio process taps (mix-level), virtual-device fallback — *⛔ won't, this horizon*

The sprint plan's "Phase 1 / Phase 2" is a different, **execution** axis (parity S6–S14 → the adaptive pivot S15–S18).

## Status
**Current status is the source + git, not this doc** — for what has shipped vs. what's next, see [sprints/sprint-plan.md](sprints/sprint-plan.md#status) (§Status + the forward schedule S6–S18). The DSP correctness gate is the C++ null-test golden-master harness (`bash scripts/build-null-test.sh`); `make gate` also runs `VerifyAUGraph` + `VerifyLibraryStore`; `make strict-gate` (CI on every PR) adds lint/format/semgrep, clang-tidy, Periphery, `swift test`, the sanitizers, leak detection and the main-thread stall self-test.

> **Note:** `architecture.md` describes both the shipped pipeline and the still-unbuilt design — design-only sections are banner-marked as such. Where a doc and the source disagree, the source wins.
