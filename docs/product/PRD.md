# Product Requirements Document
## Adaptive Sound — macOS Intelligent Audio Enhancer

**Status**: Draft v0.1
**Date**: 2026-06-12
**Owner**: Product (ramith@wso2.com)
**Phase**: Pre-development / Concept validation

---

## 0. Locked Decisions (as of 2026-06-12)

These were confirmed with the founder and supersede any conflicting text below. Open decisions still pending are listed in §7.

| # | Decision | Resolution | Affects |
|---|---|---|---|
| LD-1 | **Scope / phasing** | Start as a self-contained own-player (Phase 0), then grow to system-wide via virtual device (Phase 2). | Whole roadmap |
| LD-2 | **Meaning of "immersive"** | Both spatial (HRTF, crossfeed, room, head-tracking) **and** tonal/dynamic optimization, weighted equally. | §4 feature set |
| LD-3 | **Output targets** | Both headphones/AirPods **and** speakers; auto-detect device and switch profiles. | P0-5, P1-1, FR-SPAT/DEVICE |
| LD-4 | **MVP listening source** | **Local files only** in Phase 0. Spotify/Apple Music enhancement is deferred to Phase 2 (platform reality — own-player cannot access their PCM). | P0-1, P0-15 |
| LD-5 | **Content-aware brain** | **Phased**: DSP heuristics (FFT/spectral) ship in Phase 0; on-device Core ML genre/mood model layered in during Phase 1. Resolves §7 Decision 4. | P0-2/3, P1-8 |
| LD-6 | **Ambient mic adaptation** | **On-demand sampling** (user taps "adapt to my environment"; mic samples ~3 s). No always-on mic / no persistent orange indicator. Resolves §7 Decision 5. | P0-11, P1-4 |
| LD-7 | **HRTF & hearing personalization** | **Generic HRTF** (e.g. MIT KEMAR) + a simple in-app calibration **framed strictly as a "listening preference" tool**, not a medical/audiological device. Custom HRTF measurement deferred. Resolves §7 Decision 2 + regulatory framing. | P1-1, P1-5 |
| LD-8 | **Conversational Tuning** | Natural-language sound feedback is in scope. (a) A user instruction acts as a **governing principle** the Adaptivity Engine adapts *around*, never against. (b) **Session-scoped by default**, with explicit save to persist. (c) Instrument/source requests use **band approximation + honest caveat** now; ML source separation deferred to a later phase. (d) Positioned as a **supporting/discovery** feature at the Phase 1 launch, not the headline. Resolves §7 Decisions 6 & 7. | §3a, FR-NLT, P1-13..16 |
| LD-9 | **Project model** | Personal / open-source, non-commercial. No monetization, pricing, paywall, or feature-gating of any kind. All features are free to everyone in every phase. (Specific OSS license **deferred to post-MVP** / post-Phase 0.) | Whole doc |

---

## 1. Product Vision & Positioning

### One-Line Vision

> Make every pair of headphones and every laptop speaker sound like the best version of itself — automatically, in real time, without the listener having to think about it.

### Positioning Statement

For **audio-conscious Mac users** who are frustrated that their expensive headphones or high-end laptop speakers are never actually heard at their full potential, **Adaptive Sound** is a **macOS audio enhancement app** that continuously optimizes playback quality by adapting — in real time — to what you are listening to, how loud it is, what output device is connected, and your individual hearing profile. Unlike static equalizers such as eqMac or one-size-fits-all "3D" effects like Boom 3D, Adaptive Sound treats every listening session as a unique acoustic event and adjusts accordingly.

---

## 2. Target Personas

### Persona A — "The Audiophile Commuter" (Primary)

**Profile**: Marcus, 31, software engineer. Owns Sony WH-1000XM5 or AirPods Pro. Commutes by train and works from coffee shops. Listens to a mix of lo-fi, jazz, and electronic music for 3–5 hours per day on a MacBook Pro.

**Pain**: His headphones sound flat at low volume in a quiet cafe, then harsh and fatiguing at high volume on a noisy train. He has tried eqMac but finds manual EQ fiddling tedious. He knows his headphones are capable of more than he is hearing.

**Job to be Done**: "When I press play, I want it to sound great right now — not after I spend 20 minutes tweaking sliders."

**What they value**: Immediate, effortless improvement to daily listening with zero configuration overhead. Will abandon if there is any noticeable latency or dropout.

---

### Persona B — "The Late-Night Laptop Listener" (Primary)

**Profile**: Priya, 27, product designer. Uses MacBook Air M2 built-in speakers exclusively, often late at night at low volume. Listens to podcasts, indie pop, and ambient music.

**Pain**: MacBook Air speakers sound thin at low volume; the bass disappears entirely below 30% volume. Apple's Spatial Audio on AirPods is impressive but she often listens without headphones. She does not know what an EQ is and will not configure one.

**Job to be Done**: "Make my laptop speakers sound full and warm even when I have to keep the volume low so I don't wake anyone."

**What they value**: Sound that is noticeably fuller and warmer with zero setup or learning curve. Discoverability through word-of-mouth or a simple direct download.

---

### Persona C — "The Home Studio Hobbyist" (Secondary)

**Profile**: Tom, 38, musician and weekend producer. Uses Audio-Technica ATH-M50x studio headphones. Switches between headphone mixing, Spotify reference listening, and YouTube tutorials constantly. Runs Ableton on the same machine.

**Pain**: His studio headphones are not tuned for casual listening; they are flat and analytical. He uses Sonarworks SoundID in the DAW but it only works inside the DAW. He wants a global correction profile that works across all apps, not just Ableton.

**Job to be Done**: "I want my reference headphones to sound like they were tuned for enjoyment everywhere, not just inside my DAW."

**What they value**: A technically credible, globally-active correction profile that works across every app on the machine, not just inside a DAW. Respects well-documented tools; will read the release notes.

---

## 3. Value Proposition & Competitive Differentiation

### Core Value Proposition

Adaptive Sound is the only Mac audio enhancer that continuously reacts to context. The Adaptivity Engine adjusts processing in real time across five dimensions simultaneously: audio content, ambient environment, output device, playback volume, and personal hearing. The result is an experience that feels effortlessly perfect rather than technically configured.

### Competitive Comparison Table

| Capability | Adaptive Sound | eqMac | Boom 3D | SoundSource | Sonarworks SoundID | Apple Spatial Audio |
|---|---|---|---|---|---|---|
| System-wide processing | Phase 2 | Yes | Yes | Yes | DAW only | AirPods only |
| Own-player mode (no driver) | Phase 0 MVP | No | No | No | No | No |
| Adaptive / real-time adjustment | Yes (core) | No — static | No — static | No — static | No — static | Limited (head tracking) |
| Content-aware EQ (genre/spectrum) | Yes | No | No | No | No | No |
| Volume-aware EQ (Fletcher-Munson) | Yes | Manual | No | No | No | No |
| Ambient noise sensing (mic) | Yes | No | No | No | No | No |
| HRTF binaural / spatial staging | Yes | No | Basic "3D" | No | No | Yes |
| Head tracking (AirPods motion) | Yes | No | No | No | No | Yes |
| Headphone correction profiles | Yes | No | No | No | Yes (excellent) | No |
| Speaker auto-detection + switch | Yes | Manual | Manual | Manual | No | No |
| Hearing personalization | Yes (Phase 1) | No | No | No | Via Mimi | No |
| Natural-language sound tuning | Yes (Phase 1+) | No | No | No | No | No |
| Price | Free / open-source | Free | $19.99 | $39 | $99/yr | Free (Apple ecosystem) |
| macOS virtual audio driver required | Phase 2 only | Yes | Yes | Yes | No | No |

**Sharp differentiation in one sentence**: Every competitor requires the user to configure a static profile up-front and leave it alone; Adaptive Sound is the only product that keeps working on your behalf every second the audio is playing.

---

## 3a. Feature Definition — Conversational Tuning

### What It Is

Conversational Tuning lets users describe what they hear in plain English — "bass is too low," "I can't hear voices," "this is hurting my ears" — and have the Adaptivity Engine respond with an immediate, meaningful adjustment. There are no sliders to find, no band numbers to know, no audio vocabulary required. The user simply speaks the problem; the app fixes it.

This makes the Adaptivity Engine *directable*: fully automatic by default, but steerable in plain English when the automatic result is not quite right.

### User Value

- **Zero-knowledge interface to the engine.** For users who do not know what an EQ is (Persona B — Priya), this is the only way to express a sound preference without learning a new domain. Typing "more warmth" is far more accessible than locating a 200 Hz slider.
- **Escapes the frustration gap.** The Adaptivity Engine is excellent at what it infers automatically, but it cannot know the listener's subjective taste in the moment. Conversational Tuning closes the gap between "pretty good automatically" and "exactly how I want it right now."
- **Protective response to discomfort.** Phrases signalling pain or discomfort ("it hurts my ears," "too harsh," "piercing") are treated as an urgent signal, not a preference adjustment. The app responds with an immediate protective reduction before any fine-tuning occurs.

### Jobs to Be Done (JTBD)

| Persona | JTBD Statement |
|---|---|
| **Persona B — Priya** (primary JTBD) | "When the sound bothers me or feels off, I want to fix it by just saying what's wrong — without learning anything about audio." |
| **Persona A — Marcus** | "When I'm on a noisy train and the automatic settings aren't quite right, I want to nudge the sound quickly without breaking my flow." |
| **Persona C — Tom** | "When I want a specific instrument to sit better in the mix, I want to direct the app with professional intent without manually hunting EQ bands." |

### How Any Phrase Becomes an Adjustment — the Unified Model

Whatever the user says — a frequency word, an instrument name, or a purely aesthetic impression — it resolves to the **same underlying action**: a set of **gain changes across frequency regions**, plus optional **dynamics** (compression / transient) and **spatial** (width / crossfeed) moves. There is one shared **DSP action-space**; phrases differ only in how *directly* they map onto it, not in the machinery behind them.

| Directness | Example phrases | How it maps |
|---|---|---|
| **Direct** — frequency word | "bass too low," "too much treble," "more warmth" | 1:1 to a band's gain (e.g. bass → 60–250 Hz). Trivial, real-time. |
| **Indirect** — instrument / source | "can't hear voices," "guitar isn't clear," "drums too loud" | Adjust the region where that source's energy dominates (e.g. vocal presence 2–4 kHz). |
| **Abstract** — aesthetic / emotional | "sounds boring / bland / lifeless," "muddy," "harsh," "thin," "boxy" | A *combination* of moves (e.g. "lifeless" → +presence +air +transient punch, maybe +width). The richest expression of taste. |

**Key consequence:** the engineering target is a **parameter vector over the spectrum + dynamics + spatial**, *not* a stem separator. This collapses what once looked like "two classes" into a single mechanism and **removes ML source separation from the critical path** — for instrument-named requests, EQ-region approximation is the baseline, and true per-source isolation (source separation) becomes an *optional precision upgrade* in a later phase, never a prerequisite for the feature to ship.

### Safety Principle — Discomfort Phrases

Any input that signals physical discomfort ("hurts my ears," "too painful," "it's piercing," "too harsh at this volume") must be treated as a *protective event*, not a preference signal. The required response is:

1. Immediately attenuate the problematic frequency region by a meaningful amount (e.g., −4 to −6 dB on the offending range).
2. Apply the reduction before any confirmation or explanation is shown to the user.
3. Surface a brief, human confirmation: "Turned down the harsh highs — adjusting now." Do not ask the user to confirm first.

This is a first-class product principle, not a nice-to-have. Discomfort signals are urgent; the cost of under-reacting is real harm and immediate loss of trust.

### Interaction with the Adaptivity Engine and Adaptation Strength

Conversational Tuning adjustments operate as a **user preference layer** that sits on top of the automatic Adaptivity Engine output — they do not replace it.

**Behavioral model:**

- A Conversational Tuning instruction is treated as a **governing principle for adaptation**, not a one-off offset. It expresses the listener's intent for some aspect of the sound (e.g., "keep vocals intelligible," "less bass"), and the Adaptivity Engine adopts that intent as a **standing objective**: it keeps adapting to volume, content, and environment, but does so **in service of the principle, never against it.** Where automatic adaptation would move a band counter to a stated instruction, the instruction wins and the engine adapts the rest of the chain around it.
- Governing principles are **session-scoped by default**: they reset when a new session starts, so the engine begins fresh. The user can promote any instruction to a **saved principle** (tied to the current device profile or content type) with an explicit save — see LD-8.
- Interaction with the Adaptation Strength slider: **Adaptation Strength governs the engine's *autonomous* range; a user instruction is not subject to that range.** It is an explicit directive, so it executes fully and then constrains subsequent autonomous adaptation regardless of the strength setting.
- Multiple sequential instructions accumulate (e.g., "bass up" then "treble down" both persist). The user can reset all adjustments with a single "reset" or "undo everything" instruction, or via a visual reset button in the UI.

---

## 4. Prioritized Feature Set by Phase

### Prioritization Scheme: MoSCoW

- **M** (Must Have): Ship-blocking. MVP is unusable without it.
- **S** (Should Have): High user value, ship in the phase if feasible.
- **C** (Could Have): Nice to have; defer if schedule is tight.
- **W** (Won't Have this phase): Explicitly out of scope — documented to prevent scope creep.

---

### Phase 0 — Own-Player MVP

**Goal**: Prove the Adaptivity Engine concept end-to-end. Ship fast with zero driver complexity. Target: 8–12 weeks to private beta.
**Architecture**: AVAudioEngine / AUHAL + C++ DSP engine + SwiftUI UI. No virtual audio device, no sudo, no notarization complexity beyond standard app notarization.

#### Features

| # | Feature | Priority | Notes |
|---|---|---|---|
| P0-1 | Local file playback (FLAC, ALAC, MP3, AAC, WAV) | M | The player shell. Use AVAudioEngine. |
| P0-2 | Real-time spectral analysis of playing content | M | FFT via vDSP. Foundation of content-aware EQ. |
| P0-3 | Content-aware adaptive EQ — auto-adjusts bands per spectral profile | M | The core differentiator, must be demonstrated in MVP. |
| P0-4 | Volume-aware EQ (Fletcher-Munson compensation) | M | Boosts bass/treble at low volume. Immediate "wow" for Persona B. |
| P0-5 | Output device auto-detection (headphones vs. speakers) | M | Via `kAudioHardwarePropertyDefaultOutputDevice`. Switch profiles on plug/unplug. |
| P0-6 | Built-in device preset library (MacBook Air/Pro speakers, AirPods, Sony, Bose, Sennheiser top models) | S | ~20 presets covering 80% of users. Enables out-of-box experience. |
| P0-7 | Manual EQ override (10-band) with real-time visualization | S | Escape hatch for Persona C. Keeps audiophiles happy. |
| P0-8 | Basic crossfeed (reduce stereo separation for headphones) | S | Reduces listening fatigue. Differentiates from plain EQ. |
| P0-9 | Playback queue, basic library view, drag-and-drop | S | Minimum viable player UX. |
| P0-10 | Adaptive dynamics: soft limiter + psychoacoustic bass enhancement | C | Nice-to-have for bass emphasis on laptop speakers. |
| P0-11 | Ambient noise sensing via built-in mic (adjust EQ/volume) | C | Requires mic permission UX; can defer to Phase 1. |
| P0-12 | Head tracking via AirPods motion | W | Phase 1. Requires CoreMotion, adds complexity. |
| P0-13 | HRTF binaural rendering (full spatial) | W | Phase 1. Computationally heavier; needs tuning time. |
| P0-14 | Personal hearing profile / audiogram import | W | Phase 1. |
| P0-15 | Streaming service integration (Spotify, Apple Music) | W | Phase 2 (requires system-wide driver). |
| P0-16 | System-wide audio processing | W | Phase 2. Requires AudioServerPlugIn — explicitly deferred. |
| P0-17 | Windows / cross-platform | W | Not in roadmap. macOS only. |

**What is explicitly NOT in Phase 0**: Any virtual audio device, any sudo/install step, any system-wide processing, any streaming app integration. The MVP is a music player with a smart brain, nothing more.

---

### Phase 1 — Richer Adaptivity & Profiles

**Goal**: Deepen the "adaptive" story, ship spatial audio, add personalization. Target: 16–24 weeks after Phase 0 launch. Begin growing beyond own-player by layering intelligence, not distribution scope.
**Architecture**: All Phase 0 plus CoreMotion (AirPods head tracking), HRTF convolution engine (can use measured IRs from MIT KEMAR or user-chosen), optional mic-based ambient sensing.

#### Features

| # | Feature | Priority | Notes |
|---|---|---|---|
| P1-1 | HRTF binaural rendering — virtual soundstage outside the head | M | The spatial half of "immersive." Needs a library of HRTFs and a default generic HRTF. |
| P1-2 | Head tracking via AirPods motion (CoreMotion / CMHeadphoneMotionManager) | M | Makes HRTF dynamic. Strong differentiation vs. Boom 3D. |
| P1-3 | Virtual room convolution (living room, studio, concert hall IRs) | S | Pairs with HRTF for full spatial experience. |
| P1-4 | Ambient noise sensing via mic — adapts EQ and dynamics to room noise floor | S | Differentiates from all static competitors. |
| P1-5 | Personal hearing profile: in-app audiogram test or Mimi SDK import | S | Addresses Persona C; meaningful for users 35+. |
| P1-6 | Adaptive loudness — automatic volume leveling across tracks | S | User convenience. Competes with Apple's Sound Check. |
| P1-7 | Profile system: save/load named profiles, sync via iCloud | S | Enables device-switching workflow. |
| P1-8 | Genre detection / tagging integration for content-aware mode | C | Improve spectral classification by reading ID3 genre tags. |
| P1-9 | Apple Music / iTunes library integration (local files only, no streaming) | C | Surfaces local library without dragging files in. |
| P1-10 | A/B listening mode (bypass toggle with matched loudness) | C | Helps users perceive the enhancement — retention driver. |
| P1-11 | Basic analytics dashboard: listening time, enhancement deltas | C | Engagement / habit-formation feature. |
| P1-12 | System-wide audio (Phase 2 scope) | W | Keep gate between phases clean. |
| P1-13 | **Conversational Tuning — Class 1 (frequency-band requests)**: natural-language input mapped to EQ band adjustments ("bass too low," "too bright") | S | Zero-knowledge interface for Persona B. Requires text input field + phrase-to-band mapping layer. Interpretation architecture is a deferred open decision (see §7). |
| P1-14 | **Conversational Tuning — Class 2a (instrument EQ approximation)**: source-named requests ("I can't hear voices") mapped to the dominant frequency range of that instrument | S | Ships alongside P1-13. Uses a static instrument-to-frequency-range lookup; no source separation. Accuracy is approximate by design — document expectation clearly in UX copy. |
| P1-15 | **Conversational Tuning — discomfort/safety response**: phrases signalling pain or harshness trigger immediate protective attenuation before any confirmation | M (if P1-13 ships) | Non-negotiable safety behaviour. Must ship at the same time as P1-13; cannot be deferred independently. See §3a Safety Principle. |
| P1-16 | Conversational Tuning — session preference persistence and "reset all adjustments" control | S | Required for the feature to feel coherent across a session. Visual reset button + spoken "undo everything" equivalent. |

---

### Phase 2 — System-Wide Enhancement via Virtual Audio Device

**Goal**: Process audio from any app — Spotify, Apple Music, YouTube, Zoom — through the Adaptivity Engine. This is the full product vision.
**Architecture**: AudioServerPlugIn virtual device (reference: BlackHole, Background Music, eqMac). User sets "Adaptive Sound" as system output. The driver reads audio, pipes it to the companion DSP engine via Mach IPC, and writes to the real hardware device. Requires: Developer ID signing, notarization, Hardened Runtime, sudo install, `coreaudiod` restart.

**Non-trivial engineering gate**: The AudioServerPlugIn lives in `coreaudiod`'s process space, must be pure C/C++, cannot allocate on the audio thread, and must communicate with the UI process via Mach services declared in Info.plist. Plan 6–10 additional engineering weeks for driver stability before shipping. Reference: eqMac, BlackHole, libASPL.

#### Features

| # | Feature | Priority | Notes |
|---|---|---|---|
| P2-1 | Virtual audio device (AudioServerPlugIn) — intercept any app's output | M | The architectural foundation of Phase 2. |
| P2-2 | Installer with guided setup UX (sudo, coreaudiod restart, device selection) | M | UX must make the complexity invisible. Critical for Persona B adoption. |
| P2-3 | Auto-reconnect after OS update / coreaudiod restart | M | Reliability non-negotiable. |
| P2-4 | Per-app enhancement profiles (different settings for Spotify vs. Zoom) | S | SoundSource's core value — competitive necessity in Phase 2. |
| P2-5 | All Phase 1 adaptivity features applied system-wide | S | Content-aware, volume-aware, ambient — now work for all apps. |
| P2-6 | Low-latency mode for gaming / video calls (< 5 ms added latency target) | S | Without this, Zoom/Teams users will disable the driver. |
| P2-7 | macOS 14.4+ Core Audio process tap as capture alternative (read-only) | C | Supplementary. Capture-only; still needs virtual device for processing. |
| P2-8 | Spatial audio for video (movie/YouTube content) | C | Extend head tracking to non-music content. |
| P2-9 | CLI / API for pro users to script profile switching | C | Persona C power user feature. |
| P2-10 | Multi-output routing (e.g., headphones + HDMI simultaneously) | W | Complex driver edge case; defer. |
| P2-11 | iOS / iPadOS companion | W | Out of scope for Phase 2. |
| P2-12 | **Conversational Tuning — Class 2b (true ML source separation)**: instrument/source requests fulfilled by genuinely isolating the source signal before applying gain adjustment | C | Depends on a capable real-time source-separation model running on-device (Apple Silicon Neural Engine is the target platform). Computationally heavy. Delivers significantly more accurate "I can't hear the guitar" responses than the Phase 1 EQ approximation. Explicit open decision whether this is in-scope for Phase 2 or a later phase. |

---

## 5. Success Metrics / KPIs by Phase

### Phase 0 KPIs (Own-Player MVP)

| Metric | Target | Measurement Method |
|---|---|---|
| Private beta signups | 200+ before launch | Landing page waitlist |
| Day-7 retention (users still opening app) | > 50% | In-app analytics (anonymous, opt-in) |
| Session length (median) | > 25 minutes | In-app analytics |
| App Store / direct rating | > 4.3 stars | Store reviews |
| "Sounds better" self-reported (post-install survey) | > 70% | In-app NPS prompt at Day 3 |
| Crash-free sessions | > 99.5% | Crashlytics or Sentry |
| Audio thread underruns (dropouts) | < 0.1% of sessions | In-app counter, anonymous telemetry |
| GitHub stars (open-source repo) | Tracked; growth trend as adoption signal | GitHub Insights |
| Personal daily use by maintainer | Used as primary daily driver | Self-reported / qualitative |

### Phase 1 KPIs (Richer Adaptivity)

| Metric | Target | Measurement Method |
|---|---|---|
| HRTF spatial mode adoption | > 35% of active users | Feature-level analytics |
| Head tracking enablement rate (AirPods users) | > 50% | Feature-level analytics |
| D30 retention | > 40% | Cohort analysis |
| Personal hearing profile completion | > 25% of users | Funnel analytics |
| NPS score | > 45 | Quarterly in-app survey |
| Monthly active users (MAU) | 5,000+ | Analytics |
| GitHub contributors (open-source) | Tracked; any external contributor is a milestone | GitHub Insights |
| **Conversational Tuning — weekly active users of feature** | > 30% of Phase 1 active users | Feature-level analytics (count of sessions with at least one Conversational Tuning input) |
| **Conversational Tuning — phrase success rate** (user did not immediately undo or re-enter a correction) | > 75% | Event sequence analysis: input → [no undo within 60 s] |
| **Conversational Tuning — discomfort phrase response latency** (time from input submission to first attenuation applied) | < 300 ms | In-app instrumentation |
| **Conversational Tuning — Persona B discovery rate** (users who have never touched the manual EQ but have used Conversational Tuning) | Tracked; baseline to be set at launch | Segment analysis: Conversational Tuning users ∩ zero-manual-EQ-interactions |
| **Conversational Tuning — saved preference promotions** (session adjustments promoted to a named profile) | Tracked; baseline to be set at launch | Feature-level analytics |

### Phase 2 KPIs (System-Wide)

| Metric | Target | Measurement Method |
|---|---|---|
| Driver install success rate (first attempt) | > 90% | Installer telemetry |
| System-wide mode adoption among existing users | > 60% | Feature analytics |
| Added latency (P95) | < 5 ms | Internal measurement, user-reported |
| Driver-related crash rate | < 0.05% of sessions | Crash reporting |
| MAU | 20,000+ | Analytics |
| GitHub stars / forks | Tracked; growth trend as community adoption signal | GitHub Insights |

---

## 6. Project Model

Adaptive Sound is a **personal / open-source project**. It is free to use, free to share, and free to build on. There is no monetization, no pricing, no paywall, and no feature-gating of any kind. Every feature in every phase is available to everyone.

The choice of open-source license is **deferred until post-MVP** (after Phase 0). It does not need to be settled to build or privately test the MVP; it only needs to be in place before the repository is made public. Until then, treat the code as "source-available, license TBD."

---

## 7. Top Risks and Open Product Decisions

### Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Adaptivity Engine introduces audible artifacts or latency on the audio thread | High | Critical | Strict real-time thread rules (no allocation, no locks). Extensive A/B testing against bypass mode. Ship Phase 0 as validation gate before investing in Phase 2 driver. |
| Phase 2 virtual audio driver causes system instability / coreaudiod crashes | Medium | Critical | Reference BlackHole and eqMac's stability track records. Extensive beta testing. Auto-recovery mechanism. Clear user communication about the complexity. |
| macOS future OS updates break the AudioServerPlugIn ABI | Medium | High | Monitor Apple developer forums. Maintain fast release cadence for compatibility patches. |
| App Store sandbox blocks Phase 2 AudioServerPlugIn (technical constraint) | High | High | Direct notarized DMG is the required distribution path for Phase 2 — plan this from day one. App Store listing (if used) can still serve as a discovery page for Phase 0/1 and link to the direct download. Notarization and Developer ID signing are still required even for free distribution. |
| Apple Spatial Audio / AirPods improvements narrow the differentiation gap | Medium | Medium | Stay ahead on content-awareness and ambient adaptation — areas Apple has not addressed. Speed of iteration is the moat. |
| HRTF quality not compelling enough out-of-box with generic HRTFs | Medium | High | Invest in a high-quality default HRTF (MIT KEMAR or licensed). Offer personalization path. Ship A/B mode so users can directly compare. |
| User confusion about "why do I need to change my audio output?" (Phase 2 setup) | High | High | Dedicated onboarding flow. Auto-switching prompt. One-click guided installer. Study how eqMac handles this UX. |
| **Conversational Tuning — phrase interpretation produces a wrong or unexpected EQ move** | Medium | Medium | Ship a transparent "here is what I did" confirmation card after each adjustment so the user can see and undo the mapping. Log failure patterns from opt-in telemetry to iteratively improve phrase coverage. |
| **Conversational Tuning — discomfort phrase is not recognised quickly enough** | Low | High | Maintain a hard-coded priority list of known discomfort signals as an in-app safety layer, independent of the phrase-interpretation architecture. This list executes at the app level with no network round-trip. |
| **Conversational Tuning — Class 2b source separation model is too slow or power-hungry for real-time use on older Apple Silicon** | Medium | Medium | Gate Class 2b on Apple Silicon generation at runtime. M2 and later is the minimum viable target. M1 gets the Class 2a EQ approximation instead. |

---

### Open Product Decisions — Requires Founder Input

**Decision 1 — Monetization timing** ✓ **RESOLVED (LD-9): Not applicable.** This project is non-commercial. There is no paywall, no trial gate, and no paid tier in any phase. All features ship free.

---

**Decision 2 — HRTF strategy: Generic vs. personalized from day one?** ✓ **RESOLVED (LD-7): Choice A** — ship a quality generic HRTF (MIT KEMAR or similar) + a "listening preference" calibration. Custom/personalized HRTF deferred. Marketing must avoid any medical/audiological claim.

Choice A: Ship a single high-quality generic HRTF (MIT KEMAR or similar open-license IR) in Phase 1 and call it done for now. Fast, predictable. Some users will not find it compelling because HRTF is highly individual.
Choice B: Integrate an open or freely-licensable personalization SDK (e.g., Embody, or an open-source ear-shape pipeline) in Phase 1. Slower, requires evaluating whether any candidate SDK is compatible with an open-source project, but delivers significantly stronger spatial quality.

This decision affects the Phase 1 timeline and the perceived quality of the spatial audio feature at launch.

---

**Decision 3 — Distribution channels for Phase 2: App Store or direct-only?**

The Phase 2 virtual audio device (`AudioServerPlugIn`) cannot be installed inside the Mac App Store sandbox. This is a hard technical constraint that applies regardless of pricing. Phase 2 **must** ship as a notarized direct-download DMG with a guided installer (sudo + `coreaudiod` restart). Developer ID signing and Hardened Runtime are still required for notarization even though the app is free.

Distribution options for free / open-source release (open for founder to decide):

- **Choice A**: Direct notarized DMG download only — linked from the GitHub repository / project website. Simplest; full control over installer UX.
- **Choice B**: Phase 0–1 on the Mac App Store (free listing); Phase 2 as a direct-download DMG linked from the App Store listing description. Adds App Store discoverability.
- **Choice C**: Direct DMG + Homebrew cask (`brew install --cask adaptive-sound`). Convenient for developer / power-user audience who already uses Homebrew.

Choice C (Homebrew) is recommended for the open-source audience and can be combined with Choice B for broader reach. Choice A is sufficient to start.

---

**Decision 4 — Content classification: On-device ML model or DSP-only heuristics?** ✓ **RESOLVED (LD-5): Both, phased** — DSP heuristics (Choice A) ship in Phase 0; Core ML model (Choice B) layered in during Phase 1.

The Adaptivity Engine's content-awareness (detecting genre, energy, spectral profile) can be implemented two ways:

Choice A: Pure DSP heuristics — real-time FFT analysis, spectral centroid, RMS energy, dynamic range estimation. Zero ML runtime. Fully on-device, deterministic, no model maintenance. Less nuanced classification.
Choice B: Small on-device Core ML model (trained offline) for genre/mood classification, triggered every N seconds. Richer semantic understanding (e.g., "this is classical piano" vs. "this is electronic with heavy sub-bass"). Requires training data, model maintenance, and adds ~10–20 MB to app size.

This decision shapes the engineering sprint plan for Phase 0 (Choice A is faster) and Phase 1 (Choice B could be phased in).

---

**Decision 5 — Ambient noise sensing: Mic always-on or user-triggered?** ✓ **RESOLVED (LD-6): Choice B** — user-triggered on-demand sampling. No always-on mic in any phase.

Choice A: Mic is always listening (with explicit opt-in) when the app is running. Fully adaptive to real-time noise changes. Privacy-sensitive. Apple will show the orange mic indicator dot on macOS — this is visible and may concern users.
Choice B: User manually triggers "I am in a noisy environment" mode, or the app samples mic for 3 seconds on demand. Less invasive. Loses real-time ambient adaptation but avoids the continuous mic concern.

This is as much a trust/privacy decision as a product decision. Recommendation: Ship Choice B in Phase 0–1, offer Choice A as an opt-in "deep adaptation" mode with clear privacy disclosure.

---

**Decision 6 — Conversational Tuning: Is it a headline marketing feature or a supporting capability?** ✓ **RESOLVED (LD-8): supporting / discovery feature** for the Phase 1 launch — lead with spatial audio; let Conversational Tuning earn word-of-mouth and become a headline once phrase accuracy is proven.

Choice A: Lead marketing with Conversational Tuning at Phase 1 launch. Position Adaptive Sound as "the audio app you can just talk to." This creates a memorable, shareable demo moment and is likely the first product of its kind in the Mac audio space.
Choice B: Ship it as a useful but non-headlining feature. Lead marketing with spatial audio and HRTF (more tangible, easier to demo in a 15-second clip). Conversational Tuning is surfaced in onboarding and word-of-mouth, but not the lead story.

This is a positioning decision with downstream effects on the App Store listing, press pitch, and demo video. The feature differentiates regardless — the question is how loudly to announce it at launch.

---

**Decision 7 — Conversational Tuning: Session-scoped preferences by default, or saved by default?** ✓ **RESOLVED (LD-8): session-scoped by default + explicit save.** Note the refined model: instructions are governing principles within the session (see §3a behavioral model), not passive deltas.

Choice A: Adjustments are session-scoped by default (reset on next app launch). Users who want persistence explicitly save them. This keeps the engine's autonomous adaptation fresh for each session and avoids "stacking" corrections over time that the user forgets about.
Choice B: Adjustments persist across sessions by default (tied to the current device profile). Users who want a clean slate explicitly reset. This feels more like the app is "learning" the user's taste, which may improve perceived value — but risks accumulating adjustments that conflict with future automatic adaptation.

Recommendation: Choice A (session-scoped by default) with a prominent, low-friction "save these preferences" prompt shown after the first successful Conversational Tuning interaction. Re-evaluate based on usage telemetry after Phase 1 launch.

---

**Decision 8 — Conversational Tuning: Deferred architecture for phrase interpretation (OPEN — explicitly not decided)**

How the app understands and parses natural-language input — whether on-device, cloud-based, rule-based, or model-based — is an explicit open architecture decision. No recommendation is made here. This decision must be made before Phase 1 engineering begins on P1-13 and should be treated as its own scoping exercise, separate from the product requirements above. The product requirements are written to be architecture-agnostic; what the system does in response to a phrase is defined above; how it understands the phrase is not.

---

## Appendix: Phasing Summary

```
Phase 0 (Weeks 0-12):   Own-player MVP — prove the Adaptivity Engine
                         AVAudioEngine + C++ DSP + SwiftUI
                         No virtual device, no sudo, no streaming apps
                         Success gate: > 50% D7 retention, > 70% "sounds better"

Phase 1 (Weeks 13-36):  Spatial audio, personalization, ambient sensing
                         HRTF + head tracking + hearing profiles
                         Conversational Tuning (Class 1 + Class 2a + safety response)
                         All features free, open-source
                         Success gate: > 40% D30 retention, > 5,000 MAU,
                                       > 30% of users engaging with Conversational Tuning

Phase 2 (Weeks 37+):    System-wide via AudioServerPlugIn virtual device
                         All apps: Spotify, Apple Music, YouTube, Zoom
                         Direct-download DMG, guided installer
                         Conversational Tuning — Class 2b (ML source separation, if scoped in)
                         Success gate: > 90% driver install success, < 5 ms latency
```

---

*Document owner: Ramith (ramith@wso2.com). Next review: 2026-07-12. Approval required from founder before Phase 0 engineering kickoff.*
