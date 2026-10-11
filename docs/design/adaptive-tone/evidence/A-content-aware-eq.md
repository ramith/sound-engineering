# Brief A: Content-aware EQ. Sensing, the objective, the policy and themes as embeddings

*Track A · 2026-10-10 · follows `00-research-protocol.md`. Owns **RO1** (sensing), **RO2** (the objective, including the Audiobox Aesthetics deep-dive), **RO3** (the policy), and the embedding/reference half of **RO5** (themes). Includes a cross-track note for RO4. Source IDs `S#` refer to the evidence table at the end. Grades: A, B, C, D, U as in protocol §4. "Inference:" marks my own reasoning, not a source's claim.*

---

## TL;DR

- **Automatic EQ beats the original only when the input is raw or damaged, never yet on a finished master.** The best result is a blind A/B test with 26 listeners on unprocessed instrument tracks: auto-EQ was preferred 57.2% to 28.8%, with 14% undecided [S4, A]. A blind EQ-restorer won 60–4 over randomly EQ-damaged music, with 8 listeners [S5, A]. I found **no listening test** where automatic EQ of a finished commercial master beat the untouched master. In the closest test, a restoration model's "fix the EQ" outputs gave **no significant** quality gain, the only category of five without one [S24, A].
- **Style transfer is tested for similarity, not preference.** ST-ITO (23 listeners), Koo's MixFXcloner (11) and ITO-Master (10) asked "how close is this to the reference?" [S7, S8, S10]. DeepAFx-ST and Diff-MST ran no listening tests at all [S6, S9]. None of them shows that listeners *like* the result better.
- **Mature systems have one thing in common: they are static per track.** Matchering applies one zero-phase FIR per mid/side channel, built from the loudest pieces of the whole track [S15]. DeepAFx-ST mean-pools the whole clip into one embedding [S6]. Diff-MST names "static mixing configurations" as a limitation [S9]. I found no evidence, for or against, that listeners prefer EQ that changes mid-song on a finished master. This is a gap for RO4 (track B).
- **Audiobox Aesthetics (the founder's flag) is at best a coarse quality gate, not a critic for choosing between EQ candidates.**
  - It resamples everything to **16 kHz mono** [S18], so it cannot hear the "Air" band above 8 kHz or the stereo image.
  - It was trained on differences *between* clips. It was never validated on processing changes to the *same* clip, and I found no follow-up that did.
  - Its agreement with human fidelity preferences between music systems is 59% against a 50% chance level [S23].
  - Optimising a generator against it shows reward hacking: +0.58 on Audiobox, while CLAP and SongEval scores fell [S27].
- **Sensing is the solved part.** These are all deterministic and cheap to compute ahead of playback:
  - a whole-track or per-section long-term spectrum (Matchering's analysis is a 4096-point average) [S15];
  - section labels from All-In-One: 10 labels including verse and chorus, MIT code, 10 songs in 73 s on an RTX 4090 [S33];
  - SongFormer, newer, with open weights [S34].
- **Themes as embeddings or reference tracks are well developed for matching, but general-purpose embeddings are the wrong tool.** CLAP scored 0.56 at telling production styles apart, against 0.86 for an effects-trained embedding (AFx-Rep) [S7]. CLAP-guided EQ made a sound more "warm/bright/…" in only 45–48% of 924 ratings, against 22% for random EQ [S16].
  - The strongest pattern is DeepAFx-ST's **"adaptive presets"**: a curated set of reference recordings, each with a semantic label, chosen by the user [S6]. That is almost exactly the founder's "theme".
  - A Gaussian **prior over plausible settings** cut parameter error by up to 33% and was favoured by 16 listeners [S37]. That is a natural way to make a theme a guard-rail.
- **The output format suits AdaptiveSound.** Every target-matching method produces a *smooth correction curve*:
  - LOWESS smoothing in Matchering [S15];
  - Savitzky–Golay in FxNorm [S11];
  - Gaussian smoothing with a ±12 dB cap in Mockenhaupt [S4];
  - 32 mel bands in Moliner [S5].

  Inference: the existing accurate 31-band cascade GEQ can realise such a curve directly. The neural networks in this literature that "match a parametric EQ" (4–6 bands) [S4, S14] solve a problem this product doesn't have.

---

## Findings by RO

### RO1: Sensing (what can be read ahead, and what predicts a preferred correction)

**Spectral balance against a target.** Pestana et al. analysed long-term spectra of commercial recordings from 1950 to 2010 [S1]. They found "a consistent leaning towards a target equalization curve" that comes from industry practice and partly mimics the natural spectra of ensembles. I could open only the abstract, so I have no per-genre or per-decade numbers.

Elowsson & Friberg reportedly attribute genre differences in long-term spectrum mainly to how prominent the percussion is [S3, U: search snippet only]. Inference: if true, a target conditioned on percussiveness would beat one conditioned on genre labels.

The one target-based EQ with a positive preference result conditions its target on **instrument class**: 35 classes, with 79% classifier accuracy [S4]. FxNorm-Automix normalises each stem toward the average spectrum of its stem type [S11]. Both are stem-level methods. No source conditions a *mastering* target on content features and then tests listener preference.

**Structure and sections.**
- All-In-One [S33] predicts beats, downbeats and functional segments with 10 labels: start, end, intro, outro, break, bridge, inst, solo, verse, chorus. It reports state of the art on the Harmonix Set. It runs Demucs source separation internally. Code is MIT; the weights' licence is not stated.
- SongFormer [S34] (2025) reports the best strict boundary score on its own 300-song benchmark and beats Gemini 2.5 Pro. It is open-sourced; the licence is not stated on the page.
- MSAF [S35] is the older MIT-licensed framework.
- One-hop snowball: 53 papers cite All-In-One [S33]. None applies its sections to audio *processing* (EQ, mixing or mastering). The only playback-adaptive use is exercise tempo sync.

**Production quality.** Audiobox Aesthetics PQ can be computed per 10-second window [S18]. Its limits are covered under RO2.

**Instrument and genre content.** A CNN instrument classifier is practical (79% over 35 classes) [S4]. I ran no dedicated search on genre, mood or era classifiers. That is a gap, which belongs with RO8 (track D).

### RO2: The objective (what "better" means)

Three candidate objectives appear in the literature:

**(a) Distance to a target curve or reference.** This is the objective used by Matchering [S15], FxNorm [S11], Mockenhaupt [S4] and Moliner [S5]. Its listening-test support has a pattern:

| Study | Input material | Listeners | Result |
|---|---|---|---|
| Mockenhaupt [S4] | raw instrument tracks | 26 | auto-EQ preferred 57.2% vs 28.8% |
| Moliner [S5] | music deliberately EQ-damaged at random | 8 | restorer won 60–4 over the damaged input |

In Moliner's test, a fixed **average-spectrum** correction lost to the content-aware one, 13–51. Inference: one static "average" target is a poor objective even for damaged material.

Neither study tested finished masters.

**(b) A learned aesthetics or quality predictor.** See the deep-dive below. Short version: there is no evidence that any such predictor tracks listener preference for **EQ changes on the same track**.

**(c) A model of the listener's own preference.** This half belongs to RO6 (track B). The one item I found for that track was the Pardo-group EQ preference-learning patent [S48, U].

#### RO2 deep-dive: Meta Audiobox Aesthetics [S18, S19]

**(1) Axes, annotation and agreement.** Raters scored four axes on a 1–10 scale (§2.1 and Appendix B):

| Axis | Definition in the guidelines |
|---|---|
| **Production Quality (PQ)** | "Technical aspects of quality instead of subjective quality": clarity & fidelity, dynamics, *frequencies* ("balanced and natural frequency response… bass well-defined without muddiness or boominess; high frequency… crisp… without harshness or sibilance"), spatialization, and overall technical proficiency |
| **Production Complexity (PC)** | The number of audio components |
| **Content Enjoyment (CE)** | Emotional impact, artistic skill, artistic expression, subjective experience |
| **Content Usefulness (CU)** | How likely a content creator would be to use the clip as source material |

How the data was collected:
- About **500 hours, 97k samples**, split evenly across speech, sound and music, mostly 10–30 s long and loudness-normalised before annotation.
- **3 ratings per sample**, from **158 raters**. Raters qualified by reaching **Pearson > 0.7** against expert "golden" labels on PQ and PC.
- **No inter-rater agreement statistic is reported.** The only reliability figure is the qualification threshold.
- The axes correlate with each other: PQ–CU r = 0.81, CE–CU 0.63, PQ–CE 0.52. PC correlates with the others at only 0.26–0.35.
- The separate AES-Natural evaluation set has 2,950 clips, 10 trained annotators per clip. Its 1,000 music clips come from MUSDB18-HQ (451) and MusicCaps (549).

**(2) Architecture, input and windowing.**
- The model is a WavLM-style 12-layer Transformer (768 hidden). A weighted sum across layers is mean-pooled over time, L2-normalised, and fed to four MLP heads. The model card gives about 0.1B parameters (F32).
- **Input is resampled to 16 kHz, single-channel.** Training uses random 10-s chunks.
- At inference it scores consecutive 10-s windows and takes a length-weighted average (Algorithm 1). The CLI accepts `start_time`/`end_time` per item [S19].
- **So it can score per section** (sections of 10 s or more fit naturally). But it is blind to everything above 8 kHz and to stereo, even though the PQ guidelines include high frequencies and spatialization.

**(3) Is it sensitive to EQ or tonal balance on the same music?** I found no evidence that it is.
- The paper reports only correlations with human labels *across different clips*. On natural music, PQ has an utterance-level Pearson correlation of 0.887 on AES-Natural. On PAM-music it is 0.587 against expert PQ labels and 0.464 against overall-quality labels.
- The paper has no degradation, processing or EQ experiments.
- I found no study that validates it against listener A/B preference for processing changes. I screened the first 100 of its more than 100 Semantic Scholar citations by title.

Indirect evidence:
- **SonicMaster [S24].** Its restoration raises mean PQ from 7.03 to 7.71, against 7.89 for clean audio, averaged over all degradation types. Yet listeners found the **EQ** category's quality gain **not significant** (n = 12, 7-point scale). EQ had "the worst preference ratings", which the authors attribute to EQ effects being "more stylistic or difficult to notice (e.g., airiness, boominess)".
- **Zhang et al. [S23].** On 1,889 non-tie fidelity-preference pairs between text-to-music systems, PQ picks the human's choice **59.1%** of the time against a 50% chance level (Spearman 0.18). PC is at chance.
- **Cyanite review [S25, D].** An informal test found PQ "only slightly lower" for a deliberately poor MP3 than for a studio reference.

**(4) Where it has been used as a reward or filter.**
- **The paper itself [S18]:** for data filtering and for "quality prompting" of TTS, text-to-music and text-to-audio generators. In pairwise human tests (200 samples, 3 listeners each), prompting at p = 75, r = 2 beat the music baseline by a net +46.2% (±7.5). Filtering at p = 50 beat it by +21.0%.
- **SMART [S26]:** an RL reward for a symbolic-music generator. A preliminary test with 14 listeners showed higher ratings. The authors warn that "over-optimization dramatically reduces diversity."
- **Rubric-Based Optimization [S27]:** DPO ranked by Audiobox gave Audiobox +0.584, but CLAP −0.019 and SongEval −0.053. The authors call this "consistent with reward hacking."
- **MuseCritic [S28]:** an evaluation metric for GRPO-tuned song generators.
- **SonicMaster [S24]:** a restoration metric.
- Every use is for **generative** models. None steers an EQ or mastering processor.

**(5) Licence.** The README says "The majority of audiobox-aesthetics is licensed under CC-BY 4.0", with portions from microsoft/unilm under MIT. The Hugging Face card lists cc-by-4.0. The weights' licence is not addressed separately [S19].

**(6) Follow-up work and close alternatives.**
- **Tests on EQ or mastering:** none found, apart from SonicMaster's use of PQ as one metric [S24].
- **PAM [S20]** prompts a CLAP-style audio-language model. Pearson correlation with human overall-quality ratings ranges from 0.33 to 0.69, depending on the text-to-music system. Its controlled-distortion tests cover noise, tanh, mu-law and reverb, but **not EQ**. Code is MIT.
- **MusicEval [S21]** is CLAP-based, built from 14 experts and 2,748 generated clips.
- **SongEval [S22]** has five *musical* dimensions (coherence, memorability, vocal phrasing, structure, musicality) and **none for production**.
- One SongEval predictor applies a **7-band ±3 dB EQ as training augmentation** (p = 0.3) [S29]. Inference: augmented copies keep the original score, so the model is trained to ignore exactly the range of changes Tone presets make. The paper does not state this rationale itself.
- SongEval also shows genre shortcut learning, overrating pop [S31]. Generic MOS predictors learn "dataset-specific acoustic signatures" [S32].
- **MAD [S30]** is a distribution-level metric, not a per-item one.
- I found no later Meta aesthetics model.

**Verdict.** Audiobox Aesthetics is **not fit as a critic for choosing among EQ candidates** on the same track. Five reasons:
1. It cannot hear above 8 kHz or stereo.
2. It was never validated on within-track processing.
3. Optimising against it is known to hack it.
4. It has unmeasured genre and demographic priors [S25 D; and S31 for SongEval].
5. Listeners themselves barely notice EQ "fixes" in the one comparable test [S24].

It is usable at most as a **coarse gate**, for example to flag a badly produced track or to veto a gross failure. Even that should be confirmed by the "+D probe" the protocol already plans: apply known spectral tilts to N tracks and check whether PQ moves monotonically.

### RO3: The policy (content to EQ/tone)

| Method | Output | Offline / real-time | Listening evidence |
|---|---|---|---|
| Matchering [S15] | One static 4096-tap zero-phase FIR each for mid and side, plus RMS match and a limiter | Offline | No peer-reviewed test. A third-party test ranked it 3rd of 12, behind two professional engineers [S49, U] |
| Mockenhaupt / NI 2024 [S4] | 4-band PEQ (shelves at 30–450 Hz and 1.5–16 kHz, 2 peaks), ±12 dB, 10 parameters | Fast (MLP or CNN) | **A/B, n = 26, 35 trials: preferred 57.2% vs 28.8%, 14% undecided.** Raw tracks |
| Moliner et al. 2026 [S5] | 32-mel-band zero-phase inverse filter. Frozen CLAP embedding plus a 0.34M-parameter head | Not stated | Pairwise, n = 8: 60–4 vs damaged input, 51–13 vs average target, 31–33 vs oracle. Damaged input only |
| DeepAFx-ST 2022 [S6] | 6-band PEQ plus a compressor | DSP real-time factor ≈ 0.003 on CPU | None |
| ST-ITO 2024 [S7] | Any effect chain. Gradient-free CMA-ES search (population 64, up to 25 steps) | **About 1 min per transfer**, vs about 1 s for parameter predictors | MUSHRA-like **similarity** test, n = 23 |
| MixFXcloner 2023 [S8] | Audio directly (TCN conditioned on a 2048-d FXencoder embedding) | Offline | Similarity, n = 11 engineers |
| ITO-Master 2025 [S10] | 46 parameters: 6-band EQ, distortion, 3-band compressor, makeup gain, stereo imager, limiter. Optimises the reference embedding (up to 100 steps) | Offline | MUSHRA-style **similarity**, n = 10. Objective AF loss: 0.099 (ITO) vs 0.160 (Matchering) |
| Diff-MST 2024 [S9] | Per track: gain, 4-band PEQ, compressor, pan. Master: stereo EQ and compressor | Offline | None. "Constrained to static mixing configurations" |
| FxNorm-Automix 2022 [S11] | A mix built from stems | Offline | n = 14 professionals: on a par with human mixes for Production Value and Excitement, better on Clarity (p = 0.008) |
| SonicMaster 2025 [S24] | **Regenerated audio** (rectified flow, Stable Audio Open VAE) | Offline, 30-s chunks | EQ category not significant (n = 12). Beat text-guided baselines 180 of 200 times (n = 20) |
| Text2FX 2025 [S16] / LLM2Fx 2025 [S17] | 6-band PEQ (18 parameters), from text | About 600 iterations / one LLM call | Text2FX: n = 167, 924 ratings, 45–48% positive vs 22% for random. LLM2Fx: none |

Other sources:
- **Parametric EQ matching** networks: Mimilakis 2020 (4-band IIR, one-shot) [S13]; Nercessian 2020 (differentiable biquads, spectral loss beats parameter loss) [S14].
- **Real-time enhancement** benchmark [S41]: "indiscriminate enhancement can make the degraded input worse." Inference: this supports a do-no-harm default.

### RO5 (embedding/reference half): Themes

- **Effects-specific embeddings beat general ones.** In ST-ITO's zero-shot style classification [S7], AFx-Rep averages 0.86. That compares with DeepAFx-ST+ at 0.78, FX-Encoder at 0.69, BEATs at 0.59 and CLAP at 0.56. Plain MFCCs score 0.74.
  - AFx-Rep is a PANNs backbone with separate mid and side embeddings. It was trained to classify which of 63 open VST effects was applied, and with which preset.
- **Embeddings for finished, wet audio.** These matter because a theme reference is itself a master, never a dry recording.
  - FXencoder [S8] (MIT code, trained on MUSDB18).
  - Fx-Encoder++ [S39]: per-instrument effects read from mixtures.
  - **RelFx** [S36] learns the *relative* effect between two already-processed clips, with no dry references needed.
- **A theme as a curated reference set.** DeepAFx-ST proposes "adaptive presets": "a curated, predefined set of style reference recordings, each with semantic descriptions" [S6]. In its Fig. 5, increasingly bright or compressed input produced progressively smaller high-shelf boosts and gentler compression. Inference: content-adaptive behaviour of exactly the kind a theme needs.
- **A theme as a prior.** MAP optimisation under a Gaussian prior fitted to a preset dataset cut parameter MSE by up to 33%, with 16 listeners favouring it [S37]. Inference: a theme can be expressed as a prior over the 5-D Tone vector, which bounds how far any suggestion can move.
- **Optimising in embedding space.** Optimising the *reference embedding* worked far better than optimising effect parameters directly (ITO-Master: 100 steps on the embedding beat 2,000 on the parameters) [S10].
- **Text embeddings are weak for EQ.** See the Text2FX numbers above [S16]. In LLM2Fx, GPT-4o picked EQ settings with an MMD of 0.22, compared with 0.55 for Text2FX [S17]. Either way, natural language is out of scope here.

### Cross-track note for RO4 (track B): changing EQ within a song

- No paper I found applies section-aware or time-varying EQ to a **finished** master and tests listener preference.
- Every system above is static per track. Matchering's analysis even uses the *loudest pieces* [S15].
- Diff-MST notes that real mixing "often entails dynamic adjustments… our system is presently constrained to static mixing configurations" [S9].
- The All-In-One citation snowball found no processing applications [S33].
- Inference: this is unexplored, not refuted. Any mid-song change would be novel, and would need its own listening test.

---

## What this means for the founder's idea

**Well supported**
- Reading ahead to compute long-term spectra, section boundaries and an effects embedding is reliable, cheap and fully offline [S15, S33, S34, S7].
- Computing a smooth, bounded correction toward a target or reference is a mature technique [S4, S5, S11, S15]. The output shape fits the 31-band GEQ.
- Defining a "theme" as a curated set of reference tracks plus a prior over Tone settings has direct precedent [S6, S37]. So does using an effects-specific embedding rather than CLAP [S7, S36].

**Speculative (no evidence either way)**
- That listeners prefer auto-EQ'd **finished masters** over the originals. Every positive result involves raw or damaged input [S4, S5]. For EQ "fixes" on near-finished material, listeners found no significant gain [S24].
- That any learned predictor can pick the better of two EQ candidates (RO2 deep-dive).
- That mid-song EQ changes are preferred, or even go unnoticed (RO4).

**Biggest risks**
1. **Homogenisation against faithfulness.** A target is an industry average [S1]. Pulling each master toward it overrides intentional tonal choices. The Diff-MST authors flag "homogenization" themselves [S9]. A fixed average target lost even on damaged input [S5].
2. **Proxy failure.** Optimising against an aesthetics model invites reward hacking [S27] and diversity collapse [S26]. Audiobox cannot hear above 8 kHz or stereo [S18].
3. **Small true effects.** EQ differences are "stylistic or difficult to notice" [S24]. A one-bit "better / not" signal will be noisy, and any A/B test must be loudness-matched. Mockenhaupt normalised all stimuli to −23 LUFS [S4]; the product's loudness-neutral gain already covers this.
4. **Weight provenance.** FXencoder was trained on MUSDB18 [S8] and All-In-One on Harmonix [S33]. Their weight licences are unstated; DeepAFx-ST's are under the Adobe Research License [S6]. This matters less for an OSS or personal project, but it is still a flag for RO8.

**Recommendation (for synthesis; recommended option first).** **Recommended: a faithful-first, static-per-track suggestion.**
- By default, apply no correction.
- When a theme is on, compute *one* bounded Tone offset per track. Derive it from spectrum-versus-theme-references and an embedding distance, regularised by the theme prior.
  - Inference: bound it at something like ±3 dB, the range one SongEval predictor uses as label-keeping training augmentation [S29]. The exact bound is for RO4/RO7.
- Treat the user's "better / not" as the real objective.
- Use Audiobox only as an optional gate, after the planned probe.
- Leave mid-song changes off until track B's RO4 evidence and our own test (RO12) justify them.

**Alternative:** an optimiser in the ST-ITO style that searches for the setting a critic scores highest, per track or per section. Not recommended: there is no valid critic (RO2), and it is the costliest option, at about 1 minute per transfer in the paper [S7].

---

## Answers per RO

| RO | Answer | Confidence | Key sources |
|---|---|---|---|
| RO1 | Reliably sensed ahead of play: long-term spectrum (whole-track or per-section), section boundaries and labels, instrument/effects embeddings, and a coarse production-quality score. The only feature with preference evidence for predicting a correction is **deviation from a content-conditioned target** (instrument class), and only for raw tracks. Genre and era targets are measured but untested for preference. | Med (sensing) / Low (prediction of preference) | S1, S4, S15, S33, S34, S18 |
| RO2 | No automatic objective is shown to track listener preference for EQ changes on the same track. Target distance works for raw or damaged audio. Audiobox Aesthetics is unvalidated for this and structurally unsuited (16 kHz mono, between-clip training, hackable). Coarse gate at most. | **High** that no evidence exists (within this search); Med on unsuitability | S18, S23, S24, S27, S29, S5 |
| RO3 | Mature policies output smooth target-difference curves or 4–6-band PEQs, offline and static per track. Preference wins over the original exist only for raw tracks (57.2% vs 28.8%, n = 26) and damaged input (60–4, n = 8). None for finished masters. Style-transfer evidence is similarity only. | High (the pattern) / Low (finished-master benefit) | S4, S5, S7, S8, S10, S11, S15, S24 |
| RO5 (emb.) | Represent a theme as curated reference recordings plus an effects-specific embedding (AFx-Rep, FXencoder, RelFx), regularised by a prior over Tone settings. CLAP and text are weak for EQ. | Med | S6, S7, S36, S37, S16 |
| RO4 (note) | Unexplored in the literature. All systems are static. | Med (absence) | S9, S15, S33 |

## Gaps

1. No listening test of automatic EQ on **finished commercial masters** against the untouched original. This is the decisive question, and the product will have to test it itself (RO12).
2. No test of whether Audiobox or any aesthetics predictor responds to ±3–5 dB tonal changes on the same track. Needs the "+D probe".
3. No per-genre or per-decade target numbers. Pestana and Elowsson were inaccessible (AES returned 403); I saw abstracts only.
4. No evidence on mid-song EQ changes (RO4), or on how much change goes unnoticed.
5. Inter-rater agreement for the Audiobox labels is not published.
6. Weight licences for FXencoder, AFx-Rep, All-In-One and ITO-Master are unstated.
7. Genre, mood and era classifiers were not searched (they belong with RO8).
8. Several 2025–26 items (RelFx, Fx-Encoder++, MEGAMI, the genre-shortcut paper) were read at abstract level only. Their numbers are not extracted.

---

## Search log

| # | Query / action | Source | Hits screened | Included |
|---|---|---|---|---|
| 1 | Ma Reiss Black intelligent equalization Yule-Walker target spectrum | WebSearch | 9 | 0 (S2 = U) |
| 2 | Pestana Ma Reiss spectral characteristics commercial recordings 1950–2010 | WebSearch + UCP repository | 10 | 1 (S1) |
| 3 | Steinmetz ST-ITO inference-time optimization | WebSearch | 9 | 2 (S7, S10) |
| 4 | DeepAFx-ST 2207.08759 | WebSearch | 10 | 1 (S6) |
| 5 | Direct: 2410.21233, 2211.02247, 2407.08889, 2506.16889, 2409.18847 (PDF/HTML) | arXiv | 5 | 5 (S7–S10, S16) |
| 6 | LLM2Fx predict audio effects parameters natural language | WebSearch | 10 | 1 (S17) |
| 7 | Matchering repo, wiki, FAQ, `defaults.py`, `match_frequencies.py` | GitHub | 5 pages | 1 (S15) |
| 8 | Direct: 2502.05139 (full PDF, 17 pp), 2402.00282 | arXiv | 2 | 2 (S18, S20) |
| 9 | MusicEval 2501.10811 | WebSearch + arXiv | 9 | 1 (S21) |
| 10 | All-In-One 2307.16425 + repo | arXiv, GitHub | 2 | 1 (S33) |
| 11 | audiobox aesthetics sensitivity equalization mastering reward 2025 | WebSearch (extended) | 9 | 3 (S23, S24, S25) |
| 12 | SonicMaster listening test | WebSearch | 9 | 0 new |
| 13 | Zheng Ma thesis target EQ listening test | WebSearch | 9 | 0 |
| 14 | Hafezi Reiss autonomous multitrack EQ masking | WebSearch | 9 | 2 (S4, S5); S47 = U |
| 15 | Elowsson Friberg LTAS percussion | WebSearch | 10 | 0 (S3 = U) |
| 16 | Wilson Fazenda perception of audio quality | WebSearch | 9 | 0 (S46 = U; 403) |
| 17 | Rämö Välimäki neural third-octave GEQ | WebSearch | 10 | 0 (S45 = U) |
| 18 | LTAS commercial music genre decade target slope | WebSearch | 10 | 0 |
| 19 | Pestana Reiss best-practices strategies PDF | WebSearch + QMRO | 10 | 0 (fetch failed twice) |
| 20 | "audiobox aesthetics" reward RL DPO GRPO | WebSearch (extended) | 9 | 3 (S26, S27, S28) |
| 21 | AudioMOS 2025 summary track 2 | WebSearch | 9 | 0 (not opened) |
| 22 | SongEval benchmark | WebSearch + arXiv | 10 | 1 (S22) |
| 23 | Meta audio aesthetics follow-up 2025–26 | WebSearch | 9 | 0 |
| 24 | quality predictor sensitivity perturbations EQ aesthetics | WebSearch (extended) | 9 | 1 (S29) |
| 25 | Aligning text-to-music evaluation with human preferences | WebSearch + arXiv | 9 | 1 (S30) |
| 26 | Mimilakis one-shot parametric style transfer EQ | WebSearch + Adobe | 9 | 1 (S13) |
| 27 | Nercessian neural PEQ matching differentiable biquads | WebSearch + DAFx | 10 | 1 (S14) |
| 28 | time-varying EQ finished master section preference | WebSearch (extended) | 9 | 1 (S43); S48 = U |
| 29 | **Snowball forward:** citations of Audiobox (2502.05139) | Semantic Scholar API | 100 (first page of >100) | 3 new (S31, S32, S41) |
| 30 | **Snowball forward:** citations of ST-ITO (2410.21233) | Semantic Scholar API | 29 | 5 new (S36–S40) |
| 31 | **Snowball forward:** citations of Mockenhaupt (2407.16691) | Semantic Scholar API | 5 | 1 new (S42) |
| 32 | **Snowball forward:** citations of All-In-One (2307.16425); MSAF repo | Semantic Scholar API, GitHub | 53 + 1 | 2 (S34, S35) |
| 33 | **Snowball backward:** reference lists of S6, S7, S4, S18 (read in full text) | Paper references | ≈150 | 5 (S8, S11, S12, S13, S14) |
| 34 | Licence checks: DeepAFx-ST, st-ito, ITO-Master, MixFXcloner, audiobox README + HF card, PAM | GitHub, HF | 7 | (licence columns) |

**Key papers snowballed per RO.** RO1: All-In-One, Mockenhaupt, Pestana (no API record). RO2: Audiobox, SonicMaster (citations via S4's snowball), PAM (backward via S18). RO3: DeepAFx-ST, ST-ITO, Mockenhaupt. RO5: ST-ITO, FXencoder (backward), DeepAFx-ST.

**Saturation.**
- **RO2 core question** (does a predictor track EQ preference on the same track?): **saturated.** Rounds 24 and 25 plus snowball 29 added no source that tests it. Caveat: only the first 100 citing titles were screened.
- **RO3 "auto-EQ preferred over a finished master":** **saturated.** Round 28 and snowball 31 added no such evidence.
- **RO1 and RO5:** stopped at the **cap**. Genre/mood classifiers were not searched, and several 2025–26 embedding papers were read only at abstract level.

---

## Evidence table (also the numbered source list)

`ID | RO | type | claim | numbers | method / output | code + weights licence | limitation | grade | URL`

| ID | RO | Type | Claim | Numbers | Method / output | Code + weights | Limitation | Grade | URL |
|---|---|---|---|---|---|---|---|---|---|
| S1 | 1, 2 | Conf. paper (AES 135) | Commercial recordings lean toward a target EQ curve | n/a (abstract only) | Long-term spectral averaging by year and genre | — | Numbers not seen | A (abstract only) | https://ciencia.ucp.pt/en/publications/spectral-characteristics-of-popular-commercial-recordings-1950-20/ |
| S2 | 3 | Conf. paper (AES 134) | Yule-Walker EQ toward target spectrum | — | — | — | Not opened | U | https://code.soundsoftware.ac.uk/publications/136 |
| S3 | 1 | Conf. paper (AES 142) | Genre LTAS differences mainly from percussion | — | HPSS + LTAS | — | Snippet only | U | https://aes2.org/publications/elibrary-page/?id=18638 |
| S4 | 1, 2, 3 | DAFx24 paper | Instrument-target auto-EQ preferred over original | n = 26, 35 trials, blind A/B + neutral, −23 LUFS: 57.2 / 28.8 / 14.0%; MAE 1.02 dB (−24%) | Classifier (35 classes, 79%), smoothed spectral difference, 4-band PEQ ±12 dB | — | Raw tracks; listeners from inside NI | A | https://arxiv.org/abs/2407.16691 |
| S5 | 2, 3, 5 | Preprint / AES AIMLA | Blind EQ restorer ≈ oracle; beats average target | n = 8, pairwise; 60–4, 51–13, 31–33 | Frozen CLAP + 0.34M head → 32 mel bands → zero-phase inverse filter | Not stated | Damaged input; small n; 7-s clips | A | https://arxiv.org/abs/2607.23846 |
| S6 | 3, 5 | JAES 2022 | Self-supervised effects style transfer; "adaptive presets" | No listening test; DSP RTF ≈ 0.003 on CPU | EfficientNet encoder, mean-pooled; 6-band PEQ + compressor | Adobe Research License (code + models) | Similarity metrics only | B | https://arxiv.org/abs/2207.08759 |
| S7 | 3, 5 | ISMIR 2024 | Inference-time search over any effect chain; AFx-Rep embedding | n = 23 similarity test; style classification 0.86 vs CLAP 0.56; ≈1 min vs ≈1 s | CMA-ES (population 64, ≤25 steps) | Code Apache-2.0; weights not stated | Similarity, not preference | A | https://arxiv.org/abs/2410.21233 |
| S8 | 3, 5 | ICASSP 2023 | Contrastive FXencoder + mixing-style converter | n = 11 engineers, similarity; output ≈ ground truth (n.s.) | Outputs audio (TCN) | Code MIT; weights on Drive (MUSDB18) | Stems; similarity | A | https://arxiv.org/abs/2211.02247 |
| S9 | 3, 4 | ISMIR 2024 | Differentiable mixing console style transfer | No listening test | Per-track 4-band PEQ, compressor, pan; master EQ + compressor | Code via project page | "Static mixing configurations"; flags homogenisation | B | https://arxiv.org/abs/2407.08889 |
| S10 | 3, 5 | Preprint 2025 | Mastering style transfer with embedding ITO | n = 10, similarity; AF loss 0.099 vs Matchering 0.160 | 46 parameters (6-band EQ … limiter) | LICENSE type not shown | Similarity; CLAP text guidance qualitative only | A (preprint) | https://arxiv.org/abs/2506.16889 |
| S11 | 1, 3 | ISMIR 2022 | Automix from wet data via effects normalisation | n = 14 pros; ≈ human mixes (PV, Excitement); Clarity p = 0.008 | EQ normalised to stem-type average (Savitzky–Golay, zero-phase FIR) | Code via project page | Mixing from stems | A | https://arxiv.org/abs/2208.11428 |
| S12 | 3 | ICASSP 2022 | End-to-end remastering to a reference | Listening test (numbers not seen) | Audio output, adversarial | — | Abstract only | A (abstract only) | https://arxiv.org/abs/2202.08520 |
| S13 | 3 | ICASSP 2020 | One-shot 4-band EQ style transfer | No test mentioned | Parameter prediction | — | Abstract only | B | https://research.adobe.com/publication/one-shot-parametric-audio-production-style-transfer-with-application-to-frequency-equalization |
| S14 | 3 | DAFx 2020 | Spectral loss via differentiable biquads beats parameter loss | — | PEQ matching network | — | Abstract only | B | https://dafx.de/paper-archive/details/lpNI_8szg2jo_eJO1RnKxw |
| S15 | 1, 3, 4 | Code + docs | One static zero-phase FIR per mid/side, from the loudest pieces; LOWESS-smoothed | FFT 4096; LOWESS frac 0.0375 | Reference matching + Hyrax limiter | **GPL-3.0** | No peer-reviewed listening test | C | https://github.com/sergree/matchering |
| S16 | 3, 5 | ICASSP 2025 | CLAP-guided EQ/reverb from text | n = 167, 924 ratings; EQ positive 48.3 / 45.5% vs random 22.2% | 6-band PEQ, 600 Adam iterations | Code via project page | Text UI (out of scope) | A | https://arxiv.org/abs/2409.18847 |
| S17 | 5 | WASPAA 2025 | LLM predicts EQ parameters zero-shot | MMD 0.22 (GPT-4o) vs 0.55 (Text2FX); no listening test | JSON parameters | Not stated | Text UI | B | https://arxiv.org/abs/2505.20770 |
| S18 | 1, 2 | Preprint (Meta) 2025 | 4-axis aesthetics predictor | 97k clips, 158 raters × 3 ratings; music PQ r = 0.887 (AES-Natural), 0.587 (PAM-music) | WavLM-style, **16 kHz mono**, 10-s windows | See S19 | No processing/EQ tests; no inter-rater agreement | A (preprint; across-clip only) | https://arxiv.org/abs/2502.05139 |
| S19 | 2, 8 | Repo + model card | Licence and usage | ≈0.1B parameters | CLI with `start_time`/`end_time` | CC-BY 4.0 (majority) + MIT parts; weights not separately stated | — | C | https://github.com/facebookresearch/audiobox-aesthetics ; https://huggingface.co/facebook/audiobox-aesthetics |
| S20 | 2 | Preprint 2024 | Prompted audio-language model quality metric | Text-to-music overall-quality PCC 0.33–0.69 | Text-prompt similarity | Code MIT | No EQ in distortion tests | A (preprint) | https://arxiv.org/abs/2402.00282 |
| S21 | 2 | ICASSP 2025 | Expert MOS dataset for generated music | 2,748 clips, 14 experts, 13,740 ratings | CLAP-based MOS predictor | — | Generated music only | B | https://arxiv.org/abs/2501.10811 |
| S22 | 2 | Preprint 2025 | Song aesthetics benchmark | 2,399 songs, 16 annotators, 5 dimensions | — | — | No production dimension | B | https://arxiv.org/abs/2505.10793 |
| S23 | 2 | Preprint 2025 | Audiobox axes vs human pairwise preferences | PQ fidelity accuracy 59.1% (Spearman 0.18) on 1,889 pairs | — | — | Text-to-music systems, not EQ | A (preprint) | https://arxiv.org/abs/2504.21815 |
| S24 | 2, 3 | Preprint / ICML 2026 | Generative restoration incl. 10 EQ degradations | n = 12: EQ the only n.s. category; n = 20: 180 of 200; PQ 7.03 → 7.71 | Rectified flow, regenerates audio | Release "upon acceptance" | Not faithful (regenerates) | A | https://arxiv.org/abs/2508.03448 |
| S25 | 2 | Vendor blog 2026 | Audiobox insensitive to fidelity; gender bias | Qualitative | Informal tests | — | Non-peer, vendor | D | https://cyanite.ai/2026/02/12/meta-audiobox-aesthetics-review/ |
| S26 | 2 | Preprint 2025 | Audiobox as RL reward (symbolic music) | n = 14 preliminary; diversity collapse | RL | — | Generative domain | A (preprint) | https://arxiv.org/abs/2504.16839 |
| S27 | 2 | Preprint 2026 | Audiobox-only DPO = reward hacking | +0.584 Audiobox, −0.019 CLAP, −0.053 SongEval | DPO on MusicGen-small | — | No human test for that run | B | https://arxiv.org/abs/2610.03589 |
| S28 | 2 | Preprint 2026 | Critique-based song reward model | Music Arena 71.35% | — | — | Generative domain | B | https://arxiv.org/abs/2608.11755 |
| S29 | 2 | Preprint 2025 | SongEval predictor uses ±3 dB 7-band EQ augmentation | p = 0.3 | MuQ/MusicFM encoders | — | Implies EQ invariance (inference) | B | https://arxiv.org/abs/2511.18869 |
| S30 | 2 | ISMIR 2025 | Text-to-music metrics vs preferences; MAD | MAD τ = 0.62 vs FAD 0.14 | Distribution metric | — | Noise is the only fidelity test | A | https://arxiv.org/abs/2503.16669 |
| S31 | 2 | Preprint 2026 | SongEval has genre shortcut (overrates pop) | Numbers not seen | — | — | Abstract only | B | https://arxiv.org/abs/2607.13903 |
| S32 | 2 | Preprint 2026 | MOS predictors learn dataset signatures | Numbers not seen | Domain-adversarial training | — | Abstract only | B | https://arxiv.org/abs/2603.16201 |
| S33 | 1, 4 | WASPAA 2023 + repo | Beats + 10 functional labels | 10 songs / 73 s on an RTX 4090 | Demucs + NATTEN | Code MIT; weights not stated (Harmonix) | No processing uses found | B / C | https://arxiv.org/abs/2307.16425 ; https://github.com/mir-aidj/all-in-one |
| S34 | 1 | Preprint 2025 | Best strict boundary score; 14k-song DB | HR.5F best on SongFormBench | — | "Open-sourced", licence not stated | Own benchmark | B | https://arxiv.org/abs/2510.02797 |
| S35 | 1 | Repo | Music structure framework | — | Boundary and label algorithms | MIT | Older methods | C | https://github.com/urinieto/msaf |
| S36 | 5 | ISMIR 2026 preprint | Relative effects embedding without dry references | Numbers not seen | Siamese + cross-attention | Project page | Abstract only | B | https://arxiv.org/abs/2608.10573 |
| S37 | 5 | Preprint 2025 | Gaussian prior (MAP) for ITO | Parameter MSE −33%; n = 16 favour | Prior from preset dataset | — | Vocals; numbers partial | A (preprint) | https://arxiv.org/abs/2505.11315 |
| S38 | 3 | ICASSP 2026 preprint | Generative effects-embedding automix | "Approaching human-level" (no numbers) | Per-track embeddings | — | Abstract only | A (abstract only) | https://arxiv.org/abs/2511.08040 |
| S39 | 5 | ISMIR 2025 | Per-instrument effects embeddings from mixtures | Numbers not seen | Contrastive + query extractor | — | Abstract only | B | https://arxiv.org/abs/2507.02273 |
| S40 | 5 | Preprint 2026 | Transformation vs processed-audio embeddings | Numbers not seen | — | — | Abstract only | B | https://arxiv.org/abs/2608.28127 |
| S41 | 3 | Preprint 2026 | Real-time music enhancement; blanket enhancement can hurt | No ms figures | Causal networks | — | Degraded input | B | https://arxiv.org/abs/2607.12872 |
| S42 | 5 | Preprint 2026 (cs.HC) | Scoped reference-listening comparison | 12 musicians; 9 of 10 differences had partial expert support | Features + AI guidance | — | Production tool, not playback | A (preprint) | https://arxiv.org/abs/2609.39963 |
| S43 | 5, 6 | Preprint 2026 | Listener variability in EQ for the same prompt | Numbers not seen | LLM distributional EQ | — | Text UI | B | https://arxiv.org/abs/2601.09448 |
| S44 | — | Tool | Citation graphs for snowballing | — | Semantic Scholar Graph API | — | — | — | https://api.semanticscholar.org/graph/v1/paper/arXiv:2410.21233/citations |
| S45 | 3 | DAFx 2019 | Neural third-octave GEQ gain design | — | — | — | Snippet only | U | https://dafx.de/paper-archive/details/LjIjfHTZj3NTbKcGFC8R8g |
| S46 | 2 | JAES 2016 | Quality ≠ liking; quality tied to loudness/DRC | — | — | — | 403; snippet only | U | https://salford-repository.worktribe.com/output/1407562/perception-of-audio-quality-in-productions-of-popular-music |
| S47 | 3 | JAES 2015 | Masking-reduction multitrack EQ | — | — | — | Not opened | U | https://aes2.org/publications/elibrary-page/?id=17637 |
| S48 | 6, 11 | US patent | EQ preference learning (Pardo group) | — | — | — | Not opened (for tracks B and F) | U | https://patents.google.com/patent/US8565908 |
| S49 | 3 | Video review | Matchering ranked 3rd of 12 in a 472-entry test | — | — | — | Cited by the repo; video not opened | U | https://github.com/sergree/matchering |
