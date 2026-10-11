# Brief C: Market and positioning (RO10) + what shipped "AI" is allowed to control (RO7, market half)

*Track C · 2026-10-10 · competitive-analyst · follows `00-research-protocol.md`*

**Grading used** (per the coordinator): A = peer-reviewed + listener/measurement evidence; B = patent, or source code / an official technical artifact; C = vendor manual, help page, or white paper; D = marketing, press release, review, forum, or Product Hunt; U = not opened this session (search-snippet only, or the page was blocked or empty). A U claim is never stated as fact. Every in-text tag `[M#]` points to a row of the evidence table in section 3, which doubles as the numbered source list.

**Scope note.** I didn't repeat the existing EQ UI study. Hearing-test and audiogram products are tagged *adjacent* and covered only briefly. I tested nothing hands-on, so every claim here is documentary.

---

## 0. TL;DR

1. **Nobody I could document ships the full combination in a music player:** read-ahead (whole-track) analysis, content-aware EQ/tone, preference learning from in-use feedback, and theme steering. The gap is real but closing. **EQK** (Mac, launched July 2026, ₹699 lifetime) is the closest direct competitor. It does per-song content-adaptive EQ ("by moment, section, or one static curve"), keeps per-song memory, and claims taste adaptation. But it is causal (it learns on the first play and applies on the second), has no theme control and no published bounds, and its bypass wasn't level-matched at 3.0. Its own maker admits "the eq could appear to be doing too much". [M56–M58, D]
2. **The best documented consumer precedent for "steer to a theme, and leave good content alone" is Dolby's Intelligent Equalizer** (Windows PCs and phones, OEM-bundled). It continuously compares the content's spectral balance to a user-chosen tone preset and moves only toward it: "If the audio already has enough bass… leaves the bass alone", and "Older recordings are instantly 'remastered'… modern recordings are left unprocessed" [M29, C]. Its patent family adds a content classifier with confidence-weighted EQ amount, per-genre/instrument "music clusters", and asymmetric slow-rise/fast-fall smoothing with hold timers [M30, B].
3. **The closest UI precedent for AdaptiveSound's Tone macros is a pro plugin, sonible learn:EQ (2025).** It has Intensity (scales the learned curve), three Styles (Warm / Neutral / Bright), a Dynamic knob (0 = static; raise it for real-time adaptation), and up to six labelled Tone Sliders ("Body", "Clarity", "Air"…). There's no preference learning and no player [M3, C]. smart:EQ 4 uses the same pattern with Impact (which can go negative), Smoothing, Adaptive (0 = static), and genre "Mix" profiles [M1, C].
4. **Preference learning ships only as a one-time onboarding test that outputs a static curve.** Examples: LG AI Sound Wizard (2025 TVs; four versions of a clip, pick 1–2, several rounds) [M25, D], Sonarworks SoundID (two-way A/B with a "no difference" option) [M45, M46, D], Sony "Find Your Equalizer" [M42, C], and Sennheiser "Sound Check" [M43, M44, D]. **None learns continuously from "better / not" feedback on a content-adaptive EQ.** The only documented "learn from the user over time" mechanism is a Sony patent: genre-based EQ biased by the user's history of manual tweaks [M59, B]. That patent belongs to the IP track (RO11).
5. **Read-ahead analysis exists in a player, but not for EQ.** Apple Music AutoMix analyses key and tempo to time-stretch, beat-match, and trim transitions [M37, C; M39, D]. Its loudest complaint is that it **alters the timeline**, "chopping the last 30 seconds off a song" and skipping verses [M41, D]. Offline whole-file analysis is standard in mastering services (Matchering: one static FIR from whole-track averages [M20, B]), but not in listening.
6. **What users reject, consistently:** drift (Ozone's assistant gets "even brighter" when re-run [M6, D]), over-processing ("over-EQ'd" [M58]), mid-song changes that "second-guess" a careful master [M58], loudness bias ("learning volume and calling it taste" [M58]; SoundID's toggle changes level [M45]), wrong automatic classification (Ozone genre pick "hit and miss" [M7]), and automation that is "worse than no DSP" when wrong [M53, D].
7. **Authority (RO7):** consumer listening products confine their "AI" to **EQ/tone**, or (on TVs) to **dialogue, surround up-mix and volume**, almost always with **on/off as the only control**. Full-chain authority (EQ + dynamics + width + loudness) appears only in creator mastering tools, where the user audits a render. There, a strength control, a style choice and a **gain-matched bypass** are standard [M5, M7, M18, M21].

---

## 1. Findings by RO

### RO10: Market and positioning

#### RO10.a Content analysis that sets EQ/tone automatically

**Pro/creator, learn-then-apply (static unless the user opts into adaptation).**
- **sonible smart:EQ 4.** It "learns" from at least about 6 s of active audio. The manual says the minimum is ~6 s on p.8 and ~10 s on p.7. The smart:filter then applies automatically. A longer maximum learning time and a "Get result" button are available. Profiles include Universal (the default), instrument profiles, 12 genre **Mix** profiles (Acoustic … Rock), and a **Reference** profile built from an audio file. Controls are Impact (strength; negative values *increase* spectral irregularity), Width, Smoothing, and a frequency-weighting curve. With **Adaptive > 0**, the plugin "continuously adapts the computed smart:filter to the input" for consistency on heterogeneous material. The output section has automatic gain compensation [M1, C]. €129 (on sale €79) [M2, D].
- **sonible learn:EQ** (v1.0, manual 2025-08). Profile → Learn → a "content-aware EQ curve". Controls are **Intensity** ("strength of the corrective EQ curve"), **Styles Warm/Neutral/Bright**, **Dynamic** (the curve "respond[s] in real time to changes in the input"; described as "more transparent and musical" on time-varying signals), up to six **Tone Sliders** named by tonal character, and *manual* Out Gain "to match loudness". You can relearn on a different section [M3, C].
- **iZotope Ozone Master Assistant.** It auditions a section (Ozone 12: an Analysis Time slider of up to 60 s) and proposes a whole chain. Ozone 10 onward adds Stabilizer, Impact and Imager to the chain; Ozone 10 picked one of 10 genres, which reviewers found "fairly hit and miss" [M7, D]. Ozone 12 has a Custom flow (pick modules, loudness target, Maximizer intensity) [M5, D] and "25 new genre targets" [M4, D]. Users report that the assistant leans bright and that re-running it gets "even brighter" [M6, D].
- **iZotope Neutron (Mix Assistant + Sculptor).** Relearn → a target curve from a Target Library. A **Tone Match** slider "pushes your audio towards or pulls it away from" the target and is linked to Sculptor's Amount and Pre-EQ. Sculptor is a per-band "army of compressors and EQs" with Dry/Wet, Tone and Speed [M10, D].
- **FabFilter Pro-Q 4 EQ Match.** The spectrum "averages over time" (about 30 s). It "automatically calculates how many and what kind of EQ bands" it needs, and the bands are then **static** and editable. The only control is a detail (band-count) slider; there is **no amount control** [M14, C].
- **Matchering 2** (GPL-3.0, open source). It matches RMS, frequency response, peak and stereo width to a reference [M19, B]. The code builds **one static linear-phase FIR per mid/side channel** from the average spectra of the loudest pieces (reference/target ratio, LOWESS-smoothed on a log-frequency grid, Hann-windowed) and convolves the whole track [M20, B]. It is the only product whose mechanism I verified in code.
- **LANDR** (cloud). AI mastering with styles **Warm / Balanced / Open** (Tonic engine), Volume Matching, saved "Mastering Preferences" [M18, D], and up to three reference tracks [M17, D]. The intensity Lo/Med/Hi and the micro-genre-detection claims come from third-party pages I didn't open, so they are [U].
- **Waves Online Mastering** (cloud). It was "modelled" with ML on the engineer Piper Payne. Controls are Style (Precise / Organic / Elevated), Tone (Depth / Presence buttons), a reference track, and a loudness-compensated preview. The review complains of no EQ display, no loudness target, no width control, **no control over how much the reference influences the result**, and masters "around −7 LUFS". $2.99–$5.99 per track [M21, D].
- **Waves Curves AQ** (plugin). "Learn" creates five generated "Spectral Targets". Modes are **dynamic, static or hybrid**, with boost/cut intensity (global or per band), Smart Tilt, Offset and a sidechain. $65 introductory, $155 later. The source is a promotional, untested write-up [M22, D].
- **Mastering The Mix BASSROOM.** It **suggests** low-end EQ targets and doesn't apply them. Targets update in real time, with an "Integrated" (whole track) and a "Short-Term" (last 3 s) reading. Presets come from analysing "the best mixes in various genres", and you can use up to 20 reference tracks. Its algorithm "accounts for differences in loudness" [M16, C].

**Pro/creator, continuous real-time "perceptual/adaptive" EQ (causal, fast).**
- **Soundtheory Gullfoss.** A perceptual model of masking. Controls are Recover, Tame, Bias, Brighten and Boost (a level-dependent, loudness-preserving tonal control) [M11, D]. The vendor-partner article claims it changes its response "more than 300 times per second", and frequency-range limiters can restrict it [M12, D]. The review warns that Recover can **raise noise** in noisy material. £139 / $199 [M11, D].
- **oeksound soothe2.** It detects resonances and applies reduction automatically. The EQ nodes are a *sensitivity* curve. Attack and release are frequency-dependent. Other controls are Depth, Sharpness, Selectivity, Soft/Hard mode and sidechain [M13, C].
- **Ozone Stabilizer.** Shape mode "gently massage[s] your audio in real-time" toward a target curve, and Cut mode notches resonances. Controls are Amount, Speed, Smoothing, Sensitivity, per-band Low/Mid/High amounts, and Tame Transients (on/off). In Ozone 10 you couldn't run both modes at once and couldn't import your own targets [M7, D]. **Ozone Clarity** (11) works in real time above 300 Hz, nudging toward pink noise, with Amount, Attack, Release and Tilt [M8, D].
- **Pro-Q 4 spectral dynamics** works per frequency inside a band, with automatic threshold, attack and release [M15, C].

**Consumer TV / OS / phone (causal; marketing-level detail except Dolby).**
- **Dolby Intelligent Equalizer** (PC Entertainment Experience v4). It is "continuously monitoring the spectral balance… comparing it to a desired tone, and dynamically adjusting an equalization filter". The user "simply select[s] a preset defining the desired relative balance". It is part of a suite that also levels loudness (Volume Leveler, which uses "Auditory Scene Analysis" so loudness is "not adjusted at inappropriate moments… such as during a naturally decaying note"), enhances dialogue, up-mixes and virtualises surround, and **boosts level "by as much as 12 dB"** behind a look-ahead limiter [M29, C]. Patent US9621124B2 (Dolby; priority 2013) [M30, B] adds:
  - a real-time classifier (speech / short-term music / background / noise; contexts movie / long-term music / game / VoIP) with 0–1 confidences;
  - an **EQ level, the weight of the EQ gains**, adjusted "continuous[ly]… rather than abrupt or discrete";
  - smoothing time constants chosen per transition type: a large τ for speech→music, a small τ for music→speech, slow rise and fast fall;
  - a hold timer before changing type;
  - a low EQ level on "music pieces with dominant sources";
  - per-cluster profiles (genre, instrument, rhythm, tempo, timbre) with hard or soft blending;
  - EQ disabled for movie and game contexts.
- **LG AI Sound Pro.** "Utilizes… deep learning technology to provide optimized sound… based on the genre of the video", on the TV speaker or Sound Share only [M23, C]. 2025–26 marketing adds AI Object Remastering, which "extracts dialogue and other distinct audio elements" and rebalances them, and says features must be enabled in the Sound Mode menu [M24, D]. Virtual 11.1.2 up-mix [M26, D].
- **Samsung Adaptive Sound / Sound+ / Sound Pro.** "Provides optimized sound quality by analyzing the viewing space and the acoustic components of the content". It works on the TV speaker only and is enabled only through the Intelligent Mode toggle. Active Voice Amplifier reacts to ambient noise, and Adaptive Volume learns from the user's volume history [M27, C]. Samsung says no data is saved during the analysis (reported second-hand) [M28, D].
- **Huawei.** Histen "Auto: Automatically identifies what you are playing and intelligently applies sound effects" (headset only) [M31, C]. Dolby Atmos on Huawei phones "intelligently identifies audio content and automatically adjusts the audio quality" [M32, C]. Neither page says what is adjusted.
- **QQ Music × Qualcomm.** An on-device "AI model" for "audio detail restoration" (restoration, not EQ steering) for paying Super VIP members [M33, D].
- **DTS Sound Unbound.** No content-adaptive EQ is described; it's positioned for gaming spatial audio [M34, D].
- **Negative results** (one query each, nothing opened supports them): Windows 11 has no AI music EQ (its AI audio is call-focused) [U]; Sony Bravia "Voice Zoom 3" is AI dialogue level (page 403) [U]; Samsung Galaxy "Dolby Atmos Auto" mode reportedly picks "Voice" for music (forum 403) [U]; Xiaomi's equalizer is manual [U].

**Headphones / Apple.**
- **AirPods Adaptive EQ is not content-aware.** It adjusts "to the fit and seal… by measuring the sound signal delivered to a user and adjusting the low and mid-frequencies in real time" [M35, D]. iOS 27 adds a *manual* Custom EQ (highs/mids/lows) with preview and revert on H2 models [M36, D]. **Bose CustomTune** is the same idea: a chime plus in-ear mics characterise the ear canal [M48, D]. Both are adjacent.
- **Apple Music on Mac.** Sound Enhancer is a single strength slider with no stated content analysis. **AutoMix** "transitions tracks at the right moment based on analysis of the key and tempo" [M37, C]. Apple's wording via 9to5Mac is "Using AI to analyze audio features… time stretching and beat matching"; it's on by default, with AutoMix / Crossfade / Off options [M39, D]. iOS 27 "can remix portions of a song's intro or outro, repeat sections" [M40, D]. Whether it works only on catalogue tracks and where the analysis runs is [U]. The Music app also lets you **pin an EQ preset to an individual song** [M38, C].

**Music players and system EQs.**
- **EQK** (Mac; kuja.dev). "Optional on-device AI Tune… gentle adjustments during a song, by moment, section, or one static curve"; "Completed song profiles can be remembered; manual controls remain available"; "does not upload audio". It also has a 10-band EQ per app, 3,985 AutoEq headphone profiles ("Measured correction stays separate from your custom EQ"), and a local FLAC/ALAC/WAV/MP3 library. ₹699 lifetime, 14-day trial, macOS 14.6+ [M56, D]. The maker says the curve is "refreshed every second to twice a second", it holds up to 1,000 songs, "learns it side-by-side to apply a more accurate EQ on the second play", and it accounts for "headphones + bad source material + user preference". The maker also admits: "sometimes, the eq could appear to be doing too much", "not all genres are well accounted for", "Some songs may appear over-EQ'd" [M58, D]. The launch listing (3.0 on 2026-07-29) claims Apple Intelligence updates "decision weights" [M57, D; mechanism unverified].
- **Rule-based per-track EQ (not AI).** Poweramp assigns presets by output, song or album [M49, D]. Its forum says genre-tag rules exist and that it does no live-analysis EQ, but the forum was 403, so [U]. Apple Music assigns per song [M38, C].
- **Manual tone macros (precedent for the Tone UI, not adaptive).** HiBy MSEB has 10 named dimensions (Overall Temperature, Bass Extension, Note Thickness, Voice, Sibilance, Air…); "Toggle on and drag sliders to adjust" [M50, C].
- **No adaptive EQ found** in Boom 3D (31-band EQ, genre presets, intensity sliders) [M51, D] or Spotify (manual presets and drag) [M52, C]. Nor did I find any in Roon: community requests from 2021 and 2026 got no staff reply [M53, M54, D]. Audirvana, eqMac, Neutron Player, Wavelet, FiiO, Tidal, Qobuz and Amazon Music turned up nothing in search snippets [U]. Neutron and Wavelet list AutoEq *headphone* presets, and FiiO Control added "AUTO EQ" in 2026-01; all three are [U] and probably headphone correction, not content analysis.
- **Long-tail "AI EQ" mobile apps** ("AI Equalizer / Auto Equalizer", "AutoEQ: Smart Music Equalizer" with per-song presets via MediaSession that "learns from your manual changes") appeared only in snippets because their Play Store pages truncated [U].

#### RO10.b Personalisation from user feedback (not hearing tests)

| Product | Format | Output | Evidence |
|---|---|---|---|
| LG AI Sound Wizard (2025 TVs) | 4 versions of a clip; pick 1–2; repeat on new clips; demo toggle standard ↔ personal | static personal sound mode, tied to the LG account | M25 D, M24 D; "40 million sound profiles" (marketing) M26 D |
| Sonarworks SoundID → SoundID Listen | 2 versions with "slight variations in EQ balance"; pick 1st / 2nd / no difference; multiple rounds; ML; plus headphone model (350+) | static profile = headphone calibration + preference; Listen is on/off only, not editable | M45 D, M46 D; "8–12 questions" [U] |
| Sony Find Your Equalizer | "selecting sound while listening to music" | saved to EQ "Custom 2" | M42 C; "nine presets" [U] |
| Sennheiser Sound Check | "guided process", "short listening test"; requires login | custom EQ preset (many allowed) | M43 D, M44 D; exact A/B format [U] |
| EQK | claims adaptation to "user preference"; no documented feedback UI | per-song profiles | M58 D (mechanism unverified) |
| Sony patent US10855241B2 | learns from the user's *manual* EQ edits per genre (e.g. biases a 7 dB rule toward the user's habitual 10 dB) | real-time genre EQ + user bias | M59 B (not known to have shipped) |
| Roon users (request) | "suggest 10 diverse tracks… system learns" my taste | not built | M53 D |

**Adjacent (hearing-test based, out of scope):** Samsung Adapt Sound (beeps; yes/no) [M47, D]. Nothing (Mimi → Audiodo), Soundcore HearID and JBL Personi-Fi (2.0/3.0) pages were blocked or empty, so [U].

#### RO10.c Steering with a style / theme / target

- **Small named style sets:** learn:EQ Warm / Neutral / Bright [M3]; LANDR Warm / Balanced / Open [M18]; Waves Precise / Organic / Elevated plus Depth / Presence [M21]. Dolby's IEQ presets are "Balanced, Open, Focused, Bright, Rich, Warm" according to a review that returned a 502, so [U].
- **Genre target libraries:** smart:EQ 4 has 12 genre Mix profiles [M1]. Ozone 12 Stabilizer has "25 new genre targets" [M4], against 10 in Ozone 10 [M7]. Tonal Balance Control 2 has "30+ genre and subgenre curves… built from analyzing hundreds of professional masters", custom targets captured from *any system audio*, and a "Target Blender" that mixes two targets [M9, D]. BASSROOM targets come from genre-best mixes [M16].
- **Reference-as-theme:** smart:EQ 4 Reference profile [M1], Neutron custom target [M10], Pro-Q 4 / Matchering / LANDR / Waves references [M14, M19, M17, M21].
- **Continuous theme in a consumer product:** only Dolby IEQ (the user-chosen tone target, content moved toward it) [M29]. LG and Samsung TVs expose no theme, only on/off [M23, M27].
- **Tilt-as-theme:** Ozone Clarity Tilt (brown ↔ white) [M8], Curves AQ Smart Tilt / Offset [M22], Gullfoss Brighten [M11].

#### RO10 comparison table

| Product | Category | Analyzes | Outputs | Time-varying? | User control | On-device? | Price | Complaints | Src (grade) |
|---|---|---|---|---|---|---|---|---|---|
| sonible smart:EQ 4 | pro plugin | ≥6–10 s of input vs profile (instrument / genre Mix / reference) | EQ curve ("smart:filter"); group unmasking | static after learning; continuous if Adaptive > 0 (rate unpublished) | profile, Impact (±), Width, Smoothing, Adaptive, weighting curve | yes | €129 (sale €79) | — (none opened) | M1 C, M2 D |
| sonible learn:EQ | pro plugin | learned section vs profile | corrective EQ + Tone Sliders | static; real-time if Dynamic > 0 | **Intensity, Style W/N/B, Dynamic**, 6 Tone Sliders, manual Out Gain | yes | ~$69 [U] | "starting point" [U] | M3 C |
| Ozone 12 Master Assistant | pro plugin | a section (≤60 s) | full chain (EQ, Stabilizer, Impact, Imager, Maximizer, Clarity) | chain is static; modules dynamic | genre target, modules on/off, loudness target, intensity; macros + gain-matched bypass | yes | Adv $499 / Std $219 / Elem $55 | too bright; re-runs brighter; LUFS target missed; genre pick hit-and-miss | M4 D, M5 D, M6 D, M7 D |
| Ozone Stabilizer / Clarity | pro plugin module | live spectrum vs genre target / pink noise | dynamic EQ; resonance cuts | real-time (Speed / attack-release) | Amount, Speed, Smoothing, Sensitivity, L/M/H; Clarity Tilt | yes | in Std/Adv | couldn't run Shape + Cut together; no custom targets (v10) | M7 D, M8 D |
| Neutron Mix Assistant / Sculptor | pro plugin | learned audio vs Target Library | target-matched per-band EQ + compression; width / exciter / punch macros | dynamic (Speed) | Tone Match, Dry/Wet, Speed | yes | — | — | M10 D |
| Gullfoss | pro plugin | perceptual masking model, live | dynamic EQ | real-time, ">300×/s" (vendor-partner claim) | Recover, Tame, Bias, Brighten, Boost, range limiters | yes | $199 | raises noise in noisy material; "takes figuring out" [U] | M11 D, M12 D |
| soothe2 | pro plugin | resonances, live | dynamic cuts only | real-time, frequency-dependent attack / release | Depth, Sharpness, Selectivity, mode, sensitivity curve | yes | — | — | M13 C |
| Pro-Q 4 EQ Match / spectral | pro plugin | ~30 s average vs reference | static bands / per-frequency dynamics | static / real-time | detail slider (no amount) / band range, density | yes | — | (old flow "un-FabFilter-like" [U]) | M14 C, M15 C |
| Waves Curves AQ | pro plugin | learned input | 5 generated spectral targets → EQ | dynamic / static / hybrid | intensity (global / per band), Smart Tilt, Offset | yes | $65 → $155 | untested claims | M22 D |
| BASSROOM | pro plugin | low end vs genre preset or ≤20 refs, loudness-aware | **suggested** band targets | targets update live (integrated or 3 s) | user applies | yes | — | — | M16 C |
| Matchering 2 | OSS mastering | whole-track loudest pieces vs reference | static M/S FIR + RMS + limiter + width | **static** (verified in code) | none (reference only) | yes (Python / Docker) | free, GPL-3.0 | depends on reference [U] | M19 B, M20 B |
| LANDR | cloud mastering | uploaded track (+ ≤3 refs) | rendered master | offline render | style W/B/O, intensity [U], refs, volume match | **cloud** | subscription | — | M17 D, M18 D |
| Waves Online Mastering | cloud mastering | uploaded track (+ ref) | rendered master | offline render | Style, Tone (Depth / Presence), ref | **cloud** | $2.99–5.99 / track | no EQ display, no loudness target, can't set reference influence, hot (−7 LUFS) | M21 D |
| Dolby Intelligent EQ (PCEE v4 / Dolby apps) | OS / OEM audio | live spectral balance vs chosen tone; content classifier (patent) | dynamic EQ toward target | continuous, smoothed (asymmetric τ, hold timer) | tone preset; advanced users edit presets | yes | OEM-bundled [U] | (Samsung Auto picks wrong mode [U]) | M29 C, M30 B |
| LG AI Sound Pro / Object Remastering | TV | genre of video; dialogue / effects extraction | "optimized sound", up-mix 11.1.2, voice remaster | real-time [D] | on/off via Sound Mode | yes | bundled | — | M23 C, M24 D, M26 D |
| Samsung Adaptive Sound Pro | TV | "acoustic components of content" + room | "optimized sound" | real-time [D] | Intelligent Mode on/off | yes | bundled | results vary with speakers | M27 C, M28 D |
| Huawei Histen Auto / Dolby Atmos | phone | "identifies what you are playing" | "sound effects" | unknown | mode select | yes | bundled | — | M31 C, M32 C |
| AirPods Adaptive EQ *(not content)* | earbuds | in-ear mic, fit / seal | low / mid EQ | real-time | none (iOS 27 adds manual Custom EQ) | yes | bundled | — | M35 D, M36 D |
| Apple AutoMix *(read-ahead precedent)* | player | key, tempo, audio features of adjacent tracks | transition (time-stretch, beat-match, trim; iOS 27 intro/outro remix) | per transition | AutoMix / Crossfade / Off | unknown [U] | Apple Music sub | cuts last ~30 s, skips verses | M37 C, M39 D, M40 D, M41 D |
| LG AI Sound Wizard *(A/B)* | TV | user picks among 4 versions × rounds | static personal mode | no | the test itself | yes (account-tied) | bundled | (first-look only) | M24 D, M25 D, M26 D |
| SoundID / SoundID Listen *(A/B)* | app + desktop | 2-AFC + "no difference", headphone model | static profile | no | on/off only | processing local; profile in cloud | ~$4.99/mo (2021) | inconsistent across headphones; level jump on toggle; can't edit | M45 D, M46 D |
| Sony FYE / Sennheiser Sound Check *(A/B-ish)* | headphone apps | user selections while listening | EQ preset | no | the test | yes | free | — | M42 C, M43 D, M44 D |
| **EQK** | **Mac system EQ + local player** | captured app audio per song | 10-band EQ curve per moment / section / static; per-song memory | **1–2 Hz refresh** (maker) or by section or static | mode, manual EQ, (level-matched bypass "coming") | yes | ₹699 lifetime | "doing too much", "over-EQ'd", "not all genres"; mid-song changes unwelcome; loudness bias risk | M56 D, M57 D, M58 D |
| Poweramp / Apple Music per-song EQ | players | tags / rules | preset per song / album / output | per track | manual assignment | yes | — | genre tags unreliable [U] | M49 D, M38 C |
| HiBy MSEB | player DSP | — (manual) | 10 tone dimensions | no | sliders | yes | free | — | M50 C |

#### Patterns that work (repeated across vendors; evidence is documentary, not efficacy)
1. **A strength knob that scales the learned correction**: Intensity [M3], Impact [M1], Tone Match [M10], Amount [M7, M8], intensity [M22]. In consumer products it is rare: Apple Sound Enhancer's slider [M37] and Dolby's leveling amount [M29].
2. **A small named style set (three is typical) plus genre or reference targets** [M3, M18, M21, M1, M4, M9].
3. **"Static by default, adaptive by opt-in"**: smart:EQ Adaptive and learn:EQ Dynamic both default to 0 in the manuals' screenshots [M1, M3]; EQK offers "one static curve" as a mode [M56].
4. **Move toward a target only where the content falls short ("leave good content alone")** [M29], plus confidence-weighted amount and asymmetric smoothing with hold timers [M30].
5. **Gain-matched compare**: Ozone Assistant View [M7], LANDR Volume Matching [M18], Waves loudness-compensation switch [M21]. EQK users explicitly demand it [M58].
6. **Keep measured correction separate from taste**: EQK [M56]; SoundID = headphone calibration + preference profile [M45].
7. **Suggest, don't impose**: BASSROOM [M16]; Pro-Q bands stay editable [M14]; learn:EQ Assisted ↔ Advanced [M3].
8. **Short A/B onboarding with an explicit "no difference" option** [M45], or 4-way "pick 1–2" [M25], and a before/after demo toggle at the end [M25].
9. **Per-song memory** [M38, M49, M56].

#### Patterns users reject
1. **Drift / compounding**: "run it through again and it will get even brighter… proves it's not making really intelligent decisions" [M6].
2. **Over-processing**: "Some songs may appear over-EQ'd"; "doing too much" [M58]. Gullfoss Recover lifts noise [M11].
3. **Second-guessing the master / moving mid-song**: "an adaptive curve is second-guessing them in real time"; mid-song changes "could be unpleasant" [M58].
4. **Loudness confounds**: "learning volume and calling it taste", with a demand to match within ~0.5 dB and show the offset [M58]; SoundID's toggle "seems louder" [M45]; Waves masters ~−7 LUFS [M21].
5. **Wrong classification**: genre pick "hit and miss" [M7]; Samsung Auto chooses Voice for music [U].
6. **Automation that touches the timeline**: AutoMix chopping outros and intros [M41].
7. **Opacity / no control**: can't set how much the reference influences the result, no EQ display [M21]; profile not editable [M45]; consumer TVs are on/off only [M23, M27].
8. **Interruption and the "worse than nothing" risk**: "Getting the DSP setting wrong sometimes is worse than no DSP"; automated DSP changes are "contrary to… uninterrupted listening" [M53].

#### The gap: is anyone doing read-ahead, content-aware, preference-learned, theme-steered EQ in a music player?

**No, not in any source I opened.** Each capability exists somewhere, but never all four together:

| Capability | Who has it | In a music player? |
|---|---|---|
| Read-ahead / non-causal whole-track analysis | Matchering, LANDR, Waves (offline mastering) [M20, M17, M21]; Apple AutoMix (for transitions only) [M37, M39] | **AutoMix only, and not for EQ** |
| Content-aware EQ/tone | Dolby IEQ [M29, M30], pro plugins, TVs [M23, M27], EQK [M56] | **EQK** (causal: learns on first play) |
| Preference learning from feedback | LG Sound Wizard [M25], SoundID [M45], Sony FYE [M42], Sennheiser [M43]: all one-time tests → static curve; Sony patent (manual edits) [M59] | **No**; EQK only claims it [M58] |
| Theme steering | learn:EQ styles [M3], genre targets [M1, M4, M9], Dolby tone presets [M29] | **No** (Dolby is OS-level and OEM-bundled) |

**Positioning implications** (my analysis, for the synthesis step):
- AdaptiveSound's structural edge is **non-causal read-ahead on local files**. It can decide a section's tone *before* that section plays and time any change to a section boundary, rather than reacting with a lag like the causal products (Dolby, TVs, Gullfoss, EQK on first play). That addresses the two biggest documented rejections, "moving mid-song" and "doing too much", if it's paired with Dolby-style "leave good masters alone" [M29] and static-by-default [M1, M3].
- The **"better / not" loop with a loudness-matched compare** directly answers the most specific user critique of the closest competitor ("learning volume and calling it taste") [M58]. AdaptiveSound already has loudness-neutral output gain (decision 26). That's a credible differentiator, *if* it's enforced in the compare.
- **Theme + Intensity over the 5 Tone macros** is a proven pro pattern [M3] that no consumer player exposes.
- **Threats:** EQK is on the same platform, cheap, and iterating fast (two launches in July 2026) [M57]. Apple has the analysis plumbing (AutoMix) [M39] and is adding user EQ to AirPods in iOS 27 [M36]. LG has normalised A/B personalisation on mass-market TVs [M25].

### RO7 (market half): what shipped "AI" is allowed to control, and the bounds it exposes

| Product | EQ / tone | Dialogue / vocal | Loudness / volume | Dynamics | Width / surround | Timeline | Bounds / strength exposed | Compare / bypass | Src |
|---|---|---|---|---|---|---|---|---|---|
| smart:EQ 4 | ✔ (smart:filter) | – | auto gain comp. (output) | – | M/S balance (manual) | – | Impact ±, Width, Smoothing, Adaptive, freq-weighting curve | A/B/C… states (8) | M1 |
| learn:EQ | ✔ | – | manual Out Gain | – | – | – | Intensity, Style, Dynamic, Tone Sliders | bypass | M3 |
| Ozone Master Assistant | ✔ | – | ✔ (Maximizer, loudness target) | ✔ (Impact, Stabilizer) | ✔ (Imager) | – | modules on/off, loudness target, intensity, macros | gain-matched bypass | M5, M7 |
| Neutron Mix Assistant | ✔ (Sculptor) | – | – | ✔ (per-band comp, Punch) | ✔ (Width) | – | Tone Match, Dry/Wet, Speed | — | M10 |
| Gullfoss | ✔ | – | Boost claims loudness preserved | – | – | – | 5 controls + freq-range limiters | — | M11, M12 |
| soothe2 | cuts only | – | – | (spectral) | – | – | Depth, Sharpness, Selectivity, attack / release, sensitivity curve | — | M13 |
| Pro-Q 4 EQ Match | ✔ static | – | – | – | – | – | detail slider; **no amount** | — | M14 |
| Curves AQ | ✔ | – | – | – | – | – | intensity (global / per band), Tilt, Offset | — | M22 |
| BASSROOM | suggests only | – | level-match hint | – | – | – | user applies | — | M16 |
| Matchering | ✔ static FIR | – | ✔ RMS | ✔ limiter | ✔ width | – | **none** | — | M19, M20 |
| LANDR | ✔ | – | ✔ | ✔ | ✔ [U] | – | style, intensity [U], refs | volume matching | M17, M18 |
| Waves Online Mastering | ✔ | – | ✔ (~−7 LUFS, no target) | ✔ | (not adjustable) | – | style, tone, ref (no influence knob) | loudness-comp. preview | M21 |
| Dolby PCEE suite | ✔ IEQ | ✔ Dialogue Enhancer | ✔ Leveler; **Maximizer +12 dB** | ✔ (limiter, multiband) | ✔ up-mix / virtualizer | – | preset; leveler amount; enhancer / virtualizer degree; patent: EQ weight 0–1, off for movie / game | — | M29, M30 |
| LG AI Sound Pro / Object Remastering | ✔ ("optimized") | ✔ | – | – | ✔ up-mix 11.1.2 | – | **on / off only** | — | M23, M24, M26 |
| Samsung Adaptive Sound Pro / AVA / Adaptive Volume | ✔ ("optimized") | ✔ (AVA vs noise) | ✔ (Adaptive Volume) | – | – | – | **on / off only** (Intelligent Mode) | — | M27 |
| Huawei Histen Auto | "sound effects" | ? | ? | ? | ? | – | mode only | — | M31 |
| AirPods Adaptive EQ | ✔ low / mid (fit) | – | – | – | – | – | none (manual Custom EQ coming) | — | M35, M36 |
| Apple Sound Enhancer | bass / treble | – | – | – | ✔ "wideness" | – | one slider | — | M37 |
| Apple AutoMix | – | – | (crossfade) | – | – | ✔ **time-stretch, beat-match, trim, remix** | on / off / crossfade | — | M37, M39, M40 |
| LG Sound Wizard / SoundID / Sony FYE / Sennheiser | ✔ static profile | (LG: dialogue emphasis) | – | – | – | – | test only; SoundID on / off | LG demo toggle | M25, M45, M42, M43 |
| EQK | ✔ 10-band | – | per-app trim (manual) | per-app limiter | – | – | mode (moment / section / static); **no published bounds** | bypass, not level-matched (fix "coming") | M56, M58 |

**Reading of the table.**
- In *listening* products, the AI's remit is overwhelmingly **EQ/tone only**. Loudness, dynamics and width are either left alone or owned by separately named, separately toggled processors (Dolby splits IEQ from the Leveler and the Maximizer [M29]).
- The one consumer AI that takes over the **timeline** (AutoMix) is also the one with the most visible backlash [M41].
- **Consumer bounds are almost never exposed** (on/off only) [M23, M27]. **Pro tools always expose a strength control** [M1, M3, M7, M10, M22]. The Dolby patent is the only document that describes bounding *as a continuous weight tied to classifier confidence* [M30].

### Inputs to other ROs (market-derived, low weight)
- **RO4 (changes within a song):** shipped listening products avoid audible movement in three ways. They default to static, adapting only by opt-in [M1, M3]. They smooth asymmetrically with hold timers [M30]. And they avoid adjusting "at inappropriate moments… such as during a naturally decaying note" [M29]. Fast real-time processors (Gullfoss >300/s [M12], soothe2 [M13]) are *corrective* tools for producers, not listening-taste tools. EQK's 1–2 Hz refresh draws "doing too much" complaints [M58].
- **RO5 (themes):** the market uses about 3 named styles, or 10–30 genre targets [M3, M18, M21, M4, M7, M9]. TBC's "Target Blender" (two-target interpolation) [M9] and Smart Tilt / Offset [M22] are precedents for continuous theme space.
- **RO6 (feedback):** shipped formats are 2-AFC plus "no difference" [M45] and 4-way "pick 1–2" [M25]. Loudness confounding is the top user-raised bias [M58, M45].
- **RO11 (IP):** flag Dolby US9621124B2 (classifier-confidence-weighted continuous EQ, genre / instrument clusters, transition-dependent τ) [M30] and Sony US10855241B2 (genre EQ + learning from manual adjustments, mid-song change on genre change, per-song stored genre) [M59] for the IP track.
- **RO12 (evaluation):** no vendor publishes listening-test efficacy data in any source I opened. LG's built-in "standard vs personalised" demo toggle [M25] and EQK's per-song memory [M56] hint at in-product keep/revert signals.

---

## 2. Answers per RO

| RO | Answer | Confidence | Key sources |
|---|---|---|---|
| **RO10.a** content → EQ | Widespread in pro tools (learn-then-static, or causal real-time). In consumer products: Dolby IEQ (documented mechanism), LG and Samsung TVs and Huawei phones (marketing-level, on/off). In players: only EQK (Mac, 2026). **No one uses non-causal read-ahead for EQ in a player.** | high for "exists"; med for "no read-ahead EQ in players" (absence of evidence; Asian OEM players not covered) | M1, M3, M7, M29, M30, M23, M27, M56, M58 |
| **RO10.b** feedback personalisation | Ships only as one-time A/B onboarding → static global curve (LG, SoundID, Sony, Sennheiser). No shipped continuous "better / not" learning on content-adaptive EQ. Prior art exists for learning from manual edits (Sony patent). | med-high | M25, M45, M46, M42, M43, M59, M58 |
| **RO10.c** theme steering | Standard in pro (3 styles or genre / reference targets + strength). In consumer: only Dolby tone presets. No player exposes theme + intensity. | high (pro); med (consumer) | M3, M1, M4, M9, M18, M21, M29 |
| **RO10** gap and positioning | Gap confirmed for the full combination. The closest competitor (EQK) is causal, theme-less, unbounded, and criticised for over-EQ, mid-song second-guessing and loudness bias. AdaptiveSound's read-ahead + loudness-neutral compare + theme / intensity + "leave good masters alone" addresses those documented rejections. Threats: EQK's iteration speed; Apple. | med | M56, M57, M58, M29, M3, M36, M39 |
| **RO7** (market) | Listening AIs are confined to EQ/tone (or, on TVs, dialogue / up-mix / volume as separate features). Full-chain authority appears only in offline mastering with user audit. Pro tools universally expose strength; consumer products rarely do. Timeline-touching automation (AutoMix) is the most criticised. **Implication:** limit authority to the Tone vector / EQ, bound it with an intensity knob and clamps, leave loudness to the existing BS.1770 normaliser and limiter, and never touch the timeline. | med | M29, M30, M23, M27, M37, M41, M1, M3, M7 |

---

## 3. Evidence table (= numbered sources)

`ID | RO(s) | type | claim | numbers | method / output | code + weights licence | limitation | grade | URL`

| ID | RO | type | claim | numbers | method / output | licence | limitation | grade | URL |
|---|---|---|---|---|---|---|---|---|---|
| M1 | 10, 7, 4, 5 | manual (JP) | smart:EQ 4 learns, then auto-applies the smart:filter; Adaptive > 0 = continuous adaptation; Impact ± / Width / Smoothing; genre Mix + Reference profiles; auto gain comp. | min ~6 s (p.8) / ~10 s (p.7); 12 genre Mix profiles; 8 states | profile-conditioned spectral balancing → EQ curve | proprietary | adaptation rate unpublished; manual translated by me | C | https://www.sonible.com/wp-content/uploads/2026/07/manual-smEQ4_JP.pdf |
| M2 | 10 | product page | smart:EQ 4 price, Adaptive option, three profile types | €129 (sale €79); 30-day demo | — | proprietary | marketing | D | https://www.sonible.com/smarteq4/ |
| M3 | 10, 7, 4, 5 | manual | learn:EQ: Intensity, Styles Warm / Neutral / Bright, Dynamic (real-time), ≤6 Tone Sliders (Body / Clarity / Air…), manual Out Gain "to match loudness" | v1.0.0; 5 bells + 2 shelves + 2 HP/LP | learn → content-aware EQ curve | proprietary | no efficacy data | C | https://www.sonible.com/wp-content/uploads/2025/08/sonible_manual-learnEQ.pdf |
| M4 | 10, 5 | product page | Stabilizer: "intelligent and adaptive mastering EQ" with 25 new genre targets; Std / Adv only | Adv $499 | — | proprietary | page gave little mechanism | D | https://www.izotope.com/en/products/ozone/features/stabilizer |
| M5 | 10, 7 | review (SOS, Dec 2025) | Ozone 12 Master Assistant auditions a section → chain; Custom flow; "won't rescue a poor mix" | ≤60 s analysis; Adv $499 / Std $219 / Elem $55 | assistant → module chain | proprietary | review | D | https://www.soundonsound.com/reviews/izotope-ozone-12-advanced?amp |
| M6 | 10 | forum (KVR) | Assistant boosts highs; re-runs get brighter; always Clarity; narrows stereo ~20–30%; LUFS target missed | anecdotal, n≈5 posters | — | — | anecdotal | D | https://www.kvraudio.com/forum/viewtopic.php?p=9252759 |
| M7 | 10, 7, 4 | review (MusicTech) | Ozone 10: Stabilizer Shape (real-time to target) / Cut; Amount, Speed, Smoothing, Sensitivity, L/M/H; no simultaneous modes, no import; Assistant genre pick "hit and miss"; gain-matched bypass | 10 genre presets + All-Purpose | dynamic EQ toward target | proprietary | Ozone 10 era | D | https://musictech.com/reviews/plug-ins/izotope-ozone-10-advanced-review/ |
| M8 | 10, 4 | review (SOS) | Ozone 11 Clarity: real-time, toward pink noise, > 300 Hz; Amount, attack / release, Tilt | — | dynamic tonal shaping | proprietary | review | D | https://www.soundonsound.com/reviews/izotope-ozone-11-advanced |
| M9 | 10, 5 | product page | TBC 2 targets "built from analyzing hundreds of professional masters"; 30+ curves; capture targets from system audio; Target Blender; built-in EQ | 30+ curves | target display + manual / dynamic EQ | proprietary | other pages say "thousands" [U] | D | https://www.izotope.com/en/products/tonal-balance-control-2/features/tonal-balance-curves |
| M10 | 10, 7 | article (Splice) | Neutron Mix Assistant target + Tone Match slider linked to Sculptor Amount / Pre-EQ; Sculptor = per-band comp + EQ | — | target-matching dynamic EQ | proprietary | describes Neutron 4 | D | https://splice.com/blog/how-to-mix-izotope-neutron |
| M11 | 10, 7 | review (SOS 2018) | Gullfoss perceptual model; Recover / Tame / Bias / Brighten / Boost; Recover raises noise | £139 / $199 | perceptual dynamic EQ | proprietary | 2018 review | D | https://www.soundonsound.com/reviews/soundtheory-gullfoss?amp |
| M12 | 10, 4 | partner article | Gullfoss changes response ">300 times per second"; frequency-range limiters | >300 Hz update | — | proprietary | promotional | D | https://www.production-expert.com/production-expert-1/how-to-get-the-best-from-soundtheory-gullfoss-in-five-minutes |
| M13 | 10, 7, 4 | manual | soothe2 detects resonances, reduces automatically; frequency-dependent attack / release; Depth / Sharpness / Selectivity | no numeric rates | dynamic spectral cuts | proprietary | — | C | https://www.oeksound.com/manuals/soothe2 |
| M14 | 10, 7 | help docs | Pro-Q 4 EQ Match averages ~30 s, auto-chooses band count / types, static result, detail slider only | ~30 s | match → static bands | proprietary | — | C | https://www.fabfilter.com/help/pro-q/using/eqmatch |
| M15 | 10 | help docs | spectral dynamics: per-frequency triggering, auto threshold / attack / release, density, tilt 3 dB/oct | — | linear-phase dynamic | proprietary | — | C | https://www.fabfilter.com/help/pro-q/using/spectral-dynamics |
| M16 | 10, 5, 4 | manual | BASSROOM suggests targets in real time; Integrated vs Short-Term (3 s); loudness-aware; ≤20 refs | 3 s; 20 refs | suggestion only | proprietary | algorithm undisclosed | C | https://masteringthemix.com/pages/bassroom-manual |
| M17 | 10 | vendor blog | LANDR reference mastering, ≤3 references, needs rights | ≤3 refs | cloud render | proprietary | no mechanism | D | https://blog.landr.com/reference-mastering/ |
| M18 | 10, 5 | news (MusicTech) | LANDR styles Warm / Balanced / Open (Tonic engine); Volume Matching; Mastering Preferences | 3 styles | cloud render | proprietary | no mechanism | D | https://musictech.com/news/gear/landr-adds-three-new-mastering-styles-to-ai-mastering-service/ |
| M19 | 10, 7 | code README | Matchering matches RMS, FR, peak, stereo width; Hyrax limiter | — | reference matching | **GPL-3.0** (code; no weights) | — | B | https://github.com/sergree/matchering |
| M20 | 10, 7, 1 | source code | static M/S FIR from loudest-piece average spectra; LOWESS on log grid; whole-track convolution | boxcar STFT, no overlap | offline, non-causal, static | **GPL-3.0** | non-adaptive | B | https://raw.githubusercontent.com/sergree/matchering/master/matchering/stage_helpers/match_frequencies.py |
| M21 | 10, 7, 5 | review (SOS) | Waves Online Mastering ML on Piper Payne; Style / Tone / Ref; no EQ display, no loudness target, no reference-influence control; ~−7 LUFS | $2.99–5.99 / track | cloud render | proprietary | review | D | https://www.soundonsound.com/reviews/waves-online-mastering |
| M22 | 10, 7 | news (Gearnews) | Curves AQ: Learn → 5 generated spectral targets; dynamic / static / hybrid; intensity, Smart Tilt, Offset | $65 intro → $155 | generative target → EQ | proprietary | untested, promotional | D | https://www.gearnews.com/waves-curves-aq-plugin-studio |
| M23 | 10, 7 | help page | LG AI Sound Pro: deep learning, "based on the genre of the video"; TV speaker / Sound Share only | webOS 5 / 6 / 22 paths | genre → sound mode | proprietary | no mechanism | C | https://www.lg.com/ae/support/product-help/CT20076005-20153290820794 |
| M24 | 10, 7, 6 | product page | AI Object Remastering extracts dialogue / elements; AI Sound Wizard "learns your unique preferences"; enable via Sound Mode | "millions of data points" | — | proprietary | marketing | D | https://www.lg.com/global/lg-ai/ai-tv/ |
| M25 | 10, 6 | hands-on preview (TechRadar NL) | Sound Wizard: 4 versions per clip, pick 1–2, repeat; profile emphasises dialogue / brightness or low end; demo toggle; account-tied | 4-way choices | A/B → static profile | proprietary | demo-room first look; partly truncated | D | https://global.techradar.com/nl-nl/televisions/wij-zagen-de-lg-c5-oled-tvs-nieuwe-gepersonaliseerde-geluidsmodus-in-actie-en-het-is-de-beste-ai-feature-die-we-tot-nu-toe-op-een-tv-hebben-gezien |
| M26 | 10 | news (CES 2025) | Wizard "analyzed… 40 million sound profiles"; virtual 11.1.2 | 40 M (marketing) | — | proprietary | press-release figures | D | https://interestingengineering.com/ces-2025/lg-oled-tv-ai-powered-visuals-sound |
| M27 | 10, 7 | support page | Samsung Adaptive Sound (+ / Pro): "analyzing the viewing space and the acoustic components of the content"; AVA; Adaptive Volume; TV speaker only; Intelligent Mode toggle | 2020–2024 models | — | proprietary | no mechanism | C | https://www.samsung.com/us/support/answer/ANS00082443 |
| M28 | 10 | news (SamMobile) | real-time content + space analysis; "no data is saved" (Samsung claim); mileage varies | — | — | proprietary | second-hand | D | https://www.sammobile.com/news/understanding-using-adaptive-sound-samsung-tv/ |
| M29 | 10, 7, 4, 5 | white paper | Dolby IEQ: continuous spectral-balance monitoring vs desired tone → dynamic EQ; leaves sufficient bands alone; "older recordings… remastered, modern… left unprocessed"; Leveler (ASA, per-band), Dialogue Enhancer, Maximizer +12 dB | +12 dB max boost | causal dynamic EQ toward a target | proprietary | undated (DHT v4 era) [date U]; no rates | C | https://professional.dolby.com/siteassets/pdfs/dolby-pc-entertainment-experience-v4-white-paper.pdf |
| M30 | 10, 7, 4, 11 | patent US9621124B2 (Dolby) | classifier confidences (0–1) → continuous EQ level (weight of gains); transition-dependent τ (slow rise / fast fall); hold timer; genre / instrument clusters with per-cluster profiles; low EQ on dominant-source music; off for movie / game | priority 2013-03-26; granted 2017-04-11 | content-type-controlled EQ | patent | claims-level only; no listener data | B | https://patents.google.com/patent/US9621124B2/en |
| M31 | 10 | support page | Huawei Histen "Auto… identifies what you are playing… applies sound effects"; headset only | — | — | proprietary | no mechanism | C | https://consumer.huawei.com/uk/support/content/en-gb02234437 |
| M32 | 10 | support page | Huawei Dolby Atmos "intelligently identifies audio content… automatically adjusts" | — | — | proprietary | no mechanism | C | https://consumer.huawei.com/uk/support/content/en-gb00765406 |
| M33 | 10 | news (TechNode 2023) | QQ Music on-device AI model + Qualcomm AI Engine for "audio detail restoration"; Super VIP | — | on-device restoration | proprietary | no EQ claim | D | https://technode.com/2023/09/28/tencent-music-partners-with-qualcomm-to-launch-ai-powered-premium-sound-quality/ |
| M34 | 10 | product page | DTS Sound Unbound: gaming spatial; no content-adaptive EQ described | — | — | proprietary | — | D | https://dts.com/dts-sound-unbound/ |
| M35 | 10, 7 | press release (2020) | AirPods Max Adaptive EQ adjusts "to the fit and seal… adjusting the low and mid-frequencies in real time" | — | in-ear mic feedback | proprietary | not content-aware | D | https://apple.com/newsroom/2020/12/apple-introduces-airpods-max-the-magic-of-airpods-in-a-stunning-over-ear-design |
| M36 | 10, 7 | news (Engadget) | iOS 27 Custom EQ (highs / mids / lows) for H2 AirPods, preview + revert | — | manual | proprietary | beta-era | D | https://engadget.com/2189850/airpods-are-getting-a-customizable-eq-in-ios-27 |
| M37 | 10, 7, 1 | support page | Music on Mac: Sound Enhancer slider; Sound Check; AutoMix "based on analysis of the key and tempo" | — | analysis → transitions | proprietary | — | C | https://support.apple.com/guide/music/musdf855a1b/mac |
| M38 | 10 | support page | Music on Mac EQ: 20+ presets; preset can be assigned per song | 20+ presets | rule (per-song) | proprietary | — | C | https://support.apple.com/guide/music/museb684a3de/mac |
| M39 | 10, 1, 7 | news (9to5Mac) | AutoMix "Using AI to analyze audio features… time stretching and beat matching"; iPhone 11+; on by default | — | read-ahead transitions | proprietary | beta-era; analysis location unstated | D | https://9to5mac.com/2025/06/16/automix-apple-music-ios-26/ |
| M40 | 10, 7 | news (RouteNote) | iOS 27 AutoMix "remix portions of a song's intro or outro, repeat sections" | — | — | proprietary | "reportedly" | D | https://routenote.com/radar/apple-music-automix-gets-a-major-upgrade-in-ios-27/ |
| M41 | 10, 7 | news (TechRadar via Yahoo) | AutoMix "chopping the last 30 seconds off a song", skipping a first verse | ~25–49 s examples | — | — | anecdotal (Reddit / TikTok) | D | https://tech.yahoo.com/audio/articles/apple-music-users-loving-automix-140000012.html |
| M42 | 10, 6 | help guide | Sony Find Your Equalizer: "selecting sound while listening to music"; saved to Custom 2 | — | preference → EQ preset | proprietary | rounds unspecified | C | https://helpguide.sony.net/mdr/hpc/v1/en/contents/TP1001274108.html |
| M43 | 10, 6 | product page | Sennheiser Sound Check: guided process → best EQ preset; login required; app free | — | — | proprietary | format unspecified | D | https://global.sennheiser-hearing.com/pages/smartcontrol |
| M44 | 10, 6 | review (Audio46) | Sound Check "creates a custom EQ preset based on a short listening test"; multiple presets | — | — | proprietary | — | D | https://audio46.com/blogs/headphones/sennheiser-momentum-4-review |
| M45 | 10, 6, 7 | review (MusicTech) | SoundID A/B: "two sets… slight variations in EQ balance", pick 1st / 2nd / no difference; ML; 350+ headphones; Listen on / off only, not editable; level jump; inconsistent across headphones | £4/mo, £36/yr | 2-AFC → static profile | proprietary | ~2021 | D | https://musictech.com/reviews/studio-recording-gear/sonarworks-sound-id-and-sound-id-listen |
| M46 | 10, 6 | news (Engadget) | "A/B test with multiple rounds using the same sample with different tunings"; age / sex compensation; barely audible on bass-heavy EDM | $4.99/mo | — | proprietary | ~2021 | D | https://engadget.com/sonarworks-soundid-listen-personalized-audio-app-mac-pc-130040080.html |
| M47 | 10 (adjacent) | news (SamMobile) | Samsung Adapt Sound: beeps, yes / no → profile; media or calls | — | hearing test | proprietary | adjacent | D | https://www.sammobile.com/news/one-ui-tip-get-the-best-audio-quality-adapt-sound/ |
| M48 | 10 (adjacent) | vendor story | Bose CustomTune: chime + in-ear mics measure the ear canal; adjusts audio and ANC | — | ear-acoustics calibration | proprietary | not content | D | https://bose.com/stories/sound-shaped-to-you-bose-customtune-technology |
| M49 | 10 | article (Android Police 2013) | Poweramp assigns EQ presets per output / song / album; song / album override output | — | rule-based | proprietary | old | D | https://www.androidpolice.com/2013/06/26/poweramp-tip-automate-your-eq-presets-based-on-audio-output-and-even-specific-songs-or-albums/ |
| M50 | 10, 5 | user guide | HiBy MSEB: 10 named manual tone dimensions; nothing automatic | 10 dimensions | manual macros | proprietary | — | C | https://guide.hiby.com/en/docs/guides/audioprocess/mseb |
| M51 | 10 | product page | Boom 3D: 31-band EQ, genre presets, intensity sliders; no adaptive | 31 bands | manual | proprietary | — | D | https://globaldelight.com/boom/features |
| M52 | 10 | support page | Spotify equalizer: choose a preset or drag; nothing automatic | — | manual | proprietary | — | C | https://support.spotify.com/my-en/article/equalizer |
| M53 | 10, 6, 7 | forum (Roon, 2021–2025) | request for taste-learning EQ ("suggest 10 tracks"); objections: needs more data; "wrong… worse than no DSP"; interrupts listening | — | — | — | community, not staff | D | https://community.roonlabs.com/t/automated-ai-based-eq/137495 |
| M54 | 10 | forum (Roon, 2026-06) | request for AI EQ / headphone / NL assistant in MUSE; no staff reply; auto-closed | — | — | — | community | D | https://community.roonlabs.com/t/integrating-generative-and-predictive-ai-into-muse/321620 |
| M55 | 10 | docs (quick start) | Wavelet quick start (features not on page) | — | — | proprietary | didn't confirm AutoEq / ISO 226 claims | C (existence only) | https://pittvandewitt.github.io/Wavelet/ |
| M56 | 10, 7, 4 | product site | EQK: "Optional on-device AI Tune… during a song, by moment, section, or one static curve"; song profiles remembered; manual remains; no upload; measured correction separate; local library | ₹699 lifetime; macOS 14.6+; 3,985 AutoEq profiles | causal per-song adaptive EQ | proprietary | marketing; no independent review | D | https://kuja.dev/eqk |
| M57 | 10 | Product Hunt listing | EQK 3.0 launched 2026-07-29 (v1 2026-07-15); "each second" adjustments; Apple Intelligence "decision weights" (claim) | — | — | proprietary | maker claims | D | https://www.producthunt.com/products/eqk-eq-with-ai |
| M58 | 10, 4, 6, 7 | Product Hunt thread | maker: refresh "every second to twice a second", ≤1,000 songs, "learns… on the second play", "doing too much", "over-EQ'd", "not all genres"; users: second-guessing masters, mid-song changes, "learning volume and calling it taste", match within ~0.5 dB | 1–2 Hz; 1,000 songs | — | proprietary | anecdotal; maker statements | D | https://www.producthunt.com/p/eqk-eq-with-ai/eqk-3-0 |
| M59 | 10, 6, 11 | patent US10855241B2 (Sony) | genre-based auto EQ biased by learned user manual adjustments; periodic sampling; can change mid-song on genre change; stores genre per song | filed 2018-11-29; granted 2020-12-01 | genre classifier + user-bias learning | patent | not known to have shipped | B | https://patents.google.com/patent/US10855241 |

**Claims seen only in snippets or on blocked pages, not used as fact [U]:** LANDR intensity Lo/Med/Hi and micro-genre detection (Planetary Group); Dolby IEQ preset names (legitreviews 502); Samsung Galaxy Dolby "Auto" picks Voice (Samsung EU forum 403); Sony Bravia Voice Zoom 3 (Sony pages 403); Poweramp "no on-the-fly EQ based on live analysis" and genre-tag rules (forum 403); AutoMix catalogue-only; SoundID "8–12 questions" and ">80% prefer" (Sonarworks support 403); Sony FYE "nine presets" (What Hi-Fi truncated); Nothing / Audiodo, Soundcore HearID, JBL Personi-Fi mechanisms (403 / empty); Neutron Player and Wavelet AutoEq counts; FiiO Control "AUTO EQ" (2026-01); "AI Equalizer" and "AutoEQ: Smart Music Equalizer" Play Store apps (truncated); learn:EQ price; iZotope "guide, not decide" slogan; Gullfoss "100×/s" alternative figure; LG AI Acoustic Tuning (room scan via Magic Remote distance); Samsung Chile Vision-AI page (timeout); Spotify "AI equalizer" / "auto preset by genre" ideas (pages empty).

---

## 4. Search log

All queries ran on WebSearch (standard mode unless marked "ext") on 2026-10-10. "Hits" = result links screened. "Incl." = sources from that query opened and used (by ID).

| # | Query (abridged) | Hits | Incl. |
|---|---|---|---|
| 1 | sonible smart:EQ 4 learning phase profiles how it works manual | 9 | 1 (M1) |
| 2 | iZotope Ozone 12 Stabilizer adaptive tonal balance target how it works | 10 | 1 (M4) |
| 3 | Soundtheory Gullfoss how it works perceptual real-time EQ recover tame bias | 9 | 2 (M11, M12) |
| 4 | oeksound soothe2 how it works dynamic resonance suppressor manual | 10 | 1 (M13) |
| 5 | sonible smart:EQ 4 manual pdf english smart:filter adaptive learning | 9 | 0 |
| 6 | docs.izotope.com Ozone 12 Stabilizer Shape Cut response speed | 9 | 0 (off-topic) |
| 7 | Ozone 12 Master Assistant ML genre target Custom Flow review 2025 | 9 | 2 (M5, M6) |
| 8 | iZotope Tonal Balance Control 2 target curves how built | 10 | 1 (M9) |
| 9 | iZotope Ozone 11 Stabilizer Shape Cut Speed adaptive EQ | 9 | 0 |
| 10 | FabFilter Pro-Q 4 EQ Match spectral dynamics manual | 9 | 2 (M14, M15) |
| 11 | Mastering The Mix REFERENCE / BASSROOM / LEVELS target EQ suggestions | 9 | 1 (M16) |
| 12 | LANDR mastering how it works AI styles intensity reference 2025 | 9 | 1 (M17) |
| 13 | Matchering open source how it works reference algorithm github | 10 | 2 (M19, M20) |
| 14 | Waves Online Mastering AI how it works genre character reference | 9 | 1 (M21) |
| 15 | LANDR mastering styles Warm Balanced Open intensity help center | 10 | 1 (M18) |
| 16 | LG AI Sound Pro deep learning genre classification webOS | 10 | 1 (M23) |
| 17 | Samsung Adaptive Sound Pro AI content scene-by-scene room acoustics | 9 | 1 (M28) |
| 18 | Samsung TV e-manual "Adaptive Sound Pro" analyzing acoustic components | 9 | 1 (M27) |
| 19 | Sony Bravia Acoustic Auto Calibration Sound mode Auto AI sound XR | 9 | 0 |
| 20 | Dolby Audio "Intelligent Equalizer" how it works white paper | 10 | 2 (M29, M30) |
| 21 | Dolby Atmos for PCs Intelligent Equalizer presets Dolby Access | 9 | 0 (502) |
| 22 | Samsung Galaxy Dolby Atmos "Auto" mode detects content One UI | 10 | 0 (403) |
| 23 | DTS Sound Unbound features DTS:X Ultra modes music EQ | 10 | 1 (M34) |
| 24 | Qualcomm Snapdragon Sound AI content-aware adaptive audio genre EQ | 9 | 1 (M33) |
| 25 | Huawei Histen AI sound effect genre OR Xiaomi AI sound equalizer | 19 | 1 (M31) |
| 26 | Windows 11 audio enhancements AI Copilot+ adaptive EQ music 2025–26 | 9 | 0 |
| 27 | AirPods "Adaptive EQ" what it adjusts inward mic fit | 9 | 1 (M36) |
| 28 | Apple AirPods Max newsroom "Adaptive EQ" low and mid frequencies | 10 | 1 (M35) |
| 29 | Apple Music "Sound Enhancer" Mac support.apple.com | 10 | 2 (M37, M38) |
| 30 | Apple Music AutoMix iOS 26 how it works time stretching | 9 | 1 (M39) |
| 31 | support.apple.com AutoMix catalog albums genres transitions | 10 | 1 (M40) |
| 32 | AutoMix Apple Music complaints cuts off songs early | 9 | 1 (M41) |
| 33 | Sony Headphones Connect "Find your Equalizer" A/B | 10 | 0 |
| 34 | Sennheiser Smart Control "Sound Check" A/B steps | 10 | 1 (M43) |
| 35 | "Find Your Equalizer" Sony choose the sound you prefer (ext) | 19 | 1 (M42) |
| 36 | Sennheiser Momentum "Sound Check" review A and B | 9 | 0 |
| 37 | Sennheiser "Sound Check" bass treble step walkthrough Momentum 4 | 10 | 1 (M44) |
| 38 | Sonarworks SoundID Listen how it works A/B preference | 10 | 2 (M45, M46) |
| 39 | SoundID Listen discontinued / price 2025 | 10 | 0 |
| 40 | Samsung Galaxy "Adapt Sound" hearing test | 9 | 1 (M47) |
| 41 | Nothing "Personal Sound Profile" Audiodo hearing test | 10 | 0 (403) |
| 42 | Soundcore HearID 2.0 how it works | 9 | 0 (empty) |
| 43 | Bose CustomTune how it works | 10 | 1 (M48) |
| 44 | JBL Personi-Fi 3.0 how it works | 10 | 0 (403) |
| 45 | Poweramp equalizer AutoEq / per-track / genre preset switching | 9 | 1 (M49) |
| 46 | Neutron Music Player equalizer auto preset per genre | 20 | 0 |
| 47 | Wavelet app AutoEq features | 10 | 0 (M55 existence only) |
| 48 | HiBy Music MSEB tone sliders | 9 | 1 (M50) |
| 49 | FiiO Control app AI EQ / smart EQ 2025 | 18 | 0 |
| 50 | "AI EQ" app music listening 2025 adjusts to each song (ext) | 9 | 1 (M57) |
| 51 | sonible learn:EQ styles intensity review | 9 | 1 (M3) |
| 52 | iZotope Neutron 5 Sculptor adaptive target Mix Assistant | 9 | 1 (M10) |
| 53 | Waves Curves Equator / Curves AQ how it works AI | 10 | 1 (M22) |
| 54 | Spotify equalizer presets auto / by genre community | 10 | 1 (M52) |
| 55 | Roon DSP parametric EQ headroom AI 2025 | 20 | 2 (M53, M54) |
| 56 | Boom 3D equalizer presets intensity auto | 9 | 1 (M51) |
| 57 | Amazon Music / Tidal / Qobuz equalizer 2025 | 9 | 0 |
| 58 | EQK Mac "AI Tune" equalizer kuja | 9 | 2 (M56, M58) |
| 59 | "AutoEQ: Smart Music Equalizer" learns from changes | 9 | 1 (M59) |
| 60 | Motorola / Lenovo Dolby Atmos "Smart audio" detects content | 20 | 1 (M32) |
| 61 | Sony Bravia 2025 Voice Zoom 3 AI sound | 10 | 0 (403) |
| 62 | LG 2025 AI Sound Pro / AI Acoustic Tuning / Voice Remastering | 20 | 1 (M24) |
| 63 | eqMac AI / auto; Audirvana Studio EQ AI 2025 | 19 | 0 |
| 64 | LG "AI Sound Wizard" how it works A/B | 9 | 0 (truncated) |
| 65 | LG "AI Picture Wizard" "AI Sound Wizard" millions personalization | 9 | 2 (M25, M26) |
| 66 | SOS review Ozone 11 Stabilizer Shape Cut | 9 | 2 (M7, M8) |

**Totals:** 66 queries, 701 hits screened, 59 sources included (M1–M59). M2 came from a direct fetch of the vendor URL, not a query.

**Snowballing (one hop):** Dolby white paper (M29) → patent family (M30), forward. EQK PH listing (M57) → vendor site (M56) and 3.0 thread (M58). Matchering README (M19) → source file (M20), backward. LG product page (M24) → Sound Wizard hands-on (M25, M26).

**Saturation note.** I stopped at a **cap** (66 queries), not at full saturation. Category by category:
- **Pro/creator:** saturated. Queries 52, 53 and 66 added sources but no new product classes.
- **Players and system EQs:** near-saturated. Queries 56, 57 and 63 found no new adaptive products.
- **TV/OEM:** *not* saturated. Query 65 surfaced LG AI Sound Wizard late.
- **Not searched:** Asian phone OEMs beyond Huawei (OPPO, vivo, Honor, Xiaomi HyperOS AI) and car audio.

---

## 5. Gaps (what the evidence doesn't answer)

1. **Efficacy.** No opened source shows listener-test evidence that any adaptive or preference-learned EQ beats the original or a static preset. SoundID's ">80% prefer" figure is vendor-reported and [U].
2. **Rates and constants.** Consumer products publish no update rates, smoothing constants or change bounds. Dolby's patent is qualitative, and Gullfoss's ">300/s" comes from partner content.
3. **What "optimized sound" changes** on LG, Samsung and Huawei (EQ only? dynamics? width?) is undocumented.
4. **AutoMix internals.** Where the analysis runs, whether local files are eligible, and whether there is any EQ/loudness component are all [U].
5. **EQK's real behaviour.** There is no independent review or hands-on. Its preference-learning mechanism and the role of Apple Intelligence are maker claims only.
6. **LG Sound Wizard.** The number of rounds, the output dimensionality, and whether the profile interacts with AI Sound Pro's genre adaptation are unknown.
7. **User-complaint evidence is anecdotal** (forums, PH comments, one TechRadar piece). I did no systematic review or app-store mining.
8. **Coverage holes.** I didn't cover OPPO, vivo, Honor or Xiaomi AI sound, car infotainment, or Sonos and other speaker room-plus-content systems. Windows and the streaming apps rest on one negative query each.
9. **The IP freedom-to-operate implications** of M30 and M59 need the IP track (RO11).
