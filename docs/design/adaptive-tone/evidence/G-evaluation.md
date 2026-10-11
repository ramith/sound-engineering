# Brief G: evaluation (RO12): how we would prove the adaptive EQ is better

*Track G · 2026-10-10 · follows `00-research-protocol.md`. Owns **RO12**. The repo was only read (`feat/s10-8-eq` @ 6b52c44).
Source IDs `G#` refer to the evidence table in §3. `R#` are repo files, and `A-S#` are Track A's sources (Track A graded them; I did not re-open them).*

**Labels.** **[M]** = computed or measured by me in this session (the arithmetic is shown) · **[C]** = a source I opened ·
**[O]** = my opinion or inference · **U** = not opened this session, so never stated as fact.

---

## 1. TL;DR

1. **Use preference tests, not quality-vs-reference tests.**
   - MUSHRA (BS.1534) and BS.1116 score how far a version falls *below* the original. The hidden reference is pinned at the top of the scale [G2, G4].
   - So neither can show "better than the original". BS.1534 itself warns that results bunched at 80–100 "may be invalid" [G2].
   - The right tools are blind, loudness-matched **forced-choice preference (2AFC)**, with **Bradley–Terry** scaling for a panel. A graded **CCR** scale (−3 … +3) is an option, because it can register "better than the reference" [G19].
   - Note: the repo's planned "MUSHRA" panel in `validation-strategy.md` is not MUSHRA. It uses a 5-point scale with no anchors, the misuse BS.1534 names [R1, G2].
2. **One listener can give a valid answer, but only about himself, and only with many trials.** This is an "N-of-1" trial [G30].
   - 16 trials detect only a *strong* preference: about 80 % power if the founder picks the adaptive EQ 80 % of the time, and only 17 % power at 60 % [M].
   - A **sequential test (SPRT)** decides after each trial, with no penalty for peeking [G16, G28].
   - With p₀ = 0.5, p₁ = 0.7, α = 0.05 and β = 0.2, it needs about **23 trials on average** if the preference is real, and about **15** if there is none [M]. A fixed-length test needs 37.
   - A weak preference (60 %) needs about **150 trials**, which is too many for one person [M].
3. **Loudness: match to ≤ 0.2 dB (target 0.1 dB) by BS.1770, then check that loudness isn't the real reason.**
   - The engine's own predictor already meets this: 0.112 dB max and 0.036 dB p90 against measured BS.1770 [R2].
   - But BS.1770's fixed K-weighting is only an *estimate* of perceived loudness [G3]. Nothing I opened measures its error for EQ'd versions of the *same* track (gap).
   - So add **level-catch trials** (identical audio, one copy +0.3 dB), and a second-opinion loudness model (ISO 532-1 Zwicker, or ISO 532-3 Moore–Glasberg–Schlittenlacher) [G29].
4. **Personalisation claims are usually made against a weak baseline.**
   - Widex's headline "84 % / 89 % preferred" compared against the classifier *off* (n = 19) [G7].
   - The peer-reviewed double-blind study used the strong baseline (classifier *on*). It found only **+6.5 / 100** on basic audio quality, and **no** group-level benefit for comfort or clarity [G6].
   - Sonarworks' ">78 % in blind tests" has no published protocol [G12].
   - **Our baseline must be the best *static* preset of the same theme**, not just Flat.
5. **Expect noisy listeners and a small true effect.**
   - Listeners agree with themselves only moderately: median r = 0.69 on repeated EQ ratings [G10].
   - In MusicRL, the team agreed with users' choices 60 % of the time, and the learned preference model reached 60 % held-out accuracy [G11].
   - Labels alone shift ratings: 15 of 20 people preferred an identical hearing aid labelled "new" [G13]. Sighted viewing moved loudspeaker ratings by up to 12 % of the scale [G4].
   - Brightness judgments adapt to the previous ~16 s of sound [G18].
   - **Everything must be blind and randomised, and a sham/hold-out control is needed in-product** to separate real benefit from novelty and regression to the mean [G13, G14, G15].
6. **CI can gate *safety and behaviour*, not *quality*.**
   - **Trustworthy gates:** bounds and loudness-neutrality invariants, change-only-at-boundaries and slew limits, determinism via a golden "decision signature", and metamorphic tests (level, codec and offset invariance, plus "undo a known EQ").
   - **Do not gate on learned quality scores.** On our own probe, Audiobox PQ moved by up to 0.29 for a 1-s misalignment. That is as much as a ±6 dB treble shelf, which moved it by 0.01–0.37 [G25]. It also rose monotonically with treble.
   - **Do not gate on full-reference metrics either** (PEAQ, ViSQOL). They score *any* EQ as damage, and ViSQOL's authors advise against using it for music regression tests without retraining [G20].
7. **Recommended ladder** (§2.5):
   - **Stage 0:** an offline probe with ground-truth tasks (recover a known EQ; leave pristine masters alone) plus all invariants. This unlocks spending founder time.
   - **Stage 1:** the founder's blind SPRT A/B of Adaptive vs Static-preset and vs Original, plus a "did it move?" detection test (about 2–3 h over a week). This unlocks building it.
   - **Stage 2:** a 10–15-person blind paired-comparison panel (about 45 min each). This unlocks default-on and public claims.
   - After shipping: a randomised in-product hold-out run for at least 3 weeks.

---

## 2. Findings (RO12)

### 2.1 Listening-test methods: what each measures, how big, how long, and which fits

| Method | What it measures | Minimum n and trials (source) | Time | (a) Founder alone | (b) Panel of 5–15 | Fit for "is the adaptive EQ better?" |
|---|---|---|---|---|---|---|
| **ITU-R BS.1116-3** (double-blind triple stimulus, hidden reference, "ABC/HR") | Size of a *small impairment* against a known reference, on a 1.0–5.0 scale [G1] | "Data from 20 subjects is often sufficient"; at least 5 excerpts (1.5 × number of systems); excerpts 10–25 s [G1] | Sessions ≤ 20–30 min with 10–15 trials, and rest of equal length between sessions [G1] | Only for transparency questions (e.g. "is the transition audible?") | Under-powered against the 20 it recommends | **No** for preference: any difference "must be interpreted as an impairment" [G1]. **Borrow its controls:** blind, ≈ 40 ms switching, level alignment, session limits |
| **ITU-R BS.1534-3** (MUSHRA) | *Intermediate* quality against a reference, 0–100. Hidden reference plus 3.5 kHz and 7 kHz low-pass anchors [G2] | "No more than 20 assessors are often sufficient". Exclude an assessor who rates the hidden reference < 90 on > 15 % of items. Items ≈ 10 s, ≤ 12 s [G2] | About 1 h per assessor with training (training is mandatory) [G2] | No | Possible, but answers the wrong question | **No.** The hidden reference must get the top score [G4], so "better than the original" cannot be expressed. EQ variants of good masters will bunch at 80–100, which BS.1534 says "may be invalid" [G2] |
| **ABX** | *Discrimination*: can you hear any difference? Binomial | One listener, many trials. 16 trials are reliable only if p(correct) ≈ 0.8 (power table below) [M] | 30–60 s per trial; 20 trials ≈ 15–20 min [O] | **Yes**, for "can I hear it?" and for **inaudibility** claims (needs ≈ 70 trials, below) | Yes | **Partly.** A prerequisite check, not a preference test |
| **Paired comparison / 2AFC preference** (+ binomial or SPRT for one listener; Bradley–Terry or Thurstone for a panel) | *Direction* (and, scaled, strength) of preference between versions | k conditions need k(k−1)/2 pairs. Smarter pair-scheduling beats random; knockout tournaments do no better than random [G33]. Paired comparison has a ~50-year record as "sensitive, valid and reliable" for hearing-aid settings [G31] | 20–40 s per trial [O] | **Yes, primary** | **Yes, primary** | **Yes.** It asks exactly "which do you prefer?" |
| **CCR** (ITU-T P.800 comparison category rating, −3 … +3) | Graded preference against a reference, *including better than the reference* [G19] | Crowd: 30 votes per item. Runs agree: ICC 0.94, Pearson ≈ 0.94; CMOS 95 % CI ≈ 0.18–0.20 [G19] | About 2× the cost of absolute rating [G19] | Optional add-on | **Good secondary**, measures *how much* better | **Yes**, as the magnitude companion to 2AFC |
| **Harman practice** (double-blind multiple-stimulus preference rating; positional and visual controls; trained listeners; replicated items) | Preference across products | Target development: **10 trained listeners**. Validation: 130–283 listeners. The virtual-headphone method (every headphone simulated on one replicator) matched real-headphone ratings at r = 0.86–0.99 [G5] | Not stated | **Adopt its controls**: same chain and same headphones for A and B (our "positional control"), blind, level-matched | Adopt | **Yes, as the control set**. Harman's own primary papers are paywalled (U) |

**Why "positional control" matters for us** [O]:
- Harman removes the cue of *where* a sound comes from (a speaker shuffler; U, the white paper failed TLS) and of *which* device it is (the virtual-headphone method [G5]).
- Our equivalent: **A and B must pass through the identical chain**, so only the EQ differs. That means the same limiter, the same loudness-neutral gain and the same output.
- This is not automatic. At Intensity 0 on a loud master, EQ On makes the limiter work for about half the time and plays about 1.2–1.4 dB under Off [R3].
- So log the limiter's gain reduction for both versions, and flag pairs whose gain reduction differs by > 1 dB.

**Today's Compare is sighted.** `EQCompareButton` is "hold to hear the song without the EQ, at matched loudness" [R5]. The listener always knows which is which, so it cannot provide blind evidence.

#### Statistical power for one listener [M]

These are one-sided exact binomial tests at α = 0.05 (normal approximation with continuity correction where marked ≈).

| Trials n | Correct needed | Power if p = 0.6 | Power if p = 0.7 | Power if p = 0.8 |
|---|---|---|---|---|
| 16 | 12 | **0.17** (exact) | **0.45** (exact) | ≈ 0.80 |
| 30 | 20 | ≈ 0.29 | ≈ 0.73 | — |
| 50 | 32 | ≈ 0.33 | ≈ 0.86 | — |
| 100 | 59 | ≈ 0.62 | — | — |

- **Fixed-n trials for 80 % power:** p = 0.6 → **153**; 0.65 → **67**; 0.7 → **37**; 0.75 → 23; 0.8 → 15. For 90 % power at p = 0.7 → 50.
- These figures reproduce the classic warnings about 16-trial ABX tests that are quoted from Leventhal 1986: a 0.83 miss rate at p = 0.6, and 0.38 even at 100 trials (U; I recomputed both).

**Sequential probability ratio test (Wald)** [M; procedure per ISO 16820 [G28]]:
- **Setting:** H₀ p = 0.5, H₁ p = 0.7, α = 0.05, β = 0.2.
- **Per-trial log-likelihood steps:** +ln 1.4 = +0.336 for a choice of A; ln 0.6 = −0.511 for a choice of B. Stop when the sum is ≥ ln 16 = 2.77 or ≤ ln(0.2/0.95) = −1.56.
- **In counts after n trials, with k choices of A:**
  - stop with **"prefers A"** when k ≥ 3.27 + 0.603 n;
  - stop with **"no strong preference"** when k ≤ −1.84 + 0.603 n.

| n | 10 | 15 | 20 | 25 | 30 | 40 | 50 | 60 |
|---|---|---|---|---|---|---|---|---|
| "Prefers A" if k ≥ | 10 | 13 | 16 | 19 | 22 | 28 | 34 | 40 |
| "No strong pref." if k ≤ | 4 | 7 | 10 | 13 | 16 | 22 | 28 | 34 |

- **Average trials (Wald's approximation):** ≈ **23** if p really is 0.7, and ≈ **15** if p = 0.5.
- **Truncate at 60.** If neither line is crossed, fall back to the fixed test: ≥ 37/60 is significant at 0.047 and is read as a "weak preference".
- **Variant with p₁ = 0.65:** k ≥ 4.48 + 0.576 n or k ≤ −2.52 + 0.576 n. Average ≈ 42 trials under H₁ and ≈ 28 under H₀.
- **Which way the preference goes:** run the mirror test for B as well (two one-sided SPRTs).
- **Why sequential:** checking a fixed-n test after every trial makes its p-values "wholly unreliable" [G16]. The SPRT is built to be checked after every trial, and ISO 16820 specifies exactly this stop-or-continue procedure for 2-AFC sensory tests [G28].

**Proving inaudibility** (the KPI "adaptation is never perceived as the EQ moving") [M]:
- A null result proves nothing until it is bounded. Use a 2AFC task ("which clip changed?").
- With a true 50 % hit rate, the one-sided 95 % upper bound on p(correct) falls below 0.6 only after **≈ 70 trials** (0.5 + 1.645·√(0.25/70) = 0.598).
- With guessing, 0.6 correct means a true detection rate of 20 %.
- If the founder scores 55 %, about 270 trials are needed for the same bound. So run this as an SPRT with H₀ p = 0.5 against H₁ p = 0.65.

**Trials are not independent** [O]:
- Trials repeat on the same track, the listener learns and tires, and the previous sound biases the next judgment. Brightness judgments adapt contrastively and settle after about 8 × 2-s trials [G18].
- So: **block by track**, use at least 8–12 tracks, and counterbalance AB/BA.
- Re-cue with a neutral reference before each pair, or alternate themes.
- Analyse with track as a cluster (cluster bootstrap or mixed-effects logistic regression).
- The design effect is 1 + (m − 1)ρ for m trials per track; with m = 4 and ρ = 0.2 it is 1.6.

### 2.2 Loudness matching when the EQ changes the spectrum

- **The standards treat level alignment as part of the method.**
  - BS.1116 has experts adjust each excerpt's loudness *subjectively*, by consensus, before the test [G1].
  - BS.1770 states that its measured loudness "is an estimation of subjective loudness and involves some degree of uncertainty". It also anticipates that "future complex algorithms based on psychoacoustic models may provide improved objective measures" [G3].
- **The tolerance:**
  - **≤ 0.2 dB integrated mismatch is the floor, and 0.1 dB the target** [O].
  - The reason: the matching error must sit well below the level differences that listeners can detect, so that level is never the cue.
  - The commonly cited figure, that "a few tenths of a dB" is noticed as "clarity" rather than as loudness, comes from forums only (U).
  - The engine already achieves **0.112 dB max and 0.036 dB p90** against measured BS.1770 on 7 tracks × 15 curves, with a load-time profile [R2].
  - Two leftovers [R2]:
    - **The first seconds:** the causal prior is up to 2.69 dB off in the first 10 s. Start test excerpts after the profile has landed.
    - **Short-term drift:** 3-s On vs Off wanders by −0.8 … +0.9 dB (Warm) and −2.9 … +0.9 dB (strong Tone). This is inherent and must be disclosed.
- **The metric:**
  - BS.1770 is the right *primary* metric, because it is what the product's neutral gain ships with [R2]. Test what ships.
  - But K-weighting is fixed and does not depend on level. A level-free weighting cannot track how the ear's bass sensitivity changes with SPL [O, from G29's scope].
  - For EQ'd versions of the *same* track, I found **no** published measurement of BS.1770's error (gap).
  - The nearest data point is across *different* items: BS.1770 gains averaged **2.2 dB** away from listener-chosen alignment gains (Berendes et al. 2022, U: abstract seen only via the search index).
  - **Second opinion:** compute **ISO 532-1** (Zwicker, time-varying) or **ISO 532-3** (Moore–Glasberg–Schlittenlacher) loudness for both versions, at the actual listening SPL.
  - ISO 532-3 explicitly covers music, but a single overall value for a signal longer than 5 s is outside its scope [G29]. So summarise its short-term loudness yourself (e.g. a percentile), and say that you did.
  - Flag pairs where the two models disagree by > 0.5 dB-equivalent [O].
- **The bias check (recommended)** [O]:
  - **Catch trials:** embed identical-audio pairs where one copy is +0.3 dB (about 10 % of trials).
  - If the founder picks the louder copy in ≫ 50 % of them, level differences of BS.1770's size can drive his preferences, and loudness must be re-matched perceptually.
  - **Optional robustness rove:** a random ±0.25 dB applied independently to each side. A preference that survives it is not level-driven. Level roving is standard practice in profile-analysis psychoacoustics (Green 1988, U).

### 2.3 How adaptive and personalised systems have been validated, and the traps

**Widex SoundSense Learn** (the closest analogue: paired-comparison learning of a 3-band gain):
- **Lab test** (Townend et al., Hearing Review 2018) [G7]:
  - n = 19, double-blind; recordings were rated at least 3 days after adjustment.
  - **84 % / 89 % preferred SSL over the *No Active Classifier* baseline.** Against the Active Classifier, comfort was p < 0.01 and quality p < 0.05.
  - "Only 20 iterations are needed" is a figure-caption claim. There are no field data.
- **Peer-reviewed study** (Jensen et al., Trends in Hearing 2019) [G6]:
  - n = 20, double-blind KEMAR recordings, 20 comparisons per scenario (plus 7 for training), 0–100 ratings given twice.
  - **Basic audio quality:** REF 32.6, UNI (classifier on) 60.0, **SSL 66.5**; all pairs differ, p < .05.
  - **Comfort:** not significant overall (p = .30). **Clarity:** not significant.
  - Benefit was "highly individual". Adjustments often hit the range limits; the low band went up by about +5 dB.
  - **Loudness matching between settings is not described.** That is a real confound for a +5 dB low-band change [O].
- Vendor blogs repeat the 84 % / 89 % with no n or design [G8].
- **Lesson** [O]: the headline number depends on the baseline. Test against the *strongest* static alternative.

**Preference-learning EQ research:**
- **Pardo group** [G10]: n = 19 learned an EQ weighting from about 20 ratings (15–30). Embedding 25 duplicate probes among 75 gave a median **test-retest r = 0.69**. Machine-vs-user agreement was 0.67, about the listener's own consistency, and users judged the learned control at a median 0.75 on a −1 … 1 "did it learn?" scale.
  - **Lesson:** a model cannot predict a listener better than the listener predicts himself. **Measure the founder's self-consistency** with embedded repeats.
- **DTU/Widex** (Nielsen et al. 2015, U): 10–20 pairwise trials (5–10 min) personalised up to 4 parameters, and the result was preferred over the initial fitting.
- **Self-adjusted gain** [G32]: n = 30 spans about 40 dB across people. Listener factors explain ≤ 10 % of the between-person variance, yet people are stable on repeats. Personal models are justified, and population averages mislead.

**Harman** [G5]:
- Preference **classes**: 64 % prefer the target, 15 % want +4–6 dB bass, 21 % want 2 dB less bass.
- "A simple solution for headphone personalization is to provide a simple bass and treble control."
- Validation used blind ratings by large groups (130–283) plus a trained 10-listener core.

**Sonarworks:** ">78 % … in blind testing", "39,000 completed preference tests", with no protocol [G12, D]. **Sony:** I found no published validation of its EQ personalisation (one search; the market track may have more).

**In-product metrics** (generative music and other adaptive features):
- **MusicRL** [G11]:
  - 300k user pairs were collected with an *optional* trophy. Only pairs where **both clips were heard** were kept.
  - The preference reward model reached **60 %** held-out accuracy, and the team agreed with the users **60 %** of the time.
  - Raters judged 101 prompts × 3 raters, with win rate = win / (win + loss) and a Wilcoxon test.
  - The model **over-optimised the user reward within < 2k steps**.
- **Android Adaptive Brightness** [G17] judged its on-device learner by **manual override rate**: about half of test users made fewer adjustments after a week, and slider interactions fell 10 %. That is internal users with no control group, which is exactly the weakness to avoid.

**The metrics I'd define for AdaptiveSound** [O]:

| Metric | Definition | Trap | Mitigation |
|---|---|---|---|
| **Override rate** | Manual EQ/Tone edits, or theme switches, per hour of adaptive playback | Novelty: effects decay over 2–3 weeks [G15] | Run ≥ 3–4 weeks and plot the effect against days since first exposure [G15] |
| **Revert rate** | Share of adaptive changes undone within 30 s, or Compare held and then the EQ switched off | Default / status-quo effect inflates "keep" (U, Mackay 1991) | A **randomised hold-out**: on X % of tracks, blindly apply the static theme preset instead |
| **Keep rate** | Tracks finished with adaptive on and no override | Same as above | Same |
| **Feedback rate and balance** | "Better" and "not" presses per hour, and their ratio | Presses come at low moments → **regression to the mean** makes any next move look good [G14]. Labels alone sway judgment [G13] | Count only presses ≥ 5 s after a change. In dogfood, answer a random 10–20 % of "not" presses with a sham (no change) to measure the true effect |
| **Theme drift** | Distance of the learned setting from the theme's prior | Reward over-optimisation [G11] | A bound in CI (§2.4) and a check |

**Bias summary** (each with its control):
- **Expectation and labels** [G4 Toole & Olive (12 % of scale), Bentler (33 of 40 preferred an identical aid labelled "digital"); G13] → double-blind.
- **Recency** (up to 23 % or about 50 % of the scale) [G4] → short, consistent excerpts.
- **Contrastive spectral adaptation** [G18] → re-cue before each pair and counterbalance.
- **Loudness** → §2.2.
- **Novelty and primacy** [G15] → long runs and a hold-out.
- **Regression to the mean** [G14] → randomised control.
- **"Different = better"** [O: a mix of novelty, contrast and expectation] → the Original must always be a blind condition, and O-vs-O null pairs estimate position bias.

### 2.4 Offline and automatic proxies for CI: which to trust

**Trustworthy for EQ** (they test properties we can state exactly; fits the existing null-test and golden-master culture [R1]):

1. **Safety invariants** (property tests over random and corpus inputs, like the nightly "1000 random curves" test [R1]):
   - per-band and per-macro bounds: the theme bound, inside the Arbiter's design clamps (+10/+12 dB, 3–5 kHz +8 dB, low-confidence ±3 dB) [R4];
   - **loudness neutrality** after the neutral gain: |ΔL_int| ≤ 0.2 dB (the engine measures 0.112 dB max [R2]);
   - **slew and transitions:** changes only at chosen boundaries, with a glide of at least τ and at most X dB/s. The numbers come from Track B (RO4);
   - **no change within N s of a detected phrase or onset**, if a detector exists;
   - **Intensity 0 and Pure Mode** still bit-exact (the existing nulls [R1]).
2. **Determinism / golden master for a model-driven contributor:**
   - PyTorch: "Completely reproducible results are not guaranteed across PyTorch releases, individual commits, or different platforms", and CPU vs GPU may differ [G26]. So don't hash audio from the model path.
   - Instead, **hash a quantised decision timeline**: (boundary frame, Tone vector rounded to 0.1 dB), FNV-1a, computed on a CPU-only reference run. This mirrors the stereo golden master `0xE7267654BA01D315` [R1, O].
   - Pin the model version and a hash of the weights. Re-baseline only on founder approval, as with DSP changes.
3. **Metamorphic / behavioural tests** (the CheckList idea of invariance and directional-expectation tests; practitioners found about 3× more bugs with it [G27]):
   - **invariance:** −6 dB input level → the same decisions; FLAC vs 256k AAC of the same master → within 0.5 dB; +1 s of leading silence → the same decisions shifted by 1 s;
   - **directional:** add a known +3 dB treble shelf → the policy's Air/Presence decision drops by ≥ 1.5 dB;
   - **restraint:** on pristine reference masters under the neutral theme, |decision| ≤ 1 dB per macro on ≥ 90 % of tracks.
   - "Undo a known EQ" is the only offline task with **ground truth**. On deliberately damaged music, a content-aware restorer won 60–4 in a blind pairwise test, and an average-spectrum correction *lost* 13–51 (A-S5, n = 8).
4. **Model-to-model behaviour diff** (nightly, on the corpus): the distribution of proposed Tone vectors per genre. Flag when the median shifts by > 0.5 dB between versions [O].

**Known to mislead for EQ:**

- **Learned no-reference quality predictors as critics or gates:**
  - **Audiobox Aesthetics** reports only across-clip correlations (music PQ r = 0.887 on AES-Natural, 0.587 on PAM-music). It runs at 16 kHz mono, and no EQ or same-content test has been done [G24; A-S23, A-S24, A-S29].
  - **Our own probe** [G25: Track D bench, 3 clips]:
    - a ±6 dB treble shelf moves PQ by +0.01 … +0.37 (same sign in 9/9 windows, higher whenever brighter);
    - a harsh +9 dB at 3 kHz moves it by −0.02 … −0.39;
    - a 0.5–2 s misalignment of the *same* audio moves it by up to 0.29;
    - on the dense band clip, no EQ moves it by more than 0.03.
  - So its EQ signal is no bigger than its noise, it is ceiling-limited, and it is biased toward brightness. **Log it as a diagnostic at most.**
  - Optimising against it invites reward hacking (A-S27). One related predictor (SongEval) even trains with ±3 dB EQ augmentation, i.e. it is taught to ignore Tone-sized changes (A-S29).
- **Full-reference impairment metrics** (PEAQ, ViSQOL, PEMO-Q):
  - By design they measure distance from the reference. ViSQOL "presumes a clean reference", and its authors "would not recommend using ViSQOL for automated regression tests [on music] without retraining the model" [G20].
  - PEAQ's limits come largely from its distortion-to-score mapping [G22].
  - On production degradations, ViSQOL had low sensitivity to hum and glitches, and PEAQ Advanced behaved anomalously. No EQ condition and no listening test were included [G21].
  - **Use them at most as a "faithfulness budget"** (how far from the original), never as a "better" signal [O].
- **Raw spectral distances:**
  - MSE on spectrograms agreed with human same/different judgments only 43–66 % of the time in 2AFC (chance is 50 %). That is on a set of about 52k judgments that included 3-band EQ perturbations [G23, speech-centric].
  - **Distance to an average target curve** fits the average, not this record's intent; the average-spectrum correction lost 13–51 (A-S5).
  - Harman's distance-to-target model predicts *headphone* preference (r = 0.86, error 6.7 / 100) [G5]. It is not validated for content EQ on finished masters (gap).

### 2.5 The evaluation plan for this product, in three stages

*Shared rules (every stage):*
- **Pre-register** the track list and the pass bars before listening.
- **Three conditions:** **O** (Original: the EQ at flat through the same chain), **S** (the best *static* preset for the chosen theme), **A** (Adaptive, same theme).
- All rendered offline through the C++ kernel. This needs the corpus driver that `validation-strategy.md` lists as missing ("Test 2", aspirational) [R1]. Building it once serves all three stages [O].

#### Stage 0: offline feasibility probe (agents; no listening)

- **Decision it unlocks:** whether the founder's listening time is worth spending, i.e. is there a safe, stable and *audible* difference to test?
- **Material:** ≥ 60 tracks across genres and decades, including the repo's 7-track corpus. Plus a damage set of the same tracks × 10 random tone errors each (±3–6 dB shelves and tilts): about 600 cases.

| Check | Pass bar [O] |
|---|---|
| Safety invariants, loudness neutrality (≤ 0.2 dB), boundaries and slew, Intensity 0 / Pure nulls | 100 % |
| Determinism: decision-signature hash identical on 3 runs (CPU reference) | 100 % |
| Metamorphic invariance: level, codec (within 0.5 dB), offset | ≥ 99 %, exceptions listed |
| **Recovery** on the damage set: correlation between applied error and correction (sign-flipped) per macro | r ≥ 0.7, and residual RMS ≤ 1 dB |
| **Restraint** on pristine masters (neutral theme) | |decision| ≤ 1 dB per macro on ≥ 90 % |
| **Something to hear**: A differs from S by ≥ 1 dB in some macro | on ≥ 30 % of tracks; otherwise stop: nothing audible to test |
| Audiobox PQ, PEAQ/ViSQOL distance | Logged only, not gating |

#### Stage 1: founder blind A/B, by ear (2–3 h over about a week)

- **Decision it unlocks:** build it, meaning invest in the Arbiter contributor, the UI and the feedback loop, and recruit a panel. The alternatives are to iterate on the model or to stop and keep static presets.
- **Instrument:**
  - Pre-rendered, loudness-matched pairs in a small blind 2AFC player (randomised X/Y, ≈ 40 ms crossfade switching, time-aligned, replays allowed, every choice logged) [G1].
  - Or a debug-only "Blind Compare" mode in the app (Track D, RO8).
  - Use the founder's usual headphones at his usual level.
- **Material:** 12–16 tracks, half his picks and half random from the library. 20–30-s excerpts, starting after the loudness profile has landed [R2]. Use one or two themes (e.g. Warm and Clarity).

| Sub-test | Design | Sample size | Pass bar |
|---|---|---|---|
| **1a: A vs S** (the core question) | 2AFC, counterbalanced AB/BA, blocked by track | SPRT p₀ 0.5 / p₁ 0.7, α .05, β .2: ≈ 23 trials expected, cap 60 | SPRT accepts "prefers A" (e.g. ≥ 16/20 or ≥ 22/30), or ≥ 37/60 at the cap counts as weak; A must not be clearly worse on any track (no track with 4/4 for S) |
| **1b: A vs O** | Same | Same | Mirror SPRT does **not** accept "prefers O" (A is not worse than doing nothing); "prefers A" is a bonus |
| **Controls inside 1a/1b** | 20 % repeated pairs; ~10 % O-vs-O null pairs; ~10 % level-catch pairs (+0.3 dB) | about 15–20 extra trials | Self-agreement on repeats ≥ 70 %; null pairs show no side bias (≤ 70 % one side); catch pairs no louder-preference (≤ 65 %), else re-match loudness perceptually (§2.2) |
| **1c: "did the EQ move?"** | 2AFC on 30–45-s clips, one with a mid-clip adaptive transition and one static: "which changed?" | ≈ 70 trials, or SPRT p₀ 0.5 / p₁ 0.65 | Detection not accepted; 95 % upper bound on p(correct) < 0.6 |

- **Sessions:** ≤ 20–30 min with ≤ 15–20 trials, with rest between sessions [G1].
- **Interpretation** [O]:
  - The result is about **this listener only** (N-of-1 [G30]).
  - The founder prefers faithful, minimally processed sound, so a pass is strong evidence and a fail is not proof the feature has no market. That is why Stage 2 exists.
  - If A passes against O but not against S, the adaptivity is not earning its complexity. Ship the static theme instead.

#### Stage 2: small blind panel, 10–15 people (about 45 min each)

- **Decision it unlocks:** default-on vs opt-in, which themes ship, and which public claims are allowed.
- **Panel:** 10–15 people, 3–4 trained and the rest music lovers, on their own headphones. Device differences cancel within a pair.
  - Each listener first picks their theme, so the test matches the product.
  - Remote, pre-rendered stimuli in a web 2AFC/MUSHRA-style page (webMUSHRA supports AB and forced-choice pages, U).
- **Per listener:** 3 pairs (A–S, A–O, S–O) × 10 tracks × 2 orders = 60 trials. Plus 6 anchor trials (O vs a 3.5 kHz low-pass, as in BS.1534) and 6 O-vs-O nulls. About 72 trials in 2 sessions.
  - Optional: a CCR −3 … +3 rating after each choice, for magnitude [G19].
- **Analysis:** mixed-effects logistic regression (random effects for listener and track) and Bradley–Terry scale values for O, S and A. Report pooled and per-listener results.
- **Post-screening:** exclude a listener who prefers the low-pass anchor on > 15 % of anchor trials (the BS.1534 analogue [G2]) or whose null pairs show > 80 % side bias.

**Power** [M]:
- 153 independent trials detect a pooled p = 0.6 with 80 % power.
- Trials cluster by listener. With 20 trials each and ρ = 0.02–0.05, the design effect is 1.4–2.0, so **10–15 listeners** are needed for p ≈ 0.6.
- **5 listeners detect only about p ≥ 0.65**: 67 × 1.4–2.0 ≈ 94–134 trials.

**Pass bars** [O]:
- pooled P(A ≻ S) ≥ 0.6, with the 95 % CI lower bound > 0.5;
- P(A ≻ O): lower bound > 0.5, or non-inferior (lower bound > 0.45) for a neutral theme;
- no track significantly O ≻ A;
- ≥ 70 % of listeners individually at ≥ 50 % A over O;
- artefact reports ≤ 10 % (the repo's existing criterion [R1]).

#### After Stage 2: in-product evidence (dogfood, then users)

- A randomised **hold-out**: on 20–30 % of tracks, blindly use S instead of A.
- Track override, revert, keep and feedback rates (§2.3) for **≥ 3–4 weeks**, plotted against days since first exposure [G15].
- Use always-valid sequential monitoring, so the dashboard can be checked at any time without peeking errors [G16].
- Decide on the hold-out contrast, not on raw "keep rate".

---

## 3. Evidence table

`ID | RO(s) | type | claim | numbers (n, effect size, test type) | method / output | code + weights licence | limitation | grade | URL`

| ID | RO | Type | Claim | Numbers | Method / output | Licence | Limitation | Grade | URL |
|---|---|---|---|---|---|---|---|---|---|
| G1 | 12 | ITU-R standard | BS.1116-3: double-blind triple-stimulus hidden-reference method for *small impairments* | "20 subjects … often sufficient"; ≥ 5 excerpts (1.5 × objects), 10–25 s; sessions 20–30 min, 10–15 trials; ~40 ms switching; post-screen by one-sided t-test on difference grades | 1.0–5.0 impairment scale; ANOVA | n/a | Differences are impairments by definition; not for preference | B | https://www.itu.int/rec/R-REC-BS.1116-3-201502-I/en |
| G2 | 12 | ITU-R standard | BS.1534-3 MUSHRA for *intermediate* quality | "no more than 20 assessors … often sufficient"; exclude if hidden ref < 90 on > 15 % of items or mid anchor > 90 on > 15 %; anchors LP 3.5/7 kHz; items ≈ 10 s (≤ 12); scores 80–100 "may be invalid"; "name MUSHRA is often misused" | 0–100 continuous scale | n/a | Reference pinned at top | B | https://www.itu.int/rec/R-REC-BS.1534/en |
| G3 | 12 | ITU-R standard | BS.1770-5 loudness is "an estimation … with some degree of uncertainty"; psychoacoustic models "may provide improved" measures | K-weighting; 400 ms blocks; −70 LKFS / −10 dB gates | Loudness algorithm | n/a | Fixed, level-independent weighting | B | https://www.itu.int/rec/R-REC-BS.1770/en |
| G4 | 12 | JAES review (Zieliński, Rumsey, Bech 2008) | Systematic biases in listening tests | Toole & Olive: blind vs sighted up to 1.2/10 (12 %); Bentler: 33/40 preferred identical aid labelled "digital"; recency up to 23 % / ~50 % of scale; > 30 s excerpts problematic; MUSHRA: max score for hidden ref | Review of listener studies | n/a | Some figures second-hand; "up to 40 %" in the AES abstract not seen (U) | A | https://www.aes.org/e-lib/browse.cfm?elib=14393 (opened via http://www.acourate.com/Download/BiasesInModernAudioQualityListeningTests.pdf) |
| G5 | 5, 12 | Acoustics Today (ASA) review, Olive 2022 | Harman methods, classes, preference model | Virtual vs real headphones r = 0.86–0.99; 130 and 283 listeners; 10 trained listeners for initial target; classes 64/15/21 %; AE/OE model r = 0.86 (6.7 pts / 100), IE r = 0.91 | Double-blind virtual headphone; method of adjustment | n/a | Headphone responses, not content EQ; pp. 60–63, 65 opened | B | https://acousticstoday.org/issues/2022AT/Spring2022/files/basic-html/page61.html |
| G6 | 6, 12 | Trends in Hearing 2019 (Jensen et al.) | ML (SoundSense Learn) gain vs prescription, double-blind | n = 20; 20 comparisons per scenario + 7 training; 3 bands; BAQ 32.6 / 60.0 / 66.5 (p < .05); Comfort p = .30; Clarity n.s.; low band ≈ +5 dB, hits limits | KEMAR recordings, 0–100 ratings ×2 | Proprietary | Hearing-impaired, lab; loudness matching not described | A | https://doi.org/10.1177/2331216519847413 |
| G7 | 12 | Trade article, Widex authors (Townend et al. 2018) | SSL lab test | n = 19, double-blind, ratings ≥ 3 days later; 84 % / 89 % preferred SSL over *No Active Classifier*; vs Active Classifier p < .01 (comfort) | BS.1534 continuous quality scale | Proprietary | Vendor; weak baseline for headline %; no field data | C | https://www.hearingreview.com/hearing-products/hearing-aids/real-life-applications-machine-learning-hearing-aids-2 |
| G8 | 10, 12 | Vendor blog | Repeats 84 % / 89 % | No n or design | — | — | Marketing | D | https://www.widexpro.com/en/blog/global/can-soundsense-learn-give-clients-better-hearing-experience/ |
| G9 | 6, 12 | IEEE/ACM TASLP 2015 (Nielsen, Nielsen, Larsen) | GP active-learning personalisation | n = 10; 10–20 pairwise ≈ 5–10 min for ≤ 4 params; preferred over initial fitting | GP + active learning | — | Not opened (abstract via search index) | U | https://doi.org/10.1109/TASLP.2014.2377581 |
| G10 | 6, 12 | JAES 2011 (Sabin, Rafii, Pardo) | Learned EQ from ratings; listener self-consistency | n = 19; 25 duplicate probes in 75; test-retest median r = 0.69; machine-vs-user 0.67; "learned it" 0.75; asymptote ≈ 20 (15–30) ratings | Weighting-function EQ | — | Descriptors, 5-s solo clips | A | https://users.cs.northwestern.edu/~zra446/doc/Sabin-Rafii-Pardo%20-%20Weighting-Function%96Based%20Rapid%20Mapping%20of%20Descriptors%20to%20Audio%20Processing%20Parameters%20-%20JAES%202011.pdf |
| G11 | 6, 12 | ICML 2024 (MusicRL) | User-preference noise; evaluation design; over-optimisation | 300k pairs (both heard); reward model 60 % held-out; team–user agreement 60 %; quality predictor 53.3 %; 101 prompts × 3 raters; Wilcoxon; RL-U over-optimised in < 2k steps | Bradley–Terry reward model | — | Generation, not EQ | A | https://arxiv.org/abs/2402.04229 |
| G12 | 10, 12 | Press release | Sonarworks SoundID preferred by "> 78 % … in blind testing" | 39,000 completed preference tests; no protocol | A/B rounds + hearing test | Proprietary | Unverifiable | D | https://audioxpress.com/news/sonarworks-enables-personalized-audio-perfected-for-any-device-with-soundid |
| G13 | 12 | Ear & Hearing 2011 (Dawes, Powell, Munro) | Placebo / labels | n = 20 identical aids; quality 9.12 vs 8.35 (p < .01); 15/20 preferred "new" (p = .02) | Randomised labels | — | Hearing aids | A | https://europepmc.org/article/MED/21730857 |
| G14 | 12 | Int J Epidemiol 2005 (Barnett et al.) | Regression to the mean | Grows with measurement error and with selection on a baseline value | Methods | — | General | B | https://europepmc.org/article/MED/15333621 |
| G15 | 12 | Preprint, Microsoft (Sadeghi et al. 2021) | Novelty / primacy in online experiments | −5.07 % (first 3 days) → −1.23 % (week 3, n.s.); ≈ 300k users/arm; DID test | Difference-in-differences | — | Web products | B | https://arxiv.org/abs/2102.12893 |
| G16 | 12 | Preprint (Johari, Pekelis, Walsh) | Continuous monitoring makes fixed-n p-values "wholly unreliable"; always-valid p-values | — | mSPRT | — | — | B | https://arxiv.org/abs/1512.04922 |
| G17 | 12 | Vendor engineering blog (Android 2018) | Adaptive Brightness evaluated by manual-override rate | ≈ half of test users fewer adjustments after 1 week; slider interactions −10 % | On-device learner | Proprietary | Internal users, no control | C | https://android-developers.googleblog.com/2018/11/getting-screen-brightness-right-for.html |
| G18 | 4, 12 | Sci Rep 2021 (Siedenburg, Barg, Schepker) | Brightness judgments adapt contrastively to preceding spectral context | Exp 1 n = 19 (slope β 1.45; adaptation β −0.24); Exp 3 n = 20: 0.66 vs 0.31 "bright"; stabilises after ≈ 8 × 2-s trials | 2AFC bright/dull | — | Judgments, not preference | A | https://doi.org/10.1038/s41598-021-00707-7 |
| G19 | 12 | Interspeech 2021 (Naderi, Möller, Cutler) | CCR (−3 … +3) can assess systems better than the reference | Runs: ICC 0.94, Pearson ≈ 0.94; CMOS CI ≈ 0.18–0.20; ≈ 2× ACR cost | P.800 CCR, crowd | — | Speech | A | https://arxiv.org/abs/2104.04371 |
| G20 | 12 | QoMEX 2020 (ViSQOL v3) | Full-reference NSIM metric; authors advise against music regression tests without retraining | No music correlation reported | Gammatone NSIM → MOS | Open source (licence not checked, U) | Codec-trained | B | https://arxiv.org/abs/2004.09584 |
| G21 | 12 | DAFx 2025 (He, Williams, Fazenda) | 5 FR metrics on production degradations | 12 MUSDB18 clips; ViSQOL low sensitivity to hum/glitch; PEAQ Adv anomalies | Effectiveness + robustness tests | Code promised | No EQ condition, no listeners | B | https://dafx25.dii.univpm.it/wp-content/uploads/2025/09/DAFx25_paper_5.pdf |
| G22 | 12 | QoMEX 2020 (Delgado, Herre) | PEAQ limits; a remapped score improves it | — | — | — | Abstract only | B | https://arxiv.org/abs/2212.01467 |
| G23 | 12 | Interspeech 2020 (Manocha et al., DPAM) | JND-trained metric; dataset includes 3-band EQ perturbations | ≈ 52k crowd judgments; MSE-spectrogram 2AFC 43–66 %; ViSQOL 44–84 % | Learned metric | — | Speech-centric | A | https://arxiv.org/abs/2001.04460 |
| G24 | 2, 12 | Preprint 2025 (Meta, Audiobox Aesthetics) | 4-axis aesthetics predictor | Music PQ r = 0.887 (AES-Natural), 0.587 (PAM-music); 3 ratings × 97k clips | 16 kHz mono, 10-s windows | CC-BY-4.0 (majority of code); weights not separately stated | Across-clip only; no EQ test | A | https://arxiv.org/abs/2502.05139 |
| G25 | 2, 12 | In-house probe (Track D bench; read by me) | Audiobox PQ vs EQ on the same clip | 3 clips; treble +6 ΔPQ +0.01 … +0.37 (9/9 sign); harsh +9 dB @ 3 kHz −0.02 … −0.39; 0.5–2 s shift |ΔPQ| ≤ 0.29; band clip ≤ 0.03 | Loudness-matched variants | — | 3 clips, one model | M | `scratchpad/bench-results/aes_summary.txt` |
| G26 | 12 | Official docs (PyTorch) | Reproducibility not guaranteed across releases, commits, platforms, or CPU vs GPU | — | Seeds, deterministic algorithms | BSD | Framework-specific | C | https://docs.pytorch.org/docs/2.14/notes/randomness.html |
| G27 | 12 | ACL 2020 (CheckList) | Behavioural tests (invariance, directional) find bugs that held-out metrics miss | ≈ 3× more bugs found by practitioners | Test matrix | Not checked | NLP domain | B | https://arxiv.org/abs/2005.04118 |
| G28 | 12 | ISO 16820:2019 overview | Sequential analysis for 2-AFC/triangle tests: stop and declare a difference, no difference, or continue after each trial | — | SPRT-type | n/a | Overview only | B | https://knowledge.bsigroup.com/products/sensory-analysis-methodology-sequential-analysis |
| G29 | 12 | ISO 532-3:2023 catalogue | Moore–Glasberg–Schlittenlacher loudness for time-varying sounds incl. music; single overall value > 5 s out of scope | — | Loudness model | n/a | Catalogue scope | B | https://genorma.com/en/standards/iso-532-3-2023 |
| G30 | 12 | History of N-of-1 trials (Guyatt 1986) | Single-subject RCTs: randomised paired periods, blinding, preset decision rules | — | — | — | Medical | B | https://www.jameslindlibrary.org/articles/history-development-n-1-trials/ |
| G31 | 12 | Trends in Amplification review 2009 (Amlani, Schafer) | Paired comparison is "sensitive, valid, and reliable" for hearing-aid settings | — | Round-robin, adaptive strategies | — | Abstract only | B | https://europepmc.org/article/PMC/PMC4111476 |
| G32 | 6, 12 | Trends in Hearing 2019 (Perry, Nelson, Van Tasell) | Self-adjusted gain varies hugely, and listener factors explain little | n = 30; 1,019 trials; ≈ 40 dB spread; ≤ 10 % variance explained; stable on repeats | Self-adjustment | — | Hearing aids | A | https://europepmc.org/article/PMC/PMC6423677 |
| G33 | 12 | Preprint 2025 | Pair-scheduling: Sort-MST / Hybrid-MST beat random; knockout ≤ random | Simulations, 8–32 stimuli | Bradley–Terry | — | No audio data | B | https://arxiv.org/abs/2508.17840 |
| R1 | 12 | Repo | Gate culture; planned "MUSHRA" uses a 5-point scale; panels never run; corpus driver missing | Golden master `0xE7267654BA01D315` | — | — | — | repo | `docs/architecture/validation-strategy.md` |
| R2 | 12 | Repo (measured) | Loudness-neutral predictor accuracy | 0.112 dB max, 0.036 p90 (7 tracks × 15 curves); first 10 s up to 2.69 dB; 3-s wander −2.9 … +0.9 dB | Gated 1/24-oct profile | — | — | repo | `docs/design/eq-lens/plan/engine-plan.md` §4 |
| R3 | 12 | Repo (measured) | Limiter differs between On and Off at Intensity 0 on loud masters | GR > 1 dB ≈ 43–52 % of time for 3 presets; On ≈ 1.2–1.4 dB under Off | — | — | — | repo | `docs/design/eq-lens/plan/preset-revoice.md` §3, §5 |
| R4 | 7, 12 | Repo (design) | Arbiter hearing-safety clamps | +10/+12 dB; 3–5 kHz +8 dB; low-confidence ±3 dB; short-term ceiling | — | — | Not built | repo | `docs/architecture/architecture.md` §11 |
| R5 | 8, 12 | Repo (code) | Compare is sighted hold-to-compare at matched loudness | — | — | — | Not blind | repo | `Sources/AdaptiveSound/UI/EQ/EQCompareButton.swift` |
| U1 | 12 | JAES 1986 (Leventhal) | Type II error of short ABX tests | (Quoted: 0.83 miss at p = 0.6 with 16 trials) | Binomial | — | Paywalled; numbers recomputed in §2.1 | U | https://www.aes.org/e-lib/browse.cfm?elib=5265 |
| U2 | 12 | AES 2022 (Berendes, Travaglini, Uhle) | BS.1770 vs listener-chosen alignment gains | 2.2 dB average difference; validation +16 % MOS | Adjustment tests | — | Abstract via search index only | U | https://www.aes.org/e-lib/browse.cfm?elib=21908 |
| U3 | 12 | JAES 2003 (Olive) | Trained and untrained listeners share preferences; trained are more reliable | 199 listeners, 4 speakers, 28 tests | — | — | Abstract via search index only | U | https://www.aes.org/e-lib/browse.cfm?elib=12206 |
| U4 | 12 | AES 1998 (Olive, Castro, Toole) | MLL speaker shuffler eliminates positional bias (9 speakers) | — | — | — | TLS error; snippet only | U | https://www.harman.com/documents/HarmanWhitePaperMLLListeningLab_0.pdf |

Cross-track sources cited (graded by Track A, not re-opened): **A-S5** (blind EQ restorer, n = 8, 60–4; average-spectrum correction 13–51), **A-S23** (Audiobox PQ picks the human's choice 59.1 % on 1,889 pairs), **A-S24** (SonicMaster: EQ category not significant, n = 12), **A-S27** (Audiobox-only DPO consistent with reward hacking), **A-S29** (SongEval predictor uses ±3 dB EQ augmentation).

---

## 4. Search log

| # | Query (abridged) | Source | Hits screened | Included |
|---|---|---|---|---|
| 1 | ITU-R BS.1116-3 small impairments listeners post-screening | WebSearch → ITU PDF | 10 | 1 (G1) |
| 2 | ITU-R BS.1534-3 MUSHRA hidden reference anchor post-screening | WebSearch → ITU PDF | 9 | 1 (G2) |
| 3 | Leventhal 1986 type 1/2 errors ABX trials | WebSearch | 9 | 0 (U1; Stereophile 403) |
| 4 | Boley & Lester ABX signal detection theory | WebSearch | 9 | 0 |
| 5 | Olive trained vs untrained listeners | WebSearch | 10 | 0 (U3) |
| 6 | Olive/Welti in-room & headphone target preferences | WebSearch → Acoustics Today | 10 | 1 (G5) |
| 7 | Harman MLL shuffler loudness matched | WebSearch | 10 | 0 (U4; TLS) |
| 8 | Toole & Olive hearing is believing blind vs sighted | WebSearch | 9 | 0 (via G4) |
| 9 | Skovenborg & Nielsen loudness models | WebSearch | 9 | 0 (PDF 500) |
| 10 | level matching 0.1 dB louder preferred | WebSearch | 9 | 0 (forums only) |
| 11 | Soulodre evaluation of loudness meters | WebSearch | 10 | 0 |
| 12 | BS.1770 accuracy spectrally different / Moore TVL (extended) | WebSearch | 9 | 1 (U2) + G3 |
| 13 | Jensen 2019 Trends in Hearing ML gain | WebSearch → Europe PMC | 10 | 2 (G6, G32) |
| 14 | Nielsen GP active learning hearing aids | WebSearch | 9 | 1 (G9, U) |
| 15 | Dawes placebo hearing aid | WebSearch → Europe PMC | 9 | 1 (G13) |
| 16 | Widex SSL field study | WebSearch → Hearing Review | 9 | 2 (G7, G8) |
| 17 | MusicRL human preference evaluation | WebSearch → text | 9 | 1 (G11) |
| 18 | Audiobox Aesthetics correlation | WebSearch → arXiv HTML, GitHub | 9 | 1 (G24) |
| 19 | PAM audio-language quality | WebSearch | 9 | 0 (Track A has it) |
| 20 | PEAQ ViSQOL linear distortion EQ (extended) | WebSearch | 9 | 2 (G21, G22) |
| 21 | PEAQ AvgLinDist MOV | WebSearch | 10 | 0 |
| 22 | ViSQOL v3 | WebSearch → ar5iv | 9 | 1 (G20) |
| 23 | Olive virtual headphone method loudness | WebSearch | 10 | 0 |
| 24 | Zieliński biases review | WebSearch → PDF | 9 | 1 (G4) |
| 25 | ISO 16820 sequential analysis | WebSearch → BSI | 10 | 1 (G28) |
| 26 | Burstein ABX approximation formulas | WebSearch | 9 | 0 |
| 27 | Sonarworks SoundID blind test | WebSearch → audioXpress | 10 | 1 (G12) |
| 28 | novelty/primacy online experiments | WebSearch → arXiv | 18 | 1 (G15) |
| 29 | Harman How to Listen | WebSearch | 9 | 0 |
| 30 | Bradley–Terry audio paired comparison | WebSearch → arXiv | 18 | 1 (G33) |
| 31 | small loudness differences preference (extended) | WebSearch | 9 | 0 |
| 32 | ITU journal directional weights JND | WebFetch (PDF too large) | 1 | 0 |
| 33 | Wichern loudness features automixing | WebSearch | 9 | 0 |
| 34 | ISO 532-2 / 532-3 | WebSearch → catalogue | 20 | 1 (G29) |
| 35 | status quo defaults / Mackay | WebSearch | 19 | 0 |
| 36 | regression to the mean (Barnett) | WebSearch → Europe PMC | 9 | 1 (G14) |
| 37 | Android Adaptive Brightness | WebSearch → blog | 10 | 1 (G17) |
| 38 | Nest learning thermostat overrides | WebSearch | 10 | 0 |
| 39 | auditory colour constancy / adaptation | WebSearch → Europe PMC | 10 | 1 (G18) |
| 40 | test-retest preferred bass/treble | WebSearch | 18 | 0 |
| 41 | Sabin & Pardo EQ preference learning | WebSearch → PDF | 9 | 1 (G10) |
| 42 | ITU-T P.800 CCR | WebSearch → arXiv | 27 | 1 (G19) |
| 43 | PyTorch reproducibility; Core ML compute units | WebFetch / WebSearch | 9 | 1 (G26) |
| 44 | DPAM JND metric | WebFetch arXiv | 1 | 1 (G23) |
| 45 | CheckList; metamorphic testing | WebFetch / WebSearch | 10 | 1 (G27) |
| 46 | Johari always-valid inference | WebSearch → arXiv | 9 | 1 (G16) |
| 47 | Guyatt N-of-1 | WebSearch → James Lind | 10 | 1 (G30) |
| 48 | Amlani paired comparison hearing aids | Europe PMC | 1 | 1 (G31) |
| 49 | Sony Find your Equalizer validation | WebSearch | 9 | 0 |
| 50 | level roving profile analysis | WebSearch | 18 | 0 (Green 1988, U) |

**Snowball** (the 3 key sources: G1, G4, G6):
- **Backward from G4:** Toole & Olive 1994, Bentler (labels), Gros / Seferidis (recency), all used via G4.
- **Backward from G6:** Nielsen 2015 (G9, U), Townend 2018 (G7).
- **Backward from G2:** BS.2300 eGauge (noted, not opened).
- **Forward from G6:** Perry 2019 (G32, A) and a 2024 multi-band Bayesian preprint (not opened).

**Saturation note:**
- **Standards and test methods** (rounds 1–2, 24–26, 42) and **ML-metric validity** (rounds 18–22, 44): **saturated**. The last two rounds in each added no new included source.
- **Loudness-matching tolerance under EQ** (rounds 9–12, 31–33): **stopped at the cap without saturation**. The primary sources (Soulodre 2004, Skovenborg 2004, Berendes 2022, Harman methods) are AES-paywalled or failed to download (403/500/TLS).
- **In-product metrics** (rounds 28, 35–38): stopped at the cap.

---

## 5. Answers per RO

| RO | Answer | Confidence | Key sources |
|---|---|---|---|
| **RO12.1** Which listening-test method | **Blind, loudness-matched 2AFC preference**, decided by **SPRT** for the founder (about 23 trials if p = 0.7; cap 60), and **paired comparison + Bradley–Terry** (optionally with CCR) for a panel of 10–15. Use BS.1116's controls but **not** BS.1116 or MUSHRA scoring: both pin the original at the top and cannot show "better". ABX only for "can I hear it?" and for inaudibility claims (≈ 70 trials). | **High** on which methods fit; Medium on the exact trial counts (they depend on the true effect size) | G1, G2, G4, G19, G28, G30; [M] |
| **RO12.2** Loudness matching | Match BS.1770 integrated to ≤ 0.2 dB (target 0.1 dB); the engine's 0.112 dB max qualifies. Add level-catch trials and an ISO 532-1/-3 second opinion, because BS.1770's error for EQ'd versions of the same track is unmeasured. Keep both versions in the identical chain (limiter included). | Medium (tolerance is convention plus reasoning; validity of BS.1770 for this case is a gap) | G1, G3, G29, R2, R3; U2 |
| **RO12.3** Adaptive / personalised validation and pitfalls | The best-documented analogue (Widex) shows a **small** benefit against a strong baseline (+6.5 / 100, comfort n.s.), and large percentages only against a weak one. Listener self-consistency (r ≈ 0.69) and preference-label noise (≈ 60 % agreement) cap what any learner can show. Control expectation (blind), novelty (≥ 3 weeks, days-since-exposure), RTM and defaults (randomised hold-out / sham). In-product, judge by **override / revert rates against a hold-out**, not keep rate. | **High** on the pitfalls; Medium on the transfer from hearing aids to music EQ | G6, G7, G10, G11, G13, G14, G15, G17, G32 |
| **RO12.4** Offline / CI proxies | **Gate on:** safety and loudness invariants, boundary and slew rules, a quantised-decision golden master (CPU reference), metamorphic invariance, "undo a known EQ" recovery, and restraint on pristine masters. **Log only (misleading as gates):** Audiobox and other learned aesthetics (EQ signal ≤ alignment noise; brightness bias); PEAQ, ViSQOL and other full-reference metrics (any EQ = damage); raw spectral or average-target distance. | **High** that learned and full-reference scores must not gate; Medium on the exact tolerances | G20–G27, R1, R4; A-S5, A-S23, A-S27, A-S29 |
| **RO12.5** Evaluation plan | Stage 0 offline (unlocks founder time) → Stage 1 founder blind SPRT A/B vs Static and Original, plus a "did it move?" test (unlocks the build) → Stage 2 panel of 10–15, ≈ 72 trials each (unlocks default-on and claims) → randomised in-product hold-out for ≥ 3 weeks. Pass bars in §2.5. | Medium (the design is sound; the bars are my proposal, for founder decision) | §2.5; G1, G2, G6, G15, G28 |

---

## 6. Gaps (what the evidence does not answer)

1. **No published listening test of automatic or adaptive EQ on finished commercial masters against the untouched original.** Track A found the same. So the effect size we will see is unknown. If it is small (p ≈ 0.6), the founder cannot detect it alone (≈ 150 trials), and Stage 2 needs at least 15 listeners.
2. **BS.1770's loudness error for EQ'd versions of the same track** is unmeasured in anything I could open. The two closest numbers (2.2 dB across items; validation outliers) are U or second-hand. Stage 1's catch trials and the ISO 532 cross-check fill this for our own case.
3. **The Harman primary methods papers** (exact loudness-matching tolerance, shuffler timing, trained-listener statistics) are paywalled (U3, U4). I used Olive's 2022 review [G5] instead.
4. **The level difference at which loudness starts to bias *preference*** (not just detection): no primary study found. The 0.1–0.2 dB rule rests on standards practice and reasoning [O].
5. **Long-term preference vs short A/B:** brightness adaptation settles within about 16 s [G18], but I found no study of whether quick-switch EQ preferences hold after days of listening. This is why the in-product hold-out matters.
6. **Field validation of personalisation in music players** (rather than hearing aids): none with a published protocol. Sonarworks and Sony publish no design [G12].
7. **ICC / design effect for music-EQ preference panels:** I assumed ρ = 0.02–0.05. Stage 1's data (track clustering) will give the first real estimate.
