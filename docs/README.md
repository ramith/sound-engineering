# Adaptive Sound — documentation

A macOS app that turns good-quality music into a **personal, perceptually-tuned, spatially-rendered mix you can steer in plain language** — immersive on headphones & speakers, adaptive, and (in its own player) stem-aware. Personal / open-source.

## Reading order

| # | Doc | What it is |
|---|---|---|
| 1 | [architecture/architecture.md](architecture/architecture.md) | **Canonical architecture (v0.3)** — start here. Spine, signal model, stem engine, Reimagine knob, ADRs (001–011), locked decisions (LD-1…19). |
| 2 | [product/PRD.md](product/PRD.md) | Vision, personas, positioning, phased roadmap, locked decisions (LD-1…LD-17), KPIs, risks. |
| 3 | [product/requirements.md](product/requirements.md) | Functional + non-functional requirements, user journeys, adaptivity decision matrix, assumptions/constraints/dependencies, open questions. |
| 4 | [product/backlog.md](product/backlog.md) | Epics, user stories, spikes, draft sprint sequencing. |
| 5 | [product/roadmap.md](product/roadmap.md) | Phase/sprint timeline + status. |
| 6 | [sprints/](sprints/) | Per-sprint plans, designs, and retros (the implementation record, Sprints 4–9). |
| 7 | [development/DEVELOPMENT.md](development/DEVELOPMENT.md) | Build, test (the C++ null-test harness gate), and coding-standard notes. |
| – | [session-notes/](session-notes/) | Historical / superseded reference (kept for provenance): early engine/mix-core plans, design reviews ([prior-art](session-notes/prior-art.md), [proposal-review](session-notes/proposal-review.md), [proposal](session-notes/proposal.md)), postmortems, handoffs. |

## Phasing at a glance
- **Phase 0** — local-file player MVP (the DSP spine, passthrough → first DSP)
- **Phase 1** — mix-based core: perceptual clarity + correction + loudness-comp + adaptive engine + **BRIR immersion** + natural-language control + the **Reimagine** knob (mix range)
- **Phase 1.5** — **stem-based object engine**: offline 6-stem separation, per-stem chains + spatial placement, between-stem unmasking (Reimagine knob, stem range)
- **Phase 2** — system-wide via Core Audio process taps (mix-level), virtual-device fallback

## Status
**Active development** (branch `feat/sprint-5-eq-wiring`). Shipped so far: the player MVP + DSP spine (Sprints 0–3), loudness safety (Sprint 4, merged), the EQ foundation + N-channel multichannel pipeline + Monitoring tab (Sprint 5/5b), a bit-perfect **Pure Mode** HAL output path with runtime FFmpeg-or-Apple decode, and **gapless / continuous playback** (Enhanced + Pure same-rate) with device-resilience. The DSP gate is the C++ null-test harness (`bash scripts/build-null-test.sh`); `swift test` is currently broken (toolchain skew) — Swift tests run in Xcode. Phase 1 enhancement features (perceptual clarity/Arbiter, BRIR immersion, NL control, the Reimagine knob) and the Phase 1.5 stem engine are designed but not yet built. Personal / open-source; OSS license deferred to post-MVP.

> **Note:** `architecture.md` describes both the shipped pipeline and the still-unbuilt design — sections that are design-only are marked as such. See [sprints/](sprints/) for what has actually landed.
