# Sprint Plan — AdaptiveSound

**Document ID:** SPRINT-PLAN-001
**Version:** 0.2 — finalized for execution (2026-06-19); founder-reviewed.
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

## 2. Where we are today (verified current state)

**Shipped & solid (the engine is genuinely strong — in places ahead of the field):**

- Bit-perfect **Pure Mode** — CoreAudio HAL-direct, hog mode, per-track sample-rate match, DSP fully bypassed. (*Apple Music itself is not bit-perfect on macOS — this is a real differentiator.*)
- **Enhanced** path — `AVAudioEngine` two-AU N-channel graph (≤7.1), 48 kHz float, EQ → loudness → limiter → spatial-passthrough.
- Runtime **FFmpeg-or-Apple decode** (dlopen, baked major-version guard) — FLAC/ALAC/WAV/AIFF/Opus/MP3/AAC.
- **31-band EQ** — real, live, UI-driven (drag the response curve), ±12 dB, kernel-clamped.
- **True-peak limiter** (8× ISP) + **BS.1770-5 loudness meter** with active LUFS normalization (we are *ahead* of most players on loudness).
- **Gapless** — Enhanced (full) + Pure (same-rate); auto-advance; device-resilience + pin/follow connect-behavior setting.
- **Signal-path transparency UI** (Roon-style: Pure vs Enhanced, sample rate, decode backend).

**Half-built / stubs (the gap list):**

- EQ has **no presets, no device-correction** (AutoEq import). **Reimagine** intensity knob is **not UI-wired** (pinned at 1.0). **Clarity** (masking-aware) module is an empty stub. **BRIR/spatial render** is a stub. **Loudness compensation** (ISO-226 equal-loudness) not built. **Arbiter/Realizer** adaptive control plane not built. **Crossfeed / virtual bass** absent.
- **QA gaps:** no libebur128 conformance oracle, no EQ 31-band FR sweep, no THD+N, no ISP-detector accuracy test, no SRC alias test.

**The biggest credibility gap (the linchpin):** we are a **playlist/folder player, not a library player.** There is no persistent music library, no album/artist/genre browse, no search, no cover-art grid — just a flat in-memory playlist + folder monitor. *This is the single largest distance between us and a mature player, and it gates the entire lean-back browse/queue UX.*

---

## 3. Phase 1 — Player maturity / competitive parity

> **Exit criterion:** a listener can point us at their music folders and live in the app daily — browse, search, queue, play bit-perfect with art, tags, media keys, CUE albums, headphone correction, loudness compensation — on a QA gate we trust. **This is the GitHub release that earns the right to differentiate.**

**Execution order (founder decision §8.2):** harden the QA gate first (cheap, pure safety, must precede any DSP-touching work), then build the library spine as one focused block (the credibility critical path), then the sound-parity sprints.

| Sprint | Title | SP | Scope | Depends on |
|---|---|---|---|---|
| **S6** | DSP-gate hardening | 8 | libebur128 LUFS/TP conformance oracle; EQ 31-band FR sweep + bit-transparent-bypass test; limiter −1 dBTP guarantee + ISP-detector accuracy; SRC alias/stopband test; gapless-seam regression (both paths); 1-hr XRun/allocation soak. (BA US-QA-01..06) | shipped DSP |
| **S7** | Library spine: scan + persistent DB | 9 | Folder scan/watch, metadata + embedded-art extraction, incremental rescan, persistent store (GRDB/SQLite), art cache. Headless-testable via CLI/C++ harness before UI. | — (foundation) |
| **S8** | Browse & search UI | 8 | Album-grid; Artist/Album/Genre/Year views; incremental search; cover-art rendering; click-to-queue. | S7 |
| **S9** | Queue + playlists + macOS control | 8 | Queue reorder/save/play-next/history; playlist create/edit + **M3U/M3U8** import-export; **media keys + Now-Playing/Control Center** (`MPNowPlayingInfoCenter`); keyboard shortcuts; folder-browse mode. | S7, S8 |
| **S10** | CUE sheets + format hardening | 7 | External + embedded **CUE** → virtual tracks (reuse gapless); FLAC seektable/fast-seek verification; enable WavPack/APE if free via FFmpeg; full metadata-display panel; close **gapless Stage 2b** (lossy AAC/MP3 encoder-delay trim — US-PLAY-07). | S7, gapless |
| **S11** | Tonal parity + finish half-built | 9 | **Parametric EQ** bands alongside the 31-band graphic; **AutoEq/oratory1990 `ParametricEQ.txt` import**; preset save/load per-output; **wire the Reimagine intensity knob** (0 % ⇒ bit-transparent bypass — closes the NFR-QUAL-03 demonstrability gap); **A/B LUFS-matched bypass** toggle. | S6, EQ (have) |
| **S12** | Headphone + device parity | 7 | **Crossfeed** (Bauer/Meier, established low-artifact algo); **device-correction EQ** auto-load by identified device; profile JSON import/export. | S6, S11 |
| **S13** | Loudness compensation (ISO-226) | 8 | Equal-loudness contour tilt driven by playback level/target SPL; ramped, capped (+12 dB default), no zipper; wires to the existing param bus/TargetState. *Pulled into Phase 1 (founder decision §8.4): it's a parity feature ("the loudness button") AND the lowest-risk first taste of the adaptive thesis — proving the adaptive platform within the parity release.* | S6, loudness infra (have) |

*After **S9** we are already a credible daily-driver (minimum-credible release R1). S10–S13 add the audiophile-credible layer.*

**Phase 1 total:** ~64 SP across 8 sprints. Realistic to release in two waves (R1 after S9, R2 after S13).

**Critical path:** S7 → S8 → S9 (library spine) — the highest-leverage and most-underestimated stretch in the plan; everything browse/queue hangs off S7.

---

## 4. Phase 2 — The strategic pivot (the Adaptive Sound thesis)

> Loudness compensation (S13) already delivered the lowest-risk adaptive feature and proved the platform. Phase 2 builds the perceptual core, enabler-first (per the sprint-model dependency graph), lowest-artifact-risk first. S11's PEQ + AutoEq import planted the "device-aware correction" seed — Phase 2 makes it *adaptive*.

| Sprint | Title | SP | Scope | Depends on |
|---|---|---|---|---|
| **S14** | SPIKE: masking model + arbitration | 7 | roex masking + Arbiter logic validation (enabler, not a shippable feature). De-risks the core thesis before building the Realizer. | DSP spine |
| **S15** | Clarity (masking-aware) — Arbiter + Realizer v1 | 9 | Arbiter logic → Realizer biquad fitting; the core perceptual differentiator. Conservative defaults; A/B vs bypass. | S14 |
| **S16** | Reimagine intensity (full mapping) | 6 | Map intensity 0→1 across loudness-comp + clarity (+ crossfeed) — the single steerable UX that ties the thesis together (beyond the on/off wiring done in S11). | S13, S15 |
| **S17** | SPIKE-BRIR + BRIR spatial render v1 | 9 | Binaural impulse-response spatial rendering; highest complexity/artifact risk → sequenced last. Independent spike chain, can run parallel to S15/S16. | DSP spine; SPIKE-BRIR |

**Phase 2 total:** ~31 SP across 4 sprints. **Critical path of the thesis:** S14 (spike) → S15 (Realizer); S16 ties it together.

---

## 5. Deferred

**Next wave, after R2 — gated on hardware:**

- **DSD playback (DoP + native)** — real L-sized work (DoP packing into the Pure HAL path, native-vs-DoP negotiation, DSD→PCM fallback). **Deferred past R2 (founder decision §8.3): no DSD DAC to verify by ear** — shipping an unhearable headline feature violates the by-ear verification workflow. First candidate for the post-R2 wave, gated on acquiring a DSD-capable DAC (same pattern as the pending Pure-mode USB-DAC verification).

**"Won't, this horizon"** — kept on the backlog as the future roadmap, out of this plan's window:

- **Natural-language / conversational tuning (EP-NLT)** — the vision's endgame; needs the full adaptive stack (S13–S17) to have anything to steer. (Blocked on SPIKE-NLT-ARCH / OQ-11.)
- **Stem separation / object engine (EP-STEM, Phase 1.5)** — high compute/artifact risk; revisit only after the mix-based thesis is validated and loved.
- **System-wide capture / virtual device (EP-SYSWIDE, EP-VDEVICE)** — different product surface; our story is *this Mac → this DAC, bit-perfect*.
- **Off-thesis player features:** streaming integration (Qobuz/Tidal — licensing, off-limits for non-commercial solo dev), CD ripping, DLNA/UPnP/multi-zone, SACD ISO.
- **Cheap P2 nice-to-haves** (tag editing/write-back, smart playlists, last.fm scrobbling, internet radio, sleep timer) — pull *opportunistically* into a polish mini-sprint if velocity allows, never as planned scope.

---

## 6. Backlog re-anchor (prerequisite — the backlog has drifted from shipped reality)

The backlog (v2.2) describes a single mix-level DSP graph; what shipped is the two-path Pure/Enhanced engine + gapless + decode — **none of it reflected as Done stories.** Before/alongside S6, re-anchor so the plan stays traceable:

**6A — Back-fill as DONE** (cite commits): Bit-perfect Pure Mode (new US-ENG-07); two-path engine (US-ENG-08); runtime FFmpeg-or-Apple decode (amend US-PLAY-01); **31-band** live UI-driven EQ (amend US-TON-01 — *deviation: backlog says 10-band*); true-peak limiter (US-ENG-05); BS.1770-5 meter + LUFS normalization (new); gapless + auto-advance (new US-PLAY-08/09); device-resilience + pin/follow (new US-DEVICE-09); **signal-path** transparency UI (new US-ADAPT-06 — *deviation: distinct from the still-unbuilt **adaptation**-transparency US-ADAPT-04; do not conflate*).

**6B — Tag "Won't — this horizon":** EP-STEM, EP-SYSWIDE, EP-VDEVICE, EP-NLT (incl. multilingual), US-PROF-01 (iCloud sync), and their gating spikes — keep entries, mark out-of-window. DSD: tag "deferred — post-R2, gated on DSD DAC."

**6C — Doc gap closed:** `00-sprint-model.md` references this `sprint-plan.md` (which did not exist until now). This document closes that gap; update the three backlog references + the model's "Related Documents" to point here.

---

## 7. Release milestones & critical path

- **Critical path:** S7 → S8 → S9 (library spine). Everything browse/queue hangs off S7, the highest-leverage and most-underestimated sprint in the plan.
- **Release R1 ("a real player"):** after **S9** — daily-driver: library, browse, search, queue, media keys, bit-perfect playback.
- **Release R2 ("audiophile-credible"):** after **S13** — CUE, format hardening, PEQ/AutoEq, presets, crossfeed, device correction, loudness compensation, QA gate green. **This is the parity milestone that unlocks Phase 2.**
- **Release R3 ("differentiated"):** after **S16** — Clarity + steerable Reimagine. The Adaptive Sound thesis, demonstrable and comparable.

**One opinionated recommendation (PM + BA agree):** do **not** start Phase 2 until S7–S9 ship and you've lived on the app as your daily player for a week. The adaptive DSP is more fun than catalog plumbing — resist jumping early. The differentiators only earn attention once the table-stakes are invisible-because-they-just-work.

---

## 8. Decisions (founder review, 2026-06-19)

1. **Doc home & numbering** — keep this as `docs/sprints/sprint-plan.md`, continue sprint numbering at **S6**. (Closes the referenced-but-missing doc gap; `roadmap.md` stays the high-altitude view.)
2. **Track sequencing** — **QA-gate first (S6), then library as a focused block (S7–S9), then sound-parity sprints (S10–S13).** Safety net before any DSP-touching work, without fragmenting the library critical path.
3. **DSD** — **deferred past R2**, gated on acquiring a DSD DAC. Keeps every R2 feature by-ear verified.
4. **Loudness compensation** — **pulled forward into Phase 1 (S13)** as a parity feature + lowest-risk taste of the adaptive thesis.
5. **Competitor research** — **start S6 now**; commission feature-level teardowns per-sprint, the week each feature is built. (A separate positioning narrative can run in the background anytime.)

---

**Last updated:** 2026-06-19 · **Maintained by:** AdaptiveSound team · **Methodology:** [00-sprint-model.md](00-sprint-model.md) · **Backlog:** [../product/backlog.md](../product/backlog.md)
