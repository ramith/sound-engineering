# Sprint Plan — AdaptiveSound

**Document ID:** SPRINT-PLAN-001
**Version:** 0.3 — added the architecture-review gate as the first sprint (2026-06-19); founder-reviewed.
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

**Shipped baseline (S6–S9):** bit-perfect Pure-Mode HAL + the Enhanced two-AU N-channel graph (≤7.1), 31-band live EQ, BS.1770 loudness + true-peak limiter, gapless + device-resilience, the QW1 differentiators (crossfeed · Reimagine-intensity · tonal presets), and the **GRDB-backed** library spine + full browse/search UI (Songs · Albums · Artists · Genres). Pipeline snapshot: [architecture.md](../architecture/architecture.md) §2.5.

**Still ahead (mapped to the schedule below):** parametric EQ + AutoEq device-correction (S12–S13), CUE + format hardening (S11), loudness compensation (S14), masking-aware Clarity + Arbiter + Realizer v1 (S15–S16), full Reimagine mapping (S17), BRIR spatial render (S18). **Open QA gap:** THD+N (the one S7 oracle not yet built). The perceptual `Realizer` scaffold and the steerable intensity anchor landed in S6/QW1; the `Clarity`/`BRIR` modules are still stubs.

---

## 3. Phase 1 — Player maturity / competitive parity

> **Exit criterion:** a listener can point us at their music folders and live in the app daily — browse, search, queue, play bit-perfect with art, tags, media keys, CUE albums, headphone correction, loudness compensation — on a QA gate we trust. **This is the GitHub release that earns the right to differentiate.**

**Execution order (founder decisions §8.2, §8.6):** **review and harden the architecture first** (gate — no implementation begins until it's green), then harden the QA gate (cheap, pure safety, must precede any DSP-touching work), then build the library spine as one focused block (the credibility critical path), then the sound-parity sprints.

> **Gate provenance (rationale kept; status is code+git):** **S6** arch-review gate — findings in [s6-architecture-review-findings.md](s6-architecture-review-findings.md), Tier-3 DSP-spine rework in [s6-tier3-spine-design.md](s6-tier3-spine-design.md). **S7** DSP-gate hardening — the six regression oracles. **QW1** differentiators (the founder-approved burst before S8) — [qw1-quick-win-differentiators-design.md](qw1-quick-win-differentiators-design.md); founder by-ear verification still pending. The DSP spine is confirmed Phase-2-ready, so S15→S16→S17 build directly on it.

| Sprint | Title | SP | Scope | Depends on |
|---|---|---|---|---|
| **S6** ✅ | Technical architecture review & hardening *(gate — §8.6)* | 8† | Multi-discipline review of the shipped codebase; RT-safety/lifecycle + concurrency consolidation + the Tier-3 DSP spine (`Realizer`, `RtSwappableResource`, steerable equal-power intensity with intensity-0 the bit-exact anchor, `GaplessController`). Confirmed the spine is Phase-2-ready. **Rationale:** [s6-architecture-review-findings.md](s6-architecture-review-findings.md), [s6-tier3-spine-design.md](s6-tier3-spine-design.md). | shipped codebase |
| **S7** ✅ | DSP-gate hardening | 8 | Regression oracles for every shipped DSP stage: libebur128 LUFS/TP, limiter −1 dBTP + ISP accuracy, 31-band EQ FR sweep + bit-transparent bypass, SRC alias/stopband, gapless-seam, RT-allocation soak (US-QA-01..06). **Open follow-up:** THD+N. | S6 |
| **S8** ✅ | Library spine: scan + persistent DB | 9 | Folder scan/watch, metadata + embedded-art, incremental rescan, persistent **GRDB**-backed store, art cache; S8.4 id-preserving move-match. Headless-gated by `VerifyLibraryStore`. **Forward:** Gate 1 (playlist filter, known-issues SEQ-1) stays open until **S10.1** ships the playlist table. | S6 |
| **S9** ✅ | Browse & search UI | 8 | Album grid + detail; Songs (filter-preserves-sort + customizable columns); Artists (tile grid) + Genres; FTS5 incremental search; queue/advance core (`PlaybackQueueKit`); cover art; a11y. *(Years tab cut.)* **Deferred → S10:** the A–Z jump rail (→ S10.5). *(drag-to-queue was routed to S10.2, then deprioritized 2026-07-14.)* | S8 |
| **S10.1** ✅ | Playlist/queue persistence spine | 8 | `playlists` + `playlist_entries` tables (GRDB, keyed on `tracks.id` + position); create/rename/delete + ordered-membership DAO; built-in non-deletable **"current"** queue playlist; `untitled-N` naming. **Closes Gate 1** (SEQ-1). `VerifyLibraryStore`-gated. | S8 |
| **S10.2** ✅ | Queue UX | 6 | Persistent play queue (the "current" playlist; survives quit/relaunch, restore-paused); Up Next｜History + session history; Clear Queue; reorder via grip-drag + context-menu + keyboard. *(drag-from-Library-into-queue deprioritized 2026-07-14.)* | S10.1 |
| **S10.3** ✅ | Playlists UX | 6 | Playlist browse/edit (create/rename/delete, scales to hundreds); add songs → playlist = **reference-add** (never a file move); add a single non-library file; the US-PLIST-08 move-survival seam test; dead/missing-file handling (skip-on-play + badge + Locate + remove-missing). Design: [s10-3-playlists-ux-design.md](s10-3-playlists-ux-design.md). *(M3U/M3U8 import-export deprioritized 2026-07-14. Shipped #59 core + #60 dead-files/checks.)* | S10.1 |
| **S10.4** ✅ | macOS system control | 5 | **Media keys + Now-Playing/Control Center** (`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`); Stop/Jump shortcuts; folds in the on-screen footer/mini-player metadata fix (same resolver) + loose-file embedded tags. Design: [s10-4-macos-system-control-design.md](s10-4-macos-system-control-design.md). *(Shipped #58.)* | S9 |
| ~~**S10.5**~~ ✂️ | Browse polish | ~~3~~ | **CUT 2026-07-17 (founder).** Folder-browse judged not a differentiator (effort goes elsewhere); the A–Z jump rail is an iOS-only pattern on macOS (type-to-select is the native affordance) — deep-research 2026-07-16 supported both calls. Kept as a row (annotated, not excised) per the docs rule. | — |
| **S10.6** ✅ | Recently Played (frecency) | 5 | Rework the S10.2 History tab → all-time, per-track, **frecency-ranked** "Recently Played": play count persisted (a play = **≥60% heard, ~4-min cap**), decayed-score accumulator column (`frecency_score`, schema v4, 7-day half-life), dedicated read + row. Design: [recently-played-frecency-design.md](recently-played-frecency-design.md). *(US-PLAY-10; enhancement, not an R1 gate. Shipped #57.)* | S10.2 |
| **S10.7** 🔨 | Liquid Glass release UX — Now Playing + shell | 6 | Adopt the founder-approved **8a "Liquid Glass"** design ([docs/design/now-playing-7a/](../design/now-playing-7a/README.md)) on the Now Playing tab + global shell: `DesignSystem.Glass` tokens (the foundation the WHOLE GUI redesigns around), app-wide dark-base re-tune, ambient content glows, analyzer lens (dB grid + peak-hold), hero title/badges, inspector as a trailing 260pt glass column, chrome + footer restyle. Both appearances; Reduce Transparency/Motion honored. Design: [s10-7-liquid-glass-design.md](s10-7-liquid-glass-design.md). ***R1-gating** — founder 2026-07-17: the current UX is elementary, not releasable; 8a IS the release UX.* | S10.3 |
| **S10.8** | Liquid Glass sweep — remaining tabs | 3 | Restyle Library, EQ, Monitoring, Settings with the S10.7-proven `Glass` tokens (surfaces/controls/type; **no layout redesigns** — those are post-R1 waves of the full Liquid-Glass GUI redesign). ***R1-gating** (founder 2026-07-17: nothing elementary ships).* | S10.7 |

*S10 expands into the `S10.x` done-done sprints above (~34 SP active after the S10.5 cut); each runs the full dev process. Sub-numbered `S10.x` to avoid renumbering S11–S18 and the R1/R2/R3 anchors. Breakdown: [s10-queue-playlists-macos-plan.md](s10-queue-playlists-macos-plan.md).*
| **S11** | CUE sheets + format hardening | 7 | External + embedded **CUE** → virtual tracks (reuse gapless); FLAC seektable/fast-seek verification; enable WavPack/APE if free via FFmpeg; full metadata-display panel; close **gapless Stage 2b** (lossy AAC/MP3 encoder-delay trim — US-PLAY-07). | S8, gapless |
| **S12** | Tonal parity + finish half-built | 9 | **Parametric EQ** bands alongside the 31-band graphic; **AutoEq/oratory1990 `ParametricEQ.txt` import**; **A/B LUFS-matched bypass** toggle. *(preset save/load per-output + Reimagine intensity-knob wiring were delivered early in QW1 — the latter closed the NFR-QUAL-03 demonstrability gap.)* | S7, EQ (have) |
| **S13** | Headphone + device parity | 7 | **device-correction EQ** auto-load by identified device; profile JSON import/export. *(crossfeed was delivered in QW1.)* | S7, S12 |
| **S14** | Loudness compensation (ISO-226) | 8 | Equal-loudness contour tilt driven by playback level/target SPL; ramped, capped (+12 dB default), no zipper; wires to the existing param bus/TargetState. *Pulled into Phase 1 (founder decision §8.4): it's a parity feature ("the loudness button") AND the lowest-risk first taste of the adaptive thesis — proving the adaptive platform within the parity release.* | S7, loudness infra (have) |

†S6 is review + fixes; it may spill beyond 8 SP if the review surfaces heavy structural issues — that's expected and acceptable, since the whole point is to fix the foundation before building on it.

*After the **S10.x** sprints we are already a credible daily-driver (minimum-credible release R1). S11–S14 add the audiophile-credible layer.*

**Phase 1 total:** ~103 SP (S10 expanded into sub-sprints S10.1–S10.8; S10.5 cut). Realistic to release in two waves (R1 after S10.1–S10.4 + **S10.7/S10.8 release UX**; S10.6 is an enhancement; R2 after S14).

**Critical path:** S6 (architecture gate) → S8 → S9 → **S10.1** (playlist/queue spine, also closes Gate 1) → S10.2/S10.3 → S10.4 — the architecture review gates everything; after it, the library/queue spine is the highest-leverage and most-underestimated stretch.

### Status

**S6–S10 functional gates ✅ COMPLETE (S10.3 fully shipped: #59 core + #60 dead-files/scanner-seam checks) · S10.5 ✂️ CUT · S10.7 Liquid Glass release UX 🔨 IN PROGRESS on `sprint/s10-7-liquid-glass` → S10.8 tab sweep → R1.** R1 was re-gated on the UX 2026-07-17 (founder): the pre-8a look is elementary and not releasable; the entire GUI will eventually redesign around Liquid Glass, with S10.7's `Glass` tokens as the foundation. Everything R1 gates on (S10.1 playlist/queue spine, S10.2 queue UX, S10.3 playlists UX incl. dead/missing-file handling + US-PLIST-08 real-scanner seam & scan-isolation checks, S10.4 macOS system control) is merged to main; S10.6 (Recently Played — frecency, #57) also shipped. **Playlist FOLDERS CUT 2026-07-16 (founder)** — the folder *data layer* (v5 migration + DAO + checks) shipped in #59 and stays DORMANT (re-enabling is free); no folders UI. **S10.5 browse polish CUT 2026-07-17 (founder)** — folder-browse not a differentiator; A–Z rail is an iOS pattern (macOS type-to-select is native). **Smart playlists** stay a post-R1 fast-follow. Deprioritized 2026-07-14 (founder): drag-from-Library-into-queue + M3U/M3U8 import-export (see [roadmap Deferred](../product/roadmap.md)). **Current work — S10.7:** adopt the 8a Liquid Glass design ([handoff](../design/now-playing-7a/README.md)) on Now Playing + the global shell per [s10-7-liquid-glass-design.md](s10-7-liquid-glass-design.md); founder-locked scope = Now Playing + shell, inspector = trailing 260pt glass column, transport stays in the footer, chrome stays a band. **This line is the single prose status surface for the project** — README/roadmap defer here; everything finer-grained lives in the source + git log (which are authoritative if they disagree with this).

---

## 4. Phase 2 — The strategic pivot (the Adaptive Sound thesis)

> Loudness compensation (S14) already delivered the lowest-risk adaptive feature and proved the platform. Phase 2 builds the perceptual core, enabler-first (per the sprint-model dependency graph), lowest-artifact-risk first. S12's PEQ + AutoEq import planted the "device-aware correction" seed — Phase 2 makes it *adaptive*.

| Sprint | Title | SP | Scope | Depends on |
|---|---|---|---|---|
| **S15** | SPIKE: masking model + arbitration | 7 | roex masking + Arbiter logic validation (enabler, not a shippable feature). De-risks the core thesis before building the Realizer. | DSP spine |
| **S16** | Clarity (masking-aware) — Arbiter + Realizer v1 | 9 | Arbiter logic → Realizer biquad fitting; the core perceptual differentiator. Conservative defaults; A/B vs bypass. | S15 |
| **S17** | Reimagine intensity (full mapping) | 6 | Map intensity 0→1 across loudness-comp + clarity (+ crossfeed) — the single steerable UX that ties the thesis together (beyond the on/off wiring done in S12). | S14, S16 |
| **S18** | SPIKE-BRIR + BRIR spatial render v1 | 9 | Binaural impulse-response spatial rendering; highest complexity/artifact risk → sequenced last. Independent spike chain, can run parallel to S16/S17. | DSP spine; SPIKE-BRIR |

**Phase 2 total:** ~31 SP across 4 sprints. **Critical path of the thesis:** S15 (spike) → S16 (Realizer); S17 ties it together.

---

## 5. Deferred

**Next wave, after R2 — gated on hardware:**

- **DSD playback (DoP + native)** — real L-sized work (DoP packing into the Pure HAL path, native-vs-DoP negotiation, DSD→PCM fallback). **Deferred past R2 (founder decision §8.3): no DSD DAC to verify by ear** — shipping an unhearable headline feature violates the by-ear verification workflow. First candidate for the post-R2 wave, gated on acquiring a DSD-capable DAC (same pattern as the pending Pure-mode USB-DAC verification).

**"Won't, this horizon"** — kept on the backlog as the future roadmap, out of this plan's window:

- **Stem separation / object engine (EP-STEM, Phase 1.5)** — high compute/artifact risk; revisit only after the mix-based thesis is validated and loved.
- **System-wide capture / virtual device (EP-SYSWIDE, EP-VDEVICE)** — different product surface; our story is *this Mac → this DAC, bit-perfect*.
- **Off-thesis player features:** streaming integration (Qobuz/Tidal — licensing, off-limits for non-commercial solo dev), CD ripping, DLNA/UPnP/multi-zone, SACD ISO.
- **Cheap P2 nice-to-haves** (tag editing/write-back, smart playlists, last.fm scrobbling, internet radio, sleep timer) — pull *opportunistically* into a polish mini-sprint if velocity allows, never as planned scope.

---

## 6. Backlog re-anchor — DONE

The one-time re-anchor this section mandated (back-fill shipped work as Done stories; tag EP-STEM/SYSWIDE/VDEVICE + DSD as "Won't, this horizon"; close the sprint-plan doc gap) has been executed — see [../product/backlog.md](../product/backlog.md) (now a forward backlog + a shipped-traceability index) and its change-log. The deviation flags it recorded (shipped EQ is 31-band not 10; signal-path transparency ≠ the unbuilt adaptation-transparency US-ADAPT-04; Opus replaced OGG) live in the backlog and are not restated here.

---

## 7. Release milestones & critical path

- **Gate:** S6 (architecture review & hardening) — **no feature sprint starts until this is green.**
- **Critical path:** S6 (gate) → S8 → S9 → **S10.1 → S10.2/S10.3 → S10.4** (queue/playlist spine + UX + system control). Everything browse/queue hangs off S8, the highest-leverage and most-underestimated stretch in the plan.
- **Release R1 ("a real player"):** after **S10.1–S10.4 + S10.7/S10.8** — daily-driver: library, browse, search, queue, playlists, media keys, bit-perfect playback, **in the 8a Liquid Glass release UX**. *(Functional gates shipped 2026-07-17; the founder then re-gated R1 on the UX: the pre-8a look is "elementary and not to be released." Long-term: the entire GUI redesigns around Liquid Glass — S10.7's `Glass` tokens are that foundation; post-R1 waves do per-tab layout redesigns.)*
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

**Last updated:** 2026-07-12 (docs-cleanup pass: done-narration thinned to pointers; §Status is now the single prose status surface; S10 next) · **Maintained by:** AdaptiveSound team · **Methodology:** [00-sprint-model.md](00-sprint-model.md) · **Backlog:** [../product/backlog.md](../product/backlog.md)
