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

**Execution order (founder decisions §8.2, §8.6):** **review and harden the architecture first** (gate — no implementation begins until it's green), then harden the QA gate (cheap, pure safety, must precede any DSP-touching work), then build the library spine as one focused block (the credibility critical path), then the sound-parity sprints.

> **Gate status (2026-06-19): S6 is ✅ DONE — the architecture-review gate is GREEN.** The 4-discipline review + all three tiers of fixes shipped (Tier 1 RT-safety/lifecycle; Tier 2 concurrency consolidation; Tier 3 DSP spine), gate-verified (null-test 93/0, golden master held). Feature work (S7+) is unblocked. See the S6 row below and [s6-architecture-review-findings.md](s6-architecture-review-findings.md).
>
> **S7 (DSP-gate hardening): ✅ DONE (2026-06-19).** All six QA stories shipped (null-test 105/0, golden master held): libebur128 loudness oracle, limiter true-peak, EQ 31-band FR sweep, SRC alias/imaging, gapless-seam regression, RT-allocation soak. Every shipped DSP stage now has an automated regression gate validated against an independent oracle where possible. See the S7 row.
>
> **QW1 — Quick-Win Differentiators (exception, before S8; 2026-06-19).** A founder-approved one-off differentiator burst leveraging the S6 spine, *before* resuming the maturity arc at S8: **Reimagine intensity knob** (UI wiring; kernel done) + **tonal presets** + a **crossfeed** DSP stage (knob-scaled). Team-designed + architect-reviewed (**GO-WITH-CHANGES**) → [qw1-quick-win-differentiators-design.md](qw1-quick-win-differentiators-design.md). Then resume S8.

| Sprint | Title | SP | Scope | Depends on |
|---|---|---|---|---|
| **S6 ✅ DONE** | Technical architecture review & hardening *(gate — first & foremost; §8.6)* | 8† | Comprehensive multi-discipline review of the **shipped codebase before any feature work**: system architecture & module boundaries (the two-path Pure/Enhanced engine; the Swift↔C++ boundary; **whether the DSP spine — `TargetState` / lock-free param bus / off-RT worker — genuinely supports the Phase 2 adaptive vision**); C++ RT-safety & lock-free correctness (`DoubleBufferSnapshot`, `SpscRing`, `GaplessSource` atomics + memory ordering; no alloc/lock/syscall on the audio thread); Swift concurrency & engine lifecycle (dispatch queues, `@MainActor` isolation, data races, retain cycles, `AVAudioEngine` teardown); DSP correctness & gain staging (chain order, master-gain-vs-limiter, makeup-gain placement, headroom budget, gapless seam); and verification-coverage gaps. **Outcome:** the 4-discipline review produced [s6-architecture-review-findings.md](s6-architecture-review-findings.md), and **all three tiers of fixes shipped**: **Tier 1** RT-safety/lifecycle, **Tier 2** concurrency consolidation (engineQueue + leaf lock + device-loss serialization), **Tier 3 spine** ([s6-tier3-spine-design.md](s6-tier3-spine-design.md)) — `RtSwappableResource<T>` extracted (EQ migrated) + a **control-plane `Realizer`** (off-RT owner of the canonical `TargetState`, off-main EQ-cascade design, EQ+intensity coalescing, sole publisher, queue-draining teardown) + **steerable equal-power wet/dry intensity** (intensity-0 stays the bit-exact anchor) + a `GaplessController` conformance suite (Pure/Enhanced position-re-zero parity). **Gate-verified:** C++ null-test 93/0, golden master `0xE7267654BA01D315` held. The DSP spine is now confirmed ready, so Phase 2 (S15 spike → S16 Clarity/perceptual-Realizer → S17 Reimagine) builds directly on it. S7's DSP-gate stories were seeded with new intensity tests (true-peak at intermediate `x`, equal-power conformance, settled-ramp byte-identity). | shipped codebase |
| **S7 ✅ DONE** | DSP-gate hardening | 8 | libebur128 LUFS/TP conformance oracle; EQ 31-band FR sweep + bit-transparent-bypass; limiter −1 dBTP guarantee + ISP-detector accuracy; SRC alias/stopband; gapless-seam regression (both paths); RT-allocation soak. (BA US-QA-01..06) **Outcome:** all six shipped — libebur128 vendored test-only (meter conformant ±0.047 LU vs oracle); limiter ceiling held under a dual-oracle true-peak gate; all 31 EQ bands FR-accurate incl. near-Nyquist (clears the S6 Schur-Cohn concern); SRC imaging ≤ −83.7 dBFS via `SRCQualityMeasure`; 14 gapless-seam tests; RT-allocation soak proves zero audio-thread allocations (fast default; full 1-hr via `SOAK_FULL=1`) + an Instruments XRun procedure ([s7-soak-instruments-procedure.md](s7-soak-instruments-procedure.md)) for the on-hardware half. Gate: null-test 105/0, golden master held. | S6 |
| **S8** | Library spine: scan + persistent DB | 9 | Folder scan/watch, metadata + embedded-art extraction, incremental rescan, persistent store (GRDB/SQLite), art cache. Headless-testable via CLI/C++ harness before UI. | S6 (foundation) |
| **S9** | Browse & search UI | 8 | Album-grid; Artist/Album/Genre/Year views; incremental search; cover-art rendering; click-to-queue. | S8 |
| **S10** | Queue + playlists + macOS control | 8 | Queue reorder/save/play-next/history; playlist create/edit + **M3U/M3U8** import-export; **media keys + Now-Playing/Control Center** (`MPNowPlayingInfoCenter`); keyboard shortcuts; folder-browse mode. | S8, S9 |
| **S11** | CUE sheets + format hardening | 7 | External + embedded **CUE** → virtual tracks (reuse gapless); FLAC seektable/fast-seek verification; enable WavPack/APE if free via FFmpeg; full metadata-display panel; close **gapless Stage 2b** (lossy AAC/MP3 encoder-delay trim — US-PLAY-07). | S8, gapless |
| **S12** | Tonal parity + finish half-built | 9 | **Parametric EQ** bands alongside the 31-band graphic; **AutoEq/oratory1990 `ParametricEQ.txt` import**; preset save/load per-output; **wire the Reimagine intensity knob** (0 % ⇒ bit-transparent bypass — closes the NFR-QUAL-03 demonstrability gap); **A/B LUFS-matched bypass** toggle. | S7, EQ (have) |
| **S13** | Headphone + device parity | 7 | **Crossfeed** (Bauer/Meier, established low-artifact algo); **device-correction EQ** auto-load by identified device; profile JSON import/export. | S7, S12 |
| **S14** | Loudness compensation (ISO-226) | 8 | Equal-loudness contour tilt driven by playback level/target SPL; ramped, capped (+12 dB default), no zipper; wires to the existing param bus/TargetState. *Pulled into Phase 1 (founder decision §8.4): it's a parity feature ("the loudness button") AND the lowest-risk first taste of the adaptive thesis — proving the adaptive platform within the parity release.* | S7, loudness infra (have) |

†S6 is review + fixes; it may spill beyond 8 SP if the review surfaces heavy structural issues — that's expected and acceptable, since the whole point is to fix the foundation before building on it.

*After **S10** we are already a credible daily-driver (minimum-credible release R1). S11–S14 add the audiophile-credible layer.*

**Phase 1 total:** ~72 SP across 9 sprints. Realistic to release in two waves (R1 after S10, R2 after S14).

**Critical path:** S6 (architecture gate) → S8 → S9 → S10 (library spine) — the architecture review gates everything; after it, the library spine is the highest-leverage and most-underestimated stretch.

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

- **Natural-language / conversational tuning (EP-NLT)** — the vision's endgame; needs the full adaptive stack (S14–S18) to have anything to steer. (Blocked on SPIKE-NLT-ARCH / OQ-11.)
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

- **Gate:** S6 (architecture review & hardening) — **no feature sprint starts until this is green.**
- **Critical path:** S6 (gate) → S8 → S9 → S10 (library spine). Everything browse/queue hangs off S8, the highest-leverage and most-underestimated feature sprint in the plan.
- **Release R1 ("a real player"):** after **S10** — daily-driver: library, browse, search, queue, media keys, bit-perfect playback.
- **Release R2 ("audiophile-credible"):** after **S14** — CUE, format hardening, PEQ/AutoEq, presets, crossfeed, device correction, loudness compensation, QA gate green. **This is the parity milestone that unlocks Phase 2.**
- **Release R3 ("differentiated"):** after **S17** — Clarity + steerable Reimagine. The Adaptive Sound thesis, demonstrable and comparable.

**One opinionated recommendation (PM + BA agree):** do **not** start Phase 2 until S8–S10 ship and you've lived on the app as your daily player for a week. The adaptive DSP is more fun than catalog plumbing — resist jumping early. The differentiators only earn attention once the table-stakes are invisible-because-they-just-work.

---

## 8. Decisions (founder review, 2026-06-19)

1. **Doc home & numbering** — keep this as `docs/sprints/sprint-plan.md`, continue sprint numbering at **S6**. (Closes the referenced-but-missing doc gap; `roadmap.md` stays the high-altitude view.)
2. **Track sequencing** — **architecture-review gate first (S6), then QA-gate (S7), then library as a focused block (S8–S10), then sound-parity sprints (S11–S14).** Foundation hardened and safety net in place before any feature/DSP work, without fragmenting the library critical path.
3. **DSD** — **deferred past R2**, gated on acquiring a DSD DAC. Keeps every R2 feature by-ear verified.
4. **Loudness compensation** — **pulled forward into Phase 1 (S13)** as a parity feature + lowest-risk taste of the adaptive thesis.
5. **Competitor research** — commission feature-level teardowns per-sprint, the week each feature is built. (A separate positioning narrative can run in the background anytime.)
6. **Architecture-review gate (added 2026-06-19)** — a **technical architecture review of the shipped codebase is the first & foremost sprint (S6)**, before any implementation; its findings are fixed before S7+ begins. Rationale: harden the foundation and confirm the DSP spine supports the Phase 2 adaptive vision before building eight sprints of features on it. This pushed the prior S6–S17 down by one to S7–S18.

---

**Last updated:** 2026-06-19 · **Maintained by:** AdaptiveSound team · **Methodology:** [00-sprint-model.md](00-sprint-model.md) · **Backlog:** [../product/backlog.md](../product/backlog.md)
