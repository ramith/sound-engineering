# Re-voicing the built-in EQ presets for the honest engine (proposal)

*2026-10-10. A proposal only: the repo was only read (`feat/s10-8-eq` @ deb94e3). Everything here re-runs with
`sh run.sh` in this folder, in about 1 minute.*

**Labels.** **[M]** measured here · **[C]** a source I opened · **[O]** my opinion.

**Tools used.** The repo's own oracle (`research/eq-geq-poc/author/geq2.py`, copied to `oracle/`; 5 passes, 48 kHz);
BS.1770 on the repo's 7-track corpus (the author's 6 tracks plus a synthetic −9 LUFS master); and a replica of
`LimiterModule.h` at the decision-29 ceiling of −0.1 dBTP (Intensity 0 with the EQ On).

## 0. Why re-voice, and the rule I used

**Today's presets were voiced for the old engine, which played only a fraction of what was drawn.** The honest
engine plays them exactly, so today they would sound extreme:
- Warm is a **+10 dB** low-mid hump.
- Presence has a **+8 dB peak at 2 kHz next to a 0 dB notch at 4 kHz.** The formula's two lobes meet at zero, so
  adjacent points step by 4.1 dB.
- Clarity rises to +6 dB at 8 kHz and then falls back to 0 dB at 16 kHz.

All of this measures out [M `results/revoice.txt`, old-preset rows].

**The rule** (the evidence is in §2):
- Every preset is a **Tone-macro vector**: [Bass <150, Body 150–500, Mids 0.5–2 k, Presence 2–6 k, Air >6 k].
- It is evaluated through the app's own raised-cosine Tone weights (`EQToneRegion`: 1-octave C¹ crossovers at
  150/500/2000/6000 Hz) at the nominal ISO centres, and rounded to 0.1 dB.
- Every preset is therefore a smooth, low-order shape with no narrow peaks. The largest step between adjacent points
  is 2.5 dB, across a 1-octave crossover.
- Every preset can be described in the Tone card's own words, e.g. "Warm = Bass +3, Body +2, Presence −1.5,
  Air −2".
- Magnitudes stay small: bass lifts ≤ +5 dB, cuts ≤ 2 dB, treble lifts ≤ +3.5 dB.
- A preset sets the *base*. As decided, choosing a preset still resets Tone to 0.

The plots show the old curve as drawn (orange) against the new curve as played (teal), with the new points in white:
`png/all_presets.png`, plus one PNG per preset in `png/`.

## 1. The presets

Each preset gives its intent, its Tone vector and its 31 points (dB, ISO order 20 Hz … 20 kHz). The played curve
is measured at 48 kHz [M].

### Flat
**Intent:** no change; the recording as it is.
**Points:** all 0.0.
**Played:** bit-exact identity.

### Presence
**Intent:** voices and lead instruments step forward, with a little more bite.
**Tone:** Presence +3.5, Air +1.
**Points:** `0.0 ×19, 0.3, 1.8, 3.2, 3.5, 3.5, 3.2, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0`
**Played:** max centre error 0.020 dB; peak +3.51 dB (3.15–4 kHz); `png/Presence.png`.

### Clarity
**Intent:** cleaner and more open: a touch less boxiness, a touch more top.
**Tone:** Body −2, Presence +1.5, Air +3.
**Points:** `0.0 ×8, −0.3, −1.3, −2.0, −2.0, −2.0, −1.8, −1.0, −0.1, 0.0, 0.0, 0.0, 0.1, 0.8, 1.4, 1.5, 1.5, 1.7, 2.4, 3.0, 3.0, 3.0, 3.0, 3.0`
**Played:** error 0.014 dB; +3.07 dB at the top and −2.02 dB at 200–315 Hz; `png/Clarity.png`.

### Warm
**Intent:** fuller and softer; a cosy, darker balance.
**Tone:** Bass +3, Body +2, Presence −1.5, Air −2.
**Points:** `3.0 ×8, 2.9, 2.4, 2.0, 2.0, 2.0, 1.8, 1.0, 0.1, 0.0, 0.0, 0.0, −0.1, −0.8, −1.4, −1.5, −1.5, −1.6, −1.8, −2.0, −2.0, −2.0, −2.0, −2.0`
**Played:** error 0.015 dB; +3.08 / −2.04 dB; `png/Warm.png`. It replaces the old +10 dB hump, which, made loudness-neutral, plays as a 7–8 dB treble cut [M §3].

### Bass & Treble (stable id `Loudness`; rename in §4)
**Intent:** punchier and livelier, the classic "smile". It also suits low-volume listening until S14 does that
properly.
**Tone:** Bass +5, Presence +1, Air +3.5.
**Points:** `5.0 ×8, 4.3, 1.8, 0.1, 0.0 ×8, 0.1, 0.5, 0.9, 1.0, 1.0, 1.3, 2.5, 3.5, 3.5, 3.5, 3.5, 3.5`
**Played:** error 0.028 dB; peak +5.14 dB, below 100 Hz; `png/Bass_and_Treble.png`.

### Vocal
**Intent:** singing and speech come through clearly, with less low-end mud under them.
**Tone:** Bass −2, Body −1.5, Mids +2, Presence +3.
**Points:** `−2.0 ×8, −1.9, −1.7, −1.5, −1.5, −1.5, −1.2, 0.2, 1.8, 2.0, 2.0, 2.0, 2.1, 2.5, 2.9, 3.0, 3.0, 2.6, 1.2, 0.1, 0.0, 0.0, 0.0, 0.0`
**Played:** error 0.018 dB; +3.01 dB at 2.5–4 kHz, −2.06 dB in the bass; `png/Vocal.png`. Unlike Presence (which only lifts 3–6 kHz), Vocal lifts 1–4 kHz *and* cuts what masks the voice underneath.

### Bass Boost (replaces Studio's slot; see §4)
**Intent:** deeper bass for small speakers or bass lovers; everything else untouched.
**Tone:** Bass +5, Body +1.
**Points:** `5.0 ×8, 4.5, 2.4, 1.1, 1.0, 1.0, 0.9, 0.5, 0.1, 0.0 ×15`
**Played:** error 0.026 dB; peak +5.14 dB; `png/Bass_Boost.png`. Tapering 20/25 Hz changed nothing measurable (limiter GR 2.73 → 2.71 dB), so it stays a plain shelf [M].

### Alternative for the 7th slot: Bright
**Intent:** airier and a little leaner.
**Tone:** Bass −1, Presence +1, Air +3.
**Points:** `−1.0 ×8, −0.9, −0.4, 0.0 ×9, 0.1, 0.5, 0.9, 1.0, 1.0, 1.3, 2.2, 3.0, 3.0, 3.0, 3.0, 3.0`
**Played:** error 0.015 dB; `png/Bright.png`.

**Accuracy summary.** Every new preset plays within **0.03 dB** of its points at the centres. The played curves
overshoot by at most +0.14 dB between centres [M]. Smooth shapes are where the engine is nearly exact; the worst
cases were jagged commands at 0.44 dB.

## 2. Evidence for the magnitudes

**Olive, *Acoustics Today* 18(1), Spring 2022** [C, pp. 61–65 opened]:
- **Bass preferences cluster in three classes** (p. 63):
  - "Class 1 includes most listeners (64%) who prefer headphones that closely comply with the Harman target";
  - "Class 2 listeners (15%) prefer the Harman target with 4-6 dB more bass";
  - "Class 3 listeners (21%) prefer the Harman target curve with 2 dB less bass".
- **The bass presets sit inside the measured spread.** Bass Boost and Bass & Treble are +5 dB, the middle of
  Class 2's 4–6 dB. No preset cuts bass by more than 2 dB, matching Class 3.
- **Too much bass alienates many listeners.** Olive warns that "adding too much bass beyond the Harman target may
  alienate many listeners", and that only 4 % of women want more bass (p. 63). That is why +5 is the ceiling and
  bass appears in only three presets.
- **Taste, age and programme move bass and treble.** Preferred levels "were influenced by several factors, including
  the music program … age, gender, and prior listening experience". Older listeners (55+) preferred "significantly
  more treble and less bass" (pp. 61–62). That supports a treble-forward option (Clarity, and the alternative Bright)
  and modest treble lifts of +3 to +3.5 dB.
- **Simple controls are the recommended personalisation.** "A simple solution for headphone personalization is to
  provide a simple bass and treble control" (p. 62). Presets built from the Tone macros are exactly that kind of
  control, pre-set.
- **Smooth shapes are favoured.** The Harman preference model predicts ratings from "the standard deviation and the
  absolute slope of the error curve" (p. 65), with r = 0.86. Narrow peaks and notches inflate the standard deviation,
  so smooth, low-order deviations are what listeners tolerate. That is why the old Presence notch goes [C, my
  inference].

**Other players** [from `eq-market-research.md` and `players-implementation.md`, both on the branch]:
- **Same names elsewhere.** Apple Music ships "Bass/Treble Booster/Reducer" and Sony ships "Bright, Bass Boost,
  Vocal, Speech". So Bass Boost, Bright and Vocal are familiar to users.
- **Genre-named presets fare badly.** Macworld calls them "hit or miss", and VOX says its names are "only for
  identification". Descriptive intents are better.
- **Plateau presets over-sum.** eqMac's Bass sets 3 bands to the same gain, and in an uncompensated cascade that
  over-sums.
- **No per-band values were published** in any source we hold. Apple's values are not in a readable resource in
  Music.app (checked), and a web search found none.
- So the magnitudes rest on Olive's data, not on copying another player [O].

## 3. Loudness: what each preset does to level, and to the limiter

**Loudness change.** BS.1770 integrated change per track, in dB [M]. The loudness-neutral gain cancels it, so the
user never hears the change as level. It does show how hard a preset pushes energy around:

| Preset | old rec. | band | gen band | gen cinem. | gen folkpop | remaster | LOUD-A | max |
|---|---|---|---|---|---|---|---|---|
| **OLD Warm** | +7.26 | +7.42 | +7.37 | +8.39 | +8.35 | +7.28 | +7.41 | **+8.39** |
| OLD Presence / Vocal / Clarity | up to +3.59 / +3.26 / +2.02 | | | | | | | |
| NEW Presence | +1.10 | +1.06 | +1.05 | +0.21 | +0.35 | +1.10 | +1.07 | +1.10 |
| NEW Clarity | −0.04 | −0.07 | +0.33 | −0.39 | −0.17 | −0.04 | −0.07 | +0.33 |
| NEW Warm | +0.89 | +1.14 | +1.43 | +1.60 | +2.02 | +0.87 | +1.14 | +2.02 |
| NEW Bass & Treble | +1.29 | +1.70 | +2.81 | +2.29 | +3.05 | +1.22 | +1.69 | +3.05 |
| NEW Vocal | +1.08 | +0.84 | +0.38 | +0.11 | −0.72 | +1.10 | +0.84 | +1.10 |
| NEW Bass Boost | +1.35 | +1.77 | +2.59 | +2.33 | +3.06 | +1.28 | +1.77 | +3.06 |
| NEW Bright (alt.) | +0.14 | +0.07 | +0.23 | −0.12 | −0.08 | +0.15 | +0.07 | +0.23 |

**Limiter work at Intensity 0** (EQ → limiter at −0.1 dBTP), on two synthetic loud masters [M]:
- **LOUD-A** (band excerpt, −9.2 LUFS, HF-poor): every new preset is easy. GR ≤ 2.15 dB, GR > 1 dB for ≤ 4.5 % of the
  time, never > 3 dB, On − Off ≥ −0.36 dB.
- **LOUD-B** (generated folkpop, −10.1 LUFS, dense and HF-rich): the work is sustained. Flat itself has GR 1.21 dB.

| LOUD-B | GR max | time GR > 1 dB | time GR > 3 dB | On − Off |
|---|---|---|---|---|
| NEW Warm | 1.19 | 2.6 % | 0 | −0.50 |
| NEW Presence | 2.29 | 11.8 % | 0 | −0.61 |
| NEW Vocal | 3.58 | 29.7 % | 0.3 % | −0.94 |
| NEW Bright (alt.) | 3.48 | 36.4 % | 0.7 % | −1.10 |
| **NEW Clarity** ⚑ | 3.52 | **43.1 %** | 0.8 % | −1.21 |
| **NEW Bass Boost** ⚑ | 2.73 | **48.3 %** | 0 | −1.24 |
| **NEW Bass & Treble** ⚑ | 2.90 | **51.8 %** | 0 | −1.42 |
| OLD Clarity / OLD Vocal | 3.25 / 3.53 | 30.4 % / 25.6 % | 0.5 / 0.7 % | −1.02 / −0.89 |

**Flagged (⚑): Bass & Treble, Bass Boost and Clarity.**
- On a dense loud master at Intensity 0, they keep the limiter about 1–2 dB busy for roughly half the time. The peaks
  stay ≤ 2.9–3.5 dB and almost never exceed 3 dB.
- On ends up about 1.2–1.4 dB quieter than the bit-perfect Off.
- This is the decision-29 trade-off: loudness-neutral EQ on a master with no headroom. It is not a fault of the
  shapes.
- **Smaller lifts only help partly** [M `results/variants.txt`]:

  | Variant | time GR > 1 dB |
  |---|---|
  | Bass Boost +5 / +4 / +3 | 48 % / 35 % / 24 % |
  | Bass & Treble 5/3.5 → 4/3 | 52 % → 45 % |
  | Clarity with Air +3 → +2 | 43 % → 27 % |

- **Recommendation:** keep the proposed magnitudes, which are audible and evidence-sized. Let the founder's
  loud-master check (§5, step 6) decide. The +4 bass and Air +2 variants are the fallbacks [O].
- Above Intensity 0, the normaliser brings everything to −16 LUFS and the limiter is nearly idle: ≤ +1.2 dB on
  ≤ 0.5 % of frames [M, SOTA review v1].

## 4. Names

**"Loudness" → "Low Volume": I recommend no. Rename it "Bass & Treble" and keep the id `Loudness`.**
- "Low Volume" ties the preset to listening *level*. That is exactly S14's level-dependent loudness compensation
  (the ISO 226 contour difference).
- Once S14 ships, a static "Low Volume" preset would *double* the bass and treble lift at low levels, and two
  controls would claim the same job.
- A shape name never collides. It stays a valid taste preset, the classic smile, after S14. Apple's own "Loudness"
  preset is the same shape.
- The id stays `Loudness` (persisted); only `displayName` changes, as `EQBuiltInPreset` already provides.

**"Studio": recommend change.**
- Its stated intent, "near-flat reference with a subtle air shelf like studio monitors", is not what it does: it was
  +2 dB above 8 kHz.
- "Flat" *is* the reference. Under the old engine Studio played about nothing, so no one relies on its sound.
- **(A, recommended) Bass Boost in this slot.** It is the one adjustment Olive's data says a real segment wants
  (15 % want +4–6 dB); Apple and Sony both ship it; and our set lacks a pure bass option (Warm also touches body and
  treble). Because the meaning changes, use a **new stable id** `BassBoost` and decode a stored "Studio" as `Flat`,
  which is what Studio users actually heard (the EQ0 migration/alias pattern; the code is the engineer's call).
- **(B) Bright (Bass −1, Presence +1, Air +3).** This serves the 55+/Class-3 preference for more treble and less
  bass. Clarity already covers most of that ground.

**The other names stay:** Flat, Presence, Clarity, Warm and Vocal are descriptive, matching the market research's
advice against genre names.

**Engineering note.** PRESET-06 pins `EQBuiltInPreset.points` to the C++ gate's `kEqPresetCurves` table
(`Tests/EqDesignerTests.inc`). Re-voicing must update both. The gate's preset bounds (≤ 0.2 dB) will pass with a wide
margin (≤ 0.03 measured).

## 5. The founder's 10-minute listening check

**Setup.**
- Your usual headphones, at your normal level.
- Enhanced path with **Intensity 0**. This isolates the EQ, Off is bit-perfect, and it is the path where the limiter
  works hardest.
- **Hold-to-Compare** hears the song without the EQ at the same loudness. Let go to return.
- Use four tracks you know well:
  - **V:** a close-miked vocal + acoustic track;
  - **B:** a dense band/rock mix;
  - **L:** a modern loud master with deep bass (pop/EDM, around −8 LUFS);
  - **O:** the old recording you care about (`research/reimagine-poc/data/seetha_excerpt.wav` will do).

| Min | Track | Preset(s) | What to listen for (hold Compare 2–3 times each) |
|---|---|---|---|
| 0:00 | V | Flat → **Vocal** → **Presence** | Vocal: are the words easier to follow, and is the low mud gone without thinning the voice? Presence: does the lead step forward without "s" or "t" harshness? Both should sound the same level as Compare. |
| 2:00 | B | **Clarity** | Less boxy and more open. Listen for cymbal splash or edge on the top, and for any loss of guitar body around 250 Hz. |
| 3:30 | B | **Warm** | Fuller and softer, but not muffled or boomy. Does the snare still have snap? |
| 5:00 | B → L | **Bass & Treble** | Livelier, the smile. On L, listen for pumping or squashing in the beat; that would be the limiter. Compare should not feel louder. |
| 6:30 | L | **Bass Boost** ⚑ | Deeper bass without boom. On a loud master, is the kick still punchy or flattened? If you hear it flatten, use the +4 dB fallback (§3). |
| 8:00 | O | **Warm**, then **Clarity** | The old recording: does Warm hide the hiss, and does Clarity open it up without exposing the noise floor? |
| 9:00 | any | **Bright** (only if you want the alternative) | For the 7th slot: Bass Boost or Bright? |
| 9:30 | — | — | For each preset, mark *too little / right / too much*, and whether you would use it. |

**Pass criteria** [O]:
- Each preset's effect matches its one-line intent.
- None sounds harsh, boomy or squashed.
- Compare never sounds louder or quieter. The level match is within 0.11 dB on the corpus; short-term variation
  within a song is inherent.

---

**Path:** `/private/tmp/claude-501/-Users-ramith-code-sound-engineering/737ceb91-aaa1-4ae6-bf56-9f296592de83/scratchpad/eq-revoice/revoice-proposal.md`

**Summary**
1. **Flat:** 0 dB, unchanged.
2. **Presence:** Presence +3.5, Air +1; peak **+3.5 dB** at 3.15–4 kHz (was a +8 dB peak with a 4 kHz notch).
3. **Clarity:** Body −2, Presence +1.5, Air +3; peak **+3.0 dB** above 8 kHz (was +6 dB); ⚑ loud masters.
4. **Warm:** Bass +3, Body +2, Presence −1.5, Air −2; peak **+3.0 dB** (was a +10 dB hump).
5. **Bass & Treble** (rename of "Loudness", id kept; "Low Volume" not recommended because of S14): Bass +5, Air +3.5; peak **+5.0 dB**; ⚑.
6. **Vocal:** Bass −2, Body −1.5, Mids +2, Presence +3; peak **+3.0 dB** (was +6 dB).
7. **Bass Boost** (replaces Studio, new id, stored "Studio" decodes as Flat): Bass +5, Body +1; peak **+5.0 dB**; ⚑.
8. **Alternative 7th slot, Bright:** Bass −1, Presence +1, Air +3; peak **+3.0 dB**.
9. Every preset plays within 0.03 dB of its points. Magnitudes follow Olive/Harman: bass ≤ +5 (Class 2: 4–6 dB), cuts ≤ 2 (Class 3), smooth Tone-macro shapes.
10. ⚑ At Intensity 0 on a dense loud master, the bass presets and Clarity keep the limiter about 1–2 dB busy for about half the time (On about 1.2–1.4 dB under Off); the fallbacks +4 bass and Air +2 cut that to 27–45 %.
