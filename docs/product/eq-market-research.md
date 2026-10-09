# How EQs look in other products: market research for the EQ tab redesign

*2026-10-08 · for the founder and the ui-designer · 23 products plus AdaptiveSound today · sources are numbered [n] at the end. "n/d" means the vendor doesn't document it. I list a claim only where a source supports it.*

**TL;DR**
- **The market splits in two.** Mainstream players offer ≤10 fixed bands or presets only (Apple Music, Spotify, Sony, Bose, Sonos). Audiophile and pro tools moved to **parametric points you drag on a graph** (Audirvana, Roon, eqMac Expert, Poweramp, Pro-Q, Logic, EQ Eight). Nobody defaults to 31 bands: Boom 3D hides its 31 behind "Advanced", and Swinsian makes 31 an option.
- **The elegant ones share five traits:** the graph *is* the editor, there are few handles, the curve shows what you actually hear, gain/clipping is handled automatically and visibly, and details appear only on demand.
- **Headphone correction from a database (AutoEq) is now table stakes for enthusiast tools:** Roon, SoundSource, eqMac, Plexamp, Poweramp, Wavelet. Our roadmap already has it (S12/S13).
- **Our EQ tab has three honesty problems the market punishes:**
  - the graph shows the curve you asked for, not the quieter curve the safety clamp actually plays;
  - saved custom presets never appear in the Preset menu;
  - per-device recall has no way to assign a preset. (See §3.2.)
- **Recommendation:**
  - R1 ships the glass restyle plus small honesty fixes.
  - A new editor of about 5 labelled "tone points" is designed now and built as the first post-R1 wave, folded into S12's parametric work. It runs on the existing 31-band engine until S12 adds the true parametric engine.

---

## 1. Comparison table

### 1a. Desktop players and system-wide Mac EQs

| Product | Band model | Interaction & visual | Presets & device memory | Gain safety · bypass · A/B | Simple → advanced | Headphone / auto correction | Reviewers / users say | Src |
|---|---|---|---|---|---|---|---|---|
| **Apple Music (macOS)** | Fixed graphic, 10 bands + **preamp** | Vertical faders in a small separate window (Window › Equalizer, ⌥⌘E) | 20+ built-ins (genre + Bass/Treble Booster/Reducer); *Make Preset*; *Edit List* to rename/delete; **per-song preset** (Get Info › Options) | Preamp; **On** checkbox; no A/B | One mode | None (a separate "Sound Enhancer" slider) | Genre presets are "hit or miss"; custom presets don't travel between Macs | [1][2][3] |
| **Spotify (desktop + mobile)** | Fixed graphic, 6 bands (Android: system EQ) | Drag dots on a small curve, buried in Settings › Playback | ~22 iTunes-style presets; no saved user presets (much requested) | On toggle; no preamp (n/d); unavailable over Connect | One mode | None | Wants more bands, a sub-60 Hz band, saved presets, **numeric values** | [4][5][6][7][8] |
| **Audirvana Studio** (2025) | **Parametric, 10 bands**: peak, notch, shelves, HP/LP, band-pass | Drag points (x = freq, y = gain); Freq/Gain/Q knobs; double-click a value to type it; per-band Active + Solo; **live input (white) and output (blue) spectrum** behind the curve | Named user presets, Default, Manage; **settings auto-saved per output device** | Output Gain + **Auto** (lowers gain by the boost); output meter; red "Clipping Output" with per-channel overs; master On/Off; undo/redo | One view; knobs below the graph | None built in (hosts AU plugins) | (Too new for much review) | [9][10] |
| **Roon (MUSE)** | Parametric EQ as one filter in a reorderable DSP chain (PEQ, Procedural EQ, Crossfeed, Convolution, Headphone EQ) | EQ display + per-filter rows (Freq, Gain, Q, Type); editing desktop-only, mobile only toggles | Save curves from the display; **Headphone EQ: search by model** ("hundreds", OPRA) | **Headroom Management** (start at −3 dB) + clipping indicator (signal-path light turns red) | Chain of filters; mobile = on/off only | OPRA headphone EQ; convolution | Users fight clipping; the community advises keeping the curve below 0 dB | [11][12][13][14] |
| **foobar2000** | 18-band graphic (SuperEQ); the 31-band xgeq is Windows-only | Sliders in DSP Manager (n/d on Mac) | `.feq` preset files | n/d | — | — | The Mac EQ ships unconfirmed; the Mac app has AU DSP support | [15][16][17] |
| **Swinsian 3** | Fixed graphic, **10 or 31** bands | Drag one band, or **Ctrl-drag across bands to draw a curve** (like ours) | 20+ presets | n/d | 10 ↔ 31 switch | None | — | [18][19] |
| **Doppler** | No EQ found in the product page or launch coverage | — | — | — | — | — | Library-first player; EQ absent | [20] |
| **Plexamp** | Graphic (UI max +10 dB) | n/d | **AutoEQ headphone database, 3000+** (4.5.0); auto-switch by connected device (user report) | n/d | EQ hidden in Settings › Playback › EQ | AutoEQ presets | Can't save arbitrary presets; device switching "pretty much never works"; "if it's flat it's off"; presets exceed the UI range; leveling active with EQ on | [21][22][23][24][25] |
| **VOX** | 10-band graphic (bands movable in frequency) | Sliders + an on switch at the top right | 14 named presets (30+ with Premium); names "only for identification" | **Gain slider** on the left to offset boosts | One mode | None | "Easy to fine-tune… useful presets"; the UI's unlabeled buttons confuse | [26][27][28] |
| **eqMac** | **Basic** (bass/mid/treble) → **Advanced** (10 fixed bands) → **Expert** (unlimited parametric + graph + spectrum, Pro) | Graph + analyzer in Expert | **Headphone presets 4,600+**; **Super Presets** auto-switch by output device or app | Volume boost >100% (no clip guard documented) | **Three explicit tiers**, the canonical progressive disclosure | Headphone presets | — | [29][30] |
| **SoundSource 6** (Rogue Amoeba) | 10-band graphic (Lagutin) + **preamp (added 6.0)**; separate **Headphone EQ** effect; AU hosting | Effects chain per app / system in a menu-bar popover; sliders take keyboard entry and the scroll wheel | ~2 dozen presets; presets reachable from the main UI; **user presets prioritised** | Preamp | Effect chain = disclosure | **Headphone EQ (AutoEq, "thousands"): add it, search your model, done** | 6.1.1 fixed presets applying **only half** their boost (invisible without an honest graph) | [31][32][33][34] |
| **Boom 3D** | Graphic, **10 bands by default, 31 in "Advanced"** | Sliders (n/d); menu bar | Genre / movie presets; save an edited one under a new name | n/d | 10 → 31 behind Advanced | None (3D surround instead) | "Lots of settings to tinker with" | [35][36][37] |
| **SoundID Reference** (Sonarworks) | Measured / profile correction (500+ headphones); target Flat / Custom / Translation Check | Graph with **before/after curves**, in/out meters, **Dry/Wet dial** | Per-headphone profile | "Safe Headroom" | A reviewer asks for an Expert mode | **Profile correction with a strength dial** | Correction at ~50% Dry/Wet sounded best; strong corrections are audible | [38][39][40] |
| ***AdaptiveSound today*** | Fixed graphic, **31 ISO ⅓-oct bands, ±12 dB** | Freehand drag across 31 dots; "Interpolation: Smooth / Discrete"; axis drawn ±20 dB; curve interpolated through the dots | 7 descriptive built-ins (Flat, Presence, Clarity, Warm, Loudness, Vocal, Studio); Save as Custom; per-device map | **No On/Off, no preamp, no reset on the tab**; a hidden cumulative clamp; −1 dBTP limiter downstream | One mode | None yet (S12/S13) | — | code |

### 1b. Pro references and mobile / headphone apps

| Product | Band model | Interaction & visual | Presets & memory | Gain · bypass · A/B | Simple → advanced | Correction | Reviewers say | Src |
|---|---|---|---|---|---|---|---|---|
| **FabFilter Pro-Q 4** | Parametric; bell/shelf/cut/notch plus dynamic/spectral bands | Hover the centre line → yellow blob → **click to create**; drag a dot = freq + gain; **scroll wheel = width**; double-click the far edges = cuts; multi-select drags scale together; a **floating panel for the selected band only**; display range ±3/6/12/30 dB auto-expands; **pre/post analyzer, Spectrum Grab** | DAW presets; A/B + undo (own help page) | **Auto Gain**, **Gain Scale**, never clips internally, soft global bypass | Details appear on selection | EQ Match (n/d here) | "Efficient, intuitive and powerful"; **EQ Sketch (drawing) rarely faster than placing points** | [41][42][43] |
| **Logic Pro Channel EQ** | **8 fixed-role, colour-coded bands**: HP, low shelf, 4 bells, high shelf, LP | Drag inside a band's region (horizontal = freq, vertical = gain); pivot = Q; analyzer **pre/post**; **Gain-Q couple** keeps perceived width | Logic presets | Master gain | Fixed roles mean no "add band" decision | — | Good for beginners thanks to the live analyzer | [44][45][46] |
| **Ableton EQ Eight** | 8 parametric bands, 6 types | Drag dots; **⌥-drag = Q**; **arrow keys move selected dots**; Analyze; **Audition** (solo one filter); **Adaptive Q**; **Scale** (all gains); expanded view | Device presets | Global gain | Expanded view on demand | — | — | [47] |
| **iOS Music** | **Presets only** (22), no custom | Settings › Music › EQ list | 22 fixed | Sound Check (normalisation) | — | — | — | [48][49] |
| **Poweramp Equalizer** | **Graphic 5–32 bands (custom count/range, ±15 dB) or Parametric** (add bands with type/channel/Q) | Two modes with separate preset stores | **AutoEq presets preinstalled and suggested on device connect**; **per-device assignment**; JSON + AutoEq `.txt` import; preset search; lock a preset | **Preamp**, limiter, compressor, balance, bass/treble tone | Graphic ↔ Parametric | AutoEq | Parametric presets can't load into graphic mode | [50][51][52] |
| **Wavelet** (Android) | AutoEq database (5000+, Harman target) **+ a 9-band graphic on top** | Search by model; recent headphones list | Multiple custom presets (25.03) | Limiter (auto post-gain), channel balance, clipping-reduction option | Correction first, taste second | **AutoEq** | — | [53][54][55] |
| **Sony Sound Connect** | 5 bands + Clear Bass; **10 bands on WH-1000XM6** | Sliders | Bright, Bass Boost, Vocal, Speech… + 2 custom slots; **"Find Your Equalizer": pick a favourite of 5 variants while your own music plays, narrowing; saved to Custom 2** | n/d | Presets → Manual → guided | — | Reviewer wishes for parametric "but most people would struggle" | [56][57][58][59][60] |
| **Bose** | **3 bands** (bass / mid / treble) | Drag a white circle per band; **Reset** top right | Flat, Bass/Treble Boost/Reducer, Custom | Warns that extremes hurt quality | — | — | — | [61][62][63] |
| **Sonos** | **Bass / treble ±10 + Loudness toggle** | Two sliders; EQ shortcut on the volume slider | Per speaker | — | Manual EQ is tiny; Trueplay tunes a **hidden parametric EQ** | **Trueplay** room measurement (iOS) | Users find two sliders too coarse | [64][65] |
| **AirPods Headphone Accommodations** *(reference only; hearing personalization is out of scope)* | 3 tonal words (Balanced Tone / Vocal Range / Brightness) × 3 strengths (Slight/Moderate/Strong) | Pick + **Play Sample** preview | Per device | — | — | — | (Vocabulary reference only: plain words + strength + preview) | [66] |

### 1c. Keyboard and accessibility (where documented)

Apple Music opens the EQ with ⌥⌘E [3]. SoundSource fixed keyboard entry in its EQ sliders in 6.0.3 [32]. Ableton moves selected dots with the arrow keys [47]. Pro-Q tabs between typed Freq/Gain/Q fields [41]. Nobody else documents keyboard or VoiceOver editing.

**AdaptiveSound's arrow-key band cursor and VoiceOver-adjustable per-band elements go beyond anything documented here.** Keep them through the redesign.

---

## 2. Patterns

### 2.1 Table stakes for a music-player EQ
1. **A visible On/Off at the EQ itself.** Apple, Spotify, Audirvana, VOX and Bose all have one. *We don't:* bypass lives in Pure Mode or the Now Playing intensity knob.
2. **A preset menu with built-ins plus save / rename / delete.** Apple (*Make Preset* / *Edit List*), Boom, SoundSource and Poweramp. *We save, but saved presets never appear in the menu* (§3.2).
3. **Gain staging: a preamp, an output gain or an automatic one.**
   - Apple preamp [2], VOX gain slider [26], SoundSource 6 preamp [32].
   - Audirvana Auto [9], Poweramp preamp [50], Roon headroom [12].
   - AutoEq profiles carry their own negative preamp [67].
4. **Reset to flat**, one click (Bose Reset [61]; Flat presets elsewhere).
5. **Per-device memory.** Audirvana auto-saves per output [10], eqMac Super Presets [29], Poweramp per device [50], Plexamp auto-switch [21].
6. **For the enthusiast segment: a headphone-correction database searched by model.** Roon, SoundSource, eqMac, Plexamp, Poweramp, Wavelet. Already in S12/S13.

### 2.2 What makes the elegant ones elegant
- **The graph is the control** (Pro-Q, Logic, EQ Eight, Audirvana, Spotify's dots). There are no separate slider banks, and you edit where you look.
- **Few handles with clear roles.**
  - Logic's 8 fixed, colour-coded roles remove the "how many bands, what type" decision [44].
  - Apple Music's elegance is restraint: one window, one On box, one preset menu, 10 faders [1][2].
- **Details on demand.**
  - Pro-Q shows a per-band panel only for the selected point [41].
  - eqMac's Basic → Advanced → Expert [29]; Boom's 10 → 31 Advanced [35].
  - Roon's mobile app can only toggle; editing happens on desktop [11].
- **Gain is solved automatically and visibly.** Pro-Q never clips and has Auto Gain [42]. Audirvana's Auto lowers output by the boost and turns a label red on overs [9]. SoundSource added a preamp in 6.0 [32].
- **The picture tells the truth.**
  - Analyzers show pre/post signal (Pro-Q, Logic, Audirvana in/out) [43][45][9]; Pro-Q auto-ranges the dB scale to the curve [41].
  - SoundSource's "presets applied half their boost" bug (6.1.1 [32]) shows what happens when picture and sound drift apart.
- **Global "amount" controls.** Pro-Q Gain Scale [42], Ableton Scale [47] and SoundID Dry/Wet [38] scale the whole curve with one control. That maps onto our existing intensity knob.
- **Drawing gestures are not the elegant part.** Sound On Sound found Pro-Q's EQ Sketch "rarely faster" than placing points [43].

### 2.3 Common anti-patterns (✱ = AdaptiveSound has it today)
- **Dense banks of tiny fixed controls** ✱.
  - 31 handles over ~800 pt is a ~25 pt pitch.
  - Fixed graphic bands can't move centre or width, and adjacent bands interact in ways the panel doesn't show [68].
  - Boom hides its 31 bands; Swinsian makes 31 optional [35][18].
- **Jargon in primary position** ✱. "Interpolation: Smooth Curve / Discrete Steps" is an editing-brush setting shown as a top-level control. "Q" appears in Roon and Audirvana. Logic and Ableton hide it via Q-couple and Adaptive Q.
- **Genre-named presets.** VOX admits its names are "only for identification" [26], and Macworld finds them "hit or miss" [3]. *Ours are descriptive (Warm, Presence), which is good; "Loudness" will collide with S14's level-dependent loudness compensation.*
- **Hidden EQ or hidden presets** ✱. Spotify and Plexamp bury the EQ in Settings [4][24]. Plexamp users can't tell whether it is on [23]. *Ours: saved presets are unreachable.*
- **The picture lies** ✱.
  - Plexamp applies leveling with EQ on and ships presets beyond its UI range [25][21].
  - SoundSource presets did half their boost [32].
  - *Ours draws the requested curve while the safety clamp plays a much smaller one* (§3.2).
- **No numbers.** A Spotify complaint is that its EQ "doesn't even provide numerical feedback" [8].
- **Boost without headroom.** VOX warns that boosts above 0 "inevitably" distort [26]. Roon users chase clipping [14].

### 2.4 Simple vs pro: the ladder
0. **Presets only:** iOS Music.
1. **Tone controls (2–3 bands):** Sonos, Bose, eqMac Basic.
2. **Fixed graphic (5–10 bands):** Apple Music, Spotify, VOX, Sony, Wavelet, SoundSource.
3. **Dense graphic (31 bands):** Boom Advanced, Swinsian, **us**.
4. **Parametric points:** Audirvana 10, Roon, eqMac Expert, Poweramp, Logic 8, EQ Eight 8, Pro-Q.

Two orthogonal layers sit beside the ladder:
- **Correction** from a database or a measurement, often with a strength control (SoundSource, Roon, Wavelet, SoundID Dry/Wet, Sonos Trueplay).
- **Guided choice** (Sony "Find Your Equalizer").

AutoEq itself says ~10 parametric filters give "very good results" and 5 can be enough [67]. Audiophile-oriented players (Audirvana, Roon) chose rung 4; mainstream players stop at rung 2.

---

## 3. Implications for AdaptiveSound

### 3.1 Band model and interaction for a discerning listener
**Recommend rung 4, kept small: about 5 labelled "tone points" on the existing graph.** The model is Logic's fixed roles plus Pro-Q's direct manipulation, with jargon hidden:
- **Default points:**
  - Bass (low shelf, ~100 Hz)
  - Body (bell, ~250 Hz)
  - Mids (bell, ~1 kHz)
  - Presence (bell, ~3 kHz)
  - Air (high shelf, ~10 kHz)
- **Dragging a point:** vertical = boost/cut; horizontal = shift within its zone.
- **Width:** set with the scroll wheel or ⌥-drag. Gain-Q coupling is on by default (Logic / Ableton), so "Q" is never shown.
- **Feedback:** a value readout on hover or drag (the Spotify complaint).
- **Labels:** plain words under the axis.

**Engineering path (no DSP change for the redesign).** The points produce a target curve, which is sampled at the 31 ISO centres and fed to **today's 31-band kernel**.
- S12 then swaps in a true parametric realizer, adds AutoEq `ParametricEQ.txt` import (up to ~10 points in a correction layer), and keeps the same UI.
- Caveat: a ⅓-octave graphic engine renders broad shapes well but not narrow peaks. That suits 5 broad tone points. The S7 31-band frequency-response sweep oracle can confirm the rendered response matches the drawn one.

**The 31-band freehand draw** becomes an advanced "Draw" mode, or is retired (Question 2). The evidence (Sketch "rarely faster", density anti-pattern) says it should not be the default.

### 3.2 What to keep and what to drop from the current 31-band design

**Keep**
- The graph-as-editor on the lens. This matches every elegant reference. **Sweep decision 3 ("controls under the graph, the graph fills the height") holds up:** Pro-Q and Audirvana also put the controls in a strip below the graph.
- The log-frequency axis and its single shared plot map.
- The keyboard band cursor and the VoiceOver-adjustable per-band elements (§1c).
- Descriptive preset names, user presets, per-device memory as a concept, and last-setting restore.
- The hearing-safety intent.

**Drop or change.** I found the first three items in the code:
1. **The graph shows intent, not what plays.**
   - `EQSafetyClamp` scales *all* bands whenever the signed sum of the 31 band gains exceeds +12 dB, and `bandGains` (what's drawn) stays unscaled.
   - By my arithmetic from `EQPreset.swift`:

     | Preset | Drawn peak | Peak that plays |
     |---|---|---|
     | Warm | +10 dB | ≈ +0.7 dB |
     | Loudness | +4 dB | ≈ +0.85 dB |
     | Vocal | +6 dB | ≈ +1.6 dB |
     | Clarity | +6 dB | ≈ +1.7 dB |
     | Presence | +8 dB | ≈ +2.7 dB |
     | Studio | unchanged | unchanged |

   - The sum metric also **punishes broad gentle shelves** (+2 dB over 10 bands gets scaled to +1.2 dB), yet **lets a single narrow +12 dB spike through** (its sum is exactly 12).
   - **Proposal:** use automatic headroom, meaning an overall level cut equal to the curve's highest boost (Audirvana Auto [9], AutoEq preamp [67], Pro-Q Auto Gain [42]). The −1 dBTP limiter stays for peaks, and the graph draws the curve that plays. This is stricter for hearing safety, because no frequency ever ends up louder than the source, and it keeps the user's shape. **Founder decision (Question 3).**
2. **Saved custom presets are write-only.** `EQPresetPickerView` lists only the 7 built-ins plus a read-only "Custom". `selectCustomPreset(named:)` is reached only from device recall. This is the "hidden presets" anti-pattern.
3. **Per-device recall can't be assigned.** Nothing in `Sources/` writes an entry into `outputPresetMap`, so recall never fires for a fresh user. The fix fits naturally with S13.
4. **The "Interpolation" picker is jargon in primary position.** Make "smooth" the only behaviour (or a modifier key) and give its slot to an **EQ On/Off** switch.
5. **The axis spans ±20 dB but edits clamp at ±12.** About 40% of the height can never be reached. Use ±12, or Pro-Q-style auto-range.
6. **Missing table stakes:** On/Off, Reset, a value readout, and preset rename/delete.
7. *(Hygiene)* The `EQSafetyClamp` doc comment still mentions the "future NL macro layer". That feature is cut.

### 3.3 Where an adaptive player can differentiate (within scope)
None of these use natural-language tuning or hearing tests.
- **Device-aware two-layer EQ (S12/S13).**
  - A per-device correction layer (AutoEq, auto-loaded on device change, with a **strength** slider, SoundID-style [38][39]) sits *under* your taste curve.
  - The graph shows both layers.
  - Competitors ship correction as a separate effect or filter (SoundSource, Roon). Wavelet layers a 9-band EQ on top but without a combined picture [53]. I found no Mac player that shows correction and taste on one graph.
- **An honest Compare (S12): a loudness-matched before/after.**
  - Louder playback is reliably judged "better" [69][70], so an unmatched A/B misleads.
  - No consumer player in this set documents loudness-matched comparison. The app already measures BS.1770 loudness, so this is cheap credibility.
- **Level-aware tone (S14).** Draw the loudness-compensation contour as a live ghost layer that moves with volume. Sonos only offers a static Loudness toggle [64].
- **Content-aware tone (Phase 2).** Show the adaptive Clarity contribution as its own ghost curve. Make **Amount** (the existing intensity, where 0% = bit-perfect) the global scale, like Pro-Q's Gain Scale and Ableton's Scale [42][47].
- *Not recommended:* a Sony-style "Find Your Equalizer" taste tournament [57]. It isn't a hearing test, but it sits close to the cut "personalization" line.

### 3.4 R1 versus later

| When | What |
|---|---|
| **R1 (Sprint F)** | **F3** as planned (graph on the lens), plus the axis set to ±12 dB and the curve drawn as it plays. Saved presets listed in the Preset menu (a bug-level fix). A value readout on hover/drag. **F4:** give the capsule switch to **EQ On/Off** instead of Interpolation. *This removes an element, so it needs a §C exception.* |
| **First post-R1 wave** (design now; build with S12) | The tone-points editor on the 31-band realizer; automatic headroom replaces the sum clamp; Reset; preset rename/delete; Draw as an advanced mode (or retired) |
| **S12** | True parametric realizer; AutoEq `ParametricEQ.txt` import; loudness-matched Compare |
| **S13** | Correction layer per device (auto-load + strength); visible per-device memory ("AirPods Pro → Warm") |
| **S14 / Phase 2** | Loudness-compensation ghost; adaptive layer; Amount = intensity |

**Flags on `s10-8-glass-sweep-plan.md`:**
- **Decision 3 stands.**
- **§C "no new arrangements"** blocks the F4 swap. I recommend a one-line exception, like the playlist-Move one.
- **F4** should not polish the Interpolation switch into a prominent capsule if that control is going away.

---

## 4. Questions for the founder (recommended option first)

1. **When should the EQ redesign land?**
   - **(A) Recommended:** R1 gets the glass restyle plus the small honesty fixes (curve shows what plays, ±12 axis, saved presets listed, On/Off in the Interpolation slot). The new editor is designed now and built right after R1, together with S12's parametric work.
   - (B) The full redesign before R1. R1 slips by about a sprint.
   - (C) Restyle only. Revisit at S12.
2. **What do you drag on the graph?**
   - **(A) Recommended:** about 5 labelled points (Bass, Body, Mids, Presence, Air). Up/down to boost or cut, sideways to shift. The 31-band freehand drawing stays as an "advanced" mode.
   - (B) Points only; retire the 31-band drawing.
   - (C) Keep the 31 dots and just restyle them.
3. **How should the safety limit work, and should the graph show it?**
   - **(A) Recommended:** the EQ never makes any frequency louder than the original. Boosts automatically lower the overall level, the limiter still catches peaks, and the graph shows exactly what plays.
   - (B) Keep today's sum-based limit but draw the reduced curve.
   - (C) Leave it as is. Today the presets play at about a tenth to a third of what the graph shows.
4. **How should headphone correction and your own taste combine (S12/S13)?**
   - **(A) Recommended:** two layers. A per-headphone correction (auto-loaded for that device, with a strength slider) sits under your taste curve, and the graph shows both.
   - (B) One curve; an imported headphone profile is just another preset.
   - (C) Correction lives in Settings, not on the EQ tab.
5. **Should the EQ tab have its own On/Off and Compare?**
   - **(A) Recommended:** On/Off now (R1), and a loudness-matched Compare in S12.
   - (B) Compare only, later. On/Off stays in Pure Mode and intensity.
   - (C) Neither.

---

## Sources
1. Apple, Music for Mac: Use the equalizer: https://support.apple.com/en-nz/guide/music/museb684a3de/mac
2. Apple, iTunes for Mac: equalizer (preamp, Make Preset, per-song): https://support.apple.com/en-ca/guide/itunes/itns2991/mac
3. Macworld, How to tweak your sound in iTunes and on iOS: https://www.macworld.com/article/228068/how-to-tweak-your-sound-in-itunes-and-on-ios-devices.html
4. Spotify Support, Equalizer: https://support.spotify.com/us/article/equalizer/
5. Headphonesty, Best Spotify EQ settings (6 bands on iOS): https://www.headphonesty.com/2022/03/best-spotify-equalizer-settings/
6. TechCrunch, Spotify adds an equalizer (preset list): https://techcrunch.com/2014/07/29/spotify-adds-an-equalizer-so-you-can-turn-up-the-bass
7. Spotify Community, More EQ bands and custom presets: https://community.spotify.com/t5/iOS-iPhone-iPad/More-equalizer-bands-and-custom-EQ-presets-for-iOS/m-p/5857684/highlight/true
8. Spotify Community, 30-band EQ apps / no numerical feedback: https://community.spotify.com/t5/Spotify-for-Developers/30-band-EQ-apps-broken-with-SDK-change-screenshot-comparison/m-p/5425771/highlight/true
9. Audirvana Help, How to use the integrated Studio equalizer: https://help.audirvana.com/support/solutions/articles/202000096012-how-to-use-the-integrated-studio-equalizer-eq-
10. Audirvana, Studio 2.11.0 release note / Signal Processing Suite: https://community.audirvana.com/t/release-note-audirvana-studio-2-11-0/44586 · https://audirvana.com/signal-processing-suite/
11. Roon, MUSE Parametric Equalizer: https://help.roonlabs.com/portal/en/kb/articles/dsp-engine-parametric-equalizer
12. Roon, Headroom Management: https://help.roonlabs.com/portal/en/kb/articles/dsp-engine-headroom-management
13. Roon blog, Optimizing headphone audio with OPRA (Feb 2025): https://blog.roonlabs.com/how-to-roon-optimizing-headphone-audio-with-opra/
14. Roon Community, Clipping using DSP/MUSE: https://community.roonlabs.com/t/clipping-using-dsp-muse/245222
15. foobar2000, Equalizer / SuperEQ: https://www.foobar2000.org/equalizer
16. foobar2000, foo_dsp_xgeq (31-band, Windows): https://foobar2000.org/components/view/foo_dsp_xgeq
17. foobar2000, Mac changelog (AU DSP support): https://foobar2000.com/changelog-mac
18. Swinsian, What's new in Swinsian 2 (10/31 bands, Ctrl-drag): https://swinsian.com/blog/2017/11/21/whats-new-in-swinsian-2
19. ifun.de, Swinsian 3.0 (20+ presets): https://www.ifun.de/swinsian-3-0-renaissance-der-mp3-player-auf-dem-mac-263613/
20. Brushed Type, Doppler: https://brushedtype.co/doppler/
21. Plex Forums, Plexamp EQ preset things: https://forums.plex.tv/t/plexamp-eq-preset-things/863387
22. Plex Forums, Plexamp release notes (4.5.0 AutoEQ 3000+): https://forums.plex.tv/t/plexamp-release-notes/221280/48
23. r/plexamp (mirror), How does Plexamp equalizer work: https://redlib.hackliberty.org/r/plexamp/comments/1l8vnj1/how_does_plexamp_equalizer_work
24. Plex Forums, EQ Settings (location) / Saving multiple EQ settings: https://forums.plex.tv/t/eq-settings/822126.md · https://forums.plex.tv/t/saving-multiple-equalizer-settings-on-plexamp-mod-personalized-presets/687778
25. Plex Forums, Plexamp leveling even when off: https://forums.plex.tv/t/plexamp-clearly-doing-leveling-even-when-turned-off/779979.md
26. VOX blog, What is the Equalizer in VOX: https://vox.rocks/blog/vox-eq/
27. VOX store (30+ presets, Premium): https://vox.rocks/store
28. Yahoo/Engadget, Vox for Mac review: https://www.yahoo.com/news/vox-mac-review-175640763.html
29. eqMac, home/features: https://eqmac.app/
30. eqMac, GitHub README: https://github.com/bitgapp/eqmac
31. Rogue Amoeba, SoundSource: https://rogueamoeba.com/soundsource/
32. Rogue Amoeba, SoundSource release notes (6.0 preamp, per-app Headphone EQ, 6.0.3/6.0.4/6.1.1): https://rogueamoeba.com/support/releasenotes/?product=SoundSource
33. Rogue Amoeba weblog, SoundSource 5.1 Headphone EQ: https://weblog.rogueamoeba.com/2020/10/29/
34. TidBITS, SoundSource 4.0.1 (~two dozen presets): https://tidbits.com/watchlist/soundsource-4-0-1/
35. Global Delight blog, How to customize the equalizer in Boom 3D: https://blog.globaldelight.com/boom-3d-windows/how-to-customize-equalizer-in-boom-3d-on-your-mac-windows
36. Hongkiat, Boom3D for Mac review: https://www.hongkiat.com/blog/boom3d-mac-review/
37. TechRadar, Boom3D review: https://www.techradar.com/reviews/boom3d
38. MusicTech, Review: Sonarworks SoundID Reference: https://musictech.net/reviews/studio-recording-gear/review-sonarworks-soundid-reference/
39. Bonedo, SoundID Reference test: https://www.bonedo.de/artikel/sonarworks-soundid-reference-for-speakers-headphones-with-mic-test
40. Sonarworks store, SoundID Reference for Headphones: https://store.sonarworks.com/products/soundid-reference-for-headphones
41. FabFilter, Pro-Q 4 help: EQ display: https://www.fabfilter.com/help/pro-q/using/eqdisplay
42. FabFilter, Pro-Q 4 help: Output options: https://www.fabfilter.com/help/pro-q/using/output
43. Sound On Sound, FabFilter Pro-Q 4 review: https://www.soundonsound.com/reviews/fabfilter-pro-q-4 · analyzer: https://www.fabfilter.com/help/pro-q/using/analyzer
44. Apple, Logic Pro for iPad: Channel EQ (8 colour-coded bands): https://support.apple.com/guide/logicpro-ipad/lpipaaa9fbf5/ipados
45. Apple, Logic Pro for Mac: Channel EQ: https://support.apple.com/en-al/guide/logicpro/lgcef1edc1d7/mac · Final Cut Pro Channel EQ controls (Gain-Q couple): https://support.apple.com/en-mz/guide/final-cut-pro-logic-effects/lgex92fd757d/mac · Logic 9 Channel EQ (drag regions): https://help.apple.com/logicpro/mac/9.1.6/en/logicpro/effects/chapter_5_section_1.html
46. Promix Academy, Using EQ in Logic Pro X: https://promixacademy.com/blog/using-eq-in-logic-pro-x/
47. Ableton, Live Audio Effect Reference: EQ Eight: https://www.ableton.com/en/manual/live-audio-effect-reference/
48. Headphonesty, iPhone equalizer settings (22 presets, no custom): https://www.headphonesty.com/2022/07/iphone-equalizer-settings/
49. Apple, iPad: Adjust the sound quality in Music: https://support.apple.com/guide/ipad/aside/ipad0e2fd3dd/ipados
50. Poweramp forum, Poweramp Equalizer build-908 (features): https://forum.powerampapp.com/files/file/74-powerampequalizer-build-908-equ-uniapk/
51. APKMirror, Poweramp Equalizer build-963 changelog: https://www.apkmirror.com/?p=4835644
52. Poweramp forum, Applying AutoEq settings: https://forum.powerampapp.com/topic/27284-how-to-apply-equalizer-settings-from-autoeqapp/
53. Wavelet README (mirror): https://github.com/damianos133eu/Wavelet
54. XDA, Wavelet automatic EQ: https://www.xda-developers.com/make-your-headphones-sound-better-automatic-eq-wavelet/amp/
55. APKMirror, Wavelet 25.03: https://www.apkmirror.com/?p=8830749
56. Sony, Sound Connect EQ settings article: https://www.sony.co.in/electronics/support/articles/00286844
57. Sony Help Guide, Find Your Equalizer: https://helpguide.sony.net/mdr/hpc/v1/en/contents/TP1001274108.html
58. SoundGuys, Sony 1000X EQ / Find Your Equalizer hands-on: https://www.soundguys.com/sony-1000x-the-collexion-eq-161547/
59. ShopSavvy, WH-1000XM6 Sound Connect (10 bands): https://shopsavvy.com/answers/sony-wh-1000xm6-sound-connect-app-features-settings
60. SoundGuys, WF-1000XM6 EQ presets (wishes for parametric): https://www.soundguys.com/what-do-the-sony-wf-1000xm6-eq-presets-sound-like-152641/
61. Bose, QC Ultra Headphones: using the equalizer: https://support.bose.com/s/article/quietcomfort-ultra-headphones-using-the-equalizer-settings
62. Bose, QC Ultra Earbuds (2nd Gen): equalizer: https://support.bose.com/s/article/quietcomfort-ultra-earbuds-gen-2-using-the-equalizer-settings
63. Bose, Too little bass or too much treble: https://support.bose.com/s/article/quietcomfort-ultra-earbuds-too-little-bass-or-too-much-treble-from-product
64. Sonos, Adjust the bass, treble, balance and loudness: https://support.sonos.com/s/article/2850
65. Sonos Community, Advanced EQ settings (hidden PEQ via Trueplay): https://en.community.sonos.com/controllers-software-228995/advanced-eq-settings-6872124
66. Apple, Set headphone accommodations for AirPods: https://support.apple.com/guide/airpods/devcd05671ab
67. AutoEq README (fork mirror; preamp, "10 filters very good, 5 can be enough"): https://github.com/chaertian/AutoEq
68. Graphic vs parametric EQ trade-offs: https://www.prosoundweb.com/?p=44853 · https://audiosolace.com/parametric-eq-vs-graphic-eq/
69. Steinberg WaveLab, A/B comparisons (louder perceived as better): https://archive.steinberg.help/wavelab_pro/v12/en/wavelab/topics/audio_montage/a_b_comparisons_c.html
70. Stereophile, Level matching: https://stereophile.com/content/mark-levinson-no38s-preamplifier-level-matching

*Code findings in §3.2 come from `Sources/AdaptiveSound/EQSafetyClamp.swift`, `EQViewModel.swift`, `Models/EQPreset.swift`, `UI/EQ/EQPresetPickerView.swift` and `UI/EQ/FrequencyResponseCanvas*.swift` (read 2026-10-08). The playback values are my arithmetic from the preset formulas and are worth confirming with the S7 frequency-response sweep before acting on them.*
