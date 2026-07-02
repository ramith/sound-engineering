# Adaptive Sound — Product Backlog
## Epics, User Stories, and Spikes

**Document ID:** BACKLOG-ASE-001
**Version:** 2.3 — re-anchored to shipped reality (sprint-plan.md §6); S6/S7 marked Done
**Date:** 2026-06-19
**Author:** Lead Business Analyst
**Status:** Draft — Pending sprint planning review

> **v1.1 change note (2026-06-12 — prior-art refinement pass):** Folded in findings from `docs/architecture/prior-art.md`. (A) EP-VDEVICE reframed as driver **fallback path** only; EP-SYSWIDE updated to lead with tap-primary path, drive-fallback secondary; US-SYS-01..05 annotated accordingly. (B) SPIKE-HRTF updated: largely resolved to SADIE II (Apache-2.0) + libmysofa (BSD-3) + custom SOFA-HRIR convolution; remaining work is performance benchmark and integration. (C) US-SPAT-01 and US-SPAT-01a/b/c updated to reference custom SOFA convolution. (D) US-TON-04 updated with mono-summed constraint (CON-11). (E) SPIKE-VDEVICE updated to include tap-path prototype as primary workstream. (F) Added SPIKE-IPREVIEW (OQ-16 — patent IP review for bass enhancement). (G) Added SPIKE-LIBBS2B (OQ-17 — libbs2b licence dispute). (H) Updated Open Items table with OQ-16 and OQ-17.

> **v2.0 change note (2026-06-13 — architecture v0.2 alignment):** Major revamp to align with `docs/architecture/architecture.md` v0.2 (source of truth) and requirements v0.5. Adopted the **four-phase scheme (0 / 1 / 1.5 / 2)**. Epics restructured: added **EP-PERCEPTUAL** (typed contributors + ERB/Bark masking); **EP-SPAT → EP-IMMERSION** (BRIR-first); **EP-TONAL** reframed (min-phase default, no program DRC, loudness-comp method); **EP-NLT** reframed (typed-macro + per-stem); added **EP-REIMAGINE** (intensity control) and **EP-STEM** (Phase 1.5 object engine). New spikes: **SPIKE-PERF-BUDGET** (gates Phase 1.5), **SPIKE-SEP-QUALITY**, **SPIKE-REIMAGINE-MAP**, **SPIKE-MASKING-MODEL**, **SPIKE-BRIR** (kept SPIKE-IPREVIEW, SPIKE-LIBBS2B). Open Items updated with OQ-18–22. Existing Phase 0/1 stories are retained; affected ones are annotated rather than rewritten.

> **v2.1 change note (2026-06-13 — architecture v0.3 sync):** Folded in the expert-panel review ([review-v0.2.md](../session-notes/review-v0.2.md)) + founder decisions: **re-sum mixbus** (ADR-011) onto US-STEM-02; **bass/lead-vocal spatial exemptions**; **shared late-reverb** + content-adaptive room; masking = **ERB excitation-pattern** subset; gate stems on **perceptual artifacts, not SDR**; **MLX-primary** + **weights auto-download on first run**; Reimagine defaults (low-mid / dead-band / loudness-matched); NL **on-device-lean + output-clamping** (mechanism still deferred); **ADR-004 RT-ML → contingent**; tap **high-consent + comms-exclusion + never-persist**. Hardware floor **M1 Pro/16 GB** (M4/M5 above) → **Risk R-3 Low**, SPIKE-PERF-BUDGET is a **tuning** spike (sets QualityProfile caps, not a go/no-go). Persona → **Ramith**. **Removed outdated:** Class-1/2a/2b labels and the M1/M2 runtime-gating stub (US-SYSW-04 — superseded by the Phase-1.5 stem engine); MacBook-Air/8 GB baselines → M1 Pro/16 GB floor.

> **v2.2 change note (2026-06-19 — gapless follow-up):** Added **US-PLAY-07** (gapless trimming of lossy AAC/MP3 encoder delay/padding on the FFmpeg decode path; **Could**, deferred). Context: gapless / continuous playback shipped after v2.1 outside this backlog — Enhanced-path gapless + auto-advance (`cf33e5d`) and Pure-path same-rate gapless (`2e2242a`); see `../sprints/09-phase-b-bit-perfect-pure-mode.md`. US-PLAY-07 is the remaining refinement (lossy gapless on the FFmpeg backend; Apple backend + lossless already gapless) plus the deferred compressed-vs-uncompressed format-match-predicate edge case. The broader gapless/Pure-Mode feature is not yet otherwise back-filled into this backlog.

> **v2.3 change note (2026-06-19 — backlog re-anchor to shipped reality):** Executed the re-anchor mandated by [`../sprints/sprint-plan.md`](../sprints/sprint-plan.md) §6 (and S6/S7, which have since shipped). The backlog had drifted: it described a single mix-level DSP graph, while what actually shipped is the **two-path Pure/Enhanced engine + bit-perfect HAL Pure Mode + runtime FFmpeg-or-Apple decode + 31-band live EQ + true-peak limiter + BS.1770-5 loudness/LUFS-normalization + gapless + device-resilience + signal-path transparency UI** — none of it reflected as Done stories. Changes in this pass:
> - **Back-filled as DONE** (citing commits): bit-perfect Pure Mode (**new US-ENG-07**); two-path Pure/Enhanced engine (**new US-ENG-08**); runtime FFmpeg-or-Apple decode (**amended US-PLAY-01**); 31-band live UI-driven EQ ±12 dB (**amended US-TON-01** — ⚠ deviation flag: backlog specified **10-band**); true-peak limiter (**US-ENG-05** marked Done); BS.1770-5 loudness meter + LUFS normalization (**new US-ENG-09**); gapless + auto-advance (**new US-PLAY-08 / US-PLAY-09**); device-resilience + pin/follow connect-behavior (**new US-DEVICE-09**); signal-path transparency UI (**new US-ADAPT-06** — ⚠ deviation flag: this is the **signal-path** transparency, distinct from the still-unbuilt **adaptation**-transparency view US-ADAPT-04 — do **not** conflate).
> - **Marked DONE the two new completed sprints** as enabler stories: **S6** architecture review & hardening (**new US-ARCH-01**) and **S7** DSP-gate hardening (**new US-QA-01..06**, grouped under a new **EP-QA** epic). Both cite [`../sprints/s6-architecture-review-findings.md`](../sprints/s6-architecture-review-findings.md), [`../sprints/s6-tier3-spine-design.md`](../sprints/s6-tier3-spine-design.md), and the S7 row of sprint-plan.md.
> - **Tagged "Won't — this horizon"** (entries kept, marked out-of-window): EP-STEM + its stories, EP-SYSWIDE / EP-VDEVICE + their stories, EP-NLT (incl. OQ-14 multilingual) + its stories, US-PROF-01 (iCloud sync), and the gating spikes (SPIKE-VDEVICE, SPIKE-PERF-BUDGET, SPIKE-SEP-QUALITY, SPIKE-NLT-ARCH). **DSD** is tagged "deferred — post-R2, gated on a DSD DAC."
> - **Deviation flags recorded** (for traceability honesty): (1) shipped EQ is **31-band**, backlog said 10-band (US-TON-01 / US-ENG-02); (2) the shipped transparency UI is **signal-path** transparency (Pure vs Enhanced, rate, decode backend), **not** the adaptation-transparency view (US-ADAPT-04) — these are two distinct features.
> - **Doc-gap closed:** `sprint-plan.md` now exists (it was referenced-but-missing). All backlog references to "`00-sprint-model.md` for sprint assignments" have been pointed at `sprint-plan.md`.

> **v2.4 change note (2026-07-02 — library/playlist domain rules formalized):** Added two new Phase-0 epics, back-filling the founder's stated library/playlist use cases as formal requirements ahead of the S8 library-spine build so the persistent store schema is designed against them from day one rather than retrofitted. **EP-LIBRARY** (8 stories, US-LIB-01..08) — multiple independent scan folders; single-file play outside any scan folder; a track lives in exactly one scan folder, with cross-folder duplicates treated as normal distinct files (never silently deduped); a filesystem move updates a track's location in place while its durable identity (and therefore playlist membership) survives the move; stable durable track identity as the thing every future reference (playlist entry, play count) points at, not the file path. **EP-PLAYLIST** (8 stories, US-PLIST-01..08) — many-to-many, user-ordered playlist membership; adding a single non-library file to a playlist; drag-and-drop into a playlist is always a reference-add, never a filesystem move; drag-and-drop folder-to-folder is potentially a real filesystem move (routed through EP-LIBRARY's move-in-place handling so membership survives); user-provided playlist naming with "untitled-N" auto-naming; the built-in non-deletable "current" playlist as the play queue. Every story is tagged with the sprint-chunk it belongs to (S8.1 store schema / S8.2 scan / S8.4 rescan-move / S9 browse / S10 queue-playlists) per [`../sprints/s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md), which is being updated in step to accommodate these rules (nullable `folder_id` for loose files, the stable integer `tracks.id` as the durable reference, and new playlist/playlist_entry tables). No FR/NFR IDs exist yet for library/playlist domain rules (requirements.md predates this feature); stories trace to the design doc and to sprint-plan.md's S8–S10 scope instead, per the same precedent set by the EP-QA stories (US-QA-01..06) tracing to sprint docs. These stories are Draft/Ready-for-sprint-planning, not Done — no code has been touched.

---

> **Note:** Sprint methodology and Kanban model details are documented in `docs/sprints/00-sprint-model.md`; the authoritative **sprint schedule** (which now exists — it was referenced-but-missing until 2026-06-19) is `docs/sprints/sprint-plan.md`. This backlog contains epics, stories, and spikes; sprint assignments are tracked in sprint-plan.md.

## How to Read This Backlog

### Story Format

Every user story uses the following template:

```
Story ID | Title
As a [persona] I want [goal] so that [outcome].
Acceptance Criteria: references to FR/NFR IDs plus any story-specific criteria not already covered.
Priority: MoSCoW  |  Estimate: N sp  |  Dependencies: [IDs]
Traceability: FR-* / NFR-*
```

Note: Phase tags (0 / 1 / 1.5 / 2) appear in story descriptions for context, but sprint assignment is managed separately in `docs/sprints/sprint-plan.md` (schedule) per the `docs/sprints/00-sprint-model.md` methodology.

Personas referenced in stories are drawn directly from the PRD:
- **Marcus** — Persona A, The Audiophile Commuter
- **Ramith** — Persona B, The Developer-Audiophile (the maker)
- **Tom** — Persona C, The Home Studio Hobbyist
- **developer** / **system** — used for enabler stories with no direct end-user actor

### Estimation Scale (Fibonacci Story Points)

| Points | Meaning |
|--------|---------|
| 1 | Trivial — a few hours, no unknowns |
| 2 | Small — half a day, well-understood |
| 3 | Medium — 1–2 days, some complexity |
| 5 | Medium-large — 2–4 days, moderate complexity |
| 8 | Large — nearly a sprint, significant unknowns or risk |
| 13 | Too large — split before planning; treat as an epic boundary |

Anything estimated at 13+ is flagged as an epic and must be split into smaller stories before it enters a sprint.

### Priority Convention (MoSCoW)

- **Must** — ship-blocking for the phase; MVP is unusable without it
- **Should** — high value, ship in the phase if feasible
- **Could** — nice-to-have; defer to next phase if schedule is tight
- **Won't** — explicitly out of scope for the stated phase; documented to prevent creep

> **Project model note (LD-9):** Adaptive Sound is a personal / open-source, non-commercial project. All features are free. MoSCoW prioritisation reflects engineering effort and phasing only — it does not gate any feature behind a paid tier, paywall, or entitlement check. Monetization stories and the OQ-02 feature-gating spike have been removed from this backlog.

### Phase Tags (Organizational Grouping)

Phase tags organize stories by architectural scope and dependency depth. They are **not** lifecycle gates; sprints may span phases and phases may overlap.

- **Phase 0** — Player MVP: the DSP spine (playback through the kernel, param bus, passthrough → first DSP)
- **Phase 1** — Mix-based core: perceptual clarity/correction, loudness-comp, adaptive engine, **BRIR** immersion, NL (typed-macro, mix-level), **Reimagine** knob (mix range)
- **Phase 1.5** — **Stem-based object engine**: offline 6-stem separation, per-stem chains + spatial placement, between-stem unmasking, per-stem NL, Reimagine (stem range) — own-player-only
- **Phase 2** — System-wide via Core Audio process taps (mix-level), virtual-device fallback

**Phase ordering principle:** Enablers and foundational work (Phase 0) typically precede higher phases, but sprint sequencing is determined in `docs/sprints/sprint-plan.md`, not by phase alone.

### Traceability Convention

Every story includes a "Traceability" field listing all FR and NFR IDs it satisfies. Where the requirement document already contains Given/When/Then acceptance criteria, this backlog references the FR ID rather than re-typing the criteria verbatim. Story-specific conditions that are not already covered in the requirements document are written out explicitly under "Acceptance Criteria."

### Definition of Ready (DoR)

A story is ready to enter a sprint when:
1. The story has a clear, agreed acceptance criterion (referencing FR/NFR or written explicitly).
2. All upstream dependency stories are either done or in the same sprint.
3. Any spike result needed to begin implementation is available.
4. Design mocks or engineering architecture decision records (ADRs) are available for stories of 5+ points.
5. The story is estimated by the team.

### Definition of Done (DoD)

A story is done when:
1. All acceptance criteria pass (including referenced FR/NFR criteria).
2. Unit and/or integration tests are written and green.
3. The feature works on Apple Silicon (M1 or later) under macOS 14 Sonoma.
4. No new XRuns, memory leaks, or audio-thread allocations introduced (verified by Instruments).
5. VoiceOver labels and keyboard navigation verified for any new UI control.
6. Code reviewed by at least one other engineer.
7. The story is demonstrable in the sprint review.

---

## Epics

**Note:** The Phase column indicates architectural scope (0 = player foundation, 1 = mix-level features, 1.5 = stem features, 2 = system-wide). It is **not** a timeline or gate; sprint assignments are in `docs/sprints/sprint-plan.md`.

| Epic ID | Goal | Phase | FR / NFR Coverage | Success Measure (from PRD KPIs) |
|---------|------|-------|-------------------|--------------------------------|
| EP-ENGINE | Real-time engine spine — AVAudioEngine + custom AU (C++ kernel, Swift/C++ interop), **per-stem** lock-free param bus, Audio Workgroups, off-RT Realizer | 0 | FR-ADAPT-02/03, NFR-PERF-01/06, NFR-QUAL-01..04, CON-01/02 | Zero XRuns in 1-hour playback; audio thread ≤ 50% of buffer period |
| EP-PLAYER | Local file playback, queue, metadata, session state | 0 | FR-PLAY-01..06, FR-UI-01/04/06, NFR-REL-01..03 | Median session > 25 min; crash-free > 99.5% |
| EP-DEVICE | Output-device enumeration, type classification, auto-profile switching | 0→1 | FR-DEVICE-01..06, FR-SPAT-06/07 | Profile switch < 500 ms; no dropout > 50 ms |
| EP-PERCEPTUAL | **(new)** Typed-contributor model + Arbiter (ERB/Bark + masking + partial-loudness) + off-RT Realizer (min-phase default, content-driven phase; FIR/biquad fit) | 1 | LD-12/13, FR-TONAL-01, FR-ADAPT-*, NFR-PERF-01 | Clarity/masking decisions made perceptually; users do **not** perceive the EQ "moving" |
| EP-TONAL | **(reframed)** Correction-to-target EQ (AutoEq), loudness-comp (fractional contour-diff + SPL calibration), **no-program-DRC** dynamics + true-peak limiter, psychoacoustic bass (mono-sum) | 1 | FR-TONAL-02..07, LD-17 | "Sounds better" > 70%; dropouts < 0.1% |
| EP-IMMERSION | **(was EP-SPAT + EP-HEADTRACK)** BRIR-first binaural (HRTF + room reflections/reverb), room synthesis, head-tracking (opt-in), speaker M/S + ambience (mono-safe) | 1 | FR-SPAT-01..07, LD-14, DEP-03 | Externalisation works (ABX vs dry-HRTF); spatial adoption |
| EP-ADAPT | **(absorbs EP-AMBIENT)** Pre-analysis pipeline (look-ahead, cached), content/genre, on-demand ambient, conservative cadence | 1 | FR-ADAPT-01/04..08, NFR-PERF-02/04 | Adaptation imperceptible-as-motion; adapts with foresight |
| EP-HEAR | Guided calibration, hearing-profile contributor, safe-volume guard | 1 | FR-HEAR-01..05, FR-ADAPT-06, NFR-PRIV-03 | Calibration completion > 25% |
| EP-NLT | **(reframed)** Conversational Tuning — typed-macro interface, governing principle, **per-stem targeting (1.5)**, SAFE/SocialEQ priors + validation harness — **⛔ Won't, this horizon (re-anchor 2026-06-19; incl. OQ-14 multilingual)** | 1 (per-stem 1.5) | FR-NLT-01..12, LD-8 | NLT weekly active > 30%; phrase success > 75%; discomfort < 300 ms |
| EP-REIMAGINE | **(new)** The single intensity control (0 = bit-faithful → full reimagine); mix-range now, stem-range at 1.5 | 1 (stem-range 1.5) | FR-REIMAGINE-01..04, NFR-QUAL-03, LD-16 | Reimagine engagement; intensity-0 verified bit-transparent |
| EP-PROFILE | Named profiles, device↔profile binding, A/B mode, session NL principles | 1 | FR-DEVICE-04/05, FR-HEAR-03/04 | D30 active-use > 40% |
| EP-UI | Now Playing, DSP + **Reimagine** controls, onboarding, dark mode, accessibility, l10n-ready | 0→1 | FR-UI-01..07, NFR-ACC-01..04, NFR-L10N-01/03 | Rating > 4.3; onboarding < 3 min |
| EP-PRIVACY | Mic permission (on-demand), hearing-data encryption, **cloud-LLM context exclusions**, sandbox | 1 | NFR-PRIV-01..05 | No mic/hearing data in outbound traffic |
| EP-STEM | **(new — Phase 1.5)** Stem object engine: offline 6-stem separation + SSD cache, per-stem chains + spatial placement, between-stem unmasking, per-stem NL, quality-gating — **⛔ Won't, this horizon (re-anchor 2026-06-19)** | **1.5** | FR-STEM-01..06, FR-REIMAGINE (stem range), NFR-PERF-06 | Separation quality-gate pass; per-stem unmasking measurable; render budget held |
| EP-SYSWIDE | System-wide via **Core Audio process tap (primary, macOS 14.2+)** + libASPL fallback; **mix-level only** — **⛔ Won't, this horizon (re-anchor 2026-06-19)** | 2 | FR-SYS-07/08/01..06, NFR-PERF-05 | System-wide adoption; no admin password on tap path |
| EP-VDEVICE | AudioServerPlugIn **fallback** (older macOS / driver preference) — **⛔ Won't, this horizon (re-anchor 2026-06-19)** | 2 | FR-SYS-01..06, NFR-INSTALL-02..04 | Driver install success > 90% |
| EP-QA | **(new — re-anchor 2026-06-19) ✅ Done** DSP-gate hardening: automated regression gates for every shipped DSP stage, validated against independent oracles where possible (libebur128 LUFS/TP, limiter TP, 31-band EQ FR sweep, SRC alias/imaging, gapless-seam, RT-allocation soak) | 0 | NFR-QUAL-01..04, NFR-PERF-01/03, CON-01/02 | Null-test 105/0; golden master held; meter conformant ±0.047 LU vs libebur128 |
| EP-LIBRARY | **(new — v2.4, 2026-07-02)** Persistent library: multiple scan folders, single-file (non-library) play, stable durable track identity across moves/retags, cross-folder duplicates treated as normal distinct files (not deduped) | 0 | *(no FR/NFR yet — traces to `s8-1-persistent-store-design.md` + sprint-plan.md S8)* | Library survives a scan-folder move/rescan with zero broken playlist references; duplicates across folders never silently collapsed |
| EP-PLAYLIST | **(new — v2.4, 2026-07-02)** Playlists: many-to-many ordered membership, single non-library file added to a playlist, DnD reference-add (playlist) vs. potential real move (folder→folder), user/auto naming, built-in "current" queue playlist | 0 | *(no FR/NFR yet — traces to `s8-1-persistent-store-design.md` + sprint-plan.md S9/S10)* | Zero filesystem side-effects from playlist add/remove; a track survives in all its playlists across a folder→folder move |

> **Re-anchor note (v2.3, 2026-06-19):** Several Phase-0/Phase-1 epics now carry shipped Done stories (back-filled from the two-path engine, Pure Mode, decode, EQ, limiter, loudness, gapless, device-resilience, signal-path transparency). **EP-STEM**, **EP-SYSWIDE**, **EP-VDEVICE**, and **EP-NLT** are tagged **⛔ Won't, this horizon** per sprint-plan.md §6B — entries retained as the future roadmap, marked out-of-window. **DSD** (a feature, not an epic) is deferred post-R2, gated on acquiring a DSD DAC. See the v2.3 change note.

> **Epic migration note (v2.0):** `EP-SPAT` + `EP-HEADTRACK` → **`EP-IMMERSION`** (BRIR-first); `EP-AMBIENT` → folded into **`EP-ADAPT`**; perceptual decision-making split out into **`EP-PERCEPTUAL`**. Existing `US-SPAT-*` / `US-AMBIENT-*` stories below now live under the renamed epics; affected stories are annotated rather than rewritten.

---

## Phase 0 Stories — Own-Player MVP (Foundation)

### EP-ENGINE — Real-Time Audio Engine Skeleton

**Epic goal:** Establish the AVAudioEngine / AUHAL graph and C++ DSP module framework with a lock-free parameter bus before any feature work begins. This is the foundation every other Phase 0 epic depends on.

---

#### US-ENG-01 [Enabler] — AVAudioEngine graph bootstrap

As a **developer** I want a runnable AVAudioEngine graph that opens the default Core Audio output device, renders silence, and reports its buffer size and sample rate, so that all subsequent DSP modules have a stable audio thread to attach to.

**Acceptance Criteria:**
- Engine initialises on macOS 14 without errors on Apple Silicon (M1+).
- Buffer size and sample rate are logged at startup and match the device's preferred values (FR-DEVICE-06 / FR-ADAPT-05 context).
- Audio thread renders without XRuns for 10 minutes on an M1 Pro / 16 GB Mac (the floor; LD-18) (NFR-QUAL-02 baseline).
- Zero heap allocations in the render callback (CON-01); verified by Instruments Allocations with guard malloc.
- Instruments Thread State Trace shows no lock contention on the audio thread (CON-02).

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** none
**Traceability:** NFR-PERF-01, NFR-PERF-03, NFR-QUAL-02, CON-01, CON-02

---

#### US-ENG-02 [Enabler] — C++ DSP module framework with biquad EQ scaffold

> **⚠ Deviation flag (re-anchor v2.3, 2026-06-19):** this scaffold specified a **10-band** biquad EQ; what shipped is a **31-band** biquad cascade (kernel-clamped, ±12 dB). The framework, process(buffer,frames) interface, and bit-identical 0 dB bypass landed as written; only the band count diverged. See US-TON-01 (the corresponding deviation flag) and US-ENG-08.

As a **developer** I want a C++ DSP module framework that exposes a process(buffer, frames) interface and includes a working 10-band biquad EQ (all bands pass-through at 0 dB by default), so that tonal and adaptive modules can be slotted in without redesigning the chain.

**Acceptance Criteria:**
- Framework compiles with -Wall -Wextra -fno-exceptions on the audio thread translation unit (CON-01/CON-02 guard).
- 10-band biquad EQ with frequency, gain, and Q per band; at 0 dB all bands, output is bit-identical to input (NFR-QUAL-03).
- THD+N in bypass ≤ -90 dB at 1 kHz (NFR-QUAL-01).
- Module chain supports 44.1, 48, 88.2, and 96 kHz sample rates (NFR-QUAL-04).
- Pre-allocated audio buffers; no std::vector or new on the render path (CON-01).

**Priority:** Must | **Phase:** 0 | **Estimate:** 8 sp | **Dependencies:** US-ENG-01
**Traceability:** FR-TONAL-01, NFR-QUAL-01, NFR-QUAL-03, NFR-QUAL-04, CON-01, CON-02

---

#### US-ENG-03 [Enabler] — Lock-free SPSC parameter bus

As a **developer** I want a single-producer, single-consumer ring buffer (e.g., TPCircularBuffer) wiring the UI/adaptivity thread to the DSP audio thread, so that all parameter updates arrive without mutex or blocking on the render callback.

**Acceptance Criteria:**
- Parameter messages are consumed by the audio thread within the next render cycle after being enqueued (FR-ADAPT-02).
- Instruments Thread State Trace: zero audio-thread preemptions attributable to lock acquisition during a 5-minute stress test (FR-ADAPT-02 AC).
- Ring buffer depth sufficient for burst of 20 simultaneous parameter updates.
- Ring buffer is the only cross-thread mechanism on the hot path; no additional sync primitives introduced (CON-02).

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-ENG-02
**Traceability:** FR-ADAPT-02, CON-02, DEP-09

---

#### US-ENG-04 [Enabler] — Parameter smoothing / ramp engine

As a **developer** I want every DSP parameter change applied via a per-block linear ramp of at least 50 ms, so that automated and user-driven EQ changes never produce audible zipper noise.

**Acceptance Criteria:**
- See FR-ADAPT-03 Given/When/Then: gain 0 → +6 dB on a 1 kHz sine wave produces no audible click; ramp is >= 50 ms; verified by scope/FFT.
- Ramp applies to all band gains, dynamics thresholds, and spatial parameters uniformly.
- Ramp time is configurable per parameter type (e.g., EQ: 50 ms, profile crossfade: 200 ms).

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-ENG-03
**Traceability:** FR-ADAPT-03

---

#### US-ENG-05 [Enabler] — True-peak limiter (final DSP stage) ✅ DONE

As a **developer** I want a transparent true-peak limiter as the final stage in the DSP chain, so that no upstream gain change can cause the output to exceed -1 dBTP and damage hearing or clip the DAC.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** Shipped as the final stage of the Enhanced DSP chain (EQ → loudness → limiter → spatial-passthrough) with **8× ISP (inter-sample-peak) oversampling**. Validated in S7 under a dual-oracle true-peak gate: the −1 dBTP ceiling holds, including at intermediate steerable-intensity `x` (S6 Tier-3 steerable wet/dry primitive). Limiter threshold is adjustable by the control plane. (Pure Mode bypasses the limiter entirely — bit-perfect by design.) See sprint-plan.md §2 and the S7 row.

**Acceptance Criteria:**
- See FR-TONAL-07 Given/When/Then: +6 dB upstream gain on a 0 dBFS signal; output TP ≤ -1 dBTP verified by reference meter. ✅
- Limiter introduces no perceptible colouration at normal listening levels (verify by bypass A/B with white noise at -18 dBFS). ✅
- Limiter threshold is adjustable by the adaptivity engine (for FR-NLT-09 urgent path, Phase 1). ✅ (control-plane adjustable)

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-ENG-02 | **Status:** ✅ DONE (S7-gated)
**Traceability:** FR-TONAL-07, NFR-QUAL-01

---

#### US-ENG-06 [Enabler] — Sample-rate conversion and device negotiation

As a **developer** I want the DSP chain to query the output device's preferred sample rate and perform high-quality SRC when the source file's rate differs, so that a 44.1 kHz file plays correctly on a 48 kHz device and vice versa.

**Acceptance Criteria:**
- See FR-DEVICE-06 Given/When/Then: 44.1 kHz file on 48 kHz device plays at correct pitch and duration.
- SRC algorithm meets stopband attenuation ≥ 90 dB (NFR-QUAL-04).
- 88.2 and 96 kHz pass-through also verified (no SRC needed when rates match).

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-ENG-01
**Traceability:** FR-DEVICE-06, NFR-QUAL-04

---

#### US-ENG-07 [Enabler] — Bit-perfect Pure Mode (CoreAudio HAL-direct, hog mode, per-track rate-match) ✅ DONE

As a **Ramith** I want a bit-perfect playback path that drives the DAC directly through the CoreAudio HAL, takes the device into hog mode, matches the device's physical sample rate to each track, and bypasses all DSP, so that the bits I bought reach the DAC unaltered — something Apple Music itself does not do on macOS.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** Shipped as the **Pure** path of the two-path engine: HAL-direct output (`HALOutputEngine`), device hog mode, per-track sample-rate match (sets the device physical format, not a forced AU output rate), DSP fully bypassed. Phase A done; Phase B1/B2a/B2b done & pushed (`d59b853`); see `../sprints/09-phase-b-bit-perfect-pure-mode.md` and sprint-plan.md §2. **A real differentiator** — Apple Music is not bit-perfect on macOS. *By-ear verification on a USB DAC is still pending (offline null-test verified; founder owns the audible check).* Remaining items B3/B4/B5/A2 are tracked in the Pure-Mode sprint doc, not here.

**Acceptance Criteria:**
- HAL output renders directly to the default/selected device; DSP chain bypassed; output is sample-identical to source on a rate-matched device (offline null-test). ✅
- Device is taken into hog mode for exclusive bit-exact access; released cleanly on stop/teardown/device-loss. ✅
- Per-track sample-rate negotiation sets the device **physical** format to match the source (44.1/48/88.2/96/176.4/192 kHz) with a rate-match gate + diagnostics. ✅
- Bit-exactness is the verifiable contract: the S6 golden master (`0xE7267654BA01D315`) holds under the C++ null-test gate. ✅
- *Deferred (not part of Done):* by-ear confirmation on a USB DAC; B3/B4/B5/A2 polish.

**Priority:** Must | **Phase:** 0 | **Estimate:** 8 sp | **Dependencies:** US-ENG-01, US-ENG-06 | **Status:** ✅ DONE (`d59b853`; A2/B3–B5 deferred)
**Traceability:** FR-PLAY-01, FR-DEVICE-06, NFR-QUAL-03, NFR-QUAL-04

---

#### US-ENG-08 [Enabler] — Two-path Pure / Enhanced engine ✅ DONE

As a **developer** I want a runtime engine that selects between the bit-perfect **Pure** path and the DSP **Enhanced** path (with automatic fallback) on a per-session/per-track basis, so that the listener gets bit-exact output when no processing is requested and the full N-channel DSP graph when it is.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** The shipped engine is **two-path**, not the single mix-level graph this backlog originally described: **Pure** (HAL-direct, bit-perfect — US-ENG-07) and **Enhanced** (`AVAudioEngine` two-AU **N-channel** graph, ≤7.1, 48 kHz float: EQ → loudness → limiter → spatial-passthrough). Path selection + fallback model was reviewed in S6 and called "production-quality"; the S6 Tier-3 spine work (`RtSwappableResource<T>`, control-plane `Realizer`, steerable equal-power wet/dry intensity, `GaplessController` conformance suite) confirmed the spine is Phase-2-ready. See sprint-plan.md §2 + the S6 row, `../sprints/s6-tier3-spine-design.md`.

**Acceptance Criteria:**
- Engine exposes both paths; selects Pure when DSP is off / intensity-0 and a rate-match is achievable, else Enhanced. ✅
- Enhanced path is a two-AU N-channel graph (≤7.1, no naive downmix), 48 kHz float, chain order EQ → loudness → limiter → spatial-passthrough. ✅
- Automatic, glitch-tolerant fallback Pure→Enhanced when bit-exact conditions cannot be met. ✅
- intensity-0 on Enhanced is the bit-exact anchor (S6 Tier-3 steerable intensity; settled-ramp byte-identity verified in S7). ✅
- S6-reviewed for RT-safety, concurrency (engineQueue + leaf lock + device-loss serialization), and gain staging; all three tiers of fixes shipped. ✅

**Priority:** Must | **Phase:** 0 | **Estimate:** 8 sp | **Dependencies:** US-ENG-07, US-ENG-01, US-ENG-02 | **Status:** ✅ DONE (S6-hardened)
**Traceability:** FR-PLAY-01, NFR-QUAL-01..04, NFR-PERF-01, CON-01, CON-02

---

#### US-ENG-09 [Enabler] — BS.1770-5 loudness meter + LUFS normalization ✅ DONE

As a **Marcus** I want the engine to measure program loudness to the BS.1770-5 standard and normalize playback toward a target LUFS, so that tracks and albums play back at a consistent perceived level without me riding the volume knob.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** Shipped as the loudness stage of the Enhanced chain: a **BS.1770-5** integrated-loudness meter with active **LUFS normalization** (makeup gain). The architecture review (S6) noted the loudness module routes makeup gain through its own off-RT worker + double-buffer (a "canary" that motivated the Tier-3 `Realizer`). S7 validated the meter against the **libebur128** oracle (vendored test-only): conformant to **±0.047 LU**. We are *ahead* of most players on loudness. See sprint-plan.md §2 + the S7 row.

**Acceptance Criteria:**
- Integrated-loudness measurement conforms to ITU-R BS.1770-5 (K-weighting, gating); verified ±0.047 LU vs libebur128. ✅
- LUFS normalization applies a ramped makeup gain toward the target with no zipper noise; feeds the limiter for safe ceilings. ✅
- Meter runs off the RT thread; no audio-thread allocations (RT-allocation soak, S7). ✅
- Pure Mode does not apply normalization (bit-perfect). ✅

**Priority:** Should | **Phase:** 0/1 | **Estimate:** 5 sp | **Dependencies:** US-ENG-02, US-ENG-05 | **Status:** ✅ DONE (S7-gated vs libebur128)
**Traceability:** FR-TONAL-07, NFR-QUAL-01, NFR-PERF-04

---

#### US-ARCH-01 [Enabler] — Technical architecture review & hardening (S6 gate) ✅ DONE

As a **developer** I want a comprehensive multi-discipline review of the shipped codebase before any new feature work, with the agreed fixes landed and the C++ gate green, so that we harden the foundation and confirm the DSP spine carries the Phase-2 adaptive vision before building eight sprints on it.

> **Status: ✅ DONE (S6 gate — GREEN, 2026-06-19; back-filled by re-anchor v2.3).** A 4-discipline read-only review (system architecture, C++ RT-safety/lock-free, Swift concurrency & engine lifecycle, DSP correctness & gain staging) produced [`../sprints/s6-architecture-review-findings.md`](../sprints/s6-architecture-review-findings.md). **All three tiers of fixes shipped:** **Tier 1** RT-safety/lifecycle (e.g. P1-A full Schur-Cohn biquad-stability fix, P1-D HAL render-format RT corruption fix); **Tier 2** concurrency consolidation (engineQueue + leaf lock + device-loss serialization — P1-B/P1-C/P2-B/P2-C); **Tier 3 DSP spine** ([`../sprints/s6-tier3-spine-design.md`](../sprints/s6-tier3-spine-design.md)): `RtSwappableResource<T>` extracted (EQ migrated) + a control-plane **`Realizer`** (off-RT owner of the canonical `TargetState`, off-main EQ-cascade design, EQ+intensity coalescing, sole publisher, queue-draining teardown) + **steerable equal-power wet/dry intensity** (intensity-0 = bit-exact anchor) + a **`GaplessController`** conformance suite (Pure/Enhanced position-re-zero parity). **Gate-verified:** C++ null-test **93/0**, golden master `0xE7267654BA01D315` held. The spine is now confirmed Phase-2-ready (S15→S16→S17 build directly on it).

**Acceptance Criteria:**
- Findings document produced, grounded in file:line, founder-triaged. ✅
- P1 fixes (the one live bug + concurrency races + RT memory-safety edges) landed. ✅
- DSP spine architecture decided and built (off-RT Realizer, single canonical TargetState, steerable intensity, gapless contract). ✅
- C++ null-test green (93/0); golden master held. ✅

**Priority:** Must | **Phase:** 0 (gate) | **Estimate:** 8 sp | **Dependencies:** shipped codebase | **Status:** ✅ DONE (gate GREEN)
**Traceability:** NFR-PERF-01/03, NFR-QUAL-01..03, CON-01, CON-02

---

### EP-QA — DSP-Gate Hardening *(new — re-anchor v2.3, 2026-06-19)*

**Epic goal:** Give every shipped DSP stage an automated regression gate, validated against an independent oracle where one exists. Shipped as **S7** (✅ DONE, 2026-06-19): null-test **105/0**, golden master held. Cheap, pure safety; precedes any further DSP-touching work. Citations: sprint-plan.md S7 row + [`../sprints/s7-soak-instruments-procedure.md`](../sprints/s7-soak-instruments-procedure.md).

---

#### US-QA-01 — libebur128 LUFS/TP conformance oracle ✅ DONE

As a **developer** I want the BS.1770-5 loudness meter validated against the libebur128 reference, so that our LUFS/true-peak numbers are trustworthy.

> **Status: ✅ DONE (S7).** libebur128 vendored **test-only**; meter conformant **±0.047 LU** vs the oracle. Citations: sprint-plan.md S7 row.

**Acceptance Criteria:** integrated-loudness + TP measured against libebur128 over a fixture set; deviation within tolerance (±0.047 LU achieved). ✅
**Priority:** Must | **Phase:** 0 | **Estimate:** ~1.5 sp | **Dependencies:** US-ENG-09 | **Status:** ✅ DONE
**Traceability:** NFR-QUAL-01, FR-TONAL-07

---

#### US-QA-02 — EQ 31-band FR sweep + bit-transparent-bypass ✅ DONE

As a **developer** I want every one of the 31 EQ bands swept for frequency-response accuracy and the flat/bypass case proven bit-transparent, so that the EQ is provably correct end-to-end (incl. near-Nyquist).

> **Status: ✅ DONE (S7).** All 31 bands FR-accurate including near-Nyquist — clears the S6 P1-A Schur-Cohn stability concern; flat EQ verified bit-transparent. Citations: sprint-plan.md S7 row.

**Acceptance Criteria:** per-band FR within tolerance across the audible range incl. near-Nyquist; flat = bit-identical. ✅
**Priority:** Must | **Phase:** 0 | **Estimate:** ~1.5 sp | **Dependencies:** US-TON-01, US-ARCH-01 | **Status:** ✅ DONE
**Traceability:** FR-TONAL-01, NFR-QUAL-03

---

#### US-QA-03 — Limiter −1 dBTP guarantee + ISP-detector accuracy ✅ DONE

As a **developer** I want the true-peak limiter's −1 dBTP ceiling proven under a dual-oracle true-peak gate, including at intermediate steerable-intensity values, so that no gain configuration can breach the ceiling.

> **Status: ✅ DONE (S7).** Ceiling held under a dual-oracle TP gate; intermediate-intensity true-peak verified (S6 Tier-3 steerable intensity). Citations: sprint-plan.md S7 row.

**Acceptance Criteria:** output TP ≤ −1 dBTP across worst-case gain + intermediate intensity `x`; ISP detector accuracy validated. ✅
**Priority:** Must | **Phase:** 0 | **Estimate:** ~1.5 sp | **Dependencies:** US-ENG-05 | **Status:** ✅ DONE
**Traceability:** FR-TONAL-07, NFR-QUAL-01

---

#### US-QA-04 — SRC alias / stopband / imaging ✅ DONE

As a **developer** I want the sample-rate converter's alias/imaging products measured, so that rate conversion meets the quality bar.

> **Status: ✅ DONE (S7).** SRC imaging ≤ **−83.7 dBFS** via `SRCQualityMeasure`. Citations: sprint-plan.md S7 row.

**Acceptance Criteria:** alias/imaging products below the stopband target (≤ −83.7 dBFS achieved). ✅
**Priority:** Must | **Phase:** 0 | **Estimate:** ~1 sp | **Dependencies:** US-ENG-06 | **Status:** ✅ DONE
**Traceability:** NFR-QUAL-04

---

#### US-QA-05 — Gapless-seam regression (both paths) ✅ DONE

As a **developer** I want automated gapless-seam tests on both the Pure and Enhanced paths, so that the sample-accurate join is protected against regression.

> **Status: ✅ DONE (S7).** 14 gapless-seam tests covering both paths. Citations: sprint-plan.md S7 row.

**Acceptance Criteria:** seam join sample-accurate on both paths under the conformance suite. ✅
**Priority:** Must | **Phase:** 0 | **Estimate:** ~1.5 sp | **Dependencies:** US-PLAY-08, US-ARCH-01 | **Status:** ✅ DONE
**Traceability:** NFR-QUAL-03, FR-PLAY-01

---

#### US-QA-06 — RT-allocation soak + Instruments XRun procedure ✅ DONE

As a **developer** I want a soak test proving zero audio-thread allocations and a documented on-hardware XRun procedure, so that real-time safety is continuously verified.

> **Status: ✅ DONE (S7).** Soak proves zero audio-thread allocations (fast default; full 1-hr via `SOAK_FULL=1`) + an Instruments XRun procedure ([`../sprints/s7-soak-instruments-procedure.md`](../sprints/s7-soak-instruments-procedure.md)) for the on-hardware half. Citations: sprint-plan.md S7 row.

**Acceptance Criteria:** zero RT-thread allocations over the soak window; documented Instruments procedure for XRun verification. ✅
**Priority:** Must | **Phase:** 0 | **Estimate:** ~1 sp | **Dependencies:** US-ARCH-01 | **Status:** ✅ DONE
**Traceability:** CON-01, CON-02, NFR-PERF-03

---

### EP-PLAYER — Local File Playback

**Epic goal:** Deliver a functional music player for local files with standard controls, metadata display, queue management, and session state persistence.

---

#### US-PLAY-01 — Local file import and supported-format playback ✅ DONE (decode shipped)

As a **Marcus** I want to drag FLAC, ALAC, MP3, AAC, WAV, AIFF, and OGG files into the app and hear them immediately, so that I can load my existing library without format conversion.

> **Status: decode path ✅ DONE — runtime FFmpeg-or-Apple decode (back-filled by re-anchor v2.3, 2026-06-19).** Shipped as a runtime-selected `FileDecodeSource`: **FFmpeg via `dlopen` (with a baked major-version guard) or Apple's `ExtAudioFile`**, covering FLAC / ALAC / WAV / AIFF / Opus / MP3 / AAC. The decode backend is reported in the signal-path UI (US-ADAPT-06). See sprint-plan.md §2 and `../sprints/09-phase-b-bit-perfect-pure-mode.md`. *(The broader player UX — flat in-memory playlist + folder monitor — is shipped; persistent library/browse/queue is the still-unbuilt critical path, see sprint-plan.md §2 "biggest credibility gap" and S8–S10.)* Opus replaces OGG-Vorbis on the shipped list.

**Acceptance Criteria:**
- See FR-PLAY-01 Given/When/Then: file added to queue, Play pressed, audio within 500 ms, routed through the selected (Pure or Enhanced) path. ✅
- Drag-and-drop from Finder and from macOS Open panel both work. ✅
- Decode handled by runtime FFmpeg-or-Apple backend (FLAC/ALAC/WAV/AIFF/Opus/MP3/AAC); FFmpeg loaded via `dlopen` behind a baked major-version guard; unsupported formats surface FR-PLAY-06 rather than silent failure. ✅

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-ENG-01 | **Status:** ✅ DONE (decode); library UX pending (S8–S10)
**Traceability:** FR-PLAY-01, FR-PLAY-06

---

#### US-PLAY-02 — Playback controls (play, pause, skip, seek, volume)

As a **Marcus** I want play, pause, skip forward, skip backward, seek, and volume controls that respond within 100 ms, so that I can manage playback without breaking my listening flow.

**Acceptance Criteria:**
- See FR-PLAY-02 Given/When/Then: any control activated within 100 ms, no audio glitch.
- Media keys (F7/F8/F9) and Touch Bar (where applicable) trigger the same actions.
- Seek updates playback position correctly without dropout.

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-PLAY-01
**Traceability:** FR-PLAY-02

---

#### US-PLAY-03 — Playback queue with drag-to-reorder, remove, shuffle, and repeat

As a **Marcus** I want to build and reorder a playback queue and toggle shuffle and repeat, so that I can manage long listening sessions without manually restarting the app.

**Acceptance Criteria:**
- See FR-PLAY-03 Given/When/Then: drag-to-reorder in a 5-track queue; new order reflected immediately; next track plays in updated order.
- Remove track from queue without stopping current playback.
- Shuffle mode randomises remaining tracks; repeat-all and repeat-one both work.

**Priority:** Should | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-PLAY-01
**Traceability:** FR-PLAY-03

---

#### US-PLAY-04 — Track metadata and album art display

As a **Ramith** I want to see track title, artist, album, album art, and duration in the Now Playing view, so that I know what is playing without switching apps.

**Acceptance Criteria:**
- See FR-PLAY-04 Given/When/Then: ID3v2-tagged file; all metadata fields populated correctly.
- Missing art shows a tasteful placeholder; missing fields show empty/dash without crashing.
- Metadata reading occurs on a background thread; never blocks the audio thread.

**Priority:** Must | **Phase:** 0 | **Estimate:** 2 sp | **Dependencies:** US-PLAY-01
**Traceability:** FR-PLAY-04

---

#### US-PLAY-05 — Session state persistence across app restarts

As a **Marcus** I want the app to restore my queue and playback position when I reopen it, so that I can resume exactly where I stopped.

**Acceptance Criteria:**
- See FR-PLAY-05 Given/When/Then: app closed paused at 2:34; on relaunch, queue restored and track pre-loaded at 2:34 with same profile active.
- State written atomically to UserDefaults or a local JSON file on pause/close; partial writes do not corrupt state.
- If a queued file has been moved or deleted, the app shows an inline error for that track rather than crashing.

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-PLAY-01
**Traceability:** FR-PLAY-05

---

#### US-PLAY-06 — Unsupported format error surfacing

As a **Tom** I want the app to name the unsupported format and explain why it cannot play it when I drag in an unsupported file, so that I am not left wondering why the track is silent.

**Acceptance Criteria:**
- See FR-PLAY-06 Given/When/Then: unsupported format dragged in; inline error names the format and links to supported-formats list.
- Unsupported file does not appear as a valid queue entry; it is rejected at import.

**Priority:** Should | **Phase:** 0 | **Estimate:** 1 sp | **Dependencies:** US-PLAY-01
**Traceability:** FR-PLAY-06

---

#### US-PLAY-07 — Gapless trimming of lossy encoder delay/padding (FFmpeg decode path)

As a **Marcus** I want consecutive lossy tracks (AAC, MP3) to play gaplessly even when they are decoded by the FFmpeg backend, so that albums mastered to flow together (live recordings, DJ mixes, concept albums) do not get a sliver of silence inserted at every track boundary.

> **Context (post-v2.1):** Gapless / continuous playback shipped outside this backlog after v2.1 — Enhanced-path gapless + auto-advance (commit `cf33e5d`) and Pure-path same-rate gapless via `GaplessSource` + the runtime FFmpeg-or-Apple `FileDecodeSource` (commit `2e2242a`); see `docs/sprints/09-phase-b-bit-perfect-pure-mode.md`. This story is the remaining refinement: lossy files carry encoder-delay/priming + remainder-padding silence (AAC `iTunSMPB` / priming samples; MP3 LAME delay/padding) at their start/end. Apple's decoder (`ExtAudioFile`) already trims these via the file's edit list — so the gap only occurs when **FFmpeg is the active decode backend** for lossy files. Lossless (FLAC/ALAC/WAV/AIFF) has no encoder delay and is the bit-perfect priority.

**Acceptance Criteria:**
- On the Pure (bit-perfect HAL) path, the FFmpeg decode backend trims AAC encoder-delay/priming + remainder padding (`iTunSMPB` / AAC priming samples) and MP3 LAME encoder delay/padding before the decoded stream reaches the gapless seam.
- The Apple decode backend (`ExtAudioFile`) behaviour is unchanged (it already trims via the edit list); the Enhanced path (`AVAudioFile`) is likewise unchanged (already gapless for lossy).
- Offline-verifiable in the C++ null-test harness: decoding two same-format lossy fixtures (known encoder delay/padding) and concatenating them yields the sample-accurate join with no inserted silence at the seam. Requires committed encoded (AAC/MP3) test fixtures.
- Edge case (related Pure same-rate gapless predicate limitation, deferred from Stage 2a): `sameRateGaplessCompatible` compares `bitsPerChannel`, which is `0` for compressed formats — so MIXING a compressed (AAC, bits=0) and an uncompressed (WAV, bits=16) track at the same rate forces a needless reconfigure gap even though both decode to the same float format. Either exclude bits-per-channel from the predicate when a source is compressed, or normalise the compressed value to the decoded float format. (Consecutive same-format tracks — e.g. an all-AAC library — are unaffected.)

**Priority:** Could | **Phase:** 1 | **Estimate:** 3 sp | **Dependencies:** gapless Stage 1 (`cf33e5d`) + Stage 2a (`2e2242a`) — Pure `GaplessSource` + the `FileDecodeSource` FFmpeg backend
**Traceability:** FR-PLAY-01, NFR-QUAL-03, NFR-QUAL-04

---

#### US-PLAY-08 — Gapless / continuous playback ✅ DONE (Enhanced full + Pure same-rate)

As a **Marcus** I want consecutive tracks to play without a gap at the boundary, so that albums mastered to flow together (live recordings, DJ mixes, concept albums) play seamlessly.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** Shipped in two stages: **Stage 1 — Enhanced-path gapless (full)** (`cf33e5d`); **Stage 2a — Pure-path same-rate gapless** via the lock-free C++ `GaplessSource` (`2e2242a`). S6 unified the **contract** across both paths via a `GaplessController` conformance suite (Pure/Enhanced position-re-zero parity); S7 added 14 gapless-seam regression tests (both paths). *Pure same-rate gapless by-ear verification needs a USB DAC (offline-verified; founder owns the audible check).* The remaining refinement — lossy AAC/MP3 encoder-delay trimming on the FFmpeg backend + the compressed/uncompressed format-match-predicate edge case — is **US-PLAY-07** (Could, deferred). See `../sprints/09-phase-b-bit-perfect-pure-mode.md` and sprint-plan.md §2.

**Acceptance Criteria:**
- Enhanced path: consecutive tracks play with no inserted silence at the boundary. ✅
- Pure path: consecutive **same-rate** tracks play gaplessly via the lock-free `GaplessSource` (no audio-thread allocations). ✅
- A `GaplessController` contract + shared conformance test suite runs against both paths; position semantics re-zero correctly at the seam. ✅ (S6/S7)
- *Deferred (US-PLAY-07):* lossy encoder-delay trim on the FFmpeg backend; cross-format same-rate predicate edge case.

**Priority:** Should | **Phase:** 0/1 | **Estimate:** 8 sp | **Dependencies:** US-ENG-07, US-ENG-08, US-PLAY-01 | **Status:** ✅ DONE (`cf33e5d`, `2e2242a`; lossy trim → US-PLAY-07)
**Traceability:** FR-PLAY-01, FR-PLAY-03, NFR-QUAL-03, NFR-QUAL-04

---

#### US-PLAY-09 — Auto-advance to next track ✅ DONE

As a **Marcus** I want playback to advance automatically to the next track in the queue when the current one ends, so that an album or playlist plays through without my intervention.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** Shipped alongside gapless (`cf33e5d`). S6 flagged a drift edge case (advance-by-one-per-tick on very short files / UI stalls — finding P2-I); the fix (advance by the actual transition delta) was folded into the Tier-2 concurrency hardening. See sprint-plan.md §2 + the S6 row.

**Acceptance Criteria:**
- On track end, playback advances to the next queue entry without a manual skip. ✅
- Advance is by the actual transition delta, robust to multiple boundaries per UI tick (S6 P2-I fix). ✅
- Honours repeat-one / repeat-all / shuffle when set (US-PLAY-03). ✅

**Priority:** Should | **Phase:** 0 | **Estimate:** 2 sp | **Dependencies:** US-PLAY-08, US-PLAY-03 | **Status:** ✅ DONE (`cf33e5d`; P2-I fixed)
**Traceability:** FR-PLAY-02, FR-PLAY-03

---

### EP-TONAL — Tonal and Dynamic Optimization

**Epic goal:** Implement the parametric EQ, device correction profiles, Fletcher-Munson loudness compensation, psychoacoustic bass enhancement, adaptive dynamics, and preset library.

---

#### US-TON-01 — 31-band live UI-driven EQ with real-time visualisation ✅ DONE *(⚠ deviation: spec said 10-band)*

As a **Tom** I want a graphic EQ where I can drag the response curve per band and see the resulting curve update in real time, so that I can fine-tune the sound to my preference as a manual escape hatch.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** Shipped as a **real, live, UI-driven 31-band** graphic EQ — drag the response curve directly, ±12 dB, kernel-clamped. **⚠ Deviation flag:** this backlog (US-TON-01 and the US-ENG-02 scaffold) specified a **10-band parametric** EQ; what shipped is a **31-band graphic** EQ. The deviation is recorded for traceability honesty; the band count and interaction model changed, the FR-TONAL-01 intent (live, accurate, resettable per-band tonal control) is met. The EQ was migrated onto the S6 Tier-3 `RtSwappableResource<T>` and its off-RT cascade realization moved into the control-plane `Realizer` (no biquad design on the audio thread). S7 validated **all 31 bands** for FR accuracy including near-Nyquist (clears the S6 P1-A Schur-Cohn stability concern) and confirmed bit-transparent bypass. **Still missing (not part of this Done):** EQ **presets**, **parametric** bands, and **device-correction / AutoEq import** — those are S12 (US-TON-02, US-TON-06) and tonal-parity scope. See sprint-plan.md §2 + the S6/S7 rows.

**Acceptance Criteria:**
- See FR-TONAL-01 Given/When/Then: band at 200 Hz, +6 dB; FFT output shows +6 dB peak centred at the band ±0.5 dB. ✅ (validated across all 31 bands incl. near-Nyquist, S7)
- EQ curve visualisation updates within one render cycle of any band change (< 23 ms at 512 frames / 44.1 kHz — FR-UI-02). ✅
- User can reset all bands to 0 dB; at flat the EQ is bit-transparent (S7 bypass test). ✅
- *Deferred (not Done):* presets (US-TON-06), parametric bands + AutoEq import (S12 / US-TON-02), device-correction auto-load (US-TON-02 / S13).

**Priority:** Should | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-ENG-02, US-ENG-03, US-ENG-04 | **Status:** ✅ DONE (31-band; presets/PEQ/AutoEq pending → S12)
**Traceability:** FR-TONAL-01, FR-UI-02

---

#### US-TON-02 — Device correction EQ (headphone and speaker profiles)

As a **Marcus** I want the app to automatically apply a frequency response correction for my AirPods Pro or Sony WH-1000XM5, so that the headphones sound as neutrally balanced as the driver allows right out of the box.

**Acceptance Criteria:**
- See FR-TONAL-02 Given/When/Then: "Apple AirPods Pro 2" identified; correction profile loaded and togglable on/off with audible difference.
- At least 20 device correction profiles ship at launch (per P0-6: AirPods, Sony, Bose, Sennheiser, Mac built-in — covering common output devices).
- Correction data sourced from AutoEQ (MIT license) or self-measured and validated (ASM-05).
- Toggle persists per profile.

**Priority:** Should | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-ENG-02, US-DEVICE-03, SPIKE-DEVCORRLIB
**Traceability:** FR-TONAL-02, DEP-07, ASM-05

---

#### US-TON-03 — Fletcher-Munson loudness-compensated EQ

As a **Ramith** I want the app to automatically boost bass and treble when I turn the volume down, so that music sounds full and warm even at low volume.

**Acceptance Criteria:**
- See FR-TONAL-03 Given/When/Then: volume reduced by 20 dB; bass (80–200 Hz) increases ~6–10 dB; highs (8–12 kHz) increases ~3–5 dB per ISO 226 curves; applied within one DSP processing block.
- Compensation updates on every volume change event (FR-ADAPT-05).
- Compensation is limited to a configurable maximum boost (default: +12 dB) to prevent distortion on laptop speakers.
- No audible discontinuity during volume changes (ramp per US-ENG-04).

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-ENG-03, US-ENG-04
**Traceability:** FR-TONAL-03, FR-ADAPT-05

---

#### US-TON-04 — Psychoacoustic bass enhancement for small speakers

As a **Ramith** I want the app to generate harmonic partials of sub-bass frequencies on small or built-in speakers so that I can feel bass weight even though the speakers cannot reproduce low fundamentals.

**Acceptance Criteria:**
- See FR-TONAL-04 Given/When/Then (updated): MacBook built-in speakers, bass-heavy track; enhancement active; harmonic partials of sub-bass (below 80 Hz) audible from a **mono-summed (L+R) low-band** signal; no distortion artefacts on casual listen.
- **Patent constraint (CON-11):** Bass harmonics MUST be generated from a mono-summed (L+R) low band. Per-channel (stereo) harmonic generation is prohibited — it falls within Waves US-11,102,577 (active, ~2038). Verifiable by inspecting the signal path: the NLD input must be L+R, not separate L and R signals.
- Enhancement is automatically enabled only for devices classified as small speakers or in-ear headphones (FR-DEVICE-03 / Adaptivity Signal Matrix: output device type).
- Enhancement strength configurable via the DSP controls panel.
- Engineering may proceed; **public release blocked** until SPIKE-IPREVIEW IP review is complete (OQ-16).

**Priority:** Could | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-ENG-02, US-DEVICE-03, SPIKE-IPREVIEW (for public release only)
**Traceability:** FR-TONAL-04, FR-DEVICE-03, CON-11, OQ-16

---

#### US-TON-05 — Adaptive multi-band dynamics (compressor/limiter)

As a **Marcus** I want the app to apply appropriate compression per content type (e.g., preserve dynamics for classical, more compression for podcasts), so that every genre sounds natural and intelligible without me touching any settings.

**Acceptance Criteria:**
- See FR-TONAL-05 Given/When/Then: classical track, Quiet ambient; ratio < 1.5:1; switching to Loud ambient increases ratio ≥ 3:1.
- Attack and release parameters are genre-appropriate per the Adaptivity Signal Matrix.
- Parameter updates go through lock-free bus and ramp (US-ENG-03, US-ENG-04); no zipper noise on ratio changes.

**Priority:** Must | **Phase:** 0 | **Estimate:** 8 sp | **Dependencies:** US-ENG-02, US-ENG-03, US-ENG-04, US-ENG-05, US-ADAPT-01
**Traceability:** FR-TONAL-05, NFR-QUAL-02

---

#### US-TON-06 — Tonal preset library (8+ named presets)

As a **Tom** I want to select from named presets (Neutral, Warm, Bright, Bass Boost, Podcast, Film, Classical, Electronic) and save custom variations, so that I can quickly switch tonal characters without manual EQ work.

**Acceptance Criteria:**
- See FR-TONAL-06 Given/When/Then: "Electronic" preset selected; EQ parameters update within one render cycle; "Save as Custom" appears on any subsequent adjustment.
- At least 8 named presets shipped.
- Custom presets are stored in the profile system (FR-DEVICE-04) and survive app restarts.

**Priority:** Should | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-TON-01, US-DEVICE-04
**Traceability:** FR-TONAL-06, FR-DEVICE-04

---

### EP-ADAPT — Adaptivity Engine and Content Classification

**Epic goal:** Build the FFT-based content/genre classifier, the adaptivity engine orchestrator that coordinates all DSP signals, the volume tracker, and the transparency view.

---

#### US-ADAPT-01 [Enabler] — FFT spectrum analysis pipeline

As a **developer** I want a real-time FFT analysis pipeline running on a non-real-time background thread that feeds spectral data into the adaptivity engine within 5 seconds of a track starting, so that all content-aware features have the signal data they need.

**Acceptance Criteria:**
- FFT runs on a non-real-time thread (separate from the audio render callback); audio thread is not blocked (CON-02).
- Window size and hop configurable; default 2048-sample FFT at 44.1 kHz.
- Spectral data (magnitude spectrum, spectral centroid, RMS energy) delivered to adaptivity engine via lock-free channel.
- Classification latency: first classification result within 5 s of track start (NFR-PERF-04).
- CPU usage for classifier ≤ 10% of one core (NFR-PERF-04).

**Priority:** Must | **Phase:** 0 | **Estimate:** 8 sp | **Dependencies:** US-ENG-01, US-ENG-03
**Traceability:** FR-ADAPT-01, NFR-PERF-04, DEP-02

---

#### US-ADAPT-02 — Content/genre classification (DSP heuristics)

As a **Marcus** I want the app to automatically detect whether I am playing classical, electronic, rock, acoustic, or speech and adjust the tonal and dynamic profile accordingly, so that every genre sounds like it was specifically tuned.

**Acceptance Criteria:**
- See FR-ADAPT-01 Given/When/Then: electronic track with dominant bass + 4/4 drum pattern; classified as "Electronic" within 5 s; genre-tuned curve applied.
- Six minimum classifications: speech, classical, electronic/bass-heavy, acoustic/folk, rock/metal, other.
- Classification uses DSP heuristics only (spectral centroid, BPM estimation, onset detection) — no Core ML in Phase 0 (LD-5).
- Genre change between tracks triggers a smooth crossfade (per US-ENG-04), not an abrupt shift.
- Adaptivity Signal Matrix tonal and dynamics rules per genre are implemented and verifiable in the transparency view (US-ADAPT-04).

**Priority:** Must | **Phase:** 0 | **Estimate:** 8 sp | **Dependencies:** US-ADAPT-01
**Traceability:** FR-ADAPT-01, LD-5, NFR-PERF-04

---

#### US-ADAPT-03 — Volume-level tracking and signal dispatch

As a **developer** I want the adaptivity engine to monitor current playback volume continuously and dispatch updated compensation curve parameters to the DSP chain within 100 ms of any volume change, so that Fletcher-Munson compensation is always current.

**Acceptance Criteria:**
- See FR-ADAPT-05 Given/When/Then: volume 50% → 30%; compensation EQ parameters update within 100 ms; no audio dropout.
- Volume is monitored via system volume API (kAudioHardwareServiceDeviceProperty_VirtualMainVolume) and the in-app volume control.
- Dispatch uses lock-free bus (US-ENG-03); ramp applied (US-ENG-04).

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-ENG-03, US-ENG-04, US-TON-03
**Traceability:** FR-ADAPT-05

---

#### US-ADAPT-04 — Adaptation transparency view *(NOT YET BUILT — distinct from US-ADAPT-06)*

> **⚠ Deviation / scope-distinction flag (re-anchor v2.3, 2026-06-19):** A **signal-path** transparency UI shipped (Pure vs Enhanced, sample rate, decode backend — see new **US-ADAPT-06**). That is **not** this story. **US-ADAPT-04 is the adaptation-transparency view** — which signals (volume / genre / device) are driving which DSP changes in real time. It is **still unbuilt** (it presupposes the adaptive engine of EP-ADAPT/EP-PERCEPTUAL, which is also unbuilt). Do **not** mark this Done on the strength of the signal-path UI; they are different features for different audiences.

As a **Tom** I want to open a debug/analysis view that shows exactly which signals are driving which DSP changes in real time, so that I can understand and trust what the engine is doing.

**Acceptance Criteria:**
- See FR-ADAPT-07 Given/When/Then: adaptivity engine active; Transparency view open; each active signal listed with current value and DSP adjustment; updates at ≥ 2 Hz.
- View shows at minimum: Volume level → bass/treble gain; Genre → EQ curve name; Device type → spatialisation mode.
- Each row has an inline Undo link (required for Phase 1 NLT history rows — future-proofing the data model now).
- View is accessible via VoiceOver (NFR-ACC-01).

**Priority:** Should | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-ADAPT-02, US-ADAPT-03
**Traceability:** FR-ADAPT-07, NFR-ACC-01

---

#### US-ADAPT-05 — Adaptation strength slider

As a **Tom** I want a master Adaptation Strength slider (0–100%) that lets me dial back how aggressively the engine modifies the sound, so that I can choose how much automation I want while keeping my manual EQ corrections.

**Acceptance Criteria:**
- See FR-ADAPT-08 Given/When/Then: Adaptation Strength = 0%; content/volume/ambient all change; DSP parameters do not change from baseline (verifiable in Transparency view).
- At 100% (default), full adaptive range is active.
- Slider position persists per profile.

**Priority:** Should | **Phase:** 0 | **Estimate:** 2 sp | **Dependencies:** US-ADAPT-02, US-ADAPT-03, US-ADAPT-04
**Traceability:** FR-ADAPT-08

---

#### US-ADAPT-06 — Signal-path transparency UI (Pure vs Enhanced, rate, decode backend) ✅ DONE *(⚠ distinct from US-ADAPT-04)*

As a **Ramith** I want a Roon-style readout of exactly how the engine is handling the current track — bit-perfect Pure vs DSP Enhanced, the active sample rate, and which decode backend is in use — so that I can trust the playback path and confirm bit-exactness at a glance.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** Shipped: a **signal-path transparency** readout (Pure vs Enhanced path, current sample rate, decode backend = FFmpeg or Apple). This is a parity feature mature players (Roon, Audirvana) nail. **⚠ Scope-distinction flag:** this is the **SIGNAL-PATH** transparency view — it is *not* the **ADAPTATION**-transparency view of **US-ADAPT-04** (which shows which signals drive which DSP changes and remains unbuilt). The two are deliberately separated in the backlog to keep requirements traceability honest. See sprint-plan.md §2.

**Acceptance Criteria:**
- View shows the active path (Pure / Enhanced), current sample rate, and decode backend (FFmpeg / Apple). ✅
- Reflects per-track changes (e.g. a rate change or a Pure→Enhanced fallback) without restart. ✅
- *Out of scope (→ US-ADAPT-04):* signal→DSP-adjustment attribution rows; adaptive-engine activity.

**Priority:** Should | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-ENG-07, US-ENG-08, US-PLAY-01 | **Status:** ✅ DONE (signal-path; adaptation transparency = US-ADAPT-04, unbuilt)
**Traceability:** FR-UI-01, FR-ADAPT-07 (signal-path subset; full FR-ADAPT-07 → US-ADAPT-04)

---

### EP-DEVICE — Device Enumeration, Classification, and Profile Switching

**Epic goal:** Enumerate Core Audio output devices, classify them by type, auto-switch DSP profiles on plug/unplug, and enable user-created named profiles.

---

#### US-DEVICE-01 [Enabler] — Output device enumeration and change listener

As a **developer** I want the app to enumerate all available Core Audio output devices on launch and register an AudioObjectAddPropertyListenerBlock callback so that device changes are detected immediately, so that profile switching logic has a reliable device event source.

**Acceptance Criteria:**
- See FR-DEVICE-01 Given/When/Then: two devices connected; both appear with correct names and type icons.
- Callback fires on the non-real-time thread within 100 ms of a device plug/unplug event.
- Device list updates UI without a restart.

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-ENG-01
**Traceability:** FR-DEVICE-01, FR-DEVICE-02

---

#### US-DEVICE-02 — Device-change auto-profile switching with crossfade

As a **Marcus** I want the DSP profile to switch automatically within 500 ms when I plug in or unplug headphones, with no audio dropout and a smooth crossfade, so that my listening is never interrupted.

**Acceptance Criteria:**
- See FR-DEVICE-02 Given/When/Then: AirPods Pro profile saved; AirPods connected; profile loaded within 500 ms; no dropout.
- Journey 2.4 Step 3: crossfade window = 200 ms default (configurable); ring buffer absorbs the gap.
- Non-blocking banner confirms the switch (Journey 2.4 Step 4).
- If no specific profile exists for the new device, the generic profile for the device category is loaded.

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-DEVICE-01, US-ENG-03, US-ENG-04
**Traceability:** FR-DEVICE-02, NFR-REL-03

---

#### US-DEVICE-03 — Device type classification (in-ear, over-ear, built-in speakers, etc.)

As a **developer** I want connected output devices classified into six categories (in-ear headphones, over-ear headphones, built-in speakers, external speakers, DAC/amplifier, unknown) using device name heuristics and Core Audio transport type, so that spatialisation mode and bass enhancement are selected automatically.

**Acceptance Criteria:**
- See FR-DEVICE-03 Given/When/Then: AirPods Pro identified as "in-ear headphones"; HRTF + headphone correction pipeline auto-selected.
- Built-in MacBook speaker classified as "built-in speakers"; speaker widening and psychoacoustic bass enhancement selected.
- Unknown devices default to neutral/headphones profile with a prompt to select category manually.

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-DEVICE-01
**Traceability:** FR-DEVICE-03

---

#### US-DEVICE-04 — Named profile creation, editing, and device association

As a **Tom** I want to create named DSP profiles ("Night Mode — AirPods," "Office — Sony"), link them to specific output devices, and switch between them from the device menu, so that I can maintain different listening setups without re-configuring the app every time I switch headphones.

**Acceptance Criteria:**
- See FR-DEVICE-04 Given/When/Then: "Night Mode — AirPods" created with custom EQ; AirPods connected; app offers to auto-load; manual switch also available.
- Profile stores: EQ bands, spatialization settings, dynamics settings, Adaptation Strength, linked device ID.
- Profiles persist across app restarts (FR-PLAY-05 persistence layer reused).
- At least 3 profiles can coexist; no artificial limit imposed.

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-DEVICE-02, US-TON-01
**Traceability:** FR-DEVICE-04

---

#### US-DEVICE-05 — Profile import and export (JSON)

As a **Tom** I want to export any profile as a JSON file and import it on another Mac, so that I can share my carefully tuned settings with other users.

**Acceptance Criteria:**
- See FR-DEVICE-05 Given/When/Then: profile exported; imported on different Mac; all parameters correctly restored and audible.
- Export uses a versioned schema; import validates schema version before applying.
- Import/export available from profile menu.

**Priority:** Could | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-DEVICE-04
**Traceability:** FR-DEVICE-05

---

#### US-DEVICE-06 — Speaker stereo widening and spatialisation mode auto-switch

As a **Ramith** I want the app to automatically switch to stereo widening mode when I am using MacBook speakers and back to HRTF mode when I plug in headphones, so that I get the appropriate spatialisation for each device without manual intervention.

**Acceptance Criteria:**
- See FR-SPAT-06 Given/When/Then: active output is speakers; HRTF inactive; stereo width processing applied; mid/side balance adjustable.
- See FR-SPAT-07 Given/When/Then: device changes headphones → speakers; spatialisation mode updates within 500 ms; banner confirms; override available.
- Mode transition uses crossfade (US-ENG-04); no audible click.

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-DEVICE-03, US-ENG-04
**Traceability:** FR-SPAT-06, FR-SPAT-07

---

#### US-DEVICE-07 — Basic crossfeed for headphones

As a **Marcus** I want the app to apply Bauer stereophonic-to-binaural crossfeed on headphones so that hard-panned elements feel less fatiguing and more natural over long listening sessions.

**Acceptance Criteria:**
- See FR-SPAT-03 Given/When/Then: hard-panned stereo on headphones; crossfeed enabled at default (~700 Hz crossover); channel separation measurably reduced via FFT; no perceived image collapse.
- Crossfeed is automatically active when device is classified as headphones (any type); disabled for speakers.
- Crossfeed level is adjustable in the DSP controls panel (0 = off, default = moderate Bauer level).
- **Licence gate (OQ-17 / CON-12):** If SPIKE-LIBBS2B confirms libbs2b is MIT, use it. If not clearly permissive, the implementation shall be a clean-room reimplementation of the Bauer algorithm from the public specification (biquad filters + delay). This story is blocked on SPIKE-LIBBS2B resolution.

**Priority:** Should | **Phase:** 0 | **Estimate:** 3 sp (or +2 sp if clean-room reimplement is needed) | **Dependencies:** US-DEVICE-03, US-ENG-02, SPIKE-LIBBS2B
**Traceability:** FR-SPAT-03, DEP-16, CON-12, OQ-17

---

#### US-DEVICE-08 — Bluetooth device sample-rate negotiation and auto-adaptation

As a **Marcus** I want the app to detect my Bluetooth device's native sample rate (e.g., 44.1 kHz on AirPods) and automatically adapt to it, rather than forcing 48 kHz resampling on the device, so that I get better battery life and lower latency on wireless headphones.

**Acceptance Criteria:**
- See FR-DEVICE-01 + new AC: device enumerated; native sample rate detected via CoreAudio property API (kAudioDevicePropertyNominalSampleRate).
- App offers two options (UI setting or auto-detect default):
  - **Auto-detect (default):** Use device's native sample rate if available; fallback to 48 kHz if detection fails.
  - **Force 48 kHz:** User override for devices where native rate causes issues.
- Status bar displays current sample rate (e.g., "48.0 kHz") and "Resampling" badge if OS is resampling.
- Sample-rate choice persists per device profile (US-DEVICE-04).
- Common Bluetooth rates supported: 44.1, 48, 96 kHz (future: 192 kHz in Phase 2).
- Reference tone (1 kHz) generated at the negotiated sample rate with no audible artifacts.
- No dropouts or latency increase compared to hardcoded 48 kHz.
- Manual QA on ≥2 Bluetooth device types (Apple AirPods + one other, e.g., Bose, Beats) verified (NFR-REL-03).

**Priority:** Could | **Phase:** 1.5 | **Estimate:** 3 sp | **Dependencies:** US-DEVICE-01, US-DEVICE-02, US-DEVICE-04
**Traceability:** FR-DEVICE-01, FR-DEVICE-02, FR-DEVICE-06, NFR-REL-03, NFR-PERF-01

---

#### US-DEVICE-09 — Device-loss resilience + pin/follow connect-behavior ✅ DONE

As a **Marcus** I want playback to survive a device disappearing (BT/USB unplug, sleep) and a setting that controls whether playback **follows** a newly-connected device or **pins** to the current one, so that an accidental disconnect doesn't kill the session and I decide what happens when a new DAC appears.

> **Status: ✅ DONE (back-filled by re-anchor v2.3, 2026-06-19).** Shipped: device-loss resilience (pause/recover on disconnect) on both paths + a **pin/follow connect-behavior setting** (`cf33e5d`). This path was a primary focus of the **S6** review — it surfaced a device-disconnect double-handler race (P1-B) and unsynchronized shared state (P1-C); the **Tier-2** concurrency consolidation (engineQueue + leaf lock + **device-loss serialization**) and Tier-1 RT-safety/lifecycle fixes resolved them and shipped. See sprint-plan.md §2 + the S6 row + `../sprints/s6-architecture-review-findings.md` (P1-B/P1-C).

**Acceptance Criteria:**
- On device loss (BT/USB unplug, sleep), playback pauses cleanly and recovers without a crash or `-10875` storm; HAL hog mode released. ✅
- Connect-behavior setting: **follow** (switch to the newly-connected device) or **pin** (stay on the current device). ✅
- Device-loss + config-change handlers are serialized (no double-handler race); shared transport state is confined/guarded (S6 Tier-1/Tier-2 fixes). ✅

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-DEVICE-01, US-DEVICE-02, US-ENG-07, US-ENG-08 | **Status:** ✅ DONE (`cf33e5d`; S6-hardened P1-B/P1-C)
**Traceability:** FR-DEVICE-01, FR-DEVICE-02, NFR-REL-01, NFR-REL-03

---

### EP-UI — Now Playing View, Controls Panel, Onboarding, and Accessibility

**Epic goal:** Deliver the full SwiftUI shell — Now Playing view with spectrum analyser, DSP controls panel, first-run onboarding wizard, dark/light mode, VoiceOver, keyboard navigation, and localisation-ready strings.

---

#### US-UI-01 — Now Playing view with spectrum analyser

As a **Marcus** I want a persistent Now Playing view showing album art, track metadata, playback controls, a real-time spectrum analyser at ≥ 30 fps, and the active profile name, so that I can see what is playing and how the engine is processing it at a glance.

**Acceptance Criteria:**
- See FR-UI-01 Given/When/Then: track playing; spectrum analyser updates ≥ 30 fps; all metadata visible without scrolling on 13-inch MacBook display.
- Spectrum analyser is powered by the FFT pipeline (US-ADAPT-01); does not re-run its own FFT.
- VoiceOver label for analyser reads accessible text equivalent (e.g., "Spectrum: Bass heavy, moderate highs") — FR-UI-05.

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-PLAY-04, US-ADAPT-01
**Traceability:** FR-UI-01, FR-UI-05, NFR-ACC-01

---

#### US-UI-02 — DSP controls panel

As a **Tom** I want a single panel that exposes EQ bands, spatialisation toggle, dynamics controls, and profile selector without navigating into settings, so that I can tune the sound mid-session without losing my flow.

**Acceptance Criteria:**
- See FR-UI-02 Given/When/Then: panel open; EQ band adjusted; change audible in next render cycle (< 23 ms at 512 frames); EQ curve visualisation updates immediately.
- Panel accessible via keyboard shortcut (no mouse required) — NFR-ACC-02.
- All controls have meaningful VoiceOver labels — NFR-ACC-01.

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-TON-01, US-DEVICE-04
**Traceability:** FR-UI-02, NFR-ACC-01, NFR-ACC-02

---

#### US-UI-03 — First-run onboarding wizard

As a **Ramith** I want a first-run wizard that detects my output device, explains what the app does in one screen, and lets me start listening in under 3 minutes without being forced to complete any step, so that I can get value immediately without learning anything about audio.

**Acceptance Criteria:**
- See FR-UI-04 Given/When/Then: user skips all steps; main player view reached within 10 seconds with default settings active.
- Journey 2.1: Steps 1–6 implemented; device detected and displayed; skip available at every step.
- Mic permission dialog uses NSMicrophoneUsageDescription string explaining purpose in plain English (NFR-PRIV-02).
- Hearing check step present but skippable (FR-HEAR-01 hearing test itself is Phase 1; onboarding step is a placeholder with "coming soon" or skip-always in Phase 0).
- Onboarding state persisted; wizard does not re-run on subsequent launches.

**Priority:** Must | **Phase:** 0 | **Estimate:** 5 sp | **Dependencies:** US-DEVICE-01, US-PLAY-01
**Traceability:** FR-UI-04, NFR-PRIV-02

---

#### US-UI-04 — Dark mode and light mode support

As a **Ramith** I want the app to match macOS dark or light mode automatically and switch in real time, so that it feels native and does not clash with the rest of my desktop.

**Acceptance Criteria:**
- See FR-UI-06 Given/When/Then: system switches to Dark Mode while app is open; all windows update to dark theme without restart; no illegible text or invisible controls.
- All colours defined using semantic NSColor/SwiftUI Color tokens (not hardcoded hex values).

**Priority:** Must | **Phase:** 0 | **Estimate:** 2 sp | **Dependencies:** US-UI-01
**Traceability:** FR-UI-06

---

#### US-UI-05 — VoiceOver and keyboard accessibility

As a **developer** I want every interactive control to have a meaningful VoiceOver label and be operable via keyboard alone, so that the app meets macOS accessibility standards at launch.

**Acceptance Criteria:**
- See FR-UI-05 Given/When/Then: VoiceOver enabled; DSP controls panel navigated via arrow keys; every slider and button announces label and current value.
- All primary functions (play/pause, skip, volume, profile select, DSP toggle) accessible via keyboard shortcuts with no conflicts with standard macOS shortcuts (NFR-ACC-02).
- Reduce Motion: all animations disabled or reduced when macOS "Reduce Motion" is active (NFR-ACC-04 — see AC).

**Priority:** Must | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-UI-02
**Traceability:** FR-UI-05, NFR-ACC-01, NFR-ACC-02, NFR-ACC-04

---

#### US-UI-06 — Localisation-ready string externalisation

As a **developer** I want all user-visible strings stored in .strings files from day one with no hardcoded English strings in UI components, so that future localisation requires only translation without code changes.

**Acceptance Criteria:**
- All strings in Views and ViewModels reference NSLocalizedString or SwiftUI LocalizedStringKey; no inline string literals in UI code (NFR-L10N-01).
- Build lint rule or CI check fails if a hardcoded UI string is introduced.
- No audio processing logic depends on locale settings for numeric formatting (NFR-L10N-03).

**Priority:** Must | **Phase:** 0 | **Estimate:** 2 sp | **Dependencies:** none
**Traceability:** NFR-L10N-01, NFR-L10N-03

---

#### US-UI-07 — Adaptive UI feedback (engine activity indicators)

As a **Marcus** I want subtle visual feedback when the adaptivity engine changes a DSP parameter, so that I can see the engine working without it being distracting.

**Acceptance Criteria:**
- See FR-UI-07 Given/When/Then: bass EQ updated by 3 dB; bass band indicator briefly animates; does not disrupt user interaction.
- Reduce Motion compliance: animation disabled when NFR-ACC-04 applies; state change shown by colour pulse instead.

**Priority:** Should | **Phase:** 0 | **Estimate:** 2 sp | **Dependencies:** US-UI-02, US-ADAPT-02
**Traceability:** FR-UI-07, NFR-ACC-04

---

### EP-PRIVACY — Privacy, Permissions, and Sandbox Compliance

**Epic goal:** Ensure mic permission is handled transparently, hearing data is encrypted locally, telemetry is opt-in, and the app is sandbox compliant for App Store submission.

---

#### US-PRIV-01 — Microphone permission UX and denial graceful fallback

As a **Ramith** I want the app to explain in plain language why it needs the microphone before requesting permission, and I want to know that ambient sensing will simply be unavailable (not broken) if I deny, so that I feel safe granting or declining without anxiety.

**Acceptance Criteria:**
- See NFR-PRIV-02 Given/When/Then: user denies microphone; all features except ambient adaptation function normally; persistent dismissable banner shown.
- NSMicrophoneUsageDescription string: "Used only to sense room noise — never recorded or transmitted." or equivalent.
- Mid-session mic permission revocation handled gracefully (CON-06): ambient sensing silently stops; banner shown; no crash.

**Priority:** Must | **Phase:** 0 | **Estimate:** 2 sp | **Dependencies:** US-UI-03
**Traceability:** NFR-PRIV-01, NFR-PRIV-02, CON-06

---

#### US-PRIV-02 — App sandbox compliance and entitlements declaration

As a **developer** I want the app to be fully sandboxed per App Store requirements with all entitlements declared and justified, so that it passes App Store review and the privacy nutrition label is accurate.

**Acceptance Criteria:**
- App is sandboxed (com.apple.security.app-sandbox = true).
- Microphone entitlement (com.apple.security.device.microphone) declared only if ambient sensing is included (NFR-PRIV-05).
- No entitlements claimed beyond those actually used; reviewed by a second engineer.
- Privacy nutrition label entries verified against actual data collection (NFR-PRIV-01, NFR-PRIV-03).

**Priority:** Must | **Phase:** 0 | **Estimate:** 2 sp | **Dependencies:** US-PRIV-01
**Traceability:** NFR-PRIV-05, NFR-INSTALL-01

---

#### US-PRIV-03 — Telemetry opt-in framework

As a **developer** I want an opt-in analytics framework that is clearly described at onboarding, excludes audio content and hearing data, and respects opt-out immediately, so that optional anonymous quality and diagnostics data (crash-free rate, audio-engine error counts) can be collected ethically if the project chooses to implement telemetry at all (LD-9 — no commercial analytics purpose).

**Acceptance Criteria:**
- See NFR-PRIV-04 Given/When/Then: user opts out; no analytics events sent after opt-out (verified by Charles Proxy).
- Opt-in dialog at first launch; default is opted-out.
- Telemetry excludes any audio content, hearing profile data, or personal identifiers.
- Crash reporting SDK selection deferred to SPIKE-TELEMETRY resolution (OQ-10).

**Priority:** Should | **Phase:** 0 | **Estimate:** 3 sp | **Dependencies:** US-UI-03, SPIKE-TELEMETRY
**Traceability:** NFR-PRIV-04

---

---

## Phase 0 Stories (Continued) — Library & Playlist Foundation *(new — v2.4, 2026-07-02)*

> **Context:** these two epics formalize a set of domain rules/use-cases the founder stated directly (2026-07-02) ahead of the S8 library-spine build, so the persistent store schema (see [`../sprints/s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md)) is *designed against* them rather than retrofitted after the fact. **No FR/NFR IDs exist for this domain** — `requirements.md` predates the persistent-library feature entirely (it only covers flat-playlist playback under `FR-PLAY-*`). Stories below trace to the S8.1 design doc and to `sprint-plan.md`'s S8–S10 scope, the same pattern already used for `EP-QA` (US-QA-01..06), which trace to sprint docs rather than invented FR-IDs. **All stories in this section are Draft — pending sprint planning review; none are Done.** Every story is tagged with its sprint-chunk so sprint boundaries stay clean: **S8.1** (store schema — design exists, implementation pending), **S8.2** (folder scan), **S8.4** (incremental rescan / move detection), **S9** (browse UI), **S10** (queue + playlists UI). Nothing here is scheduled for S8.3 (metadata/artwork extraction) — that chunk is orthogonal to these rules.

### EP-LIBRARY — Persistent Library: Scan Folders, Single-File Play, Durable Identity, Duplicates

**Epic goal:** Formalize the rules governing how the persistent library store (S8.1 schema) represents scan folders and tracks so that (a) a listener can point the app at several independent folders and play from any of them, (b) a single file outside any scan folder is still first-class playable, (c) duplicates of a song across folders are treated as normal — never silently deduped — and (d) a track's durable identity survives a filesystem move or a retag, so nothing that references it (a playlist, a future play-count) breaks. This epic is the schema-shaping input to S8.1/S8.2/S8.4; it does not itself ship UI.

---

#### US-LIB-01 — Multiple independent scan folders

As a **Ramith** I want to register several scan folders (e.g., "Lossless," "Live Bootlegs," "Podcasts") and have the app treat each as an independent library root that I can play from, browse, or remove independently, so that I am not forced to consolidate my collection into one folder tree to get library features.

**Acceptance Criteria:**
- The store's `folders` table supports multiple root rows (`parent_id IS NULL`, `is_root = 1`); no artificial limit on the number of roots (S8.1 schema already supports this — `folders.id` is a normal auto-increment key, not a singleton).
- Adding a second, third, ... Nth scan folder does not require removing or merging any existing root; each root scans and rescans independently (S8.2/S8.4 scope — this story pins the *rule*, not the scan mechanics).
- A track's browse/queue/playlist behavior is identical regardless of which scan-folder root it came from — "which folder" is provenance metadata (`tracks.folder_id`), not a partition that changes app behavior.
- Removing a scan folder root removes (cascades) only that root's tracks (`ON DELETE CASCADE` on `folders.parent_id` / `tracks.folder_id`, per the S8.1 DDL); it does not touch tracks under other roots, and playlist entries referencing tracks under the removed root are handled per US-LIB-06 (orphan/dangling-reference policy), not silently left corrupt.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S8.1 (schema — supports this today) / S8.2 (scan UX to add/remove roots) | **Estimate:** 3 sp | **Dependencies:** S8.1 store foundation
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §3 (`folders` table, `parent_id`/`is_root`)

---

#### US-LIB-02 — Single-file play outside any scan folder

As a **Ramith** I want to open and play a single audio file that is not inside any of my scan folders (e.g., a one-off download or an email attachment), so that I am not forced to import or copy a file into my library just to hear it once.

**Acceptance Criteria:**
- A file opened via Finder drag-and-drop, the macOS Open panel, or "open with" plays immediately through the existing playback engine (US-PLAY-01/US-ENG-07/08) without requiring a library entry to exist first — this path must keep working exactly as it does today (S8.1 §7: "the running app is byte-identical" — this story extends that guarantee forward through S8.2+).
- The played file is **not required** to be written into the persistent store to play; if/when it is added to a playlist (US-PLIST-02), *that* action creates its track row with `folder_id = NULL` (loose file) — playing alone never does.
- A loose (non-scan-folder) file that is never added to a playlist leaves no residue in the library store after the session ends (no orphan row).
- Session-state restore (US-PLAY-05) continues to work for a loose file that was mid-playback at last quit, exactly as it does for a scan-folder file.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S8.1 (schema: nullable `folder_id`) / S8.2 (does not regress the existing single-file-open path) | **Estimate:** 2 sp | **Dependencies:** US-PLAY-01, S8.1 store foundation
**Traceability:** FR-PLAY-01 (existing single-file playback path is preserved, not superseded); design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §7 (integration — additive only)

---

#### US-LIB-03 — Stable durable track identity, independent of file path

As a **developer** I want every track to have a stable integer identity (the store's `tracks.id`) that playlists and any future per-track state (play counts, ratings) reference, rather than referencing the file's URL/path directly, so that a filesystem move or a metadata retag never silently breaks a playlist or loses history.

**Acceptance Criteria:**
- All playlist-membership references (US-PLIST-01) point at `tracks.id` (a stable integer), never at `tracks.url` or a raw path string.
- A track retag (title/artist/album edited) updates the row in place; `tracks.id` is unchanged; every playlist referencing that track continues to resolve correctly with no re-linking step.
- This is a **naming/design constraint on the schema**, not new DDL — the S8.1 schema (§3, §4) already keys `tracks` on an integer `id` and exposes it via the `LibraryStore` actor API; this story is the explicit requirement that all *future* consumers (playlists, S10) build against `id`, never against `url`, for anything that must survive a move.
- Distinguish explicitly from `UNIQUE(url)`: `url` remains the natural key for *duplicate-file detection at scan time* (US-LIB-04) and for *resolving "is this exact path already known"* — but it is never the reference playlists hold.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S8.1 (schema decision — pins how S10's playlist tables must be built) | **Estimate:** 1 sp | **Dependencies:** S8.1 store foundation
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §3 (`tracks.id`), §4 (`LibraryStore` API keys reads/writes off `Int64` track ids)

---

#### US-LIB-04 — Duplicates across scan folders are normal, never auto-deduped

As a **Ramith** I want the app to treat two copies of the same song living in two different scan folders (e.g., a FLAC rip in "Lossless" and an MP3 of the same track in "Car") as two distinct, independent tracks — each playable, each addable to playlists on its own — rather than trying to detect and collapse them into one, so that I never lose a file or have the "wrong" copy silently substituted.

**Acceptance Criteria:**
- A song residing in exactly one scan folder is the normal case (per the founder's stated invariant); a second (or third...) copy of that same song under a **different** scan folder is a **distinct row** in `tracks` (distinct `url`, distinct `folder_id`, distinct `id`) — not an error, not a warning, not something the scanner attempts to merge.
- Two files with identical audio content but different paths are never collapsed into a single library entry by default. The `content_hash` column exists in the S8.1 schema for a **future, explicitly opt-in** dedupe/"show duplicates" feature (per S8.1 Open Decision D3: "Defer. Column provisioned, unused in S8.1/8.2; path-uniqueness is enough for R1.") — this story confirms that deferral and pins the default behavior (no auto-dedupe) as a hard requirement, not just an implementation shortcut.
- `UNIQUE(url)` is the only per-scan-folder duplicate guard (re-scanning the same file at the same path is idempotent — see US-LIB-05); it does **not** and must not be used across different folders/paths to detect or block "duplicates."
- Adding either copy to a playlist adds *that specific file's* track row; adding "the same song" from two folders to one playlist results in two distinct entries (this is expected, not a bug — see US-PLIST-01).

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S8.2 (scan behavior) | **Estimate:** 2 sp | **Dependencies:** US-LIB-01, S8.1 store foundation
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §3 (`content_hash` deferred), Open Decision D3

---

#### US-LIB-05 — Idempotent re-scan (unchanged files produce no spurious writes)

As a **developer** I want re-scanning a folder whose files have not changed to produce zero new rows and zero spurious updates (no `mtime`/`date_added` churn), so that the "duplicates are normal, don't dedupe" rule (US-LIB-04) never gets confused with "the same file re-scanned" (which is not a duplicate at all).

**Acceptance Criteria:**
- Re-scanning an unchanged file (same `url`, same `(file_size, mtime, inode)` signature) results in exactly one row, unchanged, per the S8.1 delta-friendly upsert contract (`ON CONFLICT(url) DO UPDATE`, classified as "unchanged" by `classify(_:)`).
- This is explicitly **the boundary case that separates US-LIB-04 (cross-folder duplicate = normal, two rows) from a re-scan (same-folder same-file = one row, no-op)** — the acceptance test set must include both cases side by side so the distinction is provable, not just described.
- Covered by the S8.1 `VerifyLibraryStore` idempotency test cases (already scoped in the design doc §6: "re-upsert identical row = one row, no spurious mtime bump").

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S8.1 (store contract — already designed) / S8.4 (consumed by incremental rescan) | **Estimate:** 1 sp | **Dependencies:** S8.1 store foundation
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §6 ("Idempotency" test group)

---

#### US-LIB-06 — Filesystem move updates a track in place, preserving playlist membership

As a **Ramith** I want moving a file from one scan folder to another (or renaming/relocating it within a scan folder) to be recognized by a rescan as "the same track that moved," updating its stored location in place, so that every playlist it belonged to still contains it after the move — not a broken reference plus an orphaned new entry.

**Acceptance Criteria:**
- A rescan that finds a file at a **new** path whose content/identity signature matches a previously-known track (see Note below on the matching heuristic) updates that track's `url`/`folder_id`/`relative_path` **in place**; `tracks.id` does not change.
- Because all playlist membership references `tracks.id` (US-LIB-03), a track that moves remains present, in the same position, in every playlist that contained it — before and after the move, a `SELECT` over that playlist's entries returns the identical set of track ids.
- **Explicit scope note (do not over-promise):** the S8.1 design doc records this as **Open Decision D1**, currently deferred: *"File-move tracking (moved file = delete+add today, losing future play-counts/ratings) — Accept for R1. `inode` column provisioned to add move-following later (revisit at S10 when per-track state exists)."* This story is the formal requirement that **motivates reversing that deferral before/at S8.4** (rescan is exactly where move-detection belongs) — it does not itself change the D1 default. Acceptance for *this story* is: (a) the requirement is recorded and traced (this row), (b) S8.4's design must explicitly re-examine D1 in light of it, using the provisioned `inode` (and/or `content_hash`) column as the move-matching signature, given `url`'s `UNIQUE` constraint means a naive delete-at-old-path + insert-at-new-path is the *wrong* default once playlists exist.
- A retag (US-LIB-03) and a move (this story) compose: a track that is both retagged and moved between scans is still the same `tracks.id` row, playlist membership intact.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S8.4 (incremental rescan/move detection — this is where D1 must be revisited) | **Estimate:** 5 sp | **Dependencies:** US-LIB-03, US-LIB-05, S8.1 store foundation
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §8, Open Decision D1 (`inode` column provisioned, revisit at S10) — **this story is the formal driver to revisit D1 at S8.4, not S10, given playlists (EP-PLAYLIST) land at S10 and depend on membership surviving a move that could happen any time before then**

---

#### US-LIB-07 — Drag-and-drop folder-to-folder is a real filesystem move

As a **Ramith** I want dragging a song (or songs) from one scan folder's browse view into another scan folder to physically relocate the file(s) on disk — not just re-file them in the database — so that folder-to-folder drag behaves the way Finder-style file organization actually expects.

**Acceptance Criteria:**
- Dropping track(s) from scan-folder A's browse view onto scan-folder B (in the browse UI) performs an actual `FileManager` move of the underlying file(s) from A's directory tree to B's, then reconciles the store per US-LIB-06 (in-place update, `tracks.id` unchanged, playlist membership intact) — it is explicitly **not** a copy, and it is explicitly **not** a database-only re-parent with the file left in place.
- This is the deliberate contrast with playlist drag-and-drop (US-PLIST-03/04): dropping into a **playlist** is a reference-add (US-PLIST-04), dropping into a **scan folder** is a potential real move (this story) — the UI/UX must make the distinction between "playlist" drop targets and "scan folder" drop targets unambiguous (different visual affordance), since the filesystem consequence is different.
- Collision handling is explicit: if a file with the same name already exists at the destination path, the user is prompted (rename / skip / overwrite) rather than silently overwriting or silently failing.
- Failure mid-move (permissions, destination full, source removed externally) leaves the store consistent with whatever actually happened on disk — never a store row pointing at a path that doesn't exist, and never a lost file.

**Priority:** Should | **Phase:** 0 | **Sprint-chunk:** S9 (browse UI — this is where folder-to-folder DnD is exposed) | **Estimate:** 5 sp | **Dependencies:** US-LIB-06, US-LIB-01
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §8 (reconciliation path reused from US-LIB-06)

---

#### US-LIB-08 — Corrupt/missing-store recovery does not lose scan-folder registrations

As a **developer** I want the list of registered scan-folder roots to be recoverable independently of the rest of the store's corruption-recovery path, so that a quarantine-and-rebuild event (S8.1 §5) does not force the listener to re-register every scan folder from scratch on top of losing their scan history.

**Acceptance Criteria:**
- On store quarantine + fresh-create (S8.1 §5 policy: corrupt file → rename `library.corrupt-<ts>.sqlite3` + create fresh), the app can re-populate `folders` root rows without founder/user having to manually re-pick each folder via a file picker — at minimum, the security-scoped `bookmark` blob per root (already provisioned in the S8.1 schema, §3: `folders.bookmark`) must be resolvable independent of the rest of the corrupted DB, or a lightweight sidecar (e.g., a small JSON of root bookmarks in App Support, alongside the SQLite file) must exist for this purpose.
- This story does **not** require recovering tracks or playlists after corruption (that remains "files on disk are the source of truth, rescan repopulates," per S8.1 §5/D2) — it is scoped narrowly to *not losing the roots themselves*, which is the one piece of state a rescan cannot regenerate on its own (the user would have to remember and re-browse-to every folder).

**Priority:** Could | **Phase:** 0 | **Sprint-chunk:** S8.1 (schema already provisions `folders.bookmark`; the sidecar-or-not decision belongs here) | **Estimate:** 2 sp | **Dependencies:** S8.1 store foundation
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §3 (`folders.bookmark`), §5 (corruption policy), Open Decision D5 (sandbox posture)

---

### EP-PLAYLIST — Playlists: Membership, Drag-and-Drop Semantics, Built-in "current," Naming

**Epic goal:** Formalize the rules governing playlists as a distinct concept from scan folders: many-to-many ordered membership referencing the durable track identity (EP-LIBRARY, US-LIB-03), the ability to add a single non-library file to a playlist, the drag-and-drop reference-add semantic (never a filesystem operation), user/auto naming, and the built-in "current" playlist that is the play queue. This epic is schema-shaping input to S8.1 (playlist tables are noted as an S10 addition in the store design) and UX-shaping input to S10.

---

#### US-PLIST-01 — Many-to-many, user-ordered playlist membership

As a **Ramith** I want a track to be able to belong to any number of playlists at once, and each playlist to hold an arbitrary, user-arrangeable ordering of its tracks, so that I can organize the same song into "Workout," "Chill," and "2026 Favorites" simultaneously without the app treating that as a conflict.

**Acceptance Criteria:**
- The store schema (an addition beyond what S8.1 ships — S8.1's scope is explicitly library-only, per its §1 table: "S10 queue/playlist tables" is listed as deferred) adds a `playlists` table (id, name, `is_builtin`, `created_at`) and a `playlist_entries` join table (`playlist_id`, `track_id` referencing `tracks.id` — **not** `tracks.url` — per US-LIB-03 — plus an explicit `position` / ordering column and its own entry id, since the same `track_id` can legitimately appear more than once in one playlist, e.g. an intro track re-used later).
- A track appearing in zero playlists is valid (not every track needs to be organized); a track appearing in many playlists is valid and is the expected common case, not an edge case.
- Reordering a playlist (drag-to-reorder within the playlist, reusing the existing queue-reorder UX pattern from US-PLAY-03) updates only that playlist's `position` values; it has no effect on any other playlist containing the same track, and no effect on the track's row in `tracks`.
- Deleting a playlist removes its `playlist_entries` rows (cascade) but never touches `tracks` or the underlying file — deleting "Workout" does not delete the song from the library or from "Chill."

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S10 (playlist tables + UI) | **Estimate:** 5 sp | **Dependencies:** US-LIB-03, S8.1 store foundation
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §1 ("S10 queue/playlist tables" listed as deferred-from-S8.1 scope)

---

#### US-PLIST-02 — Add a single (possibly non-library) file to a playlist

As a **Ramith** I want to add a single audio file to a playlist even when that file is not inside any of my scan folders, so that a one-off track (a promo download, a friend's demo) can live in a playlist alongside my scanned library without first importing it as a full library citizen.

**Acceptance Criteria:**
- Adding a file via Finder drag-and-drop or the Open panel directly onto a playlist (not onto the main library view) creates a `tracks` row with `folder_id = NULL` (a "loose" / non-scan-folder track, per US-LIB-02's schema accommodation) if one doesn't already exist for that exact `url`, then adds a `playlist_entries` row referencing it.
- A loose track added to a playlist this way behaves identically to a scan-folder track for playback, metadata display, and further playlist membership (it can be added to additional playlists, reordered, removed) — the only difference is `folder_id IS NULL` and it is invisible to folder-scoped browse views (US-LIB-01's "which folder" provenance) since it has no folder.
- If the underlying file is later deleted or moved externally (outside the app, since it's not scan-folder-monitored), the playlist entry surfaces an inline "file not found" state on next play attempt (consistent with the existing US-PLAY-05 pattern for a moved/deleted queued file), rather than crashing or silently dropping the entry.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S10 | **Estimate:** 3 sp | **Dependencies:** US-LIB-02, US-PLIST-01
**Traceability:** FR-PLAY-05 (moved/deleted-file inline-error pattern reused); design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §3 (nullable `folder_id`)

---

#### US-PLIST-03 — Drag a song from a scan folder or another playlist into a playlist

As a **Ramith** I want to drag a song (or a multi-select of songs) from a scan-folder browse view, or from one playlist, and drop it onto a different playlist, so that building and curating a playlist feels the same regardless of where the song is coming from.

**Acceptance Criteria:**
- Dragging from a scan-folder browse view (US-LIB-01/US-LIB-07 context) onto a playlist and dropping it into another playlist both use the identical drop handler and produce the identical result: a new `playlist_entries` row in the **destination** playlist referencing the existing `tracks.id` (US-LIB-03) — the source (folder browse, or the source playlist) is completely unaffected.
- Dragging from playlist A to playlist B does **not** remove the track from playlist A (a copy-the-reference semantic, not a move-the-reference semantic) unless the user explicitly performs a "move" gesture (e.g., holding a modifier key) if/when that is designed — the **default** DnD outcome is additive-only, per the founder's stated rule ("adding to a playlist" — no move variant was specified as default).
- Multi-select drag (several songs at once) adds all of them, preserving their relative order, as consecutive entries at (or near) the drop position.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S10 | **Estimate:** 5 sp | **Dependencies:** US-PLIST-01, US-LIB-01
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §4 (`LibraryStore` write-path pattern reused for the entry-insert)

---

#### US-PLIST-04 — Playlist drop is always a reference-add, never a filesystem move

As a **developer** I want dropping a song onto a playlist to be implemented so that it is architecturally impossible for it to touch the filesystem, so that the "playlist add ≠ file move" invariant the founder stated cannot be violated by a future refactor that conflates it with the folder-to-folder move handler (US-LIB-07).

**Acceptance Criteria:**
- The playlist drop handler's only side effect is an INSERT into `playlist_entries` (plus, if the source track doesn't yet have a `tracks` row — the loose-file case, US-PLIST-02 — an INSERT into `tracks` with `folder_id = NULL`); it never calls any `FileManager` move/copy/relocate API, and this is enforced by keeping the playlist-drop code path and the folder-to-folder-move code path (US-LIB-07) as two separate, non-shared handlers rather than one generic "drop" handler with a folder-vs-playlist branch buried inside it.
- This story is explicitly the architectural/testable counterpart to US-LIB-07: a regression test (or code-review checklist item) asserts that dropping onto any playlist target across a stress set of source types (scan-folder track, another-playlist track, loose file) never results in a changed `mtime` or moved path for the underlying file on disk.
- Removing a track from a playlist (the inverse operation) is likewise filesystem-inert: it is a DELETE on `playlist_entries` only, never a file delete.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S10 | **Estimate:** 2 sp | **Dependencies:** US-PLIST-03, US-LIB-07
**Traceability:** *(no FR/NFR — see epic-level note; this is a founder-stated invariant, not a derived one)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §7 (additive-only integration precedent)

---

#### US-PLIST-05 — Playlist naming: user-provided, or auto-named "untitled-N"

As a **Ramith** I want a newly-created playlist to take the name I type, or if I don't type one, to be auto-named "untitled-1," "untitled-2," and so on, so that I never end up with an unnamed or ambiguously-named playlist cluttering my list.

**Acceptance Criteria:**
- Playlist creation accepts an optional user-provided name; if omitted (or left as empty string), the app assigns the lowest-numbered unused `"untitled-N"` name (N starting at 1), scanning existing playlist names to avoid collision — e.g., if "untitled-1" and "untitled-3" exist but "untitled-2" was renamed away, the next auto-name is "untitled-2," not "untitled-4" (lowest-unused, not a monotonic counter, to avoid unbounded drift from rename/delete churn — *flagging this as the recommended default; founder may prefer a monotonic counter instead, which is the simpler alternative if collision-avoidance-by-scan is judged unnecessary complexity*).
- A user can rename any playlist (including an auto-named one) at any time; renaming a user-named playlist to an empty string re-triggers the "untitled-N" auto-naming rule rather than leaving it blank.
- The built-in "current" playlist (US-PLIST-06) is explicitly exempt from this rule — it is never auto-numbered and its name is not user-editable (see US-PLIST-06).
- Two playlists may not share the exact same name at the same time (case-sensitive exact match) — attempting to rename/create a duplicate name either auto-suffixes or is rejected with an inline message; the specific choice is a UI-design decision for S10, not pinned here, but *some* collision handling is required (never two rows with byte-identical `name`).

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S10 | **Estimate:** 2 sp | **Dependencies:** US-PLIST-01
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §1 (playlist tables, S10 scope)

---

#### US-PLIST-06 — Built-in "current" playlist (the play queue)

As a **Ramith** I want a built-in playlist named "current" that always represents whatever is queued/now-playing, so that the existing queue concept (US-PLAY-03) and the new playlist concept are unified into one model rather than two parallel, inconsistent systems.

**Acceptance Criteria:**
- Exactly one `playlists` row has `is_builtin = 1` and `name = "current"`; it is created once, at first launch after S10 ships (or via a one-time migration for existing installs), and can never be deleted or renamed by the user (delete/rename UI affordances are disabled/hidden for it, and the store layer rejects a delete/rename attempt on a builtin row defensively, not just via UI graying-out).
- The existing queue behaviors — drag-to-reorder, remove, shuffle, repeat (US-PLAY-03), auto-advance (US-PLAY-09), gapless (US-PLAY-08), session-state restore (US-PLAY-05) — become, architecturally, operations on the "current" playlist's `playlist_entries` rather than a separate in-memory queue data structure; this is the unification this story requires, not merely a coincidental same-named list.
- "current" is otherwise a normal playlist for read purposes: it can be Saved-As under a different (user-chosen) name to "freeze" today's queue into a permanent playlist (a copy of its entries into a new, non-builtin playlist) without disturbing "current" itself or requiring the two rows to be kept in sync afterward.
- Shuffle/repeat state (US-PLAY-03) is a *playback-session* setting, not a permanent reordering of "current"'s stored entry order — shuffling the queue must not silently rewrite the persisted `position` values in a way that's visible as "current" being permanently shuffled the next time it's viewed unshuffled.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S10 | **Estimate:** 5 sp | **Dependencies:** US-PLIST-01, US-PLAY-03, US-PLAY-05, US-PLAY-08, US-PLAY-09
**Traceability:** FR-PLAY-03 (queue reorder/remove/shuffle/repeat — behavior preserved, re-platformed onto playlist storage), FR-PLAY-05 (session-state restore — re-platformed); design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §1

---

#### US-PLIST-07 — Multiple playlists coexist with no artificial limit

As a **Ramith** I want to create as many playlists as I want, so that my organizational scheme (by mood, by activity, by year, by project) is not constrained by an arbitrary cap.

**Acceptance Criteria:**
- No hard-coded limit on the number of `playlists` rows (beyond SQLite's own practical ceilings, which are far beyond any realistic personal-library scale).
- The browse/list UI for "all my playlists" (S10 scope) scales to at least low hundreds of playlists without a perceptible slowdown (indexed query, not a full unindexed scan — reuses the same indexing discipline the S8.1 schema already applies to `tracks`/`albums` facets).
- This story exists primarily to make the "no limit" requirement explicit and testable (a stress-fixture of e.g. 200 synthetic playlists in the `VerifyLibraryStore`-style harness, once playlist tables exist) rather than left as an unstated assumption.

**Priority:** Should | **Phase:** 0 | **Sprint-chunk:** S10 | **Estimate:** 1 sp | **Dependencies:** US-PLIST-01, US-PLIST-05
**Traceability:** *(no FR/NFR — see epic-level note)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §6 (indexed-facet-query discipline reused)

---

#### US-PLIST-08 — Playlist membership survives a scan-folder move

As a **Ramith** I want a playlist that contains a song to still contain that exact song after I've moved its file from one scan folder to another via folder-to-folder drag-and-drop (US-LIB-07), so that reorganizing my library on disk never quietly breaks the playlists I've curated.

**Acceptance Criteria:**
- This story is the explicit **integration test** that ties EP-LIBRARY's durable-identity/move handling (US-LIB-06, US-LIB-07) to EP-PLAYLIST's membership model (US-PLIST-01): given a track that is a member of ≥2 playlists, performing a folder-to-folder move (US-LIB-07) on that track's file, then re-querying every playlist that contained it, returns the identical membership (same playlists, same relative position) as before the move.
- This is the concrete, testable form of the founder's derived invariant ("a filesystem move updates the track's location in place, preserving playlist memberships") — it is listed as its own story specifically so it has an independent acceptance test in the S10/S8.4 verification harness, rather than being assumed as a free consequence of US-LIB-06 + US-PLIST-01 without ever being explicitly checked end-to-end.
- Covers the cross-chunk dependency explicitly: this story cannot be verified until **both** S8.4 (move detection, US-LIB-06) and S10 (playlist tables, US-PLIST-01) have shipped — it is the seam between the two sprint-chunks and should be flagged in sprint planning as a "does not enter Definition of Done until both sides exist" story, not scheduled as if it were a single-chunk unit of work.

**Priority:** Must | **Phase:** 0 | **Sprint-chunk:** S10 (verification depends on S8.4 having shipped first — cross-chunk seam, see Acceptance Criteria) | **Estimate:** 3 sp | **Dependencies:** US-LIB-06, US-LIB-07, US-PLIST-01, US-PLIST-03
**Traceability:** *(no FR/NFR — see epic-level note; this is the integration test for the founder's derived invariant)*; design ref: [`s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md) §8

---

---

## Phase 1 Stories — Mix-Level Core Features

### EP-SPAT — HRTF Binaural Rendering

---

#### US-SPAT-01 — HRTF binaural rendering (custom SOFA-HRIR convolution, SADIE II default)

As a **Marcus** I want binaural HRTF rendering that places the soundstage outside my head when I use headphones, so that listening feels three-dimensional and less fatiguing on long commutes.

**Acceptance Criteria:**
- See FR-SPAT-01 Given/When/Then: stereo track, headphone device active, HRTF mode enabled; naive listener ABX test shows audible spatial difference vs. bypass at statistically significant rate.
- HRTF rendering is implemented as **custom SOFA-HRIR partitioned convolution** using **libmysofa (BSD-3)** for SOFA loading and **vDSP / FFTConvolver (MIT)** for convolution (DEP-06, DEP-12). Apple PHASE / AVAudioEnvironmentNode / AUSpatialMixer are explicitly NOT used for HRTF (their HRTFs are fixed and non-replaceable — see FR-SPAT-01 and `docs/architecture/prior-art.md`).
- Default dataset is **SADIE II (Apache-2.0)** (ASM-04, DEP-06 — confirmed permissive; OQ-04 resolved).
- Convolution CPU within NFR-PERF-02 budget. Validated in SPIKE-HRTF.
- HRTF is default-on for any device classified as headphones; off for speakers.
- Non-medical framing enforced in all UI copy (LD-7).

**Priority:** Must | **Phase:** 1 | **Estimate:** 13 — split into: US-SPAT-01a (SOFA-HRIR convolution engine with libmysofa + FFTConvolver), US-SPAT-01b (integration into DSP chain), US-SPAT-01c (HRTF toggle and UI)
**Dependencies:** US-ENG-02, US-DEVICE-03, SPIKE-HRTF
**Traceability:** FR-SPAT-01, ASM-04, DEP-06, DEP-12, DEP-15 (BNNS for any RT ML path), LD-7

---

#### US-SPAT-02 — HRTF profile selection (3 presets: generic, small-head, large-head)

As a **Marcus** I want to choose from at least 3 HRTF profiles and see a recommended one based on my hearing calibration, so that I can pick the one that sounds most natural for my head shape.

**Acceptance Criteria:**
- See FR-SPAT-02 Given/When/Then: calibration complete; HRTF selector open; recommended profile highlighted; renders immediately on selection, no restart.
- Non-medical framing: profiles labelled as "listening preference" variants, not audiological recommendations.

**Priority:** Should | **Phase:** 1 | **Estimate:** 3 sp | **Dependencies:** US-SPAT-01, US-HEAR-01
**Traceability:** FR-SPAT-02, LD-7

---

#### US-SPAT-03 — Virtual room convolution (studio, living room, concert hall IRs)

As a **Marcus** I want to optionally place a virtual listening room around my music, so that I can experience a concert hall or studio feel on headphones.

**Acceptance Criteria:**
- See FR-SPAT-05 Given/When/Then: room IR selected; convolution enabled; output contains reverb consistent with IR RT60; CPU within NFR-PERF-01 budget.
- At least 3 IR presets shipped. IRs are licensed for redistribution in open-source software (permissive licence required — project is personal/open-source per LD-9).
- Room convolution is off by default; user opt-in only.

**Priority:** Should | **Phase:** 1 | **Estimate:** 8 sp | **Dependencies:** US-SPAT-01
**Traceability:** FR-SPAT-05, NFR-PERF-01

---

### EP-HEADTRACK — AirPods Head Tracking

---

#### US-HT-01 — CoreMotion AirPods head-tracking integration

As a **Marcus** I want the HRTF soundstage to remain fixed in space when I turn my head while wearing AirPods, so that the music stays in front of me and the experience feels like real speakers in a room.

**Acceptance Criteria:**
- See FR-SPAT-04 Given/When/Then: AirPods Pro active, head-tracking enabled, 30-degree rotation; soundstage counter-compensates; perceived source does not move with head; lag < 20 ms.
- Update rate gated: only update HRTF when orientation delta > 1 degree (Adaptivity Signal Matrix).
- CMHeadphoneMotionManager checked at runtime; feature gracefully unavailable on non-AirPods devices (ASM-08).
- Head tracking is opt-in with a clear permission explanation; macOS 14+ required (ASM-01).

**Priority:** Must | **Phase:** 1 | **Estimate:** 8 sp | **Dependencies:** US-SPAT-01, DEP-03
**Traceability:** FR-SPAT-04, DEP-03, ASM-01, ASM-08

---

### EP-HEAR — Guided Hearing Calibration

---

#### US-HEAR-01 — Guided hearing calibration test

As a **Tom** I want to run a guided hearing test that plays tones at 7 audiometric frequencies per ear and stores a personal hearing profile, so that the app can compensate for my specific hearing characteristics.

**Acceptance Criteria:**
- See FR-HEAR-01 Given/When/Then: headphones on; each tone presented; user responds; thresholds recorded per ear per frequency; stored in structured hearing profile.
- See FR-HEAR-05 Given/When/Then: system volume 100% during test; app overrides to safe level; cannot be bypassed.
- Journey 2.2 implemented: pre-check, tone sequence, graph, save, label, device link.
- Profile stored encrypted (AES-256 or platform Data Protection) — NFR-PRIV-03.
- Profile not transmitted remotely; network traffic verified (FR-HEAR-02 AC).
- Non-medical framing: all UI copy describes this as a "listening preference" test, not a clinical audiogram (LD-7).

**Priority:** Should | **Phase:** 1 | **Estimate:** 8 sp | **Dependencies:** US-ENG-01, US-DEVICE-03
**Traceability:** FR-HEAR-01, FR-HEAR-02, FR-HEAR-05, NFR-PRIV-03, LD-7

---

#### US-HEAR-02 — Hearing profile DSP integration

As a **Tom** I want the app to apply personalised per-frequency gain correction based on my hearing profile automatically, so that frequencies where my hearing is weaker are boosted to restore balance.

**Acceptance Criteria:**
- See FR-ADAPT-06 Given/When/Then: 15 dB threshold elevation at 4 kHz right ear; profile active; compensating gain added at 4 kHz right channel proportional to deficit; no manual adjustment needed.
- Hearing compensation is additive on top of the base profile; does not replace it.
- Profile can be toggled on/off from the DSP controls panel.

**Priority:** Should | **Phase:** 1 | **Estimate:** 5 sp | **Dependencies:** US-HEAR-01, US-ENG-02, US-ENG-04
**Traceability:** FR-ADAPT-06

---

#### US-HEAR-03 — Multiple hearing profiles and retest prompt

As a **Tom** I want to store separate hearing profiles for different family members and be reminded to re-test after 12 months, so that the app remains accurate as my hearing changes.

**Acceptance Criteria:**
- See FR-HEAR-03 Given/When/Then: two profiles exist; "Bob" selected; DSP curve changes; UI confirms.
- See FR-HEAR-04 Given/When/Then: profile 366 days old; launch shows non-blocking prompt; dismissable.

**Priority:** Could | **Phase:** 1 | **Estimate:** 3 sp | **Dependencies:** US-HEAR-01
**Traceability:** FR-HEAR-03, FR-HEAR-04

---

### EP-AMBIENT — On-Demand Ambient Noise Sensing

---

#### US-AMB-01 — On-demand ambient noise sample and DSP adaptation

As a **Marcus** I want to tap "Adapt to my environment" and have the app sample the room noise for 3 seconds and adjust the EQ and dynamics accordingly, without keeping the microphone on.

**Acceptance Criteria:**
- See FR-ADAPT-04 first Given/When/Then: "Adapt to my environment" tapped; noisy room (>65 dBA); 3 s sample completes; ambient classified "Loud"; DSP adapted; mic released; orange indicator clears within 1 s.
- See FR-ADAPT-04 second Given/When/Then: no trigger event; audio playing; microphone not accessed; no mic-in-use indicator.
- Journey 2.5 Steps 1–6 implemented (including noise-decrease return path).
- Adaptivity Signal Matrix DSP rules for ambient noise applied (multi-band compressor ratio, low-frequency gain, presence EQ).
- Mic permission denied gracefully: ambient sensing skipped; banner shown; NFR-PRIV-02.

**Priority:** Should | **Phase:** 1 | **Estimate:** 8 sp | **Dependencies:** US-ENG-03, US-ENG-04, US-ADAPT-02, SPIKE-AMBNOISE
**Traceability:** FR-ADAPT-04, NFR-PRIV-01, NFR-PRIV-02, LD-6, CON-06

---

### EP-PROFILE — Named Profiles, iCloud Sync, A/B Mode

---

#### US-PROF-01 — Profile import/export and iCloud sync ⛔ Won't, this horizon (re-anchor 2026-06-19)

> **⛔ Won't, this horizon (re-anchor v2.3, 2026-06-19):** iCloud profile sync is out of this plan's window (sprint-plan.md §6B). Entry kept as future roadmap; not scheduled. The JSON export/import half lives on as US-DEVICE-05 (Could, Phase 0).

As a **Tom** I want to sync my profiles across my Macs via iCloud and export/import them as JSON files, so that I can use the same settings everywhere without manual re-configuration.

**Acceptance Criteria:**
- Profile JSON export/import (US-DEVICE-05 extended to iCloud).
- iCloud sync using NSUbiquitousKeyValueStore or CloudKit (decision: choose simpler option for Phase 1, document in ADR).
- Sync conflict resolution: last-write-wins with a merge prompt if profiles differ.
- Hearing profiles NOT synced by default (NFR-PRIV-03 — remote transmission requires explicit opt-in).

**Priority:** Should | **Phase:** 1 | **Estimate:** 5 sp | **Dependencies:** US-DEVICE-05
**Traceability:** FR-DEVICE-05, NFR-PRIV-03

---

#### US-PROF-02 — A/B listening mode (bypass toggle with matched loudness)

As a **Tom** I want to quickly toggle between enhanced and bypassed audio with loudness-matched levels so that I can hear exactly what the Adaptivity Engine is adding.

**Acceptance Criteria:**
- Single button or keyboard shortcut toggles between enhanced and bypass mode.
- Loudness is matched (LUFS-matched, ± 0.5 LU) so the comparison is fair (loudness preference bias eliminated).
- NFR-QUAL-03: bypass mode is bit-transparent.
- A/B state visible in the UI and announced via VoiceOver.

**Priority:** Could | **Phase:** 1 | **Estimate:** 3 sp | **Dependencies:** US-ENG-02
**Traceability:** NFR-QUAL-03, FR-ADAPT-08

---

### EP-NLT — Conversational Tuning ⛔ Won't, this horizon (re-anchor 2026-06-19)

> **⛔ Won't, this horizon (re-anchor v2.3, 2026-06-19):** Natural-language / conversational tuning — the vision's endgame — is out of this plan's window (sprint-plan.md §5, §6B). It needs the full adaptive stack (loudness-comp + Clarity + Reimagine, S14–S18) to have anything to steer, and is blocked on SPIKE-NLT-ARCH / OQ-11. Multilingual scope (OQ-14) is likewise out-of-window. **All US-NLT-* stories below and SPIKE-NLT-ARCH are tagged Won't, this horizon** — entries kept as the future roadmap, not scheduled.

**Epic goal:** Ship the full Conversational Tuning feature (FR-NLT-01 through FR-NLT-12) as a supporting/discovery feature at Phase 1 launch. The interpretation mechanism (OQ-11) is resolved via a Spike before engineering begins. All stories are architecture-agnostic; they specify behavior, not mechanism.

> **Blocker resolved:** The previously flagged OQ-02 blocker (monetization / feature-gating model affecting whether NLT and other Phase 1 features could be gated) is fully resolved. The project is personal / open-source and non-commercial (LD-9). No feature-flag or entitlement-check layer is needed; all features ship unconditionally.

---

#### US-NLT-00 [Enabler] — Intent derivation subsystem scaffold

As a **developer** I want a Conversational Tuning subsystem module that accepts raw text, calls the interpretation mechanism (whichever is chosen via SPIKE-NLT-ARCH), and returns a typed DSP action vector for forwarding to the lock-free parameter bus, so that all NLT stories have a stable, testable integration point.

**Acceptance Criteria:**
- Module exposes a single async interface: `deriveIntent(text: String) async -> DSPActionVector?`
- DSP action vector type encodes: per-band gain deltas (array of frequency band + direction + magnitude), optional dynamics delta, optional spatial delta.
- Module is mockable; unit tests stub the interpretation mechanism independently of the chosen approach.
- Processing indicator visible to user within 100 ms of submission (FR-NLT-01 second AC).
- Total round-trip from submission to DSP parameter applied ≤ 1500 ms for the chosen mechanism (FR-NLT-04 / ASM-09).

**Priority:** Must (if NLT ships) | **Phase:** 1 | **Estimate:** 5 sp | **Dependencies:** SPIKE-NLT-ARCH, US-ENG-03, US-ENG-04
**Traceability:** FR-NLT-01, FR-NLT-02, FR-NLT-03, ASM-09

---

#### US-NLT-01 — Free-text input field in Now Playing view

As a **Ramith** I want a "Tell us what you hear" text field accessible from the Now Playing view by clicking a button or pressing a keyboard shortcut, so that I can describe the sound problem in plain English without needing to find an EQ slider.

**Acceptance Criteria:**
- See FR-NLT-01 Given/When/Then (both ACs): field appears and focuses on activation; accepts free-form Unicode up to 280 chars; raw text passed to intent subsystem within 100 ms of submission; processing indicator visible.
- Placeholder text: "e.g. 'bass is too low' or 'voices are hard to hear'" (Journey 2.7 Step 1).
- Field operable via keyboard alone and via VoiceOver (FR-NLT-11).

**Priority:** Must (if NLT ships) | **Phase:** 1 | **Estimate:** 3 sp | **Dependencies:** US-NLT-00, US-UI-01
**Traceability:** FR-NLT-01, FR-NLT-11, NFR-ACC-01

---

#### US-NLT-02 — Intent derivation: DSP action vector for direct frequency phrases

As a **Marcus** I want phrases like "bass is too low" and "slightly too bright" to map directly to EQ band adjustments with the right magnitude, so that simple corrections happen immediately without multiple clarification rounds.

**Acceptance Criteria:**
- See FR-NLT-02 Given/When/Then (first two ACs): "bass is too low" → increase 60–250 Hz, moderate; "slightly too bright" → decrease 6–12 kHz, subtle (intensity qualifier respected).
- Magnitude scale: subtle ≤ ±2 dB, moderate ~±3 dB, strong ≥ ±6 dB.
- DSP change delivered via FR-ADAPT-02/FR-ADAPT-03 lock-free ramp (FR-NLT-03 AC verified by Thread State Trace).

**Priority:** Must (if NLT ships) | **Phase:** 1 | **Estimate:** 5 sp | **Dependencies:** US-NLT-00
**Traceability:** FR-NLT-02, FR-NLT-03, LD-8

---

#### US-NLT-03 — Intent derivation: abstract and aesthetic descriptor phrases

As a **Ramith** I want phrases like "sounds boring," "dull," "muffled," "boxy," or "make it wider" to produce meaningful multi-component DSP adjustments, so that I can express dissatisfaction in natural everyday language without knowing any audio vocabulary.

**Acceptance Criteria:**
- See FR-NLT-12 Given/When/Then (all ACs): "sounds boring" → presence +2–5 kHz + air shelf +10–15 kHz + transient enhancement + optional stereo width; "dull/muffled" → treble shelf + low-mid cut; "wider/spacious" → spatial move (stereo width / crossfeed).
- See FR-NLT-02 third AC: "music sounds boring" → multi-component action vector.
- All descriptors in §3.9.1 mapping table produce a non-null action vector.
- Confirmation card summarises combined changes in plain language (not band numbers alone).

**Priority:** Must (if NLT ships) | **Phase:** 1 | **Estimate:** 8 sp | **Dependencies:** US-NLT-00
**Traceability:** FR-NLT-02, FR-NLT-12, LD-8

---

#### US-NLT-04 — Intent derivation: instrument and source requests (band approximation)

As a **Tom** I want "I can't hear the guitar" or "vocals too quiet" to boost the frequency region where that source dominates, with an honest note in the confirmation that the full mix in that range is being adjusted, so that I get a quick directional fix with clear expectations.

**Acceptance Criteria:**
- See FR-NLT-10 Given/When/Then (both ACs): "can't hear guitar" → 250 Hz–4 kHz boost; confirmation reads "Boosted guitar presence region (250 Hz–4 kHz) — better? Note: this affects the full mix in that range, not guitar alone." "can't hear voices" → 2–4 kHz boost; note surfaced.
- Source-to-frequency mapping covers at minimum: vocals, guitar, bass, drums (§3.9.1 table rows).
- No ML source separation required or used — band approximation is the production baseline (LD-8, OQ-12 resolved).

**Priority:** Should (if NLT ships) | **Phase:** 1 | **Estimate:** 5 sp | **Dependencies:** US-NLT-00
**Traceability:** FR-NLT-10, LD-8

---

#### US-NLT-05 — Urgent protective reduction for discomfort phrases

As a **Marcus** I want "it hurts my ears" or "too painful" to immediately reduce the offending frequency range by at least -6 dB and tighten the limiter before any confirmation is shown, so that I am never left in auditory discomfort waiting for the app to respond.

**Acceptance Criteria:**
- See FR-NLT-09 Given/When/Then (both ACs): discomfort phrase submitted; ≥ -6 dB reduction on implicated band within 500 ms; true-peak limiter tightened; applied before confirmation card renders.
- High-urgency card: amber/warning colour, states what was reduced, recommends volume reduction, [Undo] and [Keep it] (default focus on [Keep it]).
- Discomfort keyword list is hard-coded in-app independent of interpretation mechanism (PRD Risk Register: "priority list of known discomfort signals").
- Discomfort path bypasses confidence-check gate entirely (FR-NLT-09).
- KPI: discomfort phrase response latency < 300 ms measured end-to-end (Phase 1 KPI).

**Priority:** Must (ships with US-NLT-02 — non-deferrable per LD-8 / P1-15) | **Phase:** 1 | **Estimate:** 5 sp | **Dependencies:** US-NLT-00, US-ENG-05
**Traceability:** FR-NLT-09, LD-8, NFR-QUAL-02

---

#### US-NLT-06 — Confirmation card, one-tap undo, and governing principle persistence

As a **Marcus** I want a confirmation card after every NLT adjustment showing what changed and why, with one-tap undo and an explicit "Yes, keep it" to persist, and I want the engine to respect my instruction for the rest of the session, so that I stay in control of the sound and can correct the engine when needed.

**Acceptance Criteria:**
- See FR-NLT-04 Given/When/Then (all ACs): confirmation card appears within 1500 ms; auto-dismisses after 8 s as implicit acceptance without persisting; multi-component changes summarised in plain language.
- See FR-NLT-05 Given/When/Then (both ACs): undo from card; undo from Transparency view; DSP reverts over ≥ 50 ms; no audible click.
- See FR-NLT-06 Given/When/Then (both ACs): [Yes, keep it] → delta persists across restart; auto-dismiss → no residual delta on restart.
- Governing principle: once confirmed, automatic adaptation does not counteract the NLT-stated parameter direction for the session (LD-8 / Adaptivity Signal Matrix NLT row).
- Session-scoped by default; persists only on explicit [Yes, keep it] (LD-8).

**Priority:** Must (if NLT ships) | **Phase:** 1 | **Estimate:** 5 sp | **Dependencies:** US-NLT-02, US-NLT-03, US-ADAPT-04
**Traceability:** FR-NLT-04, FR-NLT-05, FR-NLT-06, LD-8

---

#### US-NLT-07 — Ambiguity handling and clarifying question flow

As a **Ramith** I want the app to ask me a clarifying question when it cannot understand my phrase (up to two rounds), and then offer me the EQ panel if it still cannot help, so that I am never left with no path forward.

**Acceptance Criteria:**
- See FR-NLT-08 Given/When/Then (both ACs): low-confidence phrase → no DSP change; clarifying question displayed with examples; after two failed rounds → EQ panel deep-link offered.
- Journey 2.7 Step 5 (ambiguity/low-confidence path) implemented.
- Clarifying question text follows example phrasing in FR-NLT-08.

**Priority:** Must (if NLT ships) | **Phase:** 1 | **Estimate:** 3 sp | **Dependencies:** US-NLT-00, US-UI-02
**Traceability:** FR-NLT-08

---

#### US-NLT-08 — NLT transparency history in Transparency view

As a **Tom** I want every confirmed NLT change to appear as a row in the Transparency view with the original phrase, the full DSP action (plain language + technical notation), timestamp, and an undo link, so that I can review every text-driven change made in the session.

**Acceptance Criteria:**
- See FR-NLT-07 Given/When/Then (all ACs): single-band row example; multi-component row lists all components; "Clear session log" clears history rows without affecting persisted profile delta.
- Journey 2.7 Step 8: row persists in session history.
- Transparency view row format consistent with US-ADAPT-04 row format for existing signals.

**Priority:** Must (if NLT ships) | **Phase:** 1 | **Estimate:** 3 sp | **Dependencies:** US-NLT-06, US-ADAPT-04
**Traceability:** FR-NLT-07, FR-ADAPT-07

---

#### US-NLT-09 — "Reset all NLT adjustments" control

As a **Marcus** I want a single "Reset all NLT adjustments" button (and a spoken "undo everything" phrase) that reverts all Conversational Tuning changes made in the session in one action, so that I can start fresh when I have been iterating and lost track of the baseline.

**Acceptance Criteria:**
- Reset button visible in the Transparency view and in the NLT input area.
- "undo everything" or "reset all adjustments" as an NLT phrase triggers the same action.
- All session governing principles cleared; DSP parameters return to pre-NLT baseline via smooth ramp.
- Session NLT history cleared from Transparency view.
- Persisted profile deltas (from previous sessions' [Yes, keep it] confirmations) are NOT affected by this action; it resets only the current session.

**Priority:** Should | **Phase:** 1 | **Estimate:** 2 sp | **Dependencies:** US-NLT-06
**Traceability:** FR-NLT-05, FR-NLT-06, LD-8

---

#### US-NLT-10 — NLT VoiceOver and keyboard accessibility

As a **developer** I want all NLT UI elements (text field, confirmation card, all action buttons) to be fully operable via VoiceOver and keyboard alone, so that the feature meets the same accessibility bar as the rest of the app.

**Acceptance Criteria:**
- See FR-NLT-11 Given/When/Then: VoiceOver enabled; Conversational Tuning input active; keyboard navigation to confirmation card; VoiceOver announces description of change and all available actions with keyboard shortcuts.
- Text field, [Yes keep it], [Undo], [Adjust more], clarifying question response — all keyboard-accessible.

**Priority:** Must (if NLT ships) | **Phase:** 1 | **Estimate:** 2 sp | **Dependencies:** US-NLT-01, US-NLT-06
**Traceability:** FR-NLT-11, NFR-ACC-01, NFR-ACC-02

---

---

## Phase 1 Stories (Continued) — Perceptual Engine & Reimagine

### EP-PERCEPTUAL — Typed Contributors, Perceptual Arbiter, Off-RT Realizer

**US-PERC-01 | Typed-contributor model + Arbiter** [Enabler]
As a **developer** I want an Arbiter that composes **typed** contributions (EQ-curve + per-band dynamic + transient + spatial) in the **ERB/Bark** domain with a masking + partial-loudness model and enforces governing-principle clamps, producing a per-stem TargetState, so that clarity/adaptive/NL moves compose correctly.
Acceptance: LD-12; governing-principle clamp (LD-8) verified — an auto-contributor cannot counteract a confirmed NL move in its band.
Priority: Must | Phase: 1 | Estimate: 8 sp | Dependencies: US-ENG-03, SPIKE-MASKING-MODEL
Traceability: LD-12, LD-8, FR-ADAPT-02/03, FR-NLT

**US-PERC-02 | Off-RT Realizer (min-phase default; FIR opt-in)** [Enabler]
As a **developer** I want an off-RT Realizer that turns a TargetState into finished coefficients — **minimum-phase biquads by default**, linear/mixed-phase FIR opt-in or content-selected — so the RT kernel only ramps & runs.

**Biquad fitting specification (architecture.md §4, locked 2026-06-13):**
- **Greedy iterative add:** Start with 2 biquads initialized at max-gain frequency; L-M optimize; check weighted Chebyshev error `E_max`; if > 1.0 dB and < 10 biquads, add 1 biquad at peak-residual frequency, re-optimize. Repeat until `E_max ≤ 1.0 dB` or 10 biquads.
- **L-M optimizer:** Semi-analytical Jacobian (log-magnitude separability + per-biquad finite differences); projected-gradient box constraints (f0 ∈ [50, 20k], Q ∈ [0.5, 10], gain ∈ [-12, +12]); terminate at ||J^T r||_inf < 1e-5 or 200 iterations.
- **Error metric:** Weighted Chebyshev-adjacent, `E_max = max_k( W[k] × |H(f_k) − target[k]| )` dB, where `W[k] = W_ath × W_erb × W_intent` (absolute-threshold perceptual weight × ERB-bandwidth normalization × intent salience amplification).
- **Biquad structure:** TDF-II (Transposed Direct Form II) for numeric stability. Promote end sections to shelves (low-shelf at f0 < 200 Hz, high-shelf at f0 > 8 kHz). Sort by ascending f0.
- **Convergence:** Typical ~20–50 L-M iterations per greedy pass; ~5 passes for typical curve = ~10–15 ms total on M1 Pro.
- **Test acceptance:** (1) Null test: all-zero target → E_max ≤ 0.01 dB. (2) Single-peak test: +6 dB at 1 kHz → 1 section, E_max ≤ 1.0 dB. (3) Stress test: 1000 random ERB curves → ≥95% meet budget in ≤8 sections within 10 ms. (4) Stability: all poles `|p| < 1 − 1e-6`. (5) Phase coherence: re-sum comb artifacts ≤ −20 dB relative to direct signal.

Acceptance: LD-13; biquad fit per spec above (greedy add + L-M, ERB/masking-weighted, ≤ ±1 dB to target); no design/fitting on the audio thread; all 5 tests pass.
Priority: Must | Phase: 1 | Estimate: 13 sp | Dependencies: US-ENG-02, SPIKE-MASKING-MODEL, OQ-18
Traceability: LD-13, FR-TONAL-01, NFR-PERF-01, architecture.md §4 (biquad cascade fitting)

**US-PERC-03 | Masking/clarity contributor**
As **Marcus** I want masked detail (e.g. a buried instrument region) lifted so I can actually hear what's playing.
Acceptance: ERB/Bark masking-relief contribution; conservative, gain-limited; imperceptible-as-motion (FR-ADAPT note).
Priority: Should | Phase: 1 | Estimate: 8 sp | Dependencies: US-PERC-01, SPIKE-MASKING-MODEL
Traceability: LD-12, FR-ADAPT, OQ-22

### EP-REIMAGINE — Intensity Control

**US-RMG-01 | Single Reimagine intensity control (0 = bit-faithful)**
As **Ramith** I want one simple knob from "faithful" to "reimagined" so I can dial how much the app transforms my music.
Acceptance: FR-REIMAGINE-01/02; at 0% the engine is bypassed and output is MD5-identical to source (NFR-QUAL-03).
Priority: Must | Phase: 1 | Estimate: 5 sp | Dependencies: US-ENG-02, US-UI-02
Traceability: FR-REIMAGINE-01, FR-REIMAGINE-02, NFR-QUAL-03, LD-16

**US-RMG-02 | Intensity→parameter mapping (mix-range)**
As a **developer** I want the knob to crossfade original↔processed and scale clarity/widening across the mix-range, smoothly.
Acceptance: FR-REIMAGINE-03/04; ramped (FR-ADAPT-03); mapping curve per SPIKE-REIMAGINE-MAP.
Priority: Must | Phase: 1 | Estimate: 5 sp | Dependencies: US-RMG-01, SPIKE-REIMAGINE-MAP
Traceability: FR-REIMAGINE-03, FR-REIMAGINE-04, LD-16

---

## Phase 1.5 Stories — Stem-Based Object Engine ⛔ Won't, this horizon (re-anchor 2026-06-19)

> **⛔ Won't, this horizon (re-anchor v2.3, 2026-06-19):** Stem separation / object engine (EP-STEM) is out of this plan's window (sprint-plan.md §5, §6B): high compute/artifact risk; revisit only after the mix-based thesis is validated and loved. **All US-STEM-* stories below and the gating spikes SPIKE-PERF-BUDGET + SPIKE-SEP-QUALITY are tagged Won't, this horizon** — entries kept as the future roadmap, not scheduled.

> Own-player-only (LD-15). **Sized by SPIKE-PERF-BUDGET** (NFR-PERF-06) — which sets per-tier QualityProfile caps. Low risk on the M1 Pro floor + current hardware (LD-18).

### EP-STEM — Stem Separation, Per-Stem Chains, Spatial Placement, Unmasking

**US-STEM-01 | Offline 6-stem separation + SSD cache** [Enabler]
As a **developer** I want tracks separated offline into 6 stems (vocals/drums/bass/guitar/piano/other) via an on-device model (Demucs/HTDemucs through Core ML/MLX) and cached, without blocking playback.
Acceptance: FR-STEM-01; separation is non-RT; original mix plays immediately; progress indicated.
Priority: Must (Phase 1.5) | Phase: 1.5 | Estimate: 8 sp | Dependencies: SPIKE-SEP-QUALITY, SPIKE-PERF-BUDGET
Traceability: FR-STEM-01, NFR-PERF-06, LD-15

**US-STEM-02 | Per-stem render graph + re-sum** [Enabler]
As a **developer** I want the kernel to render N stems each through its own chain, parallelised via Audio Workgroups, and re-sum to binaural without glitches.
Acceptance: FR-STEM-02; holds the per-buffer deadline at max-quality on a base Apple-Silicon laptop (NFR-PERF-06) or the QualityProfile reduces stem count first.
Priority: Must (Phase 1.5) | Phase: 1.5 | Estimate: 8 sp | Dependencies: US-STEM-01, US-PERC-02, US-SPAT-01 (BRIR), SPIKE-PERF-BUDGET
Traceability: FR-STEM-02, NFR-PERF-06

**US-STEM-03 | Per-stem spatial placement**
As **Tom** I want each stem placed in the spatial field so I can spread the mix into a personal stage.
Acceptance: FR-STEM-02 (spatial); each stem rendered via the BRIR field at its own position/level.
Priority: Should (Phase 1.5) | Phase: 1.5 | Estimate: 8 sp | Dependencies: US-STEM-02
Traceability: FR-STEM-02, FR-SPAT-01, LD-14

**US-STEM-04 | Between-stem unmasking**
As **Marcus** I want masked sources (e.g. vocals under guitar) genuinely unmasked, not approximated.
Acceptance: FR-STEM-03; masking computed between stems (ERB/Bark); measurable improvement in the masked source's prominence.
Priority: Should (Phase 1.5) | Phase: 1.5 | Estimate: 8 sp | Dependencies: US-STEM-02, US-PERC-03
Traceability: FR-STEM-03, LD-12

**US-STEM-05 | Per-stem natural-language targeting**
As **Tom** I want to say "bring up the guitar" / "move the vocals forward" and have it act on that stem.
Acceptance: FR-STEM-04; NL macro targets a stem (governing principle, LD-8); shown in transparency view.
Priority: Should (Phase 1.5) | Phase: 1.5 | Estimate: 5 sp | Dependencies: US-STEM-02, EP-NLT
Traceability: FR-STEM-04, FR-NLT, LD-8

**US-STEM-06 | Quality-gating + graceful fallback**
As **Ramith** I want the app to never present an obviously-broken separated stem.
Acceptance: FR-STEM-05; poorly-separated stems merged into "other" / fewer stems; confidence bounds the achievable Reimagine ceiling.
Priority: Must (Phase 1.5) | Phase: 1.5 | Estimate: 5 sp | Dependencies: US-STEM-01, SPIKE-SEP-QUALITY
Traceability: FR-STEM-05, OQ-20

**US-STEM-07 | Reimagine stem-range + own-player-only boundary**
As **Ramith** I want the Reimagine knob's upper range to unlock the stem-based spatial reimagining in the player, and the system-wide path to fall back to mix-level gracefully.
Acceptance: FR-REIMAGINE-03 (stem range); FR-STEM-06 (tap path = mix-level; app indicates stem features are own-player-only).
Priority: Should (Phase 1.5) | Phase: 1.5 | Estimate: 3 sp | Dependencies: US-STEM-02, US-RMG-02
Traceability: FR-REIMAGINE-03, FR-STEM-06, LD-15, LD-16

---

## Phase 2 Stories — System-Wide Enhancement & UI Polish ⛔ Won't, this horizon (re-anchor 2026-06-19)

> **⛔ Won't, this horizon (re-anchor v2.3, 2026-06-19):** System-wide capture / virtual device (**EP-SYSWIDE** + **EP-VDEVICE** and all US-SYS-* / US-SYSW-* stubs) is out of this plan's window (sprint-plan.md §5, §6B): a different product surface — our story is *this Mac → this DAC, bit-perfect*. The gating spike **SPIKE-VDEVICE** is likewise Won't, this horizon. Entries kept as the future roadmap, not scheduled. *(Note: the project's own Phase 2 — sprint-plan.md §4 S15–S18, the Adaptive Sound thesis: masking/Clarity + steerable Reimagine + BRIR — is a separate, in-roadmap "Phase 2" and is NOT covered by this Won't tag. The backlog's "Phase 2" label here means system-wide only.)*

Phase 2 is far out and subject to change. Full story detail is deferred; epics and stubs provide engineering team visibility for architecture decisions made now.

> **UI & Branding Note:** Phase 2 also includes UI polish and brand identity implementation (Flux mark, Sunset gradient, Space Grotesk typography). This is deferred from Phase 1c (DSP-first focus). See [branding/BRAND-INTEGRATION-PLAN.md](branding/BRAND-INTEGRATION-PLAN.md) for detailed guidance (app icon integration, color constants, typography, README branding section). Estimate: ~2–3 hours Phase 2 workstream.

### EP-VDEVICE — AudioServerPlugIn Virtual Device (FALLBACK PATH)

**Epic goal:** Build, sign, notarise, and install an AudioServerPlugIn that intercepts system audio from any application, processes it through the Adaptivity Engine, and forwards processed audio to the physical output device. **This epic covers the FALLBACK PATH only** (macOS < 14.2 or where the user explicitly requests a persistent selectable output device). The primary Phase 2 mechanism is the Core Audio process tap (EP-SYSWIDE / US-SYSW-TAP). Both paths are needed; this epic is not deprecated.

> **Prior-art note (ADR-002, Proposed — `docs/architecture/prior-art.md`):** Reference implementation: **libASPL (MIT)** as the AudioServerPlugIn framework; **AudioCap (BSD-2)** as tap-path sample. Ref-only: eqMac (Apache-2.0 v1.3.2 snapshot), BlackHole (GPL — ref only), Background Music (GPL — ref only).

**Critical architecture notes:**
- Plug-in must be pure C/C++ — no Objective-C, no Swift, no Foundation (FR-SYS-06 / CON-03).
- Plug-in runs inside coreaudiod (CON-04); IPC via Mach services only (FR-SYS-05).
- Privileged installer uses **SMAppService** (DEP-08; SMJobBless deprecated on macOS 13+).
- Plan 6–10 engineering weeks for driver stability alone (PRD §4 Phase 2 note).
- Validate feasibility first via SPIKE-VDEVICE.

---

#### US-SYS-01 [Stub] — AudioServerPlugIn virtual device bundle (fallback path)

As a **developer** I want an AudioServerPlugIn bundle (built on libASPL, MIT) that appears as a selectable output in macOS Sound settings and passes audio to the DSP engine via Mach IPC.
Refs: FR-SYS-01, FR-SYS-05, FR-SYS-06, CON-03, CON-04, DEP-05, DEP-08, DEP-13 | Phase: 2 | Estimate: TBD (post-spike)

---

#### US-SYS-02 [Stub] — Privileged installer with informed consent UX (fallback path)

As a **Ramith** I want a guided one-click installer that explains what it does in plain language, asks for admin password once, and restarts coreaudiod transparently.
Refs: FR-SYS-02, NFR-INSTALL-02, OQ-01 | Phase: 2 | Estimate: TBD

---

#### US-SYS-03 [Stub] — Crash-safe audio passthrough (fallback path)

As a **system** I want the virtual device to pass audio through unprocessed if the companion app crashes, so that no system-level audio outage occurs.
Refs: FR-SYS-04 | Phase: 2 | Estimate: TBD

---

#### US-SYS-04 [Stub] — Safe uninstall and fallback (fallback path)

As a **Tom** I want a one-click uninstall that removes the HAL plug-in, restarts coreaudiod, and restores system output with no residual orphaned devices.
Refs: FR-SYS-03, NFR-INSTALL-04 | Phase: 2 | Estimate: TBD

---

#### US-SYS-05 [Stub] — Auto-reconnect after OS update or coreaudiod restart (fallback path)

As a **Marcus** I want the virtual device to reconnect automatically after a macOS update or coreaudiod restart without manual intervention.
Refs: P2-3 | Phase: 2 | Estimate: TBD

---

### EP-SYSWIDE — System-Wide Adaptivity and Per-App Profiles

> **Primary mechanism (macOS 14.2+):** Core Audio process tap (`CATapDescription` + `AudioHardwareCreateProcessTap` + private aggregate device with original output muted) — no HAL plug-in, no privileged helper, no coreaudiod restart, no admin password; TCC audio-capture consent only. Sample reference: **AudioCap (BSD-2)** — `docs/architecture/prior-art.md`. This is ADR-002 (Proposed); architecture discussion will confirm. The driver path (EP-VDEVICE) remains as fallback for macOS < 14.2.

---

#### US-SYSW-TAP [Stub] — Core Audio process tap activation (primary path, macOS 14.2+)

As a **Marcus** I want to enable system-wide audio enhancement with a single permission dialog — no admin password, no driver install — so that all apps (Spotify, YouTube, Zoom) benefit without any system disruption.
Refs: FR-SYS-07, FR-SYS-08, CON-10, OQ-07 | Phase: 2 | Estimate: TBD (post SPIKE-VDEVICE tap workstream) | Note: Depends on confirming exact macOS version floor in AudioHardwareTapping.h (CON-10).

---

#### US-SYSW-01 [Stub] — All Phase 1 adaptivity applied system-wide

As a **Marcus** I want content-aware EQ, volume compensation, and ambient sensing to work for Spotify, Apple Music, and YouTube, not just the own-player.
Refs: P2-5, FR-SYS-07 (primary) / FR-SYS-01 (fallback) | Phase: 2 | Estimate: TBD

---

#### US-SYSW-02 [Stub] — Per-app enhancement profiles

As a **Tom** I want different EQ profiles for Spotify (music) and Zoom (voice), so that each app sounds optimal without me switching profiles manually.
Refs: P2-4 | Phase: 2 | Estimate: TBD

---

#### US-SYSW-03 [Stub] — Low-latency mode for gaming and video calls (< 5 ms added latency)

As a **Tom** I want a low-latency mode that keeps added DSP latency under 5 ms so that the tap or virtual device does not cause perceptible delay during Zoom calls or gaming.
Refs: P2-6, NFR-PERF-05 | Phase: 2 | Estimate: TBD

---

#### US-SYSW-04 — *removed (superseded).*
True per-instrument source separation is the **Phase-1.5 own-player stem engine** (EP-STEM / US-STEM-*, LD-15), **not** a Phase-2 system-wide feature. The old "Class 2b / gate on M2+ vs M1-fallback" framing is obsolete: the floor is M1 Pro (LD-18) and separation is an offline pre-pass, not a runtime chip gate.

---

---

## Spike / Research Stories

Spikes are time-boxed investigations. Each produces a written decision or recommendation that unblocks one or more user stories. Spikes do not produce shippable code.

---

#### SPIKE-HRTF — HRTF dataset and convolution engine validation

**Goal:** Prior-art research pass has largely resolved the dataset selection question (OQ-04 resolved — see `docs/architecture/prior-art.md`). The remaining work is: (a) confirm SADIE II (Apache-2.0) SOFA file quality and subject coverage for the 3-preset requirement (FR-SPAT-02); (b) benchmark partitioned SOFA-HRIR convolution using **libmysofa (BSD-3)** + **vDSP / FFTConvolver (MIT)** on the M1 Pro / 16 GB floor (LD-18) at 44.1 and 48 kHz; (c) confirm that Apple PHASE / AVAudioEnvironmentNode / AUSpatialMixer are explicitly **not** used (their HRTFs are fixed and non-replaceable — custom convolution is the only path); (d) confirm FFTConvolver `LICENSE` file path in-repo (README says MIT; canonical `/LICENSE` path 404'd per `docs/architecture/prior-art.md` §5).

**Outputs:**
- SADIE II subject selection for generic / small-head / large-head presets with SOFA file inventory
- Performance benchmark: libmysofa SOFA load time + partitioned convolution CPU cost on M1
- FFTConvolver licence file path confirmed (or decision to use vDSP-only)
- Go/no-go recommendation for FR-SPAT-01 scope; note that dataset licence (Apache-2.0) is already confirmed

**Time-box:** 2 days (reduced from 3 — dataset selection resolved) | **Phase:** 1 | **Estimate:** 2 sp | **Blocks:** US-SPAT-01
**Traceability:** FR-SPAT-01, FR-SPAT-02, ASM-04, DEP-06, DEP-12, OQ-04 (resolved: SADIE II default)

---

#### SPIKE-DEVCORRLIB — Device correction library scope and data sourcing

**Goal:** OQ-08 is partially resolved: **AutoEq computed parametric curves (MIT + attribution)** are the confirmed source. The remaining work is: (a) select the 20+ headphone/speaker models to ship at Phase 0; (b) verify upstream measurement provenance per model — AutoEq's code is MIT but upstream measurers (oratory1990, Crinacle, etc.) may be CC-BY-NC-SA; ship only AutoEq's *computed* curves with attribution, do not republish raw databases (see `docs/architecture/prior-art.md` §5 and CON-12); (c) define format for integrating AutoEq parametric curves into the app's EQ profile format; (d) identify owner of ongoing library curation.

**Outputs:**
- List of 20+ validated device correction profiles with per-model provenance note
- Confirmation that only AutoEq *computed* curves (not raw measurements) are shipped
- Engineering effort estimate to integrate AutoEq data into the profile format
- Ongoing curation process and owner identified

**Time-box:** 3 days | **Phase:** 0 | **Estimate:** 2 sp | **Blocks:** US-TON-02
**Traceability:** FR-TONAL-02, ASM-05, DEP-07, OQ-08 (resolved: AutoEq MIT computed curves)

---

#### SPIKE-NLT-ARCH — Conversational Tuning interpretation mechanism selection ⛔ Won't, this horizon (re-anchor 2026-06-19)

> **⛔ Won't, this horizon (re-anchor v2.3, 2026-06-19):** Gating spike for EP-NLT (tagged Won't, this horizon). Out of this plan's window; not scheduled.

**Goal:** Evaluate the three candidate approaches for text-to-DSP-intent derivation (a) deterministic keyword/rule engine, (b) on-device small language model, (c) cloud LLM API) against the acceptance criteria in FR-NLT-04 (< 1500 ms), NFR-PRIV-01..05, offline/airplane-mode behaviour, App Store compliance, and ongoing cost. This is OQ-11 and is explicitly deferred by design — do not resolve without founder input.

**Outputs:**
- Written comparison of all three approaches against criteria
- Latency benchmark (prototype or reference data) for the chosen mechanism especially for multi-component abstract phrases (ASM-09)
- Privacy implications per mechanism documented for App Store privacy label
- Recommended approach with founder sign-off
- Engineering effort delta per approach

**Time-box:** 5 days | **Phase:** 1 (must complete before US-NLT-00) | **Estimate:** 5 sp
**Traceability:** FR-NLT-01..12, NFR-PRIV-01..05, ASM-09, OQ-11

---

#### SPIKE-AMBNOISE — Ambient noise sensing: sample window and smoothing specification

**Goal:** Determine the optimal mic sample window length, A-weighted SPL smoothing parameters, and hysteresis thresholds for the on-demand ambient sensing feature (FR-ADAPT-04). Validate the 3-second sample window proposed in requirements and confirm whether the < 5-second DSP adaptation target from Journey 2.5 is achievable.

**Outputs:**
- Validated sample window length and smoothing algorithm recommendation
- Acceptance criterion update for NFR-PERF-04 and FR-ADAPT-04 if needed
- Audio engineer sign-off

**Time-box:** 2 days | **Phase:** 1 (must complete before US-AMB-01) | **Estimate:** 2 sp
**Traceability:** FR-ADAPT-04, NFR-PERF-04, OQ-03

---

#### SPIKE-VDEVICE — Phase 2 system-wide audio feasibility (tap-primary + driver-fallback) ⛔ Won't, this horizon (re-anchor 2026-06-19)

> **⛔ Won't, this horizon (re-anchor v2.3, 2026-06-19):** Gating spike for EP-SYSWIDE / EP-VDEVICE (tagged Won't, this horizon). Out of this plan's window; not scheduled.

**Goal:** Validate both Phase 2 mechanisms (per ADR-002 Proposed — `docs/architecture/prior-art.md`). Two parallel workstreams:

**Workstream A — Core Audio process tap (primary path, macOS 14.2+):**
- Confirm exact minimum macOS version for `CATapDescription` + `AudioHardwareCreateProcessTap` + muted-aggregate-device topology by inspecting `<CoreAudio/AudioHardwareTapping.h>` SDK headers (CON-10 — 14.2 vs. 14.4 unconfirmed).
- Prototype the tap + private aggregate device topology using **AudioCap (BSD-2)** as reference.
- Confirm TCC entitlement string (NSAudioCaptureUsageDescription) and purple indicator behaviour.
- Measure added round-trip latency of tap path vs. direct output (target ≤ 10 ms, NFR-PERF-05).

**Workstream B — AudioServerPlugIn (fallback path):**
- Prototype an AudioServerPlugIn skeleton (pure C, Mach IPC stub, loads into coreaudiod) on macOS 14 Sonoma using **libASPL (MIT)** as the framework (DEP-13).
- Validate SMAppService as replacement for deprecated SMJobBless.
- Confirm notarization requirements for HAL plug-ins.
- Estimated engineering weeks for driver stability (targeting 6–10 weeks per PRD).
- IPC latency budget.
- OQ-01 (auto-switch vs. manual output selection) impact on installer UX.

**Outputs:**
- Confirmed macOS version floor for tap path; go/no-go on tap-primary vs. driver-fallback split
- Working tap prototype demonstrating muted-aggregate-device topology with measured latency
- Working plug-in skeleton (libASPL) that loads without coreaudiod crash
- SMAppService migration recommendation
- Engineering estimate for both paths; phasing recommendation
- OQ-01 recommendation

**Time-box:** 7 days | **Phase:** 2 | **Estimate:** 7 sp | **Note:** Pre-work for Phase 2 (can begin after core Phase 1 features stabilize)
**Traceability:** FR-SYS-01..06, FR-SYS-07, FR-SYS-08, DEP-05, DEP-08, DEP-13, CON-03, CON-04, CON-10, OQ-01, OQ-07, ASM-03, ASM-07

---

#### SPIKE-IPREVIEW — Patent IP review for psychoacoustic bass enhancement (OQ-16)

**Goal:** Obtain formal IP counsel review before any public release of FR-TONAL-04. This is not a technical investigation — it is a legal/IP task. Engineering may proceed with the mono-summed NLD design (CON-11) but public release is blocked until this review is complete.

**Scope:**
- Verify US-5,930,373 (Waves/MaxxBass, ~2019) is truly expired on USPTO before relying on the nonlinear-multiplier + harmonics approach.
- Confirm the mono-summed (L+R) low-band NLD design clearly falls outside Waves US-11,102,577 (active, ~2038 — covers per-channel/stereo virtual bass).
- Check whether any Xperi/SRS virtual-bass patents active post-~2006 are triggered by the implementation.
- Document the legal opinion and approved implementation constraints for the engineering team.

**Outputs:**
- Written IP counsel opinion on the three patent questions above
- Approved implementation note: "use mono-summed low-band NLD; confirmed clear of US-11,102,577"
- Go/no-go sign-off for public release of FR-TONAL-04

**Time-box:** Depends on IP counsel availability — not a fixed time-box; must complete before Phase 0 public release | **Phase:** 0 (before public release, not before engineering) | **Estimate:** 1 sp (BA coordination only; legal cost is external)
**Traceability:** FR-TONAL-04, CON-11, OQ-16

---

#### SPIKE-LIBBS2B — libbs2b licence dispute resolution (OQ-17)

**Goal:** Resolve the disputed libbs2b licence (MIT vs. GPL-2.0+) before shipping FR-SPAT-03 (crossfeed). This is a short investigation, not a technical prototype.

**Scope:**
- Open the upstream libbs2b repository and inspect the canonical `LICENSE` file and C source file headers.
- If clearly MIT: confirm and record; unblocks shipping libbs2b.
- If GPL or ambiguous: do not ship libbs2b. Instead, plan a clean-room reimplementation of the Bauer stereophonic-to-binaural crossfeed algorithm from the public specification (a small number of biquad filters + a delay line — trivial to reimplement). Estimate reimplementation effort.

**Outputs:**
- Definitive licence finding with source (repo URL + commit hash)
- Decision: ship libbs2b (if MIT confirmed) OR reimplement (if not)
- If reimplement: engineering effort estimate added to US-DEVICE-07

**Time-box:** 0.5 days | **Phase:** 0 | **Estimate:** 1 sp | **Blocks:** US-DEVICE-07
**Traceability:** FR-SPAT-03, US-DEVICE-07, CON-12, DEP-16, OQ-17

---

#### SPIKE-PERF-BUDGET — Stem-engine render budget (tuning; sets Phase 1.5 caps) ⛔ Won't, this horizon (re-anchor 2026-06-19)
> **⛔ Won't, this horizon (re-anchor v2.3, 2026-06-19):** Gating spike for EP-STEM (tagged Won't, this horizon). Out of this plan's window; not scheduled.

**Goal:** Measure the real cost of the Phase-1.5 render — up to **6 stems × per-stem EQ/dynamics/spatial + BRIR convolution**, re-summed — on the **M1 Pro / 16 GB floor** (LD-18; foreground sole-occupancy): per-stem RT cost, worst-case (p99.9) render vs. the per-buffer deadline (NFR-PERF-01), memory for 6 cached stems + BRIR kernels, Audio-Workgroups parallel scaling. **Compare independent-per-stem BRIR vs. shared-late-reverb decomposition** (expect ~6× saving — review C2). Set per-tier QualityProfile caps (stem count / reverb-tail length — *not* buffer size; review C5).
**Output:** measured budget + per-tier QualityProfile caps. Given LD-18 (M1 Pro floor, sole-occupancy) + current-gen headroom (M4/M5 ~3–4× the floor), this is a **tuning spike that sets caps — not a go/no-go.**
Time-box: 5 days | Estimate: 5 sp | Refs: NFR-PERF-06, OQ-19, EP-STEM

#### SPIKE-SEP-QUALITY — 6-stem separation model, quality, gating, and ML backend decision ⛔ Won't, this horizon (re-anchor 2026-06-19)
> **⛔ Won't, this horizon (re-anchor v2.3, 2026-06-19):** Gating spike for EP-STEM (tagged Won't, this horizon). Out of this plan's window; not scheduled.

**Goal:** Evaluate 6-stem separation (Demucs/HTDemucs) on-device via MLX (primary) across genres; quantify separation quality and artifacts (esp. guitar/piano); define the **quality-gating** criteria (when to merge a stem into "other" / drop to fewer stems) and how confidence bounds the Reimagine ceiling. Additionally, **measure runtime per hardware tier** (M1 Pro, M4, M5) to lock the MLX-vs-Core ML decision (primary is MLX unconditional unless Phase 1.5 tuning reveals user-visible latency).

**Test Protocol (see FR-STEM-05 Validation Protocol):**
1. **Listening panel:** 3–5 audio engineers. Per-track A/B test: original mix vs. separated+recombined stems vs. Reimagine stem-range (controlled blind).
2. **Artifact scoring:** 5-point scale per stem (leakage, distortion, phase). Threshold: ≤1 artifact per stem passes; >1 artifact merged into "other" or track ceiling lowered.
3. **Genre coverage:** representative tracks from vocal-heavy (pop/soul), drums-prominent (rock/electronic), classical/acoustic (piano/strings), mixed-instrumentation (indie/alternative). At least 12 tracks (3 per genre).
4. **Confidence metric:** fitted curve (1 − artifacts − penalty). Acceptance: ≥0.7 (full stem range), 0.5–0.7 (mix range), <0.5 (mix-only). All genres must pass (0 broken stems audible; ≥3 usable stems per track).
5. **Hardware timing:** measure sec/track on M1 Pro (target hardware), M4 (current market), M5 (future-proofing). Log coldstart (first run) vs. cached (subsequent). Lock MLX-primary or escalate to Core ML eval if M1 Pro >20 sec/track (user-visible).

**Output:** (1) model choice + quality-gating policy + confidence curves (FR-STEM-05); (2) sec/track measurements at three hardware tiers + MLX-vs-Core-ML decision (architecture.md §12); (3) per-genre artifact threshold recommendations; (4) test dataset (tracks + panel feedback) for regression testing in Phase 1.5+.
Time-box: 5 days | Estimate: 5 sp | Refs: FR-STEM-01/05 (validation protocol), architecture.md §12 (ML decision tree), OQ-20

#### SPIKE-REIMAGINE-MAP — Reimagine intensity→parameter mapping + user test
**Goal:** Define the mapping from the 0–100% knob to crossfade + spatial spread + unmask depth (mix-range and stem-range ceiling), and validate with a small listening test that the progression feels natural and that 0% is unmistakably "faithful".
**Output:** the mapping curve (FR-REIMAGINE-03) + test findings.
Time-box: 3 days | Estimate: 3 sp | Refs: FR-REIMAGINE-03/04, OQ-21

#### SPIKE-MASKING-MODEL — Moore-Glasberg roex excitation-pattern implementation + validation
**Goal (locked model choice, 2026-06-13):** Implement the roex(p) excitation-pattern masking model on the ERB-rate scale (34 bands, 50 Hz–16 kHz) as locked in architecture.md §4 (ADR-006 amendment). Prototype on vDSP to confirm off-RT cost; unit-test masking-aware clarity decisions (before/after) on 8–10 representative tracks; document the roex parameter fitting and the absolute-threshold floor (ISO 226); validate arbitration logic (governing-principle locks + additive composition + proportional clamping) in the Arbiter unit tests.
**Output:** (1) vDSP implementation of roex convolution + masked-threshold per-frame computation; (2) unit tests (masking-aware EQ vs. naive level-match A/B); (3) arbitration code + tests for LD-8 governing-principle locks and multi-contributor composition; (4) off-RT cost profile (sec/frame, vDSP utilization); (5) documentation of roex parameters and ISO 226 absolute threshold application.
Time-box: 4 days | Estimate: 5 sp | Refs: architecture.md §4 (Moore-Glasberg roex lock, arbitration rules), LD-12 (masking domain), US-PERC-01/03 (Arbiter + clarity contributor), US-STEM-04 (between-stem unmasking)

#### SPIKE-BRIR — BRIR room synthesis + externalisation validation
**Goal:** Validate the BRIR-first immersion: synthesise (image-source + FDN) or source CC0/CC-BY room responses combined with the SADIE-II HRIR; ABX-test externalisation **vs. the dry-HRTF minimal mode**; confirm convolution cost fits the budget.
**Output:** a default "treated room" BRIR + alternates, and evidence BRIR externalises better than dry HRTF (FR-SPAT-01).
Time-box: 4 days | Estimate: 5 sp | Refs: FR-SPAT-01/05, LD-14

#### SPIKE-TELEMETRY — Crash reporting and analytics SDK selection

**Goal:** Evaluate crash reporting and anonymous analytics SDK options (Sentry, Firebase Crashlytics, TelemetryDeck) against NFR-PRIV-04, App Store privacy label requirements, and EU data residency considerations. Recommend SDK and integration approach.

**Outputs:**
- Recommended SDK with privacy justification
- App Store privacy nutrition label entries required
- Integration effort estimate

**Time-box:** 2 days | **Phase:** 0 | **Estimate:** 1 sp | **Blocks:** US-PRIV-03
**Traceability:** NFR-PRIV-04, OQ-10

---

#### SPIKE-OQ15BC — NLT delta cap and hearing-profile reconciliation defaults (OQ-15b / OQ-15c)

**Goal:** Obtain founder confirmation on the two pending OQ-15 recommendations: (b) post-calibration NLT delta review UX; (c) ±12 dB per-band accumulated delta cap. Engineering must not proceed on profile-delta storage design (FR-NLT-06, FR-HEAR-01) until both are confirmed. This spike is a facilitated decision session, not a technical investigation.

**Outputs:**
- Written founder confirmation of OQ-15b (post-calibration review UX) and OQ-15c (±12 dB cap)
- Updated acceptance criteria for FR-NLT-06 and FR-HEAR-01

**Time-box:** 1 day (decision session + write-up) | **Phase:** 1 (before profile-delta storage design) | **Estimate:** 1 sp
**Traceability:** FR-NLT-06, FR-HEAR-01, OQ-15

---

---

---

> **Sprint sequencing and epic ordering:** See `docs/sprints/sprint-plan.md` for sprint assignments, dependency sequencing, and the release schedule, governed by the `docs/sprints/00-sprint-model.md` methodology. This backlog contains stories and epics; sprint-plan.md contains the sprint schedule and planning details.

---

## Open Items Requiring Founder / Product Owner Decision Before Engineering Can Proceed

The following items are tracked from OQ-* and must be resolved before the stories that depend on them enter sprint planning:

| Item | Blocks | Urgency |
|------|--------|---------|
| SPIKE-LOUDNESS-COMP-TUNING — FR-TONAL-03 loudness-compensation fraction validation | Phase 0 Polish: determine whether 50% (provisional) is the correct fraction; test frequency-variable fractions; validate gain caps (+6 dB bass, +4 dB treble). MUSHRA-style listening test, 10+ listeners, 4–6 tracks at −15 dB and −25 dB SPL offsets. Audio-dsp endorses 50% as provisional with precedent (THX Loudness Plus, broadcast 40–60% range); Phase 0 testing will lock final value (likely 40–55%). | Phase 0 Polish — before Phase 0 release gates; implementation unblocked with provisional values. |
| SPIKE-HEARING-SAFETY-VALIDATION — FR-NLT-02 numeric clamps UX validation | Phase 0 Polish: validate whether the locked hearing-safety bounds (+10 dB per-band, +12 dB cumulative, −9 LUFS session cap, confirmation gate at +8 dB) are appropriately responsive to user requests ("MUCH louder" should feel satisfied by +10 dB, not over-constrained). Measure: (a) Can users achieve their desired adjustments within the bounds? (b) Is the confirmation gate at +8 dB triggering appropriately (not too frequent, not missed)? (c) Is the session loudness tracker visible/useful? Test with 5–8 listeners, naturalistic usage over 1–2 weeks. Accept outcome: if +10 dB is perceived as too tight, widen to +12 dB. If confirmation gate is noise, move to +10 dB. If no feedback, lock the bounds as-is. | Phase 0 Polish — before Phase 0 release gates; implementation unblocked with locked numeric values. |
| OQ-11 — NLT interpretation mechanism | SPIKE-NLT-ARCH → all US-NLT-* stories | ⛔ Won't, this horizon (re-anchor 2026-06-19) — EP-NLT is out-of-window; not a near-term blocker |
| ~~OQ-15b — post-calibration NLT delta review UX~~ | ~~SPIKE-OQ15BC → FR-NLT-06, FR-HEAR-01~~ | **Resolved (founder decision, 2026-06-13).** Session-scoped by default; persists to profile only when user taps [Yes, keep it] (FR-NLT-06). Confirmed in requirements v0.6 change note and FR-NLT-06 acceptance criteria. |
| ~~OQ-15c — ±12 dB NLT delta cap~~ | ~~SPIKE-OQ15BC → FR-NLT-06~~ | **Resolved (locked in BLK-8 blocker fix, 2026-06-13).** Cumulative NL interpreter output capped at +12 dB total loudness change (all bands combined); per-band caps +10 dB target / +12 dB hard clamp; low-confidence magnitude capped ±3 dB. Documented in architecture §11 and requirements FR-NLT-02. |
| ~~OQ-02 — monetization / feature gating model~~ | ~~Feature flag architecture across all phases~~ | **Resolved and removed (LD-9).** Project is personal / open-source and non-commercial. No feature-flag or paywall architecture required anywhere. |
| OQ-01 — Phase 2 auto-switch system output | SPIKE-VDEVICE → US-SYS-02 installer UX (driver fallback path) | ⛔ Won't, this horizon (re-anchor 2026-06-19) — gates EP-SYSWIDE/EP-VDEVICE, which are out-of-window |
| OQ-07 — macOS minimum deployment target | ASM-01 validation; CON-10 — tap path requires ≥ 14.2/14.4 (verify); affects Phase 2 mechanism choice | Medium — before Phase 0 Sprint 1; critical for Phase 2 tap-vs-driver decision |
| OQ-13 — NLT clarification round limit | US-NLT-07 acceptance criteria (1 round vs. 2?) | Medium — blocks US-NLT-07 |
| OQ-14 — Conversational Tuning multilingual support scope | FR-NLT-* scope, NFR-L10N-01 | ⛔ Won't, this horizon (re-anchor 2026-06-19) — gated on EP-NLT, which is out-of-window |
| OQ-10 — Crash reporting SDK | US-PRIV-03 / SPIKE-TELEMETRY output | Low — SPIKE-TELEMETRY resolves this |
| OQ-16 — Patent IP review (psychoacoustic bass, FR-TONAL-04) | SPIKE-IPREVIEW → public release of US-TON-04 | High — blocks public release only; engineering unblocked with mono-summed design |
| OQ-17 — libbs2b licence dispute (FR-SPAT-03 crossfeed) | SPIKE-LIBBS2B → US-DEVICE-07 | Medium — blocks US-DEVICE-07; clean-room reimplement is ready fallback |
| ~~OQ-04 — HRTF dataset selection~~ | ~~SPIKE-HRTF → US-SPAT-01~~ | **Resolved (prior-art pass):** SADIE II (Apache-2.0) is the default; libmysofa (BSD-3) + FFTConvolver (MIT) for convolution; Apple HRTF APIs not used. SPIKE-HRTF scope reduced to performance benchmarking only. |
| ~~OQ-08 — Device correction library source~~ | ~~SPIKE-DEVCORRLIB → US-TON-02~~ | **Resolved (prior-art pass):** AutoEq computed parametric curves (MIT + attribution) confirmed as source. SPIKE-DEVCORRLIB continues for model selection and provenance verification. |
| OQ-18 — Min-phase vs linear-phase per content | SPIKE / US-PERC-02 (off-RT Realizer) | High — before Realizer implementation |
| OQ-19 — Stem-engine render budget (caps) | SPIKE-PERF-BUDGET → EP-STEM QualityProfile caps | ⛔ Won't, this horizon (re-anchor 2026-06-19) — gates EP-STEM, which is out-of-window |
| OQ-20 — 6-stem quality-gating policy | SPIKE-SEP-QUALITY → US-STEM-06 | ⛔ Won't, this horizon (re-anchor 2026-06-19) — gates EP-STEM, which is out-of-window |
| OQ-21 — Reimagine intensity→parameter mapping | SPIKE-REIMAGINE-MAP → US-RMG-02 | Medium-High — before US-RMG-02 |
| OQ-22 — Masking + partial-loudness model choice | SPIKE-MASKING-MODEL → US-PERC-01/03, US-STEM-04 | Medium — before EP-PERCEPTUAL |
