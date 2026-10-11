# Brief B: learning taste from "better / not", and how listeners hear EQ that moves

*Track B, 2026-10-10. Follows `00-research-protocol.md`. RO coverage: **RO6** (all), **RO4** (all), **RO5** (the listener-preference-classes half), **RO2** (the human-preference half). Source IDs are `B01…`. Grades: A/B/C/D/U as defined in the protocol §4. A **U** claim is never stated as fact here.*

---

## TL;DR

1. **The method is well established for this size of problem (RO6).** A Gaussian-process (GP) preference model with active query selection finds a person's preferred setting of **up to 4 continuous parameters in 10–20 paired comparisons (5–10 min)** [B10, A]. A field system using **3 bands** typically gets there in **≤15 comparisons** [B13, C]. In a synthetic 6-D test, the same family of methods **did not converge within 50 queries** [B18, A]. So the model should learn **2–4 dimensions**, not 31 bands and not freely across all 5 Tone axes.
2. **A prior cuts the cost to a handful of answers.** Rating-based EQ learning reached its plateau after **~20–25 ratings (~2 min)** [B01, A]. Using other users' data as a prior gave a usable controller after **about 3 ratings** [B04, A]. In AdaptiveSound the chosen **theme should be the prior mean**.
3. **Single answers are noisy, so the model must be probabilistic.** Test-retest consistency of EQ ratings was median **r = 0.69** in the lab [B01] and **r = 0.41** from crowd workers [B05]. In MusicRL, the reward model predicted held-out user preferences only **60%** of the time, and the team agreed with users' own labels 60% of the time [B23, A]. Never move the default on one click.
4. **Binary feedback at scale works but can be gamed (RO6/RO2).** 300,000 one-bit user preferences gave a **74% win rate** over the base model. Over-optimising a learned reward degraded other qualities, which is why KL-regularisation was needed [B23, A]. The parallel for us: if loudness is not controlled, "better" will drift toward louder or brighter.
5. **A few classes cover most listeners (RO5).** In Harman's blind headphone tests: **64%** prefer a near-neutral target, **15%** want **+4–6 dB bass**, and **21%** want about **−2 dB bass** (more often women and listeners over 50) [B24, B]. Hearing-aid field data: the **2 largest clusters cover 79%** of saved programmes on average, and **4 clusters cover >90%** in 8 of 10 situations [B13, C]. Two principal components explain **87%** of the variance in 279 learned EQ curves [B03, B]. That suggests **3–4 themes plus a 1–2-D personal offset**, mostly along bass and treble/tilt.
6. **Controls the "sounds better" button needs (RO6).** Instant switching on short-term memory (~40 ms crossfade). Sessions of **≤10–15 trials / 20–30 min**, with rest at least as long as the session [B30, B]. A gap between the two sounds of **≤2 s** (no time-order error at 0.1–2 s; a small error appears at 4–8 s) [B32, A]. Order randomised and balanced [B31, A; B45, B]. Loudness matched: the official calibration tolerance is **±0.25 dB** [B30]; I could not open any primary source that measures how much a 0.1–0.5 dB mismatch shifts preference (gap).
7. **EQ that moves mid-song: there is no direct evidence (RO4).** I found **no listening test** on how listeners perceive or judge EQ that changes within a music track. The indirect evidence points one way:
   - hearing **adapts to a steady colouration within about 16 s** (8 trials × 2 s) [B38, A];
   - a new spectrum is heard **in contrast to** the preceding one, which exaggerates a change [B37, A];
   - hearing discounts steady colouration from rooms and loudspeakers [B29, A].
   So a move is most audible right after a stable passage, and is then quickly normalised away. Faithfulness argues for a **static per-track setting by default** [B29].
8. **Faithful versus processed (RO2/RO4).** Toole's "circle of confusion": listeners hear what the artist intended only if playback resembles monitoring. He also notes that listeners sensitive to timbral imbalance can benefit from simple **bass/treble controls** [B29, A]. Olive likewise proposes a simple bass/treble control for personalisation [B24]. This supports correcting a track's tonal balance once. It does not support riding the EQ against the music's own contrast.

---

## Findings by RO

### RO6: Learning from feedback

**Rating-based EQ learning (Northwestern).**
- *Method* [B01, A].
  - 19 listeners each did 5 runs × 75 trials.
  - Each trial applies a random 40-band (ERB-spaced) probe curve built from 2–8 Gaussians (±20 dB) to a 5-s solo recording.
  - The listener rates "how warm/bright/…" on a slider from −1 to +1.
  - Each band's regression slope of rating on gain forms the "weighting function". A single multivariate regression is avoided because adjacent bands are collinear.
  - All stimuli were RMS-matched.
- *Results* [B01].
  - Test-retest median **r = 0.69**.
  - Machine vs. listener prediction median **r = 0.67**.
  - Listeners scored "captured my meaning" at a median **0.75** on a scale from −1 to 1.
  - Learning plateaued at **≈20 trials**: about 15 for the most consistent listeners and about 30 for the least. The authors' summary: "<25 ratings (~2 minutes)".
- *Limits* [B01]. The method assumes the descriptor changes monotonically with each parameter and that parameters don't interact. The same word maps to very different curves across people, and even within one person across sources.
- *Patent* [B02, B]. Median trial time was 3.7 s. In a hearing-aid variant (25 bands), learning plateaued in <20 ratings, and 2 principal components explained **95.6%** of 120 weighting functions.
- *2DEQ* [B03, B]. 279 weighting functions from 19 listeners. Two principal components explain **87%** of the variance, so a single 2-D dot can control all 40 bands.
- *Transfer learning* [B04, A]. 35 users, 5 words, 50 probe curves. With prior users' data, the machine–user correlation was **≈0.5 after one rating** versus ≈0 for the baseline (read from Fig. 4). Both reach ≈0.63–0.65 by 50 ratings. The authors claim an effective controller after "only three ratings", a ~10× reduction.
- *SocialEQ* [B05, A]. Crowd version: 633 MTurk workers, 1,102 sessions, 40 rated examples with 15 repeats. Median consistency was **r = 0.41** (95% CI 0.39–0.44). After dropping sessions with r ≤ 0, 481 participants and 731 sessions (324 words) remained. Mean session time was 292 s. Word agreement across people was low: the top agreement score was 0.294, for "tinny".
- *Unopened* (U, not used as fact): the 2008 AES paper itself [B06], ACM MM 2009 [B07], Audealize [B08].

**Paired-comparison GP + active learning (Widex/DTU).**
- *Design* [B09, B].
  - The user hears settings A and B and drags a slider for *degree* of preference (Beta likelihood).
  - Model: GP prior with SE-ARD kernel and Laplace inference.
  - ML-II hyperparameter fitting gave lengthscales that were too large with fewer than 20 observations, so the authors placed **half-Student-t priors** on the lengthscales.
  - Queries are chosen by bivariate expected improvement.
  - A 4-parameter hearing-aid setting was found in **~10 min**, and the setting was significantly preferred over the prescription (p < 0.05). This was a preliminary result for one user.
  - The authors argue pairwise comparison is preferable "due to its low cognitive load", and that "even quarters of an hour of careful listening is a very demanding task".
- *Journal result* [B10, A, abstract]. 10 hearing-impaired subjects. **10–20 pairwise comparisons (5–10 min)** were enough for up to 4 parameters. The result was significantly preferred over the initial fitting and was reproducible "with reasonable precision". The thesis states the same "ten to twenty iterations … up to four parameters" [B11, B].
- *Product, SoundSense Learn* [B12, C; vendor-authored].
  - The user makes binary A/B choices.
  - Figure caption: "only 20 iterations are needed".
  - Double-blind lab test, N = 19 (mean age 68): **84%** preferred their settings for comfort and **89%** for sound quality.
  - People "settled on varied settings" in clusters.
- *Field data* [B13, C].
  - 3 bands: bass 0.1–0.7 kHz, middle, treble 2.2–10 kHz.
  - Typically ≤15 comparisons.
  - "Millions" of A/B comparisons from thousands of users.
  - Preferences shifted over time (2020 lockdowns), so the model must allow for drift.
- *Further lab support* [B14, C]. Two double-blind lab studies showed benefits.
- *Unopened* (U): Jensen et al. 2019, Trends in Hearing [B16].
- **Scope caveat:** this line of work comes from hearing aids. AdaptiveSound uses it for *taste*, not hearing loss. Audiogram personalisation stays out of scope.

**Which algorithm for ~3–6 continuous parameters with noisy one-bit feedback?**
- **GP preference learning** [B17, B]. Probit (Thurstone) likelihood, P(x ≻ y) = Φ((f(x)−f(y))/√2σ). Noise is explicit, and hyperparameters are chosen by evidence. This is the base model that B09, B18 and B19 all build on.
- **Brochu et al.** [B18, A].
  - Probit GP plus EI. Rating scales "drift", and comparisons are cheaper for the user.
  - With 50 queries the method found the optimum on 2-D and 4-D synthetic tests but **failed on 6-D** ("requiring more than 50 user queries … would be unacceptable").
  - User study (5 subjects, matching a target): **8.56 ± 5.23** clicks with EI vs. 18.40 ± 7.87 with a Latin hypercube.
- **Preferential BO** [B19, B]. A GP with Bernoulli likelihood over "duels". Thompson-sampling duels (pbo-dts) were consistently best. Dueling-bandit baselines "need many more evaluations" because they don't model correlation between arms. Tested only up to 2-D, over 200 duels.
- **Dueling bandits** [B20, B]. Built for **K discrete options** with noisy binary comparisons (e.g. "taste of food"). Regret bounds are near-optimal, but nothing is shared between arms. Fit for us: choosing among a few *themes*, not tuning continuous gains.
- **qEUBO** [B21, B]. Bayes-optimal in one step when there is no noise, with a constant-gap guarantee under noise. Outperforms other PBO acquisitions. A good modern choice of acquisition.
- **Sequential line search** [B22, A]. Asks for one slider move along a line chosen by BO, not a pairwise pick.
  - Converges much faster than 2- or 4-option galleries at 2, 6 and 20 dimensions.
  - Photo enhancement over 6 parameters in 15 iterations.
  - The task takes less than 2× as long as a comparison but converges more than 2× faster.
  - Robustness came from the median of ≥5 crowd answers and a BTL likelihood that down-weights high-variance answers.
- **Answer:** for 2–4 parameters with noisy binary feedback, use **GP preference learning** (probit/BTL likelihood) with **Thompson-sampling or qEUBO** queries. Add **lengthscale priors** [B09] and a **theme prior mean** [B04]. Use dueling bandits only for discrete theme selection.

**Binary feedback at scale (MusicRL)** [B23, A].
- Data: users optionally gave a trophy to one of two 20-s clips. 300k pairs were used to train a reward model, which reached 60% accuracy on 15k held-out pairs.
- MusicRL-U beat the base model **74%** of the time; adding the hand-designed rewards, MusicRL-RU won **87%**.
- Pitfalls:
  - the labels are subjective and noisy (team agreement with user labels was 60%);
  - **reward over-optimisation**: training on the quality reward past about 10k steps lowered user-preference scores;
  - over-optimising the user reward lowered text adherence, hence KL regularisation;
  - text-adherence and quality predictors explained user preference barely above chance (51.6% and 53.3%).

**Biases a "sounds better" button must control.**
- **Memory and switching** [B30, B]. "Long- and medium-term aural memory is unreliable": rely on short-term memory, with near-instant switching of about **40 ms** fade-down/changeover/fade-up. Sessions ≤20–30 min, **10–15 trials** per session, rest ≥ session length. Use a hidden reference and post-screening.
- **Comparing from memory fails** [B42, A]. Melody changes of up to 4 semitones heard across a 500-ms gap often went unnoticed, even by professional orchestral musicians. Memory keeps a "gist".
- **Order and time error** [B32, A]. Brightness comparisons of noise showed **no time-order error at gaps of 0.1–2 s** and a small negative error at 4–8 s.
- **Balanced order and level alignment** [B31, A]. A fully balanced design puts each sound first and second equally often, and stimuli were RMS-aligned "to prevent loudness differences". Paired comparisons avoid rating-scale biases but cost time.
- **Example in a closely matched task** [B45, B]. Randomised A/B positions and BS.1770 loudness alignment to −18 LUFS.
- **Order effects in mix-level preference.** A primacy effect is reported [B33], but I couldn't open the paper (U).
- **Loudness.**
  - The opened official tolerance for calibrated listening level is **78 ± 0.25 dBA** [B30].
  - The figures of 0.1–0.2 dB I found come only from forums (D, excluded).
  - The claim that louder playback makes reproductions seem fuller and brighter [B36] is U.
  - So the strict number is engineering practice, not a measured threshold.
- **Expectation and sighted bias.** Toole & Olive 1994 [B34] and the trained-vs-untrained study [B35] are U. The opened vendor studies used **double-blind** designs [B12, B14].
- **Fatigue.** See BS.1116 above [B30], and Nielsen's "quarter of an hour" remark [B09].
- **Number of trials before judgments are reliable.**
  - The lab retest of r ≈ 0.7 [B01] shows one rating is weak evidence.
  - Crowd workers needed a median of ≥5 answers per query [B22].
  - The hearing-aid GP needed 10–20 comparisons [B10].
  - An evolutionary headphone-target search needed 8 generations (mean 31.5 min) to shrink the candidate pool's spread from 1.72 to 0.98 dB. The final curve beat the starting curve only modestly: odds ×1.29, rating 3.74 vs 3.51 [B45, B].

### RO4: Changing EQ within a song

- **Direct evidence: none found.** Five targeted queries found no listening test of time-varying EQ in music: no detection threshold for slow EQ ramps, no study of "pumping"/"breathing" preference, and no study of mid-song moves. Patents and practitioner pages assert the trade-off but have no data (excluded).
- **Adaptation.**
  - Listeners showed consistent *contrastive* adaptation of brightness judgments to spectrally coloured music and speech. The effect grew with longer adaptor duration and **levelled off after about 8 trials of 2 s**. A short-term-memory criterion model fit at r = .97. Linear tilt filters and a real hearing-device response behaved alike [B38, A, abstract].
  - Rapid timbre aftereffects occur across many natural sound classes [B39, A, abstract].
- **Contrast with the preceding sound.** Listeners "calibrate" to reliable spectral properties of the preceding context, whether speech or *music*. A context filtered toward horn made a target more likely to be heard as saxophone ("auditory colour constancy") [B37, A, abstract]. For us: right after a stable section, a new EQ is heard *relative* to the old one, which exaggerates the move. Later the auditory system normalises it away.
- **Rooms and loudspeakers** [B29, A]. Humans "exhibit skills in separating room sound from the timbral identity of loudspeakers, and in adapting". Toole also calls ±3 dB room-curve tolerances "too generous", and says bass performance alone accounted for **~30%** of overall subjective ratings.
- **Detection thresholds.**
  - BS.1116 asks monitor loudspeakers to be matched within **1.0 dB** from 250 Hz to 2 kHz [B30]. That is a reference-equipment requirement, not a perceptual threshold.
  - Peak and dip audibility [B43], resonance thresholds [B44], spectral-envelope compensation [B40] and slow-change deafness [B41] are all U.
- **Artist intent** [B29, A; B47, D]. The circle of confusion: monitors judge recordings that are made with the same monitors, so consumers hear "what the artists created" only if playback and monitoring are fundamentally similar. Toole still endorses tone controls for listeners sensitive to timbral imbalance [B29].

### RO5 (half): Listener preference classes, or how many themes

- **Harman headphone panel** [B24, B; author's own summary of AES papers B26–B28 (U)].
  - Panel: 130 listeners (about half trained), 31 headphones from 18 makers.
  - The Harman-target-equalised headphone was preferred over 28 of the models, and trained and untrained listeners both preferred it.
  - Cluster analysis found 3 classes:
    - **Class 1, 64%:** the target;
    - **Class 2, 15%:** target + **4–6 dB bass**;
    - **Class 3, 21%:** about **−2 dB bass**.
  - By gender, men split 69/18/13% across classes 1/2/3 and women 56/4/40%.
  - By age, Class 1 drops to 30% for listeners over 50, and 50% of over-50s are in Class 3.
  - Younger men and less experienced listeners preferred more bass *and* treble. Listeners aged 55+ preferred more treble and less bass.
  - The author proposes "a simple bass and treble control" for personalisation.
  - The vendor case study gives slightly different numbers [B25, D]: Class 2 +3–6 dB bass; Class 3 −2–3 dB bass and +1 dB above 1 kHz.
- **Hearing-aid field clusters** [B13, C]. The two strongest clusters cover **79%** of programmes on average (range 49–100%), and four clusters cover **>90%** in 8/10 environments. Cluster count depends on context: one cluster covers 100% in Transport, and the top two cover 49% in Entertainment.
- **Low-dimensional structure.** 2 principal components explain 87% [B03] and 95.6% [B02] of the variance in learned EQ curves. Prompt-driven EQ responses from 11 listeners lie on a lower-dimensional manifold, but their spread differs **114×** between the most consistent and most ambiguous prompt [B46, B; natural language itself is out of scope].
- **Words don't define themes** [B01, B05]. "Warm" varies dramatically across listeners, and the top cross-listener agreement score was only 0.294. Themes should be *sounds/curves*, not adjectives.
- **Genre dependence:** not established in opened sources. The Olive & Welti 2015 "program" effect [B27] and the MDPI genre/mood study are U.

### RO2 (human half): What "better" means to listeners

- **In blind, controlled tests, preference follows a neutral reference.**
  - Headphone preference is predicted from deviation from the target: **r = 0.86** (error 6.7 points on a 100-point scale), and **r = 0.91** for in-ears [B24].
  - Loudspeakers: predicted vs. rated **r = 0.86 / 0.995** (p < 0.0001) [B29].
  - Individual taste mostly shifts **bass ±2–6 dB** and treble a little [B24, B25].
- **Preference is noisy and only partly explained by measurable quality** [B23]. The quality predictor matched user choices only **53.3%** of the time.
- **Implication for an automatic "best".** A neutral target plus a personal bass/treble offset is the evidence-backed reading of "better". Any learned predictor must be validated on *same-track* EQ changes; that validation is RO2's main question, and track A covers it.

---

## Evidence table

`ID | RO(s) | type | claim | numbers | method / output | code + weights licence | limitation | grade | URL`

| ID | RO | type | claim | numbers | method / output | licence | limitation | grade | URL |
|---|---|---|---|---|---|---|---|---|---|
| B01 | 6,5 | journal | Rating-based EQ learning works fast | n=19; 75 trials/run; retest r=0.69; pred r=0.67; plateau ~20 (15–30) | per-band regression → 40-band curve; slider −1..1; RMS-matched | n/a | monotone, no interactions; descriptor-based | A | https://users.cs.northwestern.edu/~zra446/doc/Sabin-Rafii-Pardo%20-%20Weighting-Function%96Based%20Rapid%20Mapping%20of%20Descriptors%20to%20Audio%20Processing%20Parameters%20-%20JAES%202011.pdf |
| B02 | 6,5 | patent | Same method; HA variant | 3.7 s/trial; <20 ratings; 2 PCs = 95.6% of 120 curves | weighting function | patent (Northwestern) | patent, IP note for RO11 | B | https://patents.google.com/patent/US8565908 |
| B03 | 5,6 | short paper | 2-D space captures most EQ curves | 279 curves, 19 listeners; 2 PCs = 87% | PCA → 2-D dot EQ | n/a | no eval of interface | B | https://interactiveaudiolab.github.io/assets/papers/sabin-pardo-acmcc09.pdf |
| B04 | 6 | conf | Transfer learning → ~3 ratings | n=35; r≈0.5 @1 rating vs ≈0 baseline (Fig. 4) | distance-weighted prior users | n/a | same-word transfer only | A | https://nime.org/proceedings/2012/nime2012_74.pdf |
| B05 | 6,5 | conf | Crowd EQ ratings are noisy; words disagree | 633 workers; median r=0.41; 324 words | web EQ learner | data released (socialeq.org) | uncontrolled playback | A | https://markcartwright.com/files/cartwright2013socialeq.pdf |
| B09 | 6 | workshop | GP + EI from A/B degree-of-preference | 4 params; ~10 min; p<0.05 vs prescription (1 user) | Beta-lik. GP, Laplace, half-t priors | n/a | preliminary | B | https://eprints.gla.ac.uk/119556/1/119556.pdf |
| B10 | 6 | journal (abstract) | 10–20 comparisons suffice for ≤4 params | n=10 HI; 5–10 min | GP + active learning | n/a | hearing aids; abstract only | A | https://search.isc.ac/Inventory/49/75630.htm (DOI 10.1109/TASLP.2014.2377581) |
| B11 | 6 | thesis | same, "ten to twenty iterations" | ≤4 params | GP + sequential design | n/a | summary only | B | https://pdfroom.com/books/systems-for-personalization-of-hearing-instruments-a-machine-learning-approach/zW5n1Zxr2Nq |
| B12 | 6,5 | trade article | Binary A/B ML in product; blind gains | N=19; 84% / 89%; "20 iterations" | SoundSense Learn | proprietary | vendor-authored | C | https://hearingreview.com/hearing-products/hearing-aids/real-life-applications-machine-learning-hearing-aids-2 |
| B13 | 5,6 | trade article | Field clusters; ≤15 comparisons; drift | 2 clusters 79%; 4 >90% in 8/10 | 3 bands; meanshift on 20k programs | proprietary | vendor; context-based | C | https://hearingreview.com/hearing-products/hearing-aids/ai |
| B14 | 6 | conf abstract | Double-blind benefit of SSL | 2 sites | — | proprietary | abstract, vendor | C | https://canadianaudiology.ca/wp-content/uploads/2019/09/Perceptual-benefits-of-patient-driven-fine-tuning-using-machine-learning-technology.pdf |
| B15 | 6 | blog | marketing of B12 numbers | 84/89% | — | — | marketing | D | https://www.widexpro.com/en/blog/global/can-soundsense-learn-give-clients-better-hearing-experience/ |
| B17 | 6 | conf | Probit GP preference likelihood | — | GP, Laplace, evidence | n/a | no human study | B | https://mlg.eng.cam.ac.uk/zoubin/papers/icml05chuwei-pl.pdf |
| B18 | 6 | conf | EI preference queries; 6-D fails at 50 | user study 8.56±5.23 vs 18.40 clicks | probit GP + EI | n/a | target-matching, n=5 | A | https://proceedings.nips.cc/paper_files/paper/2007/file/b6a1085a27ab7bff7550f8a3bd017df8-Paper.pdf |
| B19 | 6 | conf | PBO; bandits need far more duels | ≤2-D; 200 duels; pbo-dts best | GP Bernoulli duels | GPyOpt-based (n/a here) | synthetic only | B | https://arxiv.org/abs/1704.03651 |
| B20 | 6 | conf | Dueling bandits for K discrete arms | regret ~optimal | interleaved filter | n/a | no correlation across arms | B | https://www.learningtheory.org/colt2009/papers/006.pdf |
| B21 | 6 | conf | qEUBO acquisition, noise-robust | regret o(1/n) | EUBO | BoTorch (not checked) | synthetic | B | https://arxiv.org/abs/2303.15746 |
| B22 | 6 | journal | Slider line search ≫ pairwise in 6–20-D | 15 iterations; ≥5 crowd answers each | BO + BTL, variance-adaptive | n/a | assumes shared preference | A | https://koyama.xyz/project/sequential_line_search/download/preprint.pdf |
| B23 | 6,2 | conf | RLHF from 300k binary prefs; over-optimisation | 74% / 87% wins; RM 60%; 51.6/53.3% | reward model + KL-reg RL | not checked | generative, not EQ | A | https://arxiv.org/abs/2402.04229 |
| B24 | 5,2 | magazine (author) | 3 classes; target preferred; bass/treble control | 130 listeners; 64/15/21%; r=0.86 | clustering; regression model | n/a | headphones, one lab | B | https://acousticstoday.org/issues/2022AT/Spring2022/files/basic-html/page63.html (pp. 62–66) |
| B25 | 5 | case study | class dB offsets | +3–6 dB; −2–3 dB, +1 dB >1 kHz | — | — | vendor | D | https://www.grasacoustics.com/fileadmin-gras/Images/Consumer_Audio/Household_Appliances/GRAS_Case_Harman_Final_02182021pdf.pdf |
| B29 | 4,2 | journal (review) | circle of confusion; adaptation; tone controls OK | r=0.86/0.995; bass ≈30% | review of listening tests | open access | loudspeakers/rooms | A | https://linkwitzlab.com/Toole-Room%20calibration.pdf (DOI 10.17743/jaes.2015.0064) |
| B30 | 6,4 | standard | short-term memory; 40 ms switch; 10–15 trials; ±0.25 dB | 20–30 min sessions | test method | ITU | small-impairment tests | B | https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1116-3-201502-I!!PDF-E.pdf |
| B31 | 6 | conf | balanced order; RMS alignment; PC vs ranking | n=52 | method comparison | n/a | codecs, not EQ | A | https://www.mathpsy.uni-tuebingen.de/wickelmaier/pubs/WickelmaierUmbach2009AES.pdf |
| B32 | 6 | journal (abstract) | no time-order error at 0.1–2 s | negative TE at 4–8 s | brightness PC | n/a | noise stimuli | A | https://acoustics.ippt.gov.pl/index.php/aa/article/view/3333 |
| B37 | 4 | journal (abstract) | calibration to context spectrum (music too) | — | instrument categorisation | n/a | abstract only | A | DOI 10.3758/APP.72.2.470 via https://api.semanticscholar.org/graph/v1/paper/DOI:10.3758/APP.72.2.470 |
| B38 | 4 | journal (abstract) | brightness adaptation plateaus ~8×2 s | r=.97 model | music + speech, tilt filters | n/a | abstract only | A | DOI 10.1038/s41598-021-00707-7 via Semantic Scholar API |
| B39 | 4 | journal (abstract) | rapid timbre aftereffects | — | morph continua | n/a | abstract only | A | DOI 10.1038/s41598-018-32018-9 via Semantic Scholar API |
| B42 | 6,4 | conf | change deafness for melodies across gap | n=26 / 36 | same/different | n/a | pitch, not EQ | A | https://repositories.cdlib.org/content/qt84z5g0j7/qt84z5g0j7.pdf |
| B45 | 6,5 | preprint | adaptive paired-rating target search | 24+22 listeners; SD 1.72→0.98 dB; odds 1.29 | IDE over 10 octave bands; −18 LUFS | not checked | small gain over start | B | https://arxiv.org/html/2512.08313 |
| B46 | 5 | preprint | listener spread varies 114× by prompt | n=11; 2-D smile/tilt ±6 dB | NL→EQ (out of scope) | not checked | NL; small n | B | https://arxiv.org/html/2601.09448 |
| B47 | 4 | vendor blog | circle of confusion (Olive) | — | — | — | marketing | D | https://pro.harman.com/insights/enterprise/broadcast/tech-talks-how-accurate-reference-monitoring-can-end-the-circle-of-confusion/ |

**Unverified (U): not opened; no claim rests on them.**
- B06 Sabin & Pardo 2008 (AES 125).
- B07 Sabin & Pardo, ACM MM 2009 (403).
- B08 Seetharaman & Pardo 2016, Audealize (AES 403).
- B16 Jensen et al. 2019, *Trends in Hearing*.
- B26 Olive, Welti & Khonsaripour 2019 (AES 146, segmentation).
- B27 Olive & Welti 2015 (AES 139).
- B28 Olive, Welti & McMullin 2013 (AES 135).
- B33 Knoll & Siedenburg 2022, *Music & Science* (order effects).
- B34 Toole & Olive 1994 (blind vs sighted).
- B35 Olive 2003 (trained vs untrained).
- B36 Gabrielsson et al. 1990 (JASA, sound level).
- B40 Watkins 1991.
- B41 Wayand et al. 2015 (slow change deafness).
- B43 Bücklein 1981.
- B44 Toole & Olive 1988.
- B48 Hjortkjær & Walther-Hansen 2014.
- B49 Frazier, Assgari & Stilp 2019 (title only).

---

## Search log

Source = WebSearch (general web index) unless noted. "Screened" = result titles/snippets reviewed; "included" = sources opened and used. Access blockers: the AES E-Library returned 403; PMC showed a reCAPTCHA; MDPI, Sage, Nature and Springer returned 403 or login redirects; the Semantic Scholar API returned 429 after a few calls. These blockers are why so many seminal AES/JASA items are U.

| # | Query (abridged) | RO | Screened | Included |
|---|---|---|---|---|
| 1 | Sabin Pardo "Rapid learning of subjective preference in equalization" AES 2008 | 6 | 9 | 2 (B01, B02) |
| 2 | Nielsen Jensen "Perception-based personalization … Gaussian processes" | 6 | 9 | 1 (B09) |
| 3 | MusicRL arXiv 2402.04229 | 6,2 | 9 | 1 (B23) |
| 4 | Sabin Pardo "rapid personalization of audio equalization parameters" pdf | 6 | 9 | 1 (B04) |
| 5 | Cartwright Pardo SocialEQ ISMIR 2013 | 6 | 9 | 0 |
| 6 | Sabin Pardo 2DEQ 2009 | 6,5 | 9 | 0 |
| 7 | "Rapid learning of subjective preference in equalization" Sabin (extended) | 6 | 18 | 3 (B03, B05, B46) |
| 8 | Widex SoundSense Learn white paper GP comparisons | 6 | 9 | 2 (B12, B15) |
| 9 | Seetharaman Pardo Audealize JAES 2016 | 6 | 9 | 0 |
| 10 | Nielsen 2015 TASLP orbit pdf EI pairwise | 6 | 10 | 0 |
| 11 | Nielsen PhD "ten to twenty iterations" | 6 | 10 | 2 (B10, B11) |
| 12 | Jensen/Hau/Nielsen/Legarth 2019 Trends in Hearing title | 6 | 9 | 1 (B14) |
| 13 | SoundSense Learn real-world Balling Townend | 6,5 | 20 | 1 (B13) |
| 14 | same title + PMC | 6 | 9 | 0 |
| 15 | González … "Preferential Bayesian Optimization" | 6 | 10 | 1 (B19) |
| 16 | Chu Ghahramani 2005 preference learning GP | 6 | 9 | 1 (B17) |
| 17 | Koyama "Sequential line search" | 6 | 9 | 1 (B22) |
| 18 | Yue … "K-armed dueling bandits" | 6 | 10 | 1 (B20) |
| 19 | Brochu … "Active preference learning with discrete choice data" | 6 | 10 | 1 (B18) |
| 20 | Olive Khonsaripour Welti preferred bass/treble segments | 5 | 10 | 2 (B24, B25) |
| 21 | Olive Welti McMullin 2013 in-room targets | 5 | 10 | 0 |
| 22 | preferred EQ depends on genre (extended) | 5 | 9 | 0 |
| 23 | Pestana et al. spectral characteristics 1950–2010 | 5 | 10 | 0 |
| 24 | Acoustics Today Spring 2022 Olive headphone | 5,2 | 9 | (B24 confirmed) |
| 25 | Toole Olive "Hearing is believing…" | 6 | 9 | 0 |
| 26 | Olive 2003 trained vs untrained | 6,2 | 10 | 0 |
| 27 | level matching 0.1 dB louder-better (extended) | 6 | 9 | 0 |
| 28 | Hjortkjær Walther-Hansen compression loudness-matched | 6 | 10 | 0 |
| 29 | ITU-R BS.1116-3 loudness | 6 | 10 | 1 (B30) |
| 30 | intensity JND broadband 0.2/0.5 dB | 6 | 10 | 0 |
| 31 | Stilp spectral contrast music | 4 | 9 | 0 |
| 32 | Watkins 1991 perceptual compensation | 4 | 10 | 0 |
| 33 | Toole Olive modification of timbre by resonances | 4 | 10 | 0 |
| 34 | Frazier Assgari Stilp 2019 | 4 | 9 | 0 |
| 35 | Stilp 2010 auditory colour constancy | 4 | 9 | 1 (B37) |
| 36 | listeners adapt to frequency-response colouration (extended) | 4 | 9 | 3 (B38, B39, B45) |
| 37 | Siedenburg adaptive brightness | 4 | 9 | (B38) |
| 38 | JND spectral tilt dB/oct music (extended) | 4 | 9 | 0 |
| 39 | Bücklein 1981 | 4 | 10 | 0 |
| 40 | gradual vs abrupt spectral change detection | 4 | 10 | 0 |
| 41 | Toole "circle of confusion" | 4 | 9 | 1 (B47) |
| 42 | time-varying EQ listening test (extended) | 4 | 10 | 0 |
| 43 | slow change deafness | 4 | 9 | 0 |
| 44 | Toole 2015 measurement & calibration | 4,2 | 9 | 1 (B29) |
| 45 | audibility slow gain changes AGC pumping | 4 | 10 | 0 |
| 46 | JND shelf filter gain music (extended) | 4 | 9 | 0 |
| 47 | Moore Oldfield Dooley peaks/notches | 4 | 10 | 0 |
| 48 | "spectral slope" discrimination dB/oct | 4 | 10 | 0 |
| 49 | Siedenburg timbral Shepard illusion | 4 | 9 | 0 |
| 50 | Knoll Siedenburg presentation order | 6 | 9 | 0 (U) |
| 51 | time-order error paired comparison audio | 6 | 10 | 2 (B31, B32) |
| 52 | Illényi Korpássy loudness quality | 6 | 9 | 0 |
| 53 | Gabrielsson 1990 frequency response & level | 6,2 | 10 | 0 |
| 54 | "0.2 dB" level difference blind comparison | 6 | 9 | 0 (forums, D, excluded) |
| 55 | PBO human user study audio, 2022–24 | 6 | 9 | 0 |
| 56 | change deafness music phrase boundary | 4 | 19 | 1 (B42) |
| — | direct fetch: qEUBO arXiv 2303.15746 (forward snowball) | 6 | 1 | 1 (B21) |

**Snowball (one hop):**
- **RO6.**
  - From **B01**: backward to 2DEQ (B03, opened) and the modified-simplex refs (Neuman 1987, Kuk & Pape 1992; titles only); forward to B04 and B05 (opened).
  - From **B09/B10**: backward to Chu & Ghahramani (B17, opened), Jensen 2011 MLSP (not found) and BALD (screened); forward to B12, B13 and B14 (opened) and Jensen 2019 (U).
  - From **B19**: backward to B18 and B20 (opened); forward to qEUBO (B21, opened); and forward from B18 to Koyama (B22, opened).
- **RO4.**
  - From **B37**: backward to Watkins 1991 (U) and Kiefte & Kluender (not opened); forward to Frazier 2019 (title) and Siedenburg 2021 (B38).
  - From **B38**: backward to Siedenburg 2018 (snippet) and Piazza 2018 (B39); forward to Knoll & Siedenburg 2022 (U).
  - From **B29**: backward to Toole & Olive 1988 (U) and the Olive 2013 papers (U); forward to B24.
- **RO5.**
  - From **B24**: backward to the AES 2015/2019 papers (U); forward to B45 and B46.
  - From **B13**: backward to B12.

**Saturation:**
- **RO6:** saturated. Rounds 15–19 and 55 plus the forward snowball added only qEUBO, then nothing new.
- **RO4:** stopped at a cap (16 queries). Direct evidence is absent, and the key psychoacoustics papers are paywalled.
- **RO5 and RO2:** stopped at a cap. Further sources (AES) are blocked.

---

## Answers per RO

| RO | Answer | Confidence | Key IDs |
|---|---|---|---|
| **RO6, method** | GP preference model (probit/BTL) with Thompson-sampling or qEUBO queries over **2–4 continuous dims**, theme as prior mean, lengthscale priors, explicit noise, slow forgetting for drift. Dueling bandits only to choose among K themes. | **High** for the method family and dimensionality; **medium** for transfer to music taste. | B09, B10, B17, B18, B19, B21, B04, B13 |
| **RO6, trials** | Usable after **~3–5** answers with a good prior; converged by **~10–20** comparisons in ≤4-D; >50 needed in 6-D. Spread over sessions of **≤10–15 asks**. | **Medium-high** | B04, B10, B13, B18, B30 |
| **RO6, one-bit "better/not"** | Treat each tap as a **paired comparison between the setting just before and after a change**, valid only within a few seconds of the switch. An absolute "like" on a static state is weaker evidence and drifts. | **Medium** (inferred; no study of exactly this UI) | B18, B30, B32, B42 |
| **RO6, biases** | Instant switching (~40 ms crossfade); ≤2 s gap; order randomised and balanced; blind (unlabelled) A/B; loudness-matched (BS.1770), tolerance **±0.25 dB** as the evidenced bound and ≤0.1 dB as a target; ≤10–15 asks per session; expect adaptation. | **Medium** (the loudness threshold has no opened primary source) | B30, B31, B32, B45, B12 |
| **RO4** | No direct evidence on mid-song EQ moves. Indirectly: adaptation within ~16 s, plus contrast effects, mean moves are most noticeable at the switch, then normalised. The faithfulness argument favours **one static per-track setting chosen by read-ahead**; mid-song changes should be rare and small, at section boundaries and slow ramps, and only to correct production defects, never to flatten musical contrast. | **Low-medium** | B37, B38, B39, B29 |
| **RO5 (classes)** | About **3 classes** cover headphone listeners (64/15/21%), differing mainly in **bass ±2–6 dB** and a little treble. Field data: 2–4 clusters cover 79–90%+. EQ taste is roughly 2-D. So **3–4 themes plus a 1–2-D personal offset**. | **Medium** (one lab, headphones; HA context) | B24, B25, B13, B03, B02 |
| **RO2 (human side)** | In blind, level-controlled tests, "better" is mostly closeness to a neutral target plus personal bass/treble taste. Judgments are noisy (r 0.41–0.7). Measurable "quality" explains only part of preference, and unconstrained optimisation of a learned preference over-optimises. | **Medium** | B24, B29, B01, B05, B23 |

---

## Design implications (concrete)

1. **Learning algorithm:** a probit-GP preference model [B17] with Thompson-sampling (pbo-dts) [B19] or qEUBO [B21] to pick the next proposal.
   - Prior mean = the user's theme.
   - Lengthscale priors as in [B09].
   - Explicit noise.
   - A per-output-device model, which matches the existing per-output memory.
   - Exponential forgetting with a long half-life, because preferences drift [B13].
2. **Parameters:**
   - Learn **2–3 offsets** relative to the theme, e.g. Bass, a Presence+Air "treble/tilt" axis, and optionally Body.
   - Keep the 5-D Tone vector as the representation, but **constrain learning to a low-dimensional subspace**, since 2 principal components carry 87–96% of EQ variance [B02, B03].
   - Never learn 31 bands.
   - Bound offsets to the class range observed in [B24]: about ±6 dB bass and a few dB treble. This is engineering judgment, inside the existing safety clamps.
3. **Feedback UI:**
   - "Sounds better / not" refers to the *last change*.
   - Offer a **blind A/B toggle** (unlabelled, randomised which is first, ~40 ms crossfade) only on the same short passage, within ≤2 s gaps [B30, B32].
   - Never ask after a long listen (adaptation [B38]) or after a gap (memory [B42]).
4. **Trial budget:**
   - Show a first personalised suggestion after **3–5 answers** with the theme prior [B04].
   - Expect convergence at **10–20** [B10].
   - Cap prompts at **10–15 per session** [B30].
   - Require ≥2 consistent answers before changing the stored default, given retest r ≈ 0.4–0.7 [B01, B05].
5. **Loudness-match tolerance:**
   - Match integrated loudness (BS.1770, gated) of A and B on the *played segment* before every comparison.
   - Target **≤0.1 dB** and fail the comparison if the mismatch is above **±0.25 dB** [B30].
   - Log the mismatch so RO12 can test whether "better" correlates with residual loudness. That correlation is the reward-hacking signature [B23].
6. **Mid-song change rate and timing (engineering judgment where evidence is missing):**
   - **Default:** one setting per track, decided from read-ahead before playback starts.
   - **Mid-song:** only at detected section boundaries, only when the read-ahead finds a large, sustained spectral defect relative to the theme (not musical contrast), with ramps of several seconds.
   - Keep per-change size below about 1–2 dB per Tone band and allow at most a few changes per track.
   - Never ask for feedback within ~20 s of an automatic move, because the contrast effect exaggerates it [B37, B38].
   - Ship only after an ABX "can you hear it move?" gate (RO12).
   - Keep Pure Mode untouched.
7. **Themes:** ship **3–4 sound-defined themes** (Neutral/target, More bass, Less bass/more treble, and possibly one "warm/dark" tilt), each a Tone vector. Do not ship adjective-defined themes [B01, B05]. Choosing between themes can use a small dueling-bandit step [B20].

---

## Gaps (what the evidence does not answer)

1. **Mid-song EQ moves:** no opened listening study of detectability or preference for time-varying EQ in music, slow EQ ramps, or "pumping" at musical rates. This is the biggest gap. RO12 needs to generate first-party data.
2. **The loudness-mismatch preference threshold:** no opened primary study measures how much a 0.1–0.5 dB mismatch biases preference. The ±0.25 dB figure is a calibration tolerance [B30].
3. **One-bit "better/not" without A/B:** every opened learning study used paired comparisons or graded ratings. A single tap on a running state has not been studied for EQ.
4. **Taste versus hearing:** the Widex evidence comes from hearing-impaired users and the Harman classes from headphones in one lab. Neither covers loudspeaker listening in homes, and genre dependence of tonal preference is not established in opened sources.
5. **Drift and context:** preferences shift over time and with context [B13], but the rate is not quantified. How a theme should interact with genre or era is unstudied in what I could open.
6. **Paywalled seminal work:** Toole & Olive 1988/1994, Olive 2003, Bücklein, Watkins, the Olive segmentation papers and the Sabin & Pardo 2008 paper itself remain U. Someone with AES/ASA access should verify them before the proposal cites their numbers.
