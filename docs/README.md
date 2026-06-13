# Adaptive Sound — documentation

A macOS app that turns good-quality music into a **personal, perceptually-tuned, spatially-rendered mix you can steer in plain language** — immersive on headphones & speakers, adaptive, and (in its own player) stem-aware. Personal / open-source.

## Reading order

| # | Doc | What it is |
|---|---|---|
| 1 | [architecture/architecture.md](architecture/architecture.md) | **Canonical architecture (v0.3)** — start here. Spine, signal model, stem engine, Reimagine knob, ADRs (001–011), locked decisions (LD-1…19). |
| 2 | [product/PRD.md](product/PRD.md) | Vision, personas, positioning, phased roadmap, locked decisions (LD-1…LD-17), KPIs, risks. |
| 3 | [product/requirements.md](product/requirements.md) | Functional + non-functional requirements, user journeys, adaptivity decision matrix, assumptions/constraints/dependencies, open questions. |
| 4 | [product/backlog.md](product/backlog.md) | Epics, user stories, spikes, draft sprint sequencing. |
| 5 | [architecture/prior-art.md](architecture/prior-art.md) | License-verified reuse-vs-build research + native-first stack + patent watch. |
| 6 | [architecture/proposal-review.md](architecture/proposal-review.md) | The 4-reviewer panel review that drove v0.2. |
| – | [architecture/proposal.md](architecture/proposal.md) | v0.1 proposal — **superseded** by architecture.md (kept for provenance). |

## Phasing at a glance
- **Phase 0** — local-file player MVP (the DSP spine, passthrough → first DSP)
- **Phase 1** — mix-based core: perceptual clarity + correction + loudness-comp + adaptive engine + **BRIR immersion** + natural-language control + the **Reimagine** knob (mix range)
- **Phase 1.5** — **stem-based object engine**: offline 6-stem separation, per-stem chains + spatial placement, between-stem unmasking (Reimagine knob, stem range)
- **Phase 2** — system-wide via Core Audio process taps (mix-level), virtual-device fallback

## Status
Pre-development / architecture defined. Personal / open-source; OSS license deferred to post-MVP.
