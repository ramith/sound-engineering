# Adaptive Sound — Product Roadmap
## Phase Timeline & Release Plan

**Strategy:** *Player-maturity first → differentiate later* (founder-reviewed 2026-06-19)
**Release model:** GitHub releases R1 → R2 → R3, effort-driven (no calendar pressure). **R1 = v1.0.0-alpha — shipped 2026-10-14** ([release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha); see [sprint-plan §Status](../sprints/sprint-plan.md#status)). The 2026-10 council's re-planned roadmap is still to come; until the founder decides on it, the arc below stands.

> **This is the high-altitude product view.** The authoritative, detailed sprint sequence — and the only place that narrates **what has shipped vs. what's next** — is [../sprints/sprint-plan.md](../sprints/sprint-plan.md) (S6–S18) + the source/git. Where the two overlap, sprint-plan.md wins.
>
> **Phase vocabulary:** this roadmap's **Phase 1 / Phase 2** is the *execution / release* axis (player-maturity parity → differentiation pivot). The PRD's **Phase 0 / 1 / 1.5 / 2** is a different, *product-capability* axis — see the Rosetta note in [PRD.md](PRD.md).

---

## Strategy in one paragraph

An audiophile player lives or dies on **library + playback maturity, not on its cleverest DSP** — a listener who can't get an album into a queue never hears the differentiator. So we **reach competitive parity as a player first** (Phase 1), then build the differentiating *Adaptive Sound* thesis — masking-aware perceptual clarity, steerable Reimagine, spatial rendering — on top of a credible base where it can actually be compared against the field (Phase 2). Our anchor story is *this Mac → this DAC, bit-perfect* (which Apple Music is not, on macOS). See [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §1.

---

## Phase 1 — Player maturity / competitive parity (S8–S14)

**Exit criterion:** a listener can point the app at their music folders and live in it daily — browse, search, queue, play bit-perfect with art / tags / media keys, CUE albums, headphone correction, loudness compensation — on a QA gate we trust. This is the GitHub release that earns the right to differentiate.

| Sprint | Scope |
|--------|-------|
| S8 | Library spine: scan + persistent DB |
| S9 | Browse & search UI — album grid; Artist/Album/Genre; incremental search; cover art; click-to-queue |
| S10 *(runs as S10.1–S10.8; S10.5 cut)* | Queue + playlists + macOS control — queue, recently-played (frecency), media keys + Now-Playing/Control Center (S10.1–S10.6) — plus the **Liquid Glass release UX** (S10.7 Now Playing + shell, S10.8 every other tab + light mode, which also carried the full EQ redesign, "Sprint EQ"). Split into individual sub-sprints — see [sprint-plan.md](../sprints/sprint-plan.md) + [s10 plan](../sprints/s10-queue-playlists-macos-plan.md). *(M3U/M3U8 import-export deferred — see below.)* |
| S11 | CUE sheets + format hardening — CUE→virtual tracks, FLAC fast-seek, WavPack/APE, lossy gapless trim |
| S12 | Tonal parity — parametric EQ + AutoEq/oratory1990 import + A/B LUFS-matched bypass |
| S13 | Headphone + device parity — device-correction EQ auto-load + profile JSON import/export |
| S14 | Loudness compensation (ISO-226) — the lowest-risk first taste of the adaptive thesis |

*(Delivered early: preset save/load, the Reimagine intensity-knob wiring and crossfeed — originally scoped in S12/S13 — in the QW1 differentiators burst; the EQ's loudness-matched hold-to-Compare and per-output EQ memory in Sprint EQ (S10.8). Detail and the code facts per sprint: [sprint-plan §3](../sprints/sprint-plan.md#3-phase-1--player-maturity--competitive-parity).)*

---

## Phase 2 — The Adaptive Sound differentiation (S15–S18)

Built on the mature base, enabler-first, lowest-artifact-risk first. This is the thesis that no static competitor (including Apple's ASAF) can match — it adapts every buffer to content, level and device. *("…and hearing" removed: hearing personalization was cut 2026-07-12 — see Deferred.)*

| Sprint | Scope |
|--------|-------|
| S15 | SPIKE: masking model + arbitration (roex + Arbiter logic; de-risks the thesis) |
| S16 | Clarity (masking-aware) — Arbiter + Realizer v1; the core perceptual differentiator |
| S17 | Reimagine intensity — full mapping (0→1 across loudness-comp + clarity + crossfeed) |
| S18 | SPIKE-BRIR + BRIR spatial render v1 — highest artifact risk → sequenced last |

---

## Release milestones (per [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §7)

| Release | After | Theme | Content |
|---------|-------|-------|---------|
| **R1 — "a real player"** = **v1.0.0-alpha** *(✅ shipped 2026-10-14)* | S10.1–S10.4 + S10.7/S10.8 (release UX) + the council's R1 blocker fixes (PR #88) | Daily-driver | Library, browse, search, queue, playlists, media keys, bit-perfect playback, in the Liquid Glass UI (dark + light) with the honest 31-band EQ — [release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha), [release notes](../releases/v1.0.0-alpha.md) |
| **R2 — "audiophile-credible"** | S14 | Parity (unlocks Phase 2) | CUE, format hardening, PEQ/AutoEq, presets, crossfeed, device correction, loudness compensation, QA gate green |
| **R3 — "differentiated"** | S17 | The thesis | Clarity + steerable Reimagine — demonstrable and comparable |

**Critical path:** S6 (gate) → S8 → S9 → S10.1–S10.4 (queue/playlist spine + UX + system control) → S10.7/S10.8 (the release UX R1 was re-gated on, 2026-07-17). Everything browse/queue hangs off S8 — the highest-leverage and most-underestimated stretch in the plan.

**Opinionated guardrail (PM + BA agree):** do not start Phase 2 until S8–S10 ship and the app has been the daily driver for a week. The adaptive DSP is more fun than catalog plumbing — the differentiators only earn attention once the table-stakes are invisible-because-they-just-work.

---

## Planned, placement pending — Agent control surface (MCP) *(founder, 2026-10-13)*

**Expose ALL of the player's functionality through a local [MCP](https://modelcontextprotocol.io) server**, so an
LLM client (Claude Desktop / Claude Code, the open-source agent [OpenClaw](https://bigdataboutique.com/what-is-openclaw),
or any MCP client) can drive AdaptiveSound: transport, queue, library search and browse, playlists, EQ and sound
settings, output devices and Pure Mode, and read the player's state.

- **One command layer, two front ends.** MCP tools call the SAME command / state API as the UI, never a second
  path. That makes it depend on the 2026-10 council's transport command / reducer and engine-event work.
- **Local and consented.** Off by default; enabled in Settings; local only (stdio or localhost); per-client scopes
  (read-only / control / library-modify); destructive operations confirmed; hearing-safety clamps enforced
  server-side for every client.
- **Placement:** decided by the 2026-10 council, after the command-layer refactor wave. Backlog:
  [EP-MCP](backlog.md#ep-mcp--agent-control-surface-mcp).
- **Relationship to the 2026-07-12 cut:** in-app conversational tuning stays cut. This is an *external* control
  surface. An LLM adjusting the EQ through MCP is a consequence the founder confirms explicitly (council decision list).

## Deferred / out-of-window

- **Removed from scope (2026-07-12, founder decision):** **natural-language / conversational tuning** and **hearing personalization** (hearing-test → profile → compensation) were cut from the vision entirely — not deferred, removed. May be re-added later. Prior specs are in git history.
- **Deprioritized (2026-07-14, founder decision):** **drag-from-Library-into-queue** and **playlist file import/export (M3U/M3U8)** — judged not useful enough to plan now. Not removed from the vision; revisit opportunistically post-R1. Add-to-queue is already covered by the Play Next / Add to Queue verbs; playlist portability (M3U) can return if a real need appears. R1 no longer depends on either.
- **Cut 2026-07-16 / 2026-07-17 (founder):** the playlist-folders UI (its data layer shipped and stays dormant) and S10.5 browse polish (folder-browse; the A–Z rail). **Smart playlists** are a post-R1 fast-follow. Detail: [sprint-plan §Status](../sprints/sprint-plan.md#status).
- **DSD playback (DoP + native)** — deferred past R2, gated on acquiring a DSD DAC (keeps every feature by-ear verifiable).
- **"Won't, this horizon"** — kept on the [backlog](backlog.md) as future vision, out of this plan's window:
  - **Stem separation / object engine (Phase 1.5)** — high compute/artifact risk; revisit only after the mix-based thesis is validated and loved.
  - **System-wide capture / virtual device (Phase 2 system-wide)** — a different product surface; our story stays *this Mac → this DAC, bit-perfect*.
  - **Generative re-imagination of old recordings** — a research direction (`research/reimagine-poc/`), not planned scope.
  - Off-thesis player features (streaming integration, CD ripping, DLNA/UPnP/multi-zone, SACD ISO) and cheap nice-to-haves (tag write-back, smart playlists, scrobbling, sleep timer) — opportunistic only, never planned scope.

- **Proposals awaiting a founder decision (not on the schedule):** *Adaptive Tone* — read-ahead per-song tone suggestions steered by "better / not" ([design study, 2026-10-10](../design/adaptive-tone/README.md)); it overlaps the S15–S17 adaptive thesis and has not been placed.

---

## Validation framework

Three pillars: automated per-merge gates + DSP regression oracles + founder by-ear/by-hand verification.

- **Per-merge gate (`make gate`):** the C++ null-test (golden master `0xE7AF0C67F9340785` since Sprint EQ — was `0xE7267654BA01D315`; bit-exact bypass at intensity 0 with the EQ flat or off), `VerifyAUGraph`, and `VerifyLibraryStore`. **`make strict-gate`** (CI on every PR) adds format/lint/semgrep, clang-tidy, Periphery, `swift test` (native swift-testing), ASan/UBSan/TSan, leak detection and the `make main-thread-stall` self-test. *(The DSP correctness gate is the C++ null-test golden-master. See [../sprints/README.md](../sprints/README.md).)*
- **DSP oracles (S7):** libebur128 loudness/TP, limiter −1 dBTP, 31-band EQ FR sweep, SRC alias/imaging, gapless-seam, RT-allocation soak. *(THD+N: not built.)*
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

**For current status and "what's next," see [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §Status + the source/git.** This roadmap intentionally does not track per-sprint state — it is the high-altitude arc (Phase 1 parity → Phase 2 differentiation, R1 → R2 → R3).
