# Adaptive Sound — Product Roadmap
## Phase Timeline & Release Plan

**Strategy:** *Player-maturity first → differentiate later* (founder-reviewed 2026-06-19)
**Release model:** GitHub releases R1 → R2 → R3 *(R1.1 added between R1 and R2, 2026-10-14)*, effort-driven (no calendar pressure). **R1 = v1.0.0-alpha — shipped 2026-10-14** ([release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha); see [sprint-plan §Status](../sprints/sprint-plan.md#status)). **Re-planned 2026-10-14** from the founder's decisions on the 2026-10 product council ([council report](../reviews/2026-10-council/README.md)): **R1.1 → the Engine sprint → R2 in a new order** — see [The post-R1 plan](#the-post-r1-plan-council-2026-10-14). ~~The 2026-10 council's re-planned roadmap is still to come; until the founder decides on it, the arc below stands.~~

> **This is the high-altitude product view.** The authoritative, detailed sprint sequence — and the only place that narrates **what has shipped vs. what's next** — is [../sprints/sprint-plan.md](../sprints/sprint-plan.md) (S6–S18) + the source/git. Where the two overlap, sprint-plan.md wins.
>
> **Phase vocabulary:** this roadmap's **Phase 1 / Phase 2** is the *execution / release* axis (player-maturity parity → differentiation pivot). The PRD's **Phase 0 / 1 / 1.5 / 2** is a different, *product-capability* axis — see the Rosetta note in [PRD.md](PRD.md).
>
> **IDs used below:** **C-xx** are rows of the council's finding register ([`stage5-architect.md` §1](../reviews/2026-10-council/working/stage5-architect.md#1-finding-register)); **FD-x** are the founder's decisions of 2026-10-14 ([council report §5](../reviews/2026-10-council/README.md#5-the-founders-decisions-2026-10-14)); **KI-** / **DEV-** / **LIB-VOL-** are [known issues](known-issues.md); **US-** / **EP-** are [backlog](backlog.md) stories and epics.

---

## Strategy in one paragraph

An audiophile player lives or dies on **library + playback maturity, not on its cleverest DSP** — a listener who can't get an album into a queue never hears the differentiator. So we **reach competitive parity as a player first** (Phase 1), then build the differentiating *Adaptive Sound* thesis — masking-aware perceptual clarity, steerable Reimagine, spatial rendering — on top of a credible base where it can actually be compared against the field (Phase 2). Our anchor story is *this Mac → this DAC, bit-perfect* (which Apple Music is not, on macOS). See [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §1.

**After R1 (founder, 2026-10-14):** make the default experience faithful, durable and honest first (R1.1), then build our own playback engine in a sprint of its own, then ship the R2 features, each carrying only the restructuring it needs. No standalone refactor waves (FD-1).

---

## The post-R1 plan (council, 2026-10-14)

**Recommendation, adopted by the founder:** fix what the listener hears and loses first; then replace the Enhanced engine's internals with our own engine, measured against a mature one; then features.

```
R1 (shipped) → R1.1-A → R1.1-B → Engine sprint → R2: S14-lite → S12 → S13 → S11-lite → R3: S15 → S16 → S17 (S18 last)
                                  (R1.1 is the daily driver)   each R2 sprint carries its own structural slice
EP-MCP: after W2 (one playback owner) + the command layer, R2 or later (FD-8)
```

Why this order, in short (detail in the [council report §6](../reviews/2026-10-council/README.md#6-the-plan)):
- **R1.1 first (FD-1).** A fresh launch plays processed sound, Master Gain comes back at its loudest, and dragging the scrubber to the end of a 44.1 kHz track stops the music. Each is small, and each is something the founder meets every day.
- **The Engine sprint next (FD-4).** The Enhanced path's gaps, clicks, early title changes and seek hang share one root: it hands its queue to `AVAudioPlayerNode` and re-derives position from callbacks (council RC-2). The founder chose to study SFBAudioEngine, build our own engine with that knowledge, and compare the two before deciding.
- **R2 in the product's order.** S14 is the cheapest proof of "adaptive"; S12 and S13 are table stakes for enthusiasts; S11 is format breadth, which matters least for the founder's own library.

### R1.1-A: faithful, durable, honest

Time-box: **at most 2 weeks**, small (S) items only; anything bigger moves to R1.1-B or into its slice. Every fix lands with its breaker's red test as a regression test on the real code (C-85; C-80 for the transport tests).

| # | Item | Council row | Known issue | Backlog |
|---|---|---|---|---|
| 1 | **A faithful default** (FD-2): Intensity 0, leveling off, EQ off at a fresh launch. Intensity is hidden until its effects are real (S17) | C-41 (takes C-38, C-39, C-40 off the default path) | KI-SND-01 | US-R1F-09 |
| 2 | **Remember the listener's settings** (FD-2): Pure, Master Gain (never restored louder than it was left), crossfeed, shuffle / repeat, the chosen output device. Switching Enhanced → Pure never raises the level unseen | C-102, C-12, C-29 (slice) | KI-SET-01, KI-SET-02, DEV-1 | US-R1F-05 |
| 3 | **Seek to the end ends the track**: a seek that commits only when it succeeds, with a finiteness check | C-25 | KI-PB-18 (HIGH) | US-R1F-11 |
| 4 | **Apple's Mastering-quality converter** for Enhanced sample-rate conversion (measured flat to 21 kHz, aliases ≤ −160 dB, bit-exact at equal rates — [engine-research §1](../reviews/2026-10-council/working/engine-research.md#1-new-measurements-avaudioengines-own-sample-rate-conversion-offline-probes)), with a passband / stopband gate (≤ 0.1 dB to 20 kHz, ≤ −100 dB) that fails when it should | C-26, R-6 | KI-SND-02 | US-R1F-11 |
| 5 | **Transport correctness**: Stop is numbered at once, the bridge drops stale commands, a starting / pausing state exists; an append during a start's prime is armed, the next pick is recomputed after queue edits, Play Next works by slot | C-15, C-17 | KI-PB-19, KI-PB-20, KI-PB-04, KI-PB-06, KI-PB-07, KI-PB-08, KI-PB-09, KI-PB-10 | US-R1F-01 |
| 6 | **Audible DSP**: the limiter's dual release made real; a bs2b-faithful crossfeed, with headphones detected by data source (the built-in jack counts); a per-track "Integrated" readout and analysis workers that idle while paused; scoped flush-to-zero. *(C-40, the Intensity blend, waits until Intensity returns.)* | C-39, C-42, C-30 (slice), C-46, C-50 | KI-SND-03, KI-SND-04, KI-DEV-01, KI-UI-03 | US-R1F-12, US-R1F-06 |
| 7 | **Pure honesty**: the reason Pure declined is shown in the UI; "not bit-perfect" when the device's bit depth is lower; the Settings copy matches when the Pure switch takes effect | C-34, C-33 | KI-PB-05 | US-R1F-13 |
| 8 | **FFmpeg as an opt-in** (FD-3): off by default, a setting turns it on, loaded only from fixed absolute paths (no bare-name lookup); the metadata scan uses it only when it is on; its seek honours the stream start. Scan `.opus` / `.oga` (Apple decodes them natively on macOS 26), with a format-table test | C-99, C-08 (scanner half), C-35 | KI-SEC-01, KI-LIB-05 | US-R1F-16 |
| 9 | **Library safety and search**: "Remove Missing" respects paused or unreachable folders (HIGH, data loss); a scan refusal covers only the unreadable subfolder, and "paused" is shown; no empty-list flash on reload; search tokenizes by Unicode category and normalises to NFC (Sinhala, NFD) | C-56 (the KI slice, no tombstone), C-55, C-58, C-61 (slice) | KI-LIB-01 (HIGH), KI-LIB-02, KI-LIB-11 | US-R1F-03, US-R1F-04, US-R1F-14 |
| 10 | **Live readouts**: the spectrum's level (+4.26 dB high today), an FFT size per sample rate, and its hand-off race; timers that stop when nothing plays or shows; a scrubber and meters that don't keep VoiceOver busy | C-51, C-52, C-53 | KI-UI-02, KI-ENG-01, KI-UI-01 | US-R1F-15 |
| 11 | **Hygiene**: dead code and placeholders; the effects render block's nil-pull guard; stale contracts, comments and scripts | C-86, C-87, C-88 | KI-ENG-03 | US-R1F-07 |

### R1.1-B: the decided medium items

Time-box: **at most 2 weeks**. Each item is medium-sized and was settled by a founder decision or a council default.

| # | Item | Council row | Known issue | Backlog |
|---|---|---|---|---|
| 1 | **ITU-R BS.775 fold-down** for 5.1 / 7.1 on a narrower output (FD-9): channel roles from the file's channel labels first, a safety ceiling after the spatial stage, the loudness weights fixed. S18's binaural render later replaces it in the same slot. *It bends the "no naive downmix" rule until then: a standard matrix at the device boundary, where today's truncation drops four channels* | C-43, C-44, C-45 | KI-MC-01, KI-MC-02 (HIGH) | US-R1F-08 |
| 2 | **Shuffle as a permutation with history**: each song once per pass, Previous walks back, Repeat off ends the queue | C-16 | KI-PB-03 | US-R1F-01 |
| 3 | **One search rule and a global ⌘F** (ranked prefix search, Unicode-correct, the same in every tab) | C-61 | KI-LIB-09 | US-R1F-14 |
| 4 | **Atomic queue restore**: the place in the queue survives a crash or force-quit; one coalescing writer | C-65 | KI-PB-21 | US-R1F-01 |
| 5 | **Loose files**: Open…, drop on the app, Open With; add a non-library file to a playlist | C-69 | (known limitation) | US-LIB-02, US-PLIST-02 |
| 6 | **"Use this drive"**: rebind a paused folder to its drive without losing plays, loved or ratings (founder: "later, via the council list") | C-54 | LIB-VOL-1 | US-R1F-03 |
| 7 | **Leveling as its own setting** (FD-2): Off / Album / Track, from the existing per-track analysis; off by default | C-38 | — | US-R1F-10 |

**Then:** R1.1 becomes the founder's daily driver. The guardrail below ("live on it for a week before the next phase") applies to R1.1; the Engine sprint gives that week.

### Where everything else went

- **The Engine sprint** (FD-4): the gapless and scheduling internals — C-07, C-14 / F1 seam identity (KI-PB-16, KI-PB-17), C-21 (KI-GAP-01), C-22 (KI-GAP-04), C-23 (KI-GAP-02), C-24 (KI-GAP-05), C-28 (KI-DEV-03), C-36, C-37, C-48, C-08 (one probe / decode path), C-04's bounded-source half, ENH-001, KI-GAP-03, KI-PB-02. Backlog: US-R1F-02, [EP-PLAYENGINE](backlog.md#ep-playengine--the-engine-sprint).
- **Release readiness, deferred** (FD-7): C-10 (diagnostics), C-101 (playlist export and backup), C-103 (licence file, notarization, clean-Mac first run). Backlog: US-REL-01…05.
- **Not adopted:** "CI is the only gate" (C-83's rule; FD-6); the `missing_since` tombstone (C-56's second layer) and the 100k-song performance gate (C-60) (FD-10).
- **Parked until hardware** (FD-5): Pure pause as a device teardown (C-100, KI-PURE-01), the HAL device-state contract (C-31), the USB-DAC check, the virtual-DAC rig.
- **Post-R1.1 pool** (small, no lane; each rides with the next change that touches its code): C-19 (KI-PB-14), C-20, C-32, the C-57 slices, C-68, C-71, C-74, C-76, C-79, and the logged known issues not listed above (KI-PB-11, -12, -13, -15; KI-LIB-03, -04, -06, -07, -08, -10; KI-EQ-01, -02, -03; KI-DEV-02; KI-SET-03; KI-ENG-02, -04; ENH-002). KI-EQ-01 (unpin overwrites the shared EQ) is the first candidate if a lane has room: it destroys user edits.

### The Engine sprint

**Goal:** one owner of the Enhanced audio timeline, written by us with the knowledge of a mature open-source engine, and proven better — or not — by measurement before it ships. **Placed after R1.1 and before R2** (FD-4). It is the founder's one named exception to FD-1's "no standalone refactor": a sprint of its own, still under finish-or-revert.

1. **Discovery.** Clone SFBAudioEngine (MIT; pinned to the version the council read, 0.14.0 at 9ed712d), read it as data outside the repo's build, and analyse it at code level against our Enhanced path: the decode-ahead ring, gapless and format-change joins, seek, device and configuration changes, threading, events, sample-rate conversion. Write down where **our** implementation can improve, each tied to a council row. Design the new module's interface.
2. **Build our own engine** as its own SwiftPM module behind a clean interface. Enhanced first: a pull model (`AVAudioSourceNode` over Pure's proven C++ decode and gapless pipeline), the explicit Mastering converter from R1.1, our two audio units unchanged. Designed so Pure's decode can share it later. It lands behind a developer switch; today's path stays the default.
3. **Compare, then decide.** A code-level comparison (size, threading model, test surface, dependencies, licences) and the **11 measured checks** of [engine-research §5](../reviews/2026-10-council/working/engine-research.md#5-recommendation-and-spike-plan-refines-stage5-architect-45) (P1–P11: SRC, our units in the graph, same-format gapless, format-change joins, seek, threads, device change, formats, Pure decode sharing, supply chain, real-time robustness), on both engines where each applies. The founder decides: our engine, SFBAudioEngine, or today's path with the R1.1 fixes. The losing path is removed; two engines never ship.

**Guardrails:** agents never play audio — checks that need ears or a device plugged in (P7, part of P11) are the founder's; no engine call on the main thread (the PR #86 rule); Pure's HAL output is unchanged (FD-5). **Not in it:** crossfade, CUE parsing, Pure output changes. **Backlog:** [EP-PLAYENGINE](backlog.md#ep-playengine--the-engine-sprint).

### R2: features, each carrying its slice

| Order | Sprint | The slice it carries (FD-1) | Notes |
|---|---|---|---|
| 1 | **S14-lite** — loudness compensation (ISO 226) | **W5-min:** loudness neutrality computed from the *taste* design only, a compensation layer, a level input (C-09). Compensation must respect the ±12 dB trust clamp, with its own headroom or a cap | S14's adaptive half (the system volume observed, engine events) waits for W2. [US-TON-03](backlog.md) |
| 2 | **S12** — parametric EQ + AutoEq import | **W5:** `EQProgram` / `FilterSpec`, per-band glide, SVF shelves; the Realizer also owns the channel layout (C-45's rest) and a stage concept (C-47) | The A/B LUFS-matched bypass already shipped as hold-to-Compare (Sprint EQ) |
| 3 | **S13** — headphone and device correction | A correction layer and the user's taste on one graph | |
| 4 | **S11-lite** — format hardening, CUE | FLAC seek-table check. **CUE only if the founder's library has `.cue` files** (count them first — a council default); if so, an item id (C-04), a region source from the engine the Engine sprint chose, and a `cue_index` store key | WavPack / APE and the FFmpeg path's gapless trim (US-PLAY-07) come only through the FFmpeg opt-in (FD-3) |

**R2 ships after S11-lite**, the last of the four. Each sprint keeps the 2-week cap per slice and finish-or-revert.

### How structural work is paid for

- **No standalone waves (FD-1).** A structural slice ships only with the feature that needs it, or when its trigger fires; at most 2 weeks per slice; finish-or-revert, so a sprint never ends with two live owners of one job.
- **Where the council's former waves went** ([slice catalogue](../reviews/2026-10-council/working/stage5-architect.md#43-slice-catalogue-the-former-waves)):
  - W0-lite (tests on the real code, durable harnesses) rides with each R1.1 fix;
  - W4 (one Enhanced source pipeline) and W3-lite (one engine target) become the Engine sprint;
  - W5-min and W5 ride with S14-lite, S12 and S13;
  - the durable-library slice keeps its pieces except the tombstone (FD-10), and they ride with the next scan or watch feature;
  - the UI command and undo slice (WU) rides with smart lists, undo and the R2 UI surfaces;
  - the MCP slice and W2 belong to EP-MCP.
- **W2 — one owner for playback.** The transport reducer, the command layer and the engine event channel (C-01, C-05, C-06, C-13, C-15 in full, C-18; the library lane C-58, C-59).
  - **Funded by** EP-MCP (FD-8), S14's adaptive half (it needs engine events) or crossfade.
  - **Triggered by** any wrong-song or silent-playing bug reported after R1.1's transport fixes; that bug starts W2 instead of another patch.
  - The Engine sprint delivers the engine half (seam events that carry the track's identity, one seek, one end flag), so W2 is expected to shrink to the queue / transport reducer and the command layer.

---

## Phase 1 — Player maturity / competitive parity (S8–S14)

**Exit criterion:** a listener can point the app at their music folders and live in it daily — browse, search, queue, play bit-perfect with art / tags / media keys, CUE albums, headphone correction, loudness compensation — on a QA gate we trust. This is the GitHub release that earns the right to differentiate. *(2026-10-14: "CUE albums" holds only if the founder's library has `.cue` files — S11-lite.)*

| Sprint | Scope |
|--------|-------|
| S8 | Library spine: scan + persistent DB |
| S9 | Browse & search UI — album grid; Artist/Album/Genre; incremental search; cover art; click-to-queue |
| S10 *(runs as S10.1–S10.8; S10.5 cut)* | Queue + playlists + macOS control — queue, recently-played (frecency), media keys + Now-Playing/Control Center (S10.1–S10.6) — plus the **Liquid Glass release UX** (S10.7 Now Playing + shell, S10.8 every other tab + light mode, which also carried the full EQ redesign, "Sprint EQ"). Split into individual sub-sprints — see [sprint-plan.md](../sprints/sprint-plan.md) + [s10 plan](../sprints/s10-queue-playlists-macos-plan.md). *(M3U/M3U8 import-export deferred — see below.)* |
| **R1.1-A / R1.1-B** *(new, 2026-10-14)* | Faithful, durable, honest fixes, then the decided medium items — [above](#r11-a-faithful-durable-honest) |
| **Engine sprint** *(new, 2026-10-14)* | Study SFBAudioEngine, build our own Enhanced engine as its own module, compare, decide — [above](#the-engine-sprint) |
| S11 | CUE sheets + format hardening — CUE→virtual tracks, FLAC fast-seek, WavPack/APE, lossy gapless trim. *(2026-10-14: runs **last** of the four, as **S11-lite** — CUE only if `.cue` files exist; WavPack/APE and the trim through the FFmpeg opt-in.)* |
| S12 | Tonal parity — parametric EQ + AutoEq/oratory1990 import + A/B LUFS-matched bypass. *(2026-10-14: runs **second**, carrying W5.)* |
| S13 | Headphone + device parity — device-correction EQ auto-load + profile JSON import/export. *(2026-10-14: runs **third**.)* |
| S14 | Loudness compensation (ISO-226) — the lowest-risk first taste of the adaptive thesis. *(2026-10-14: runs **first**, as **S14-lite**, carrying W5-min.)* |

*(Delivered early: preset save/load, the Reimagine intensity-knob wiring and crossfeed — originally scoped in S12/S13 — in the QW1 differentiators burst; the EQ's loudness-matched hold-to-Compare and per-output EQ memory in Sprint EQ (S10.8). Detail and the code facts per sprint: [sprint-plan §3](../sprints/sprint-plan.md#3-phase-1--player-maturity--competitive-parity).)*

**R2 order (FD-1, 2026-10-14): S14-lite → S12 → S13 → S11-lite.** The rows keep their numbers, since renumbering breaks every link to them; the order wins.

---

## Phase 2 — The Adaptive Sound differentiation (S15–S18)

Built on the mature base, enabler-first, lowest-artifact-risk first. This is the thesis that no static competitor (including Apple's ASAF) can match — it adapts every buffer to content, level and device. *("…and hearing" removed: hearing personalization was cut 2026-07-12 — see Deferred.)*

| Sprint | Scope |
|--------|-------|
| S15 | SPIKE: masking model + arbitration (roex + Arbiter logic; de-risks the thesis) |
| S16 | Clarity (masking-aware) — Arbiter + Realizer v1; the core perceptual differentiator |
| S17 | Reimagine intensity — full mapping (0→1 across loudness-comp + clarity + crossfeed). *(2026-10-14: the Intensity control, hidden in R1.1 by FD-2, returns here, with the correlation-compensated blend — C-40.)* |
| S18 | SPIKE-BRIR + BRIR spatial render v1 — highest artifact risk → sequenced last. *(2026-10-14: it replaces R1.1-B's BS.775 fold-down in the same slot — FD-9.)* |

---

## Release milestones (per [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §7)

| Release | After | Theme | Content |
|---------|-------|-------|---------|
| **R1 — "a real player"** = **v1.0.0-alpha** *(✅ shipped 2026-10-14)* | S10.1–S10.4 + S10.7/S10.8 (release UX) + the council's R1 blocker fixes (PR #88) | Daily-driver | Library, browse, search, queue, playlists, media keys, bit-perfect playback, in the Liquid Glass UI (dark + light) with the honest 31-band EQ — [release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha), [release notes](../releases/v1.0.0-alpha.md) |
| **R1.1 — "faithful, durable, honest"** *(new, 2026-10-14; version set at release)* | R1.1-A + R1.1-B | The daily driver, fixed | A faithful default and remembered settings, seek-to-end, the Mastering converter, transport and audible-DSP fixes, Pure honesty, FFmpeg opt-in, library safety, BS.775 surround on stereo, shuffle, search + ⌘F, loose files, "Use this drive", the leveling setting |
| **R2 — "audiophile-credible"** | ~~S14~~ the Engine sprint, then S14-lite → S12 → S13 → **S11-lite** *(re-ordered 2026-10-14)* | Parity (unlocks Phase 2) | CUE (if the library has it), format hardening, PEQ/AutoEq, presets, crossfeed, device correction, loudness compensation, the engine the Engine sprint chose, QA gate green |
| **R3 — "differentiated"** | S17 | The thesis | Clarity + steerable Reimagine — demonstrable and comparable |

**Critical path:** S6 (gate) → S8 → S9 → S10.1–S10.4 (queue/playlist spine + UX + system control) → S10.7/S10.8 (the release UX R1 was re-gated on, 2026-07-17). Everything browse/queue hangs off S8 — the highest-leverage and most-underestimated stretch in the plan. *(After R1: R1.1-A → R1.1-B → the Engine sprint → S14-lite.)*

**Opinionated guardrail (PM + BA agree):** do not start Phase 2 until S8–S10 ship and the app has been the daily driver for a week. The adaptive DSP is more fun than catalog plumbing — the differentiators only earn attention once the table-stakes are invisible-because-they-just-work. *(2026-10-14, a council default: the same week applies to R1.1 before R2.)*

---

## Agent control surface (MCP) *(founder, 2026-10-13; placed 2026-10-14)*

**Expose ALL of the player's functionality through a local [MCP](https://modelcontextprotocol.io) server**, so an
LLM client (Claude Desktop / Claude Code, the open-source agent [OpenClaw](https://bigdataboutique.com/what-is-openclaw),
or any MCP client) can drive AdaptiveSound: transport, queue, library search and browse, playlists, EQ and sound
settings, output devices and Pure Mode, and read the player's state.

- **One command layer, two front ends.** MCP tools call the SAME command / state API as the UI, never a second
  path. That makes it depend on the 2026-10 council's transport command / reducer and engine-event work.
- **Local and consented.** Off by default; enabled in Settings; local only (stdio or localhost); per-client scopes
  (read-only / control / library-modify); destructive operations confirmed; hearing-safety clamps enforced
  server-side for every client.
- **Placement (FD-8, 2026-10-14): after W2 — one owner for playback — and the command layer, in R2 or later.** No early
  spike: today's transport breaks under single-client interleavings, and an agent is a fast client. EP-MCP is what
  funds W2 ([How structural work is paid for](#how-structural-work-is-paid-for)). ~~Placement: decided by the 2026-10
  council, after the command-layer refactor wave.~~ Backlog: [EP-MCP](backlog.md#ep-mcp--agent-control-surface-mcp).
- **Relationship to the 2026-07-12 cut:** in-app conversational tuning stays cut. This is an *external* control
  surface. An LLM adjusting the EQ through MCP is a consequence the founder confirms explicitly (council decision list).

## Deferred / out-of-window

- **Release readiness — deferred (FD-7, 2026-10-14): "focus on features."** The licence is chosen — **Apache-2.0** — but the LICENSE file and notices, Developer ID signing and notarization, diagnostics (`os.Logger`, MetricKit crash payloads, Copy Diagnostics, an issue template), playlist export and a "Back up library data" item, and a clean-Mac first-run test wait for a later release-readiness item. It is scheduled when the founder calls for a release beyond their own Mac (decision 13 already made notarization the first item of such a release). Backlog: US-REL-01…05; council C-10, C-101, C-103.
- **Parked until hardware (FD-5, 2026-10-14):** the **USB-DAC check** (the bit-perfect integer path on real hardware, Pure pause / resume — C-100, the HAL device-state contract — C-31, HDMI still accepted after R1's format rules, the QW1 by-ear checks) and the **virtual-DAC rig** ([plan](../reviews/2026-10-council/working/virtual-dac-plan.md)) — on the back burner until the founder brings a hardware rig (HDMI cables plus a device). The USB-DAC check is still owed. Nothing that changes Pure's output path is scheduled before it.
- **Not adopted (2026-10-14):** making CI the only merge gate — the founder keeps merging by hand, with no required checks (FD-6, council C-83); a `missing_since` tombstone and a 100k-song performance gate — the target is 20k songs under today's rules (FD-10, council C-56, C-60).
- **Removed from scope (2026-07-12, founder decision):** **natural-language / conversational tuning** and **hearing personalization** (hearing-test → profile → compensation) were cut from the vision entirely — not deferred, removed. May be re-added later. Prior specs are in git history.
- **Deprioritized (2026-07-14, founder decision):** **drag-from-Library-into-queue** and **playlist file import/export (M3U/M3U8)** — judged not useful enough to plan now. Not removed from the vision; revisit opportunistically post-R1. Add-to-queue is already covered by the Play Next / Add to Queue verbs; playlist portability (M3U) can return if a real need appears. R1 no longer depends on either. *(2026-10-14: playlist **export** returns as data safety inside release readiness — FD-7, council C-101; import stays deprioritized.)*
- **Cut 2026-07-16 / 2026-07-17 (founder):** the playlist-folders UI (its data layer shipped and stays dormant) and S10.5 browse polish (folder-browse; the A–Z rail). **Smart playlists** are a post-R1 fast-follow. Detail: [sprint-plan §Status](../sprints/sprint-plan.md#status). *(2026-10-14, a council default the founder may overrule: delete the dormant playlist-folder data-access code the next time the store is touched — C-62; the v5 tables stay, since migrations are additive-only. Smart playlists stay the fast-follow; they are not in R1.1.)*
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

- **Per-merge gate (`make gate`):** the C++ null-test (golden master `0xE7AF0C67F9340785` since Sprint EQ — was `0xE7267654BA01D315`; bit-exact bypass at intensity 0 with the EQ flat or off), `VerifyAUGraph`, and `VerifyLibraryStore`. **`make strict-gate`** (CI on every PR) adds format/lint/semgrep, clang-tidy, Periphery, `swift test` (native swift-testing), ASan/UBSan/TSan, leak detection and the `make main-thread-stall` self-test. *(The DSP correctness gate is the C++ null-test golden-master. See [../sprints/README.md](../sprints/README.md).)* *(2026-10-14, FD-6: CI runs on every PR but is not a required check; the founder merges by hand.)*
- **DSP oracles (S7):** libebur128 loudness/TP, limiter −1 dBTP, 31-band EQ FR sweep, SRC alias/imaging, gapless-seam, RT-allocation soak. *(THD+N: not built.)* *(2026-10-14: the SRC check passes a −7 dB error today — council R-6; R1.1-A item 4 makes it fail when it should.)*
- **By-ear / by-hand:** the founder owns audible/visual checks; Pure-path + QW1 by-ear verification is pending a USB DAC *(parked for about two weeks — FD-5)*.

Details: [../architecture/validation-strategy.md](../architecture/validation-strategy.md).

---

## Cross-references

- **Detailed sprint sequence (authoritative "what's next"):** [../sprints/sprint-plan.md](../sprints/sprint-plan.md)
- **The 2026-10 product council (findings, decisions, rationale):** [../reviews/2026-10-council/README.md](../reviews/2026-10-council/README.md)
- **Sprint methodology & historical records:** [../sprints/00-sprint-model.md](../sprints/00-sprint-model.md), [../sprints/README.md](../sprints/README.md)
- **Architecture, locked decisions & ADRs:** [../architecture/architecture.md](../architecture/architecture.md)
- **Product requirements & vision:** [PRD.md](PRD.md), [requirements.md](requirements.md)
- **Backlog & stories:** [backlog.md](backlog.md) · **Open issues:** [known-issues.md](known-issues.md)
- **QA framework:** [../architecture/validation-strategy.md](../architecture/validation-strategy.md)

---

**For current status and "what's next," see [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §Status + the source/git.** This roadmap intentionally does not track per-sprint state — it is the high-altitude arc (Phase 1 parity → Phase 2 differentiation, R1 → R1.1 → R2 → R3).
