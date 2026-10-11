# Brief E: training data and the learning signal (RO9)

*Track E, 2026-10-10. Follows `00-research-protocol.md`. Primary RO: RO9. Cross-feeds RO2, RO5, RO6, RO8, RO11, RO12.*

**What the model is.** The model takes a finished, mastered track, a theme, and the listener's accumulated "better / not" judgments. It outputs a 5-D Tone vector [Bass <150 Hz, Body 150–500, Mids 0.5–2k, Presence 2–6k, Air >6k], possibly one per section.

---

## 1. TL;DR

1. **There is no public dataset of listener preference ratings for EQ variants of full, mastered songs.** The nearest datasets are smaller or different:
   - SocialEQ: 1,595 crowd-taught 40-band "descriptor" curves on 3 solo-instrument clips [E1, E2, E3].
   - SAFE: about 900 warm/bright 5-band parametric settings from DAW users [E4].
   - The Mix Evaluation Dataset: 181 *mixes* of 18 songs, with 4,873 preference ratings [E7].
   - Small private listening tests: 8–26 listeners each [E10, E16, E17, E31].
   - Confidence: med-high (searches saturated).
   - Consequence: an end-to-end "content → preferred EQ" network cannot be trained from public labels.
2. **Paired before/after data is scarce, small, and nearly all non-commercial.**
   - MedleyDB: 196 multitracks, CC BY-NC-SA 4.0 [E38, E30].
   - MUSDB18-HQ: 150 songs, non-commercial [E39].
   - MoisesDB: CC BY-NC-SA 4.0 [E41].
   - Cambridge-MT: educational use; research use is not explicitly granted (U) [E40].
   - Real unmastered→mastered pairs: one 138-track set from Mixing Secrets, not released [E29].
   - Most systems (DeepAFx-ST, FXencoder, Koo remastering, ITO-Master, Diff-MST) avoid paired data with **self-supervised tricks** [E22, E24, E26, E27, E30].
3. **Self-supervised "undo a random EQ" works on synthetic colorations, but it learns a corpus average, not a preference.**
   - Moliner et al. (frozen CLAP + 0.34M-param head) won pairwise preference over a fixed-average target 51–13 and tied an oracle. Both still lost to the untouched original 15–49 [E16].
   - On real Jamendo masters, SonicMaster's EQ category got the *worst* preference scores, with no significant quality change [E17].
   - The mechanism is explicit in the literature: a blind estimator "learns the distribution of unprocessed signals" [E19]. Its estimate "reflects statistics of the training data" [E16]. Instrument-EQ targets are literally per-class averages [E31, E28].
   - Use: treat it as a **learned, content-aware target curve** that flags and gently corrects outlier masters, not as a preference model.
4. **Population preference is weakly predictable even with huge data.**
   - MusicRL: 300k user pairwise preferences produced a reward model with only **60%** held-out accuracy. The best-quality-score clip was preferred only **53.3%** of the time [E14].
   - Commercial mixes by renowned engineers were not rated above student mixes [E7].
   - About 36% of listeners are not served by the Harman population target [E46].
   - So the personal learner is where the value is.
5. **Tens of judgments are enough *if* the space is small and the prior is strong.**
   - 5-band EQ, 12 listeners, Bayesian GP with active selection: significantly better than random by 10 ratings [E10].
   - With a population prior from users teaching the same word: about **3** ratings matched what about **25** needed without one [E9].
   - A hierarchical prior helps most in the early, few-ratings phase [E11].
   - Hearing-aid A/B products report about 20 comparisons [E13] or a median of 25 [E12]. These are related work only (audiogram personalisation is out of scope).
   - A single user has no population, so substitutes are needed:
     - published preference *structure*: Harman's 64/15/21% classes [E46, E48 U];
     - a small set of theme prototypes, in the PAL style [E15];
     - correlation between adjacent bands [E10];
     - pooling across the same user's contexts (themes, outputs, genres). This last one is my inference, not tested in the literature.
6. **Best day-one prior (no training needed): a licence-clean reference distribution of band balance plus theme offsets.**
   - **AcousticBrainz** low-level features are **CC0**, frozen at about 7.56M unique recordings [E42]. Its Essentia Bark-band edges include **150, 510, 2000 and 6400 Hz** [E43b], which map almost exactly onto the Tone bands.
   - The **user's own library**, analysed on-device, is the other licence-clean, on-distribution corpus.
   - Commercial targets (iZotope's Modern / Bass Heavy / Orchestral ranges) are documented but their data is not published [E49, E50].
7. **Licence trap.** Nearly every large music corpus is NC or per-track CC:
   - MTG-Jamendo: "solely for non-commercial research" [E33].
   - FMA: per-artist CC [E34].
   - MedleyDB, MUSDB, MoisesDB: NC.
   - AcousticBrainz-Genre labels: CC BY-NC-SA [E60].
   - The SonicMaster pairs are labelled CC-BY-2.0 but derive from Jamendo CC tracks [E18]. This is inconsistent, so verify before use.
   - Shipping weights trained on NC data in a distributed app is a legal grey zone. CC0 features and the user's own files are clean.

---

## 2. Findings by RO

### RO9: Training data and the learning signal (primary)

#### 9.1 EQ preference and descriptor datasets

| Dataset | What was rated | Size | Representation | Licence / availability (checked 2026-10-10) | Sources |
|---|---|---|---|---|---|
| **SocialEQ** (Cartwright & Pardo, ISMIR 2013) | Each participant taught a descriptor by rating 40 EQ'd versions of one clip (guitar, piano or drums; 8–14 s) for "how <word> is this". 15 of the 40 were repeats, to measure consistency. | 633 MTurk participants, 1,102 sessions. After filtering: 481 participants, 731 sessions, 324 descriptors. Venkatesh counts 1,595 samples in the release (918 English, 388 unique words). | 40 ERB-band relative curves, normalised to SD units (relative to the source, not absolute) | Paper says data is at socialeq.org/data. That host **no longer resolves** (DNS failure). LLM2Fx (2025) says SocialFX (SocialEQ + SocialReverb) is "accessible as open-source", via a bit.ly link that resolves to a Dropbox share (contents not verifiable). **No licence stated.** | E1, E2, E3 |
| **SocialFX / Audealize word map** (Seetharaman & Pardo, JAES 2016) | Crowdsourced word→EQ/reverb map. A 432-nonexpert study preferred the word map to traditional interfaces. | EQ 1,595 parameter sets; reverb 6,772 | Same 40-band | Audealize API on GitHub (licence not shown); data as above | E3, Audealize repo (C) |
| **SAFE** (Stables et al., ISMIR 2014; Stasis et al., NIME 2017) | In-DAW users saved a 5-band parametric EQ setting with a descriptor | 900 warm/bright instances in the NIME subset. Total SAFE-DB "1,369" is from a search snippet only (U). | 13 parameters (2 shelves + 3 peaks), plus audio features before/after, plus metadata | Plugins are GPL-3 on GitHub. The dataset host semanticaudio.co.uk **refused connection**. No dataset licence found. | E4, E5, E6 |
| **Mix Evaluation Dataset** (De Man & Reiss, DAFx 2017) | Listeners rated several *mixes of the same song* on one "preference" axis, with no reference, plus free comments tagged by attribute (e.g. "spectrum", "too much sub bass") | 18 songs, 181 mixes, 150 subjects, 4,873 evaluations, 12,696 statements | Ratings, comments, DAW sessions and parameter settings | Browsable at c4dm.eecs.qmul.ac.uk/multitrack/MixEvaluation. Raw tracks via the Open Multitrack Testbed; 6 of the 10 newly recorded songs are CC BY 4.0. Some songs are copyrighted and not redistributed. A derivative, MixologyDB, is on HF (MIT code). | E7, E8 |
| Pardo / Little / Gergle 2012 | 35 users × 5 words × 50 EQ probes on a 5-s Flower Duet excerpt | 35 users | 40-band | Not released (paper CC BY 4.0) | E9 |
| Nielsen et al. 2013 (DTU/Widex) | Absolute 0–1 ratings of 5-band EQ settings on music, A-weighted level-matched | 21 subjects × 30 random ratings; 12 subjects in the interactive test | 5 gains | Not released | E10 |
| Moliner et al. 2025 | Pairwise "Which one do you prefer?" between restored / oracle / average / original, loudness-normalised | 8 listeners, 4 excerpts | – | Samples in the paper's attached material | E16 |
| SonicMaster test | 7-point preference, degraded vs restored | 12 listeners, 43 pairs; plus 20 people × 10 X-band-EQ items | – | – | E17 |
| Dourou et al. 2022/2024 | 5 preset EQ curves × 10 music excerpts. Reportedly "high-frequency boost" was most preferred, and band energy predicts preference. | 52 listeners | 5 presets | MDPI / IRIS pages returned 403. **U.** | E58 (U) |
| Stylianou et al. 2026 (B&O) | Listener EQ responses to NL prompts on a 2-D controller | 11 participants, 120 rows (IEEE DataPort) | 2-D | NL tuning is out of scope; listed as related work | E59 |

**What these data can and cannot do for us.**
- **Can:** give *theme vocabulary with curves* (warm, bright, deep, tinny…) as relative spectral shapes [E1, E4].
- **Can:** show that word meanings vary across people. Single-session consistency had a median r = 0.41 [E1], and "warm"/"bright" split into several sub-clusters [E4]. This argues for a per-user offset on top of a theme.
- **Can:** provide real "same song, different balance" preference judgments, but at the mix level [E7].
- **Cannot:** none of them has preference ratings for *EQ variants of finished masters* across many songs.
- **Cannot:** none uses full-band program in the sense our player needs. SocialEQ uses solo instruments.

#### 9.2 Paired before/after data (mixes, masters, multitracks)

| Corpus | Content | Licence | Used by |
|---|---|---|---|
| **MedleyDB** 1+2 | 196 multitracks (122 + 74), royalty-free | CC BY-NC-SA 4.0 (stated in the Diff-MST ethics statement); Zenodo, with a permission request | Diff-MST [E30]; Moliner (mixes only) [E16] |
| **Cambridge-MT "Mixing Secrets"** | Large multitrack library. Some entries include mixes/masters: 138 unmastered/mastered pairs were extracted by [E29]. | Free "for educational purposes only… not for any commercial purpose". The FAQ says research use is not specifically agreed with contributors and advises contacting them (U, from search snippet; page returned 403). | Diff-MST [E30]; Martínez-Ramírez 2021 [E29]; Solid State Bus-Comp (U) |
| **MUSDB18-HQ** | 150 songs, 4 stems + mix, WAV | "Other (Non-Commercial)", educational | FXencoder [E24]; blind-AFx [E20]; FxNorm [E28] |
| **MoisesDB** | Multistem songs, "not fully mastered" | CC BY-NC-SA 4.0 | ITO-Master [E27] |
| **DSD100** | 100 songs (MUSDB's source) | NC / see source | Moliner [E16]; RemFX [E21] |
| **Mix Evaluation** | 181 mixes of 18 songs, with parameters | partly CC BY 4.0 | [E7] |
| **Real unmastered→mastered pairs** | 138 tracks (Mixing Secrets), time-aligned, about 530 min | not released | [E29] |
| Private | 760 mastered pop/rock/hip-hop songs (Koo 2022); 1,505 multitracks (Sony FxNorm); about 45k instrument samples (Native Instruments) | private | E26, E28, E31 |
| **SonicMaster dataset** | about 25k clean 30-s Jamendo clips (selected by Audiobox Aesthetics PQ 6.5–8, 10 genre groups) × 7 degraded versions = about 175k pairs, 506 GB. Degradations: 19 effects in 5 groups, including 10 EQ-type (8–12-band ±6 dB, shelves, mic IRs…). | HF card says **CC-BY-2.0**, but the source is Jamendo CC (often NC/ND). **Licence inconsistent: verify.** Code Apache-2.0; weights licence not stated. | E17, E18 |

**Takeaways.**
- (a) Real *mastering* pairs are tiny. There is no public large set.
- (b) Mastering style-transfer papers sidestep pairs by assuming "any part of a song has the same mastering style". They create input/reference by applying two random chains to two halves of one song [E26, E27, E22, E30].
- (c) What we need is *mastered → preferred*. That is a different target from *unmastered → mastered*, and no corpus supplies it.
- (d) Paired data is relevant to us only as a source of high-quality "reference" masters for self-supervision.

#### 9.3 Self-supervised schemes ("undo a random EQ")

| System | Scheme | Result | Failure mode / limitation |
|---|---|---|---|
| **Moliner et al. 2025/26** (blind EQ, frozen CLAP + 0.34M MLP head) [E16] | MedleyDB + DSD100 mixes (plus speech) at −18 LUFS. Random zero-phase EQ ±20 dB on 26 Bark bands, plus reverb, noise, gain. Predict the clean 32-band log-mel minus the training-set mean; L1 loss (a conditional median). | Pairwise preference: Proposed > Average 51–13 (p ≈ 1.9e-11); Proposed ≈ Oracle 31–33; **Reference > Proposed 49–15**. 8 listeners, 4 excerpts. | Estimate "reflects statistics of the training data, which may not match a given recording's unique spectrum". Coarse 32-band inverse filter. Ill-conditioned when bands are lost. Perturbations are much larger than real master-to-master differences. |
| **SonicMaster** (rectified flow, text-conditioned) [E17] | Jamendo masters selected by Audiobox PQ; synthetic EQ/dynamics/reverb/stereo degradations | Preferred overall, but **EQ had the worst preference ratings, and quality differences were not significant for EQ** (12 listeners). Separately, 180/200 preferences vs baselines on X-band EQ. | Generative latent artifacts; "some EQ effects are subtle". Restoring EQ on an already-good master gains little. |
| **DeepAFx-ST** [E22] | Random 6-band PEQ + compressor configurations applied to two halves of one recording (MTG-Jamendo, LibriTTS); predict parameters from the reference | Objective only; music harder than speech; drops out of distribution on MUSDB18 | Train/inference mismatch: input and reference come from the same source in training but different sources in real use |
| **FXencoder** (Koo et al. ICASSP 2023) [E24] | Contrastive: same FX on different content = positive pair. FX-normalisation of MUSDB18 stems first. | 11 engineers: not significantly different from ground truth on multitrack conversion | "Timbre and audio effects are inherently interrelated" (the identifiability problem) |
| **FxNorm-automix** (Martínez-Ramírez ISMIR 2022) [E28] | EQ-normalise every wet stem to the **class-average spectrum** (65,536-pt STFT, 1,001-tap zero-phase FIR), then learn to undo it | 14 engineers: production value not significantly different from human mixes | Models "conservative"; "none of the mixes is consistently considered as very good" |
| **ST-ITO / AFx-Rep** [E23] | Classify which of 63 VST effects and presets was applied (MTG-Jamendo + 6 other sets, about 60 h); then gradient-free search at inference | 23-listener similarity test: on par with or better than DeepAFx-ST+ | Similarity to a reference, not preference |
| **Koo 2022 remastering**; **ITO-Master** [E26, E27] | Same-song-two-segments trick with random EQ/imager/limiter chains | 17 / 10 listeners: closer to the reference than anchors | Tone matches worse than loudness or width; spectral shape above 1 kHz drops [E26] |
| **NI instrument auto-EQ** [E31] | Per-instrument "ideal spectrum" = class average; also real-world targets (cut MAE 24% vs random-parameter synthesis) | 26 internal listeners preferred processed audio about 2:1 | Encodes one corpus's typical balance; internal panel; no significance tests |
| **Blind-AFx** (Peladeau & Peeters 2024/25) [E20, E19] | Random 5-band PEQ + compressor + clipper on MUSDB18 mixes | Objective only | "Blind approaches need to optimize a model which 'learns' the distribution of unprocessed signals" [E19]. Many parameter sets produce the same sound (e.g. a bass boost ≈ a treble cut up to level) [E19]. |
| **RemFX** [E21] | Effect removal for distortion, compression, reverb, chorus and delay | – | **EQ not included** |
| **MEGAMI** [E32] | Generative model of the *distribution* of professional mixes | Claims near-human listening results (details not verified) | Frames deterministic regression as the core flaw of prior automix |

**Synthesis for RO9.3.**
- "Undo a random EQ" turns the corpus into a **content-conditional reference curve** at the corpus median [E16, E19, E28, E31].
- It reliably fixes *large synthetic* colorations, and it beats a fixed average target [E16].
- Evidence that it improves *real, already-mastered* tracks is negative or null [E17].
- Its known failure mode is exactly the one the founder fears: it pulls every track toward "average commercial balance". That flattens intentional dark, lo-fi or bright productions, and it encodes nothing about the listener.
- Two engineering consequences:
  - (i) Use it only as a *bounded deviation detector*: propose corrections only outside a typical range, a range rather than a line as in iZotope's design [E49], with shrinkage.
  - (ii) Train on perturbations whose size matches real master-to-master spread, not ±20 dB. Real-world targets beat random-parameter synthesis by 24% MAE in [E31].

#### 9.4 Large unlabelled corpora with usable licences

| Corpus | Size | Licence | Fit for us |
|---|---|---|---|
| **MTG-Jamendo** | 55k+ full tracks, 195 tags, 508 GB raw | Code Apache-2.0; metadata CC BY-NC-SA 4.0; audio per-track CC; **"solely for non-commercial research and academic use"; commercial use needs Jamendo's written permission** | Feature learning / targets for research only. Several papers misreport it as "Apache 2.0" [E30]; that licence covers only the code. |
| **FMA** | 106,574 tracks, 161 genres, 343 days | Code MIT; metadata CC BY 4.0; audio per-artist CC ("meant for research purposes") | Genre-conditional statistics are possible, but the many NC tracks must be filtered out |
| **Song Describer** | about 1.1k captions for 706 tracks (from MTG-Jamendo) | CC BY-SA 4.0 (record); audio licences per track | Too small for training; useful as a captioned evaluation set |
| **AudioSet** | 2.04M unbalanced + 22k balanced + 20k eval segments, 527 classes | Labels CC BY 4.0; ontology CC BY-SA 4.0; **audio not distributed** (YouTube IDs) | Audio access/licence makes it unusable for training a distributed model |
| **MusicCaps** | 5,521 ten-second clips | CC BY-SA 4.0; YouTube IDs only | Same caveat |
| **AcousticBrainz** | 7,564,215 unique recordings (29.46M submissions); frozen 2022-07-06; dumps dated 2022-06-23 | **CC0** (data); features from the Essentia music extractor | **Best licence-clean source for band-balance priors.** Per-track Bark bands (edges at 150/510/2000/6400 Hz) and 4 energy bands (20–150 / 150–800 / 800–4k / 4k–20k). Caveat: user-submitted files of mixed encodings; lossy low-pass limits "Air". Whether an equal-loudness prefilter is applied to Bark bands should be checked in Essentia source (docs suggest not). |
| AcousticBrainz-Genre labels | Discogs / Last.fm / tagtraum genre labels for AB recordings | **CC BY-NC-SA 4.0** (AllMusic subset restricted) | Genre conditioning for the CC0 features is NC. Alternatives: AB's own CC0 high-level classifier outputs, or the user's own tags. |
| **MixCheck** (Mourgela et al. AES 157, 2024) | Metrics of amateur mixes and masters, including a "tonal profile" across 30 genres | **CC BY 4.0** (Zenodo, 24.8 MB csv) | A distribution of *amateur* deviations: useful for sizing realistic perturbations; band definitions unverified |
| **The user's own library** | Whatever the founder owns | Personal use; analysed on-device; nothing redistributed | On-distribution, licence-clean. Supports a "library-relative" target and on-device self-supervision. |

#### 9.5 Learning from in-product feedback logs

**MusicRL (Google, ICML 2024) [E14].**
- Collection: about 300k pairwise "trophy" preferences from AI Test Kitchen users, kept only when the user listened to both clips. No instructions were given. Unique-user count not reported. The data is proprietary.
- Reward model (Bradley-Terry, initialised from MusicLM, 285k/15k split): **60%** held-out accuracy. The team's own agreement with the dataset was also 60% (156 comparisons).
- Removing text left accuracy stable. Cropping audio to 3–5 s dropped it to 56%.
- MuLan text adherence predicted the preferred clip only 51.6% of the time; the quality MOS predictor only 53.3%.
- **Lesson:** population-level "better / not" is very noisy, and quality predictors barely track it. A single-user learner cannot borrow such a model. It needs low-dimensional, interpretable parameters and a strong prior.

**Other systems trained from thumbs, ratings or A/B.**

| System | Space | Data needed | Prior used | Grade |
|---|---|---|---|---|
| Sabin/Pardo iQ + transfer learning [E9] | 40-band EQ concept curve | ~25 ratings baseline; **3 ratings** with transfer (machine-user r ≈ 0.5 at 1–3 ratings vs ≈ 0.2 baseline; both converge to ≈ 0.65 at 50) | Ratings by prior users of the **same word** on a fixed 50-probe set, weighted by L1 distance | A (35 users) |
| Nielsen et al. 2013 [E10] | **5-band constant-Q EQ** (d = 5), >59k settings, music, A-weighted level match | Active GP beats random at 10 ratings (p < 0.011) and at 15–30 | Warped GP with weakly informative half-t hyperpriors. An adjacent-band (Mahalanobis) kernel modelled better (630 LOO splits, p < 0.001) but **did not help with few ratings**. | A (12 + 21 subjects) |
| Birlutiu et al. 2009 [E11] | GP utility over stimuli (speech-quality pairs) | 576 comparisons/subject × 32 subjects | Hierarchical normal-inverse-Wishart prior learned by EM from *other* subjects. Beats a flat prior, mostly early. | A (related domain) |
| Widex SoundSense Learn [E13] | Hearing-aid gain settings (A/B) | "Only 20 iterations"; 19-user study, 84–89% preferred | GP / active learning (Nielsen 2014) | C (vendor trade article; hearing-aid domain is related work only) |
| Vyas et al. 2021 [E12] | 24-D gains discretised into 15 presets (dueling bandit) | Median 25 comparisons (simulation on 35 subjects × 420 comparisons) | Population-derived presets (934 audiograms) | A (related domain; audiogram-based, out of scope) |
| PAL (ICLR 2025) [E15] | Ideal-point model: each user = convex mix of K learned prototypes | New users: "learn a new weight… with limited labeled samples". Larger K needs more samples. Cannot generalise outside the prototypes' convex hull. | Population-learned prototypes | B |
| Gracenote patent US10998872B2 [E55] | NN trained on reference audio + **EQ curves made by audio engineers, tagged by engineer**; outputs PEQ or 25-Bark gains; "like" button weights personal curve; 50/50 blend | Not stated | Engineer-labelled corpus | B (patent; active to 2039; flag to RO11) |

**Which priors make tens of judgments work for one user (synthesis).**
1. **Shrink the space.** Use the 5-D Tone, not 31 bands. 5-D EQ was learnable in 10–30 ratings [E10].
   - Back-of-envelope (my inference): 12 levels per band × 5 bands ≈ 18 bits to locate an optimum. One noisy binary choice is worth well under 1 bit, which suggests roughly 40–60 judgments to converge *per context*. That is the same order as the 20–30 reported [E10, E13, E12].
2. **Population-shaped prior without a population.**
   - Use published preference structure: Harman's majority near-target class 64%, "less bass" 21%, and "more bass" (U: ≈15%, +4–6 dB) [E46, E48].
   - Represent themes as K prototypes, and the user as weights plus a small residual (PAL-style) [E15].
3. **Hierarchy across the user's own contexts.** One user's judgments under different themes, outputs and genres can share a hierarchical prior. This is Birlutiu's multi-task idea [E11] applied to contexts rather than users. That application is my inference and untested in the literature.
4. **Decompose so the personal part stays content-free at first.** Olive found individual bass/treble preference is fairly stable, with *program-dependent* deviations due to recording quality [E47, E46]. Model the target as:
   > Tone = content-correction(track) + theme offset + personal offset
   Learn only the personal offset at first. Add content × preference interaction terms only after many judgments.
5. **Active query selection.** Active design significantly beat random [E10]. Pardo's patent family also selects probes for maximal difference or prior-user variance [E56, E9].

**Signal hygiene (what to log).**
- Judgments must be **level-matched**: A-weighting [E10], LUFS-normalised [E16, E31]. Otherwise louder wins (RO6 / RO12; we already have decision-26 loudness-neutral gain).
- Expect noise. Use repeats or consistency checks: SocialEQ used 15/40 repeats and found a median r = 0.41 [E1]; MusicRL's internal agreement was 60% [E14].
- Log at least: track ID, section/time, theme, both Tone vectors compared, output route, playback level, the choice, latency, and later overrides/reverts.
- No published evidence maps implicit signals (revert, skip, override) to EQ preference. The patents only describe "like" buttons and reset signals [E55] (gap).

#### 9.6 The cold-start prior (day-one model)

| Candidate | What it gives | Evidence | Licence / availability |
|---|---|---|---|
| **Corpus band-balance distribution (genre/era-conditioned)** | Typical range per Tone band; a deviation detector | Pestana 2013: commercial recordings lean to a consistent target EQ curve across years and genres (B). Deruty 2014: engineers mix toward a "subconscious target" approximated by a large-corpus average (B). Elowsson & Friberg 2017: more percussion → relatively more bass and treble in the LTAS, which could improve auto-EQ targets (U). | Build it ourselves: **AcousticBrainz CC0 Bark bands → Tone bands** [E42, E43, E43b], or the user's own library |
| **iZotope Tonal Balance Control targets** | 3 factory ranges (Modern, Bass Heavy, Orchestral); 4-band broad view (<250 / 250–2k / 2–8k / >8k) | "Thousands of commercial tracks". Genre mattered little; *intended listening environment* mattered most. Targets are **ranges**; "many well-balanced tracks might be outside these bounds"; one-file targets get skewed by intros and solos. | Curve data **not published** (C). TBC2 "12 curves" is U. |
| **Harman preference classes** | Personal/theme offsets: neutral, more bass, less bass | Acoustics Today 2022: 64% Harman-target class; 21% "less bass" (more female and older listeners, no trained listeners); "more bass" skewed 4:1 male (B). The 15% / +4–6 dB / −2 dB figures are from the AES abstract, not opened (U). 283 listeners adjusted bass/treble per program, and program influenced their choices (C). | Device-target research, not content. Use as *offset* priors only, to avoid double-correcting the output response (per-output memory). |
| **Descriptor curves** (SocialEQ / SAFE) | Shapes for named themes (warm, bright, deep, airy…) | A (crowd), but on solo-instrument clips; multimodal meanings | Licence unstated → derive our own 5-D vectors; do not ship the data |
| **Learned self-supervised target** | Content-aware reference (§9.3) | E16 beats a fixed average on synthetic colorations | Training data licence (§9.4) |

---

### Cross-RO findings (handed to other tracks)

- **RO2 (what "best" means).**
  - Quality predictors barely track user preference: 53.3% in MusicRL [E14].
  - Audiobox Aesthetics: about 97k clips / 500 h (one third music), 3 ratings each from 158 qualified raters. PQ correlates 0.887 with ground truth on natural music, but it was **never tested for same-clip EQ sensitivity** [E44]. Its AES-Natural labels (2,950 clips, about 1k music, 10 raters × 4 axes) are released.
  - In mix tests, "quality" vs "like" separate on commercial material (U) [E57], and commercial mixes are not rated higher than student mixes [E7].
- **RO5 (themes).** About 3 clusters recur:
  - Harman: 3 classes [E46].
  - iZotope: 3 factory targets grouped by listening environment, not genre [E49].
  - PAL: K-prototype theory [E15].
  - SocialEQ: "warm/loud/heavy/dark" and "tinny/light/bright" form two big descriptor clusters [E1].
- **RO6 (learning).** E9, E10, E11, E12, E13 and E15 above. Level matching and repeat trials are mandatory.
- **RO8 (on-device).**
  - The Moliner design is a frozen CLAP encoder plus a 0.34M-parameter MLP. That is a small head, but the CLAP weights licence is unverified here.
  - FXencoder code is MIT; weights are on Google Drive with terms not stated [E25].
  - SonicMaster code is Apache-2.0; weights licence not stated [E18].
  - Audiobox Aesthetics is CC-BY 4.0 per the repo [E45].
- **RO11 (IP).**
  - Gracenote US10998872B2 (priority 2018-10-24; active, expiry ~2039): NN-from-engineer-EQ-curves, plus like-button personalisation, plus dynamic/personal blend [E55]. Related family: US11611800, US12081833, "playback using pre-processed information and personalization" US12167084 / US12568274 / US11792481 (U, not opened).
  - Sabin/Pardo US8565908B2 (Northwestern): EQ preference learning from listener feedback on probe curves. Google marks it "ceased", with a reissue RE48462 (status not verified) [E56].
- **RO12 (evaluation).**
  - Reusable designs: pairwise preference with loudness normalisation and repeated pairs [E16]; tournament of model-best settings at 10/15/20/25/30 ratings [E10]; MUSHRA-similarity [E23, E26]; preference with no reference, as for mixes [E7].
  - No public benchmark exists for "EQ of finished masters"; we must build our own.

---

## 3. Evidence table

`ID | RO(s) | type | claim | numbers | method / output | code + weights licence | limitation | grade | URL`

| ID | RO(s) | type | claim | numbers | method / output | code + weights licence | limitation | grade | URL |
|---|---|---|---|---|---|---|---|---|---|
| E1 | 9, 5, 6 | paper (ISMIR 2013) | SocialEQ: crowd-learned EQ descriptor curves; meanings vary across people | 633 participants; 1,102 sessions → 731 kept (481 people); 324 words; 40 ERB bands; 15/40 repeats; median consistency r = 0.41 [0.39, 0.44] | Correlation of ratings with per-band gain → 40-band relative curve | Data "available" at socialeq.org/data (host dead 2026-10-10); licence unstated | Solo-instrument clips; uncontrolled speakers; learner biased to smooth curves | A | https://archives.ismir.net/ismir2013/paper/000173.pdf |
| E2 | 9 | paper (JAES 2022) | SocialEQ release = 1,595 samples (918 English, 388 words); word embeddings → 40-band EQ | MAE 0.76 (Tok2Vec) vs 0.836 (no embedding); human PCM 2.9 vs 9.3–10.5 | MLP, gains clipped ±4 dB | Code on GitHub (licence not shown) | Objective only; NL is out of scope | B | https://arxiv.org/abs/2202.08898 |
| E3 | 9 | paper (WASPAA 2025, LLM2Fx) | SocialFX = SocialEQ + SocialReverb, "accessible as open-source"; link bit.ly/1WmTP6v → Dropbox | EQ 1,595 sets; reverb 6,772; eval subset 273 EQ sets / 7 words | Re-rendered with Audealize on guitar/drums/piano | Data licence not stated | NL-focused (out of scope); Dropbox contents unverified | B | https://arxiv.org/html/2505.20770v2 |
| E4 | 9, 5 | paper (NIME 2017) | SAFE warm/bright subset; descriptors have sub-clusters | 900 instances; 13 PEQ params (2 shelves + 3 peaks); Hopkins ≈ 0.54–0.56; MUSHRA 20 subjects, 93.75% matching | Stacked autoencoder + coherence clustering | Paper CC BY 4.0 | DAW users, mixed instruments; no preference ratings | A | https://www.open-access.bcu.ac.uk/4970/1/NIME2017SFinal.pdf |
| E5 | 9 | code repo | SAFE plugins open source | GPL-3 file present; 111 commits | – | GPL-3 | No dataset file visible | C | https://github.com/semanticaudio/SAFE |
| E6 | 9 | project page | SAFE collects descriptors into a shared dataset | size not stated | – | – | semanticaudio.co.uk unreachable (ECONNREFUSED) | C | https://www.semanticaudio.ac.uk/?p=1886 |
| E7 | 9, 2, 12 | paper (DAFx 2017) | Mix Evaluation Dataset: real mixes + preference ratings + comments | 18 songs; 181 mixes; 150 subjects; 4,873 evaluations; 12,696 statements; 7 sites / 5 countries | One drag-drop "preference" axis, no reference; comments tagged (instrument, feature, valence) | Raw tracks via Open Multitrack Testbed; 6 of 10 songs CC BY 4.0; some copyrighted | Mixes, not EQ variants of masters | A | https://www.dafx.de/paper-archive/2017/papers/DAFx17_paper_49.pdf |
| E8 | 9 | dataset repo | MixologyDB: parameter annotations, mostly from Mix Evaluation | size not stated | JSON effect parameters | MIT (code); audio terms not stated | Ratings not confirmed | C | https://github.com/mclemcrew/MixologyDB |
| E9 | 6, 9 | paper (NIME 2012) | Transfer from prior users cuts ratings needed from ~25 to ~3 | 35 users × 5 words × 50 probes; machine-user r ≈ 0.5 at 1–3 ratings vs ≈ 0.2; both ≈ 0.65 at 50 | Weighted kNN over prior user-concepts (L1 distance) | Paper CC BY 4.0; no code | One 5-s clip; same-word transfer only | A | https://www.nime.org/proceedings/2012/nime2012_74.pdf |
| E10 | 6, 9, 12 | paper (AES 135, 2013; DTU/Widex) | Bayesian GP + active design personalises a **5-band EQ** on music; better than random by 10 ratings | 12 subjects (interactive); 21 × 30 ratings (model comparison); p < 0.011 at 10 examples; Mahalanobis kernel better LOO (n = 630, p < 0.001) but no few-shot gain | Warped GP, EI acquisition, anchor-ball UI, A-weighted level match, HD650 | Preprint; no code | Absolute ratings are hard to keep consistent; per-song sessions; no cross-track transfer | A | https://www2.imm.dtu.dk/pubdb/edoc/imm6567.pdf |
| E11 | 6, 9 | paper (ESANN 2009) | Hierarchical GP prior from other subjects beats a flat prior, especially with few comparisons | 576 pairs/subject; 14 normal-hearing + 18 hearing-impaired; ~75–80% of disagreements won by hierarchical early | EM-learned normal-inverse-Wishart prior; Bradley-Terry | – | Speech-quality stimuli; manual subject grouping | A | https://www.esann.org/sites/default/files/proceedings/legacy/es2009-122.pdf |
| E12 | 6 | paper (Smart Health 2021) | Pairwise personalisation of hearing-aid presets in a median 25 comparisons | 35 subjects × 420 comparisons; 15 presets from 934 audiograms; SAVAGE 50 → TPP 25 | Dueling bandit, two phases | – | Hearing-aid / audiogram domain (out of scope; related only); simulation | A | https://pmc.ncbi.nlm.nih.gov/articles/PMC10312409 |
| E13 | 6 | vendor trade article (Hearing Review 2018) | SoundSense Learn A/B: "only 20 iterations"; preferred to the classifier | n = 19; 84% comfort, 89% quality preference | GP / active learning (per Nielsen 2014) | proprietary | Vendor authors; hearing-aid domain | C | https://www.hearingreview.com/hearing-products/hearing-aids/real-life-applications-machine-learning-hearing-aids-2 |
| E14 | 9, 2, 6 | paper (ICML 2024) | 300k in-product pairwise preferences → reward model only 60% accurate; quality ≠ preference | 285k/15k split; 60% held-out; team agreement 60% (n = 156); quality-top preferred 53.3%; MuLan-top 51.6%; 3–5 s crops → 56% | Bradley-Terry reward model on MusicLM tokens; RLHF | Data proprietary | Generated music, not EQ; population-level | A | https://arxiv.org/html/2402.04229 |
| E15 | 6, 5 | paper (ICLR 2025) | Users as convex mixes of K prototypes → few-shot new users | synthetic / Persona / Pick-a-Pic; Summary ~59% for K = 1/5/10 | Ideal-point + mixture reward model; 2-layer MLP on frozen encoders | – | No audio; cannot generalise outside the prototype hull | B | https://ar5iv.labs.arxiv.org/html/2406.08469 |
| E16 | 9, 2, 8 | paper (AES AIMLA 2025; arXiv 2607.23846) | Self-supervised blind EQ predicts the clean spectrum from content; beats a fixed average, ≈ oracle, but < original | 8 listeners, 4 excerpts; Proposed vs Average 51–13 (p ≈ 1.9e-11); vs Oracle 31–33 (p = 0.72); Reference vs Proposed 49–15 | Frozen CLAP + 0.34M MLP → 32-band log-mel deviation from training mean; zero-phase inverse | Paper CC BY 4.0; code / weights licence not stated | ±20 dB synthetic colorations; estimate reflects training statistics; coarse filter | A | https://arxiv.org/html/2607.23846 |
| E17 | 9, 2 | paper (ICML 2026) | SonicMaster: restoration of synthetic degradations on real masters; EQ the weakest category | ~25k clips × 7 = ~175k pairs; 12 listeners × 43 pairs; EQ quality n.s.; 180/200 vs baselines on X-band EQ (20 people) | Text-conditioned rectified flow; Audiobox-PQ-filtered Jamendo | Code Apache-2.0; weights licence not stated | Generative artifacts; EQ "subtle / stylistic" | A | https://arxiv.org/html/2508.03448v3 |
| E18 | 9 | dataset card | SonicMaster dataset public on HF | ~175k rows; 506 GB; 19 degradations / 5 groups | Paired clean / degraded + prompts + params | Card says CC-BY-2.0; source is Jamendo CC (licence inconsistency) | Verify per-track source licences | C | https://huggingface.co/datasets/amaai-lab/SonicMasterDataset |
| E19 | 9 | paper (DAFx 2025) | Blind estimation "learns the distribution of unprocessed signals"; parameter non-identifiability | MSD 40k/5k/5k; high-shelf cascade toy | Normalizing-flow parameter distributions | Code on GitHub (licence not checked) | Toy EQ task | B | https://dafx25.dii.univpm.it/wp-content/uploads/2025/09/DAFx25_paper_19.pdf |
| E20 | 9 | paper (ICASSP 2024) | Blind mastering-chain estimation from wet audio only | EQ Mel loss 0.32 vs 0.64 baseline | 5-band PEQ / 10-band GEQ + comp + clipper on MUSDB18 | – | No listening test; parameter distance ≠ perceptual | B | https://ar5iv.labs.arxiv.org/html/2310.11781 |
| E21 | 9 | paper (WASPAA 2023) | RemFX effect removal; **no EQ** | 5 effects; 8k/1k/1k per configuration; +5.5 dB SI-SDR (1 fx) → +3.8 (5 fx) oracle | Effect classifier + per-effect removers | Datasets / models on Zenodo | EQ absent; stacked effects hard | B | https://ar5iv.labs.arxiv.org/html/2308.16177 |
| E22 | 9 | paper (JAES 2022) | DeepAFx-ST: self-supervised style transfer with random PEQ + comp on halves of one recording | LibriTTS 360 h; MTG-Jamendo 55k; objective only | Differentiable 6-band PEQ + comp controller | Code online (licence not stated here) | Train/inference mismatch; music harder; out-of-distribution drop | B | https://ar5iv.labs.arxiv.org/html/2207.08759 |
| E23 | 9 | paper (ISMIR 2024) | ST-ITO / AFx-Rep self-supervised effect representation | 7 datasets, ~60 h; 63 VST3 plugins; zero-shot accuracy 0.86 vs 0.78; 23-listener test | Effect / preset classification pretext → gradient-free ITO | "Open-sourced"; licence not stated | Similarity, not preference | A | https://arxiv.org/html/2410.21233v1 |
| E24 | 9 | paper (ICASSP 2023) | FXencoder contrastive FX disentanglement on MUSDB18 with FX-normalisation | 86/14/50 split; 11 engineers, 12 questions | Same-FX/different-content positives | MIT code (E25); weights on Google Drive, terms not stated | Timbre vs FX confound | A | https://ar5iv.labs.arxiv.org/html/2211.02247 |
| E25 | 8, 9 | code repo | FXencoder / MixFXcloner code + weights | – | – | MIT (code); weights terms not stated | Trained on NC MUSDB18 | C | https://github.com/jhtonykoo/music_mixing_style_transfer |
| E26 | 9 | paper (ICASSP 2022) | Self-supervised remastering by same-song segments | 760/28 private mastered songs; encoder on MTG-Jamendo; 17 listeners (MUSHRA similarity) | Random PEQ / imager / limiter manipulations | Inference code + models on GitHub | Tone matches worse; >1 kHz shortfall; private data | A | https://ar5iv.labs.arxiv.org/html/2202.08520 |
| E27 | 9 | paper (2025) | ITO-Master: mastering style transfer trained on MoisesDB mixtures | 200 MTG-Jamendo eval songs; 10 listeners, 8 questions | FX-norm (EQ / imager / loudness) + random chains on halves | Code SonyResearch/ITO-Master (licence not stated) | Similarity only; preference left to future work | A | https://arxiv.org/html/2506.16889 |
| E28 | 9 | paper (ISMIR 2022) | EQ-normalise stems to the **class-average spectrum**; learn the inverse | MUSDB18 + 1,505 private; 14 engineers (6 songs × 6 mixes) | 65,536-pt STFT averages → 1,001-tap zero-phase FIR | – | "Conservative"; none "consistently very good" | A | https://ar5iv.labs.arxiv.org/html/2208.11428 |
| E29 | 9 | paper (ICASSP 2021) | 138 real unmastered/mastered pairs from Mixing Secrets | ~430 / 51 / 50 min; 17-listener MUSHRA; 50-param chain (32-band GEQ) | Black-box effects with gradient approximation | – | Data not released | A | https://ar5iv.labs.arxiv.org/html/2105.04752 |
| E30 | 9 | paper (ISMIR 2024) | Diff-MST trained on MedleyDB + Cambridge (+ Jamendo references); states licences | No listening test | Synthetic random mixes or real unpaired references + AF loss | Code CC BY-NC-SA 4.0 (per search; not re-verified) | Misstates MTG-Jamendo as Apache-2.0 | B | https://arxiv.org/html/2407.08889v1 |
| E31 | 9 | paper (2024, Native Instruments) | Instrument auto-EQ to per-class average "ideal spectrum"; real-world targets beat random synthesis | 45k classified samples; 31,346 → 156,730 curves; MAE −24%; 26 internal listeners prefer ~2:1 | Classifier → target diff → differentiable 4-band PEQ matcher | private data | Encodes corpus average; internal panel | A | https://arxiv.org/html/2407.16691v1 |
| E32 | 9 | paper (ICASSP 2026) | MEGAMI: model the distribution of mixes; regression framing is the flaw | "approaching human-level" (details not opened) | Generative effect embeddings | Paper CC BY 4.0 | Listening details unverified | B | https://arxiv.org/abs/2511.08040 |
| E33 | 9 | dataset repo | MTG-Jamendo licence and size | 55k+ tracks; 508 GB raw | – | Code Apache-2.0; metadata CC BY-NC-SA 4.0; audio per-track CC; **non-commercial research only** | Commercial use needs Jamendo's permission | C | https://github.com/MTG/mtg-jamendo-dataset |
| E34 | 9 | dataset repo | FMA licence and size | 106,574 tracks; 161 genres; 879 GiB | – | Code MIT; metadata CC BY 4.0; audio per-artist CC | Many tracks NC | C | https://github.com/mdeff/fma |
| E35 | 9 | dataset record | Song Describer | ~1.1k captions; 706 tracks; 3.3 GB | – | CC BY-SA 4.0 (record); per-track audio licences | Small | C | https://zenodo.org/records/10072001 |
| E36 | 9 | dataset card | MusicCaps | 5,521 × 10 s | YouTube IDs | CC BY-SA 4.0; audio not distributed | Audio access | C | https://huggingface.co/datasets/google/MusicCaps |
| E37 | 9 | dataset page | AudioSet | 2,042,985 + 22,176 + 20,383 segments; 527 classes | YouTube IDs + VGGish-like features | CC BY 4.0 (labels); ontology CC BY-SA 4.0 | No audio | C | https://research.google.com/audioset/download.html |
| E38 | 9 | dataset page | MedleyDB 1 + 2 | 122 + 74 = 196 multitracks | – | Permission request on Zenodo; CC BY-NC-SA per E30 | NC | C | https://medleydb.weebly.com/ |
| E39 | 9 | dataset record | MUSDB18-HQ | 150 songs (100/50); 22.7 GB | 4 stems + mix | "Other (Non-Commercial)", educational | NC | C | https://zenodo.org/records/3338373 |
| E40 | 9 | site FAQ | Cambridge-MT usage terms | – | – | Educational only; research "not specifically agreed" | Page returned 403; text from search snippet | U | https://cambridge-mt.com/ms/mtk-faq |
| E41 | 9 | dataset repo | MoisesDB | count not shown | – | CC BY-NC-SA 4.0 | NC | C | https://github.com/moises-ai/moises-db |
| E42 | 9, 5 | dataset site | AcousticBrainz data is CC0; frozen 2022 | 7,564,215 unique / 29,460,584 total; dumps 2022-06-23 (30 zst archives + 3 CSVs × 29.46M rows) | Essentia music-extractor features | **CC0** | User-submitted files; mixed encodings | C | https://acousticbrainz.org/ ; https://acousticbrainz.org/download |
| E43 | 9 | docs | Essentia extractor: barkbands (27), melbands, erbbands; energy bands 20–150 / 150–800 / 800–4k / 4k–20k Hz; stats mean / var / median… | – | – | AGPL (Essentia; not re-verified) | Equal-loudness prefilter not documented for barkbands | C | https://essentia.upf.edu/streaming_extractor_music.html |
| E43b | 9 | docs | BarkBands default edges include 150, 510, 2000, 6400 Hz (power summed per band) | 29 edges, 0–27 kHz | – | – | – | C | https://essentia.upf.edu/reference/std_BarkBands.html |
| E44 | 2, 9 | paper (2025) | Audiobox Aesthetics: 4-axis predictors from about 97k rated clips | ~500 h (1/3 music); 158 raters × 3 ratings / clip; PQ r = 0.887 on natural music; AES-Natural 2,950 clips × 10 raters released | WavLM-style predictor | Repo CC-BY 4.0 (+ MIT parts) | No same-clip EQ sensitivity test | A | https://arxiv.org/html/2502.05139 |
| E45 | 8 | code repo | Audiobox Aesthetics licence | – | – | CC-BY 4.0 (most of project) | Weights licence not separately stated | C | https://github.com/facebookresearch/audiobox-aesthetics |
| E46 | 5, 9 | review article (Acoustics Today 2022, Olive) | Headphone-target preference classes | 64% Harman class; 21% "less bass" (more female / older, no trained listeners); "more bass" 4:1 male | Cluster analysis of preference ratings | – | Device response, not content | B | https://acousticstoday.org/issues/2022AT/Spring2022/files/basic-html/page66.html |
| E47 | 5, 9 | vendor article (Harman / AKG 2023) | Listeners adjusted bass/treble per music sample; program influenced preference | 283 listeners (first study); 130 (survey); 64% satisfied by target | – | – | Vendor; no dB values | C | https://pro.harman.com/insights/wp-json/wp/v2/posts/12503 |
| E48 | 5 | paper (AES 2019, Olive / Welti / Khonsaripour) | 3 classes: 64% / 15% (+4–6 dB bass) / 21% (−2 dB bass) | as stated | Cluster analysis | – | Not opened (AES 403) | U | https://aes2.org/publications/elibrary-page/?id=20289 |
| E49 | 5, 9 | vendor article (iZotope) | TBC targets from thousands of commercial tracks; listening-environment groups; ranges not lines | 3 groups; 4 broad bands per the article (<250 / 250–2k / 2–8k / >8k) | Statistical variation per group; per-second custom targets | proprietary; data unpublished | No numbers / method published | C | https://www.izotope.com/en/learn/why-izotope-created-the-tonal-balance-control-plug-in.html |
| E50 | 5 | vendor manual | TBC factory curves Orchestral / Bass Heavy / Modern; custom from file or folder | Bands 20–250 / 250–2k / 2–8k / 8–20k | – | proprietary | – | C | https://downloads.izotope.com/docs/tonal-balance-control/meters-and-target-curves/index.html |
| E51 | 9 | paper (AES 135, 2013) | Commercial recordings 1950–2010 lean to a consistent target EQ curve, partly like natural ensembles | "large dataset" (size not seen); "≈5 dB/oct 100–4k" is secondhand (U) | LTAS with a new averaging method | Restricted PDF | Full text not opened | B | https://ciencia.ucp.pt/en/publications/spectral-characteristics-of-popular-commercial-recordings-1950-20/ |
| E52 | 9 | paper (AES 142, 2017) | More percussion → relatively more bass and treble in the LTAS; improves auto-EQ targets | – | HPSS + LTAS | – | Not opened | U | https://aes2.org/publications/elibrary-page/?id=18638 |
| E53 | 9 | paper (JAES 2014) | Engineers mix toward a target curve approximated by a large-corpus average spectrum | 55 Rock Band multitracks; 392 tracks | Loudness / spectrum descriptors | – | The target-curve claim cites others; rock only | B | https://www.francoispachet.fr/wp-content/uploads/2021/01/deruty-14c.pdf |
| E54 | 9 | paper + dataset (AES 157, 2024) | MixCheck amateur mix/master metrics incl. tonal profile, 30 genres | csv 24.8 MB | – | **CC BY 4.0** | Amateur producers; band definitions unverified | B | https://zenodo.org/records/13683186 |
| E55 | 11, 9 | patent (Gracenote US10998872B2) | NN trained on reference audio + engineer-made EQ curves (engineer-tagged); like-button personalisation; blend | priority 2018-10-24; active, ~2039 | PEQ or 25-Bark-band output | – | Training size unstated | B | https://patents.google.com/patent/US10998872B2/en |
| E56 | 11, 6 | patent (Northwestern US8565908B2) | EQ preference learning from listener feedback on probe curves | priority 2009-07-29; marked ceased; reissue RE48462 noted | Weighting function from ratings | – | Claims not read | B | https://patents.google.com/patent/US8565908 |
| E57 | 2 | paper (JAES 2016, Wilson & Fazenda) | Quality vs liking separate for commercial CDs; for alternate mixes R² = 0.82 | – | – | – | Not opened | U | https://salford-repository.worktribe.com/output/1407562/perception-of-audio-quality-in-productions-of-popular-music |
| E58 | 9, 5 | papers (Acoustics 2022; AES 2024) | 5 EQ curves × 10 excerpts; HF boost most preferred; band energy predicts preference | 52 listeners | Linear regressions on mel-band energy | – | Not opened (403) | U | https://www.mdpi.com/2624-599X/4/3/45 |
| E59 | 5 | paper (IEEE JSTSP 2026) | Listener variability in prompt → EQ; population distributions | 11 participants (DataPort, 120 rows) | LLM ICL / PEFT | Paper CC BY 4.0 | NL is out of scope | B | https://arxiv.org/abs/2601.09448 |
| E60 | 9 | dataset record | AcousticBrainz-Genre labels | 4 sources; features 36.8 GB | – | **CC BY-NC-SA 4.0** (AllMusic subset restricted) | NC | C | https://zenodo.org/records/2553414 |

---

## 4. Search log

All via the WebSearch tool on 2026-10-10. "Hits" = results screened; "incl." = new sources included (then opened via WebFetch / Read).

| # | Query | Source | Hits | Incl. |
|---|---|---|---|---|
| 1 | SocialEQ dataset Cartwright Pardo equalization descriptors crowdsourced | Web | 10 | 0 |
| 2 | SAFE dataset Semantic Audio Feature Extraction Stables equalizer descriptors | Web | 9 | 2 (E2, E4) |
| 3 | Mix Evaluation Dataset De Man Reiss ratings mixes | Web | 9 | 2 (E7, E8) |
| 4 | Audealize dataset audio descriptors equalization reverberation Seetharaman Pardo | Web | 9 | 1 (E1) |
| 5 | Seetharaman Pardo "Audealize" crowdsourced audio production tools JAES 2016 | Web | 9 | 0 |
| 6 | Pardo Little Gergle personalized audio equalizer transfer learning active learning few ratings | Web | 9 | 2 (E9, E56) |
| 7 | interactiveaudiolab github socialeq data download | Web | 10 | 0 |
| 8 | SAFE-DB dataset semantic audio equalisation github download warm bright | Web | 10 | 1 (E16) |
| 9 | SocialFX dataset crowdsourced audio effects terms … huggingface | Web | 10 | 0 |
| 10 | LLM2Fx predict audio effects parameters natural language SocialFX dataset EQ | Web | 19 | 1 (E3) |
| 11 | "Mix Evaluation Dataset" De Man Reiss DAFx 2017 multitrack mixes ratings | Web | 9 | 0 (confirm) |
| 12 | Brecht De Man mix evaluation dataset download multitrack licence | Web | 10 | 0 |
| 13 | Olive Welti Khonsaripour preferred bass and treble headphones preference segments | Web | 10 | 2 (E46, E48-U) |
| 14 | Pestana Ma Reiss spectral characteristics of popular commercial recordings target curve | Web | 10 | 1 (E51) |
| 15 | MusicRL aligning music generation human preferences 300,000 pairwise | Web | 10 | 1 (E14) |
| 16 | "Class 2" "4-6 dB more bass" Harman target listener segmentation | Web | 9 | 0 (secondary) |
| 17 | Ma Reiss Black intelligent equalization tool Yule-Walker mastering | Web | 9 | 0 |
| 18 | long-term average spectrum commercial music genre "target curve" mastering | Web | 20 | 1 (E52-U) |
| 19 | Elowsson Friberg LTAS percussion pdf | Web | 10 | 0 |
| 20 | iZotope Tonal Balance Control target curves thousands commercial tracks | Web | 9 | 2 (E49, E50) |
| 21 | DeepAFx-ST style transfer … self-supervised MTG-Jamendo DAPS | Web | 20 | 1 (E22) |
| 22 | Diff-MST differentiable mixing style transfer dataset MedleyDB | Web | 29 | 1 (E30) |
| 23 | ST-ITO inference-time optimization AFx-Rep | Web | 9 | 1 (E23) |
| 24 | Koo music mixing style transfer contrastive FXencoder MUSDB18 | Web | 9 | 2 (E24, E25) |
| 25 | RemFX general purpose audio effect removal WASPAA 2023 | Web | 19 | 1 (E21) |
| 26 | Martínez-Ramírez automatic music mixing out-of-domain EQ average spectrum | Web | 18 | 2 (E28, E31) |
| 27 | SonicMaster controllable all-in-one music restoration mastering | Web | 18 | 2 (E17, E18) |
| 28 | dataset unmastered mastered pairs music mastering deep learning paired tracks | Web | 20 | 3 (E29, E27, E41) |
| 29 | AcousticBrainz data dump CC0 low-level barkbands | Web | 9 | 1 (E42) |
| 30 | Nielsen Jensen Larsen personalization hearing aids GP active learning pairwise | Web | 9 | 1 (E12) |
| 31 | End-to-end music remastering self-supervised adversarial Koo | Web | 9 | 1 (E26) |
| 32 | hierarchical Bayesian population prior preference learning audio personalization | Web | 10 | 1 (E11) |
| 33 | Widex SoundSense Learn A/B comparisons Bayesian | Web | 10 | 1 (E13) |
| 34 | listening test preferred equalization same music excerpt spectral tilt ratings | Web | 10 | 2 (E58-U, E59) |
| 35 | Wilson Fazekas perception of audio quality productions popular music mixes | Web | 9 | 1 (E57-U) |
| 36 | Dourou Acoustics 2022 MDPI equalization curves mel-band energy | Web | 10 | 0 (403) |
| 37 | automatic mixing "regression to the mean" average mix conservative | Web | 9 | 1 (E32) |
| 38 | Steinmetz Reiss intelligent music production review data scarcity | Web | 20 | 0 |
| 39 | meta-learning few-shot personalization audio equalization few ratings | Web | 9 | 0 |
| 40 | PAL pluralistic alignment personalized reward model ideal points | Web | 10 | 1 (E15) |
| 41 | "SocialFX" OR "socialeq" dataset github json 40 bands | Web | 9 | 0 |
| 42 | github SAFE plugins semantic audio labs SAFEEqualiser dataset | Web | 20 | 2 (E5, E6) |
| 43 | Essentia MusicExtractor equal-loudness barkbands | Web | 9 | 1 (E43) |
| 44 | blind estimation equalizer parameters music deep learning | Web | 9 | 2 (E19, E20) |
| 45 | learning user equalizer preferences from usage logs implicit feedback | Web | 10 | 1 (E55) |
| 46 | preferential Bayesian optimization equalizer music listener pairwise | Web | 9 | 1 (E10) |
| 47 | Sabin Rafii Pardo weighting-function-based rapid mapping 25 ratings | Web | 30 | 0 |
| 48 | genre-specific spectral balance reference curves commercial masters open data | Web | 19 | 2 (E53, E54) |
| 49 | AcousticBrainz Genre dataset Bogdanov licence | Web | 10 | 1 (E60) |

Direct lookups (not searches), each opened:
- socialeq.org (dead)
- semanticaudio.co.uk (refused)
- bit.ly → Dropbox (unverifiable)
- MTG-Jamendo, FMA, Song Describer, MusicCaps, AudioSet, MedleyDB, MUSDB18-HQ, MoisesDB
- AcousticBrainz home / download / data, Essentia docs
- Audiobox Aesthetics repo and paper
- Harman AKG post, Acoustics Today pp. 64–66
- Gracenote and Northwestern patents
- SonicMaster GitHub and HF card

**Roughly 600 results screened (with overlap); 60 sources included; 7 of them U.**

**Snowball (one hop).**
- E9 (Pardo 2012) → backward: Sabin, Rafii & Pardo 2011 (abstract only, U); forward: cited by E10 ✓.
- E16 (Moliner) → backward: MedleyDB / DSD100 / CLAP ✓; forward: none yet (posted 2026-07).
- E7 (De Man) → backward: Wilson's 101-mix study (E57-U), Open Multitrack Testbed; forward: MixologyDB (E8), MixAssist (seen, not opened).
- E14 (MusicRL) → forward: survey arXiv 2511.15038 (seen, not opened).

**Saturation notes.**
- 9.1 preference/descriptor datasets: **saturated**. The last three dataset queries (#36, #41, #42) added no new dataset, only availability info.
- 9.2 paired data: **stopped at cap**. #28 and #44 still added sources, but these are all small or synthetic, so the conclusion is stable.
- 9.3 self-supervised: **near saturation**. #44 and #37 added E19/E20/E32, all consistent with the existing picture.
- 9.4 corpora: **complete for the named corpora** (direct lookups).
- 9.5 feedback / priors: **saturated for audio-EQ**. #39 and #47 added nothing; general ML personalisation literature (meta-learning, RLHF personalisation) was *not* exhausted.
- 9.6 cold start: **stopped at cap**. #48 still added E53/E54, so a further round may find more genre-target studies.

---

## 5. Answers per RO

### RO9: What data exists or can be generated, under which licences, and can a useful model be built without large labelled data?

**Answer.**
1. **Labelled preference data for our exact task does not exist publicly.** Descriptor datasets (SocialEQ, SAFE) give theme *shapes*, not preferences, and their availability and licences are uncertain. The Mix Evaluation Dataset gives *mix-level* same-song preference. All EQ-on-music preference sets are private and have under 30 listeners.
2. **Paired data** is small and NC (MedleyDB, MUSDB, MoisesDB, Cambridge-MT). It supports *unmastered → mastered*, which is not our *mastered → preferred* problem.
3. **Self-supervised "undo a random EQ"** can be generated from any set of high-quality masters. It yields a content-aware reference curve that measurably beats a fixed average target on synthetic colorations [E16]. But it shows no reliable benefit on real, good masters [E17], and it structurally regresses to the corpus balance [E19, E28, E31]. So it is a *sensing / correction prior*, not a preference model.
4. **Yes, a useful model can be built without a large labelled dataset, if it is decomposed.** The decomposition:
   - (a) content deviation measured against a licence-clean reference distribution: AcousticBrainz CC0 Bark bands aligned to the Tone edges, and/or the user's own library;
   - (b) theme offsets hand-specified from published structure: Harman classes, iZotope's listening-environment groups, descriptor shapes;
   - (c) a low-dimensional (5-D) Bayesian personal offset learned from tens of level-matched pairwise judgments with active queries [E9, E10, E11].
   An end-to-end neural "content + theme + feedback → Tone" policy *cannot* be trained from public data. Population feedback at 300k-pair scale still predicts preference only about 60% of the time [E14].

**Confidence.**
- High that no suitable public labelled dataset exists.
- High that the self-supervised scheme learns a corpus average and has a null/negative effect on good masters (E16, E17, E19, E28, E31).
- Medium that tens of judgments suffice. There is direct 5-band evidence [E10], but only within one song per session; cross-track transfer of a personal preference is untested.
- Medium on licences: verified for corpora; SocialEQ, SAFE and SonicMaster remain unclear.

**Key sources:** E1, E4, E7, E9, E10, E11, E14, E16, E17, E19, E28, E31, E33, E42, E43b, E46.

### Cross-RO answers (short)

| RO | Answer from this track | Confidence | Sources |
|---|---|---|---|
| RO2 | Quality / aesthetic predictors barely track individual preference (53%). Audiobox Aesthetics is untested for same-clip EQ sensitivity, so track D must probe it before using it as an objective. | med | E14, E44, E7 |
| RO5 | Three recurring clusters is a reasonable starting theme count (neutral, more bass / "modern", less bass / "orchestral-like"), plus descriptor themes (warm / bright). Personal residuals are needed because descriptor meanings split. | med-low | E46, E49, E1, E4, E15 |
| RO6 | A 5-D space plus active GP / pairwise reaches a useful optimum in about 10–30 judgments per context. A prior from "others" helps most early; for one user, substitute published class structure and pooling across contexts (inference). | med | E9, E10, E11, E12, E13, E15 |
| RO8 | The Moliner-style head (0.34M params on a frozen encoder) is small; encoder weights licences need checking. AcousticBrainz-style band statistics are trivial to compute on-device. | med | E16, E25, E43b, E45 |
| RO11 | Gracenote's active patent covers NN-from-engineer-EQ-curves, like-button personalisation and dynamic/personal blending. Track F should read its claims. | med (claims unread) | E55, E56 |
| RO12 | No public benchmark exists. Reuse designs: loudness-normalised pairwise with repeats [E16], tournament-at-N [E10], no-reference preference [E7]. Build the founder's own labelled set; that is the only on-task validation data. | high | E7, E10, E16 |

---

## 6. Gaps (what the evidence does not answer)

1. **No study of EQ preference on finished commercial masters across many tracks for one listener.** Every personal-EQ study learns one song or clip per session [E9, E10]. Whether a personal offset *transfers across tracks* (and across sections) is unknown. This is the core assumption of our design.
2. **No evidence that self-supervised restoration improves real, un-perturbed masters.** E16 is synthetic ±20 dB; E17's EQ result is null on real Jamendo masters. Nobody has measured listener preference for "corrected toward corpus" versus original on genuinely old or poorly balanced masters, which is the only case where it should help.
3. **No per-section data.** There are no datasets or studies of section-wise EQ preference. Indirect hints: preference prediction worsens with shorter crops [E14]; section content skews single-track targets [E49]. This goes to RO4.
4. **Implicit feedback.** No published mapping from revert / skip / override to EQ preference; only patent descriptions [E55].
5. **Label noise for one expert listener.** Reported consistency is for crowds (r = 0.41 [E1]) or for teams on generated music (60% [E14]). There is no estimate of the founder's own test–retest reliability for 1–2 dB Tone differences, and that sets the floor on achievable learning speed.
6. **Licence status of the descriptor datasets.** SocialEQ's original host is dead and its licence is unstated. SAFE-DB's host is unreachable and its size is unverified (1,369, U). SonicMaster's CC-BY-2.0 label conflicts with its Jamendo source licences. Cambridge-MT research use is unclear.
7. **Genre-conditional reference curves.** No open, published per-genre target curves exist: Pestana's data is not public, iZotope's is proprietary, Elowsson's is unverified. The CC0 AcousticBrainz route is promising, but its genre labels are NC. Also unchecked: whether its Bark bands have any prefilter, and how lossy-file low-passing biases "Air". Both need an on-repo probe.
8. **Harman class magnitudes.** The +4–6 dB / −2 dB figures and the 15% share are unverified (AES paywall). Also, these are device-target preferences: how they combine with per-output memory without double-correcting is a design question, not answered by the evidence.
9. **General ML personalisation literature** (meta-learning reward models, in-context preference learning) was not exhausted. There may be stronger few-shot methods than GP / hierarchical Bayes, but none was found that has audio-EQ evidence.
