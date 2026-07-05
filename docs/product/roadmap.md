# Adaptive Sound — Product Roadmap
## Phase Timeline & Release Plan

**Status:** 🟢 IN ACTIVE DEVELOPMENT
**Last Updated:** 2026-07-05
**Strategy:** *Player-maturity first → differentiate later* (founder-reviewed 2026-06-19)
**Release model:** GitHub releases R1 → R2 → R3, effort-driven (no calendar pressure)

> **This is the high-altitude product view.** The authoritative, detailed sprint sequence lives in [../sprints/sprint-plan.md](../sprints/sprint-plan.md) (S6–S18). Where the two overlap, sprint-plan.md wins.

---

## Strategy in one paragraph

An audiophile player lives or dies on **library + playback maturity, not on its cleverest DSP** — a listener who can't get an album into a queue never hears the differentiator. So we **reach competitive parity as a player first** (Phase 1), then build the differentiating *Adaptive Sound* thesis — masking-aware perceptual clarity, steerable Reimagine, spatial rendering — on top of a credible base where it can actually be compared against the field (Phase 2). Our anchor story is *this Mac → this DAC, bit-perfect* (which Apple Music is not, on macOS). See [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §1.

---

## What's shipped (verified against code)

- **Sprint 4 — Loudness safety (✅ Shipped, merged):** BS.1770-5 loudness meter + true-peak limiter (8× ISP) with active LUFS normalization.
- **Sprint 5 / 5b — EQ + multichannel (✅ Shipped):** live 31-band UI-driven EQ (drag the response curve, ±12 dB, kernel-clamped), N-channel two-AU Enhanced graph (≤7.1, EQ → loudness → limiter → spatial-passthrough), Monitoring tab.
- **Bit-perfect "Pure Mode" + gapless (✅ Shipped — pipeline-review additions):** CoreAudio HAL-direct output (hog mode, per-track sample-rate match, DSP bypassed), runtime FFmpeg-or-Apple decode (FLAC/ALAC/WAV/AIFF/Opus/MP3/AAC), gapless (Enhanced full + Pure same-rate), auto-advance, device-resilience + pin/follow, signal-path transparency UI.
- **S6 — Architecture-review gate (✅ Shipped):** 4-discipline review + Tier 1/2/3 fixes — control-plane `Realizer`, steerable equal-power wet/dry intensity (intensity-0 = bit-exact anchor), `RtSwappableResource`, `GaplessController` contract. Gate green.
- **S7 — DSP-gate hardening (✅ Shipped):** regression oracles for every shipped DSP stage — libebur128 loudness/TP, limiter −1 dBTP, 31-band EQ FR sweep, SRC alias/imaging, gapless-seam, RT-allocation soak.
- **QW1 — Quick-Win Differentiators (✅ Shipped — code; founder by-ear pending):** crossfeed DSP + UI (headphone-gated), Reimagine intensity knob UI, tonal presets (house curves + Save-as-Custom + per-output recall).

**Current focus → 🟡 S8, the library spine.** The single biggest gap between us and a mature player: today we are a flat playlist/folder player with no persistent library, browse, search, or cover-art grid. The spine has largely landed — folder scan + persistent store + identity/FS-divergence/move-match (`LibraryScan`, `LibraryStore`), headless-gated by `VerifyLibraryStore`. The next user-facing step is the browse UI (S9).

---

## Phase 1 — Player maturity / competitive parity (S8–S14)

**Exit criterion:** a listener can point the app at their music folders and live in it daily — browse, search, queue, play bit-perfect with art / tags / media keys, CUE albums, headphone correction, loudness compensation — on a QA gate we trust. This is the GitHub release that earns the right to differentiate.

| Sprint | Scope | Status |
|--------|-------|--------|
| **S8** | **Library spine: scan + persistent DB** | **🟡 In progress** |
| S9 | Browse & search UI — album grid; Artist/Album/Genre/Year; incremental search; cover art; click-to-queue | Planned |
| S10 | Queue + playlists + macOS control — queue/history, M3U import-export, media keys + Now-Playing/Control Center | Planned |
| S11 | CUE sheets + format hardening — CUE→virtual tracks, FLAC fast-seek, WavPack/APE, lossy gapless trim | Planned |
| S12 | Tonal parity — parametric EQ + AutoEq/oratory1990 import + A/B LUFS-matched bypass | Planned |
| S13 | Headphone + device parity — device-correction EQ auto-load + profile JSON import/export | Planned |
| S14 | Loudness compensation (ISO-226) — the lowest-risk first taste of the adaptive thesis | Planned |

*(Preset save/load, the Reimagine intensity-knob wiring, and crossfeed — originally scoped in S12/S13 — were delivered early in QW1.)*

---

## Phase 2 — The Adaptive Sound differentiation (S15–S18)

Built on the mature base, enabler-first, lowest-artifact-risk first. This is the thesis that no static competitor (including Apple's ASAF) can match — it adapts every buffer to content, level, device, and hearing.

| Sprint | Scope | Status |
|--------|-------|--------|
| S15 | SPIKE: masking model + arbitration (roex + Arbiter logic; de-risks the thesis) | Planned |
| S16 | Clarity (masking-aware) — Arbiter + Realizer v1; the core perceptual differentiator | Planned |
| S17 | Reimagine intensity — full mapping (0→1 across loudness-comp + clarity + crossfeed) | Planned |
| S18 | SPIKE-BRIR + BRIR spatial render v1 — highest artifact risk → sequenced last | Planned |

---

## Release milestones (per [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §7)

| Release | After | Theme | Content |
|---------|-------|-------|---------|
| **R1 — "a real player"** | S10 | Daily-driver | Library, browse, search, queue, media keys, bit-perfect playback |
| **R2 — "audiophile-credible"** | S14 | Parity (unlocks Phase 2) | CUE, format hardening, PEQ/AutoEq, presets, crossfeed, device correction, loudness compensation, QA gate green |
| **R3 — "differentiated"** | S17 | The thesis | Clarity + steerable Reimagine — demonstrable and comparable |

**Critical path:** S6 (gate, done) → S8 → S9 → S10 (library spine). Everything browse/queue hangs off S8 — the highest-leverage and most-underestimated stretch in the plan.

**Opinionated guardrail (PM + BA agree):** do not start Phase 2 until S8–S10 ship and the app has been the daily driver for a week. The adaptive DSP is more fun than catalog plumbing — the differentiators only earn attention once the table-stakes are invisible-because-they-just-work.

---

## Deferred / out-of-window

- **DSD playback (DoP + native)** — deferred past R2, gated on acquiring a DSD DAC (keeps every feature by-ear verifiable).
- **"Won't, this horizon"** — kept on the [backlog](backlog.md) as future vision, out of this plan's window:
  - **Natural-language / conversational tuning** — the vision's endgame; needs the full adaptive stack (S14–S18) to have anything to steer.
  - **Stem separation / object engine (Phase 1.5)** — high compute/artifact risk; revisit only after the mix-based thesis is validated and loved.
  - **System-wide capture / virtual device (Phase 2 system-wide)** — a different product surface; our story stays *this Mac → this DAC, bit-perfect*.
  - Off-thesis player features (streaming integration, CD ripping, DLNA/UPnP/multi-zone, SACD ISO) and cheap nice-to-haves (tag write-back, smart playlists, scrobbling, sleep timer) — opportunistic only, never planned scope.

---

## Validation framework

Three pillars: automated per-merge gates + DSP regression oracles + founder by-ear/by-hand verification.

- **Per-merge gate (`make gate`):** the C++ null-test (golden master `0xE7267654BA01D315`, bit-exact bypass @ intensity 0), `VerifyAUGraph`, and `VerifyLibraryStore`. ASAN/TSan/clang-tidy clean. *(The DSP correctness gate is the C++ null-test golden-master; `swift test` (native swift-testing) also runs headless in `make strict-gate`. See [../sprints/README.md](../sprints/README.md).)*
- **DSP oracles (S7):** libebur128 loudness/TP, limiter −1 dBTP, 31-band EQ FR sweep, SRC alias/imaging, gapless-seam, RT-allocation soak.
- **By-ear / by-hand:** the founder owns audible/visual checks; Pure-path + QW1 by-ear verification is pending a USB DAC.

Details: [../architecture/validation-strategy.md](../architecture/validation-strategy.md).

---

## Cross-references

- **Detailed sprint sequence (authoritative "what's next"):** [../sprints/sprint-plan.md](../sprints/sprint-plan.md)
- **Sprint methodology & historical records:** [../sprints/00-sprint-model.md](../sprints/00-sprint-model.md), [../sprints/README.md](../sprints/README.md)
- **Architecture, locked decisions & ADRs:** [../architecture/architecture.md](../architecture/architecture.md)
- **Product requirements & vision:** [PRD.md](PRD.md), [requirements.md](requirements.md)
- **Backlog & stories:** [backlog.md](backlog.md)
- **QA framework:** [../architecture/validation-strategy.md](../architecture/validation-strategy.md)

---

**Status:** 🟢 In active development
**Next step:** 🟡 **S8 — the library spine** (scan + persistent store → S9 browse/queue), the credibility critical path toward release **R1**. Adaptive clarity, the full Reimagine mapping, and BRIR spatial are Phase 2 (S15–S18), not next. Detailed sequencing: [../sprints/sprint-plan.md](../sprints/sprint-plan.md).
