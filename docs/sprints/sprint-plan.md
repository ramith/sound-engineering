# Sprint Plan — AdaptiveSound

**Document ID:** SPRINT-PLAN-001
**Version:** 0.4 — reconciled to the code after R1 (product council, 2026-10-13): rows back-linked to PRs and ledgers, forward rows linked to backlog stories, delivered-early facts verified. No sprint was re-planned, re-ordered or re-scoped. *(0.3 — added the architecture-review gate as the first sprint, 2026-06-19; founder-reviewed.)*
**Status:** Active sprint schedule. Governed by [00-sprint-model.md](00-sprint-model.md) (methodology, done-done, enabler-first).
**Authored by:** AdaptiveSound team (PM + BA + architect + audio-DSP), synthesized and founder-reviewed.

> This is the authoritative **sprint schedule** the sprint model has referenced but never had. Sequencing reflects the founder's decisions of 2026-06-19 (§8).

---

## 1. Strategic frame — *maturity first, then differentiate*

**Founder's call (2026-06-19):** *"Prioritise any unfinished work and gaps, then strategically pivot toward the product vision. Without solid features and the maturity that exists in other players' projects, it's difficult to compete or rationalise our new differentiating features."*

This plan encodes that as a two-phase thesis:

- **Phase 1 — Player maturity / competitive parity.** Close the table-stakes gaps that mature audiophile players (Roon, Audirvana, foobar2000, JRiver) nail, finish the half-built features, harden the QA gate, and ship the lowest-risk adaptive feature (loudness compensation) as a parity-flavoured proof of the platform. Earn the right to be taken seriously as a *player*.
- **Phase 2 — The strategic pivot.** Build the differentiating *Adaptive Sound* thesis (masking-aware perceptual processing, steerable intensity, spatial) on top of a credible, mature base — where it can actually be compared and rationalised against the field.

The rationale is sound: **an audiophile player lives or dies on library + playback maturity, not on its cleverest DSP.** A listener who can't get an album into a queue never hears the differentiator. We reach parity, then we differentiate.

---

## 2. Where we are today

> **Current status is the source + git, not this prose** (see the §Status line under the table for the one-line "what shipped / what's next"). This section is the forward *gap list*, not a shipped-feature ledger.

**Shipped baseline (S6–S10.8, released as R1 = v1.0.0-alpha — release in progress):** bit-perfect Pure-Mode HAL + the Enhanced two-AU N-channel graph (≤7.1), BS.1770 loudness + true-peak limiter, gapless + device resilience, the QW1 differentiators (crossfeed · Reimagine-intensity knob · tonal presets), the **GRDB-backed** library spine + full browse/search UI (Songs · Albums · Artists · Genres), the queue / playlists / Recently Played / media keys (S10.1–S10.6), the **Liquid Glass** UI on every tab in dark and light (S10.7–S10.8), an **honest 31-band graphic EQ** that plays what it draws, loudness-neutral, with Tone controls, hold-to-Compare and per-output memory (Sprint EQ, PR #73), and the Sprint G output-device rule + app↔engine threading rules (PR #85, #86). Pipeline snapshot: [architecture.md](../architecture/architecture.md) §2.5. Release notes: [v1.0.0-alpha](../releases/v1.0.0-alpha.md).

**Still ahead (mapped to the schedule below):** CUE + format hardening (S11), parametric EQ + AutoEq import (S12), device-correction profiles (S13), loudness compensation (S14), masking-aware Clarity + Arbiter + perceptual Realizer v1 (S15–S16), full Reimagine mapping (S17), BRIR spatial render (S18). **Open QA gap:** THD+N (the one S7 oracle not yet built). The *control-plane* `Realizer` (S6, extended in Sprint EQ) and the steerable intensity blend landed in S6/QW1; the `Clarity`/`BRIR` kernel modules are still pass-through stubs, and the device-boundary spatial AU truncates a >2-channel source on a stereo output until the S18 binaural fold (council finding, see architecture §2.5).

**Logged after R1 (not yet scheduled — the council's re-planned roadmap will place them):** the "Logged post-R1" lists in the [S10.8 sweep ledger](s10-8-sweep-ledger.md#sprint-g--monitoring-then-close-out-g1-g2) (incl. the two Sprint G break-it reports, [library](s10-8-g-breakit-library.md) and [playback / shell](s10-8-g-breakit-playback-shell.md)), the [disconnect-freeze follow-ups](s10-8-sweep-ledger.md#founder-final-check-and-the-disconnect-freeze-2026-10-13), the parked app↔engine concurrency cleanup ([audit](../architecture/main-thread-audio-audit-2026-10.md)), and the open [known issues](../product/known-issues.md).

---

## 3. Phase 1 — Player maturity / competitive parity

> **Exit criterion:** a listener can point us at their music folders and live in the app daily — browse, search, queue, play bit-perfect with art, tags, media keys, CUE albums, headphone correction, loudness compensation — on a QA gate we trust. **This is the GitHub release that earns the right to differentiate.**

**Execution order (founder decisions §8.2, §8.6):** **review and harden the architecture first** (gate — no implementation begins until it's green), then harden the QA gate (cheap, pure safety, must precede any DSP-touching work), then build the library spine as one focused block (the credibility critical path), then the sound-parity sprints.

> **Gate provenance (rationale kept; status is code+git):** **S6** arch-review gate — findings in [s6-architecture-review-findings.md](s6-architecture-review-findings.md), Tier-3 DSP-spine rework in [s6-tier3-spine-design.md](s6-tier3-spine-design.md). **S7** DSP-gate hardening — the six regression oracles. **QW1** differentiators (the founder-approved burst before S8) — [qw1-quick-win-differentiators-design.md](qw1-quick-win-differentiators-design.md); founder by-ear verification still pending. The DSP spine is confirmed Phase-2-ready, so S15→S16→S17 build directly on it.

| Sprint | Title | SP | Scope | Depends on |
|---|---|---|---|---|
| **S6** ✅ | Technical architecture review & hardening *(gate — §8.6)* | 8† | Multi-discipline review of the shipped codebase; RT-safety/lifecycle + concurrency consolidation + the Tier-3 DSP spine (`Realizer`, `RtSwappableResource`, steerable equal-power intensity with intensity-0 the bit-exact anchor, `GaplessController`). Confirmed the spine is Phase-2-ready. **Rationale:** [s6-architecture-review-findings.md](s6-architecture-review-findings.md), [s6-tier3-spine-design.md](s6-tier3-spine-design.md). *(Merged with the 5b–S8 integration, PR #15.)* | shipped codebase |
| **S7** ✅ | DSP-gate hardening | 8 | Regression oracles for every shipped DSP stage: libebur128 LUFS/TP, limiter −1 dBTP + ISP accuracy, 31-band EQ FR sweep + bit-transparent bypass, SRC alias/stopband, gapless-seam, RT-allocation soak ([US-QA-01..06](../product/backlog.md)). *(PR #15.)* **Open follow-up:** THD+N — not built (no THD test in `Tests/`). | S6 |
| **S8** ✅ | Library spine: scan + persistent DB | 9 | Folder scan/watch, metadata + embedded-art, incremental rescan, persistent **GRDB**-backed store, art cache; S8.4 id-preserving move-match. Headless-gated by `VerifyLibraryStore`. *(S8.1–8.3 in PR #15, S8.4 in #17; store rebuilt on GRDB in #47–#49.)* Gate 1 (playlist filter, known-issues SEQ-1) — *closed by S10.1 (#53).* | S6 |
| **S9** ✅ | Browse & search UI | 8 | Album grid + detail; Songs (filter-preserves-sort + customizable columns); Artists (tile grid) + Genres; FTS5 incremental search; queue/advance core (`PlaybackQueueKit`); cover art; a11y. *(Years tab cut.)* **Deferred → S10:** the A–Z jump rail (→ S10.5, *cut 2026-07-17*). *(drag-to-queue was routed to S10.2, then deprioritized 2026-07-14.)* *(PRs #23, #28–#30, #33.)* | S8 |
| **S10.1** ✅ | Playlist/queue persistence spine | 8 | `playlists` + `playlist_entries` tables (GRDB, keyed on `tracks.id` + position); create/rename/delete + ordered-membership DAO; built-in non-deletable **"current"** queue playlist; `untitled-N` naming. **Closes Gate 1** (SEQ-1). `VerifyLibraryStore`-gated. Design: [s10-1-playlist-queue-store-design.md](s10-1-playlist-queue-store-design.md). *(Shipped #53.)* | S8 |
| **S10.2** ✅ | Queue UX | 6 | Persistent play queue (the "current" playlist; survives quit/relaunch, restore-paused); Up Next｜History + session history; Clear Queue; reorder via grip-drag + context-menu + keyboard. *(drag-from-Library-into-queue deprioritized 2026-07-14.)* Design: [s10-2-queue-ux-design.md](s10-2-queue-ux-design.md). *(Shipped #54.)* | S10.1 |
| **S10.3** ✅ | Playlists UX | 6 | Playlist browse/edit (create/rename/delete, scales to hundreds); add songs → playlist = **reference-add** (never a file move); add a single non-library file; the US-PLIST-08 move-survival seam test; dead/missing-file handling (skip-on-play + badge + Locate + remove-missing). Design: [s10-3-playlists-ux-design.md](s10-3-playlists-ux-design.md). *(M3U/M3U8 import-export deprioritized 2026-07-14. Shipped #59 core + #60 dead-files/checks.)* | S10.1 |
| **S10.4** ✅ | macOS system control | 5 | **Media keys + Now-Playing/Control Center** (`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`); Stop/Jump shortcuts; folds in the on-screen footer/mini-player metadata fix (same resolver) + loose-file embedded tags. Design: [s10-4-macos-system-control-design.md](s10-4-macos-system-control-design.md). *(Shipped #58.)* | S9 |
| ~~**S10.5**~~ ✂️ | Browse polish | ~~3~~ | **CUT 2026-07-17 (founder).** Folder-browse judged not a differentiator (effort goes elsewhere); the A–Z jump rail is an iOS-only pattern on macOS (type-to-select is the native affordance) — deep-research 2026-07-16 supported both calls. Kept as a row (annotated, not excised) per the docs rule. | — |
| **S10.6** ✅ | Recently Played (frecency) | 5 | Rework the S10.2 History tab → all-time, per-track, **frecency-ranked** "Recently Played": play count persisted (a play = **≥60% heard, ~4-min cap**), decayed-score accumulator column (`frecency_score`, schema v4, 7-day half-life), dedicated read + row. Design: [recently-played-frecency-design.md](recently-played-frecency-design.md). *(US-PLAY-10; enhancement, not an R1 gate. Shipped #57.)* | S10.2 |
| **S10.7** ✅ | Liquid Glass release UX — Now Playing + shell | 7 | Adopt the founder-approved **8a "Liquid Glass"** design ([docs/design/now-playing-7a/](../design/now-playing-7a/README.md)) on the Now Playing tab + global shell: `DesignSystem.Glass` tokens + `DesignTokenKit` (the foundation the WHOLE GUI redesigns around), app-wide dark-base re-tune (D10), ambient glows → **album-art-sampled** (D8), analyzer lens (dB grid + peak-hold), hero title/badges, inspector as a trailing 260pt glass column + queue filter (D7), chrome + footer restyle. Both appearances; Reduce Transparency/Motion/Increase Contrast honored. 8 incremental PRs (1a…7), founder screenshots per milestone. Design: [s10-7-liquid-glass-design.md](s10-7-liquid-glass-design.md) (SME panel + architect/fool gates folded; all decisions resolved 2026-07-17). ***R1-gating** — founder: the current UX is elementary, not releasable; 8a IS the release UX.* *(Closed 2026-07-19 — PR #61; retro [s10-7-retro.md](s10-7-retro.md); acceptance ledger [s10-7-visual-matrix.md](s10-7-visual-matrix.md).)* | S10.3 |
| **S10.8** ✅ | Liquid Glass sweep — remaining tabs | ~45 | Restyle Library, EQ, Monitoring, Settings with the S10.7-proven `Glass` tokens (surfaces/controls/type; **no new arrangements** — those are post-R1 waves of the full Liquid-Glass GUI redesign) **plus a designed light mode at full parity**. Re-estimated 2026-10-06 from 3 SP. ***R1-gating** (founder 2026-07-17: nothing elementary ships).* **Done (2026-10-13):** part 1, Now Playing polish — PR #62 ([plan](s10-8-deviations-plan.md), [realign ledger](s10-8-realign-ledger.md)); part 2, the Library "Twin Panels" — #63, founder rounds #65, #66 ([library ledger](s10-8-library-ledger.md)); then the seven sub-sprints of the [glass sweep plan](s10-8-glass-sweep-plan.md) (founder decisions 1–37 in its [§B](s10-8-glass-sweep-plan.md#b-decisions-founder)), each recorded in the [sweep ledger](s10-8-sweep-ledger.md): [A](s10-8-sweep-ledger.md#sprint-a--foundation) #68 · [B](s10-8-sweep-ledger.md#sprint-b--light-mode) #69 · [C](s10-8-sweep-ledger.md#sprint-c--album-artists-and-the-test-library) #70 · [behaviour pull-forward](s10-8-sweep-ledger.md#behaviour-pull-forward--keyboard-scroll-restore-playlist-moves-decisions-18-20) #71 · [D](s10-8-sweep-ledger.md#sprint-d--library-glass-d1d5-d6-shipped-in-the-pull-forward) #72 · [Sprint EQ](s10-8-sweep-ledger.md#sprint-eq--the-honest-31-point-eq-v1b-layout-decisions-2128) #73 · [E](s10-8-sweep-ledger.md#sprint-e--detail-pages-and-playlists-e2e4-e1-and-e4s-moves-shipped-in-the-pull-forward) #74 · [F](s10-8-sweep-ledger.md#sprint-f--glow-and-settings-f1-f2-f3f4-superseded-by-sprint-eq) #75 · [G](s10-8-sweep-ledger.md#sprint-g--monitoring-then-close-out-g1-g2) #85 (13 break-it blockers fixed; break-it reports [library](s10-8-g-breakit-library.md), [playback / shell](s10-8-g-breakit-playback-shell.md)) · the [disconnect freeze](s10-8-sweep-ledger.md#founder-final-check-and-the-disconnect-freeze-2026-10-13) #86 ([audit](../architecture/main-thread-audio-audit-2026-10.md), [evidence](../architecture/evidence/main-thread-stall-2026-10/README.md)). | S10.7 |

*S10 expands into the `S10.x` done-done sprints above (~82 SP active after the S10.5 cut and the S10.8 re-estimate; was ~34 before it); each runs the full dev process. Sub-numbered `S10.x` to avoid renumbering S11–S18 and the R1/R2/R3 anchors. Breakdown: [s10-queue-playlists-macos-plan.md](s10-queue-playlists-macos-plan.md).*

| Sprint | Title | SP | Scope | Depends on |
|---|---|---|---|---|
| **S11** | CUE sheets + format hardening | 7 | External + embedded **CUE** → virtual tracks (reuse gapless); FLAC seektable/fast-seek verification; enable WavPack/APE if free via FFmpeg; full metadata-display panel; close **gapless Stage 2b** (lossy AAC/MP3 encoder-delay trim — [US-PLAY-07](../product/backlog.md)). *(Code fact, 2026-10-13: AAC/MP3 decode through Apple on both paths, whose edit list already trims priming — `FileDecodeSource.cpp:7-11`, `AudioEngineBridge+Gapless.swift:39-42`; what remains open is the FFmpeg fallback's trim (Opus/Vorbis pre-skip) and a seam test proving AAC/MP3. No CUE story in the backlog yet. No CUE code exists.)* | S8, gapless |
| **S12** | Tonal parity + finish half-built | 9 | **Parametric EQ** bands alongside the 31-band graphic; **AutoEq/oratory1990 `ParametricEQ.txt` import**; **A/B LUFS-matched bypass** toggle. Forward: [US-TON-02](../product/backlog.md) (+ SPIKE-DEVCORRLIB), [US-PROF-02](../product/backlog.md). *(Delivered early: preset save/load per-output + Reimagine intensity-knob wiring in QW1 — the latter closed the NFR-QUAL-03 demonstrability gap; re-voiced built-in presets, user presets and per-output pins rebuilt in Sprint EQ (#73, decisions 27–32); **hold-to-Compare = hear the song without the EQ at matched loudness** (Sprint EQ decision 28, `UI/EQ/EQCompareButton.swift`) — the EQ's A/B; whether S12 still owes a whole-chain A/B is open. No parametric or AutoEq code exists.)* | S7, EQ (have) |
| **S13** | Headphone + device parity | 7 | **device-correction EQ** auto-load by identified device; profile JSON import/export. Forward: [US-TON-02](../product/backlog.md), [US-DEVICE-02 / -04 / -05](../product/backlog.md). *(Delivered early: crossfeed in QW1; the **auto-load-by-identified-output mechanism** in Sprint EQ — per-output EQ pins with a model-UID fallback (`EQEditKit/EQOutputPin.swift`, decision 28) — so what remains is the correction *profiles* and their JSON import/export.)* | S7, S12 |
| **S14** | Loudness compensation (ISO-226) | 8 | Equal-loudness contour tilt driven by playback level/target SPL; ramped, capped (+12 dB default), no zipper; wires to the existing param bus/TargetState. Forward: [US-TON-03](../product/backlog.md). *(Not started: no ISO-226 / equal-loudness code exists.)* *Pulled into Phase 1 (founder decision §8.4): it's a parity feature ("the loudness button") AND the lowest-risk first taste of the adaptive thesis — proving the adaptive platform within the parity release.* | S7, loudness infra (have) |

†S6 is review + fixes; it may spill beyond 8 SP if the review surfaces heavy structural issues — that's expected and acceptable, since the whole point is to fix the foundation before building on it.

*After the **S10.x** sprints we are already a credible daily-driver (minimum-credible release R1). S11–S14 add the audiophile-credible layer.*

**Phase 1 total:** ~146 SP (S10 expanded into sub-sprints S10.1–S10.8; S10.5 cut; S10.8 re-estimated 3 → ~45 SP on 2026-10-06 — the figure was ~103 before it). Realistic to release in two waves (R1 after S10.1–S10.4 + **S10.7/S10.8 release UX**; S10.6 is an enhancement; R2 after S14).

**Critical path:** S6 (architecture gate) → S8 → S9 → **S10.1** (playlist/queue spine, also closes Gate 1) → S10.2/S10.3 → S10.4 — the architecture review gates everything; after it, the library/queue spine is the highest-leverage and most-underestimated stretch.

### Status

**S6–S10 ✅ COMPLETE · S10.5 ✂️ CUT · S10.7 ✅ (#61) · S10.8 ✅ (#62–#86: Now Playing polish, the Library Twin Panels, sub-sprints A–G incl. Sprint EQ, the G fixes and the disconnect freeze) → R1 = v1.0.0-alpha — release in progress.** The release PR (#87, app version 1.0.0, `make dist`, a tag-triggered release workflow with build provenance) merged 2026-10-13; the `v1.0.0-alpha` tag waits on a green CI (no `v*` tag exists yet). Notes: [docs/releases/v1.0.0-alpha.md](../releases/v1.0.0-alpha.md). **Next:** the post-R1 product council (2026-10-13) reviews the product, the code and this roadmap; any re-plan of S11–S18 is a founder decision from its report — until then the forward schedule above and below stands, S11 first.

Founder decisions that shaped R1 (rationale kept; detail in the linked records): R1 was **re-gated on the UX** 2026-07-17 — the pre-8a look is elementary and not releasable; the whole GUI will redesign around Liquid Glass, with S10.7's `Glass` tokens as the foundation, and S10.8 then swept every tab onto them with a designed light mode ([glass sweep plan §B](s10-8-glass-sweep-plan.md#b-decisions-founder), decisions 1–37; decision 18 = the lighter routine). **Playlist FOLDERS CUT 2026-07-16** — the folder *data layer* (v5 migration + DAO + checks) shipped in #59 and stays DORMANT (re-enabling is free); no folders UI. **S10.5 browse polish CUT 2026-07-17** — folder-browse not a differentiator; the A–Z rail is an iOS pattern (macOS type-to-select is native). **Smart playlists** stay a post-R1 fast-follow. **Deprioritized 2026-07-14:** drag-from-Library-into-queue + M3U/M3U8 import-export (see [roadmap Deferred](../product/roadmap.md)). **The EQ was redesigned in full before R1** (decision 21; Sprint EQ, #73). **The broader app↔engine concurrency cleanup** is agreed but **parked** after the disconnect-freeze fix ("freeze fix only, decide later"). **This line is the single prose status surface for the project** — README/roadmap defer here; everything finer-grained lives in the source + git log (which are authoritative if they disagree with this).

---

## 4. Phase 2 — The strategic pivot (the Adaptive Sound thesis)

> By Phase 2, loudness compensation (S14) will have delivered the lowest-risk adaptive feature and proved the platform, and S12's PEQ + AutoEq import will have planted the "device-aware correction" seed — Phase 2 makes it *adaptive*. Phase 2 builds the perceptual core, enabler-first (per the sprint-model dependency graph), lowest-artifact-risk first. *(None of S12–S18 has started as of R1. Already in place for it: the control-plane `Realizer`, the steerable intensity blend and the `Clarity`/`BRIR` module slots (pass-through stubs) in the kernel, and the load-time track analysis from Sprint EQ — architecture §2.5. Cut from the thesis 2026-07-12: natural-language tuning and hearing personalization — [roadmap](../product/roadmap.md#deferred--out-of-window).)*

| Sprint | Title | SP | Scope | Depends on |
|---|---|---|---|---|
| **S15** | SPIKE: masking model + arbitration | 7 | roex masking + Arbiter logic validation (enabler, not a shippable feature). De-risks the core thesis before building the Realizer. Forward: SPIKE-MASKING-MODEL, [US-PERC-01](../product/backlog.md). Design: [architecture §4](../architecture/architecture.md#4-the-signal-model--typed-contributors-perceptual-decisions-ld-12). | DSP spine |
| **S16** | Clarity (masking-aware) — Arbiter + Realizer v1 | 9 | Arbiter logic → Realizer biquad fitting; the core perceptual differentiator. Conservative defaults; A/B vs bypass. Forward: [US-PERC-02, US-PERC-03](../product/backlog.md). | S15 |
| **S17** | Reimagine intensity (full mapping) | 6 | Map intensity 0→1 across loudness-comp + clarity (+ crossfeed) — the single steerable UX that ties the thesis together (beyond the knob wiring delivered early in QW1). Forward: [US-RMG-02](../product/backlog.md), SPIKE-REIMAGINE-MAP. | S14, S16 |
| **S18** | SPIKE-BRIR + BRIR spatial render v1 | 9 | Binaural impulse-response spatial rendering; highest complexity/artifact risk → sequenced last. Independent spike chain, can run parallel to S16/S17. Also replaces the spatial AU's interim M < N channel truncation with the binaural fold ([S4 design](05-sprint-5b-s4-binaural-design.md)). Forward: SPIKE-BRIR, [US-SPAT-01 / -03](../product/backlog.md). | DSP spine; SPIKE-BRIR |

**Phase 2 total:** ~31 SP across 4 sprints. **Critical path of the thesis:** S15 (spike) → S16 (Realizer); S17 ties it together.

---

**Planned, not yet scheduled — EP-MCP agent control surface (founder, 2026-10-13):**
- **What:** every player function exposed through a local MCP server, so an LLM client (Claude, OpenClaw, any MCP
  client) can drive the app: transport, queue, library, playlists, EQ / sound, output / Pure, and state.
- **Placement and size:** set by the 2026-10 council.
- **Depends on:** one command / state API shared with the UI (the transport command layer and the engine event
  channel).
- **Backlog:** [EP-MCP](../product/backlog.md#ep-mcp--agent-control-surface-mcp); roadmap
  [Agent control surface](../product/roadmap.md).

---

## 5. Deferred

**Next wave, after R2 — gated on hardware:**

- **DSD playback (DoP + native)** — real L-sized work (DoP packing into the Pure HAL path, native-vs-DoP negotiation, DSD→PCM fallback). **Deferred past R2 (founder decision §8.3): no DSD DAC to verify by ear** — shipping an unhearable headline feature violates the by-ear verification workflow. First candidate for the post-R2 wave, gated on acquiring a DSD-capable DAC (same pattern as the pending Pure-mode USB-DAC verification).

**"Won't, this horizon"** — kept on the backlog as the future roadmap, out of this plan's window:

- **Stem separation / object engine (EP-STEM, Phase 1.5)** — high compute/artifact risk; revisit only after the mix-based thesis is validated and loved.
- **System-wide capture / virtual device (EP-SYSWIDE, EP-VDEVICE)** — different product surface; our story is *this Mac → this DAC, bit-perfect*.
- **Generative re-imagination of old recordings** (keep the recorded voice, regenerate the backing — research in `research/reimagine-poc/`) — a research direction, not planned scope.
- **Off-thesis player features:** streaming integration (Qobuz/Tidal — licensing, off-limits for non-commercial solo dev), CD ripping, DLNA/UPnP/multi-zone, SACD ISO.
- **Cheap P2 nice-to-haves** (tag editing/write-back, smart playlists, last.fm scrobbling, internet radio, sleep timer) — pull *opportunistically* into a polish mini-sprint if velocity allows, never as planned scope. *(Smart playlists were since named a post-R1 fast-follow — §Status.)*

**Cut from scope (not deferred):** natural-language / conversational tuning and hearing personalization (founder, 2026-07-12; LD-8 / ADR-009 withdrawn); playlist folders UI (2026-07-16; data layer dormant); S10.5 browse polish (2026-07-17). **Deprioritized:** drag-from-Library-into-queue, M3U/M3U8 import-export (2026-07-14). Detail: [roadmap Deferred](../product/roadmap.md#deferred--out-of-window).

---

## 6. Backlog re-anchor — DONE

The one-time re-anchor this section mandated (back-fill shipped work as Done stories; tag EP-STEM/SYSWIDE/VDEVICE + DSD as "Won't, this horizon"; close the sprint-plan doc gap) has been executed — see [../product/backlog.md](../product/backlog.md) (now a forward backlog + a shipped-traceability index) and its change-log. The deviation flags it recorded (shipped EQ is 31-band not 10; signal-path transparency ≠ the unbuilt adaptation-transparency US-ADAPT-04; Opus replaced OGG) live in the backlog and are not restated here.

---

## 7. Release milestones & critical path

- **Gate:** S6 (architecture review & hardening) — **no feature sprint starts until this is green.**
- **Critical path:** S6 (gate) → S8 → S9 → **S10.1 → S10.2/S10.3 → S10.4** (queue/playlist spine + UX + system control). Everything browse/queue hangs off S8, the highest-leverage and most-underestimated stretch in the plan.
- **Release R1 ("a real player") = v1.0.0-alpha — release in progress** (PR #87 merged 2026-10-13; tag pending a green CI; [notes](../releases/v1.0.0-alpha.md)): after **S10.1–S10.4 + S10.7/S10.8** — daily-driver: library, browse, search, queue, playlists, media keys, bit-perfect playback, **in the 8a Liquid Glass release UX**. *(Functional gates shipped 2026-07-17; the founder then re-gated R1 on the UX: the pre-8a look is "elementary and not to be released." Long-term: the entire GUI redesigns around Liquid Glass — S10.7's `Glass` tokens are that foundation; post-R1 waves do per-tab layout redesigns.)*
- **Release R2 ("audiophile-credible"):** after **S14** — CUE, format hardening, PEQ/AutoEq, presets, crossfeed, device correction, loudness compensation, QA gate green. **This is the parity milestone that unlocks Phase 2.**
- **Release R3 ("differentiated"):** after **S17** — Clarity + steerable Reimagine. The Adaptive Sound thesis, demonstrable and comparable.

**One opinionated recommendation (PM + BA agree):** do **not** start Phase 2 until S8–S10 ship and you've lived on the app as your daily player for a week. The adaptive DSP is more fun than catalog plumbing — resist jumping early. The differentiators only earn attention once the table-stakes are invisible-because-they-just-work.

---

## 8. Decisions (founder review, 2026-06-19)

1. **Doc home & numbering** — keep this as `docs/sprints/sprint-plan.md`, continue sprint numbering at **S6**. (Closes the referenced-but-missing doc gap; `roadmap.md` stays the high-altitude view.)
2. **Track sequencing** — **architecture-review gate first (S6), then QA-gate (S7), then library as a focused block (S8–S10), then sound-parity sprints (S11–S14).** Foundation hardened and safety net in place before any feature/DSP work, without fragmenting the library critical path.
3. **DSD** — **deferred past R2**, gated on acquiring a DSD DAC. Keeps every R2 feature by-ear verified.
4. **Loudness compensation** — **pulled forward into Phase 1 (S14)** as a parity feature + lowest-risk taste of the adaptive thesis.
5. **Competitor research** — commission feature-level teardowns per-sprint, the week each feature is built. (A separate positioning narrative can run in the background anytime.)
6. **Architecture-review gate (added 2026-06-19)** — a **technical architecture review of the shipped codebase is the first & foremost sprint (S6)**, before any implementation; its findings are fixed before S7+ begins. Rationale: harden the foundation and confirm the DSP spine supports the Phase 2 adaptive vision before building eight sprints of features on it. This pushed the prior S6–S17 down by one to S7–S18.

---

**Last updated:** 2026-10-13 (product-council reconciliation to the code after R1: S10.7/S10.8 closed with back-links, R1 = v1.0.0-alpha in progress, forward rows linked to backlog stories, delivered-early facts verified; no re-plan) · *previous: 2026-07-12 docs-cleanup pass* · **Maintained by:** AdaptiveSound team · **Methodology:** [00-sprint-model.md](00-sprint-model.md) · **Backlog:** [../product/backlog.md](../product/backlog.md)
