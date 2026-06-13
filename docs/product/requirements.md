# Product Requirements Document
## Adaptive Sound — Object-Based Spatial Music Renderer (macOS)

**Document ID:** PRD-ASE-001  
**Version:** 0.6 — aligned to architecture.md v0.3 (architecture is the source of truth)  
**Date:** 2026-06-13  
**Author:** Business Analyst (Lead)  
**Status:** Open for stakeholder review  

---

## Table of Contents

1. [Stakeholders](#1-stakeholders)
2. [User Journeys and Workflows](#2-user-journeys-and-workflows)
3. [Functional Requirements](#3-functional-requirements)
4. [Non-Functional Requirements](#4-non-functional-requirements)
5. [Adaptivity Signal → Decision Matrix](#5-adaptivity-signal--decision-matrix)
6. [Assumptions, Constraints, and Dependencies](#6-assumptions-constraints-and-dependencies)
7. [Open Questions and Requirement Gaps](#7-open-questions-and-requirement-gaps)

> **v0.2 change note (2026-06-12):** Added FR-NLT (Natural-Language Tuning) requirements group (FR-NLT-01 through FR-NLT-11), Conversational Tuning phrase-mapping table, Journey 2.7, two new rows in the Adaptivity Signal Decision Matrix, and five new Open Questions (OQ-11 through OQ-15). Architecture for text interpretation is explicitly deferred — see OQ-11.

> **v0.3 change note (2026-06-12):** Folded in two founder decisions (Decisions A and B). Added LD-8 (unified DSP action-space model + governing principle + phase). Reframed FR-NLT-02 output target as an explicit DSP action vector. Reframed FR-NLT-10 as a point on the directness spectrum (band approximation is the shippable baseline). Added FR-NLT-12 (abstract/aesthetic descriptors as first-class inputs). Expanded §3.9.1 phrase-mapping table with aesthetic/emotional descriptor rows and added a unified action-space lead-in paragraph. Updated Adaptivity Signal Decision Matrix NLT rows to governing-principle framing. Resolved OQ-12 (band approximation baseline; source separation optional later) and OQ-15a (governing-principle takes precedence); recorded recommended defaults for OQ-15b and OQ-15c as pending confirmation. OQ-11 remains deferred.

> **v0.4 change note (2026-06-12 — prior-art refinement pass):** Folded in findings from `docs/architecture/prior-art.md`. (A) FR-SYS group: added FR-SYS-07 (process-tap primary path) and FR-SYS-08 (TCC permission for tap); reframed FR-SYS-01..06 as the FALLBACK (driver) path; updated Journey 2.6 to tap-primary + driver-fallback flows; updated NFR-INSTALL-01/02/03/04 and CON-05/07 for tap vs. driver paths; added CON-10 (tap requires macOS 14.2+/14.4+ — verify); updated OQ-07 note. (B) FR-SPAT-01/02: clarified HRTF rendering as custom SOFA-HRIR partitioned convolution (libmysofa + FFTConvolver); noted Apple PHASE/AVAudioEnvironmentNode HRTFs are non-replaceable; updated DEP-06 and ASM-04. (C) FR-ADAPT / LD-5 note: added clarification that real-time ML inference uses BNNS Graph (RT-safe); Core ML / SoundAnalysis are off-RT pre-analysis only. (D) FR-TONAL-04: added mono-summed low-band constraint (patent avoidance — Waves US-11,102,577 active); added CON-11 (patent constraint); added OQ-16 (IP review spike). (E) DEP and CON: replaced vague data deps with concrete licensed picks (SADIE II Apache-2.0, libmysofa BSD-3, libebur128 MIT, AutoEq MIT, FFTConvolver MIT, libASPL MIT, Demucs+MLX MIT); added CON-12 (permissive-only shipping rule); added OQ-17 (libbs2b license dispute). Resolved OQ-04 (SADIE II default, IRCAM avoided) and OQ-08 (AutoEq MIT computed curves). OQ-11 (Conversational Tuning architecture) remains deferred.

> **v0.5 change note (2026-06-13 — architecture v0.2 alignment):** Major revamp to align with `docs/architecture/architecture.md` v0.2 (now the source of truth). Adopted the four-phase scheme (0 / 1 / 1.5 / 2). Added LD-11…LD-17; updated LD-1/5/7/8. Added **FR-STEM-*** (stem-based object engine, Phase 1.5) and **FR-REIMAGINE-*** (intensity control). Reframed **FR-SPAT** around BRIR-first immersion; **FR-TONAL** for minimum-phase-default + no-program-DRC + loudness-comp method; **FR-ADAPT** for ERB/Bark perceptual + masking decisions + a "processing must not be perceived as moving" criterion; **FR-NLT** as a typed multi-band macro with per-stem targeting. Added a **performance/feasibility-budget NFR** (6-stem × per-stem chain × BRIR convolution) and set the **bit-transparent bypass = Reimagine intensity 0**. Tightened privacy; updated CON/ASM/DEP, the decision matrix, journeys, and open questions.

> **v0.6 — architecture v0.3 sync (authoritative; amends the FRs/NFRs it names).** Folds in the expert-panel review ([../architecture/review-v0.2.md](../architecture/review-v0.2.md)) + founder hardware/persona/power/app-shape decisions, now canonical in architecture.md v0.3 §0/§18:
> - **Re-sum mixbus (ADR-011) — amends FR-STEM-02:** per-stem chains sum through a *managed mixbus* — per-stem makeup ≤ gain-reduction removed, loudness-matched per-stem trim to the intensity-0 reference, headroom budget pre-limiter, metered limiter GR, group-delay-aligned center.
> - **Spatial exemptions — amends FR-SPAT-01/06, FR-STEM-02/03:** bass (≲120 Hz) high-passed out of the BRIR path + summed mono; lead vocal kept centered (no L/R spread) at every intensity.
> - **Shared late-reverb / content-adaptive room — amends FR-SPAT-01/05, NFR-PERF-06:** one shared late-reverb tail + cheap per-stem early/direct filters (not 6 independent BRIRs); BRIR room amount adapts to the source's existing reverberation.
> - **Masking — amends FR-ADAPT, OQ-22:** clarity/between-stem decisions use the **excitation-pattern / masked-threshold (ERB) subset**, not full Moore-Glasberg partial loudness (~50× too slow).
> - **Stem gating — amends FR-STEM-05:** gate on a **perceptual-artifact estimate, not SDR**; confidence clamps the per-track Reimagine ceiling.
> - **Separation models — amends FR-STEM-01, DEP:** **MLX primary** (Core ML secondary); code MIT, **model weights auto-downloaded on first run** (NC-trained → not redistributed); cached stems FLAC + bounded LRU.
> - **Reimagine defaults — amends FR-REIMAGINE-03/04:** default low-to-lower-mid; dead-band above 0% (no crossfade of bit-perfect vs imperfect-phase stems); loudness-matched across the knob.
> - **NL — amends FR-NLT-02:** planned primary = on-device LLM + SAFE/SocialEQ priors (CLAP demoted to reranker; rules floor; cloud opt-in); **mechanism still deferred (OQ-11)**; interpreter output is **untrusted → schema-validated + numeric-clamped** to governing-principle + hearing-safety limits; `context` field-allowlist excludes audio, hearing data, and track identity.
> - **RT ML — amends LD-5/FR-ADAPT:** ADR-004 (BNNS-Graph RT ML) is **contingent** — no RT ML is currently needed.
> - **Tap consent — amends FR-SYS-07/08, NFR-PRIV:** the muted global tap is a **high-consent, captures-everything** capability (TCC + purple indicator; all apps incl. calls) — explicit consent UX, **auto-exclude communication apps**, tapped audio **never persisted** and never fed to stem separation.
> - **Hardware (LD-18) / power / app-shape (LD-19) / persona:** floor M1 Pro/16 GB (M4/M5 far above); foreground sole-occupancy; max-quality on AC, lighter on battery; full-window listening app + menu-bar extra; primary persona **Ramith** (developer-audiophile). Risk R-3 → Low; perf spike is tuning, not a gate.

---

## 0. Locked Decisions (as of 2026-06-13)

Founder-confirmed decisions. These supersede any conflicting requirement text below; affected requirements have been annotated. Remaining open items are in §7.

> **Phase scheme:** canonical phasing is **Phase 0** (player MVP) · **Phase 1** (mix-based core: clarity / correction / loudness-comp / adaptive / **BRIR** / NL + Reimagine mix-range) · **Phase 1.5** (stem-based object engine) · **Phase 2** (system-wide via process taps) — per architecture.md §16. Where an older FR body still tags "Phase 1" for the own-player, read it as Phase 0–1.

| # | Decision | Resolution |
|---|---|---|
| LD-1 | Scope / phasing | Own-player first (Phase 0 MVP → Phase 1 mix core → Phase 1.5 stem engine), then system-wide via **process tap** (Phase 2; virtual-device fallback). |
| LD-2 | "Immersive" | Both spatial **and** tonal/dynamic, equally weighted. |
| LD-3 | Output targets | Both headphones/AirPods and speakers; auto-detect + switch profiles. |
| LD-4 | MVP source | **Local files only** in Phase 1 (resolves OQ-06). Streaming enhancement deferred to Phase 2. |
| LD-5 | Content classifier | **Phased** (resolves OQ-09): DSP heuristics first; Core ML genre/mood model (off-RT; trained via Create ML) layered in during Phase 1. Real-time ML inference uses BNNS Graph only. |
| LD-6 | Ambient mic sensing | **On-demand sampling only** — no continuous/always-on mic. See revised FR-ADAPT-04 and Journey 2.5. |
| LD-7 | Spatial + hearing profile | **BRIR-first** (superseded by LD-14): default binaural = BRIR (HRTF + early reflections + late reverb); dry HRTF = minimal mode; SADIE II (Apache-2.0) is the anechoic HRIR core. Calibration framed strictly as a **"listening preference" tool, not a medical device** (resolves OQ-05). Custom HRTF measurement deferred. |
| LD-8 | Conversational Tuning — unified DSP action-space, governing principle, and phase | (a) **In scope at Phase 1 launch** as a supporting/discovery feature. (b) **Governing principle:** a confirmed user natural-language instruction is a governing principle that the Adaptivity Engine adapts *around*, never against. Automatic adaptation (volume, content, ambient noise) is subordinate to the user's stated intent for the targeted aspect for the remainder of the session, or until the user explicitly undoes the change. Session-scoped by default; the user must explicitly tap [Yes, keep it] to persist beyond the session (mirrors FR-NLT-06 persistence model). (c) **Unified DSP action-space:** every natural-language utterance — whether naming a frequency ("bass too low"), an instrument ("can't hear guitar"), or an aesthetic/emotional quality ("sounds boring / bland") — resolves to the same fundamental output: a **DSP action vector** comprising per-band gain changes across the frequency spectrum, plus optional dynamics (compression/transient) adjustments and spatial (width/crossfeed) moves. There is one shared action-space; phrases differ only in how directly they map onto it. (d) **Directness spectrum:** Direct (frequency words → 1:1 band gain) | Indirect (instrument names → band-region approximation of where that source dominates) | Abstract (aesthetic/emotional descriptors → combination of spectral, dynamic, and/or spatial moves). (e) **Band approximation is the baseline and is shippable at Phase 1.** ML source separation (e.g., Demucs/HTDemucs) is an optional precision enhancement for instrument-named requests, deferred to a later phase — it is NOT a prerequisite and NOT on the critical path (resolves OQ-12). (f) **Aesthetic/emotional descriptors are first-class inputs** handled by the same action-space model; see FR-NLT-12 and §3.9.1 (resolves OQ-15a via governing-principle framing). (g) **Per-stem targeting (Phase 1.5):** once the stem object engine exists, an NL macro may target a specific stem ("bring up the guitar"); at Phase 1 (mix-level), instrument requests use band approximation. (h) The interpretation mechanism remains deferred (OQ-11). |
| LD-9 | Project model | **Personal / open-source, non-commercial.** No monetization, pricing, paywall, or feature-gating of any kind. All features are free. There are no paid tiers, no entitlement checks for feature access, and no conversion-oriented analytics. The specific OSS license is **deferred to post-MVP** (post-Phase 0). This decision supersedes any conflicting text in this document and resolves OQ-02. |
| LD-10 | Quality-first / ample use of modern hardware | Maximize quality by making ample use of all modern hardware: RAM, CPU, multi-core + GPU (Metal) + Neural Engine parallelism, fast SSD (disk caching/precompute), and fast networks (optional cloud assist for non-sensitive, latency-tolerant work). Prefer platform-native, hardware-accelerated multimedia frameworks/OS features over generic code (macOS-only project): Accelerate/vDSP/BNNS, Core ML (Neural Engine), Metal/MPS, Audio Workgroups (os_workgroup) for safe real-time parallelism, AVAudioEngine/AudioToolbox built-in units, hardware-accelerated decode + AVAudioConverter SRC, and Spatial Audio / head-tracking APIs. CPU/RAM/disk are not primary constraints. Hard limits that remain: (a) the real-time per-buffer deadline (NFR-PERF-01); (b) core playback stays offline-capable — network optional, never required; (c) privacy — sensitive data (mic, hearing profile) stays on-device; (d) laptop battery/thermal (optional efficiency mode). Own-player latency is free, so look-ahead/pre-analysis, linear-phase FIR EQ, oversampling, and long convolutions are all in scope. Default to the max-quality profile. Supersedes the former fixed CPU/RAM caps — see revised NFR-PERF-02/03/04. |
| **LD-11** | Source quality & non-goals | Assume good-quality sources (lossless / high-bitrate). **Audio repair/restoration is a non-goal** (no de-noise/de-clip/upsample to "fix" bad audio). Network may be used for non-sensitive, latency-tolerant work; core playback + RT DSP stay **offline-capable**. |
| **LD-12** | Perceptual tonal model | Clarity/adaptive decisions are made in **ERB/Bark with a masking + partial-loudness model** (Moore-Glasberg style), not raw dB-on-log. Contributors are **typed** (EQ-curve + per-band dynamic + transient + spatial); the dB curve is a realization/interchange format only. |
| **LD-13** | Phase realization | **Minimum-phase by default**; phase mode chosen by content (transient density from pre-analysis); linear/mixed-phase opt-in or band-limited where it genuinely helps (pre-ringing, not latency, is the real cost). |
| **LD-14** | BRIR-first immersion | Headphone spatialization defaults to a **binaural room response** (HRTF + early reflections + late reverb); dry HRTF = minimal mode; head-tracking opt-in for music. Speakers = **M/S width + ambience extraction (mono-safe)**; crosstalk-cancellation opt-in (centered near-field only); crossfeed opt-in. |
| **LD-15** | Stem-based object engine (Phase 1.5) | Offline **6-stem** separation (vocals/drums/bass/guitar/piano/other), cached to SSD; **full per-stem chains incl. spatial placement**, re-summed to binaural; masking computed **between stems**. **Own-player-only** — the live tap path (Phase 2) is mix-level only; real-time-lite separation is a research track. |
| **LD-16** | "Reimagine" intensity knob | One continuous control: **0% = original mix, stem engine bypassed (bit-faithful, zero separation artifacts)** → clarity → spatial widening → **100% = full stem-based spatial reimagining**. Crossfades original↔stem-render + scales spatial spread / unmask depth. Mix-range in Phase 1; stem-range unlocked in Phase 1.5. |
| **LD-17** | Dynamics & loudness | **No program DRC by default** (transparent LUFS normalization + true-peak safety limiter only). Loudness compensation = **fraction of the equal-loudness contour difference** (ISO 226) + per-device SPL calibration + loudness-matched makeup, **rate-limited to volume changes only**. |
| **LD-18** | Target hardware & runtime posture | Floor = Apple-Silicon Pro-class (M1 Pro, 2021) / ≥16 GB; shipping generation far above (M4 38-TOPS NE; M4 Pro/Max 10–12 P-cores, 273–546 GB/s, 64–128 GB; M5 per-GPU-core neural accelerators ~4× M4 GPU-AI). App is foreground/sole-occupancy ("lean-back listening") and may use many cores + occupy memory generously. Large headroom on current hardware; design for the floor, exploit the abundance. Supersedes the base-8 GB-Air framing; **downgrades the stem-render risk to Low** — see revised NFR-PERF-06. **Power:** default max-quality on AC; auto-lighter (Efficiency profile) on battery, user-overridable. |
| **LD-19** | App shape | Full-window lean-back listening experience (now-playing + visualizer + Reimagine dial) **plus a menu-bar extra** for quick control; both share one app-level engine. Refines FR-UI. |

---

## 1. Stakeholders

### 1.1 Primary Stakeholders

| ID | Stakeholder | Role | Primary Need | Influence | Interest |
|----|-------------|------|--------------|-----------|----------|
| STK-01 | Audiophile Music Listener | End User | Immersive, personalized listening without manual EQ fiddling | Low | High |
| STK-02 | Casual Music Listener | End User | Better sound out-of-box on AirPods/laptop speakers with zero config | Low | High |
| STK-03 | Founder / Product Owner | Decision-maker | Technical feasibility, personal project goals, OSS community adoption | High | High |
| STK-04 | macOS Platform / Apple | Platform Constraint | App Store / notarization compliance, privacy rules, entitlement grants | High | Low |

### 1.2 Secondary Stakeholders

| ID | Stakeholder | Role | Primary Need |
|----|-------------|------|--------------|
| STK-05 | Hearing-impaired Listener | End User (accessibility) | Personalized hearing compensation profile; intelligibility improvement |
| STK-06 | Developers / Engineering Team | Implementer | Clear, testable specifications; real-time safety constraints documented |
| STK-07 | Beta / QA Testers | Validator | Reproducible acceptance criteria per requirement |
| STK-08 | Streaming Service Providers (Spotify, Apple, YouTube) | Indirect | No TOS violation from system-wide processing (Phase 2) |

### 1.3 Stakeholder Needs Summary

- STK-01 and STK-02: Sound should be noticeably better immediately after install; personalization should be opt-in and progressive, not a barrier.
- STK-03: Phase 1 (own player) must ship fast enough to validate the adaptivity engine before Phase 2 (virtual device) effort. As a personal/open-source project the goal is working software and community value, not commercial revenue.
- STK-04: All entitlements, privacy strings, and signing/notarization must be correct before any public release.
- STK-05: Hearing profile must be distinct from aesthetic preferences — hearing compensation is accessibility, not a premium feature.

---

## 2. User Journeys and Workflows

### Journey 2.1 — First-Run Onboarding

**Actor:** New user, app just launched for the first time.  
**Goal:** Reach a working listening state with a meaningful default sound profile in under 3 minutes.

```
Step 1 — Welcome Screen
  App launches → shows welcome screen with a single CTA: "Get Started"
  No login, no account wall.

Step 2 — Output Device Detection
  App enumerates available output devices via Core Audio property API.
  Auto-selects the active default output device (headphones if connected, otherwise built-in speakers).
  Displays detected device name and type (e.g., "AirPods Pro detected — Headphone mode active").
  [If no device detected → show inline error with troubleshooting link]

Step 3 — Hearing Profile Prompt
  App asks: "Would you like a quick hearing check to personalise your experience?"
  Options: [Start Hearing Check] [Skip for Now]
  If skipped → uses a neutral default profile; reminder surfaced in Settings after 3 listening sessions.

Step 4 — Microphone Permission (Environment Sensing)
  System dialog requests microphone access.
  App explains in plain language: "Used only to sense room noise — never recorded or transmitted."
  If denied → environment sensing disabled; adaptive ambient-noise feature inactive; user notified with non-blocking banner.

Step 5 — Profile Load and Playback Ready (Phase 1 — Own Player)
  App loads default DSP profile for detected device.
  Opens media browser / file importer.
  User selects a track and presses Play.
  Adaptivity engine begins processing; visual VU/analysis meter shows activity.

Step 6 — First Listening Moment
  After 10 seconds of playback, a subtle non-blocking tooltip appears:
  "Sound is adapting to your headphones and room — no action needed."
```

**Success Condition:** User is listening to music with the adaptivity engine active within 3 minutes of first launch, with no technical errors.

---

### Journey 2.2 — Hearing Profile Calibration

**Actor:** User who chose to run or re-run the hearing check.  
**Goal:** Generate a personal hearing profile that the DSP engine uses for equalisation compensation.

```
Step 1 — Pre-Check Instructions
  App displays: headphone requirement notice, estimated time (~5 minutes), quiet environment recommendation.
  Volume is automatically set to a safe calibration level (~65 dBSPL target, not app-adjustable during test).

Step 2 — Tone Playback Sequence
  App plays pure tones at discrete frequencies across both ears (500 Hz, 1 kHz, 2 kHz, 3 kHz, 4 kHz, 6 kHz, 8 kHz — minimum; extended range optional).
  User presses and holds "I can hear this" button for each tone; minimum presentation threshold derived.
  Audiogram-style result graph displayed.
  [Open Question OQ-07: Should this conform to a recognised audiological standard such as ISO 8253-1?]

Step 3 — Profile Saved
  Hearing profile stored locally (encrypted, not synced by default).
  Profile applied immediately to DSP engine.
  User can label the profile (e.g., "My AirPods", "Office Headphones") and link it to a specific output device.

Step 4 — Ongoing Prompt
  App offers to re-run calibration if output device changes to a new device category not yet profiled.
```

**Success Condition:** A stored hearing profile exists, is linked to the active output device, and measurably alters EQ curves in the DSP chain.

---

### Journey 2.3 — Normal Listening Session (Phase 1 — Own Player)

**Actor:** Returning user with a configured profile.  
**Goal:** Listen to a music playlist with seamless adaptive enhancement.

```
Step 1 — App Launch / Resume
  App opens to last state (queue, volume, playback position if paused).
  Detects currently active output device; loads matching profile automatically.

Step 2 — Track Playback
  User presses Play.
  Audio routed through DSP chain: EQ → spatialization → dynamics → output.
  Adaptivity engine begins analysis; adapts over first 2–5 seconds per track.

Step 3 — Genre / Spectral Analysis
  Content analyser runs on audio buffer (on a non-real-time thread).
  Derived spectral profile / genre classification communicated to DSP via lock-free parameter update.
  DSP gradually cross-fades to genre-appropriate tonal curve (no abrupt change).

Step 4 — Volume Adjustment
  User changes volume (system slider or in-app).
  Adaptivity engine applies Fletcher-Munson equal-loudness compensation:
    — Low volume → boosts bass and treble to preserve perceived balance.
    — High volume → reduces over-compensation to avoid over-emphasis.

Step 5 — Track Skip / Change
  New track begins; content analyser re-evaluates within 2–5 seconds.
  DSP parameters smoothed across track boundary; no audible click or abrupt shift.

Step 6 — Session End
  User pauses/closes app.
  Session state (queue, position, active profile) persisted.
```

**Success Condition:** User experiences no audible glitches across a 1-hour session; adaptive parameters visibly change between tracks of different genres in the analysis display.

---

### Journey 2.4 — Switching Output Device Mid-Session

**Actor:** User listening on AirPods who unplugs or switches to laptop speakers.  
**Goal:** Sound continues without interruption; DSP profile switches automatically.

```
Step 1 — Device Change Detected
  App registers an AudioObjectAddPropertyListenerBlock callback on
  kAudioHardwarePropertyDefaultOutputDevice.
  Callback fires on device change (runs on non-real-time thread).

Step 2 — Profile Resolution
  App looks up the profile associated with the new device.
  If a profile exists → loads it.
  If no profile exists → loads generic profile for the device category (headphones vs. speakers).

Step 3 — DSP Reconfiguration
  DSP parameters pushed to audio thread via lock-free atomic/ring-buffer mechanism.
  Old DSP state fades out, new state fades in over a configurable crossfade window (default: 200 ms).
  No audio dropout; ring buffer absorbs the gap.

Step 4 — User Notification
  Non-blocking banner: "Switched to Built-in Speakers — Speaker profile loaded."
  Banner includes shortcut: [Edit Profile].

Step 5 — Spatialization Mode Change
  AirPods → binaural HRTF / head-tracked mode active.
  Built-in speakers → crossfeed / stereo widening mode; HRTF disabled (already physical stereo).
```

**Success Condition:** Device switch results in no audio dropout longer than 50 ms and the correct profile is applied within 500 ms of the detected change.

---

### Journey 2.5 — Environment Change (Room Gets Noisy) *(revised per LD-6: on-demand)*

**Actor:** User listening in a room that has become noisier (e.g., construction starts outside).  
**Goal:** User triggers a one-shot environment sample; app adapts DSP to compensate, then releases the mic.

```
Step 1 — User Triggers Environment Sample
  The room gets noisy; the user taps "Adapt to my environment" (control strip / menu).
  App opens the mic for a short window (~3 s), computes an A-weighted SPL estimate, then releases the mic.
  No continuous monitoring; the mic is not held open between samples.
  [Open Question OQ-03: exact sample-window length and smoothing to be specified by audio engineer]

Step 2 — Noise Level Classification
  Classifies ambient level into bands: Quiet (<40 dBA), Moderate (40–65 dBA), Loud (>65 dBA).
  Hysteresis applied: must remain in new band for >3 seconds before triggering adaptation
  (avoids hunting on transient noise spikes).

Step 3 — DSP Adaptation
  Noise level change communicated to DSP thread via atomic parameter update.
  Adaptivity engine adjusts:
    — Dynamic range (reduces compression ratio in louder environments to improve clarity).
    — Low-frequency gain (slight boost to maintain bass perception over masking noise).
    — Optional: activates or deepens noise-aware loudness compensation.
  Changes applied gradually over ~1 second to avoid jarring shifts.

Step 4 — Visual Feedback
  Ambient noise indicator in status bar / control strip updates (e.g., icon changes from green to amber).
  Tooltip on hover: "Loud environment detected — audio adapted."

Step 5 — Noise Decreases
  Same hysteresis logic applies to returning to quieter state.
  DSP parameters return to prior state gradually.

Step 6 — Mic Permission Denied Fallback
  If mic access unavailable, ambient noise adaptation is skipped entirely.
  All other adaptation paths (volume, device, content) remain active.
```

**Success Condition:** In a controlled test, raising ambient noise by 25 dBA causes measurable DSP parameter change (verifiable in engineering debug view) within 5 seconds, with no audio artifacts during the transition.

---

### Journey 2.6 — Phase 2: Enabling System-Wide Enhancement

**Actor:** User who wants to enable the Phase 2 system-wide enhancement (free, no paywall — LD-9).  
**Goal:** All system audio (Spotify, Apple Music, YouTube, etc.) routed through the DSP engine.

> **Architecture note (prior-art ADR-002, Proposed — see `docs/architecture/prior-art.md`):** The primary mechanism for macOS 14.2/14.4+ is a **Core Audio process tap** (no driver, no admin password, no coreaudiod restart). The AudioServerPlugIn virtual device (FALLBACK PATH) is used when the tap path is unavailable (macOS < 14.2) or when the user specifically wants a persistent, selectable output device. Both paths are described below; the app selects the primary path automatically.

```
─── PRIMARY PATH: Core Audio Process Tap (macOS 14.2+) ─────────────────────────

Step 1 — Permission Request (TCC consent only)
  App detects macOS 14.2+ (or 14.4+ — verify minimum in AudioHardwareTapping.h headers;
  see CON-10 / OQ-07).
  App presents a plain-language explanation:
    "To enhance all apps, Adaptive Sound needs permission to capture audio output.
     You'll see a one-time macOS permission dialog. No admin password needed."
  User acknowledges with [Enable System Enhancement] or [Not Now].
  macOS presents the standard audio-capture TCC consent dialog
  (NSAudioCaptureUsageDescription; purple mic-like indicator while tap is active).

Step 2 — Tap Activation (no install, no restart)
  App creates a CATapDescription for global output, creates an AudioHardwareTap,
  and constructs a private aggregate device that reads the tap and mutes the original
  output device. All audio now flows: [any app] → tap capture → DSP engine → physical
  output device.
  No HAL plug-in installed. No coreaudiod restart. No audio interruption.

Step 3 — Physical Output Selection
  App confirms or lets the user select the physical output device for processed audio
  (defaults to the current system default output).

Step 4 — Verification
  App plays a brief internal test tone through the chain.
  User confirms they can hear it; setup wizard closes.
  App enters menu-bar mode (always-on background processing).
  Purple audio-capture indicator visible in menu bar while tap is active.

Step 5 — Disable / Revoke
  User navigates to Settings → System Enhancement → Disable, or revokes audio-capture
  permission in System Settings → Privacy & Security → Microphone (or equivalent).
  App stops the tap; original output device is unmuted automatically.
  No residual audio routing or installed files left behind.

─── FALLBACK PATH: AudioServerPlugIn Virtual Device (macOS < 14.2 or user preference) ──

Step 1 — Pre-Install Notice (driver path)
  App presents a plain-language explanation:
    "To enhance all apps on this macOS version, we install a virtual audio device.
     This requires your administrator password and briefly interrupts system audio (~2 s)."
  User acknowledges with [Install System Enhancer] or [Not Now].

Step 2 — Privileged Installer
  A signed, notarised privileged helper (SMAppService / ServiceManagement framework)
  is invoked.
  Helper copies the AudioServerPlugIn bundle to /Library/Audio/Plug-Ins/HAL/.
  Helper restarts coreaudiod.
  Audio interruption is expected; app shows a "Restarting audio system…" overlay.

Step 3 — Virtual Device Activation
  coreaudiod loads the new plug-in.
  App detects the virtual device appears in the device list.
  App instructs the user (or does so automatically with permission) to set the virtual
  device as the macOS System Output in System Settings → Sound.
  [Open Question OQ-01: auto-switch vs. manual selection — see §7.]

Step 4 — Physical Output Selection
  Within the app, user selects the real physical output device.
  App configures the DSP engine to read from the virtual device and write to the
  selected physical device.

Step 5 — Verification (same as tap path Step 4 above)

Step 6 — Uninstall Path
  User navigates to Settings → System Enhancer → Remove.
  Privileged helper removes the plug-in bundle, restarts coreaudiod.
  System Output automatically reverts to built-in speakers (or previous device).
  No residual audio routing left behind.
```

**Success Condition:** After Phase 2 setup (either path), music from Spotify sounds measurably different (enhancement active vs. disabled) with no additional audio latency perceptible to the user (< 10 ms round-trip added, per NFR-PERF-05). On the tap path, no admin password was required and no files were installed.

---

### Journey 2.7 — Giving Natural-Language Feedback Mid-Listen (Conversational Tuning)

**Actor:** Returning user actively listening to music.  
**Goal:** Adjust the sound by typing what they hear in plain language, without touching EQ controls.

```
Step 1 — Opening the Conversational Tuning Input
  User notices the sound feels off (e.g., bass is too weak).
  User clicks the "Tell us what you hear" button in the Now Playing view
  (or activates via keyboard shortcut).
  A compact text field slides in below the Now Playing view.
  Placeholder text reads: "e.g. 'bass is too low' or 'voices are hard to hear'"

Step 2 — Entering Feedback
  User types: "bass is too low"
  No submit button required; user presses Return or clicks "Apply".
  The app accepts the raw text and passes it to the Conversational Tuning
  subsystem for intent derivation.
  A subtle processing indicator appears (spinner or pulsing waveform icon)
  while intent is being derived — target: < 1 500 ms.

Step 3 — Intent Derived, Change Applied
  The subsystem determines intent: raise low-frequency gain (60–250 Hz), moderate
  magnitude, positive direction.
  Change is communicated to the DSP thread via the existing lock-free parameter
  path (FR-ADAPT-02 / FR-ADAPT-03); gain ramps smoothly (≥ 50 ms, per FR-ADAPT-03).
  The text field clears; a confirmation card appears:
    "Boosted bass (60–250 Hz) +3 dB  — does that feel better?
     [Yes, keep it]  [Undo]  [Adjust more]"

Step 4 — User Confirms or Reverts
  Path A — User taps [Yes, keep it]:
    The change is stored as a user preference (tagged to current profile + device).
    Confirmation card dismisses after 2 s.
  Path B — User taps [Undo]:
    DSP parameters revert to pre-feedback values via the same smooth ramp.
    Card dismisses; text field is offered again in case user wants to re-try.
  Path C — User taps [Adjust more]:
    Text field re-opens pre-filled with the previous input; user can refine.

Step 5 — Ambiguity / Low-Confidence Path (branching from Step 3)
  If the intent derivation cannot reach a high-confidence mapping
  (e.g., "the sound is a bit weird"):
    No DSP change is made.
    The app replies with a clarifying question displayed in the card:
      "Could you describe what you mean? For example:
       'too much bass', 'too bright', 'voices are muffled', 'sounds too harsh'"
    User answers the clarifying question; loop returns to Step 3.
  Maximum clarification rounds: 2; if still unresolved, the app replies:
    "I'm not sure how to adjust that — try the EQ panel for manual control."
    and offers a deep-link to the EQ panel (FR-TONAL-01).

Step 6 — Urgent / Protective Path ("it hurts my ear")
  User types: "bass is too much, it hurts my ear"
  The subsystem detects a discomfort / pain signal.
  Immediate DSP action before confirmation card:
    — Bass (60–250 Hz) is reduced by a protective floor cut (target: −6 dB minimum).
    — True-peak limiter threshold tightened (FR-TONAL-07).
  A distinct, higher-urgency card appears:
    "Reduced bass immediately for your comfort.
     Consider also lowering your volume.  [Undo]  [Keep it]"
  This change is always applied; it is NOT held pending confidence threshold.

Step 7 — Instrument / Source Requests (e.g., "I can't hear the guitar")
  The subsystem recognises a source/instrument name — an "indirect" phrase on the
  unified DSP action-space directness spectrum (LD-8, OQ-12 resolved).
  Phase 1 handling (baseline — fully shippable):
    Derive a DSP action vector targeting the band region where the named source dominates.
    For guitar: boost the guitar body/presence region (250 Hz–4 kHz).
    Surface a note in the confirmation card:
      "Boosted guitar presence region (250 Hz–4 kHz) — better?
       Note: this affects the full mix in that range, not guitar alone."
  Optional future enhancement (later phase — not on critical path):
    ML source separation (e.g., Demucs/HTDemucs) may increase per-instrument
    isolation precision, but band approximation remains the production baseline.

Step 8 — Transparency: What Changed and Why
  After any confirmed change, the Transparency view (FR-ADAPT-07) adds a new row:
    "Natural-language feedback | 'bass is too low' | +3 dB at 60–250 Hz | [Undo]"
  This row persists in the session history so the user can review all text-driven
  changes made during the session.

Step 9 — Session End / Preference Persistence
  At session end, confirmed text-driven changes are written to the active profile
  as a signed preference delta (frequency bands + magnitude).
  Changes tagged as "one-off" (user did not tap [Yes, keep it]) are discarded.
  On next launch with the same profile + device, the persisted delta is silently
  re-applied on top of the baseline profile.
```

**Success Condition:** A user who types "bass is too low" hears a measurable bass boost within 2 seconds and can confirm or undo it with a single tap; the confirmed change persists to the next session. A user who types "it hurts my ear" receives an immediate protective bass reduction without needing to confirm first.

---

## 3. Functional Requirements

Requirements are grouped by capability area. Each requirement carries a stable ID, a description, and 1–3 Given/When/Then acceptance criteria.

**Priority Notation:** P1 = Must Have (MVP), P2 = Should Have (v1.1), P3 = Nice to Have (backlog)

---

### 3.1 Playback and Source (FR-PLAY)

**FR-PLAY-01** — Local File Playback (P1)  
The app shall play local audio files in common formats (MP3, AAC, FLAC, ALAC, WAV, AIFF, OGG) routed through the DSP engine.

> Given a local audio file in a supported format is added to the queue,  
> When the user presses Play,  
> Then audio begins within 500 ms and is routed through the full DSP chain with no audible artifacts.

**FR-PLAY-02** — Playback Controls (P1)  
The app shall provide standard playback controls: play, pause, skip forward, skip backward, seek, and volume adjustment.

> Given audio is playing,  
> When the user activates any playback control,  
> Then the corresponding action is executed within 100 ms of user input with no audio glitch.

**FR-PLAY-03** — Queue Management (P1)  
The app shall support a playback queue with drag-to-reorder, remove, and repeat/shuffle modes.

> Given a queue of at least 5 tracks,  
> When the user reorders a track via drag-and-drop,  
> Then the queue reflects the new order immediately and the next track plays in the updated order.

**FR-PLAY-04** — Metadata Display (P1)  
The app shall display track title, artist, album, album art, and duration for local files using embedded metadata (ID3, Vorbis Comment, MP4 atom).

> Given a file with complete ID3v2 tags is playing,  
> When the Now Playing screen is visible,  
> Then all available metadata fields are populated correctly.

**FR-PLAY-05** — Session State Persistence (P1)  
The app shall restore the last queue, playback position (if paused), and active profile on next launch.

> Given the app is closed while paused at position 2:34 in a track,  
> When the app is relaunched,  
> Then the queue is restored, the track is pre-loaded at 2:34, and the same profile is active.

**FR-PLAY-06** — Supported Format Extensibility (P2)  
The app should detect and surface unsupported file formats with a clear error rather than silently failing.

> Given a file in an unsupported format is dragged into the app,  
> When the import is attempted,  
> Then an inline error message names the format and links to the list of supported formats.

---

### 3.2 Spatialization (FR-SPAT)

**FR-SPAT-01** — BRIR Binaural Rendering for Headphones (P1) *(revised per LD-14: BRIR-first)*  
When a headphone output is detected, the app shall apply **binaural room-response (BRIR) rendering** — a SOFA HRIR convolved with **early reflections + late reverberation that carry interaural differences** — to produce an externalised, out-of-head soundstage. Dry (anechoic) HRTF is the **minimal mode**, not the default, because dry HRTF alone reliably collapses in-head with non-individualised data. Implemented as our own partitioned convolution using **libmysofa** (BSD-3) + **vDSP / FFTConvolver** (MIT); anechoic HRIR core = **SADIE II (Apache-2.0)**; the room layer is synthesised (image-source + FDN) or a CC0/CC-BY BRIR. Headphone-correction EQ (FR-TONAL-02) corrects **timbre only** and is not relied on for externalisation. Apple PHASE/AVAudioEnvironmentNode/AUSpatialMixer are **not** used (fixed, non-replaceable HRTFs).

> Given a stereo track is playing and a headphone device is active,  
> When HRTF mode is enabled (default for headphones),  
> Then the audio output includes externalised binaural cues produced by the BRIR convolution engine such that a naive listener ABX test shows audible spatial difference (and improved externalisation vs. the dry-HRTF minimal mode) at a statistically significant rate.

**FR-SPAT-02** — HRTF Profile Selection (P2)  
The app shall provide at least 3 selectable HRTF profiles drawn from the SOFA dataset library (e.g., SADIE II subjects offering generic, small-head, and large-head approximations) and indicate which is recommended given the user's hearing calibration data. Profile selection loads a different SOFA HRIR set; it does not switch to a platform-provided spatialization API.

> Given the hearing calibration is complete,  
> When the HRTF profile selector is opened,  
> Then the app highlights a recommended profile based on measured ear characteristics and the active HRTF (loaded from the SOFA dataset) renders immediately on selection without requiring restart.

**FR-SPAT-03** — Crossfeed for Headphones (P3, opt-in / off by default) *(revised per LD-14)*  
The app shall offer adjustable crossfeed to reduce unnatural extreme stereo panning on headphones. Crossfeed is **opt-in and off by default** — it is largely subsumed by the BRIR path (a BRIR is a physically-correct crossfeed-plus-room). The Bauer-style algorithm is reimplemented in-house pending the libbs2b license check (OQ-17).

> Given a stereo track with hard-panned elements is playing on headphones,  
> When crossfeed is enabled at the default level (Bauer stereophonic-to-binaural, ~700 Hz crossover),  
> Then channel separation is measurably reduced (verifiable via FFT analysis) without perceived image collapse.

**FR-SPAT-04** — Head-Tracked Soundstage via AirPods Motion (P2, opt-in) *(revised per LD-14)*  
When AirPods (3rd gen or later, AirPods Pro 1/2, AirPods Max) are the active output **and the user opts in**, the app shall use **CMHeadphoneMotionManager** (macOS 14+) head-tracking to stabilise the soundstage relative to a fixed world reference. Head-tracking is **off by default for music** (many listeners prefer a head-locked music stage); its externalisation benefit is largely already delivered by the BRIR path.

> Given AirPods Pro are active, head-tracking is enabled, and the user rotates their head 30 degrees,  
> When head-tracking data is received (via CoreMotion / AirPods motion API),  
> Then the soundstage rotation counter-compensates such that the perceived source direction does not move with the head, with lag < 20 ms.

**FR-SPAT-05** — Virtual Room / BRIR Layer (P1) *(promoted per LD-14 — the room component of FR-SPAT-01)*  
The app shall provide the room layer (early reflections + late reverberation carrying interaural difference) that, combined with the SADIE-II HRIR, forms the BRIR of FR-SPAT-01. At least one default "treated listening room" plus alternates (e.g., studio, living room, hall) shall be selectable. The room may be synthesised (image-source + FDN) or loaded from CC0/CC-BY BRIR/IR data.

> Given a room IR is selected from the library,  
> When convolution is enabled,  
> Then the output contains reverb characteristics consistent with that IR (measurable RT60), and CPU usage remains within the NFR-PERF-01 budget.

**FR-SPAT-06** — Speaker Immersion: M/S Width + Ambience (P1) *(revised per LD-14)*  
When a speaker output is detected, BRIR/HRTF rendering shall be disabled and a **mid-side width + ambience-extraction** mode shall activate, with a **hard mono-compatibility constraint** (the M channel is preserved). Crosstalk-cancellation/transaural is an **opt-in "centered near-field" mode** only (stereo-dipole narrow span); aggressive XTC shall not be applied blindly on laptop speakers.

> Given the active output device is identified as speakers (not headphones),  
> When a stereo track plays,  
> Then HRTF is inactive, stereo width processing is applied, and the mid/side balance is adjustable by the user.

**FR-SPAT-07** — Spatial Mode Auto-Detection and Override (P1)  
The app shall automatically choose spatial processing mode based on device type but allow the user to manually override.

> Given the active device switches from headphones to speakers,  
> When the device change event fires,  
> Then spatialization mode updates automatically within 500 ms and a banner confirms the change; the user may override via the controls panel.

---

### 3.3 Tonal and Dynamic Optimization (FR-TONAL)

**FR-TONAL-01** — Parametric EQ Engine (P1) *(revised per LD-12/LD-13)*  
The app shall provide a parametric EQ (≥10 bands; adjustable frequency, gain ±20 dB, Q). The canonical tonal target is a composable curve realized **off-RT** as **minimum-phase biquads by default**; **linear/mixed-phase FIR is opt-in or selected by content** (transient-dense material stays minimum-phase to avoid pre-ringing — LD-13). The RT kernel runs finished coefficients only (no design/fitting on the audio thread).

> Given the user sets band 3 to 200 Hz, +6 dB, Q=1.0,  
> When audio plays,  
> Then FFT analysis of the output shows a +6 dB peak centred at 200 Hz within ±0.5 dB tolerance.

**FR-TONAL-02** — Headphone/Speaker Frequency Response Correction (P1)  
The app shall apply a device-specific correction EQ curve that compensates for the measured frequency response deviation of common headphone and speaker models from a target diffuse-field or free-field response.

> Given the active device is identified as "Apple AirPods Pro 2" from the device correction library,  
> When correction EQ is enabled,  
> Then the device correction profile is loaded and applied, and the user can toggle it on/off with an audible difference.

**FR-TONAL-03** — Loudness-Compensated EQ (P1) *(revised per LD-17)*  
The app shall apply loudness compensation as a **fraction of the equal-loudness contour difference** (ISO 226) between an assumed program reference level and the actual playback level — **not** a raw single-contour boost. It requires a **per-device SPL calibration** (the app cannot know absolute SPL otherwise), applies **loudness-matched makeup gain**, is **rate-limited to volume changes** (never program dynamics), caps low-frequency boost, and is defeatable.

> Given a track is playing, equal-loudness compensation is enabled, and the user reduces volume by 20 dB,  
> When the volume change is detected,  
> Then bass (80–200 Hz) gain increases by approximately 6–10 dB (per ISO 226 curves) and high-frequency (8–12 kHz) gain increases by approximately 3–5 dB, applied within one DSP processing block.

**FR-TONAL-04** — Psychoacoustic Bass Enhancement (P1)  
The app shall apply harmonic excitation to bass frequencies to enhance perceived bass weight on small speakers and headphones that cannot reproduce low fundamentals. Bass harmonics shall be generated from a **mono-summed (L+R) low band** — per-channel (stereo) harmonic generation is explicitly prohibited to avoid infringement of Waves patent US-11,102,577 (active, ~2038; see CON-11 and OQ-16). The implementation shall target the expired MaxxBass approach (US-5,930,373, ~2019 — verify on USPTO before shipping) or a clean-room nonlinear-distortion (NLD) design from the mono low band. Formal IP review is required before any public release (OQ-16).

> Given the active output is built-in MacBook speakers and a bass-heavy track is playing,  
> When psychoacoustic bass enhancement is enabled,  
> Then harmonic partials of sub-bass frequencies (below 80 Hz) are generated from the mono-summed low band and are audible, without physical speaker over-excursion (no distortion artefacts perceptible on casual listen).

> Given the implementation under review,  
> When the harmonic generation path is inspected,  
> Then bass harmonics are derived from a mono (L+R) low-band signal, not from per-channel stereo signals independently.

**FR-TONAL-05** — Dynamics Policy: No Program DRC by Default (P1) *(revised per LD-17)*  
For good-quality sources aimed at fidelity, the app shall **not** apply program dynamic-range compression by default. The default dynamics chain is **transparent LUFS normalization + the true-peak safety limiter (FR-TONAL-07)** only. Any dynamics adaptation (e.g., raising intelligibility in a loud ambient environment) is **opt-in and conservative**, and shall **prefer dynamic EQ over broadband multiband compression**.

> Given a classical track (high dynamic range) is playing and ambient noise is Quiet,  
> When the adaptivity engine classifies the content,  
> Then compression ratio is set conservatively (< 1.5:1) to preserve dynamics; switching to a loud ambient condition increases the ratio (target ≥ 3:1) to improve intelligibility.

**FR-TONAL-06** — Tonal Preset Library (P2)  
The app shall include a preset library with at least 8 named tonal presets (e.g., Neutral, Warm, Bright, Bass Boost, Podcast, Film, Classical, Electronic) that the user can apply, modify, and save.

> Given a preset named "Electronic" is selected,  
> When applied,  
> Then EQ parameters change to preset values within one render cycle, and a "Save as Custom" button appears if the user subsequently adjusts any parameter.

**FR-TONAL-07** — True Peak Limiting (P1)  
A transparent true-peak limiter shall be the final DSP stage, preventing output from exceeding -1 dBTP regardless of upstream gain.

> Given upstream DSP adds +6 dB gain to a 0 dBFS signal,  
> When the limiter is in the chain,  
> Then the output true peak is ≤ -1 dBTP (verified by a reference meter).

---

### 3.4 Adaptivity Engine (FR-ADAPT)

> **ML path constraint (prior-art finding, ADR-004 Proposed — see `docs/architecture/prior-art.md`):** Any ML inference that occurs **inside the real-time render callback** (on the audio thread) shall use **BNNS Graph** exclusively — it is RT-safe (no runtime allocation, single-threaded, no locks). **Core ML, SoundAnalysis, and Metal/MPS** are off-RT only: they may be used freely for pre-analysis, background classification, and model training, but never inside the render block. This applies to FR-ADAPT-01 (content/genre classification), LD-5 (Core ML genre model), and any future on-device ML inference. This constraint refines but does not replace LD-5.

> **Perceptual-domain decisions (LD-12) & imperceptible adaptation:** Adaptive and clarity decisions (masking relief, content/loudness/ambient moves) shall be computed in the **ERB/Bark domain against a masking + partial-loudness model** (Moore-Glasberg style), not raw dB-on-log. Adaptation shall be **conservative and imperceptible-as-motion**: coalesced updates, slow ramps (≥50 ms, FR-ADAPT-03), hysteresis/deadbands, and no move that fights intentional musical contrast. **Acceptance:** in listening tests, users shall **not** be able to identify that "the EQ is moving" — only a net improvement (a Phase-0 KPI gate; see architecture.md §10).

**FR-ADAPT-01** — Content / Genre Classification (P1)  
The app shall analyse the spectral and rhythmic characteristics of the currently playing audio on a non-real-time thread and derive a content classification (minimum: speech, classical, electronic/bass-heavy, acoustic/folk, rock/metal, other).

> Given a track with dominant bass frequencies and a 4/4 electronic drum pattern plays for 5 seconds,  
> When the content analyser completes its window,  
> Then the classification resolves to "Electronic" and the adaptivity engine's genre-tuned curve is applied.

**FR-ADAPT-02** — Real-Time Parameter Update (Lock-Free) (P1)  
All parameter changes from the adaptivity engine to the DSP audio thread shall be communicated exclusively via lock-free mechanisms (std::atomic parameters or a single-producer, single-consumer ring buffer). No mutex or blocking call shall occur on the audio thread.

> Given the adaptivity engine updates 5 EQ parameters simultaneously,  
> When the audio thread reads these parameters during the next render callback,  
> Then no lock contention or priority inversion occurs; verifiable by running the app under Instruments Thread State Trace with no audio thread preemptions attributed to lock acquisition.

**FR-ADAPT-03** — Parameter Smoothing / Ramp (P1)  
All DSP parameter changes pushed by the adaptivity engine shall be applied via per-sample or per-block linear ramp (minimum: 50 ms ramp time) to prevent audible zipper noise or discontinuities.

> Given an EQ band gain changes from 0 dB to +6 dB in a single update,  
> When the audio thread processes this change,  
> Then the gain transitions smoothly over ≥ 50 ms; no click or zipper artifact is audible on a sine wave test signal.

**FR-ADAPT-04** — Ambient Noise Sensing — On-Demand (P1) *(revised per LD-6: on-demand, not continuous)*  
The app shall sample the microphone **only when the user triggers "Adapt to my environment"**, capturing a short window (~3 s) to estimate ambient SPL and classify it into at least 3 bands (Quiet/Moderate/Loud). The mic shall not be held open between samples — no always-on listening, no persistent macOS mic indicator during normal playback.

> Given the user taps "Adapt to my environment" while in a noisy room (>65 dBA),  
> When the ~3 s sample completes,  
> Then ambient is classified as "Loud", the corresponding DSP adaptation is applied, and the mic is released (orange indicator clears) within 1 s of sample completion.

> Given the user has not triggered an environment sample,  
> When audio is playing normally,  
> Then the microphone is not accessed and no mic-in-use indicator is shown.

**FR-ADAPT-05** — Volume-Level Tracking (P1)  
The app shall monitor the current playback volume level continuously and compute the target equal-loudness compensation curve at each volume change.

> Given volume changes from 50% to 30%,  
> When the volume change is detected,  
> Then compensation EQ parameters update within 100 ms without audio dropout.

**FR-ADAPT-06** — Personal Hearing Profile Integration (P1)  
The adaptivity engine shall incorporate the user's stored hearing profile to apply personalised gain correction per frequency band as a component of the overall EQ computation.

> Given a hearing profile indicates a 15 dB threshold elevation at 4 kHz in the right ear,  
> When the profile is active and a track plays,  
> Then the DSP chain adds compensating gain at 4 kHz (right channel) in proportion to the measured deficit, without the user needing to adjust anything manually.

**FR-ADAPT-07** — Adaptation Transparency Mode (P2)  
The app shall provide a "Transparency" debug/analysis view showing a real-time visualisation of which signals are driving which DSP changes (e.g., "Volume → +4 dB bass", "Ambient: Loud → Ratio 3:1").

> Given the adaptivity engine is active,  
> When the user opens the Transparency view,  
> Then each active adaptation signal is listed with its current value and resulting DSP adjustment, updating at ≥ 2 Hz.

**FR-ADAPT-08** — Adaptation Intensity Control (P2)  
The app shall provide a master "Adaptation Strength" slider (0–100%) that scales the magnitude of all adaptive DSP changes while leaving the baseline profile intact.

> Given Adaptation Strength is set to 0%,  
> When content, volume, and ambient noise all change,  
> Then DSP parameters do not change from the baseline profile values (verified in Transparency view).

---

### 3.5 Device and Profile Management (FR-DEVICE)

**FR-DEVICE-01** — Output Device Enumeration (P1)  
The app shall enumerate all available Core Audio output devices on launch and on device change, displaying device name, type (headphones/speakers/external DAC), and sample rate.

> Given two output devices are connected (AirPods and USB DAC),  
> When the device list is opened,  
> Then both devices appear with their correct names and type icons.

**FR-DEVICE-02** — Auto-Profile Switching on Device Change (P1)  
On any default output device change, the app shall automatically load the DSP profile associated with that device (or a generic profile for device type if no specific profile exists) within 500 ms.

> Given profile "AirPods Pro" is saved and the user connects AirPods Pro while built-in speakers are active,  
> When macOS sets AirPods Pro as the new default output,  
> Then the app loads "AirPods Pro" profile within 500 ms and plays without dropout.

**FR-DEVICE-03** — Device Type Classification (P1)  
The app shall classify connected output devices as one of: in-ear headphones, over-ear headphones, built-in speakers, external speakers, DAC/amplifier, unknown. Classification shall use device name heuristics and Core Audio transport type.

> Given an AirPods Pro device is connected,  
> When the device is classified,  
> Then it is identified as "in-ear headphones" and the HRTF + headphone correction pipeline is automatically selected.

**FR-DEVICE-04** — Named Profile Creation and Editing (P1)  
Users shall be able to create named DSP profiles, associate them with a specific output device, and edit all profile parameters.

> Given the user creates a profile named "Night Mode — AirPods" with custom EQ,  
> When AirPods are connected,  
> Then the app offers to auto-load "Night Mode — AirPods" (if it is the primary profile for that device) and the user can switch profiles manually from the device menu.

**FR-DEVICE-05** — Profile Import and Export (P2)  
The app shall support exporting and importing profiles as JSON files to allow sharing between users and backup.

> Given a profile is exported to a .json file,  
> When the file is imported on a different Mac running the app,  
> Then all profile parameters are correctly restored and audible.

**FR-DEVICE-06** — Sample Rate Negotiation (P1)  
The app shall query the preferred sample rate of the active output device and configure the DSP chain to match, performing sample-rate conversion if the source material differs.

> Given the output device's preferred rate is 48 kHz and a 44.1 kHz file plays,  
> When the DSP chain initialises,  
> Then sample-rate conversion is applied transparently and audio plays at the correct pitch and duration.

---

### 3.6 Personalization and Hearing Profile (FR-HEAR)

**FR-HEAR-01** — Guided Hearing Calibration (P1)  
The app shall include a guided hearing test that measures the user's hearing thresholds at a minimum of 7 audiometric frequencies (500 Hz, 1 kHz, 2 kHz, 3 kHz, 4 kHz, 6 kHz, 8 kHz) per ear.

> Given the user starts the hearing test with headphones,  
> When each tone is presented and the user responds,  
> Then thresholds are recorded per ear per frequency and stored in a structured hearing profile.

**FR-HEAR-02** — Hearing Profile Privacy (P1)  
Hearing profile data shall be stored exclusively on-device in an encrypted local database. It shall never be transmitted to any remote server without explicit, separately confirmed user consent.

> Given a hearing profile is saved,  
> When network traffic is inspected during the session (e.g., via Charles Proxy),  
> Then no hearing profile data appears in any outbound request.

**FR-HEAR-03** — Multiple Profile Support (P2)  
The app shall support storing and switching between multiple hearing profiles (e.g., for different family members sharing a Mac) linked to different output devices or user accounts.

> Given two hearing profiles exist ("Alice" and "Bob"),  
> When "Bob" is selected as the active profile,  
> Then the DSP hearing compensation curve changes to match Bob's thresholds and the UI confirms "Bob's profile active."

**FR-HEAR-04** — Hearing Profile Age / Retest Prompt (P2)  
The app shall prompt users to rerun hearing calibration if the existing profile is older than 12 months (configurable), given that hearing can change over time.

> Given a hearing profile was created 366 days ago,  
> When the app launches,  
> Then a non-blocking prompt appears suggesting recalibration, which the user can dismiss or act on.

**FR-HEAR-05** — Safe Volume Guard (P1)  
The app shall enforce a maximum safe output level during hearing calibration (target: equivalent to 65 dBSPL at 1 kHz on reference headphones) regardless of system volume setting.

> Given the system volume is set to 100%,  
> When the hearing test is active,  
> Then the app overrides the test tone level to a safe limit and cannot be bypassed by the user during the test.

---

### 3.7 UI and Controls (FR-UI)

**FR-UI-01** — Now Playing View (P1)  
The app shall display a persistent Now Playing view showing album art, track metadata, playback controls, a real-time spectrum analyser, and the active profile name.

> Given a track is playing,  
> When the Now Playing view is open,  
> Then the spectrum analyser updates at ≥ 30 fps and all metadata is visible without scrolling on a 13-inch MacBook display.

**FR-UI-02** — DSP Controls Panel (P1)  
A DSP controls panel shall expose EQ bands, spatialization toggle, dynamics controls, and profile selector in a single view without requiring navigation into settings.

> Given the DSP controls panel is open,  
> When the user adjusts any EQ band,  
> Then the change is audible in the next audio render cycle (< 23 ms at 512 frames / 44.1 kHz) and the EQ curve visualisation updates immediately.

**FR-UI-03** — Menu Bar / Status Bar Item (P2, required P1 for Phase 2)  
The app shall optionally run as a menu-bar app (no Dock icon) in Phase 2, showing current profile and quick access to on/off toggle.

> Given the app is in menu-bar mode,  
> When the user clicks the menu bar icon,  
> Then a popover shows: active profile, current device, enhancement on/off toggle, and an "Open Full App" link.

**FR-UI-04** — Onboarding Flow (P1)  
A first-run onboarding wizard shall complete in no more than 5 steps, be skippable at any step, and not gate the user from listening while completing it.

> Given it is the app's first launch,  
> When the user skips all onboarding steps,  
> Then they reach the main player view within 10 seconds with default settings active.

**FR-UI-05** — Accessibility — VoiceOver (P1)  
All interactive controls shall have meaningful VoiceOver labels and be operable via keyboard alone. The spectrum analyser shall have an accessible text equivalent (e.g., "Spectrum: Bass heavy, moderate highs").

> Given VoiceOver is enabled,  
> When the user navigates through the DSP controls panel with arrow keys,  
> Then every slider and button announces its label and current value.

**FR-UI-06** — Dark Mode Support (P1)  
The app shall fully support macOS Dark Mode and Light Mode, switching automatically with system preference.

> Given the system switches to Dark Mode while the app is open,  
> When the appearance changes,  
> Then all app windows update to the dark theme without requiring a restart, with no illegible text or invisible controls.

**FR-UI-07** — Adaptive UI Feedback (P2)  
The UI shall provide subtle, non-intrusive visual feedback whenever the adaptivity engine changes a DSP parameter (e.g., a brief indicator pulse on the affected control).

> Given the adaptivity engine updates the bass EQ by 3 dB,  
> When the DSP controls panel is visible,  
> Then the bass band indicator briefly animates to signal the change, without disrupting user interaction.

---

### 3.8 Phase 2 — System-Wide Enhancement (FR-SYS)

> **Architecture note:** Requirements FR-SYS-07 and FR-SYS-08 cover the **PRIMARY PATH** (Core Audio process tap, macOS 14.2+/14.4+, no driver). Requirements FR-SYS-01 through FR-SYS-06 cover the **FALLBACK PATH** (AudioServerPlugIn virtual device, for macOS < 14.2 or where a persistent selectable output device is required). The app shall use the tap path by default when the OS version permits; the driver path is only invoked when the tap path is unavailable or explicitly chosen. See `docs/architecture/prior-art.md` (ADR-002, Proposed) and Journey 2.6.

---

#### PRIMARY PATH — Core Audio Process Tap (macOS 14.2+)

**FR-SYS-07** — Process-Tap System Audio Capture (P1 for Phase 2, primary path)  
On macOS 14.2 or later (exact floor to be confirmed in `<CoreAudio/AudioHardwareTapping.h>` — see CON-10 / OQ-07), the app shall capture all system audio output via a `CATapDescription` + `AudioHardwareCreateProcessTap` (or equivalent SDK entry point) combined with a private aggregate device that mutes the original output. The captured audio shall be processed through the DSP engine and replayed to the physical output device. No HAL plug-in shall be installed, no privileged helper shall be used, and coreaudiod shall not be restarted.

> Given the user is on macOS 14.2+ and grants audio-capture TCC permission (NSAudioCaptureUsageDescription),  
> When the tap is activated,  
> Then audio from any playing application is captured, processed through the DSP chain, and played on the physical output device; no admin password was required and no files were installed in /Library.

> Given the process tap is active,  
> When the companion app is quit or the user revokes audio-capture permission,  
> Then the tap is stopped and the original output device is unmuted automatically; audio returns to normal within 500 ms with no residual routing or installed artefacts.

**FR-SYS-08** — TCC Audio-Capture Permission (P1 for Phase 2, primary path)  
The app shall declare `NSAudioCaptureUsageDescription` in its Info.plist with a plain-language explanation of purpose. The purple audio-capture indicator shall be visible to the user whenever the tap is active. The app shall handle TCC denial gracefully by falling back to the driver path (if available) or displaying a clear explanation of the limitation.

> Given the user denies the audio-capture TCC permission,  
> When the app attempts to activate the tap path,  
> Then the tap is not created; the app informs the user, offers to use the driver-based fallback path if the OS supports it, and does not crash or enter an inconsistent state.

---

#### FALLBACK PATH — AudioServerPlugIn Virtual Device (macOS < 14.2 or user preference)

> The following requirements FR-SYS-01 through FR-SYS-06 apply to the **driver fallback path only**. They remain valid requirements for that path and are not deleted; they are reframed here to make the architecture hierarchy clear.

**FR-SYS-01** — AudioServerPlugIn Virtual Device (P1 for Phase 2, fallback path)  
When the process-tap primary path is unavailable (macOS < 14.2 or tap denied), the app shall ship a signed, notarised AudioServerPlugIn that appears as a selectable output device in macOS System Settings → Sound. The virtual device shall accept PCM audio from any app and pass it to the DSP engine.

> Given the AudioServerPlugIn is installed (fallback path),  
> When the user selects it as the system output in System Settings,  
> Then audio from any playing application is routed through the DSP chain and heard on the physical output device.

**FR-SYS-02** — Privileged Installer with Minimal Footprint (P1 for Phase 2, fallback path)  
Installation of the HAL plug-in shall use a signed privileged helper via ServiceManagement (SMAppService). The helper shall do no more than: copy the bundle to /Library/Audio/Plug-Ins/HAL/ and restart coreaudiod.

> Given the user initiates installation (fallback path),  
> When the privileged helper runs,  
> Then only the plug-in bundle is written to the HAL directory and coreaudiod is restarted; no other system files are modified (verifiable by fs_usage).

**FR-SYS-03** — Safe Uninstall and Fallback (P1 for Phase 2, fallback path)  
The app shall provide a one-click uninstall that removes the HAL plug-in, restarts coreaudiod, and restores system output to built-in speakers (or previous device). No manual system repair shall be required.

> Given the Phase 2 driver enhancer is installed and active (fallback path),  
> When the user clicks Uninstall,  
> Then the plug-in is removed, coreaudiod restarts, and the system output is set to built-in speakers within 10 seconds, leaving no orphaned audio devices in the system.

**FR-SYS-04** — Crash-Safe Audio Passthrough (P1 for Phase 2, fallback path)  
If the companion app crashes or is force-quit while the virtual device is active, the virtual device shall silently pass audio through unprocessed (bypass mode) rather than causing a system audio outage.

> Given the companion app is killed via Activity Monitor while Spotify plays through the virtual device (fallback path),  
> When the app process terminates,  
> Then Spotify audio continues to play (unprocessed) within 200 ms; no system-level audio dropout occurs.

**FR-SYS-05** — IPC Between Plug-In and Companion App (P1 for Phase 2, fallback path)  
Parameter updates from the companion app to the AudioServerPlugIn shall use Mach IPC (registered under the AudioServerPlugIn_MachServices Info.plist key). No other IPC mechanism (file, socket, memory-mapped file) shall be used on the hot audio path.

> Given the companion app changes the active EQ profile (fallback path),  
> When the message is sent via the Mach port,  
> Then the plug-in receives and applies the update within the next audio render cycle.

**FR-SYS-06** — Zero Objective-C in Plug-In (P1 for Phase 2, fallback path)  
The AudioServerPlugIn bundle shall be implemented in pure C/C++ with no Objective-C runtime calls, in compliance with AudioServerPlugIn sandbox restrictions.

> Given the plug-in bundle is compiled (fallback path),  
> When inspected with otool -L,  
> Then no libobjc or Foundation dependency is linked.

---

### 3.9 Conversational Tuning — Natural-Language Sound Feedback (FR-NLT)

> **Scope note:** The Conversational Tuning subsystem accepts free-text input from the user, derives an audio adjustment intent from that text, and applies the adjustment via the existing lock-free/smoothed DSP parameter path (FR-ADAPT-02, FR-ADAPT-03). How text is interpreted (rule engine, on-device model, cloud LLM, or a hybrid) is explicitly **deferred** — see OQ-11. All requirements below are specified at the behavioral level: input → intended outcome.

---

**FR-NLT-01** — Free-Text Feedback Input (P1)  
The app shall provide a dedicated text input control, accessible from the Now Playing view (and via a keyboard shortcut), through which the user can type a natural-language description of what they are hearing. The control shall accept Unicode text up to 280 characters and impose no structured form or category selection.

> Given a track is playing,  
> When the user activates the Conversational Tuning input (click or keyboard shortcut),  
> Then a text field appears, is focused automatically, and accepts free-form typed input without requiring the user to select a category or frequency band.

> Given the user has typed feedback and presses Return (or clicks Apply),  
> When the input is submitted,  
> Then the raw text is passed to the intent-derivation subsystem within 100 ms of submission, and a processing indicator is visible to the user.

---

**FR-NLT-02** — Intent Derivation: DSP Action Vector Output (P1)  
The intent-derivation subsystem shall parse submitted text and produce a **typed multi-band macro** as its output: `{ eq_bands[], dynamics?, transient?, spatial?, target_stem?, confidence }` — (a) per-band gain deltas (direction + magnitude from language intensity markers), (b) optional dynamics, (c) optional transient, (d) optional spatial (width/crossfeed/placement), (e) an optional **target stem** (Phase 1.5; e.g., "the guitar"), and (f) a confidence score. Every phrase type — frequency-referencing, instrument-naming, or aesthetic/emotional — maps to this same macro; they differ only in directness (LD-8, §3.9.1). Mappings shall be seeded from descriptor priors (SAFE-DB / SocialEQ-style) and be **per-user-adaptable** (cross-user agreement on terms like "warm" is low). If an embedding/LLM back-end is used, descriptor→effect **monotonicity shall be validated** before shipping (some embeddings invert "warm"). The `context` passed to the interpreter shall **exclude** audio buffers and hearing-profile data (privacy). The mechanism that converts text → macro is deferred (OQ-11).

> Given the user submits "bass is too low",  
> When intent derivation completes,  
> Then the output DSP action vector specifies: per-band gain delta = increase, target bands = 60–250 Hz, magnitude = moderate; and this vector is forwarded to the DSP parameter update path (FR-ADAPT-02/FR-ADAPT-03).

> Given the user submits "the sound is slightly too bright",  
> When intent derivation completes,  
> Then the output DSP action vector specifies: per-band gain delta = decrease, target bands = 6–12 kHz, magnitude = subtle (the word "slightly" is a low-intensity qualifier); no dynamics or spatial components are included in the vector.

> Given the user submits "the music sounds boring",  
> When intent derivation completes,  
> Then the output DSP action vector includes a combination of moves: presence boost (2–5 kHz), air shelf boost (10–15 kHz), transient/dynamics enhancement, and optionally a stereo width increase — all resolved through the same action-space, not through a separate structural pathway.

---

**FR-NLT-03** — DSP Change via Existing Lock-Free Path (P1)  
All DSP parameter changes resulting from Conversational Tuning shall be applied exclusively through the lock-free parameter update mechanism defined in FR-ADAPT-02 and smoothed per FR-ADAPT-03. No new cross-thread synchronisation primitive shall be introduced for this feature.

> Given the intent-derivation subsystem produces a parameter update (e.g., low-frequency gain +3 dB),  
> When the update is forwarded to the DSP engine,  
> Then it is delivered via the existing lock-free ring buffer / atomic path and ramped over ≥ 50 ms — no mutex or blocking call occurs on the audio thread, verifiable by Thread State Trace in Instruments.

---

**FR-NLT-04** — Confirmation Feedback and Conversational Reply (P1)  
After a DSP change is applied from a natural-language input, the app shall display a non-blocking confirmation card stating (a) what was changed in plain language, (b) the approximate DSP action taken — summarising **all components** when the change spans multiple bands, dynamics, or spatial moves (e.g., an abstract phrase such as "sounds boring") — and (c) two primary actions — confirm or undo. The card shall auto-dismiss after 8 seconds if neither action is taken (treating the user's inaction as implicit acceptance without persisting the change).

> Given the user submits "bass is too low" and intent is derived at high confidence,  
> When the DSP change is applied,  
> Then a confirmation card appears within 1 500 ms of submission reading, for example: "Boosted bass (60–250 Hz) — does that feel better?" with [Yes, keep it] and [Undo] actions visible.

> Given the confirmation card is displayed and the user takes no action for 8 seconds,  
> When the card auto-dismisses,  
> Then the DSP change remains active but is NOT written to the persistent profile preference delta.

> Given the user submits an abstract phrase such as "music sounds boring" and a multi-component action vector is derived,  
> When the confirmation card appears,  
> Then it summarises the combined change in plain language (e.g., "Added presence, air, and a bit more punch — better?") rather than naming a single band.

---

**FR-NLT-05** — One-Tap Undo / Revert (P1)  
The user shall be able to revert any Conversational Tuning DSP change with a single tap/click of an Undo action, available both on the confirmation card immediately after application and in the session history list in the Transparency view (FR-ADAPT-07). Reverting shall restore the exact pre-feedback DSP parameter values via a smooth ramp (≥ 50 ms, per FR-ADAPT-03).

> Given a Conversational Tuning change has been applied (bass +3 dB),  
> When the user taps [Undo] on the confirmation card,  
> Then DSP parameters return to their pre-feedback values over ≥ 50 ms; no audible click occurs, and the confirmation card is replaced by a "Change undone" notice that dismisses after 3 seconds.

> Given the confirmation card has already dismissed,  
> When the user opens the Transparency view and taps [Undo] next to the NLT history row,  
> Then the same revert behaviour is triggered; the history row is removed from the session log.

---

**FR-NLT-06** — Preference Persistence vs. One-Off Change (P1)  
A Conversational Tuning change shall be persisted to the active DSP profile only when the user explicitly confirms it (taps [Yes, keep it]). Changes that auto-dismiss or are undone shall not be written to the profile. Persisted changes shall be stored as a signed delta on the baseline profile (not as a new stand-alone profile) and shall survive app restart, applying silently on next load of the same profile and output device.

> Given the user taps [Yes, keep it] on the confirmation card for a bass boost,  
> When the app restarts and the same profile and device are active,  
> Then the bass boost delta is silently re-applied on top of the baseline profile without prompting the user.

> Given the user does not tap [Yes, keep it] (card auto-dismisses),  
> When the app restarts,  
> Then no residual DSP delta from that interaction is applied.

---

**FR-NLT-07** — Transparency: Show What Changed and Why (P1)  
Every confirmed Conversational Tuning DSP change shall be recorded as a row in the Transparency view (FR-ADAPT-07) with the original text input, the derived DSP action (plain-language + technical notation, listing **all components** for multi-band/dynamics/spatial action vectors), the timestamp, and an Undo link. This session log shall persist within a session and be clearable by the user.

> Given a Conversational Tuning change has been confirmed,  
> When the user opens the Transparency view,  
> Then a row appears showing, for example: "NLT | 'bass is too low' | +3 dB at 60–250 Hz | 14:32 | [Undo]".

> Given a confirmed change came from an abstract phrase ("sounds boring") that produced a multi-component vector,  
> When the user opens the Transparency view,  
> Then the row lists every component, for example: "NLT | 'sounds boring' | +3 dB presence (2–5 kHz), +2 dB air (12 kHz), +transient punch, +width | 14:35 | [Undo]".

> Given the user taps "Clear session log",  
> When confirmed,  
> Then all NLT history rows are removed from the Transparency view; the DSP changes already applied to the profile are not affected.

---

**FR-NLT-08** — Ambiguity Handling: Clarifying Question (P1)  
When the intent-derivation subsystem cannot produce a high-confidence structured intent from the submitted text, it shall NOT apply any DSP change. Instead, it shall display a clarifying question to the user suggesting more specific phrasing examples. The clarifying dialogue shall support a maximum of two rounds; if intent remains unresolvable after two rounds, the app shall acknowledge the limitation and offer a deep-link to the manual EQ panel.

> Given the user submits "the sound is a bit weird",  
> When intent derivation cannot reach a high-confidence mapping,  
> Then no DSP change is applied, and the app displays: "Could you describe what you mean? For example: 'too much bass', 'too bright', 'voices are muffled', 'sounds too harsh', or 'sounds dull / boring'."

> Given two clarifying rounds have completed and intent remains unresolved,  
> When the second clarification fails,  
> Then the app displays "I'm not sure how to adjust that — try the EQ panel for manual control" and presents a tappable link to the DSP Controls Panel (FR-UI-02).

---

**FR-NLT-09** — Urgent Protective Reduction ("it hurts") (P1)  
When submitted text contains signals of immediate auditory discomfort or pain (e.g., "it hurts", "hurts my ear", "too painful", "damaging"), the app shall apply an immediate protective DSP reduction — without waiting for confirmation — and present a distinct high-urgency card. The protective action shall: (a) reduce the frequency region associated with the discomfort by a minimum of −6 dB, and (b) tighten the true-peak limiter threshold. This path bypasses the normal confidence-check gate and applies immediately.

> Given the user submits any phrase containing a discomfort or pain signal (e.g., "bass is too much, it hurts my ear"),  
> When the text is submitted,  
> Then within 500 ms the associated frequency region is reduced by ≥ −6 dB and the true-peak limiter is tightened, before any confirmation card is rendered.

> Given the protective reduction has been applied,  
> When the high-urgency card appears,  
> Then it displays a distinct visual treatment (e.g., amber/warning colour), states what was reduced, recommends the user also lower volume, and offers [Undo] and [Keep it] — with [Keep it] as the default focus.

---

**FR-NLT-10** — Instrument / Source Requests: Indirect Mapping via Band-Region Approximation (P1)  
Instrument and vocal-source requests (e.g., "guitar", "voices", "drums", "vocals") are an **indirect** point on the shared DSP action-space directness spectrum (see LD-8): the source name identifies the frequency region where that instrument or source typically dominates, and the intent-derivation subsystem outputs a DSP action vector targeting that band region. This band-region approximation is the **baseline behaviour and is fully shippable at Phase 1 launch** — it is not a degraded fallback. The confirmation card shall surface a plain-language note that the full mix in that band is being adjusted, not the isolated instrument. ML source separation (e.g., Demucs/HTDemucs) is an optional precision enhancement that may increase per-instrument isolation accuracy in a later phase but is NOT a prerequisite for this requirement — see LD-8(e) and OQ-12 (resolved).

> Given the user submits "I can't hear the guitar clearly",  
> When intent is derived,  
> Then the DSP action vector targets the guitar-dominant band region (250 Hz–4 kHz) with a moderate positive gain delta, and the confirmation card reads: "Boosted guitar presence region (250 Hz–4 kHz) — better? Note: this affects the full mix in that range, not guitar alone."

> Given the user submits "I can't hear voices",  
> When intent is derived,  
> Then the DSP action vector targets the vocal intelligibility / presence band (2–4 kHz) with a moderate positive gain delta, and the confirmation card notes: "Raised vocal clarity (2–4 kHz) — does that help?"

---

**FR-NLT-11** — VoiceOver and Keyboard Accessibility (P1)  
The Conversational Tuning text field, confirmation card, and all actions ([Yes, keep it], [Undo], [Adjust more], clarifying question responses) shall be fully operable via VoiceOver and keyboard alone, consistent with FR-UI-05 and NFR-ACC-01/02.

> Given VoiceOver is enabled and the Conversational Tuning input is active,  
> When the user navigates to the confirmation card via keyboard,  
> Then VoiceOver announces: the plain-language description of what changed, and all available actions with their keyboard shortcuts.

---

**FR-NLT-12** — Abstract / Aesthetic Descriptors as First-Class Inputs (P1)  
Abstract and aesthetic/emotional descriptors (e.g., "boring", "bland", "lifeless", "dull", "muffled", "warm", "punchy", "wide", "muddy", "boomy", "thin", "harsh", "sibilant") shall be treated as **first-class inputs** to the Conversational Tuning subsystem. They are not a special or lower-priority category: they resolve through the same unified DSP action-space as frequency-referencing and instrument-naming phrases (per LD-8), producing a DSP action vector that may include a *combination* of per-band gain changes, dynamics adjustments (compression ratio, transient enhancement), and spatial moves (stereo width, crossfeed). The interpretation mechanism is not specified here — see OQ-11. The confirmation card shall describe the resulting combination of moves in plain language so the user understands what changed.

> Given the user submits "the music sounds boring" (or "bland" or "lifeless"),  
> When intent derivation completes,  
> Then the DSP action vector includes at minimum: a presence boost (2–5 kHz), an air shelf boost (10–15 kHz), and a transient/dynamics enhancement; optional stereo width increase may be included; the confirmation card reads, for example: "Added presence, air, and punch — does that help?" with [Yes, keep it] and [Undo] actions.

> Given the user submits "sounds dull" or "sounds muffled" or "sounds veiled",  
> When intent derivation completes,  
> Then the DSP action vector includes a treble shelf boost (above 6 kHz) and often a low-mid cut (250–500 Hz); the confirmation card describes both moves in plain language.

> Given the user submits "make it wider" or "sounds like it's stuck in my head" or "more spacious",  
> When intent derivation completes,  
> Then the DSP action vector includes a spatial move (stereo width increase and/or crossfeed adjustment) as its primary component, communicated to the DSP engine via FR-ADAPT-02/FR-ADAPT-03; the confirmation card confirms the spatial change applied.

> Given a confirmed abstract/aesthetic change has been applied,  
> When the user opens the Transparency view (FR-ADAPT-07),  
> Then a row appears showing the original phrase, all DSP components of the action vector applied (plain-language + technical notation), and an Undo link — consistent with FR-NLT-07.

---

#### 3.9.1 Phrase → Interpreted Intent → DSP Action Mapping Table

The table below documents how representative natural-language phrases map to audio intent and DSP action. This table is normative for test case design and intent-derivation validation. The interpretation mechanism that produces this mapping is not specified here (see OQ-11). Frequency band definitions follow the audio grounding established by the product team.

**Unified action-space model (LD-8):** Every phrase — regardless of whether it references a frequency, an instrument, or an aesthetic/emotional quality — resolves to the same output: a **DSP action vector** over the shared parameter space (per-band gain deltas + optional dynamics + optional spatial). The columns below reflect this: "DSP Action" always describes a combination of moves within that single space. Phrases differ only in directness of mapping: Direct (frequency words → 1:1 band gain) | Indirect (instrument names → band-region approximation) | Abstract (aesthetic/emotional → combination of moves). There is no structurally different processing pathway for any category.

| Phrase (example) | Directness | Audio Aspect Identified | Direction | Magnitude Hint | Target Frequency Band(s) / Dynamics / Spatial | DSP Action (action vector components) | Notes / Edge Cases |
|---|---|---|---|---|---|---|---|
| "bass is too low" | Direct | Low-frequency level | Increase | Moderate | 60–250 Hz (bass / warmth) | Per-band gain: +boost 60–250 Hz | Sub-bass (20–60 Hz) may also be lifted slightly if device can reproduce it |
| "bass is too much, it hurts my ear" | Direct | Low-frequency level + discomfort signal | Decrease (urgent) | Strong (protective) | 60–250 Hz | Per-band gain: ≥ −6 dB cut 60–250 Hz; dynamics: true-peak limiter tightened | Triggers FR-NLT-09 urgent path; discomfort keywords override confidence gate |
| "I can't hear voices" / "vocals too quiet" | Indirect | Vocal intelligibility | Increase | Moderate | 2–4 kHz (vocal presence / intelligibility); optional 500 Hz–2 kHz (vocal body) | Per-band gain: +boost 2–4 kHz; optional +boost 500 Hz–2 kHz | Source approximation — affects full mix; note surfaced per FR-NLT-10 |
| "I think the guitar sound is not audible clearly" | Indirect | Guitar presence | Increase | Moderate | 250 Hz–2 kHz (body) + 2–4 kHz (attack/presence) | Per-band gain: +boost across guitar-dominant range | Source approximation — full mix affected; note surfaced per FR-NLT-10 |
| "too harsh" / "it's painful in the high mids" | Direct | Harshness / ear fatigue | Decrease | Moderate–Strong | 3–5 kHz (harshness / fatigue) | Per-band gain: −cut 3–5 kHz; if "painful" present, also dynamics: limiter tightened | "Painful" is a discomfort signal regardless of magnitude qualifier; triggers FR-NLT-09 |
| "too muddy" / "sounds muddy" | Direct/Abstract | Low-mid mud | Decrease | Moderate | 250–500 Hz (low-mid mud) | Per-band gain: −cut 250–500 Hz | Often co-occurs with a request to clarify bass — present change transparently |
| "too sharp" / "too sibilant" / "too much hiss" | Direct | Sibilance / high-frequency harshness | Decrease | Moderate | 6–8 kHz (sibilance / de-ess zone) | Per-band gain: −cut 6–8 kHz | May also partially address 4–6 kHz if "sharp" is used broadly |
| "music sounds flat / distant" | Abstract | Presence / air | Increase | Moderate | 2–4 kHz (presence) + 6–12 kHz (air / sparkle) | Per-band gain: +lift presence and air bands | "Flat" may also indicate a spatial issue — transparency card should suggest checking spatialization mode |
| "too boomy" / "too much low end" | Direct | Sub-bass / bass excess | Decrease | Moderate | 20–60 Hz (sub-bass) + 60–250 Hz (bass) | Per-band gain: −cut broadly across low end | Distinguish from "muddy" (250–500 Hz); if user also says "it hurts", trigger FR-NLT-09 |
| "a little more warmth" / "slightly warmer" | Abstract | Low-frequency warmth | Increase | Subtle | 100–300 Hz (warmth); optional gentle high-frequency cut | Per-band gain: +gentle boost 100–300 Hz (≤ +2 dB for subtle qualifier); optional −slight high cut | Magnitude hint = subtle; scale ramp down for low-intensity qualifiers |
| "I can't hear the drums clearly" | Indirect | Drum attack / transients | Increase | Moderate | 60–100 Hz (kick body) + 2–5 kHz (snare attack) | Per-band gain: +boost low-frequency body; +boost presence for snare attack | Multi-band approximation; note surfaced per FR-NLT-10 |
| "boring" / "bland" / "lifeless" / "flat" (when not spatial) | Abstract | Lack of excitement / engagement | Increase (excite) | Moderate | 2–5 kHz (presence) + 10–15 kHz (air, high shelf); dynamics: transient/punch; optional spatial: +stereo width | Per-band gain: +presence 2–5 kHz, +air shelf 10–15 kHz; dynamics: transient enhancement / subtle compression punch; optional spatial: +stereo width | Multi-component action vector. "Flat" used spatially → see "distant" row above. Confirm card describes all components. Optional subtle harmonic excitation. |
| "dull" / "muffled" / "veiled" | Abstract | Treble deficit + low-mid excess | Increase treble / Decrease low-mid | Moderate | Above 6 kHz (treble shelf); often also 250–500 Hz (low-mid cut) | Per-band gain: +treble shelf >6 kHz; often −low-mid 250–500 Hz | Distinguish from "muffled" (primarily low-mid) vs. "dull" (primarily treble deficit) — both map to same vector components but relative magnitudes may differ |
| "boomy" / "too much bass weight" | Abstract/Direct | Bass excess | Decrease | Moderate | 80–200 Hz (boomy sub-bass) | Per-band gain: −cut 80–200 Hz | Narrower than "too much low end" — boomy typically centres 80–200 Hz vs. broader sub-bass |
| "boxy" | Abstract | Upper-bass / low-mid resonance | Decrease | Moderate | 400–600 Hz (boxy resonance zone) | Per-band gain: −cut 400–600 Hz | Narrow Q cut often more effective than broad shelf |
| "honky" / "nasal" | Abstract | Upper-mid resonance | Decrease | Moderate | 1–2 kHz (nasal/honky zone) | Per-band gain: −cut 1–2 kHz | Often a room or headphone resonance artifact; narrow Q |
| "thin" / "tinny" | Abstract | Low-frequency deficit | Increase | Moderate | 80–250 Hz (bass / low-mid body); often also −upper-mid | Per-band gain: +boost 80–250 Hz; optional −slight upper-mid cut | "Tinny" on small speakers may also benefit from psychoacoustic bass enhancement (FR-TONAL-04) |
| "punchy" / "more punch" | Abstract | Transient impact + bass body | Increase | Moderate | 60–120 Hz (kick / punch body); dynamics: transient enhancement | Per-band gain: +bass 60–120 Hz; dynamics: transient enhancement (attack sharpening) | Primarily a dynamics move with bass support; confirm card names both components |
| "wide" / "spacious" / "sounds too narrow" / "in my head" | Abstract | Spatial impression | Increase width | Moderate | Spatial: stereo width / crossfeed reduction | Spatial: +stereo width and/or −crossfeed (headphones) or +mid-side width (speakers) | Primarily a spatial action vector component; minimal or no per-band EQ unless combined with tonal descriptor |
| "can't hear voices" / "vocal intelligibility" | Indirect | Vocal presence + consonant clarity | Increase | Moderate | 2–4 kHz (presence / intelligibility); 4–6 kHz (consonant clarity) | Per-band gain: +boost 2–4 kHz; optional +4–6 kHz consonant range | Same target as "can't hear voices" above; listed separately to document 4–6 kHz consonant component |

---

### 3.10 Reimagine Intensity Control (FR-REIMAGINE)

The single user-facing control that scales *how much we transform* the sound (LD-16).

**FR-REIMAGINE-01** — Single Intensity Control (P1)  
The app shall expose one continuous "Reimagine" intensity control (0–100%) that scales the overall degree of transformation: 0% faithful → rising clarity → spatial widening → (Phase 1.5) full stem-based spatial reimagining.

> Given the Reimagine control is at any value,
> When the user changes it,
> Then the render transitions smoothly (no clicks/zipper; ramped per FR-ADAPT-03) toward the new intensity.

**FR-REIMAGINE-02** — Intensity 0 = Bit-Faithful Bypass (P1)  
At 0%, the stem engine and all transformation stages shall be bypassed and the original mix played unaltered — bit-transparent (see NFR-QUAL bit-transparent bypass).

> Given Reimagine = 0% at the device's native sample rate,
> When a loopback capture is compared to the source file,
> Then the captured audio is bit-identical to the source (MD5-equal).

**FR-REIMAGINE-03** — Continuous Mapping, Phased Ceiling (P1)  
The intensity→parameter mapping shall crossfade original↔processed and scale spatial spread / unmask depth along the way. **Phase 1** implements the mix-level range; **Phase 1.5** raises the ceiling into the stem-based spatial range. The exact mapping curve is an open item (OQ — user-tested).

> Given Phase 1 (no stem engine yet),
> When the user raises intensity to maximum,
> Then only the mix-level range is reachable (clarity + BRIR widening); stem-range behaviour is unavailable until Phase 1.5.

**FR-REIMAGINE-04** — Artifact-Conservative Defaults (P1)  
Default intensity and behaviour shall be artifact-conservative; higher intensities (which expose separation artifacts) shall be opt-in territory the user chooses by dialing up. Quality-gating (FR-STEM-05) informs how high the stem-range is allowed to go for a given track.

---

### 3.11 Stem-Based Object Engine — Phase 1.5 (FR-STEM)

Own-player-only (LD-15). Live/system-wide audio (Phase 2 tap) is mix-level only.

**FR-STEM-01** — Offline 6-Stem Separation + Cache (P1 for Phase 1.5)  
On add/first-play, the app shall separate a local track offline into **6 stems** (vocals, drums, bass, guitar, piano, other) using an on-device model (Demucs/HTDemucs via Core ML/MLX, MIT) and cache the stems to SSD. Separation is non-real-time and must not block playback.

> Given a local track is added,
> When offline separation runs (GPU/ANE),
> Then 6 stem files are produced and cached, and a status indicator reflects progress; playback of the original mix is available immediately regardless.

**FR-STEM-02** — Per-Stem Chains + Re-Sum (P1 for Phase 1.5)  
Each stem shall be processable with its own gain, EQ, dynamics, and **spatial placement** (rendered via the BRIR field, FR-SPAT-01), then re-summed to binaural/stereo.

> Given cached stems and Reimagine in the stem range,
> When playback runs,
> Then each stem is rendered with its own placement/level and the re-summed output reflects the per-stem moves without glitches (Audio-Workgroups-parallel render, NFR-PERF).

**FR-STEM-03** — Between-Stem Unmasking (P1 for Phase 1.5)  
Masking/clarity shall be computed **between stems** (ERB/Bark, LD-12) so that a masked source (e.g., vocals under guitar) can be genuinely unmasked — not approximated by mix EQ.

> Given vocals are masked by other stems in a region,
> When unmasking is active,
> Then the vocal stem is raised / competing stems dipped in the masked ERB bands, measurably improving vocal prominence.

**FR-STEM-04** — Per-Stem Natural-Language Targeting (P1 for Phase 1.5)  
NL macros (FR-NLT) shall be able to target a specific stem ("bring up the guitar", "move the vocals forward").

> Given the user says "bring up the guitar",
> When intent is derived with the stem engine active,
> Then the guitar stem's level/placement is adjusted (governing principle, LD-8), confirmed in the transparency view.

**FR-STEM-05** — Quality-Gating + Graceful Fallback (P1 for Phase 1.5)  
6-stem separation (esp. guitar/piano) is the least-robust case. The app shall **quality-gate** separated stems and gracefully fall back (fewer stems; route poorly-separated content to "other") rather than expose bad stems. Confidence shall bound how far the stem-range / per-stem moves are allowed for that track.

> Given a track separates poorly for guitar/piano,
> When quality-gating evaluates the stems,
> Then those stems are merged into "other" (or the track is limited to fewer usable stems) and the achievable Reimagine ceiling is reduced accordingly, with no audibly broken stem presented.

**FR-STEM-06** — Own-Player-Only Boundary (P1 for Phase 1.5)  
Stem features require local files + offline pre-separation and shall be available only in the own player; the Phase-2 system-wide tap path applies mix-level processing only.

> Given audio arriving via the Phase-2 process tap (live),
> When the user requests a stem-level action,
> Then the app indicates stem features are own-player-only and applies the nearest mix-level equivalent instead.

---

## 4. Non-Functional Requirements

### 4.1 Performance (NFR-PERF)

**NFR-PERF-01** — Audio Thread Latency Budget (P1)  
Total processing time per render callback on the audio thread shall not exceed 50% of the buffer period at the nominal buffer size (e.g., ≤ 5.8 ms for a 512-frame buffer at 44.1 kHz). Measured by Instruments / CAMetricEngine under normal adaptive load.

> Given a 512-frame buffer at 44.1 kHz (11.6 ms period) with all DSP modules active,  
> When audio plays for 60 continuous minutes,  
> Then average audio thread CPU usage is ≤ 50% of the period and no buffer under-runs occur (no XRuns reported by coreaudiod).

**NFR-PERF-02** — Compute Usage: Quality-First (P1) *(revised per LD-10)*  
Compute is not a primary constraint — spend available compute on quality, and prefer hardware-accelerated, platform-native paths: Accelerate (vDSP/vForce/BNNS), Core ML on the Neural Engine, Metal/MPS on the GPU, and multi-core parallelism (including macOS **Audio Workgroups** for any real-time helper threads). There is no fixed CPU-percentage cap. Hard limits: (a) the real-time per-buffer deadline (NFR-PERF-01) is never missed; (b) sustained load stays within reasonable battery/thermal bounds, for which an optional efficiency profile may reduce quality.

> Given all DSP active at the max-quality profile on Apple Silicon,  
> When audio plays continuously,  
> Then there are zero audio-thread overruns (NFR-PERF-01 holds), regardless of average CPU/GPU/ANE utilisation.

**NFR-PERF-03** — Memory & Storage: Quality-First (P1) *(revised per LD-10)*  
RAM and SSD are not primary constraints — use memory and disk generously for quality: cached full-track pre-analysis, decoded look-ahead buffers, impulse responses, FFT plans, lookup tables, and precomputed filters (cached to fast SSD across sessions). There is no fixed resident-memory cap. Two rules still hold: (a) all real-time buffers are pre-allocated at session start; (b) **no heap allocation occurs on the audio thread** (CON-01).

> Given all DSP and full-track pre-analysis are active,  
> When memory is inspected via Instruments Allocations,  
> Then zero allocations occur in the render callback; resident/disk-cache size is bounded by cache policy, not a fixed cap.

**NFR-PERF-04** — Content Analysis: Parallel Look-Ahead Pre-Analysis (P1) *(revised per LD-10)*  
Content/genre and signal analysis runs off the real-time thread, may be parallelised across cores / GPU / Neural Engine, and in the own-player may pre-scan ahead of the playhead (up to the full track), caching results to RAM/SSD. No CPU-percentage cap applies to this non-RT work. A usable classification shall be available no later than 5 s into playback, and ideally before playback from pre-analysis.

> Given a new track starts (or is pre-scanned before playback),  
> When analysis completes,  
> Then a content classification is available to the adaptivity engine at or before 5 s of playback, without affecting the real-time render deadline.

**NFR-PERF-05** — End-to-End Added Latency (Phase 2) (P1)  
In Phase 2 virtual device mode, the total additional round-trip latency introduced by the DSP pipeline (reading from virtual device, processing, writing to physical device) shall be ≤ 10 ms.

> Given music plays via the virtual device chain with a 256-frame hardware buffer,  
> When measured with a loopback cable and impulse-response latency test,  
> Then added latency is ≤ 10 ms.

**NFR-PERF-06** — Stem-Engine Render Budget (P1 for Phase 1.5) *(new per LD-15 / architecture.md §15)*  
The Phase-1.5 stem render (up to **6 stems × per-stem EQ/dynamics/spatial + BRIR convolution**, re-summed) shall hold the per-buffer deadline (NFR-PERF-01) on the **M1 Pro / 16 GB floor** (LD-18; foreground sole-occupancy — current M4/M5 hardware has ~3–4× headroom, so this is now **Low-risk**) by: doing all heavy work off-RT (separation, FIR/BRIR design, masking — pre-computed/cached); running fixed partitioned convolutions parallelised via **Audio Workgroups**; **sharing one late-reverb tail across stems** (cheap per-stem placement filters); and the QualityProfile auto-scaling **stem count / reverb-tail length** (not buffer size) under thermal/battery pressure. Cached-stem + BRIR-kernel memory shall be bounded by a cache policy.

> Given 6 cached stems at the max-quality profile on a base Apple-Silicon laptop,
> When all stems render with per-stem chains + BRIR convolution for 60 continuous minutes,
> Then zero audio-thread overruns occur (NFR-PERF-01 holds); if the budget cannot be met, the QualityProfile reduces stem count / convolution length before any overrun. *(A pre-Phase-1.5 spike must measure real per-stem cost + memory — backlog SPIKE-PERF-BUDGET.)*

---

### 4.2 Audio Quality (NFR-QUAL)

**NFR-QUAL-01** — THD+N (P1)  
Total harmonic distortion plus noise in bypass mode (no DSP processing) shall be ≤ -90 dB (0.003%) at 1 kHz, 0 dBFS.

**NFR-QUAL-02** — No Glitch Policy (P1)  
Zero audible glitches (clicks, pops, dropouts > 1 ms) during any continuous 1-hour playback session on supported hardware, at default buffer sizes.

> Given 60 minutes of continuous playback on a MacBook Pro M3 with all Phase 1 DSP active,  
> When the session ends,  
> Then the XRun count reported by the app's internal monitor is 0.

**NFR-QUAL-03** — Bit-Transparent Bypass = Reimagine Intensity 0 (P1) *(revised per LD-16)*  
At **Reimagine intensity 0%** (and in any explicit bypass), the stem engine and all DSP stages shall be bypassed and the output shall be bit-for-bit identical to the input (after any required format conversion) — no unintentional dithering, gain, or processing. This is the architecture's fidelity anchor (FR-REIMAGINE-02).

> Given a 24-bit FLAC file plays in bypass mode at the device's native sample rate,  
> When a loopback capture is compared to the source file,  
> Then the captured audio is bit-identical to the source (verified by MD5 comparison).

**NFR-QUAL-04** — Sample Rate Support (P1)  
The DSP engine shall support sample rates of 44.1 kHz, 48 kHz, 88.2 kHz, and 96 kHz without quality degradation. Sample-rate conversion, when required, shall use a high-quality algorithm (SSRC class or equivalent, stopband attenuation ≥ 90 dB).

---

### 4.3 Privacy (NFR-PRIV)

**NFR-PRIV-01** — Microphone Data Locality (P1)  
Microphone data shall be processed entirely on-device. No raw microphone audio frames shall ever leave the device. Only the derived ambient SPL estimate (a scalar) is used internally. This shall be documented in the Privacy Policy and App Store privacy nutrition label.

**NFR-PRIV-02** — Microphone Permission Transparency (P1)  
The app shall present a clear, user-readable NSMicrophoneUsageDescription string before requesting microphone access. Denial shall not prevent any core feature except ambient-noise-based adaptation.

> Given the user denies microphone permission,  
> When the app continues to run,  
> Then all features except ambient-noise adaptation function normally and the user is informed via a persistent but dismissable banner.

**NFR-PRIV-03** — Hearing Profile Data (P1)  
Hearing profile data shall be stored in an encrypted local database (AES-256 or platform Keychain/Data Protection). It shall not be backed up to iCloud by default (set NSURLIsExcludedFromBackupKey). Remote transmission requires explicit opt-in consent with a separate dialog.

**NFR-PRIV-04** — Telemetry and Analytics (P2)  
If the app collects any usage telemetry, it shall be strictly opt-in, clearly described at onboarding, and limited to anonymous quality and diagnostics data (e.g., crash-free rate, audio-engine error counts). It shall exclude any audio content, hearing data, or personal identifiers. There is no conversion-oriented or commercial analytics purpose — this is a personal/open-source project (LD-9). Users shall be able to review and delete their telemetry data. An open-source project may choose to omit telemetry entirely; this requirement applies only if telemetry is implemented.

> Given the user opts out of telemetry,  
> When network traffic is monitored,  
> Then no analytics events are sent after opt-out.

**NFR-PRIV-05** — App Sandbox Compliance (P1)  
The companion app (not the HAL plug-in) shall be sandboxed per App Store requirements. Any entitlements required (e.g., com.apple.security.device.microphone) shall be declared and justified in the app's entitlements file.

---

### 4.4 Reliability and Stability (NFR-REL)

**NFR-REL-01** — Crash-Free Rate (P1)  
The app shall achieve a crash-free session rate of ≥ 99.5% as measured over a rolling 7-day production window.

**NFR-REL-02** — Watchdog Recovery (P1)  
If the audio engine encounters an unrecoverable error (e.g., device disconnected mid-render), it shall log the error, stop playback gracefully, and recover to a playable state within 3 seconds without requiring an app restart.

> Given the active output device is forcibly disconnected mid-playback,  
> When the error is detected,  
> Then playback stops cleanly, an error banner appears, and the user can resume playback after reconnecting or selecting another device.

**NFR-REL-03** — State Consistency (P1)  
No combination of user actions (rapid profile switching, device hotplug, simultaneous seek and device change) shall leave the DSP engine or UI in an inconsistent state (e.g., wrong profile applied, incorrect device shown).

---

### 4.5 Installation, Uninstall, and Safe Fallback (NFR-INSTALL)

**NFR-INSTALL-01** — Standard App Install (P1)  
Phase 1 app installation shall follow standard macOS drag-to-Applications convention. No kernel extensions, no privileged installers, no sudo required. Phase 2 tap-path activation (FR-SYS-07) also requires no privileged install — only a TCC audio-capture consent dialog (NSAudioCaptureUsageDescription). The requirements below (NFR-INSTALL-02 through NFR-INSTALL-04) apply to the **driver fallback path** (FR-SYS-01..06) only.

**NFR-INSTALL-02** — Phase 2 Privileged Install — User Informed Consent (P1, driver fallback path)  
Before invoking any privileged installer (driver fallback path only), the app shall display a plain-language explanation of what will be installed, what system change will occur (coreaudiod restart), and how to uninstall. User must click a clearly labelled confirmation.

**NFR-INSTALL-03** — Phase 2 Safe Fallback (P1, driver fallback path)  
If the AudioServerPlugIn fails to load after coreaudiod restart (e.g., due to a signing issue or incompatibility), system audio shall automatically fall back to built-in speakers. The app shall detect this failure and guide the user through a recovery or uninstall flow.

> Given the plug-in bundle is corrupt or unsigned (fallback path),  
> When coreaudiod restarts,  
> Then coreaudiod ignores the plug-in, audio falls back to built-in speakers, and the companion app detects the failure within 10 seconds and shows a recovery prompt.

**NFR-INSTALL-04** — Clean Uninstall (P1)  
Uninstalling the app (Phase 1 / tap path: delete from Applications or disable tap — no files to remove beyond app bundle; driver fallback path: in-app uninstall) shall leave no residual files in /Library/Audio/Plug-Ins/HAL/, /Library/LaunchDaemons/, or application support directories. For the tap path, "clean uninstall" means: tap stopped, original output unmuted, TCC permission may be revoked by the user independently in System Settings — no additional cleanup required by the app.

---

### 4.6 Accessibility (NFR-ACC)

**NFR-ACC-01** — VoiceOver Full Navigation (P1)  
All controls shall be navigable and operable via VoiceOver. No feature shall be accessible only via mouse gesture.

**NFR-ACC-02** — Keyboard Navigation (P1)  
All primary functions (play/pause, skip, volume, profile select, DSP toggle) shall be accessible via keyboard shortcuts with no conflicts with standard macOS shortcuts.

**NFR-ACC-03** — Dynamic Type / Text Size (P2)  
The app shall respect the user's preferred text size setting and remain legible at all macOS accessibility text size levels.

**NFR-ACC-04** — Reduce Motion (P1)  
All animations shall be disabled or reduced when the macOS "Reduce Motion" accessibility setting is active.

> Given "Reduce Motion" is enabled in System Settings,  
> When the app plays and the adaptivity engine fires visual feedback,  
> Then no animations play; state changes are indicated by colour or label change only.

---

### 4.7 Localization Readiness (NFR-L10N)

**NFR-L10N-01** — String Externalization (P1)  
All user-visible strings shall be stored in localizable .strings files from the initial release. No hardcoded English strings shall appear in UI components.

**NFR-L10N-02** — RTL Layout Support (P2)  
The app UI shall be designed to support right-to-left layout mirroring for future Arabic and Hebrew localization.

**NFR-L10N-03** — Locale-Independent Audio (P1)  
No audio processing logic shall depend on locale settings (e.g., number formatting for frequency values). All internal DSP values shall use invariant floating-point representation.

---

## 5. Adaptivity Signal → Decision Matrix

The following table maps each input signal consumed by the Adaptivity Engine to the DSP parameters it controls, the direction of change, and the rationale grounded in psychoacoustics.

| Signal | Signal Source | DSP Parameter Adjusted | Direction / Rule | Rationale |
|---|---|---|---|---|
| **Playback Volume (dB)** | System volume API / in-app volume | Bass EQ gain (80–200 Hz), Treble EQ gain (8–12 kHz) | Low volume → boost; high volume → reduce | Fletcher-Munson / ISO 226:2003 equal-loudness contours: human hearing is less sensitive to bass and treble at low SPLs; compensation restores perceived tonal balance. |
| **Playback Volume (dB)** | System volume API | True-peak limiter threshold | Lower volume → looser threshold; high volume → tighten | At high volumes, headroom matters more for safety and distortion avoidance. |
| **Ambient Noise Level (dBA SPL)** | Mic-derived short-term A-weighted SPL | Multi-band compressor ratio | Louder ambient → higher ratio | Noise masking reduces dynamic range perception; mild compression improves speech and transient intelligibility in noise (cocktail-party effect analogy). |
| **Ambient Noise Level (dBA SPL)** | Mic-derived SPL | Low-frequency gain (100–300 Hz) | Louder ambient → slight boost | Low-frequency noise (HVAC, traffic) masks bass; partial lift maintains warmth. Limit: ≤ +3 dB to avoid muddiness. |
| **Ambient Noise Level (dBA SPL)** | Mic-derived SPL | Mid-frequency presence EQ (2–4 kHz) | Louder ambient → slight boost | Presence band improves speech intelligibility and melodic definition against broadband noise. |
| **Output Device Type** | Core Audio device classification | Spatialization mode | Headphones → HRTF binaural + crossfeed; Speakers → stereo widening + mid-side; DAC → neutral / user-defined | HRTF on speakers produces incorrect cues (already physically spatialised); speakers need width, not in-head correction. |
| **Output Device Type** | Core Audio device classification | Headphone correction EQ | Active on headphones; inactive on speakers | Headphone frequency response deviates from diffuse-field target; correction restores neutral tonality. Speaker correction is room-dependent (handled separately or deferred). |
| **Output Device Type** | Core Audio device classification | Psychoacoustic bass enhancement | Enabled for small speakers / in-ear headphones; reduced for large over-ear or external speakers | Small transducers cannot reproduce sub-bass fundamentals; harmonic synthesis creates perceptual bass without excursion risk. |
| **Content / Genre Classification** | Non-RT spectral + rhythm analyser | Tonal EQ curve | Classical → subtle curve (preserve dynamics); Electronic → bass + sub emphasis; Vocal/Acoustic → presence boost; Rock → controlled low-mid | Each genre has distinct spectral energy distribution and listener expectation; genre-tuned curves complement rather than override device correction. |
| **Content / Genre Classification** | Non-RT spectral analyser | Dynamic range compressor ratio + attack/release | Classical → low ratio (≤ 1.5:1), slow attack; Electronic → moderate ratio (2–3:1), fast attack; Podcast/Speech → higher ratio (3:1+), very fast attack | Dynamic range of source content varies enormously by genre; mismatched compression destroys either musical impact (over-compress) or intelligibility in noise (under-compress). |
| **Personal Hearing Profile (per-frequency threshold)** | Stored hearing calibration | Per-band EQ gain (both channels independently) | Frequency where threshold elevation detected → proportional gain addition | Compensates for individual sensorineural hearing loss pattern; restores perceived frequency balance to that of normal hearing at the listening level. |
| **Personal Hearing Profile (threshold elevation magnitude)** | Stored hearing calibration | Compression ratio at affected frequencies | Higher threshold elevation → lower ratio at that frequency | Hyperacusis / recruitment: at frequencies with elevated thresholds, loudness growth is non-linear; reduced dynamic processing prevents over-amplification of loud transients. |
| **AirPods Head Orientation (quaternion)** | CoreMotion / AirPods motion API | HRTF virtual source azimuth + elevation offset | Real-time counter-rotation: offset = –(head yaw, pitch) | Stabilises virtual soundstage in world space so it does not move when user turns head; mimics natural localisation of external sound sources. |
| **AirPods Head Orientation (quaternion)** | CoreMotion | Head-tracking update rate gate | Only update HRTF when orientation delta > 1 degree | Avoids unnecessary DSP parameter churn from sensor noise; <1 degree change is below perceptual threshold. |
| **User Natural-Language Feedback — Taste / Preference** | Conversational Tuning subsystem (FR-NLT-01 / FR-NLT-02); text submitted by user at will | DSP action vector: per-band EQ gain deltas (one or more bands per derived intent); optional dynamics (compression/transient) adjustment; optional spatial (width/crossfeed) adjustment — all via FR-ADAPT-02/03 lock-free ramp | Direction and magnitude derived from text: increase or decrease target parameter(s) by a moderate default step (e.g., ±3 dB for "moderate", ±1–2 dB for "subtle", ±6 dB or more for "strong"). Abstract/aesthetic descriptors produce multi-component vectors (see §3.9.1). | **Governing principle (LD-8):** A confirmed user natural-language instruction is a governing principle — the Adaptivity Engine adapts *around* it, never against it. Once confirmed, automatic adaptation (volume-based Fletcher-Munson, content/genre curves, ambient-noise adjustments) targeting the same DSP parameter(s) is subordinate to the user's stated intent for the remainder of the session or until the user explicitly undoes the change. Session-scoped by default; persists beyond the session only when the user taps [Yes, keep it] (FR-NLT-06). Reconciliation with the hearing profile is additive: the NLT delta is layered on top of the hearing-compensation curve, not merged into it. |
| **User Natural-Language Feedback — Urgent / Protective ("it hurts")** | Conversational Tuning subsystem (FR-NLT-09); discomfort or pain keywords detected in submitted text | Per-band EQ gain (60–250 Hz or the stated region); true-peak limiter threshold | Immediate reduction: ≥ −6 dB on the implicated band; true-peak limiter threshold tightened by ≥ 3 dBTP; applied before user confirmation and before normal confidence-gating | **Safety governing principle (LD-8):** This protective action is the highest-priority governing principle in the system. No other adaptation signal — automatic or manual — shall counteract or delay this reduction during the same session without an explicit user [Undo] action. Discomfort / pain language is treated as a protective trigger analogous in urgency to an over-level event. The Adaptivity Engine is locked out of the affected DSP parameter(s) in the opposing direction for the session unless the user explicitly undoes the change. |

---

## 6. Assumptions, Constraints, and Dependencies

### 6.1 Assumptions

| ID | Assumption | Impact if Wrong |
|----|-----------|----------------|
| ASM-01 | Target users have macOS 14 (Sonoma) or later. API availability (CoreMotion for AirPods, AudioObjectAddPropertyListenerBlock, AVAudioEngine) assumed on this baseline. | Lower deployment target would restrict head-tracking (AirPods CoreMotion requires macOS 14+) and other APIs. |
| ASM-02 | The app will be distributed outside the Mac App Store initially (to avoid sandboxing restrictions on AudioServerPlugIn in Phase 2). | App Store distribution would require separate entitlement review for HAL plug-ins; currently not straightforward. |
| ASM-03 | Developer ID signing and notarization are in place before any Phase 2 beta. | Without notarization, macOS Gatekeeper blocks plug-in load; system audio fails silently. |
| ASM-04 | **SADIE II (Apache-2.0)** is confirmed as the default shipped HRTF dataset (OQ-04 resolved). Additional datasets KEMAR and CIPIC are also available under permissive/compatible terms. IRCAM Listen is explicitly avoided (unverifiable license). Custom HRTF measurement is deferred per LD-7. | Resolved — SADIE II covers the requirement; no blocking risk. |
| ASM-05 | Device correction EQ curves are sourced from **AutoEq computed parametric curves (MIT, + attribution)**. Raw measurement databases from upstream measurers are not shipped (may be CC-BY-NC-SA); only AutoEq's derived curves are included. Upstream measurement provenance must be verified per curve before shipping (OQ-08 resolved as AutoEq, but provenance check is ongoing). | Without verified correction curves, headphone EQ is generic; differentiating feature weakens. Provenance verification is a per-model ongoing task. |
| ASM-06 | The content/genre classifier runs as a lightweight on-device ML model (Core ML) or a signal-processing heuristic, not a cloud inference call. | Cloud inference would violate real-time requirements, add latency, and raise privacy concerns. |
| ASM-07 | Apple will not revoke or restrict AudioServerPlugIn entitlements for independent developers between now and Phase 2 launch. | Apple has not announced changes, but policy can shift; monitor Apple Developer Forums. |
| ASM-08 | The AirPods motion data API (CMHeadphoneMotionManager) is accessible from a sandboxed companion app without additional entitlements beyond the standard headphone motion permission. | Additional entitlement requirement would delay feature. |
| ASM-09 | The Conversational Tuning subsystem (FR-NLT) can meet the < 1 500 ms response latency target (FR-NLT-04) for the chosen interpretation mechanism, whether on-device or external — **including the harder case of resolving an abstract/aesthetic phrase (FR-NLT-12) into a multi-component action vector**, not just a single-band lookup. This assumption must be validated once the interpretation approach is selected (OQ-11). | If the chosen mechanism cannot meet the latency target (especially for multi-component derivation), the acceptance criterion in FR-NLT-04 must be revised or the mechanism reconsidered. |

### 6.2 Constraints

| ID | Constraint | Source |
|----|-----------|--------|
| CON-01 | No heap allocation on the real-time audio thread. All audio buffers must be pre-allocated at session initialisation. | Core Audio real-time thread rules; Ross Bencina "Real-time audio programming 101". |
| CON-02 | No mutex, lock, or blocking call on the audio thread. All cross-thread communication via lock-free ring buffers (e.g., TPCircularBuffer, CARingBuffer) or std::atomic. | Core Audio real-time constraints. |
| CON-03 | AudioServerPlugIn must be pure C/C++ — no Objective-C runtime, no Swift, no Foundation. | QA1811; AudioServerPlugIn sandbox restrictions. |
| CON-04 | AudioServerPlugIn runs inside coreaudiod; IPC with companion app must use registered Mach services (AudioServerPlugIn_MachServices plist key). | QA1811. |
| CON-05 | macOS provides no direct interception of another app's audio stream via a public "tap all audio" API on macOS < 14.2. On macOS 14.2+, Core Audio process taps (`CATapDescription` + `AudioHardwareCreateProcessTap`) provide this capability without a virtual device. The driver path (AudioServerPlugIn) remains required for macOS < 14.2 or when a persistent selectable output device is needed. | Core Audio architecture; process tap API introduced in macOS 14.2/14.4 (confirm exact floor — see CON-10). |
| CON-06 | Microphone access is user-grantable/revocable at any time via System Settings → Privacy. The app must handle mid-session revocation gracefully. | macOS privacy framework. |
| CON-07 | The driver fallback path (AudioServerPlugIn) requires administrator privileges for writing to /Library/Audio/Plug-Ins/HAL/ and restarting coreaudiod. This is unavoidable with the driver architecture. The tap primary path (macOS 14.2+) requires **no** administrator privileges — only TCC audio-capture consent. | macOS file system permissions / TCC framework. |
| CON-08 | Distribution of the HAL plug-in (driver fallback path) requires Developer ID Application + Developer ID Installer certificates and a passing notarization ticket. | Apple Gatekeeper policy; macOS 13+ enforces notarization strictly. |
| CON-09 | AudioDriverKit dext is NOT an alternative for virtual audio devices — Apple does not grant the required entitlements for this use case. Use AudioServerPlugIn only (driver path). | WWDC21 session 10190; Apple Developer Forums confirmation. |
| CON-10 | The Core Audio process tap primary path requires macOS **14.2 or later** (minimum floor; exact version — 14.2 vs. 14.4 — must be confirmed by inspecting `<CoreAudio/AudioHardwareTapping.h>` SDK headers before engineering begins). This constraint interacts with OQ-07 (minimum OS deployment target). | `docs/architecture/prior-art.md` §5 open verifications; SDK headers. |
| CON-11 | Bass harmonic generation must be derived from a **mono-summed (L+R) low band**. Per-channel (stereo) harmonic generation is prohibited — it falls within Waves patent US-11,102,577 (active, filed 2018, ~2038 expiry). Formal IP review required before public release (see OQ-16). The MaxxBass approach (US-5,930,373) appears expired (~2019) but must be verified on USPTO before reliance. | `docs/architecture/prior-art.md` §6 patent watch. |
| CON-12 | All third-party code and data shipped in the app (libraries, HRTF datasets, EQ correction curves, ML model weights) must be under **permissive, redistributable licences** (MIT, BSD-2/3, Apache-2.0, Boost, 0BSD, ISC, zlib, public-domain, or equivalent). Copyleft (GPL/AGPL/LGPL) code and NC-licensed weights/data are reference-only and must not be shipped. This constraint implements LD-9 at the dependency level. Approved shipable picks: libmysofa (BSD-3), FFTConvolver (MIT), libebur128 (MIT), libASPL (MIT), SADIE II (Apache-2.0), AutoEq computed curves (MIT — verify upstream measurement provenance per `docs/architecture/prior-art.md` §5), Demucs+MLX (MIT). libbs2b licence is disputed and must be resolved before shipping (see OQ-17). | LD-9; `docs/architecture/prior-art.md` §1–§5. |

### 6.3 Dependencies

| ID | Dependency | Type | Risk |
|----|-----------|------|------|
| DEP-01 | Apple Core Audio framework (AudioHardware, AudioToolbox) | Platform | Low — stable API, backward compatible to macOS 12. |
| DEP-02 | Apple Accelerate / vDSP framework (FFT, biquad, convolution) | Platform | Low — stable, highly optimised for Apple Silicon. |
| DEP-03 | CMHeadphoneMotionManager (CoreMotion) — AirPods head-tracking | Platform | Medium — requires AirPods that support motion; API introduced macOS 14. |
| DEP-04 | AVAudioEngine (Phase 1 own-player) | Platform | Low — stable, well-documented. |
| DEP-05 | AudioServerPlugIn API (Phase 2, driver fallback path) | Platform | Medium — complex, limited documentation; reference BlackHole / Background Music / libASPL (MIT). |
| DEP-06 | HRTF datasets: **SADIE II (Apache-2.0)** — primary default; also KEMAR (cite), CIPIC (commercial OK — common NC claim is false), ARI (CC BY-SA — keep data under SA). Loaded via **libmysofa (BSD-3)**. IRCAM Listen is **avoided** (license unverifiable — see `docs/architecture/prior-art.md` §5; SADIE II covers the use case). OQ-04 resolved: SADIE II is the default; custom HRTF measurement deferred per LD-7. | External data + OSS library | Low — SADIE II Apache-2.0 confirmed; libmysofa BSD-3 confirmed. |
| DEP-07 | Headphone correction EQ curves: **AutoEq computed parametric curves (MIT, + attribution)**. Ship AutoEq's *computed* curves only — do not republish raw measurement databases unchecked (upstream measurers may be CC-BY-NC-SA; verify per `docs/architecture/prior-art.md` §5). OQ-08 resolved: AutoEq MIT computed curves are the source. | External data | Medium — MIT code; upstream measurement provenance requires per-file verification. |
| DEP-08 | ServiceManagement / **SMAppService** (Phase 2 privileged helper, driver fallback path). SMJobBless is deprecated in macOS 13+; use SMAppService. | Platform | Medium — SMAppService is the current API; evaluate migration path confirmed. |
| DEP-09 | TPCircularBuffer or CARingBuffer (lock-free ring buffer) | OSS library | Low — well-tested, MIT/BSD licensed. |
| DEP-10 | Core ML / SoundAnalysis (off-RT content classification, LD-5 Phase 2 upgrade) | Platform | Low — available macOS 12+; fallback to DSP heuristic classifier possible. Never used on the audio render thread (see BNNS Graph constraint in §3.4). |
| DEP-11 | **libebur128 (MIT)** — LUFS / true-peak measurement per ITU-R BS.1770 (replaces any bespoke LUFS implementation). | OSS library | Low — MIT confirmed; well-maintained. |
| DEP-12 | **FFTConvolver (MIT)** — partitioned convolution engine for SOFA HRIR and linear-phase EQ. Confirm `LICENSE` file path in-repo before vendoring (README says MIT; canonical `/LICENSE` path 404'd — see `docs/architecture/prior-art.md` §5). | OSS library | Low risk once file confirmed. |
| DEP-13 | **libASPL (MIT)** — AudioServerPlugIn framework (driver fallback path). | OSS library | Low — MIT confirmed. |
| DEP-14 | **Demucs + MLX port (MIT, including weights)** — future offline source-separation feature (LD-8(e), Phase 2+). Offline-only / heavy; not on the audio thread. Confirms LD-8(e) is offline-only. | OSS library + model | Low — MIT confirmed for code and weights. |
| DEP-15 | **BNNS Graph (Apple Accelerate)** — RT-safe ML inference on the audio thread. Single-threaded, no runtime allocation. | Platform | Low — part of Accelerate framework, stable. |
| DEP-16 | **libbs2b** (crossfeed) — ⚠️ license disputed (MIT vs. GPL-2.0+; see `docs/architecture/prior-art.md` §5 and OQ-17). Do not ship until licence is confirmed. Algorithm is public; reimplement on biquads if not clearly permissive. | OSS library (disputed) | High until resolved — see OQ-17. |

---

## 7. Open Questions and Requirement Gaps

The following items are unresolved and require founder/product-owner decisions before the relevant requirements can be finalised.

| ID | Area | Question / Gap | Impact if Unresolved | Priority |
|----|------|---------------|----------------------|----------|
| OQ-01 | Phase 2 — Installation | Should the app automatically switch the macOS default output device to the virtual device after install, or instruct the user to do it manually in System Settings? Auto-switching via property API is technically possible but may feel invasive and could conflict with user preference. | Determines onboarding UX complexity and the number of manual steps in Journey 2.6. | Critical |
| OQ-02 | ~~Monetization / Feature Gating~~ | ✓ **Resolved — removed (LD-9).** The project is personal / open-source and non-commercial. There is no business model, no paid tier, no paywall, and no feature-gating. All features are free. Feature-flag or entitlement-check logic for paid access is not required anywhere in the codebase. | Resolved — no action required. | ✓ Resolved |
| OQ-03 | Adaptivity Engine — Ambient Sensing | What is the required update cadence and smoothing window for ambient noise estimation? The current draft says "every 2 seconds" with 3-second hysteresis, but an audio engineer must validate whether this produces acceptable latency vs. stability trade-off. | NFR-PERF-04 and FR-ADAPT-04 acceptance criteria cannot be finalised without this specification. | High |
| OQ-04 | HRTF / Spatialization | Which HRTF data set(s) will ship in Phase 1? | FR-SPAT-01 and FR-SPAT-02 scope and timeline depend on this decision. | ✓ Resolved (LD-7 + prior-art pass): **SADIE II (Apache-2.0)** is the default dataset; custom HRTF measurement deferred. IRCAM Listen avoided (unverifiable license). Rendering is custom SOFA-HRIR partitioned convolution (libmysofa + FFTConvolver) — Apple PHASE/AVAudioEnvironmentNode HRTFs are non-replaceable. See DEP-06 and FR-SPAT-01. |
| OQ-05 | Hearing Calibration — Medical/Audiological Standards | Should the hearing calibration claim clinical accuracy (requiring ISO 8253-1 compliance and potentially a medical device regulatory pathway) or be explicitly positioned as a "listening preference" tool for entertainment only? The distinction has significant legal, regulatory, and marketing implications. | Incorrect positioning risks regulatory exposure (FDA, CE marking). Correct positioning shapes all FR-HEAR-* requirements and marketing copy. | ✓ Resolved (LD-7): "listening preference" tool, not a medical device |
| OQ-06 | Phase 1 Scope — Streaming Sources | Does Phase 1 (own player) include any streaming source integration (Spotify Connect, Apple Music API, YouTube Music)? Or is Phase 1 strictly local file playback only? The question materially affects FR-PLAY-* and the breadth of source support. | A Spotify Connect or MusicKit integration is weeks of additional work; must be scoped before sprint planning. | ✓ Resolved (LD-4): local files only in Phase 1 |
| OQ-07 | macOS Version — Minimum Deployment Target | The draft assumes macOS 14 for AirPods CoreMotion. Is this acceptable, or does the market require macOS 13 (or 12) support? Lowering the target eliminates head-tracking and may affect other API choices. Additional constraint from prior-art pass: the **process-tap primary Phase 2 path requires macOS 14.2 or later** (CON-10); the exact floor (14.2 vs. 14.4) must be confirmed in `<CoreAudio/AudioHardwareTapping.h>` before Phase 2 engineering begins. If the minimum OS is set below 14.2, the driver fallback path (FR-SYS-01..06) becomes the Phase 2 mechanism for those users. | Determines which APIs are available, whether the tap primary path is viable for the target user base, and the Phase 2 installer approach. | Medium |
| OQ-08 | Device Correction Library — Scope | How many headphone/speaker models will be included in the correction library at launch? Who owns ongoing library curation? | FR-TONAL-02 cannot be validated without knowing the minimum supported device count. | ✓ Resolved (prior-art pass): **AutoEq computed parametric curves (MIT + attribution)** are the source. Raw measurement databases are not shipped (provenance uncertain). Ongoing per-model provenance verification is required (see DEP-07 and CON-12). Minimum model count and curation owner remain to be confirmed in SPIKE-DEVCORRLIB. |
| OQ-09 | Content / Genre Classifier — Approach | Will the content classifier be a Core ML model (requires training data, model management, CoreML conversion pipeline) or a DSP heuristic (spectral centroid, BPM estimation, onset detection)? The ML approach is more accurate but has higher cold-start and maintenance cost. | FR-ADAPT-01 acceptance criteria and engineering estimates differ substantially between the two approaches. | ✓ Resolved (LD-5): heuristics in Phase 1, Core ML later |
| OQ-10 | Telemetry and Crash Reporting | Will the app use a third-party crash reporting SDK (e.g., Sentry, Firebase Crashlytics)? If so, which one, and how does this interact with the App Store privacy label and NFR-PRIV-04? | Data residency, privacy disclosure, and SDK dependency must be confirmed before SDK is integrated. | Medium |
| OQ-11 *(NLT — DEFERRED ARCHITECTURE)* | Conversational Tuning — Text Interpretation Mechanism | How is user-submitted natural-language text converted into a structured audio intent (direction + aspect + magnitude)? Candidate approaches include: (a) deterministic rule/keyword engine (fast, on-device, no external dependency, limited coverage), (b) on-device small language model (broader coverage, privacy-safe, hardware/model size constraints), (c) cloud LLM API (broadest coverage, adds latency, network dependency, privacy implications, ongoing cost). This decision has cascading implications for privacy disclosure, offline behaviour, latency SLA (FR-NLT-04 target of < 1 500 ms), App Store compliance, and cost model. **This question is explicitly deferred — do not resolve in requirements.** | Affects implementation approach for FR-NLT-01 through FR-NLT-08; privacy policy; NFR-PRIV telemetry posture; offline/airplane-mode behaviour; latency acceptance criteria in FR-NLT-04. Cannot finalise engineering estimates until resolved. | Critical (deferred by design) |
| OQ-12 *(NLT)* ✓ RESOLVED (LD-8, Decision A) | Conversational Tuning — Instrument Source Separation: Approach and Phase | ~~FR-NLT-10 specifies band approximation as the near-term behaviour for instrument/source requests ("guitar", "vocals", "drums"). The confirmation card surfaces a caveat that the full mix in that band is affected. Two questions require founder input: (a) Is the band-approximation + caveat acceptable for Phase 1, or does the founder consider the caveat a user-experience deal-breaker that blocks the feature? (b) If full ML source separation (e.g., Demucs, HTDemucs) is on the roadmap, which phase is it targeted for, and is real-time source separation (high compute cost) required, or is a near-real-time / pre-analysis approach acceptable?~~ **RESOLVED:** Band-region approximation is the confirmed baseline and is fully shippable at Phase 1 — it is not a degraded fallback and the caveat in the confirmation card is acceptable UX. Instrument-naming requests are an "indirect" point on the unified DSP action-space directness spectrum (LD-8); they resolve to the same action vector as all other phrase types. ML source separation (e.g., Demucs/HTDemucs) is an optional precision enhancement for a later phase. It is NOT a prerequisite and NOT on the critical path. The instrument-naming branch of Conversational Tuning is unblocked for Phase 1. (See also FR-NLT-10 reframe.) | Resolved — no further action required. | High |
| OQ-13 *(NLT)* | Conversational Tuning — Ambiguity and Clarification UX | FR-NLT-08 specifies a maximum of two clarification rounds before the app falls back to directing the user to the EQ panel. The following sub-questions require product decisions: (a) Is a two-round limit correct, or should it be one round (to avoid the interaction feeling tedious)? (b) Should unanswered clarification prompts that time out be treated as "no action" or as "cancel input"? (c) Should the app offer suggested auto-complete phrases as the user types (predictive suggestions), and if so, is this limited to a fixed vocabulary or powered by the same mechanism as intent derivation? | The two-round limit and auto-complete decision affect acceptance criteria for FR-NLT-08 and the UI specification for FR-NLT-01. Auto-complete requires design and — depending on mechanism choice (OQ-11) — additional engineering scope. | Medium |
| OQ-14 *(NLT)* | Conversational Tuning — Multilingual Support | All phrase examples in §3.9.1 and FR-NLT-* are specified in English. Two decisions are required: (a) Is Conversational Tuning English-only at launch, with multilingual support deferred? (b) If multilingual support is in scope (even future-phase), should the system auto-detect the language of the input, or require the user to set a preferred language? The answer affects the interpretation mechanism (OQ-11), the set of example phrases and vocabulary lists, and NFR-L10N-01 string externalisation scope for dynamic reply strings. | English-only at launch is the lowest-risk position; committing to multilingual support at launch substantially increases scope of the interpretation mechanism and QA effort. If deferred, the UI must be designed to handle future addition without rework. | Medium |
| OQ-15 *(NLT)* — partially resolved | Conversational Tuning — Reconciliation of Learned Text Preferences with Automatic Adaptation and Hearing Profile | FR-NLT-06 specifies that confirmed text-driven changes are stored as a delta on the active profile. Three reconciliation scenarios: **(a) RESOLVED (LD-8, Decision B — governing principle):** A confirmed NLT instruction is a governing principle. The automatic Adaptivity Engine (volume-based Fletcher-Munson, content/genre curves, ambient-noise adjustments) is subordinate to the user's stated intent for the targeted DSP parameter(s) for the session or until undone. Composition model: automatic adaptation continues to operate on *other* bands not targeted by the NLT instruction; for the targeted band(s), the NLT delta is the floor and the engine does not push changes that would counteract it. Session-scoped by default; persists only on explicit [Yes, keep it] confirmation. **(b) PENDING CONFIRMATION — recommended default:** When the user re-runs hearing calibration (FR-HEAR-01) and the new profile shifts a band that has an existing NLT delta, the NLT delta should be **surfaced for review** rather than silently preserved or discarded. Recommended UX: post-calibration, the app presents a summary of any NLT deltas that conflict with the new hearing profile and asks the user to confirm, adjust, or discard each. This recommendation is pending founder confirmation before being locked into FR-NLT-06 and FR-HEAR-01. **(c) PENDING CONFIRMATION — recommended default:** A per-band accumulated NLT delta cap of **±12 dB** is recommended to prevent runaway drift from repeated one-directional feedback across many sessions. The cap should be surfaced to the user (e.g., "You've reached the maximum bass boost — try the EQ panel for further adjustment") rather than silently clamped. This recommendation is pending founder confirmation before being locked as a hard constraint in the profile-delta storage specification. | (a) resolved; (b) and (c) pending founder confirmation of recommended defaults — not deferred. Engineering must not proceed on profile-delta storage design until (b) and (c) are confirmed. | High |
| OQ-16 | Patents — Psychoacoustic Bass Enhancement IP Review | CON-11 requires formal IP review before any public release of FR-TONAL-04. Specific items: (a) Verify US-5,930,373 (Waves/MaxxBass, ~2019) is truly expired on USPTO before relying on it. (b) Verify the mono-summed NLD approach is clearly outside Waves US-11,102,577 (active, ~2038). (c) Check whether any Xperi/SRS virtual-bass patents are still active and whether the mono-summed design avoids them. This is a formal legal/IP task, not a technical investigation — requires qualified IP counsel. Engineering may proceed with the mono-summed design; public release is blocked until this review is complete. | Public release of FR-TONAL-04 is blocked without IP review sign-off. Engineering is unblocked (use mono-summed design per CON-11). | High — blocks public release |
| OQ-17 | libbs2b License Dispute | `docs/architecture/prior-art.md` §5 notes conflicting reports on the libbs2b licence: one source found MIT in source headers; another reported GPL-2.0+. This must be resolved before libbs2b is shipped (CON-12). Action: open the canonical `LICENSE` / source header in the upstream repo. If not clearly MIT, reimplement the Bauer crossfeed algorithm from the public specification (a small number of biquad filters + delay — trivial to reimplement cleanly). FR-SPAT-03 / US-DEVICE-07 are blocked on this resolution. | FR-SPAT-03 (crossfeed) cannot be shipped with libbs2b until confirmed permissive. Reimplementation unblocks the feature if licence is not clear. | Medium — blocks crossfeed shipping |
| OQ-18 | DSP — Phase realization per content | Minimum-phase is the default (LD-13). Open: should transient-dense content force minimum-phase even where linear/mixed-phase is otherwise selected, and what transient-density threshold triggers the switch? Resolve before the Realizer is implemented. | Realizer design + FR-TONAL-01 acceptance. | High |
| OQ-19 | Stem engine — feasibility budget | Measured per-stem RT cost, total memory for 6 cached stems + BRIR kernels, and worst-case render on a base Apple-Silicon laptop are unknown (NFR-PERF-06). A spike must measure these before Phase 1.5 scope is committed. | Gates Phase 1.5 scope; informs QualityProfile scaling. | High — gates Phase 1.5 |
| OQ-20 | Stem engine — quality-gating policy | What objective + perceptual criteria gate a separated stem as "usable" vs. merged into "other", and how does confidence bound the Reimagine ceiling per track (FR-STEM-05)? | FR-STEM-05 acceptance; user-perceived quality. | High |
| OQ-21 | Reimagine — intensity→parameter mapping | The exact mapping from the 0–100% knob to crossfade + spatial spread + unmask depth (and the mix-range vs stem-range ceiling) needs definition and user testing (FR-REIMAGINE-03). | FR-REIMAGINE-03 acceptance; UX. | Medium-High |
| OQ-22 | Perceptual model — masking choice | Which masking + partial-loudness model (Moore-Glasberg vs MPEG psychoacoustic) and what ERB/Bark arbitration details drive clarity/adaptive decisions (LD-12)? | Arbiter design; FR-ADAPT perceptual decisions; between-stem unmasking (FR-STEM-03). | Medium |

---

## Appendix A — Requirement ID Registry

| Prefix | Area |
|--------|------|
| FR-PLAY | Playback and Source |
| FR-SPAT | Spatialization |
| FR-TONAL | Tonal and Dynamic Optimization |
| FR-ADAPT | Adaptivity Engine |
| FR-DEVICE | Device and Profile Management |
| FR-HEAR | Personalization / Hearing Profile |
| FR-UI | UI and Controls |
| FR-SYS | Phase 2 System-Wide Enhancement |
| FR-NLT | Conversational Tuning — Natural-Language Sound Feedback |
| FR-REIMAGINE | Reimagine Intensity Control |
| FR-STEM | Stem-Based Object Engine (Phase 1.5) |
| NFR-PERF | Performance |
| NFR-QUAL | Audio Quality |
| NFR-PRIV | Privacy |
| NFR-REL | Reliability |
| NFR-INSTALL | Installation / Uninstall |
| NFR-ACC | Accessibility |
| NFR-L10N | Localization |
| STK | Stakeholders |
| ASM | Assumptions |
| CON | Constraints |
| DEP | Dependencies |
| OQ | Open Questions |

---

## Appendix B — Glossary

| Term | Definition |
|------|-----------|
| Conversational Tuning | The FR-NLT feature set that allows users to describe what they hear in plain language and have the app translate that description into a DSP action vector applied through the existing DSP engine. |
| Intent Derivation | The process (mechanism unspecified — see OQ-11) by which a natural-language phrase is converted into a DSP action vector (per-band gain deltas + optional dynamics + optional spatial). The output target is always the unified action-space regardless of phrase type (frequency-referencing, instrument-naming, or aesthetic/emotional). |
| DSP Action Vector | The structured output of intent derivation: a set of parameter changes over the shared DSP action-space — per-band gain deltas across the frequency spectrum, optional dynamics (compression ratio / transient enhancement), and optional spatial (stereo width / crossfeed) moves. Every phrase type resolves to this common representation (LD-8). |
| NLT Delta | The signed per-band gain adjustment (and any dynamics/spatial changes) accumulated from confirmed Conversational Tuning interactions, stored as a layer on top of the baseline DSP profile. Capped at a recommended ±12 dB per band pending founder confirmation (OQ-15c). |
| Discomfort / Pain Signal | A keyword or phrase in user-submitted text that indicates immediate auditory discomfort or pain (e.g., "it hurts", "painful"), triggering the urgent protective reduction path (FR-NLT-09) without waiting for confidence-gating. |
| Band Approximation | The Phase 1 baseline and confirmed shippable approach for instrument/source requests (FR-NLT-10, OQ-12 resolved): the DSP action vector targets the frequency region where the named instrument or source typically dominates, without true per-source isolation. This is the production behaviour, not a temporary workaround. |
| Source Separation | An ML technique (e.g., Demucs / HTDemucs) that isolates individual instruments or vocal tracks from a mixed audio signal. An optional precision enhancement for a later phase — NOT a prerequisite for instrument-naming requests (OQ-12 resolved, LD-8). |
| Governing Principle (NLT) | A confirmed user natural-language instruction that the Adaptivity Engine must adapt around, not against. Automatic adaptation signals (volume, content, ambient noise) are subordinate to the user's stated intent on the targeted DSP parameter(s) for the session duration or until explicitly undone (LD-8, OQ-15a resolved). |
| Directness Spectrum | The continuum along which natural-language phrases map to DSP action vectors: Direct (frequency words → 1:1 band gain) | Indirect (instrument names → band-region approximation) | Abstract (aesthetic/emotional → combination of spectral, dynamic, and spatial moves). All points on the spectrum share the same action-space output (LD-8). |
| AudioServerPlugIn | Apple's mechanism for a virtual audio device that runs inside the coreaudiod process. Required for system-wide audio interception. |
| AUHAL | Audio Unit Hardware Abstraction Layer. The Core Audio API for direct device I/O in a developer's own process. |
| HRTF | Head-Related Transfer Function. A pair of filters (left/right ear) that encode the spectral and temporal cues the brain uses for spatial hearing. Used to render binaural audio on headphones. |
| Crossfeed | A technique that feeds a fraction of the left channel into the right ear (and vice versa) to reduce unnatural extreme stereo separation on headphones. |
| Fletcher-Munson / ISO 226 | Equal-loudness contours describing how perceived loudness varies with frequency at different SPL levels. Basis for loudness-compensated EQ. |
| Lock-free | A concurrency technique where shared data is accessed without mutexes, using atomic operations or ring buffers. Required on the audio real-time thread. |
| True-Peak | A measure of audio peak level that accounts for inter-sample peaks. Distinct from sample peak; measured per ITU-R BS.1770. |
| XRun | An overrun or underrun of the audio buffer indicating that the audio thread missed its deadline, causing an audible glitch. |
| AutoEQ | An open-source project providing parametric EQ correction profiles for hundreds of headphone models, targeting diffuse-field or Harman target curves. |
| coreaudiod | The macOS system daemon that manages the Core Audio HAL (Hardware Abstraction Layer). |
| SPSC Ring Buffer | Single-Producer, Single-Consumer ring buffer. The standard lock-free data structure for audio thread ↔ UI thread communication. |
| SMJobBless / SMAppService | Apple's ServiceManagement APIs for installing a privileged helper tool. SMJobBless is deprecated in macOS 13 in favour of SMAppService. |
| dBTP | Decibels relative to True Peak (0 dBTP = digital full scale, accounting for inter-sample peaks). |
| LUFS | Loudness Units relative to Full Scale. Standard loudness measurement per ITU-R BS.1770 / EBU R128. |
| Process Tap | A Core Audio mechanism (macOS 14.2+) using `CATapDescription` + `AudioHardwareCreateProcessTap` that captures system audio output without installing a HAL plug-in or requiring administrator privileges. Used as the primary Phase 2 mechanism (FR-SYS-07/08). |
| SOFA | Spatially Oriented Format for Acoustics. A standardised file format for storing Head-Related Transfer Functions (HRTFs) as measured impulse-response pairs. Loaded by libmysofa (BSD-3). |
| BNNS Graph | Apple's Accelerate framework API for building and executing neural-network inference graphs on the CPU in a real-time-safe manner (no runtime allocation, single-threaded). The only ML inference mechanism permitted on the audio render thread. |
| libmysofa | BSD-3-licensed SOFA loader library used to read HRTF datasets (e.g., SADIE II) for the custom binaural convolution engine (FR-SPAT-01). |
| libebur128 | MIT-licensed C library implementing ITU-R BS.1770 / EBU R128 loudness and true-peak measurement (DEP-11). |
| SADIE II | Spatially Oriented Format for Acoustics Dataset II. An Apache-2.0-licensed binaural HRTF dataset used as the default SOFA dataset for FR-SPAT-01. |
| AutoEq | Open-source project providing MIT-licensed *computed* parametric EQ correction profiles for hundreds of headphone models. Used as the source for device correction curves (FR-TONAL-02, DEP-07). Raw upstream measurements are not shipped. |
