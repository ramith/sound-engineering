# EQ tab redesign: design note

*ui-designer · 2026-10-08 · uses the `macos-design` skill, the market research (`market-research.md`: 23 products, 70 sources) and the audio-dsp check (measured through the production coefficient code; calculation and measurement agree within 0.007 dB). Renders are in `renders/` (dark + light, 1000×720 and 880×640), the compare sheets are `renders/compare-*.png`, and the throwaway prototype is `prototype.patch` (worktree branch `eq-redesign-proto`, nothing committed).*

**In one paragraph.** Today's EQ is inelegant mostly because **it does not play what it shows**. The look comes second. The graph draws 31 dots and a smooth line, but the engine plays one or two bells, after a safety clamp that shrinks most presets to a tenth or a third of what's drawn. Two of its features are also write-only (saved presets, per-device memory). An elegant EQ for a listener is a graph that tells the truth, with a few named handles you drag directly, and details only on demand.

**Recommendation:**
- **R1:** ship the honest version of today's screen. It keeps today's arrangement and fixes the sound engine's safety rule (render `r1`).
- **First wave after R1, merged with S12:** **Concept A, "The Lens"**, with five named tone points that the engine plays exactly.

---

## 1. Diagnosis: what makes today's EQ inelegant

**1. The picture and the sound disagree. This is the root, and the DSP check measured it.**

| Preset | Drawn peak | Plays |
|---|---|---|
| Warm | +10 dB | **+0.7 dB** |
| Presence | +8 | +2.8 |
| Clarity | +6 | +1.7 |
| Vocal | +6 | +1.6 |
| Loudness | +4 | +0.8 |
| Studio | +2 | +2.0 |

The sheet fixture's own curve (+6 / −4 / +3.5) plays +2.8 / −1.8 / +1.6. Even the *cut* is shrunk, and a cut is never a hearing hazard. Three layers stack up:
- **The clamp.** `EQSafetyClamp` scales every band once the *sum of 31 dB values* passes +12. That metric is unsound: a +3 dB broadband lift plays +0.0 dB, yet a single +12 dB band passes untouched. It was written for the natural-language tuning layer, which has since been cut.
- **The fitter.** `fitBiquadCascade` plays one bell per same-sign run, at the run's largest band, with a gain-derived Q. A bass lift becomes a bell at 20 Hz, and Bass+Body merge into one bell.
- **The drawing.** The line is a smoothed straight-line join of the *pre-clamp* dots, so it is neither the clamped curve nor the played one.

The market punishes exactly this. SoundSource 6.1.1 shipped presets that did half their boost.

**2. Two features are write-only.**
- "Save as Custom…" saves presets that never appear in the Preset menu.
- Nothing ever writes `outputPresetMap`, so per-device recall, and its banner, can never fire.

**3. Density without precision.** 31 equal dots, 8 pt wide at a ~29 pt pitch, promise per-band control that the engine throws away. The drag "brush" also pulls ±2 neighbours, so it behaves like painting, not like moving handles.

**4. Jargon and hierarchy.**
- The leftmost, most prominent control is "Interpolation: Smooth Curve | Discrete Steps". It is a brush-width setting, not interpolation.
- The preset menu, which is a listener's main entry point, comes second and is small.
- "Save as Custom…" is disabled until you edit, so it reads as a dead button. "Custom" is a menu item that does nothing.
- There is no On/Off, no Reset, no Compare, and nothing tells you whether the EQ is even on.

**5. The graph itself.**
- The axis spans ±20 dB but edits stop at ±12, so **40 % of the height is unreachable**.
- There are only four frequency labels ("20Hz", no space; the analyzer writes "20 Hz") and no plain-word regions.
- There is no readout while dragging (a top Spotify complaint), and no sign of the music.

**6. Light and dark.**
- The graph sits on a flat `card` fill, not the lens.
- The teal curve on the light card is **2.52:1**, which fails 3:1 for non-text. F3's R4-EQ-02 already targets this.
- There is no glow yet (F1 adds it).

**Keep:**
- the single shared plot map and the log axis;
- persisting at drag end;
- the descriptive preset names;
- last-setting restore;
- the arrow-key band cursor and the VoiceOver-adjustable per-band elements. The research found no competitor that documents either.

## 2. Principles for a listener's EQ (not a DAW)

1. **Show what plays.** The solid curve is the response computed from the actual filters. Handles are your targets. Any gap between them is visible, never hidden.
2. **Few handles with clear roles, in listener words:** Bass · Body · Mids · Presence · Air. This is Logic's fixed roles with Pro-Q's direct manipulation, and Q is never shown.
3. **The graph is the editor.** Numbers and width appear on hover or selection only (progressive disclosure).
4. **Calm defaults.** Flat is a quiet line. Only the selected point glows (dark only), and the music sits behind as a faint silhouette.
5. **Safety you can see, never a silent veto.** Automatic headroom is shown as a number. If a ceiling ever holds a boost, the ceiling and the requested shape are drawn.
6. **Reversible and comparable:** On/Off, Reset, and a loudness-matched Compare (louder always sounds "better").
7. **The EQ belongs to the output.** Per-device memory is visible and assignable.
8. **One glass grammar.** Lens, badge, panel and pill roles; existing tokens only (light is frozen).

## 3. The honest graph (shared by R1 and every concept)

**What it draws:**
- the lens role, at ±12 dB with a 3 dB margin;
- plain-word regions (SUB · BASS · LOW MIDS · MIDS · PRESENCE · AIR) and numeric ticks in the analyzer's mono tertiary;
- the analyzer frame as a smoothed silhouette in `SpectrumRamp` at 8–11 % alpha;
- the played curve and its area wash in `accentFill` (dark #29B6A4 is 6.8:1; light #148979 is 4.3:1, so R4-EQ-02 passes with no new token);
- for a selected point, its own contribution as a soft fill.

**The safety ceiling** is drawn in the existing amber `meterHot` / `meterHotText`. **The selected point's glow** uses `sliderGlowDark`, dark only (grammar rule 6).

**What it needs from the engine** (no Swift copy of the fitter):
- the played response, read from the real coefficients;
- the headroom value.

## 4. Options

### R1: the honest version of today's screen (`r1`, `r1Menu`; `r1Clamped` shows the "truth only" variant)

**Layout.** Every element stays in today's place; this is a restyle under §C. The graph moves onto the lens and grows to fill (decision 3). The bar keeps three items:
- **an Equalizer On/Off switch in the Interpolation slot** (a one-line §C exception, like the playlist Move items);
- the Preset pill;
- Save as Preset… as the teal pill.

**The Preset menu** gains:
- "My Presets";
- "Use on MacBook Pro Speakers" ✓ (per-device memory, with no new on-screen element);
- "Save Current as Preset…" and "Delete Preset ▸".

**Graph.** Your 31 settings show as small hollow dots, and the line is what plays. A readout ("1 kHz · set −4.0 · plays −4.0") follows the cursor band, with "Headroom −6.0 dB" at the top right. Freehand drag and the keyboard/VoiceOver band editing stay as they are. "Smooth" becomes the only brush.

**Engine.** Delete the sum clamp and add **automatic headroom** (preamp = −max of the played response, carried in `EQParams.masterGainLinear`, which is already ramped at 32 ms). Re-voice the 7 presets to sane depths (≤ +6 dB) and rename **Loudness → Low Volume**, because S14's loudness compensation will collide with that name. The greedy fitter stays, so its error shows honestly as dot-to-line gaps, mostly at the band edges.

**Cost:** 11 points for the EQ, against 3 planned.

| Item | Points |
|---|---|
| F3 (planned) | M 2 |
| F4 (planned, becomes the On/Off swap) | S 1 |
| Auto-headroom, replacing the clamp (DSP) | M 2 |
| Played-curve read-back + drawing | M 2 |
| On/Off | S 1 |
| My presets + Delete | S 1 |
| Use on this output | S 1 |
| Preset re-voice + founder listening | S 1 |

Sprint F grows from 6 to about 14, or splits into F (Settings + EQ restyle) and F′ (EQ honesty, 8).

### Concept A: "The Lens" (`conceptA`, `conceptAStates`). Recommended after R1. Keeps decision 3.

**Layout.**
- The lens fills the height.
- A readout strip inside its top edge shows the selected point ("Mids 1 kHz −3.5 dB Medium") and "Headroom −5.0 dB".
- One bar under the graph: Equalizer switch │ preset pill ("Warm · edited") │ output chip (📌 MacBook Pro Speakers) ··· Compare · Reset · Save….

**Interaction.**
- Five tone points sit on the played curve: Bass (low shelf ~90 Hz), Body (bell ~250 Hz), Mids (~1 kHz), Presence (~3 kHz) and Air (high shelf ~10 kHz).
- Drag up and down to boost or cut; drag sideways to move the point within its zone.
- Width changes with the scroll wheel or ⌥-drag, with gain-Q coupling, and is shown only as Narrow/Medium/Wide.
- Hovering shows the frequency and gain. Double-click resets a point.
- Presets are point lists; "edited" marks any change.
- **Safety** (render `conceptAStates`): when overlapping boosts would pass +12 dB, the played curve stops at an amber dashed ceiling, the requested shape is ghosted, and the strip says "Held to +12 dB for hearing safety".

**Keyboard and VoiceOver.**
- Tab focuses the graph.
- ←/→ moves to the next point (5 stops, not 31). ↑/↓ changes gain by ±0.5 dB (⇧ for ±3). ⌥←/→ moves frequency by ⅙ octave. ⌥↑/↓ changes width.
- `.onDeleteCommand` resets a point (`.onKeyPress(.delete)` is dead on macOS).
- Each point is an adjustable element ("Bass, plus 3 decibels, 90 hertz, shelf"), with custom actions: Higher/Lower frequency, Wider/Narrower, Reset.

**Light and dark:** existing tokens only (renders in both).

**Engine:** needs a parametric realizer (**E2**, below). Points sampled at 31 bands and fed to today's fitter miss by **2.5–3.4 dB** on simple presets (my harness runs the real C++ fitter; Warm's Body bump is lost entirely). So the research's "no DSP change" shortcut does not hold.

**Cost (UI):** about 9 points. Add E2 (3). S12 already budgets parametric + A/B.

| Item | Points |
|---|---|
| Point editor (drag, width, hover, readout) | L 3 |
| Keyboard + VoiceOver | M 2 |
| Preset model as point lists, plus migrating saved 31-band customs | M 2 |
| Reset + Compare UI | S 1 |
| Ceiling display | S 1 |

### Concept B: "Sound first" (`conceptB`). Challenges decision 3.

**Layout.**
- A row of preset **cards** (mini curve, name, one-line description; "Late Night" is mine).
- Under it, a **Tone** panel with five bipolar carved sliders, beside a compact "What you'll hear" lens.
- A bar: Compare · Use on output ··· Fine-tune… (which opens A's editor) · Save as Preset….

**Interaction.** Pick a card, then nudge the tone. The graph is feedback, not the editor.

**Why it's not my pick:**
- It shows the same five values twice, as sliders and as graph points.
- It demotes the graph, which is the market's elegance marker.
- It needs a new bipolar `CarvedGroove` variant.
- The cards truncate at 880 pt.

**What to borrow:** the cards' mini-curve thumbnails, as glyphs in A's preset menu and rail.

**Cost:** about 10 points (cards M 2, tone panel + bipolar slider M 2, compact lens S 1, preset model M 2, plus E2 3). It rises to about 16 if Fine-tune includes A's editor.

### Concept C: "Profiles" (`conceptC`). Twin-Panels grammar.

**Layout.**
- A Library-style rail card with three sections:
  - Equalizer + switch, then Presets (curve glyphs) and My Presets;
  - **Outputs**: each device with its EQ ("MacBook Pro Speakers · Warm · playing"; "AirPods Pro · Fit (AutoEq) + Flat");
  - nothing more; the rail is navigation only.
- A detail card holds the title ("Warm · Edited · used on MacBook Pro Speakers"), Compare · Reset · Save, A's lens, and a numeric strip for the selected point (Frequency, Gain, Width capsule switch).
- Decision 3 holds inside the card.

**Assessment.** This is the right **R2 shape**, once S13 adds per-device correction layers that the graph draws under your taste curve. Before S13 the Outputs section is half-empty.

**Cost:** about 17 points (rail + output assignment + rename/delete M 2 + M 2, the editor about 8, the fields S 1, the correction display S 1, plus E2 3). It also assumes S13's correction engine.

### Engine work (DSP, estimated separately; owner: audio-dsp)

| ID | Work | Size | Needed by |
|---|---|---|---|
| E0 | Delete the sum clamp; automatic headroom (−max played response) off the audio thread via `masterGainLinear`; new oracles replace CLAMP-01..03 | M 2 | R1 |
| RB | Read-back of the played response from the real cascade, for drawing | M 2 | R1, then every concept |
| E2 | Parametric realizer: bells and RBJ low/high shelves from filter specs (≤10 now; a correction layer later), FR oracle. This is S12's core. | L 3 | A, B, C |
| E1 | Accurate cascade graphic EQ (Välimäki & Liski 2017), `kMaxBiquads` 10 → 31+, CPU check at 8 ch / 192 kHz | L+ ≈ 4 | Only if freehand 31-band drawing survives |

**Questions for the DSP agent:**
- **Coefficient changes during a 60–120 Hz drag.** Today's per-block swap keeps the filter state, but the greedy fitter's bells *jump* when runs split. E2 is topology-stable; does it still need coefficient interpolation?
- **E2's cap.** E2 should take ≤10 taste + ≤10 correction filters. Is 20 biquads a sound cap?
- **Bypass level jump.** How do we level-match On/Off so it isn't a loudness jump?

## 5. Recommendation

- **R1.** Under §G triage, an EQ that plays a tenth of what it shows is "a broken function", and the coordinator's and my reading agree. In my view it is an R1 blocker. So R1 is the honest EQ (`r1`):
  - the restyle;
  - ±12 axis;
  - the played curve, the dots and Headroom;
  - On/Off in the Interpolation slot;
  - My Presets, Delete, and "Use on this output";
  - E0 + RB;
  - re-voiced presets.
  
  That is about **+8 points**. It changes how presets *sound*: they become audible at their drawn depth. So it needs the founder's ten-minute listening check.
- **First wave after R1, merged with S12: Concept A on E2.**
  - It keeps decision 3 (the research agrees) and is the smallest arrangement change.
  - It borrows B's mini-curve thumbnails for the preset menu.
  - It adds Reset, the loudness-matched Compare (S12) and rename/delete.
  - **Retire the 31-band freehand drawing.** Keeping it honest costs E1 (about 4 points) for a gesture the market shows is rarely faster. Its keyboard and VoiceOver strengths carry over to the points.
- **R2 (with S13).** Graduate to C's rail when per-device correction layers make Outputs worth a section. Until then, A's output chip opens a small popover listing the outputs.

**Does the DSP finding change the recommendation?** It sharpens it in three ways:
1. The engine already is "a few bells", so named points are the *honest* model, not a simplification.
2. It removes the shortcut of running points on today's kernel, so wave 1 must include E2.
3. It tips freehand drawing from "advanced mode" to "retire".

## 6. Questions for the founder (recommended option first)

1. **Should today's EQ play what it shows before R1?**
   - **(A) Yes, minimum honest fix** (+8 points: auto-headroom, the played curve, re-voiced presets, On/Off, My Presets, Use on this output).
   - (B) Yes, plus an accurate 31-band engine (about +12).
   - (C) Draw the truth only and keep the clamp. It shows "Playing at 46 %" (`r1Clamped`; about +4).
   - (D) Restyle only, as planned.
2. **After R1, which editor?**
   - **(A) The Lens:** five named points on the graph.
   - (B) Sound first: cards + tone sliders.
   - (C) Profiles rail now.
3. **The 31-band freehand drawing?**
   - **(A) Retire it.**
   - (B) Keep it as an advanced mode (about +4 DSP).
   - (C) Keep it as the default.
4. **The safety rule?**
   - **(A) Automatic headroom (nothing louder than the source) plus a visible +12 dB shape ceiling.** The ceiling bounds the level jump when the EQ is switched off at a raised volume.
   - (B) Headroom only.
   - (C) Keep the sum clamp, but draw it.
5. **Rename the "Loudness" preset?** It will collide with S14.
   - **(A) Yes, to "Low Volume".**
   - (B) Keep it.
6. **Where does per-device memory live in R1?**
   - **(A) A ✓ item in the Preset menu** (no new element).
   - (B) A chip in the bar (another §C exception).

*Render caveats:*
- The native switch is drawn as a tinted replica, because offscreen renders show it untinted.
- The menu in `r1Menu` is an illustration of a system menu.
- There are no Materials.
- The music silhouette is the static fixture frame.
