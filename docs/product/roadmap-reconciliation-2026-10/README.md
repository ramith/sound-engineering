# Roadmap reconciliation — the sound features (brainstorm, October 2026)

**Status:** DECIDED 2026-10-23 — see "Decisions taken" below. The founder froze all implementation until every card was answered; the answers are recorded, and the "Roadmap changes" section is being applied to the plan (roadmap, sprint plan, backlog, use cases, requirements, architecture, known issues) so that an implementing engineer or agent can follow the roadmap with precision without reading this folder. This folder stays as the record of why.

**The guiding principle (founder, 2026-10-23).** Choices are narrowed by *how good the end product sounds to a listener* — "nice sound", as end users who are not DSP experts judge it — **not** by implementation complexity or how soon something can be delivered. So on every card the options are ranked by sound; options that sound the same are marked as ties (you are never asked to choose between them); cost and timing appear only in a one-line footnote and never in the ranking. Where an interim step is proposed, the card says what the listener loses meanwhile and whether they would notice.

**How this was made.** Four independent reviewers — a signal-chain engineer, an engineer who opened the code and manuals of Roon, JRiver, CamillaDSP, Equalizer APO, AutoEq, MPD, mpv and others, an architect, and a listener's advocate — each read the plan *and* the source without seeing the others. Their findings were merged and ranked (`technical-synthesis.md`). A product manager wrote the decisions as cards, a business analyst mapped what each answer changes in the plan, and a sound engineer checked what each option sounds like. The Fool ran a pre-mortem on the recommendations; the founder accepted all five of its failure stories. Then, under the guiding principle above, a sound engineer and a product manager each re-ranked every option purely by what the listener hears; their changes are folded in and marked.

---

## What "nice sound" means here — the listener's seven tests

Every option below is judged against these, in the listener's words:

- **Q1 Nothing sounds wrong.** No pumping, no squash, no harshness, no hollow tone, no level moving inside a song, no missing channels — and *nothing softened*: the one artifact this chain can produce on ordinary stereo music is the safety net working on a loud master, which is not pumping but drums losing their snap.
- **Q2 Nothing surprises.** The sound never changes unless I changed something, and what the screen shows is what plays.
- **Q3 Consistent.** Albums sit at one level. The same controls do the same things on every output (headphones over Bluetooth, the soundbar over HDMI, a USB DAC), and the app says in words when an output can't do one of them.
- **Q4 Full at low volume.** Late-night listening still has bass and presence.
- **Q5 Headphones sound like music in a room, not inside the head** — without artifacts, and without the *tone* changing when Spatial is switched on (a room render that also changes the tonal balance is EQ, not space).
- **Q6 The blind test.** On a blind, level-matched A/B against the untouched file — matched over *every* level change the engine adds, or the test measures loudness, not quality — anything that plays by default must be "I can't tell"; anything Enhance turns on must be "I prefer it".
- **Q7 I can say what it did.** The chip names the change in plain words. Trust rides on this as much as on the sound.

Plus the promises the founder keeps: **faithful by default** (a fresh launch plays the file as recorded), **honesty** (never claims bit-perfect when it isn't), **hearing safety**.

---

## Words used in this document

- **The processed mode (Enhanced)** — the normal path: the file passes through the sound engine, where every effect lives.
- **The bit-perfect mode (Pure)** — the file goes straight to the device, untouched. The app's own volume slider then works by turning the device's own volume down (the "volume loan"). Over Bluetooth the bit-perfect promise ends at the Mac: the link re-encodes the audio either way. *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)*
- **The sound engine** — the part of the app that processes audio in the processed mode.
- **Master Gain** — the app's own volume slider. Turn-down only. In the processed mode it is applied *after* the whole engine, so the engine never knows where it sits.
- **The safety net** — the limiter: the last stage, which stops peaks going over a ceiling, only in the instant a peak would go over, only ever turning down. Meant to act rarely. **The net working** = turning the music down on more than the odd peak; sustained work is the "flat, no snap" sound (**squashed**).
- **The ceiling** — how close to full scale the net lets peaks go: 1 dB under on Bluetooth and unknown outputs; 0.1 dB under on wired outputs when only the EQ is on.
- **True peak** — the real peak of the waveform between samples; the ceiling is measured against it.
- **dB** — the unit of level. 1 dB is about the smallest level change a listener notices on music; 10 dB sounds roughly twice as loud.
- **Loudness (the measurement)** — how loud a track feels over its length. Roon and Spotify aim at −14; ReplayGain files at −18; the sound engine's internal target today is −16.
- **Leveling** — evening out the level between tracks or albums.
- **The old auto-leveller** — a volume rider already inside the sound engine. It listens through the session and keeps nudging the level toward its target, up to 1 dB per second, anywhere from −20 to +12 dB. It is switched on in the code, nothing in the app can switch it off, and it only stays silent today because the Intensity knob is hidden at zero.
- **Loudness compensation ("the loudness button")** — when you turn the volume down your ears lose bass first; this puts some back.
- **Intensity** — the one big knob (hidden since R1.1-A) meant to blend the automatic effects in and out.
- **Clarity** — the planned automatic EQ that lifts detail hidden by other sounds, moment by moment. Also, today, the name of a built-in EQ preset.
- **Crossfeed** — a headphone effect that lets each ear hear a little of the other channel, as speakers in a room do. Shipped; stereo only.
- **The spatial render** — the planned headphone effect (S18) that simulates speakers in a room from measured head and room responses.
- **The fold** — mixing a surround file (5.1 or 7.1) down to stereo. **Coherent** = the same sound present in two channels at once, so they add up in level when folded.
- **Headroom** — the spare room between the music's peaks and the ceiling. Every boost spends it. **The peak-safe turn-down (pre-gain)** — turning a track down by exactly enough that its peaks, with every boost applied, stay under the ceiling, so the net never has to work.
- **The 12 dB safety cap** — the rule that no boost exceeds 12 dB. Today it is three separate 12 dB limits that nobody adds up.
- **Correction** — a per-headphone EQ curve that flattens a model's known tonal flaws (planned, S13). **AutoEq** is a public library of such curves.
- **Parametric EQ** — EQ bands you can place at any frequency, next to the fixed 31 points (planned, S12).
- **Compare** — the hold-to-hear button on the EQ graph: the song without your EQ, at matched loudness.
- **The status badge** — the small chip on Now Playing that names what is playing.
- **W2, "one playback owner"** — plumbing: one place owns play/pause/seek and the engine sends events instead of being polled.
- **The Engine sprint (ENG)** — studies a mature open-source engine, builds our own playback engine for the processed mode, compares the two; it rebuilds the processed path's internals.

Sprint names: **R1.1-B** (next fix sprint) · **ENG** (new playback engine) · **S14-lite** (loudness compensation) · **S12** (parametric EQ) · **S13** (headphone correction) · **S11-lite** (formats) · **S15** (masking research spike) · **S16** (Clarity) · **S17** (Intensity returns) · **S18** (spatial headphones). **R2** is the parity release after S11-lite; **R3** the thesis release after S17.

**Your gear.** Sony WH-1000XM4 over Bluetooth: ceiling −1 dB, the volume lives on the headphones, the link is lossy either way. The soundbar over HDMI: locked to 48 kHz (the engine's rate, so no hidden conversion after the engine), but the Mac cannot read or set its volume ("Set on device"). The USB DAC coming: wired, so the EQ-only ceiling is −0.1 dB; if it runs at another rate there is a conversion after the engine that nobody has measured yet.

---

## The one fact under most of this

The only leveller in the sound engine is the old auto-leveller: switched on by default, written by no code in the app, running only on the paths Intensity selects. "Leveling off" today is a side effect of Intensity being hidden at zero, not a setting. All four reviewers found this in the code; it was re-checked by hand. The day Intensity comes back, so does the old leveller — underneath whatever else was built.

---

## What ranking by sound settles

Compared with the first draft of these cards, the sound-first pass changed seven things and confirmed the rest:

1. **Leveling reaches the bit-perfect mode** (card 1). Over Bluetooth, Pure and Enhanced-with-nothing-on are the same bits into the same encoder, so leveling on the device volume in Pure sounds the same as leveling in Enhanced — and without it the mode you live in is the only one with uneven albums. *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)* It is part of the answer, not a follow-up. And the target is **−18, not −14**: under the true-peak cap every album can reach −18 while only loud ones reach −14, so the leveling is *more* even at −18.
2. **Headroom by turning down, never by limiting** (card 4). The peak-safe turn-down is one number that falls out of the true-peak measurement card 1 adds, and it comes with it in R1.1-B — because one bass boost on a loud master over Bluetooth is already squashed today, and a listener hears that against Compare now. The full ledger (per-band sum, AutoEq's preamp, the meter) follows when a second layer arrives.
3. **Two fixed rules become per-track decisions** (cards 5 and 7). The fold decides the LFE channel from the analysis (omit when it's a copy of the mains' bass, include when it's the only bass) instead of always dropping it; and the correction offer carries a level-matched hold-to-hear preview, so the better sound is heard on day one without breaking the faithful default.
4. **The loudness button is a bass tilt, not bass-and-treble** (card 3). The hearing-model numbers say a 20 dB turn-down calls for +6 dB at 100 Hz and essentially nothing above 1 kHz; the planned treble lift would add fizz. And its level reading must include everything that changes the level at the ear — leveling and the turn-down included.
5. **Enhance is per output and checkable** (card 11): the chip names what it did in the listener's words, holding it plays the file without it, and it never turns Loudness on before its reference is set.
6. **S13 stays whole** (card 6): identification plus the library buys *the right curve every time* (the right model, the ANC-on/off variant); a manual import sounds identical only for someone who already knows which file to pick.
7. **The fold's interim is justified by sound, not by cost** (card 5): today four of six channels are *dropped*, the worst sound of all, so any fold now is a large gain; the final arrangement is the target, and the interim's two losses are named — one of them (leveling computed on six channels) is fixed inside the interim by measuring the folded loudness in the same pass.

Ties the founder need not choose between: card 2 (knob vs switches), card 6 (one program vs Compare-with-menu vs S12-first), card 8 (one control vs two that grey each other out, while the greying holds), card 11 (one tap vs several), card 12 (all).

---

## Decisions taken (founder, 2026-10-23)

Answered card by card in plain-language questions with options, pros and cons. "= R" means the recommended option; "≠ R" means the founder chose differently, and that choice stands.

- **Card 12 — what proceeds now: full freeze (≠ R).** Nothing in R1.1-B starts until every card is decided and the roadmap is reconciled. R1.1-B then proceeds as one sprint (no player/sound split).
- **Card 1 — leveling (= R):** one fixed gain per track or album in the processed mode through the existing per-track gain; the old auto-leveller *removed*; Off / Auto / Album / Track (Auto = the album gain when the neighbouring track — the one just played or the next — is from the same album, else the track gain); a fixed −5 dB cut for a track of unknown loudness; our own analysis first, file tags only for a track not yet analysed; the target shown; **and** leveling in the bit-perfect mode as a cut on the device's own volume (the volume loan taught to tell its own moves from the listener's; cut-only; the soundbar excluded and told). The analysis gains a true-peak number. A gapless album takes the album gain. **Target −18 LUFS (= R).** *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)*
- **Card 4 — headroom:** the **peak-safe turn-down now, with leveling in R1.1-B (= R)** — three numbers per track from the same analysis — the leveling gain g, the loudness-neutral offset −ΔL (exists), and the cap C_cap = C_work − (track true peak + g + the curve's boost), C_work the limiter's working ceiling (the ceiling − 0.27 dB): the peak after leveling is what is protected, and the cap may be positive; the published broadband offset beyond leveling is the smaller of the two, G = min(−ΔL, C_cap), and the turn-down shown is T = G − (−ΔL) ≤ 0; compensation is exempt from the loudness-neutral offset — Compare level-matched to it; **the full ledger in S14-lite (= R)** — the per-band sum of the EQ layers held at +12 dB, one turn-down applied once before the EQ, AutoEq's preamp line replaced by the ledger, the safety net's gain reduction metered and shown; the turn-down measured from the EQ'd track's real peak as soon as the analysis can.
- **Card 5 — the fold (= R):** now, in R1.1-B: the standard fold matrix plus a per-track trim from the folded true peak in the spatial unit where truncation lives today; the folded loudness measured in the same pass so leveling is exact; a "5.1 → stereo" badge; the bit-perfect reason reads "…so Enhanced plays it, folded to stereo"; crossfeed does nothing on folded files until the fold moves and the badge says so. The final arrangement — the fold inside the engine before the one safety net, crossfeed after it, one owner of the channel layout from the decoder onward — is decided and built with the Engine sprint. **LFE per track from the analysis (= R):** include at full level per side when it carries bass the mains do not; omit when it is a copy of the mains' bass; default omit when unknown; the trim computed with that gain; two albums listened to, pass/fail, before it ships.
- **Card 3 — the loudness button (= R):** level = Master Gain + the device's own volume where the Mac can read it, against a one-time "this is my normal loud setting"; a labelled manual "Loudness amount" on an output whose volume the Mac cannot read (the soundbar over HDMI); decoupled from the Engine sprint and W2. **Form (= R):** ease the mids, never boost; the level read as "volume minus its own cut" (so no loop); **bass only** — the ISO 226 difference curve, nothing above 1 kHz; start at 50 % of the difference, the depth settled on one evening on the XM4 at a 20 dB turn-down; cap +6 dB in the bass; the level reading includes leveling and the turn-down; one "Level" card with plain names ("Even out track levels", "Keep bass at low volume") and a net-gain readout; "not in bit-perfect mode", and it says so. One check owed: whether the XM4's own buttons move the Mac's volume slider.
- **Card 6 — EQ layers (= R):** one EQ program of ordered layers — correction | taste (31 points, Tone, parametric) | compensation — designed once into one set of filters, drawn as they play, a bypass per layer; Compare keeps one meaning ("without *my* EQ"; correction and compensation stay), level-matched within 0.2 dB over every offset the program adds; a separate latching "Bypass all processing"; the existing per-output memory is the only per-device memory, extended with the parametric bands and the correction choice (the unpin-wipes-the-shared-EQ bug fixed in the same change); S16's referee emits into the program (no second filter engine); **S13 whole** — identification, the correction library (model and ANC variant), a correction layer keyed by model and separate from taste; the profile model cut to "correction + taste".
- **Card 7 — correction and spatial (= R):** opt-in per device, off on a fresh install; "auto-load" means *offer with a level-matched hold-to-hear preview, and remember*; the device class only picks the default suggestion for a never-seen output; a status-badge entry for every stage that plays.
- **Card 2 — Intensity (= R):** scales only the automatic stages — Clarity depth and room amount — as settings inside each stage, never a crossfade, never a hand-set switch; 0 = nothing automatic; both settings stay visible on their own rows; Clarity gets its own on/off and depth with a chip in S16; S16 and S17 stay separate; the blend's mid-knob level hump goes.
- **Card 8 — headphones (= R):** one "Headphones: Off / Crossfeed / Spatial" control, exclusive by construction, remembered per output; the render at the output boundary for every source width (the engine's stereo-out slot once the fold's final home exists); room amount a setting Intensity scales; the kernel's render stub retired; the older spatial design superseded; correction stays before the render; the render's responses headphone-equalised so Spatial changes space, not tone; head tracking opt-in.
- **Card 9 — one playback owner (= R):** the Engine sprint delivers the engine half (seam events carrying the track's identity, one seek, one end flag); S15 carries the transport reducer and command layer (written fallback if it cannot: the R3 sprints use only the track-identity seam event, and W2's transport half waits for its trigger bug); "S14's adaptive half" is no longer a funder; S14-lite loses "Depends on: ENG"; the Engine sprint's acceptance carries the R1.1 behaviours to re-prove (the one-converter seam, seek-to-end, channel roles from labels, leveling at the seam), the below-44 kHz EQ gap (a reduced band set or a floor), and the output-side conversion measurement; the developer switch and the losing path are deleted inside the Engine sprint; agent control is a consumer of S15's command layer.
- **Card 10 — the blind test: at the end of each processing sprint only (≠ R).** No pre-S15 or pre-S18 test. The last acceptance line of S14-lite, S16 and S18 is the founder's blind, level-matched A/B on their own gear (the adaptive-tone ladder, about 23 trials, capped at 60, matched within 0.2 dB over every offset); "can't tell" is the bar for anything that plays by default, "prefer" for anything Enhance turns on; Loudness tested at the real late-night level with the reference set; Spatial against a timbre-matched reference with an artifact checklist; a stage that does not win ships off and hidden. **The "Clarity" preset's display name becomes "Detail" (= R)**, stored id unchanged.
- **Card 11 — Enhance (= R):** one switch per output that turns on the stages that won their blind test on that output; a chip that names what it did in the listener's words; holding the chip plays the file without it at matched loudness; the chip states a level change made by design ("−6 dB to match your other albums"); in the bit-perfect mode one honest line and one tap out; never shows "ENHANCED" alone; never turns on a stage that lost; never turns Loudness on before its reference is set.
- **The ceiling (= R, scopes Sprint EQ decision 29):** −0.1 dB only where the link is lossless *and* the output runs at the engine's 48 kHz (the HDMI soundbar, a 48 kHz DAC); −1 dB on Bluetooth and on any other-rate output until the output-side conversion is measured in the Engine sprint.
- **The dogfood week: no rule (≠ R).** The founder listens however they like.
- **Smaller items, taken as recommended unless the founder objects:** the −5 dB unknown-loudness cut; tags only for unanalysed tracks; the "Level" card's home is a UI call; a "Volume restored" toast when Pure hands the device volume back; crossfeed's chip and switch read the engine's bypass; one per-output question "What's plugged into this output?" so headphones on a USB DAC are treated as headphones; "held" on the graph worded as "protected"; the loudness button's caption "nudge the volume up a notch"; the Pure card's one sentence on why there are two untouched states; the council's slice catalogue annotated as a record; "two engines never ship" means the switch and the loser are deleted inside the Engine sprint; the two things called "Realizer" named apart before S16.

---

## The decisions

Each card: the question, why it matters to you, how others solved it, the options **ranked by sound** (best first; ≡ marks a tie), the sound engineer's rules, a one-line footnote on cost and timing, and the roadmap change it implies.

### Card 1 — Leveling

**The question.** Should Leveling be one fixed adjustment per track or album that *replaces* the old auto-leveller — and should it also reach the bit-perfect mode?

**Why it matters to you.** The day Intensity comes back, the old auto-leveller wakes underneath whatever Leveling you chose: two levellers at once, one drifting the level by up to 1 dB a second mid-song, regardless of "Leveling: Off". As planned, an unanalysed track gets a live guess that moves the level during the song; "Album or Track" is asked of you instead of following what plays next; the target is never shown; the same fix is scheduled in two sprints; and in the bit-perfect mode — your daily driver — nothing happens at all. *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)* A 1980s master next to a modern one differs by 6–10 dB; you notice that on every shuffle without trying.

**How others solved it.** Roon, JRiver, foobar2000 and MPD offer Off / Auto / Album / Track (Auto = the album gain when the neighbouring track — the one just played or the next — is from the same album, else the track gain). Roon applies a fixed −5 dB to tracks of unknown loudness. In bit-perfect playback MPD moves leveling onto the device's own volume; JRiver and Roon switch it off and say so.

**Options, ranked by sound.**

1. **A + C (quality-best).** One fixed gain per track or album in the processed mode; the old auto-leveller *removed*; Off / Auto / Album / Track; a fixed cut for unanalysed tracks; our own analysis first, file tags only for a track not yet analysed; the target shown, at **−18**; *and* leveling in the bit-perfect mode as a cut on the device's own volume, once the volume loan can tell its own moves from yours.
   - Wins Q1 (the level never moves inside a song; the gain is capped by the track's true peak so the net sleeps), Q3 on every path, Q6 (a constant multiply is the most transparent processing there is).
   - What you'd hear: a quiet intro and a loud chorus play exactly as mastered, only the whole album sits at your level; old and new records shuffle at one level — in both modes. In Pure the cut comes in the device's volume steps, below the ~1 dB a listener notices between tracks and never inside one; the Mac's volume indicator moves on its own at track changes (the readout must say why). The soundbar gets no leveling in Pure (the Mac can't set its volume) — the app says so.
   - Cons: quiet albums cannot be raised in Pure (cut-only) — at a −18 target almost nothing needs raising.
2. **A alone ≡ D (defer past the Engine sprint).** The same end sound in the processed mode; the bit-perfect mode has none. Loses Q3 where you listen most; honest ("Leveling off (bit-perfect)"). *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)*
3. **C alone.** Leveling in Pure only; nothing in the processed mode.
4. **B — keep the old auto-leveller as a visible "Adaptive" mode.** The intro turned up over ten seconds, the chorus slamming into the ceiling and squashed, the gain carried into the next song. Fails Q1, Q2, Q6. No mature player ships this as leveling.
5. **E — leave as written.** Two levellers the day Intensity returns; the live guess moves the level mid-song.

**The sound engineer's rules.** The old leveller is removed, not switched off. The track analysis gains a true-peak number (it has none today) so the cap is exact. A gapless album takes the album gain even in Track mode. The −18 target: no tonal difference at any target; −18 is simply the one every album can reach, so it is the most consistent; the volume knob sits ~4 dB higher, which costs nothing on the XM4 or a DAC with its own volume.

**Footnote — cost and timing.** A: a few days beyond the story as sized; touches the engine's path selection; may re-baseline the bit-exact reference test. C: about a week; it changes the Pure volume loan's rule, which the parked hardware check covers — your word needed on doing it before the USB DAC arrives (it can be verified on the XM4 now). *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)*

**Roadmap change.** R1.1-B's leveling row rewritten (Off/Auto/Album/Track, the old leveller removed, −18, unknown-loudness cut, tags for unanalysed tracks, the Pure cut on the loan); the duplicate scheduling in S12 deleted; "loudness-comp" deleted from S17's knob; "sample-accurate at the seam" read as "at the seam as the engine counts it" until the Engine sprint.

---

### Card 2 — Intensity (S17) and Clarity (S16)

**The question.** When the Intensity knob comes back, what should it control: only the automatic effects (Clarity depth, spatial room amount), or also things you already switch by hand?

**Why it matters to you.** You've set crossfeed Strong, Loudness on, Leveling Album; S17 lands with Intensity at zero. One requirement says "0 = all stages bypassed" (your Loudness switch goes dark); another says the default is 100 %. The S17 row still lists crossfeed inside Intensity, contradicting your 2026-10-14 decision. Clarity runs only inside the Intensity blend, which stays hidden until S17 — so it ships into a path nobody can hear, and its A/B is skewed by a +3 dB bump the blend adds mid-knob: a knob that gets louder in the middle reads as "better" and is a lie.

**How others solved it.** Roon has no macro knob; each filter has its own switch. Pro-Q's one macro scales EQ shapes only, never level.

**Options, ranked by sound.**

1. **A ≡ B ≡ D (quality-best, a tie).** A: Intensity scales only the automatic stages — Clarity depth and room amount — *as settings inside each stage, never as a crossfade*; 0 = nothing automatic; Clarity gets its own on/off and depth so S16 is audible when it ships. B: Intensity stays hidden; every stage has its own control. D: S16 and S17 merge. Same sounds all three ways; every hand-set switch honoured (Q2); zero really is faithful.
   - Listener's refinement: keep "Clarity depth" and "Room amount" visible as their own settings, with Intensity a convenience over them — one knob that moves both means you can't have a full room with light Clarity.
   - What you'd hear: the knob changes *character*, never loudness and never your own switches. *Sound risk: none as settings; real as a crossfade (the mid-knob level hump; a hollow comb tone when a room-rendered signal is crossfaded with the dry one).*
2. **C — a visible macro that moves the other sliders.** The same sound untouched; moving it changes level and undoes hand-set switches (Q2, trust).
3. **E — leave as written.** The hump stays; Clarity inaudible in S16; your Loudness switch silently overridden.

**Footnote.** A day of document fixes now (do the S17 row and the two requirement texts regardless); a day or two of UI in S16 for Clarity's own switch and chip; D would push a merged sprint past its cap.

**Roadmap change.** S17 row: "Intensity = Clarity depth + room amount, as settings, default 0"; the requirement "0 = all stages bypassed" becomes "0 = nothing automatic; hand-set stages still play"; the 100 % default deleted; S16 row gains Clarity's own switch and chip.

---

### Card 3 — Loudness compensation (S14-lite)

**The question.** "Keep bass at low volume" has to know how loud you are listening — which volume should it follow, how deep should it go, and should it boost the bass or ease the mids?

**Why it matters to you.** It's late; Master Gain is at 0 and you turn the XM4 down with the volume keys. As planned the feature reads only the app's own slider, so it does nothing at any level you actually use. It has two definitions and two caps in the documents, a planned treble lift the ear does not ask for, and two dependencies (the Engine sprint, W2) it does not use — the device-volume reader already exists, gated to the bit-perfect mode. "Leveling" and "Loudness" are the same word to a Spotify listener and a bass boost to a receiver owner.

**How others solved it.** JRiver keys Loudness to its own volume plus a one-time reference calibration. CamillaDSP's loudness follows its fader and, when the volume sits *after* the processing (our case), eases the mids instead of boosting — no headroom spent, cannot clip. Roon ships none.

**The fact that makes this simpler.** Every form on the table is the *same tone curve* at a different height: lifted so the mids stay and the bass goes up ("boost"); dropped so the bass stays and the mids come down ("ease the mids"); or in between so the track's loudness doesn't change ("loudness-matched"). At the same final loudness at your ear, all three sound identical. They differ only in what they do to the safety net.

**Options — the level it follows, ranked by sound.**

1. **A (quality-best).** Master Gain plus the device's own volume where the Mac can read it, against a one-time "this is my normal loud setting"; on an output with no readable volume (the soundbar) a manual "Loudness amount" slider, labelled as such. Decoupled from the Engine sprint and W2. One cap. Plain names in one "Level" card with a readout of the net gain applied now. "Not in bit-perfect mode." Wins Q4 on the headphones; honest on the soundbar.
   - One check owed: do the XM4's own buttons move the Mac's volume slider? *(Unverified; a minute to check.)* If not, the caption must say "use the Mac's keys".
2. **B — a manual slider everywhere.** A warmth you dial in once; honest; a tone control wearing the loudness button's name; on the soundbar A ≡ B.
3. **C — leave as written (Master Gain only).** Does nothing at any volume you use while its switch says it's on. Fails Q4, Q2, Q7.

**Options — the form, ranked by sound.**

1. **Ease the mids, with the level read as "volume minus its own cut"** ≡ the hybrid (loudness-matched for the level reading, mid-cut for headroom). The net never wakes; no loop. The one cost: the music is a notch quieter and you nudge the volume up once (the caption should say so).
2. **Loudness-matched.** No notch; the net touches the loudest passages of loud records on the XM4's −1 dB ceiling (Q1 small).
3. **Boost.** On a loud familiar master with the headphones turned down, the net works constantly — squashed (Q1 real, Q6 lost on the records you know best).

**The sound engineer's rules.** (i) The curve is a **bass tilt only**: from the hearing model (ISO 226, computed this session) a 20 dB turn-down calls for about +6 dB at 100 Hz, +8 dB at 50 Hz, essentially nothing from 1 to 8 kHz, and barely +1 dB at 10 kHz; the planned "+3–5 dB at 8–12 kHz" would add brightness the ear does not ask for — fizz. The +4 dB treble cap is never reached. (ii) The level reading must include *everything* that changes the level at the ear: leveling's gain and the peak-safe turn-down, not only the volume — a loud master leveled down 8 dB is 8 dB quieter at the ear. (iii) Depth: start at 50 % of the hearing-model difference (about +3 dB at 100 Hz for a 20 dB turn-down), bass only; too much sounds thick and boomy, with vocals pushed back and the tone chasing the volume knob; too little sounds like an ordinary thin late-night listen. (iv) Enhance (card 11) must not switch Loudness on before its reference is set — an uncalibrated loudness button is a tone control at the wrong level.

**Before deciding (accepted from the pre-mortem):** one evening on the XM4 with the curve pre-rendered at three depths (40 / 50 / 60 %), at a 20 dB turn-down, on three familiar loud masters. The form is settled by the net; the evening settles the depth and the cap.

**Footnote.** About fits S14-lite once "waits for W2" goes; the reference step and the Level card add a few days; lifting the volume reader out of its Pure-only gate needs a regression test.

**Roadmap change.** S14-lite row: delete "Depends on: ENG" and "the adaptive half waits for W2"; "S14's adaptive half" deleted from W2's funders; the story rewritten (which volume counts per output; bass-only; one cap; the level definition; the Level card; the Pure line); the requirement's "per-device SPL calibration" becomes the one-time reference; the treble figures deleted; the "10+ listeners" test replaced by your blind ladder.

---

### Card 4 — Headroom: who adds up the boosts

**The question.** Who keeps the running tally of every boost — your EQ, a headphone correction, compensation, leveling, Clarity — so the total never silently passes the 12 dB cap and the net isn't quietly working all the time?

**Why it matters to you.** Today three separate 12 dB limits and nothing adds them; the plan adds four more boosters. With one bass boost on a loud master over Bluetooth the net already works more than a quarter of the time on the loudest records — drums losing their snap — and you hear that against Compare today. After S13 it is the auto-loaded correction spending the budget, not you. An AutoEq file arrives with its own "−6 dB preamp": apply it on top of our level-matching and corrected headphones play 6 dB too quiet; drop it and bass-heavy tracks hit the wired ceiling. Filters beyond 12 dB would be silently clamped, so the graph would lie.

**A plain fact.** The safety net protects the *signal* from clipping; it does **not** protect your ears from level. A heavily boosted, net-held signal has the same peak as the untouched file and can be far louder on average. What protects hearing today: the taste EQ is loudness-neutral by design, Master Gain only turns down, the headphones' volume is yours. What would: a real *sum* clamp.

**How others solved it.** Roon: one fixed Headroom stage first in the chain (−3 dB by default) plus a clipping light. Equalizer APO sums its preamps. Strawberry has one EQ preamp element.

**Options, ranked by sound.**

1. **A (quality-best).** One headroom ledger: the per-band sum of the EQ layers held at +12 dB; **one peak-safe turn-down applied once before the EQ** — exactly enough that the track's peaks with every boost stay under the ceiling, so the net never works; AutoEq's preamp line replaced by the ledger; the net's work metered and shown; Compare level-matched to the turn-down. The only option in which stacked boosts never put the net to sustained work (Q1) and the graph keeps drawing what plays (Q2, Q7). "Quieter by the turn-down" is the honest price of a hot master; a constant offset is far more transparent than sustained limiting.
   - What you'd hear: a loud record with a big EQ plays a little quieter instead of squashed; the graph says it *protected* the sound where the sum was held; a readout shows when the net would have worked.
2. **B ≡ C ≡ D in the failure mode** (separate budgets with the sum displayed; a +6 dB compensation budget until S16; leave as written): the net does the adding by squashing, and at best a readout tells you afterwards. They differ only in when it arrives.

**The sound engineer's rules.** The ledger has two numbers that are conflated today: a *loudness* offset (exists) and the *peak-safe* turn-down (needs the true-peak number card 1 adds). The turn-down is exact only if the analysis measures the EQ'd track's real peak rather than bounding it by the curve's biggest boost — the measured version turns down less on most tracks and is worth having. **The sound-first change:** the turn-down comes *with* card 1's true-peak number in R1.1-B (one number: ceiling − track peak − the curve's boost), because the squash exists with one boost today; the full per-band ledger, the AutoEq rule and the meter come with the first second layer (S14-lite).

**Footnote.** The turn-down in R1.1-B: a day or two on top of the true-peak number. The full ledger: about a week in S14-lite, replacing a slice the architecture's own wording makes moot; likely re-baselines the bit-exact test.

**Roadmap change.** R1.1-B's sound half gains the true-peak number and the peak-safe turn-down; S14-lite's structural slice becomes the ledger; S12's import drops the preamp line; the architecture's "cumulative clamp — not yet shipped" moves from S15–S16 to S14-lite; the roadmap's "respect the clamp, with its own headroom or a cap" becomes "the ledger sums and clamps the layers".

---

### Card 5 — The 5.1 / 7.1 fold-down

**The question.** When a surround file plays on stereo headphones or the soundbar, where should the fold happen, how is the extra level handled, and what happens to the LFE channel?

**Why it matters to you.** Today the second half of the chain simply *drops* four of six channels — the centre and the surrounds vanish — which is the worst sound on this whole list. Folding adds the centre and surrounds into each side: up to +7.7 dB on dense mixes (a vocal that lives only in the centre channel actually comes out 3 dB quieter per side; it is content present in front *and* centre or surround that adds up). A safety net placed after the fold works constantly on dense surround masters. Crossfeed is stereo-only and runs *before* the fold, so a folded album plays without it while the "XF" badge still shows. The agreed fold drops the LFE channel: on music mixes that put real bass *only* there, the bottom octave disappears — "where did the bass go?" is the push-back a listener feels hardest.

**How others solved it.** JRiver: "Output Format must be processed first". CamillaDSP folds with explicit gains. mpv: a normalised downmix (warned "too quiet") or an un-normalised one that can clip. The standard says the LFE is "often not included" — because no single level is right for both kinds of album.

**Options, ranked by sound.**

1. **The final arrangement (quality-best).** The fold inside the sound engine before the one safety net, crossfeed *after* it, a per-track trim from the folded true peak so the net is a backstop, one owner of the channel layout from the decoder onward. One net that rarely acts; crossfeed and later the spatial render work on surround albums exactly as on stereo ones (Q1, Q3, Q5).
2. **The interim** — the fold matrix plus the per-track trim in the spatial unit where truncation lives today; two nets in series (the second rarely acting); the folded *loudness* measured in the same analysis pass so leveling is exact; a "5.1 → stereo" badge; the bit-perfect reason reads "…so Enhanced plays it, folded to stereo". **≡ "turn everything down a fixed amount" with Leveling on.** What the listener loses meanwhile: crossfeed on surround albums — a crossfeed user hears their switch do nothing on a 5.1 album (the badge must not show XF). Nothing else: the second net is inaudible by design once the trim exists.
3. **A fixed turn-down (about −7.7 dB) with Leveling off.** Unsquashed, but every surround album 8 dB quieter than the stereo ones around it, and a quiet classical surround recording made quieter for nothing (Q3). Ranked above the next because a reach for the volume beats an artifact.
4. **The final home without the trim.** The net in the right place and working constantly on dense masters (Q1 real).
5. **Leave as written.** Squashed by default, two nets, XF showing when nothing plays.

**The LFE channel — a per-track decision from the analysis (sound engineer).** Omit it when it is a low-passed copy of the bass already in the mains (common film practice; including it would add that bass twice, +6 dB below 120 Hz — boomy); include it at full level per side when it carries bass the mains do not (the conservative end, still under the mixer's level); the trim computed with that gain so the net stays asleep; default when unknown: omit. Leveling is unaffected either way (the loudness measurement already ignores LFE). **Listen before it ships, pass/fail:** on the XM4, one album where the LFE has bass the mains don't and one where it's a copy, a bass-heavy passage three ways (omit / −6 dB / full).

**Why the interim is a sound decision, not a schedule one.** Any fold now is a large gain over dropping four channels. The final arrangement changes the engine's shape (surround in, stereo out) and the bus formats — the very thing the Engine sprint rebuilds — so building it once, there, is building it right, not building it later. Nothing in the interim is thrown away.

**Prototype first.** Run the folded-peak analysis over your surround albums and look at the spread of trims (one afternoon): if most sit within 0–3 dB the per-track trim is clearly right; if they cluster near 7 dB a fixed trim is nearly as good.

**Footnote.** The interim: about a week in R1.1-B's sound half (a small control path into the spatial unit, the trim, the folded-peak and folded-loudness numbers, the LFE rule). The final arrangement: with the Engine sprint, where the graph is being rebuilt anyway.

**Roadmap change.** R1.1-B's fold row rewritten (matrix + trim + folded loudness + the LFE rule + badge + Pure wording; "a safety ceiling after it" becomes "a backstop that the trim keeps asleep"); the Engine sprint's design settles the fold's final home and the one layout owner; "the Realizer owns the channel layout" and the "stage concept" deleted from S12 (they go to the Engine sprint); S18 "replaces the fold in the same slot" now means the engine's stereo-out slot; the surround known issues annotated.

---

### Card 6 — EQ layers, Compare, per-headphone memory (S12 / S13 / S16)

**The question.** Your own EQ, a headphone correction, parametric bands, imported AutoEq curves and the compensation tilt — one stack with one engine, one per-headphone memory and one meaning for Compare, or several separate things?

**Why it matters to you.** After S13 you hold Compare to judge your Warm curve and hear your headphones *uncorrected* — the wrong comparison. After S14-lite, if Compare also removes the compensation tilt, "matched loudness" is no longer true. Plugging in the XM4 would have three memories competing with no rule. By S16 three different filter engines would do one job. The S13 row says identification was "delivered early" by the EQ pins; it wasn't — pins remember *your taste* per device, they don't recognise a headphone model.

**How others solved it.** Roon: separate, re-orderable filters each with its own switch. Equalizer APO: one ordered list with a summed preamp. AutoEq exports the same correction in graphic and parametric form; its three XM4 corrections from different labs agree within about 1 dB.

**Options, ranked by sound.**

1. **A ≡ C ≡ D (quality-best, a tie in sound).** A: one EQ program of ordered layers — correction, taste (graphic + parametric), compensation — designed once into one set of filters, with one read-back so the graph draws what plays and a bypass per layer; Compare keeps one meaning ("without *my* EQ"; correction and compensation stay) and is level-matched over *every* offset the program adds, the peak-safe turn-down included; a separate latching "Bypass all processing"; the existing per-output memory is the only per-device memory, extended with the parametric bands and the correction choice (the unpin-wipes-the-shared-EQ bug fixed in the same change); S16's referee feeds this program instead of a second engine; **S13 whole** — recognise the headphones, offer the right curve (model and ANC variant), remember it. C (Compare with a menu) and D (S12 before S14-lite) sound the same; C is awkward in the hand.
   - What you'd hear: the curve on screen is the curve playing; Compare answers "is my curve helping?" on corrected headphones; one toast on plug-in; "this app knows my headphones".
2. **E — S13 narrowed to a manual AutoEq import.** Sound-identical to A *for a correctly chosen file*; what the full S13 buys is the right curve every time (an XM5 file on an XM4, or the ANC-off file with ANC on, is a correction that sounds wrong). A music lover doesn't know what an AutoEq file is; they'd notice by absence.
3. **B — accept three engines.** Where two overlap, small ripples and a graph that no longer matches what plays; growing with every layer.
4. **F — leave as written.** Compare means three things; three memories compete; an imported correction plays 6 dB too quiet or hits the ceiling.

**The sound engineer's rules.** Compare's level match must include every broadband offset of the program, not only the taste layer's — otherwise Compare is louder than EQ-on on hot masters and wins by habit. Clarity's slow per-band changes fit inside the existing filters' own glide; no second engine. The profile model (bands + spatial + dynamics + strength per device) can be cut to "correction + taste" without losing anything a music lover looks for; per-output memory plus Enhance covers it.

**Footnote.** S12 ends up about the same size with honest contents (it loses the layout work, gains the program and the memory extension); S13 grows by identification and the library; S16 shrinks.

**Roadmap change.** S12 row: the EQ part only (program, shelves, glide, read-back, per-layer bypass, "Bypass all", the memory extension, the unpin bug, the preset renamed "Detail"); the "A/B already shipped / still open" contradiction deleted. S13 row: delete "delivered early"; identification + a correction layer keyed by model and variant + offer-and-remember; the profile model cut to "correction + taste". S16 row: the referee emits into the program; the second fitter dropped. The two things called "Realizer" given two names.

---

### Card 7 — Correction and spatial: offered, or on by themselves (S13 / S18)

**The question.** Should headphone correction and the spatial render switch themselves on when the app recognises your headphones, or be offered and remembered per device?

**Why it matters to you.** As written, a fresh install with the XM4 connected is corrected — and after S18 spatialised — before you touch anything, and the badge wouldn't say so. The XM4's published correction is a −4 dB shelf at 105 Hz, −5 dB at 140 Hz, +6 dB at 2.2 kHz and a −6 dB preamp: a different headphone, 6 dB quieter, as the first thing you hear. If correction is written into the taste memory, a second pair of the same model gets it twice (−10 to −19 dB in the bass — unmistakably wrong). And "headphones" is a guess: a DAC feeding headphones reads as "USB".

**How others solved it.** Apple's Adaptive EQ tunes automatically — the *maker's* voicing, with no "before" to miss. Sony's stock sound is Sony's; its app's EQ and "Find Your Equalizer" are opt-in, you play your own music and pick what you prefer. The pattern listeners know: the maker's voicing is invisible; a third party's change is offered and chosen. We are the third party.

**Judged by first sound alone (sound engineer).** In level-matched tests most listeners prefer a Harman-target correction (Olive, Welti & McMullin 2013; the exact majority split not retrievable this session) — but auto-apply is *not* level-matched: the file's −6 dB preamp makes the sighted first impression "quieter and thinner", which loses by habit, and the XM4's bass is part of why people choose it. Auto-apply is a coin flip on first impression and a certain loss on trust.

**Options, ranked by sound.**

1. **A with a hold-to-hear preview (quality-best).** Opt-in per device, off on a fresh install; the toast says "Sony WH-1000XM4 recognised — hold to hear it corrected" and plays the correction *level-matched* (Compare in reverse, the preamp replaced by the loudness match); one tap keeps it for these headphones; remembered; the device class only picks the default suggestion for a never-seen output; a badge entry for every stage that plays. The first sound is the file; the better sound is one hold away; your own ear decides. Optional, borrowed from Sony: a one-minute "Tune for my headphones" that plays your own song with and without, blind, and turns the stage on only if you picked it — card 10's ladder in miniature.
2. **A as written.** The same minus the preview: you say yes to something unheard. Honest; a weaker first impression.
3. **C — one global switch, then by device class.** Simple, but headphones on a DAC read as "USB" and get nothing; a speaker DAC could be given a headphone curve (Q1 when it misfires).
4. **B — auto-apply with a six-second Undo.** The "messed with my headphones" first impression; Undo is a race; the surprise repeats on every new output. Fails Q2 and the faithful default.
5. **D — leave as written.** Processed first launch; three readings of the switch; double-apply on a second pair.

**Footnote.** A day of document fixes now; an offer toast with preview and a chip per sprint later.

**Roadmap change.** S13 and S18 rows: "auto-load" → "offer with a preview, and remember"; the story's "automatically apply … right out of the box" → "offered out of the box"; the spatial story's "default-on for headphones" → opt-in per device; the user-journey step "loads generic profile" → "offers"; crossfeed's story text aligned to the same rule (per-output memory, class default, manual override).

---

### Card 8 — Headphones: one control or three (S18)

**The question.** Crossfeed (shipped), the fold (R1.1-B), the spatial render (S18): one control with positions Off / Crossfeed / Spatial, or separate switches?

**Why it matters to you.** The engine declares crossfeed and the spatial render mutually exclusive with nothing enforcing it; S18 plans the render on by default; with crossfeed left on both run — a smeared centre and a dull top. The render has two planned homes (a stub inside the Intensity blend, which can't fold surround to stereo; and the output-boundary slot, which Intensity can't blend). The older design the sprint links to picks an Apple component the backlog bans.

**Options, ranked by sound.**

1. **A ≡ B while B's greying holds (quality-best: A).** A: one "Headphones: Off / Crossfeed / Spatial" control, exclusive by construction, remembered per output; the render at the output boundary for every source width (stereo included, so surround and stereo get the same treatment); Intensity drives its room amount as a dial, never a wet/dry blend; the stub retired; the old design superseded; each position with one line of plain words and a hold-to-hear. B: two switches that grey each other out — the same sound until a bug lets both run.
2. **C — the render inside the engine for stereo only; the fold permanent for surround.** Surround albums never get the room (Q3, Q5); "inside the blend" means a crossfade — the comb tone of card 2.
3. **D — leave as written.** Both run; the engine's own comment calls it a bug.

**The sound engineer's rules.** Correction stays *before* the render (the render assumes a neutral headphone; the architecture already says correction is "for timbre only"). The render's measured responses must be headphone-equalised so Spatial changes *space, not tone* — otherwise the pre-S18 blind test is a timbre test. Head tracking opt-in.

**Footnote.** A day of documents now; the S18 work is S18's own. R1.1-B carries the fold badge and the bit-perfect wording whatever S18 decides.

**Roadmap change.** S18 row: one home (the engine's stereo-out slot after card 5's final arrangement), the one control, opt-in per device, headphone-equalised responses, correction before the render; S17 row: "room amount as a setting"; the requirement "crossfeed largely subsumed by the render" → "exclusive with Spatial; one control"; the old spatial design marked superseded; the engine's stub retired.

---

### Card 9 — One playback owner, and the Engine sprint's neighbours

**The question.** W2 has no slot. Who builds it, and when — and what should the Engine sprint carry from R1.1?

**Why it matters to you.** Plumbing, mostly — but two sound items ride on it. (1) The Engine sprint moves processing to the device's own rate, which exposes a gap nobody owns: on a Bluetooth headset with its microphone on (it drops to 16 or 24 kHz) the EQ would silently play flat while the screen says it's on (Q2, Q7). (2) The ceiling: on a wired output running at another rate than 48 kHz, an unmeasured conversion sits after the engine. Otherwise: W2 is "funded by" agent control while agent control "waits for" W2; the R3 sprints need its events but their rows don't say so; S14-lite says "depends on ENG" and uses nothing in it; R1.1's seam, seek and channel-roles work sits on the path the Engine sprint replaces, unnamed in its acceptance.

**Options, ranked by sound.**

1. **A ≡ B ≡ C ≡ D in sound for the plumbing; A is the only one that gives the two sound items an owner (quality-best).** A: the Engine sprint delivers the engine half of W2; S15 carries the transport reducer and command layer; "S14's adaptive half" dropped as a funder; S14-lite loses "Depends on: ENG"; the Engine sprint's acceptance carries the R1.1 behaviours to re-prove and the under-44 kHz EQ gap; **the ceiling rule scoped by sound:** keep the −0.1 dB EQ-only ceiling where the link is lossless *and* the rate matches (the soundbar; a 48 kHz DAC) — fewer softened transients, no more exposure than the untouched file; −1 dB on Bluetooth (the encoder overshoots) and on any other-rate wired output until the conversion is measured. With the peak-safe turn-down of card 4 the ceiling question becomes moot: the net never works.
2. **B — agent control as an R2 sprint of its own starting with W2.** Same sound; R2 grows by a sprint.
3. **C — strike "W2 events"; let W2 wait for its trigger bug.** Same sound; the mic case and the conversion stay unowned.
4. **D — leave as written.**

**Footnote.** A day of documents now; later S15 grows by about a week (the one place the two-week cap is at real risk; C is the written fallback).

**Roadmap change.** W2's paragraph: funders and slot (= S15); S14-lite's dependency line; the Engine sprint section: the acceptance carry list, the below-44 kHz gap, the conversion measurement, "the developer switch and the losing path are deleted inside the sprint"; a known-issue entry for the below-44 kHz gap; the ceiling decision annotated with its scope.

---

### Card 10 — Your own blind test, and a name clash

**The question.** Should every processing feature pass a blind, level-matched A/B on your own gear — before it is *built*, and again before it ships on? And should the EQ preset called "Clarity" be renamed before the Clarity feature arrives?

**Why it matters to you.** No story makes "familiar music sounds more transparent on an A/B" the last line of S14-lite, S16 or S18. S16 is the one most likely to fail it: the project's own adaptive-tone study found no published test in which automatic EQ beats a finished master. The spatial story's test proves you can *hear a difference*, not that you *prefer* it — the wrong bar. Without this a stage ships because it measured right, you stop using the processed mode, and the thesis never meets its one user. The pre-mortem's story #4: the test placed at the end of the sprint finds the loser after the sprint is spent.

**Options, ranked by sound.**

1. **A ≡ C in the end product's sound (quality-best: A).** A: the blind test runs *before* S15 on an offline Clarity prototype on three of your tracks (S15 starts only if it wins) and before S18 on a spatial demo; and again as the last acceptance line of S14-lite, S16 and S18 — a stage that does not win ships off and hidden. The ready-made ladder (about 23 trials, capped at 60). The preset's display name becomes "Detail". C: the end-of-sprint test only — the same end sound, learned later.
2. **D — rename the feature instead ("Unmask").** Same sound; a word a listener has to learn, running through every document.
3. **B — skip the test.** The same off-by-default stages, but with card 11's front door a losing stage can be switched on by one tap — Q6 at risk by construction.

**The sound engineer's rules for the test.** Level-matched within 0.2 dB over *every* offset the engine adds (leveling, the turn-down, the compensation's own level change). The bar: "can't tell" for anything that plays by default; "prefer" for anything Enhance turns on. Loudness is tested at your real late-night level with the reference set. Spatial is tested against a timbre-matched dry reference (same correction, headphone-equalised responses) with an artifact checklist — no smeared centre, no hollow tone, bass intact; "I can tell them apart" proves nothing. Run on both outputs.

**Footnote.** A day of documents; an evening before S15 and before S18; an evening per processing sprint; the rename rides with the next EQ change.

**Roadmap change.** Two new pre-sprint rows ("blind test: Clarity prototype" before S15; "blind test: spatial demo" before S18); the acceptance line on S14-lite, S16, S18; the loudness spike's "MUSHRA, 10+ listeners" replaced by your ladder; the spatial story's ABX "difference" replaced by preference; the preset rename.

---

### Card 11 (from the pre-mortem) — An "Enhance" front door

**The question.** With every stage opt-in and Intensity limited to the automatic stages, does the processed mode have a one-switch way in — or only a Settings pane of eight switches?

**Why it matters to you.** Opt-in-everything plus faithful-by-default gives a fresh install that does nothing and eight separate switches. That is Roon's MUSE, and most Roon users leave it off. The pre-mortem's story #5: you live the dogfood week in the bit-perfect mode and the processed mode is never heard. Enhance is the only path on which a non-expert ever hears the processing; without it the app is faithful and nothing more.

**Options, ranked by sound.**

1. **A ≡ B in sound (quality-best: A).** A: one "Enhance" switch that turns on, together, the stages that won their blind test on *this output*, with a chip that names what it did in the listener's words — "Enhance: even levels · full at low volume · headphones in a room" — and the per-stage switches still underneath. B: per-stage switches only — the same sounds, reached by a listener who must first know what "crossfeed" and "loudness compensation" mean (most won't).
   - What pressing it should feel like (listener's advocate): one thing getting better *now*, at the same loudness, with nothing else moving — no fade-in over seconds, no level jump, nothing you set by hand touched. Holding the chip plays the file without it, at matched loudness, so the claim is checkable in a second. Where Enhance changes the level by design (leveling turning a loud master down) the chip says so ("−6 dB to match your other albums") so quieter isn't read as worse. Off returns the file as recorded. In the bit-perfect mode it reads "Not in bit-perfect mode — leave Pure?" with one tap. It never shows "ENHANCED" alone, never turns on a stage that lost, and never turns Loudness on before its reference is set.
2. **C — an "everything on" preset regardless of the blind tests.** Turns on stages that lost; the surest route to "this app messed with my music".

**Footnote.** A few days of UI in the first sprint that has a winning stage (likely S14-lite); a line in the dogfood rule now: at least half the week in the processed mode.

**Roadmap change.** A new story (Enhance: per output, the chip, hold-to-hear, the Pure line); the hero chip rework; the Pure card gains one sentence explaining why there are two "untouched" states.

---

### Card 12 (from the pre-mortem) — What proceeds now

**The question.** "Nothing gets implemented until these are reconciled" — all of R1.1-B, or only the parts the findings touch?

**All options tie in sound.** Five of R1.1-B's seven items touch no audio processing: real shuffle, global ⌘F, queue restore that can't half-fail, loose files, "Use this drive". The two the findings touch are Leveling and the fold.

1. **A (recommended).** Split R1.1-B into a player half (the five untouched items; starts now, its own PR) and a sound half (cards 1, 4's turn-down, 5's interim, the shared "Not in bit-perfect mode" row state; starts after sitting one). A is the only option under which you are listening to the processed mode while the sound decisions are made, which the dogfood rule needs.
2. **B — full freeze until all twelve cards are decided.** The pre-mortem's story #1.
3. **C — move loose files and "Use this drive" to a later library sprint.** Two things you placed in R1.1-B slip.

**Footnote.** A day to re-cut the sprint rows; the player half needs no sound decision at all.

---

## The order to decide — by what the sound depends on

Hard orderings: the level owner (cards 1 and 4's turn-down) before any second boost; card 5's interim before card 8's R1.1-B bits; card 1 before card 2's rule (removing the old leveller is what takes the level stage out of Intensity's blend); card 6's principle (compensation = the first layer of the one program) before card 3; card 7 before card 6's memory design; card 10's pre-S15 test before card 2's S16/S17 shape.

- **Sitting 1 — now, before R1.1-B's sound half:** card 12 (the split) · card 1 (leveling in both modes, the old leveller removed, −18, the Pure cut on the loan) · card 4's turn-down (with the true-peak number) · card 5's interim including the LFE rule and the folded loudness · card 8's R1.1-B bits (badge, Pure wording) · the document fixes to the S17 row that follow from card 1.
- **Sitting 1½ — before the Engine sprint (same evening):** card 9's Engine-sprint half · card 5's final arrangement and card 4's ledger shape as inputs to the Engine sprint's design.
- **Sitting 2 — before S14-lite (after the one-evening loudness prototype):** card 3 · card 4 in full · card 9's S14/S15 halves · card 6's principle · card 2's rule · card 7's rule and the preview · card 10 · card 11.
- **Sitting 3 — before S12:** card 6 in full · card 7 confirmed in the memory design.
- **Can wait:** card 8's control and the render's home (before S18) · card 2's S16/S17 shape (before S15, after the pre-S15 blind test) · card 9's fallbacks if S15 cannot carry the reducer.

**Three evenings of listening that decide more than any meeting:** the loudness depth prototype on the XM4 (card 3); the fold trims and the two LFE albums (card 5); the Clarity prototype blind test before S15 (card 10).

**Three decisions that most change what you hear:** card 1 (two levellers the day Intensity returns, or one — and even levels where you actually listen), card 4 (a net that never works, or drums losing their snap on every loud record with a bass boost), card 3 (a loudness button that follows the volume you turn and lifts only the bass, or one that does nothing on your gear and adds fizz). The decision most likely to earn "this app makes my music sound nicer": card 11 with card 10 under it. The one most likely to earn "this app messed with my music": card 1 taken wrong; card 7 taken as auto-apply the runner-up.

---

## The sound plan — one place for the decided model

*This section is written so it can be pasted into the roadmap as its own short section once the decisions are taken; the sprint rows then point at it instead of restating slices.*

- **Level has one owner.** Each track's level is set once, before it starts: a fixed leveling gain (Off / Auto / Album / Track, target −18, from our own analysis, file tags only for a track not yet analysed, a fixed cut for unknown loudness) plus a peak-safe turn-down — exactly enough that the track's peaks, with every boost applied, stay under the ceiling. The safety net is a backstop that is metered and expected to sleep. Nothing moves the level inside a song. Master Gain only turns down. In the bit-perfect mode the leveling cut rides the device's own volume; the stream is never touched.
- **Tone has one program.** Correction (per headphone model, offered with a level-matched preview and remembered per output) · taste (the 31 points, Tone, and parametric bands) · compensation — designed once into one set of filters, drawn as they play, with a bypass per layer. The per-band sum is held at +12 dB. Compare means "without my EQ", level-matched over every offset; "Bypass all" gives the file.
- **Low volume keeps its bass.** The loudness button follows the volume you actually turn where the Mac can read it (one-time "my normal loud setting"), is a labelled manual amount where it can't (the soundbar), lifts only the bass (about half the hearing-model difference, tuned by ear), reads the level as everything that changes it at the ear, and eases the mids rather than boosting so the net never works. Not in the bit-perfect mode, and it says so.
- **Headphones have one control:** Off / Crossfeed / Spatial, remembered per output, exclusive by construction. Correction before the render; the render changes space, not tone; room amount is a setting.
- **Surround folds once, before the one net,** with a per-track trim from the folded peak, the LFE decided per track from the analysis, and a badge that says "5.1 → stereo". (Interim: the matrix and the trim in today's unit, with the folded loudness measured; crossfeed on surround waits for the fold's final home.)
- **The automatic stages** — Clarity depth and room amount — are settings that Intensity scales; Intensity never blends, never changes level, and never touches a switch the listener set. 0 = nothing automatic.
- **Enhance** is one tap to the stages that won their blind test on this output, with a chip that names what it did in plain words and plays the file without it when held.
- **The rule for every processing stage:** a blind, level-matched A/B on the founder's own gear at the end of its sprint (S14-lite, S16, S18), before it ships on — a stage that does not win ships off and hidden; defaults must be "can't tell", Enhance winners must be "prefer". Leveling is judged by consistency (its own measurements), not by the A/B, and may be part of Enhance as "even levels". A fresh launch plays the file as recorded. Every control says, in words, when an output can't do it.

---

## Roadmap changes — what gets written, and what gets deleted

Applied as one docs PR once the decisions above are taken. Ids are the plan's own.

**`docs/product/roadmap.md`**
- Add "The sound plan" (above) as its own section under "The post-R1 plan"; the R1.1-B, S14-lite, S12, S13, S17, S18 rows point at it for the model and keep only their own deliverables.
- R1.1-B: one sprint (founder: full freeze, no split); its two sound rows rewritten per cards 1, 4, 5 (leveling in both modes at −18; the true-peak number and the peak-safe turn-down; the fold matrix + trim + folded loudness + LFE rule + badge + Pure wording; the shared "Not in bit-perfect mode" row state; the "Volume restored" toast). New stories: US-R1F-19 (the turn-down), US-R1F-20 (the shared row state).
- Engine sprint: acceptance carries the R1.1 behaviours, the below-44 kHz gap, the engine half of W2, the conversion measurement; its design settles the fold's final home, the layout owner and the ledger's shape; the losing path and the switch deleted inside the sprint.
- R2 table: S14-lite loses "Depends on: ENG" and "waits for W2", gains the ledger, the bass-only curve, the Level card, the per-output level source, Enhance; S12 loses the layout and the stage concept, gains the program, the memory extension, "Bypass all", the preset rename; S13 rewritten whole (identification, the library, offer with preview); S11-lite unchanged.
- "How structural work is paid for": W2's slot = S15; "S14's adaptive half" deleted from the funders; agent control a consumer.
- Phase 2 table: no pre-sprint test rows (founder: the blind test at the end of each processing sprint only); S16 gains Clarity's own switch and the blind A/B as its last line; S17 = Clarity depth + room amount as settings; S18 = one home, one control, opt-in, the blind A/B as its last line. New stories: US-TON-07 (the headroom ledger, S14-lite), US-UI-08 (Enhance, S14-lite); US-TON-02 is now Part A (S12, the one program) and Part B (S13, the correction layer).
- **Deleted:** the second scheduling of the static leveling fix (under S12's slice); "loudness-comp + clarity (+ crossfeed)" in S17; "the A/B already shipped" vs "still open" (both replaced by the one-meaning Compare); "auto-load by identified device" and "delivered early" in S13; "a safety ceiling after the spatial stage"; the link to the old spatial design (superseded); "respect the ±12 dB trust clamp, with its own headroom or a cap".

**`docs/sprints/sprint-plan.md`** — the same rows (R1.1-B, ENG, S14, S12, S13, S15, S16, S17, S18) and their "Depends on" cells; §Status "next"; the critical path; the post-R1 decisions section annotated where a decision's wording changes (the fold's ceiling; the −0.1 dB ceiling's scope; the leveling target).

**`docs/product/backlog.md`** — US-R1F-10 (leveling: both modes, −18, Auto, the fallback, tags, the Pure cut), US-R1F-08 (the fold: matrix, trim, folded loudness, LFE rule, badge, Pure reason), US-R1F-12 (crossfeed text aligned to the gate and to the per-output rule), US-TON-03 (which volume per output, bass-only, one cap, the level definition, the Level card), US-ADAPT-03 (into S14-lite), US-TON-02 (offered with preview; a layer keyed by model and variant), US-DEVICE-04/-05 (cut to correction + taste), US-PROF-02 ("Bypass all", scheduled), US-PERC-02/-03 (the referee feeds the program; Clarity's own switch; the pre-S15 blind test), US-RMG-02 and SPIKE-REIMAGINE-MAP (the mapping's two targets; default 0), US-ADAPT-05 (default and "never a hand-set switch"), US-SPAT-01/-03 (one home, opt-in, preference test, headphone-equalised responses), US-MCP-00 (slot = S15), US-PE-01/-03 (the carry list; the deletion), SPIKE-LOUDNESS-COMP-TUNING (the founder's ladder), KI-EQ-01 (scheduled into S12); a new story for Enhance.

**`docs/product/requirements.md`** — FR-TONAL-03 (bass-only; the one-time reference; one cap; the level definition), FR-TONAL-02 (correction as a layer, off by default, offered), FR-REIMAGINE-02 and FR-ADAPT-08 ("0 = nothing automatic; hand-set stages still play"), FR-SPAT-01/-03 (one control; exclusive), LD-17 (satisfied by the loudness-matched level reading; leveling = a static gain, the old leveller removed).

**`docs/architecture/architecture.md`** — §2.5 "What persists" and the EQ paragraph (the program; Compare's one meaning; the per-output memory); §5 (what Intensity scales); §7 (the render's home; correction before the render; the old design superseded); §9 (the ledger, the meter, the turn-down); §11 (the sum clamp ships in S14-lite); the −0.1 dB ceiling decision annotated with its scope; the two "Realizer"s named apart.

**`docs/product/known-issues.md`** — KI-MC-01/-02 annotated (trim + backstop now; one net after the Engine sprint); a new entry for the below-44 kHz EQ gap; a note that crossfeed is stereo-only on folded files until the fold moves; KI-EQ-01 → S12.

**`docs/reviews/2026-10-council/working/stage5-architect.md`** — annotated as a record, not a to-do list (it still lists items R1.1-A closed and schedules the leveling fix a second time).

---

## The plan as decided

- **R1.1-B, one sprint (starts when the roadmap is reconciled):** the five player items — real shuffle · global ⌘F · atomic queue restore · loose files · "Use this drive" — and the sound items: Leveling Off/Auto/Album/Track at −18 through the existing per-track gain, the old leveller removed, the fixed unknown-loudness cut, tags for unanalysed tracks, the true-peak number, the peak-safe turn-down, Compare level-matched to it, the Pure cut on the volume loan (the loan taught its own moves), the "Volume restored" toast; the fold matrix plus per-track trim in the spatial unit, the folded loudness, the LFE rule, the "5.1 → stereo" badge, the bit-perfect reason wording; the shared "Not in bit-perfect mode" row state. Nothing in the quality answer is cut. The sprint as sized likely exceeds its two-week cap; the roadmap says so and the founder decides whether it runs long or lands in two PRs.
- **The Engine sprint:** build unchanged; acceptance carries the R1.1 behaviours, the below-44 kHz gap, the engine half of W2, the conversion measurement; its design settles the fold's final home (inside the engine before the one net, crossfeed after), one layout owner from the decoder onward, and the ledger's shape; the losing engine and the switch deleted inside the sprint. The dogfood week follows R1.1-B, with no rule on which mode.
- **S14-lite:** decoupled from ENG and W2 · level = Master Gain + device volume where readable, one-time reference, a labelled manual amount on the soundbar · bass-only, depth from the prototype evening, one cap · the first layer of the one program · the full ledger (per-band sum, AutoEq's preamp rule, the meter) · one "Level" card with plain names and a net-gain readout · Enhance (if Loudness wins) · the blind A/B as the last line.
- **S12:** the one EQ program (layers, read-back, a bypass per layer) · the per-output memory extended · the unpin bug fixed · "Bypass all processing" · the preset renamed "Detail". At its cap with honest contents.
- **S13, whole:** identification · the correction library (model and variant) · a correction layer keyed by model, separate from taste · offered with a level-matched preview, off on a fresh install · a chip · the profile model cut to "correction + taste".
- **S11-lite:** unchanged.
- **S15:** the masking spike plus W2's transport reducer and command layer (the one cap risk; fallbacks named); it owes S16 the Clarity per-band cap and rate limit.
- **S16:** Clarity with its own switch and chip, feeding the one program; the blind A/B as the last line — wins, or ships off and hidden.
- **S17:** Intensity = Clarity depth + room amount, as settings, default 0.
- **S18:** one Headphones control, the render in the engine's stereo-out slot (before the one safety net, so its peaks are under the ceiling by the same trim rule as the fold), headphone-equalised responses, correction before the render, the stub retired, opt-in per device with preview; the blind A/B (space, not tone) as the last line; the default room amount is S18's design call.
- **Agent control:** a consumer of S15's command layer; "R2 or later" unchanged.

---

## Smaller open items (the reports' recommended answer in one line)

- **Leveling target:** −18 (every album can reach it under the true-peak cap; no tonal difference at any target). Show it.
- **File loudness tags:** our analysis first; tags only for a track not yet analysed, ahead of the fixed −5 dB cut (scanners disagree by 1–3 dB).
- **The −0.1 dB wired ceiling:** keep it where the link is lossless *and* the rate matches the engine's; −1 dB on Bluetooth and other-rate outputs until measured; the peak-safe turn-down makes the question moot. *(Scopes an earlier decision of yours — needs your word.)*
- **The peak-safe turn-down:** measured from the EQ'd track's real peak, not bounded by the curve's biggest boost, as soon as the analysis can — the bound turns down more than needed on most tracks.
- **Where the "Level" card lives:** one place, in signal order — Settings or the inspector, a UI call.
- **The bit-perfect give-back:** a toast ("Volume restored") when Pure hands the device volume back; the readout shows both numbers; add "volume keys during Pure, then end of queue" to the hardware check list.
- **Crossfeed on a folded surround file:** none until the fold moves; the chip and the switch read the engine's bypass so "XF" never shows when nothing plays.
- **Headphones on the USB DAC** read as "USB" and would get no crossfeed by class and no correction offer: one per-output question, "What's plugged into this output?", remembered — then everything headphone-shaped follows.
- **"Held" on the graph:** say it *protected* the sound, not that it refused.
- **"It got quieter when I turned it on":** the loudness button's caption says "nudge the volume up a notch".
- **The two "untouched" states** (Pure, and Enhanced with nothing on): the Pure card answers in one sentence why there are two.
- **The council's slice catalogue:** annotate as a record, not a to-do list.
- **"Two engines never ship":** the developer switch and the losing path are deleted inside the Engine sprint.
- **Two things called "Realizer":** name the second before S16.

---

## Where the evidence is

- `technical-synthesis.md` — the merged, ranked findings with code and document references.
- `panel/listener.md`, `panel/dsp-chain.md`, `panel/other-players.md`, `panel/architecture.md` — the four blind reviews; every web source opened is listed at the end of each.
- `brainstorm/pm-cards.md` — the first draft of the cards (before the pre-mortem and the sound-first pass).
- `brainstorm/impact-map.md` — the business analyst's impact table per option, with the plan's own story and row ids; the source of the "Roadmap changes" section.
- `brainstorm/sound-truth.md` — the sound engineer's option-by-option "what you'd hear", the six plain-language answers, and a technical appendix with the measurements that settle each question.
- `brainstorm/quality-pass-sound.md` — the sound-first ranking of every option, with the hearing-model numbers, the XM4 correction figures, the LFE answer and the ceiling answer.
- `brainstorm/quality-pass-listener.md` — the listener-experience ranking, the "out of the box" answer, what pressing Enhance should feel like, and the consistency-across-outputs map.
