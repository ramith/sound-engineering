# Product Requirements Document
## Adaptive Sound — Object-Based Spatial Music Renderer

**Status**: Draft v0.3 — aligned to architecture.md v0.3 (architecture is the source of truth)
**Date**: 2026-06-13
**Owner**: Product (ramith@wso2.com)
**Phase**: Concept-era vision doc (2026-06-13), **reframed 2026-07-05 to lead with the player-maturity-first thesis** (see §1 / §3 / §4). Build is well underway — current status & sprint sequencing live in [`../sprints/sprint-plan.md`](../sprints/sprint-plan.md) + [`backlog.md`](backlog.md). The vision, personas, KPIs, locked decisions, and risks remain the north star — now **sequenced behind the player, not abandoned**; treat phase/status specifics here as historical.
**Reconciled to the code:** 2026-10-13 (product council), against `main` at 7d7c2cd; re-checked 2026-10-14 after the R1 blocker fixes (PR #88). **R1 = v1.0.0-alpha — shipped 2026-10-14** (release PR #87, the council's blocker fixes PR #88; tag on e2d6037 — [release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha), [sprint-plan §Status](../sprints/sprint-plan.md#status), [release notes](../releases/v1.0.0-alpha.md)). The vision text below is unchanged; where the code now differs from a locked decision or a feature note, an *As-built* annotation says so and names the decision that changed it. Per-requirement status: [requirements.md §3.0](requirements.md#30-requirement-status-matrix). Per-story status and forward links: [backlog.md](backlog.md). Open defects: [known-issues.md](known-issues.md).

> **⚠️ Two "Phase" vocabularies — do not conflate.** This PRD's **Phase 0 / 1 / 1.5 / 2** is the *product-capability* axis: player MVP → mix-based core → stem object engine → system-wide. The **roadmap / sprint-plan** use **Phase 1 / Phase 2** for the *execution / release* axis: player-maturity parity → the differentiation pivot (S15–S18). They are **not** the same numbering. Rosetta: this PRD's "Phase 1 mix-core" and "Phase 1.5 stem engine" ship across execution **S15–S18** (roadmap Phase 2); this PRD's "Phase 2 system-wide" is **"Won't, this horizon"** on the execution roadmap. When in doubt, execution sequencing is authoritative in [`../sprints/sprint-plan.md`](../sprints/sprint-plan.md).

**Related Documents:**
- `docs/product/user-journeys.md` — detailed user journeys and workflows (authoritative reference)
- `docs/product/requirements.md` — detailed functional and non-functional requirements
- `docs/sprints/00-sprint-model.md` — sprint model, sequencing, and done-done criteria
- `docs/architecture/architecture.md` — technical architecture and design decisions (source of truth)

---

## 0. Locked Decisions (as of 2026-06-13)

These were confirmed with the founder and supersede any conflicting text below. LD-1…LD-10 were established in v0.1; LD-11…LD-17 were added in v0.2 to mirror architecture.md §0 (the canonical ADR registry). Open decisions still pending are listed in §7.

| # | Decision | Resolution | Affects |
|---|---|---|---|
| LD-1 | **Scope / phasing** | Start as a self-contained own-player (Phase 0), grow to system-wide via process tap (Phase 2). | Whole roadmap |
| LD-2 | **Meaning of "immersive"** | Both spatial (**BRIR-first**, see LD-14; crossfeed; head-tracking) **and** tonal/dynamic optimization, weighted equally. | §4 feature set |
| LD-3 | **Output targets** | Both headphones/AirPods **and** speakers; auto-detect device and switch profiles *(reconciled 2026-10-23: a recognised headphone is **offered** its correction with a level-matched hold-to-hear preview and the choice is remembered per output — never applied unheard; a profile is "correction + taste")*. | P0-5, P1-1, FR-SPAT/DEVICE |
| LD-4 | **MVP listening source** | **Local files only** in Phase 0. Streaming integration deferred to Phase 2 (platform reality — own-player cannot access Spotify/Apple Music PCM). | P0-1, P0-16 |
| LD-5 | **Content-aware brain** | **Phased**: DSP heuristics (FFT/spectral) ship in Phase 0; on-device Core ML genre/mood model layered in during Phase 1. | P0-2/3, P1-8 |
| LD-6 | **Ambient mic adaptation** | **On-demand sampling** (user taps "adapt to my environment"; mic samples ~3 s, then released). No always-on mic. | P0-11, P1-4 |
| LD-7 | **HRTF** | **BRIR-first** (see LD-14 — BRIR supersedes the generic-HRTF-only approach in LD-7 v0.1). Default binaural experience = BRIR (HRTF + early reflections + late reverb). Dry HRTF = "minimal" fallback mode. SADIE-II (Apache-2.0) remains the anechoic HRIR core inside the BRIR. | P1-1 |
| LD-8 | *Withdrawn 2026-07-12* | Natural-language / conversational tuning removed from scope (founder decision); may be re-added. |
| LD-9 | **Project model** | Personal / open-source, non-commercial. No monetization, pricing, paywall, or feature-gating of any kind. OSS license deferred to post-MVP. *As-built (2026-10-14): the repository is public and R1 shipped as a public GitHub release, with no licence file yet — see §6 and backlog US-REL-02.* *Decided 2026-10-14 (FD-7): **Apache-2.0**; the LICENSE file waits for release readiness.* | Whole doc |
| LD-10 | **Quality-first / ample use of modern hardware** | Maximize quality using all modern hardware: multi-core + GPU (Metal) + Neural Engine, fast SSD (aggressive caching/precompute), optional network assist for non-sensitive latency-tolerant work. Hard limits: per-buffer RT deadline; core playback stays offline-capable; privacy (mic on-device); battery/thermal. In own-player, latency is free → exploit look-ahead. Kernel exposes latency/quality budget (max-quality in player, bounded-latency in Phase 2). | NFR-PERF-02/03/04 |
| **LD-11** | **Source quality & non-goals** | Assume reasonably good sources (lossless / high-bitrate). **Audio repair/restoration is a non-goal** (no de-noise, de-clip, or upsampling to fix bad audio). Network may be used for non-sensitive, latency-tolerant work; **core playback + RT DSP stay offline-capable**. | §4, §7 |
| **LD-12** | **Perceptual tonal model** | Clarity/adaptive decisions are made in **ERB/Bark with a masking + partial-loudness model** (Moore-Glasberg style), not raw dB-on-log. Contributors are **typed** (EQ-curve + per-band dynamic + transient + spatial), not a single magnitude curve. The dB curve is a realization/interchange format only. | §4, Arbiter design |
| **LD-13** | **Phase realization = minimum-phase by default** | Phase mode is chosen by **content** (transient density from pre-analysis); linear/mixed-phase is opt-in or band-limited where it genuinely helps. Pre-ringing (not latency) is the real cost. | §4 DSP, P1-DSP |
| **LD-14** | **BRIR-first immersion** | Headphone spatialization defaults to a **binaural room response** (HRTF + early reflections + late reverb); dry HRTF is a "minimal" mode. Head-tracking is opt-in for music. Speaker immersion = M/S width + ambience extraction (mono-safe); crosstalk-cancellation is opt-in (centered near-field only). Crossfeed opt-in. | P1-1, P1-3, §4 spatial |
| **LD-15** | **Stem-based object engine (Phase 1.5)** | Offline **6-stem** separation (vocals/drums/bass/guitar/piano/other), cached to SSD. Full **per-stem chains including spatial placement**, re-summed to binaural. Masking computed **between stems**. **Own-player-only** — the live tap path (Phase 2) is mix-level only; real-time-lite separation is a research track. | §4 Phase 1.5, P1.5-1…6 |
| **LD-16** | **"Reimagine" intensity knob** | One continuous control: **0% = original mix, stem engine bypassed (bit-faithful, zero separation artifacts)** → rising = clarity → spatial widening → **100% = full stem-based spatial reimagining**. Crossfades original↔stem-render + scales spatial spread / unmask depth. Mix-range in Phase 1; stem-range unlocked in Phase 1.5. *As-built (Sprint EQ decision 25, 2026-10-10, PR #73): the user's EQ plays in full ahead of the knob, which scales only the adaptive enhancement; bit-faithful = **0 % with the EQ Off**, or Pure Mode.* | §3b, P1-17, P1.5-7 |
| **LD-17** | **Dynamics & loudness** | **No program DRC by default** (transparent LUFS normalization + true-peak safety limiter only). Loudness compensation = **fraction of the equal-loudness contour difference** (ISO 226) + per-device SPL calibration + loudness-matched makeup, **rate-limited to volume changes only**. *(Reconciled 2026-10-23, founder: the "per-device SPL calibration" is a one-time "this is my normal loud setting" reference per output; the curve is **bass only** (nothing above 1 kHz — no treble lift), starts at 50 % of the difference, capped at +6 dB, applied by easing the mids so it never boosts; leveling is one fixed gain per track or album to **−18 LUFS**, in both modes, and the old session-long auto-leveller is removed; backlog US-TON-03, US-R1F-10.)* | §4 dynamics, P1-6 |
| **LD-18** | **Target hardware & runtime posture** | **Floor = Apple-Silicon Pro-class (M1 Pro, 2021) / ≥16 GB**; the shipping generation is far above it — **M4** (38-TOPS NE, ~120 GB/s) → **M4 Pro/Max** (10–12 P-cores, 273–546 GB/s, 64–128 GB) and **M5** (per-GPU-core neural accelerators, ~4× M4 GPU-AI compute, 153 GB/s base). The app is the **foreground, primary activity** ("lean-back listening"), free to **use many cores and occupy memory generously**. Net: the Phase-1.5 render has **large headroom on current hardware**; design for the M1 Pro floor and exploit the abundance above it. Supersedes the base-8 GB-Air framing; **downgrades Risk R-3 to Low**. Degrade gracefully if backgrounded. **Power:** default max-quality on AC; auto-lighter (Efficiency profile) on battery — user-overridable. | §15, NFR-PERF-06, R-3, personas |
| **LD-19** | **App shape** | A focused **full-window lean-back listening app** (now-playing + scene visualizer + Reimagine dial) **plus a menu-bar extra** for quick control. Both surfaces share one engine. *As-built (R1): five tabs (Now Playing, Library, EQ, Monitoring, Settings) in Liquid Glass, dark and light; the menu-bar extra has transport only (PR #25) — no Reimagine dial or volume there yet.* | FR-UI |

---

## 1. Product Vision & Positioning

### One-Line Vision

> Turn any good-quality song into a personal, perceptually-tuned, spatially-rendered mix.

### Near-term thesis vs. long-horizon vision *(sequencing — 2026-06-19 founder review)*

The one-line vision above is the **north star** — *sequenced behind the player, not abandoned.* The identity we build and release **first** is a **mature, bit-perfect audiophile player**: *this Mac → this DAC, bit-perfect*, with the library, browse, queue, tags, media-keys, headphone-correction and loudness maturity that Roon / Audirvana / foobar2000 / JRiver set as table stakes (and that Apple Music does **not** deliver bit-perfect on macOS). Only on that credible base do we layer the differentiation — masking-aware perceptual clarity, the steerable Reimagine knob, spatial rendering, and (long-horizon) per-stem control. An audiophile player lives or dies on library + playback maturity, not its cleverest DSP: we earn parity, then we differentiate. Detailed sequencing: [`../sprints/sprint-plan.md`](../sprints/sprint-plan.md).

### What Adaptive Sound Is

Near-term, Adaptive Sound is a **bit-perfect audiophile music player** for macOS — a real library player (scan, browse, search, queue, tags, cover art, media keys, gapless) that drives your DAC **bit-exact** (CoreAudio HAL-direct, hog mode, per-track sample-rate match). That mature player is the near-term product and the foundation everything else stands on.

> **As-built (R1, v1.0.0-alpha, 2026-10-13):** this paragraph is now what ships — music folders with live updates, Songs / Albums / Artists / Genres with filter and sort, playlists, a persistent queue with shuffle / repeat and Recently Played, cover art, media keys and Control Center, gapless, Pure Mode (HAL-direct, hog mode, per-track rate; `HALOutputEngine`), a 31-band graphic EQ, loudness normalisation and a safety limiter. Not in R1: tag **editing** (tags are read, not written), CUE sheets, headphone correction and loudness compensation (S11–S14 → R2). macOS 26 on Apple Silicon; the build is not notarized yet.

On that base it grows into an **object-based spatial music renderer** — the long-horizon differentiation, layered in once the player is credible. That layer does two things:

1. **Perceptual clarity** — a masking-aware, ERB/Bark tonal engine ensures every element of the recording is actually audible at the playback level and device in use. *(Phase 2 — S15–S16.)*
2. **Spatial rendering** — BRIR-first binaural reproduction (HRTF + early reflections + late reverb) places the mix in a convincing acoustic space on headphones; M/S width + ambience extraction on speakers. *(Phase 2 — S18.)*

### Positioning Statement

For **audio-conscious Mac users** who want to hear their music the way it was meant to sound — not the flattened, device-compromised version their hardware delivers by default — **Adaptive Sound** is, near-term, a **mature, bit-perfect audiophile player** (*this Mac → this DAC, bit-perfect* — which Apple Music is not on macOS), and, long-horizon, an **object-based spatial music renderer** that turns any good-quality song into a personal, perceptually-tuned mix. Unlike static equalizers (eqMac), one-size "3D" effects (Boom 3D), or Apple's Spatial Audio Foundation (ASAF) — which applies fixed post-decode processing — Adaptive Sound **adapts continuously** to audio content, playback level, and output device.

### The Reimagine Knob — Reconciling Fidelity and Transformation

The central user-facing control is a single **Reimagine intensity knob**:

| Intensity | Experience |
|---|---|
| **0%** | **Bit-faithful bypass.** Original mix, stem engine off, zero separation artifacts. "Hear exactly what was recorded." |
| Low (mix range) | Subtle masking-aware clarity + gentle BRIR externalization. Sources remain near original positions. |
| Mid (mix range) | Audible clarity gains + spatial widening. Mix placed in a convincing virtual room. |
| High (stem range, Phase 1.5+) | Full per-stem reimagining: each stem placed independently in the spatial field, aggressive unmasking and rebalancing. |
| **100%** | **Full spatial reimagining.** Maximum transformation — artifacts accepted at this extreme; quality-gated. |

The knob is the honest single control spanning fidelity to transformation. It replaces the "on/off enhancement" framing with a continuous dial the user owns.

### Durable Moat

Apple's Spatial Audio Foundation (ASAF) applies **static, post-decode** binaural processing. Adaptive Sound's moat is three-layered and continuous:

- **Content-adaptive**: processing responds to what is actually playing — spectral balance, transient density, dynamic range — on every buffer.
- **Personalized**: per-device correction.
- **System-responsive**: playback level, ambient noise, battery/thermal mode all feed the engine.

None of this is available to a static post-decode pass. The stem object engine (Phase 1.5) adds a fourth layer: **per-instrument spatial placement** that no static profile can replicate.

---

## 2. Target Personas

### Persona A — "The Audiophile Commuter" (Primary)

**Profile**: Marcus, 31, software engineer. Owns Sony WH-1000XM5 or AirPods Pro. Commutes by train and works from coffee shops. Listens to lo-fi, jazz, and electronic music 3–5 hours per day on a MacBook Pro.

**Pain**: Headphones sound flat at low volume in a quiet cafe, then harsh and fatiguing at high volume on a noisy train. Manual EQ fiddling in eqMac is tedious. He knows his headphones are capable of more.

**Job to be Done**: "When I press play, I want it to sound great right now — not after I spend 20 minutes tweaking sliders."

**What they value**: Immediate, effortless improvement with zero configuration overhead. Will abandon on any noticeable latency or dropout.

**Where Adaptive Sound specifically serves Marcus:**
- **BRIR immersion (LD-14)**: his headphones get a convincing soundstage externalized out of his head — ASAF gives him a fixed stage; we adapt it to content and level continuously.
- **Reimagine knob (LD-16)**: at a moderate setting he gets spatial improvement without touching anything; he can pull it back to 0% on commutes when he wants pure fidelity.

---

### Persona B — "The Developer-Audiophile" (Primary — and the maker)

**Profile**: Ramith, software developer and audio enthusiast; owns an Apple-Silicon Mac from the M1 generation **and** a current M4. Listens widely on good headphones and capable Macs; cares about both fidelity *and* immersion; comfortable with technical controls but wants results — not an afternoon of slider-tweaking. He is building this **for himself first** (personal / open-source — LD-9), so the product is tuned to his ears and his hardware.

**Pain**: Existing tools are static EQs (eqMac) or one-size "3D" effects (Boom 3D); none adapt to the content, and none turn a stereo track into a placeable spatial mix. He has abundant hardware headroom (M1 Pro → M4) and wants software that actually **spends it on quality**.

**Job to be Done**: "Turn any good track into the most immersive, clear version of itself on my gear — instead of a static preset."

**What they value**: Maximal quality that exploits modern Apple Silicon; control and transparency when wanted; a bit-faithful anchor he can trust; open-source.

**Where Adaptive Sound specifically serves Ramith:**
- **Stem-based spatial reimagining (LD-15, LD-18)**: his M1 Pro / M4 Macs have the headroom to separate a track and place its stems in a virtual room — the signature experience.
- **Reimagine knob (LD-16)**: one dial from 0% (bit-faithful — "hear exactly what's recorded") to full spatial reimagining — fidelity and transformation on a single honest axis.
- **Quality-first / ample hardware (LD-10, LD-18)**: the engine uses many cores + memory generously on his hardware rather than playing it safe.

---

### Persona C — "The Home Studio Hobbyist" (Secondary)

**Profile**: Tom, 38, musician and weekend producer. Uses Audio-Technica ATH-M50x studio headphones. Switches between headphone mixing, reference listening, and YouTube tutorials constantly. Runs Ableton on the same machine.

**Pain**: Studio headphones are flat and analytical for casual listening. Sonarworks SoundID works only inside the DAW. He wants a globally-active correction profile across every app.

**Job to be Done**: "I want my reference headphones to sound like they were tuned for enjoyment everywhere, not just inside my DAW."

**What they value**: Technically credible, globally-active correction. Respects well-documented tools; will read the release notes.

**Where Adaptive Sound specifically serves Tom:**
- **BRIR immersion + per-stem spatial placement (LD-14, LD-15)**: Phase 1.5 lets him hear stems placed spatially in the virtual room — a reference-quality experience he cannot get in casual listening anywhere else.
- **Reimagine knob at 0% (LD-16)**: when referencing for mixing, he pulls to 0% for a verified bit-faithful bypass, then dials back up for enjoyment listening.
- **Phase 2 system-wide**: the correction profile he trusts in the own-player follows him to Spotify, YouTube, and Zoom.

---

## 3. Value Proposition & Competitive Differentiation

> **Sequencing note (2026-06-19).** Near-term, the competition we must first match is the **mature audiophile players** — Roon, Audirvana, foobar2000, JRiver — on library, playback, and **bit-perfect** fidelity (our *this Mac → this DAC, bit-perfect* story; Apple Music is not bit-perfect on macOS). The continuous-adaptation differentiation described below — and the comparison table against static enhancers (eqMac, Boom 3D, ASAF) — is the **long-horizon moat** we build **on top** once player parity is reached (Phase 2), not the near-term wedge.

### Core Value Proposition

Adaptive Sound is the only Mac audio enhancer that continuously re-renders music to your current context. The engine adjusts processing in real time across four dimensions simultaneously: audio content (spectral, dynamic, transient), ambient environment, output device, and playback volume. The result feels effortlessly perfect rather than technically configured.

### 3a. Feature Definition — Conversational Tuning

> **Withdrawn 2026-07-12** — natural-language / conversational tuning removed from scope (founder decision). Prior spec in git; may be re-added.

---

### 3b. The Reimagine Knob — Product Design Principle

The Reimagine intensity knob is the primary user-facing control for transformation depth. It is **not** an effects preset or a quality switch — it is a continuous spectrum from **"hear exactly what was recorded"** to **"hear the recording reimagined for your headphones."**

Design principles:
- **0% is a first-class listening mode.** It is not a "disable processing" fallback. At 0%, the audio path is verified bit-faithful (MD5-equal bypass, per NFR-QUAL). This is the anchor that earns user trust for higher settings. *(Amended by Sprint EQ decision 25, 2026-10-10: the knob used to blend the EQ with the dry signal, so below 100 % the EQ graph lied. Now the EQ always plays in full and the knob scales only the enhancement; the bit-faithful anchor is "0 % **with the EQ Off**" — the tooltip reads "0 % — Reimagine off (your EQ still plays)". ~~The default is 20 %.~~ The default is **0** (FD-2, 2026-10-14), and the control is hidden until S17. **Reconciled 2026-10-23:** Intensity scales only the automatic stages — Clarity depth and the spatial room amount — as settings inside each stage, never as a crossfade and never over a switch the listener set by hand; 0 = nothing automatic, and stages the listener set by hand still play.)*
- **The knob is the only control most users need.** Below the knob, the engine works automatically. Above, stems give expert users more resolution.
- ~~**Default should sit in the low-to-mid mix range.** Enough improvement to be immediately noticeable; far enough from the stem range that separation artifacts are never an out-of-box surprise.~~ **Default is 0 (faithful by default; FD-2, reconciled 2026-10-23).** A fresh launch plays the file as recorded; the listener raises the automatic stages — or presses Enhance (backlog US-UI-08) — and nothing is applied that did not win the founder's blind, level-matched A/B.
- **Phase 1 mix range and Phase 1.5 stem range are a single continuous control.** The ceiling raises when stems are available; the UX does not change.

---

### Competitive Comparison Table

| Capability | Adaptive Sound | eqMac | Boom 3D | SoundSource | Sonarworks SoundID | Apple Spatial Audio (ASAF) |
|---|---|---|---|---|---|---|
| System-wide processing | Phase 2 (process tap primary, no driver; libASPL fallback) | Yes (driver) | Yes (driver) | Yes (driver) | DAW only | AirPods / system (static) |
| Own-player mode (no driver) | Phase 0 MVP | No | No | No | No | No |
| Adaptive / real-time adjustment | Yes — continuous, content-driven | No — static | No — static | No — static | No — static | No — static post-decode |
| Content-aware EQ (spectral + genre) | Yes (ERB/Bark perceptual model, LD-12) | No | No | No | No | No |
| Volume-aware EQ (equal-loudness comp) | Yes (fractional contour diff, LD-17) | Manual | No | No | No | No |
| Ambient noise sensing (mic) | Yes (on-demand, LD-6) | No | No | No | No | No |
| **Object-based / per-stem spatial rendering** | **Yes (Phase 1.5, LD-15)** | No | No | No | No | No |
| BRIR binaural (HRTF + room) | Yes (default, LD-14) | No | Basic "3D" | No | No | HRTF-only / static ASAF |
| Head tracking (AirPods motion) | Yes (opt-in, LD-14) | No | No | No | No | Yes |
| Headphone correction profiles | Yes | No | No | No | Yes (excellent) | No |
| Speaker auto-detection + switch | Yes | Manual | Manual | Manual | No | No |
| **Reimagine intensity knob (fidelity → spatial remix)** | **Yes (Phase 1 mix range; Phase 1.5 stem range, LD-16)** | No | No | No | No | No |
| macOS driver required | **Phase 2: no driver primary** (process tap, macOS 14.2+); libASPL fallback only | Yes | Yes | Yes | No | No |
| Continuous adaptation (vs. static post-decode) | **Yes — adapts every buffer** | No | No | No | No | **No — static post-decode** |
| Price | Free / open-source | Free | $19.99 | $39 | $99/yr | Free (Apple ecosystem) |

> **As-built (R1) — read the "Adaptive Sound" column as the target, not the shipped product.** Of its rows, R1 has: own-player mode, the Reimagine knob's primitive, crossfeed, a manual EQ with presets and per-output memory, loudness normalisation, and free / source-available distribution. **Not built yet:** adaptive / content-aware / volume-aware processing (S14–S17), ambient sensing, BRIR and head tracking (S18 / unscheduled), headphone correction (S12–S13), speaker auto-switching, system-wide processing (Won't, this horizon). What R1 does have that the table does not list is the near-term wedge of §1: a bit-perfect Pure Mode and a real library.

**Sharp differentiation in one sentence**: Every competitor — including Apple's Spatial Audio Foundation — applies a fixed, static profile decided at setup; Adaptive Sound continuously re-renders every buffer to your current audio, volume, and device.

---

## 4. Prioritized Feature Set by Phase

> **⚠️ Sequencing reconciliation (2026-06-19 founder review — read first).** This section's Phase 0/1/1.5/2 scheme predates the current, founder-reviewed execution plan in [`../sprints/sprint-plan.md`](../sprints/sprint-plan.md). The **feature detail below is preserved as the product's north star**, but the *order in which it ships* is now player-maturity-first:
> - **Phase 0 player MVP + the tonal / loudness / device parity work** → the **Phase 1 maturity arc (S8–S14)**, built **library-spine-first**. Loudness compensation (ISO-226) ships here (S14) as the lowest-risk first taste of the adaptive thesis.
> - **Reimagine mix-range mapping + masking-aware clarity + BRIR spatial** → **Phase 2 (S15–S18)**, the differentiation layer. *(The Reimagine intensity knob, crossfeed, and tonal presets already shipped early in QW1.)*
> - **Stem-based object engine (Phase 1.5)** → **"Won't, this horizon"** — revisit only after the mix-based thesis is validated and loved.
> - **System-wide via process tap (Phase 2 below)** → **"Won't, this horizon"** — a different product surface; our story stays *this Mac → this DAC, bit-perfect*.
>
> The MoSCoW priorities below are within-phase *engineering* priorities as originally conceived, not the current ship order.

### Prioritization Scheme: MoSCoW

- **M** (Must Have): Ship-blocking. The phase is unusable without it.
- **S** (Should Have): High user value, ship in the phase if feasible.
- **C** (Could Have): Nice to have; defer if schedule is tight.
- **W** (Won't Have this phase): Explicitly out of scope — documented to prevent scope creep.

---

### Phase 0 — Local-File Player MVP (DSP Spine)

**Goal**: Prove the DSP spine end-to-end. Ship fast with zero driver complexity.
**Architecture**: AVAudioEngine + one custom AUAudioUnit v3 (C++ DSP kernel) + SwiftUI. Swift/C++ interop. No virtual audio device, no sudo, no driver complexity. Passthrough → first DSP as the gate.

#### Features

| # | Feature | Priority | Notes | As-built (2026-10-13) |
|---|---|---|---|---|
| P0-1 | Local file playback (FLAC, ALAC, MP3, AAC, WAV) | M | The player shell. AVAudioEngine for decode, format/SR conversion, device routing. | **Shipped (R1)** — library scan + Apple / optional-FFmpeg decode (S8 PR #15, PR #85). No single-file open (backlog US-LIB-02 → R1.1-B); `.opus` unscanned (→ ~~S11~~ R1.1-A, 2026-10-14). |
| P0-2 | Real-time spectral analysis of playing content | M | FFT via vDSP. Foundation of content-aware EQ. Meters + loudness up via seqlock/ring to UI at ≥30 fps. | **Shipped** — analyzer lens at 20 Hz + per-channel Monitoring (S10.7 PR #61, Sprint G PR #85). It feeds the display only; no adaptive EQ consumes it. |
| P0-3 | Content-aware adaptive EQ — auto-adjusts bands per spectral profile | M | Core differentiator. ERB/Bark perceptual domain (LD-12) in pre-analysis; first DSP results here. | **Not built** → S15–S16 (masking / Clarity). Content classification itself is unscheduled. |
| P0-4 | Volume-aware EQ (equal-loudness compensation) | M | Fractional equal-loudness contour difference per LD-17 *(2026-10-23: bass only, ease-the-mids form, follows the volume where the Mac can read it)*. Immediate "wow" for Persona B. | **Not built** → S14-lite. |
| P0-5 | Output device auto-detection (headphones vs. speakers) | M | Via `kAudioHardwarePropertyDefaultOutputDevice`. Switch profiles on plug/unplug. | **Partial** — pick or follow the output, pause on loss, return to the chosen output when it reconnects (in-session), per-output EQ (PR #73, #85, #88). Headphone-vs-speaker detection is transport-only (known issue KI-DEV-01) → S13. |
| P0-6 | Built-in device preset library (Mac built-in speakers, AirPods, Sony, Bose, Sennheiser top models) | S | ~20 presets covering common output devices. Offered, with a preview, when the headphone is recognised — never applied out of the box (2026-10-23). | **Not built** → S13 (7 tonal presets exist; no device presets). |
| P0-7 | Manual EQ override with real-time visualization | S | Escape hatch for Persona C. Typed contribution; does not replace the engine. | **Shipped** — accurate 31-band graphic EQ + Tone macros + played-curve graph (Sprint EQ, PR #73). |
| P0-8 | Basic crossfeed (reduce stereo separation for headphones) | S | Reduces listening fatigue. Opt-in per LD-14. | **Shipped** — in-house Bauer crossfeed, off by default (QW1, PR #15). |
| P0-9 | Playback queue, basic library view, drag-and-drop | S | Minimum viable player UX. | **Shipped (R1)** — library, browse, search, persistent queue, playlists (S8–S10.3: PR #15, #17, #23, #53, #54, #59, #60); drag onto playlists. No Finder file drop. |
| P0-10 | True-peak safety limiter + LUFS normalization | M | Per LD-17: transparent normalization + ≥4× oversampling limiter (−1 dBTP, ~1 ms look-ahead, ITU-R BS.1770-5). Non-optional. | **Shipped** — 8× oversampled limiter + BS.1770 normalisation (Sprint 4, PR #14); EQ-only ceiling −0.1 dBTP on wired outputs (decision 29, PR #73). |
| P0-11 | Psychoacoustic bass enhancement (device/SPL-gated) | C | Mono-sum NLD (avoids Waves US-11,102,577 per §7 patent risk). Gate on transducer capability. IP review required before release. | **Not built**; unscheduled (backlog US-TON-04). |
| P0-12 | Ambient noise sensing via built-in mic (on-demand, ~3 s sample) | C | LD-6: on-demand only. Requires mic-permission UX. Can defer to Phase 1. | **Not built**; unscheduled (no microphone code). |
| P0-13 | Head tracking via AirPods motion | W | Phase 1. | Not built; unscheduled. |
| P0-14 | BRIR binaural rendering (full spatial) | W | Phase 1 (LD-14). | Not built → S18. |
| P0-16 | Streaming service integration | W | Phase 2 (requires system-wide process tap). | Won't, this horizon. |
| P0-17 | System-wide audio processing | W | Phase 2 (process tap primary; libASPL fallback) — explicitly deferred. | Won't, this horizon. |
| P0-18 | Windows / cross-platform | W | Not in roadmap. macOS-only. | — |

**What is explicitly NOT in Phase 0**: Any virtual audio device, sudo/install step, system-wide processing, streaming app integration, BRIR convolution, stem separation. Phase 0 is a music player with a smart DSP brain and a verified bypass mode.

---

### Phase 1 — Mix-Based Core

**Goal**: Ship the full mix-level immersive and adaptive story. Perceptual clarity/correction, BRIR immersion, adaptive engine, loudness-comp, and the Reimagine knob (mix range).
**Architecture**: All Phase 0 plus CMHeadphoneMotionManager (head tracking, macOS 14+), BRIR convolution engine (room synthesis or CC0/CC-BY IRs; libmysofa BSD-3; vDSP/FFTConvolver MIT), full Arbiter (typed contributors, ERB/Bark, masking model), off-RT Realizer (min-phase biquad default; FIR opt-in).

#### Features

| # | Feature | Priority | Notes | As-built (2026-10-13) |
|---|---|---|---|---|
| P1-1 | **BRIR binaural rendering** — virtual soundstage externalized outside the head | M | LD-14 default. HRTF + early reflections + late reverb (room synthesis or CC0/CC-BY IRs). SADIE-II HRIR as anechoic core. libmysofa + vDSP/FFTConvolver. | **Not built** (pass-through stub) → S18. |
| P1-2 | Head tracking via AirPods motion (opt-in) | M | CMHeadphoneMotionManager, macOS 14+. Opt-in per LD-14. | **Not built**; unscheduled. |
| P1-3 | Dry HRTF "minimal" mode (crossfeed opt-in) | S | Per LD-14: BRIR is default; dry HRTF is the minimal fallback for users who prefer less room. | **Not built** → after S18. (Crossfeed shipped — P0-8.) |
| P1-4 | Ambient noise sensing via mic — adapts EQ/dynamics to room noise floor | S | On-demand per LD-6. | **Not built**; unscheduled. |
| P1-6 | Adaptive loudness — LUFS normalization across tracks + loudness-matched makeup | S | LD-17: fraction of equal-loudness contour diff; rate-limited to volume changes; a one-time reference level per output (not an SPL model) *(2026-10-23)*. | **Partial** — LUFS normalisation shipped, with per-track load-time analysis (PR #14, #73); the equal-loudness part → S14. *(2026-10-14, FD-2: leveling goes off by default in R1.1-A and becomes its own setting — Off / Album / Track — in R1.1-B; S14 runs first in R2, as S14-lite.)* |
| P1-7 | Profile system: save/load named profiles, iCloud sync | S | Device↔profile binding (per architecture §14). | **Not built** — per-output EQ memory + My Presets only (PR #73) → S13 (JSON). iCloud sync: Won't, this horizon. |
| P1-8 | Genre / mood detection (Core ML, on-device) | S | LD-5: layered in during Phase 1. vDSP feature analysis (BPM/key/spectral) per ADR-005. | **Not built**; unscheduled. |
| P1-9 | Apple Music / iTunes library integration (local files only, no streaming) | C | Surfaces local library without drag-and-drop. | **Not built**; unscheduled. The app has its own folder-based library instead (S8). |
| P1-10 | A/B listening mode (bypass toggle with matched loudness) | S | Helps users perceive the enhancement. Bypass = Reimagine at 0% (bit-faithful per LD-16). | **Partial** — the EQ's hold-to-Compare, loudness-fair (decision 28, PR #73). *(2026-10-23: no whole-chain A/B toggle — Compare means "without my EQ", level-matched within 0.2 dB over every offset; a separate latching "Bypass all processing" plays the file as recorded → S12.)* |
| P1-11 | Basic analytics dashboard: listening time, enhancement deltas | C | Engagement / habit-formation. | **Not built**. Nearest: Recently Played with play counts (S10.6, PR #57). |
| P1-12 | Speaker immersion: M/S width + ambience extraction (mono-safe) | S | LD-14 speaker path. Hard mono-compatibility. Crosstalk-cancellation = opt-in near-field only. | **Not built**; unscheduled. |
| P1-17 | **Reimagine intensity knob (mix range, 0%–~60%)** | M | LD-16. 0% = bit-faithful bypass (verified MD5-equal), the default. Rising = more Clarity depth and room amount, as settings (never a crossfade; 2026-10-23). Stem range ceiling unlocked in Phase 1.5. Single most prominent user control. | **Partial** — the knob and its blend shipped (QW1); it scales only the adaptive enhancement, and bit-faithful now means 0 % **with the EQ Off** (decision 25, PR #73). Mapping → S17. |
| P1-18 | System-wide audio (Phase 2 scope) | W | Gate between phases clean. | Won't, this horizon. |

---

### Phase 1.5 — Stem-Based Object Engine  *(now sequenced as "Won't, this horizon" — see the §4 reconciliation note)*

**Goal**: Unlock the full spatial reimagining story via per-stem rendering. This phase is **gated on a performance/feasibility spike** (see §7) that must complete before Phase 1.5 engineering begins.
**Architecture**: All Phase 1 plus offline 6-stem Demucs/HTDemucs separation (Core ML / MLX, MIT weights), per-stem DSP chains, extended Arbiter (between-stem masking), Reimagine knob stem range.

**Tuning spike (before Phase 1.5 kickoff)**: measure per-stem RT cost, memory for 6 cached stems + BRIR kernels, and worst-case render budget on the **M1 Pro / 16 GB floor** (LD-18; sole-occupancy). Sets per-tier QualityProfile caps and confirms Audio Workgroups fan-out. Given the raised floor + current-gen headroom (M4/M5 ~3–4× the floor), this is a **tuning exercise, not a go/no-go**. See §7 Risk R-3 and architecture.md §15.

#### Features

| # | Feature | Priority | Notes |
|---|---|---|---|
| P1.5-1 | **Offline 6-stem separation** (vocals/drums/bass/guitar/piano/other) | M | Demucs/HTDemucs via Core ML / MLX (MIT). On add/first-play, run offline (GPU/ANE, ~seconds/track), cache stems to SSD. |
| P1.5-2 | **Per-stem DSP chains** (EQ + dynamics + spatial placement per stem) | M | Each stem runs its own typed contributor chain. Re-summed to binaural via BRIR. |
| P1.5-3 | **Per-stem spatial placement in BRIR field** | M | Stems placed as objects in the virtual room. This is the headline Phase 1.5 capability. |
| P1.5-4 | **Between-stem masking / unmasking** | M | Masking computed between stems in ERB/Bark. This is where the true clarity gain over mix-level processing lives. |
| P1.5-5 | **Quality-gating and graceful fallback** for low-confidence separations | M | 6-stem (esp. guitar/piano) is least-robust. "Other" as catch-all. Fallback to fewer stems or mix-level processing if separation quality threshold not met. |
| P1.5-7 | **Reimagine intensity knob — stem range (0%–100%)** | M | LD-16: Phase 1.5 raises the ceiling. Rising from mix-range ceiling → stem placement → aggressive unmask/rebalance → 100% full reimagining. Crossfades original↔stem-render. |
| P1.5-8 | Per-stem manual controls (optional level / mute / solo per stem) | C | Expert/Persona C feature. Expose only if UX complexity budget allows. |
| P1.5-9 | Real-time-lite separation (research track) | W | Architecture §6: not in scope for Phase 1.5. Remains a research track. |

**Own-player-only**: All Phase 1.5 stem features apply in the own player only. The Phase 2 process-tap path is mix-level by design (LD-15).

---

### Phase 2 — System-Wide (Process Tap)  *(now sequenced as "Won't, this horizon" — different product surface; see the §4 reconciliation note)*

**Goal**: Process audio from any app — Spotify, Apple Music, YouTube, Zoom — through the same kernel. Mix-level only (stem features remain own-player-only).

**Architecture — primary path (macOS 14.2+)**: Core Audio process taps (muted global tap + private aggregate device). Same C++ DSP kernel, BoundedLatency QualityProfile. No HAL plug-in, no privileged helper, no sudo, no `coreaudiod` restart. Competitive advantage vs. eqMac, Boom 3D, SoundSource (all require a driver).

**Architecture — fallback path**: AudioServerPlugIn virtual device (libASPL, MIT) for older macOS or where a persistent selectable output device is needed. Requires Developer ID signing, notarization, Hardened Runtime, SMAppService privileged helper, sudo install, `coreaudiod` restart. Plan 6–10 additional engineering weeks for fallback stability.

#### Features

| # | Feature | Priority | Notes |
|---|---|---|---|
| P2-1 | System-wide audio capture via **Core Audio process tap** (primary) | M | macOS 14.2+ required. No driver install, no sudo. BoundedLatency profile. Mix-level processing only. |
| P2-2 | Guided setup UX for process-tap path (screen-recording / audio-capture permission) | M | UX must make permission grant feel trustworthy. Critical for Persona B adoption. |
| P2-3 | Auto-reconnect after OS update or permission revocation | M | Reliability non-negotiable for both tap and fallback paths. |
| P2-4 | Per-app enhancement profiles (different settings for Spotify vs. Zoom) | S | Competitive necessity in Phase 2. |
| P2-5 | All Phase 1 mix-level adaptivity features applied system-wide | S | Content-aware, volume-aware, BRIR — now work for all apps. |
| P2-6 | Low-latency mode for gaming / video calls (< 5 ms added latency target) | S | Without this, Zoom/Teams users will disable processing. |
| P2-7 | **Fallback: AudioServerPlugIn virtual device** (libASPL) for older macOS | S | Driver path. Includes installer with sudo + coreaudiod restart. |
| P2-8 | Spatial audio for video (movie/YouTube content) | C | Extend BRIR immersion to non-music content. |
| P2-9 | CLI / API for pro users to script profile switching | C | Persona C power user feature. |
| P2-10 | Multi-output routing (e.g., headphones + HDMI simultaneously) | W | Complex edge case; defer. |
| P2-11 | iOS / iPadOS companion | W | Out of scope for Phase 2. |
| P2-12 | Per-stem / stem object engine via process tap | W | LD-15: own-player-only. Real-time-lite separation is a research track. |

---

## 5. Success Metrics / KPIs by Phase

> **As-built (R1):** the app has **no telemetry, no analytics and no crash reporting** — it makes no network calls at all (which satisfies NFR-PRIV-04 trivially). So every metric below that needs "in-app analytics", "telemetry" or "crash reporting" **cannot be measured** today; only the qualitative rows (daily use by the maintainer, GitHub signals) apply. Measuring the rest needs SPIKE-TELEMETRY + backlog US-PRIV-03 (unscheduled), or the KPIs should be restated for a personal / open-source project.

### Phase 0 KPIs (Local-File Player MVP)

| Metric | Target | Measurement Method |
|---|---|---|
| Private beta signups | 200+ before launch | Landing page waitlist |
| Day-7 retention | > 50% | In-app analytics (anonymous, opt-in) |
| Session length (median) | > 25 minutes | In-app analytics |
| "Sounds better" self-reported (post-install survey) | > 70% | In-app NPS prompt at Day 3 |
| **EQ/processing perceptibility gate: users do NOT perceive the adaptive processing "moving"** | < 10% of sessions flagged (opt-in feedback prompt) | In-app "did anything sound weird?" binary prompt; threshold for Phase 1 gate |
| Crash-free sessions | > 99.5% | Crashlytics or Sentry |
| Audio thread underruns (dropouts) | < 0.1% of sessions | In-app counter, anonymous telemetry |
| GitHub stars (open-source repo) | Tracked; growth trend as adoption signal | GitHub Insights |
| Personal daily use by maintainer | Used as primary daily driver | Self-reported / qualitative |

### Phase 1 KPIs (Mix-Based Core)

| Metric | Target | Measurement Method |
|---|---|---|
| **Reimagine knob engagement: users who moved the knob at least once per week** | > 50% of active users | Feature-level analytics |
| **Reimagine default position (median setting across active users)** | Tracked; alert if median consistently at 0% or 100% | Feature analytics; inform UX tuning of default |
| BRIR spatial mode adoption | > 35% of active users | Feature-level analytics |
| Head tracking enablement rate (AirPods users) | > 50% | Feature-level analytics |
| D30 retention | > 40% | Cohort analysis |
| NPS score | > 45 | Quarterly in-app survey |
| Monthly active users (MAU) | 5,000+ | Analytics |
| **EQ/processing perceptibility gate: users do NOT perceive the adaptive EQ "moving"** | < 10% of sessions with negative-movement feedback | Opt-in feedback prompt; Phase 1 equivalent of Phase 0 gate |
| GitHub contributors (open-source) | Any external contributor is a milestone | GitHub Insights |

### Phase 1.5 KPIs (Stem-Based Object Engine)

| Metric | Target | Measurement Method |
|---|---|---|
| **Separation quality acceptance: users at Reimagine > 70% who did NOT report artifacts** | > 80% | Post-session opt-in artifact report (binary: "did you hear any glitching / separation artifacts?") |
| **Reimagine high-intensity use (> 60% setting, stem range) — weekly active** | > 25% of Phase 1.5 active users | Feature analytics; confirms stem engine drives engagement |
| Quality-gate fallback rate (tracks that fell back to mix-level or fewer stems) | Tracked; alert if > 20% of tracks | Separation pipeline telemetry |
| Performance: render budget on the M1 Pro / 16 GB floor (P99 per-buffer CPU) | < 60% of per-buffer deadline | Internal measurement from tuning spike |
| Crash-free sessions (stem engine active) | > 99.5% | Crash reporting |
| D30 retention (Phase 1.5 cohort) | > 40% | Cohort analysis |

### Phase 2 KPIs (System-Wide)

| Metric | Target | Measurement Method |
|---|---|---|
| **System-audio permission grant + tap setup success rate** (primary path, macOS 14.2+) | > 90% | In-app onboarding funnel telemetry |
| **Driver install success rate** (fallback path only) | > 90% | Installer telemetry (fallback path users only) |
| System-wide mode adoption among existing users | > 60% | Feature analytics |
| Added latency (P95) | < 5 ms | Internal measurement + user-reported |
| Driver-related crash rate (fallback path only) | < 0.05% of sessions | Crash reporting (fallback path users only) |
| MAU | 20,000+ | Analytics |
| GitHub stars / forks | Tracked; growth trend | GitHub Insights |

---

## 6. Project Model

Adaptive Sound is a **personal / open-source project**. It is free to use, free to share, and free to build on. There is no monetization, no pricing, no paywall, and no feature-gating of any kind. Every feature in every phase is available to everyone.

The choice of open-source license is **deferred until post-MVP** (after Phase 0). It does not need to be settled to build or privately test the MVP; it only needs to be in place before the repository is made public. Until then, treat the code as "source-available, license TBD."

> **As-built (2026-10-13) — a gap against this section:** the GitHub repository is already **public** and v1.0.0-alpha is being released from it, but there is **no LICENSE file**, so nobody may legally reuse the code yet. This section said the licence "needs to be in place before the repository is made public". Raised as a council finding; backlog **US-REL-02**.

> **Decided 2026-10-14 (founder, FD-7):** the licence is **Apache-2.0**. Adding the LICENSE file and notices is deferred to a later release-readiness item, with notarization and diagnostics ("focus on features") — backlog EP-RELEASE, [council report](../reviews/2026-10-council/README.md).

---

## 7. Top Risks and Open Product Decisions

### Risk Register

| Risk | ID | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| Adaptivity Engine introduces audible artifacts or latency on the audio thread | R-1 | High | Critical | Strict RT thread rules (no allocation, no locks). Phase 0 is the validation gate. A/B against bypass mode. The Reimagine 0% anchor is a verified bit-faithful path. |
| **EQ/processing perceived as "moving" by users** (perceptibility failure) | R-2 | Medium | High | Conservative adaptation cadence: coalesced updates, slow ramps (≥50 ms), hysteresis/deadbands. Phase 0 KPI gates Phase 1. Never fight intentional musical contrast. |
| **Performance / feasibility budget: 6 stems × per-stem chains × BRIR convolution real-time budget** | R-3 | Low | Medium | **Downgraded (LD-18):** the M1 Pro / 16 GB floor + sole-occupancy + current-gen headroom (M4/M5 ~3–4× the floor) make this comfortable, and the **shared-late-reverb decomposition** (review C2) cuts the dominant cost ~6×. Mitigations: all heavy work off-RT (separation, FIR/BRIR design, masking — pre-computed/cached); RT kernel runs fixed partitioned convolutions via Audio Workgroups; QualityProfile auto-scales **stem count / reverb-tail length** (not buffer size — see review C5). A **tuning spike** before Phase 1.5 sets per-tier caps; it informs scope rather than being a go/no-go. |
| **Separation artifacts exposed at high Reimagine intensity** | R-4 | High | Medium | By design at high intensity; managed by: (a) intensity-0 anchor is bit-faithful — users can always return; (b) conservative default Reimagine setting (low-to-mid); (c) quality-gating per stem (fallback to "other" or mix-level if threshold not met); (d) transparent artifact disclosure in UX at high intensities. |
| **6-stem separation robustness (guitar/piano)** | R-5 | High | Medium | Guitar and piano are the least-robust Demucs separation cases. Mitigation: "other" stem as catch-all; quality-gate per stem; graceful fallback to fewer stems; do not expose low-confidence stems to users without a quality signal. Validate separation quality on a curated test set before Phase 1.5 launch. |
| Phase 2 AudioServerPlugIn virtual device causes system instability (fallback path only) | R-6 | Medium | Critical | Applies only to libASPL fallback path. Reference eqMac stability track record. Extensive fallback-path beta. Auto-recovery mechanism. Primary tap path unaffected. |
| macOS future OS updates break AudioServerPlugIn ABI (fallback path only) | R-7 | Medium | High | Fallback driver path only. Monitor Apple developer forums. Fast release cadence for compatibility patches. Primary tap path governed by a different API surface. |
| App Store sandbox blocks Phase 2 AudioServerPlugIn (fallback path only) | R-8 | High | High | Fallback driver path: direct notarized DMG is the required distribution path. Verify whether primary process-tap path is App Store-eligible during Phase 2 planning. |
| **Patent risk — psychoacoustic bass enhancement** | R-9 | Medium | High | Waves US-11,102,577 (stereo virtual bass, active ~2038). Mitigation: generate bass harmonics from mono-summed (L+R) low band only (per architecture §9). Do NOT implement per-channel/stereo virtual bass. Obtain formal IP review before any public release (OQ-16). |
| **OSS license-compliance risk** *(as-built: the only linked third-party code is GRDB.swift, MIT; libebur128, MIT, is test-only; FFmpeg is never bundled — it is loaded at runtime only if the user installed it; crossfeed is an in-house reimplementation, not libbs2b)* | R-10 | Medium | High | All shipped code and data must be permissively licensed. Copyleft libs (JUCE, KFR, Essentia, aubio, BlackHole) are reference-only — do not copy or ship. Weights/data licenses are separate from code licenses (MIT-code + NC-weights is not shippable). Verify each dependency against `docs/session-notes/prior-art.md` §4–5 before vendoring. |
| Apple Spatial Audio / ASAF improvements narrow the differentiation gap | R-11 | Medium | Medium | Stay ahead on continuous content-awareness and per-stem spatial rendering — areas ASAF (static post-decode) structurally cannot address. Speed of iteration is the moat. |
| BRIR quality not compelling out-of-box with generic HRTFs | R-12 | Medium | High | Invest in a high-quality default BRIR set (room synthesis + SADIE-II HRIR core). Offer personalization path (Phase 1). Ship the founder's blind, level-matched A/B against a timbre-matched dry reference as S18's last acceptance line; a stage that does not win ships off and hidden (2026-10-23). |
| Phase 2 setup friction (permission grant or driver install) | R-13 | Medium | Medium | Primary tap path needs only a one-screen permission grant (no device switch, no sudo). Fallback: dedicated onboarding, guided installer. Study eqMac's UX. |

---

### Open Product Decisions — Requires Founder Input

**Decision 1 — Monetization timing** ✓ **RESOLVED (LD-9): Not applicable.** Non-commercial. No paywall, no trial gate, no paid tier in any phase.

---

**Decision 2 — BRIR / HRTF strategy** ✓ **RESOLVED (LD-7, updated by LD-14):** BRIR-first (HRTF + early reflections + late reverb) is the default. Dry HRTF = minimal fallback mode. SADIE-II (Apache-2.0) is the anechoic HRIR core inside the BRIR. Custom/personalized HRTF deferred. Room synthesis (image-source + FDN) or CC0/CC-BY IRs. Marketing must avoid medical/audiological claims.

---

**Decision 3 — Distribution channels for Phase 2: App Store or direct-only?**

> **As-built for the own-player (R1):** direct download only — a drag-to-Applications DMG and a zip on the GitHub release, built by a tag-triggered workflow with build-provenance attestation (PR #87; first release `v1.0.0-alpha`, 2026-10-14, with a `SHA256SUMS.txt`). The app is **Developer-ID-style, not sandboxed** (S8.1 design D5), so the Mac App Store is not an option as built. R1 is ad-hoc signed and **not notarized** (founder decision 13; backlog US-REL-01). No Homebrew cask. The question below stays open for Phase 2 only.

For the **fallback AudioServerPlugIn path**: must ship as a notarized direct-download DMG (sandbox incompatible).

For the **primary process-tap path** (macOS 14.2+): App Store eligibility unconfirmed. Verify during Phase 2 planning.

Options (open for founder to decide):
- **Choice A**: Direct notarized DMG only — linked from GitHub / project website.
- **Choice B**: Phase 0–1 on Mac App Store (free); Phase 2 as direct-download DMG linked from listing.
- **Choice C**: Direct DMG + Homebrew cask. Recommended for open-source developer audience; combinable with Choice B.

---

**Decision 4 — Content classification** ✓ **RESOLVED (LD-5): Both, phased** — DSP heuristics (Phase 0); Core ML genre/mood model (Phase 1).

---

**Decision 5 — Ambient mic** ✓ **RESOLVED (LD-6): On-demand only** — user-triggered ~3 s sample, mic then released. No always-on mic.

---

**Decisions 6–8 — Conversational Tuning (positioning, persistence, NL interpretation mechanism)** — *Withdrawn 2026-07-12: natural-language / conversational tuning removed from scope (founder decision); prior text in git; may be re-added.*

---

**Decision 9 — Reimagine knob intensity→parameter mapping curve (OPEN — OQ per architecture §17)**

The exact curve from knob position to processing parameters (how fast clarity ramps, at what position BRIR widening kicks in, where stem placement begins, etc.) must be user-tested. Initial proposal: roughly linear in perceptual magnitude, with a natural "gap" at the mix/stem range boundary that the UX should surface as the Phase 1.5 upgrade moment. This decision must be made before Phase 1 UX finalization.

---

## Appendix: Phasing Summary

> **As-built pointer (2026-10-13):** the summary below is the concept-era capability phasing. What has been built is the **Phase 0 player**, released as **R1** (v1.0.0-alpha, shipped 2026-10-14), ordered player-maturity-first; its success gates as written (retention, "sounds better" surveys) are not measurable without telemetry. Execution order and releases: [roadmap.md](roadmap.md) (R1 → R2 after S14 → R3 after S17).

```
Phase 0 — Player MVP:     Local-file player MVP — prove the DSP spine
                            AVAudioEngine + custom AUv3 (C++ kernel) + SwiftUI
                            No virtual device, no sudo, no streaming apps
                            BRIR and stem separation explicitly NOT in Phase 0
                            Success gates: > 50% D7 retention, > 70% "sounds better",
                                          < 10% of sessions flagging adaptive EQ as perceptible

Phase 1 — Mix-based core: Mix-based core — full immersive + adaptive story
                            BRIR-first binaural (LD-14) + head tracking
                            Perceptual clarity/correction (ERB/Bark, LD-12)
                            Adaptive engine: loudness-comp, content-aware, ambient
                            Reimagine intensity knob: mix range (0%–~60%, LD-16)
                            All features free, open-source
                            Success gates: > 40% D30 retention, > 5,000 MAU,
                                          Reimagine knob engagement > 50% weekly active,
                                          BRIR spatial adoption > 35%,
                                          < 10% of sessions flagging EQ as perceptible

Phase 1.5 (gated on perf spike):
                            Stem-based object engine — full spatial reimagining
                            TUNING: spike sets QualityProfile caps on the M1 Pro / 16 GB
                              floor before Phase 1.5 kickoff (§7 Risk R-3 — Low; LD-18)
                            Offline 6-stem separation (Demucs, LD-15)
                            Per-stem DSP chains + BRIR spatial placement
                            Between-stem masking/unmasking
                            Reimagine knob: stem range ceiling raised to 100%
                            Own-player-only (stem features do not reach Phase 2 tap path)
                            Success gates: > 80% artifact-acceptance at Reimagine > 70%,
                                          > 25% weekly use of Reimagine stem range,
                                          render budget < 60% of per-buffer deadline

Phase 2 — System-wide:     System-wide via Core Audio process tap (primary, macOS 14.2+)
                            No driver, no sudo, no coreaudiod restart on primary path
                            Same C++ DSP kernel, BoundedLatency profile, mix-level only
                            AudioServerPlugIn virtual device (libASPL) as fallback
                              for older macOS / persistent-output-device use case
                            All apps: Spotify, Apple Music, YouTube, Zoom
                            Direct-download DMG for fallback path
                            Stem features remain own-player-only (LD-15)
                            Success gates: > 90% tap-path permission grant success,
                                          > 90% driver install success (fallback),
                                          < 5 ms added latency (P95),
                                          > 60% system-wide mode adoption among existing users
```

---

*Document owner: Ramith (ramith@wso2.com). Architecture source of truth: `docs/architecture/architecture.md`. This is the concept-era vision/why doc; execution status & sequencing live in [`../sprints/sprint-plan.md`](../sprints/sprint-plan.md). Reconciled to the code 2026-10-13 — the code is the state of the product; this document carries the vision and the rationale.*
