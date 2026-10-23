# Adaptive Tone: an AI that reads ahead, sets the tone for each song, and learns from "better / not" (proposal)

*2026-10-10. A proposal only: nothing is built, and no product code was changed. Branch read: `feat/s10-8-eq` @ `07b35c7` (pre-merge; Sprint EQ then merged as PR #73). File:line references below are as of that commit unless marked "now".*

> **Status (reconciled 2026-10-13):** still a **proposal awaiting a founder decision** — no adaptive-tone code and no `research/adaptive-tone-poc/` exist. It is not on the schedule; the [roadmap](../../product/roadmap.md) lists it under "Proposals awaiting a founder decision" (it overlaps the S15–S17 adaptive thesis). Since it was written, EQ2 shipped (PR #73), so AT1's dependency is met.

**What the founder asked for.** "Plug in a neural network to dynamically read ahead the song we are playing, then suggest the best EQ levels (+ tone) during mid-song play, and that controls the entire playback. We can instruct the network to stick to a particular theme, and give the user a simple control to steer it: 'it sounds better, or not'." The founder also asked for a literature and market study, done systematically, before any proposal.

**How this was researched.**
- A written protocol, [evidence/00-protocol.md](evidence/00-protocol.md), split the request into 12 research objectives (RO1–RO12).
- Seven tracks searched against that protocol. Each logged its queries, opened full texts, snowballed one hop, graded evidence A–D/U, and answered its objectives with a stated confidence.
  - A: content-aware EQ literature.
  - B: preference learning and perception.
  - C: the market.
  - D: on-device feasibility, including a benchmark run on this Mac.
  - E: training data.
  - F: patents.
  - G: evaluation.
- About 300 sources were graded, and every tag below points to one. A tag such as **[A:S4]** means source S4 in brief A.
- **[M]** marks a measurement made this session, and **[O]** marks my own design judgment.

---

## 1. The answer, in short

**Yes, build it, but not in the shape first imagined. And test the one thing nobody has tested before building anything.**

1. **Reading ahead: yes.** It is cheap and already half-built. `TrackLoudnessAnalyzer` (EQ1c, landed today) already analyses the current and next track, ahead of play, into a K-weighted 1/24-octave spectrum every 100 ms (`TrackLoudnessProfile.h:6-20`). A whole track's band balance costs under a second [D:M01–M04].
2. **"The best EQ" is not something a model can score.**
   - No automatic critic tracks listener preference for EQ changes on the same song [A:S18, S23, S24].
   - Meta's Audiobox Aesthetics, measured on this Mac, rewards ever more treble up to +12 dB and a deep 3 kHz scoop [D:M05, M06]. Maximising it would make songs harsh and hollow.
   - In blind, level-matched tests, "better" means close to a balanced target plus a personal bass/treble offset [B:B24, B29]. So **"best" = your theme + your learned taste**, not a network's opinion.
3. **One setting per song, decided before it plays. No mid-song moves at launch.**
   - No study has tested EQ that changes inside a finished song [A, B: searches saturated].
   - Hearing adapts to a colouration within about 16 s, and a change is heard against what came before [B:B37, B38].
   - Users of the closest competitor reject exactly this ("second-guessing the master", "doing too much") [C:M58].
   - Mid-song changes become a later experiment that must first pass a "can you hear it move?" test.
4. **"Controls the entire playback": no. Tone only, bounded, loudness-neutral.**
   - Every listening product confines its AI to EQ/tone. The one consumer AI that touched the timeline (AutoMix) drew the loudest complaints [C:RO7].
   - The AI moves the 5 Tone macros by at most ±3 dB around the chosen preset. The live loudness-neutral gain keeps the level fair.
   - It never touches Pure Mode, the limiter, the normaliser, Intensity, crossfeed, the device or the timeline.
5. **"A simple control: sounds better or not": yes, as a short blind 1-vs-2 comparison, learned by a small Bayesian model.**
   - Paired-comparison Gaussian-process learning finds a preferred setting of ≤4 parameters in 10–20 answers [B:B10]. A good prior gets there in about 3 [B:B04].
   - One click is noisy: test-retest r = 0.41–0.69 [B:B01, B05]. So the default only moves on consistent answers, and only over 2–3 dimensions (bass, treble-tilt, maybe body), not 31 bands.
6. **"A neural network": mostly no.**
   - The part that must learn (your taste) is 2–3 numbers, and a Bayesian model beats a network there.
   - The part that must sense (spectral balance) is DSP. The learned models resample to 16 kHz and barely notice ±12 dB of treble [D:M03].
   - No public data could train an end-to-end "song + theme + feedback → EQ" network [E:§5].
   - Networks earn a place only as optional sensors: a harshness alarm, a genre hint for the target.
7. **The open question.** **No published listening test shows automatic EQ beating an untouched finished master** [A:§RO3, G:§6]. Every win in the literature is on raw or damaged audio [A:S4, S5]. In the one test on finished music, EQ was the only category with no significant gain [A:S24].
   - So the first step costs about a week and touches no product code. **Stage 0** is an offline probe. **Stage 1** is your own blind A/B of *the same preset, adaptive vs static*, and adaptive vs the original (§6).
   - If adaptive doesn't beat static for your ears, we stop and keep the presets we have.

---

## 2. Your idea, piece by piece, against the evidence

| Piece of the idea | What the evidence says | Verdict | Change |
|---|---|---|---|
| Read ahead in the song | Track spectra and section boundaries are cheap and reliable to compute ahead [A:S15, S33; D:M01–M04]. The analyzer already exists (EQ1c). | **Keep** | Reuse `TrackLoudnessAnalyzer`; add a band-balance summary |
| A neural network suggests the best EQ | No valid critic [A:RO2; D:M05–M06]. No training data [E:RO9]. Auto-EQ wins only on raw or damaged audio [A:S4, S5]. | **Reshape** | DSP measurement + theme target + Bayesian taste model; networks only as sensors |
| During mid-song play | No direct evidence [A, B]. Adaptation and contrast effects [B:B37, B38]. Users reject mid-song moves [C:M58]. Every mature system is static per track [A:S9, S15]. | **Defer** | One setting per song at launch; section glides later, behind a hearing test |
| Controls the entire playback | Shipped listening AIs are EQ/tone only; full-chain control exists only in mastering tools with a strength knob and gain-matched bypass [C:RO7] | **Narrow** | Tone authority only, ±3 dB, loudness-neutral, an Amount knob |
| Stick to a theme | About 3 listener classes (64 / 15 / 21 %) [B:B24]; 2 components explain 87–96 % of EQ curves [B:B02, B03]; 3 styles is the pro pattern [C:M3]; "leave good content alone" [C:M29] | **Keep** | A theme = an existing preset played as a *target balance*; start with 3 |
| "Sounds better / not" | GP preference learning: ≤4 parameters in 10–20 comparisons [B:B10]; a prior → about 3 [B:B04]; single answers are noisy [B:B01, B05]; level matching to ±0.25 dB or better [B:B30; G:§2.2] | **Keep, made rigorous** | A blind 1-vs-2 "Tune" on a replayed excerpt; 2–3 learned dimensions; default moves only on consistent answers |

---

## 3. The proposed design

### 3.1 What you would see

- **Each built-in preset gains an "Adapt to each song" switch, plus an Amount control.**
  - Off: the preset plays exactly as today, the same fixed Tone offset on every song.
  - On: the preset becomes a **target balance**. A song that already has plenty of bass gets less of Warm's bass lift; a dull old master gets a little more air.
  - This is Dolby Intelligent Equalizer's documented behaviour ("if the audio already has enough bass… leaves the bass alone") [C:M29], built on our Tone macros instead of a black box.
- **Start with three themes** [O, from B:B24, E:§9.6, C:M3]:
  - **Balanced** (Flat, adaptive): corrects only clear outliers, like boomy or dull masters, and leaves well-balanced ones alone.
  - **Warm** (`[bass +3, body +2, presence −1.5, air −2]`, `EQBuiltInPreset.swift:62-73`).
  - **Clarity** (`[body −2, presence +1.5, air +3]`).

  These map onto the three listener classes found again and again: neutral, more bass, less bass / more top.
- **A "Why" line under the graph.** For example: "This song: Bass +1.5 (a bass-light master) · Air held (the source is band-limited)."
  - The graph already draws the played curve (EQ3), so the readout and the curve tell the truth together.
- **"Tune" (the "better / not" control).** A short blind session. You hear the last 8–10 s twice as "1" and "2", switch freely, and answer "1 / 2 / no difference".
  - Each answer updates your personal offset for this output.
  - At most 10–15 asks per session, never within 20 s of an automatic change [B:B30, B38].
  - This is a separate, deliberate mode, not a thumbs button that interrupts listening. A passive "thumbs" on a suggestion is logged as weak evidence but never moves the default on its own [O, B:§RO6].

### 3.2 How it decides (per song, before it plays)

1. **Sense.**
   - From the analyzer's profile, sum the gated blocks' power into the 5 Tone regions, using the same raised-cosine weights the Tone card uses (`EQToneRegion.swift:20-24`). Divide out the K-weighting filter's known response first, because the profile is K-weighted.
   - Normalise to a relative balance `b` (dB per region, mean-removed).
   - Detect a band-limited source (lossy low-pass) so that Air is not "corrected" into a missing octave [D:§RO1; E:§6.7].
2. **Compare with typical.** `e = b − r`, where `r` is a reference median per region with a typical spread `s`.
   - The licence-clean source for `r` is AcousticBrainz's CC0 low-level features (about 7.56 M recordings). Its Bark-band edges at 150 / 510 / 2000 / 6400 Hz line up with the Tone edges [E:E42, E43b].
   - The user's own library, analysed on-device, can refine it.
3. **Leave good content alone.**
   - Only the part of `e` outside the typical range counts: `e′ = sign(e)·max(0, |e| − s)`.
   - This is iZotope's "targets are ranges" point [E:§9.6] and Dolby's "modern recordings are left unprocessed" [C:M29], as arithmetic.
4. **Correct partially, toward the theme.**
   - `tone = t_theme − k·e′`, where `k` ≈ 0.5 is a partial correction [O].
   - SoundID reviewers found correction at about 50 % wet sounded best ([eq-market-research.md](../../product/eq-market-research.md), the SoundID row).
   - A fixed average target lost even on damaged audio, so a full pull would be wrong [A:S5].
   - Then bound it: `|tone − t_theme| ≤ 3 dB` per region [D:§RO7; architecture §11 "low-confidence ±3 dB"].
5. **Weight by confidence.** Confidence is lower when the balance varies a lot between sections (the average isn't representative), when the track is very short, or for Air on band-limited sources. `applied = t_theme + Amount·c·(tone − t_theme)`.
6. **Add your taste.**
   - Add the learned personal offset `p` (§3.3) for this output.
   - `played Tone = applied + p`, then `points = clamp(base + Σ tone·weights, ±12)` as today (`EQCurve.swift:43-52`).
   - The loudness-neutral gain (decision 26, live since `ffd8425`) makes any shape level-fair.
7. **Cache.**
   - A derived row per track: band balance, `e`, the decision, `analyzer_version`.
   - It goes in a new LibraryStore table, via an additive migration on the `derived_version` pattern [D:§RO8-3]. Being a derived cache, it can be dropped and rebuilt.
   - A background pass on AC power can pre-decide the whole library.
   - **The first song after a cold click** plays the theme's static setting for a moment, then glides once to the adapted setting within the first seconds. The analyzer measures the prefix first, so this happens before a listener has formed a reference [O, B:B38]. Every later song is decided ahead, via the next-track prefetch.

`k`, `s`, the ±3 dB bound and the confidence rule are **starting values for Stage 0 to tune**, not settled numbers.

### 3.3 How "better / not" learns

- **The model.** A probit Gaussian-process preference model [B:B17] over **2–3 dimensions relative to the theme**.
  - The dimensions: Bass; a treble-tilt axis spanning Presence + Air; optionally Body. Two components carry 87–96 % of EQ-curve variance [B:B02, B03].
  - The theme is the prior mean, with half-Student-t lengthscale priors [B:B09] and explicit noise.
- **The next comparison** is chosen by qEUBO or Thompson sampling [B:B19, B21]. With 2–3 dimensions this is tiny: about 100 points, Laplace inference in Accelerate, off the main thread.
- **Trust rules.**
  - A first personalised offset after 3–5 answers.
  - Converged by about 10–20 answers [B:B10].
  - The stored default changes only after at least 2 consistent answers [B:B01, B05].
  - Slow forgetting, because preferences drift [B:B13].
- **Fair A/B.** EQ3's hold-Compare (`EQViewModel.swift:202-218`; now `EQSession.beginCompare` / `endCompare`, `EQEditKit/EQSession.swift:159-170`) is generalised:
  - curve-vs-curve, not curve-vs-Off;
  - unlabelled and randomised;
  - the same excerpt replayed, with about a 40 ms switch;
  - Intensity held at 0 or the normaliser frozen;
  - the louder arm attenuated;
  - mismatch within 0.2 dB (target 0.1), with the residual logged [B:§implications; D:§RO8-4; G:§2.2].
  - The −ΔL predictor already works for any curve, at 0.112 dB max (`TrackLoudnessProfile.h:14-20`).
- **Storage.** Comparisons are **user data**: a durable table, never the derived cache (memory rule: user data survives migrations).
- **The bonus.** The same blind compare is a tool for you to voice presets without sighted bias.

### 3.4 Mid-song changes (later, and only if they earn it)

- **Off at launch.** If Stage 1 shows that adaptive beats static per song, a section mode can be tried:
  - Section balances come from the profile's block ranges, with boundaries from a DSP novelty curve over the same spectra. That needs no heavy model. All-In-One and SongFormer are heavy, and SongFormer's weights depend on non-commercial MuQ [D:§RO1].
  - Change only when a section's deviation differs from the track's by a large margin, by ≤1–2 dB per region, a few times per track at most, and only at a boundary [B:§implications 6].
- **The glide.** Add a `glideSeconds` hint to `Realizer::EqIntent` (`Realizer.h:89-93`), honoured as max(τ rule, hint). The real-time cap is 2 s (`EQModule.cpp:23-24`), and τ = 1.5 s settles 95 % in about 4.5 s.
  - The loudness-neutral gain rides the same one-pole, so the level can't jump mid-glide [D:§RO8-3]. *(Now: each band glides on its own one-pole (`EQTargets::rampsFor`) and the output gain on its own (`EQParams::gainRampSeconds`) — the hint must hold both to the same glide.)* A section-local −ΔL uses the block-range variant of the predictor.
- **Must pass first:** the Stage 1c "did it move?" test. That needs about 70 trials, with the 95 % upper bound on correct answers below 0.6 [G:§2.1].
- **Never** used to flatten contrast the artist made on purpose [B:B29].

### 3.5 Authority and safety (fixed for every version)

- **It may change:** the 5 Tone macros only, within ±3 dB of the theme, scaled by Amount × confidence. On top of that sits the learned offset `p`, within the observed class range (about ±6 dB bass, a few dB treble [B:B24]). The total stays under the existing ±12 dB clamp and EQ2's ceiling.
- **It may never:**
  - run in Pure Mode;
  - switch the EQ on (only a user edit does that, `ui-plan.md:206`; the bit-perfect state is Intensity 0 with EQ Off);
  - touch the limiter, the normaliser target, Intensity, crossfeed, the output device or the timeline;
  - override a band the user moved by hand. Under the future Arbiter it becomes the **content-adaptive contributor**, bound by the lock rule (architecture.md §4, "Arbiter arbitration rules (locked)", rule 1).
- **The render thread** only ramps finished coefficients, as now (ADR-004/006).
- **Loudness.** Loudness-neutral always, via −ΔL. A shape change must never also be a level change, because louder is preferred by listeners and by the critic models alike [D:M05; B:B23].
- **Device correction.** When S12/S13 device correction (AutoEq) lands, themes sit *on top* of the corrected response, so taste isn't double-applied to the headphone target [E:§6.8].

### 3.6 Where machine learning actually fits

| Use | Model | Role | Licence | When |
|---|---|---|---|---|
| Personal taste | GP preference model (our code) | **the** learner | ours | v1 |
| Harshness or dullness alarm | Audiobox Aesthetics (104 M parameters, 0.9 s per track on MPS [D:M04]) | veto or log only, paired on the same audio; never maximised | CC-BY-4.0 | optional, after Stage 0 |
| Genre/era-aware reference `r` | YAMNet (34 genre classes) or LAION-CLAP; the year tag | condition `r` | Apache-2.0 / CC0 | later, if Stage 0 shows genre matters |
| Learned content-aware target | frozen encoder + tiny head, the Moliner style [A:S5] | an alternative to the DSP reference | depends on the encoder | Stage 0 comparison only |
| Not recommended | Essentia / MAEST / MERT / MuQ / madmom | — | NC weights; AGPL code (Essentia, MAEST) | — |

- Shipping any Python model means a Core ML conversion with static shapes. ONNX Runtime's Core ML backend ran **50× slower than its CPU backend** with dynamic shapes [D:M02, D31].
- Essentia would also reverse ADR-005.

### 3.7 What exists, and what's missing (repo)

| Need | Status @ `07b35c7` *(now @ `7d7c2cd`)* |
|---|---|
| Read-ahead analysis of current + next, cached by file identity, never in Pure Mode | **Built** (`TrackLoudnessKit/TrackLoudnessAnalyzer.swift`) |
| Loudness-neutral gain for any curve | **Built** (now `Realizer.mm:430` `loudness_.onDesign`, and `applyGainChange`) |
| Presets as Tone vectors; Tone → 31 points | **Built** (`EQBuiltInPreset.swift:62-73`, `EQCurve.swift:43-52`) |
| One EQ dispatch into the Realizer | **Built** (now `EQViewModel.publish()` → `AudioViewModel.publishEQ` → `AudioEngineBridge.publishEQ` → C-ABI `publishEQ` → `Realizer::setPendingEq`, `Realizer.mm:205`) |
| EQ2 (bridge cut-over, `EQSafetyClamp` retired, decision-29 ceiling) | ~~Open~~ **Built** — EQ2 shipped in PR #73 (`EQSafetyClamp` gone; `Limiting/OutputCeiling.h`; `publishOutputTransport`) |
| Band-balance summary + reference + decision + cache table | New |
| Curve-vs-curve, blind, replayed-excerpt Compare | New (generalises EQ3 Compare) |
| Preference model + durable feedback table | New |
| `glideSeconds` in `EqIntent` + section-local −ΔL | New (section mode only) |
| Offline corpus driver (render the corpus through the engine path) | New; also missing per `validation-strategy.md` ("Test 2") and needed by Stage 0 |

---

## 4. The market: the gap is real, and closing

- **Nobody ships the whole combination in a music player.** That means read-ahead analysis, content-aware tone, continuous learning from feedback and theme steering together [C:§gap]. Confidence is medium: Chinese phone makers and car audio weren't covered.
- **The closest rival is EQK** (Mac, July 2026, ₹699): per-song adaptive EQ by moment, section or one static curve.
  - It is *causal*: it learns on the first play and applies on the second.
  - It has no themes, no published bounds, and a bypass that isn't level-matched. Its maker admits "doing too much" and "over-EQ'd" [C:M56–M58].
- **Best precedents to copy:**
  - Dolby Intelligent Equalizer: steer toward a chosen tone and leave good content alone [C:M29, M30].
  - sonible learn:EQ: Intensity, 3 Styles, a Dynamic knob that is off by default, labelled tone sliders [C:M3].
- **Preference learning** ships only as one-time A/B tests that produce a static curve (LG Sound Wizard, SoundID, Sony, Sennheiser) [C:M25, M42, M43, M45].
- **Our edge, as evidence-backed restraint:**
  - *non-causal* read-ahead: decided before the song plays, with no reacting lag;
  - a *loudness-matched, blind* Tune, which answers the critique levelled at EQK, "learning volume and calling it taste" [C:M58];
  - themes over the Tone macros;
  - "leave good masters alone" by construction.
- **Threats:** EQK iterates fast. Apple has the analysis plumbing (AutoMix) and is adding user EQ to AirPods [C:M36, M39].

## 5. Patents (freedom to operate)

*Pending: the patent track (F) is still running. Flagged so far:*
- **Gracenote US10998872B2** (active to about 2039): a neural network trained on engineers' EQ curves, plus like/dislike personalisation [E:E55].
- **Dolby US9621124B2:** classifier-weighted content EQ with smoothing [C:M30].
- **Sony US10855241B2:** genre EQ biased by the user's manual edits [C:M59].
- **Northwestern US8565908B2:** EQ preference learning; Google lists it as ceased, with a reissue to check [E:E56].

The design above deliberately uses deterministic DSP measurement, hand-authored theme targets and a Bayesian A/B learner, with no network trained on engineers' curves. Whether that is enough is for this section to answer once F reports.

## 6. How we would prove it (the evaluation ladder)

**Shared rules for every stage** [G:§2.5]:
- Three conditions: **O** = the original, **S** = the same preset static (today's behaviour), **A** = the same preset adaptive.
- All loudness-matched within 0.2 dB, through the same chain.
- Track list and pass bars pre-registered before listening.
- **The baseline is S, not Flat.** Widex's "84 / 89 % preferred" was against a weak baseline; against a strong one, the peer-reviewed gain was +6.5 / 100 [G:§2.3].

| Stage | Who / effort | What | Pass bar | Unlocks |
|---|---|---|---|---|
| **0: offline probe** | agents, about 1–2 days, `research/` only | About 60 tracks + about 600 "known tone error" cases. Rendered with the repo's oracle (`research/eq-geq-poc`) or the new corpus driver | All safety/loudness invariants 100 %; recovers known errors (r ≥ 0.7, residual ≤ 1 dB); leaves pristine masters within ±1 dB on ≥ 90 %; **A differs from S by ≥ 1 dB on ≥ 30 % of tracks, else stop: nothing to hear** | your listening time |
| **1: your blind A/B** | you, 2–3 h over about a week | 1a A vs S; 1b A vs O; 1c "did it move?" (section mode only); **1d: does a taste offset learned on 6 songs help on 6 others?** (the untested core assumption [E:§6.1]); repeat and catch pairs measure your consistency and loudness bias | 1a: a sequential test says "prefers A" (about 23 trials if real, cap 60); 1b: not worse than O; 1d: learned offset preferred on held-out songs | **the build** |
| **2: small panel** | 10–15 listeners, about 45 min each | A/S/O pairs × 10 tracks, with anchors and nulls | pooled P(A ≻ S) ≥ 0.6, lower 95 % CI bound > 0.5; no track significantly O ≻ A | default-on, public claims |
| **After shipping** | local logs only | a randomised hold-out (20–30 % of tracks get S blindly) for ≥ 3–4 weeks | override and revert rates, A vs S | tuning |

- **Gates for CI** (for every version, matching the null-test culture) [G:§2.4]:
  - invariants (bounds, loudness neutrality, boundaries/slew, Pure / Intensity-0 nulls);
  - a golden-master hash of the *quantised decision timeline*, not of model audio;
  - metamorphic tests: level, codec and offset invariance; a directional test where a +3 dB shelf lowers that region's decision; restraint on pristine masters.
- **Never gate on** Audiobox, PEAQ or ViSQOL [G:§2.4; D:M05].
- **One caveat about Stage 1.** You prefer faithful sound, so a pass is strong evidence. A fail means "not for you", not "no market". That is why Stage 2 exists.

## 7. Plan and sequencing

- **Now (research only; respects the sprint boundaries):** Stage 0 in `research/adaptive-tone-poc/`, then Stage 1 with pre-rendered files in a small blind player. No product code.
- **If Stage 1 passes:** build after R1 as Phase 2's first, lowest-risk item. It *is* the planned content-adaptive contributor and reuses Sprint EQ's infrastructure. The exact slot relative to S11–S14 is your call at R1 planning. Chunks, in dependency order:
  - **AT1:** band balance + reference + themes as targets + the bounded suggestion layer + the "Why" line + the cache table (needs EQ2 — shipped in PR #73).
  - **AT2:** the blind curve-vs-curve Compare (also a voicing tool).
  - **AT3:** the preference model + durable feedback + per-output offset.
  - **AT4 (gated by 1c):** section glides (`glideSeconds`, section −ΔL).
  - **AT5:** the local hold-out logs.
- **If Stage 1 fails:** keep today's static presets, still ship the blind Compare (AT2) as a voicing tool, and park the rest.

## 8. Risks, and what would stop it

| Risk | Signal | Response |
|---|---|---|
| Nothing audible to test | Stage 0: A ≈ S on most tracks | Stop. Static presets stay |
| Adaptive homogenises intentional masters | Stage 1b: O ≻ A; restraint test fails | Widen `s`, lower `k`; else stop |
| Taste doesn't carry across songs | Stage 1d fails | Keep themes; drop the learner, or make it per-theme manual |
| "Better" is really "louder" | catch pairs: louder preferred > 65 % | Perceptual loudness re-match (ISO 532) before any learning |
| Patent | track F | Design-around per §5, or descope |
| A rival or Apple ships first | — | The differentiator is evidence-backed restraint + a fair blind Tune, not "AI" |
| Scope creep into cut features | — | Themes are presets, not words: **natural-language tuning and hearing personalisation stay cut** (2026-07-12) |

## 9. Decisions for you (recommended option first)

1. **What to do now.**
   - **(Recommended)** Run Stage 0 + your Stage 1 blind test first: about a week, research folder only. Decide to build after.
   - Alternatives: build now; or park the idea.
2. **What the AI may control.**
   - **(Recommended)** Tone only, ±3 dB around the chosen preset, loudness-matched, with an Amount knob.
   - Alternative: the "entire playback" (EQ + loudness + width + Intensity).
3. **Mid-song changes.**
   - **(Recommended)** Off at launch. Try section glides only after they pass your "did it move?" test.
   - Alternative: on from the start.
4. **What a theme is.**
   - **(Recommended)** Your existing presets, each with an "Adapt to each song" switch. Start with Balanced, Warm and Clarity.
   - Alternatives: new genre themes; or themes defined by reference tracks you pick.
5. **The "better / not" control.**
   - **(Recommended)** A short blind "1 or 2" Tune session on a replayed excerpt.
   - Alternative: a thumbs button while listening (noisier, and confounded by the music changing underneath).
6. **Models and licences.**
   - **(Recommended)** Permissive only: our DSP, Audiobox, CLAP, YAMNet, Apple. This keeps a commercial path open.
   - Alternative: allow non-commercial / AGPL models (Essentia and others) while the project is personal.

---

## Appendix A: evidence matrix (RO × answer)

| RO | Answer | Confidence | Key sources | Main gap |
|---|---|---|---|---|
| RO1 sensing | Band balance over time (DSP, already built); sections via DSP novelty or heavy models; genre is low-confidence on this library's material | high (balance) / low (genre) | D:M01–M03, A:S15, S33 | per-genre targets unpublished |
| RO2 "best" | No critic tracks same-song EQ preference; "better" ≈ balanced target + personal bass/treble offset | high (no critic) / med | A:S18, S23, S24; D:M05–M06; B:B24, B29 | whether any critic tracks *your* choices |
| RO3 policy | Mature methods give smooth, static per-track target-difference curves; wins only on raw or damaged audio | high (pattern) / low (finished-master benefit) | A:S4, S5, S11, S15, S24 | **no finished-master listening test** |
| RO4 mid-song | Unstudied; adaptation and contrast argue for static-per-track | low–med | B:B37–B39, B29; C:M58 | first-party test needed (1c) |
| RO5 themes | About 3 classes; 2-D taste; reference sets / priors; sound-defined, not adjectives | med | B:B24, B02, B03; A:S6, S37; C:M3 | Harman class sizes partly unverified |
| RO6 learning | Probit GP + qEUBO/TS, 2–3-D, theme prior, ≥2 consistent answers | high (method) / med (music transfer) | B:B10, B04, B17–B21 | one-tap UI unstudied |
| RO7 authority | Tone only, ±3 dB, loudness-neutral, never Pure / timeline | med | C:§RO7; D:§RO7 | — |
| RO8 feasibility | Compute < 1 s per track; licences are the constraint; hooks largely built (EQ1c landed) | high | D:M01–M04, D01–D31; repo | M1 timings; Core ML ports |
| RO9 data | No public preference data; decompose (DSP + themes + Bayesian); "undo random EQ" learns the average | high | E:E16, E17, E42, E14 | cross-track transfer of taste |
| RO10 market | Gap real (EQK closest, causal); Dolby IEQ and learn:EQ precedents | med | C:M29, M3, M56–M58 | Asian OEMs, car audio |
| RO11 patents | *pending (F)* | — | E:E55; C:M30, M59 | — |
| RO12 evaluation | Blind 2AFC + SPRT for you; Bradley–Terry panel; baseline = static preset; CI gates on invariants, not critics | high | G:§2.1–2.5 | real effect size unknown |

## Appendix B: evidence

- **Protocol:** [00-protocol.md](evidence/00-protocol.md).
- **Briefs:**
  - [A](evidence/A-content-aware-eq.md): content-aware EQ, 49 sources.
  - [B](evidence/B-preference-perception.md): preference and perception, 31 + 17 U.
  - [C](evidence/C-market.md): market, 59.
  - [D](evidence/D-feasibility.md): feasibility, 31 + 6 measurements. It carries an erratum: EQ1c landed during the study.
  - [E](evidence/E-data.md): data, 60.
  - [G](evidence/G-evaluation.md): evaluation.
  - F: patents, pending.
- **Benchmarks:** [evidence/bench/](evidence/bench/), the Audiobox EQ probe and sweep, EffNet, SoundAnalysis. Three clips from `research/`, on an M4 Pro.
- **Paywalled seminal papers** (Sabin & Pardo 2008, Toole & Olive 1988/1994, Olive 2003, Watkins 1991) are U. No claim here rests on them.
