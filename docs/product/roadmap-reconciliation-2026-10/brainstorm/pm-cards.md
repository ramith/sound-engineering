# The roadmap's sound features — decision cards

2026-10-23. Written for the founder from the four reviewer reports and the merged synthesis beside this file. Nothing here is built, and nothing is decided until you say so. Each card is one decision from the synthesis's closing list, with the same number. The synthesis carries the evidence and the code references; these cards carry the choice, in plain words. Where I reason beyond the reports, the line says so.

How to read a card: the question, what you would notice if it is left as planned, how other players handled it, the options (recommended one first), and the one line it changes in the plan.

## Words used in these cards (each defined once)

- **The processed mode (Enhanced)** — the normal path. The file passes through the sound engine, where every effect lives.
- **The bit-perfect mode (Pure)** — the file goes straight to the device, untouched: no EQ, no effects. The app's volume slider then works by turning the device's own volume down ("the volume loan").
- **The sound engine** — the part of the app that processes audio in the processed mode: EQ, crossfeed, the safety net and so on.
- **Master Gain** — the app's own volume slider. Turn-down only; it can never make anything louder than the file.
- **The safety net** — the limiter: the last stage, which stops peaks going over the ceiling. Meant to act rarely. When it acts constantly it is compressing the music.
- **The ceiling** — how close to full scale the safety net lets peaks go: −1 dB on Bluetooth and unknown outputs; −0.1 dB on wired outputs when only the EQ is on.
- **dB** — the unit of level. 1 dB is barely noticeable; 10 dB sounds roughly twice as loud.
- **Loudness (the measurement)** — how loud a track feels over its length, in "LUFS". −14 LUFS is where Roon and Spotify aim; the sound engine's own internal target is −16.
- **Leveling** — evening out the level between tracks or albums so you don't reach for the volume.
- **The old auto-leveller** — a volume rider already inside the sound engine. It listens through the session and keeps nudging the level toward its target, up to 1 dB per second, anywhere from −20 to +12 dB. It is switched on in the code, nothing in the app can switch it off, and it only stays silent today because the Intensity knob is hidden at zero.
- **Loudness compensation** — when you turn the volume down, your ears lose bass and treble first; this puts some back. Hi-fi receivers call it the "loudness" button.
- **Intensity** — the one big knob (hidden since R1.1-A) meant to blend the automatic effects in and out.
- **Clarity** — the planned automatic EQ that lifts detail hidden by other sounds, moment by moment. Also, today, the name of a built-in EQ preset.
- **The Arbiter** — S16's planned referee: it decides what the automatic EQ may change, inside the safety caps.
- **Crossfeed** — a headphone effect that lets each ear hear a little of the other channel, as speakers in a room do. Shipped; stereo only.
- **The spatial render** — the planned headphone effect (S18) that simulates speakers in a room from measured head and room responses.
- **The fold** — mixing a surround file (5.1 or 7.1 channels) down to the two channels of stereo headphones or a soundbar.
- **Headroom** — the spare room between the music's peaks and the ceiling. Every boost (EQ, correction, compensation) spends it.
- **The 12 dB safety cap** — the rule that no boost exceeds 12 dB. Today it is three separate 12 dB limits that nobody adds up.
- **Correction** — a per-headphone EQ curve that flattens a model's known tonal flaws (planned, S13). **AutoEq** is a public library of such curves.
- **Parametric EQ** — EQ bands you can place at any frequency, next to the fixed 31 points (planned, S12).
- **Compare** — the hold-to-hear button on the EQ graph: the song without your EQ, at matched loudness.
- **The status badge** — the small chip on Now Playing that names what is playing (ENHANCED; XF for crossfeed).
- **W2, "one playback owner"** — structural work: one place owns play/pause/seek, and the engine sends events instead of the app asking it 20 times a second.
- **Agent control** — letting an AI agent drive the app from outside (the EP-MCP epic).

Sprint names, with a short gloss: **R1.1-B** (next fix sprint) · **ENG** (new playback engine) · **S14-lite** (loudness compensation sprint) · **S12** (parametric EQ sprint) · **S13** (headphone correction sprint) · **S15** (masking research spike) · **S16** (Clarity feature sprint) · **S17** (Intensity returns sprint) · **S18** (spatial headphone sprint). **R2** is the parity release that closes after S11-lite; **R3** is the thesis release, S15 to S18.

---

## Card 1 — Leveling

**The question.** When Leveling evens out track levels, should it be one fixed adjustment per track or album that *replaces* the old auto-leveller — and should the bit-perfect mode simply say "Leveling off" for now?

**Why it matters to you.** Today "leveling off" is not a setting. The old auto-leveller is still inside the sound engine, switched on, and it only stays quiet because Intensity is hidden at zero. The day Intensity comes back (S17, the Intensity returns sprint), a nudge above zero wakes it, underneath whatever Leveling you chose: two levellers at once, one drifting the level by up to 1 dB a second in the middle of a song, regardless of "Leveling: Off". As planned, a track the app hasn't analysed yet gets a live guess that moves the level during the song; "Album or Track" is asked of you instead of following what plays next; the target is never shown; loudness tags already in your files are ignored. And in the bit-perfect mode — your daily driver — the story says nothing, so Leveling would silently do nothing there.

**How others solved it.** Roon, JRiver, foobar2000 and MPD all offer Off / Auto / Album / Track, where Auto means album when the next track is from the same album, else track. Roon aims at −14 LUFS, applies a fixed −5 dB to tracks of unknown loudness, and reads loudness tags. In bit-perfect playback, MPD moves leveling onto the device's own volume; JRiver and Roon switch it off and say so.

**Options.**

**A. One fixed gain per track or album; retire the old auto-leveller; Off / Auto / Album / Track; the bit-perfect mode says "Leveling off" (Recommended).**
What it means: leveling becomes one number per track, set at the track change and never moved mid-song. Its switch also retires the old rider (default off). A fixed cut for unanalysed tracks, the target shown, tags read when present. In the bit-perfect mode the badge reads "Leveling off (bit-perfect)".
- Pros: one owner of level, so Intensity's return can never wake a second leveller.
- Pros: the level never moves inside a song; the shape every mature player uses.
- Pros: "Auto" asks nothing of you; shuffle and album play both come out right.
- Cons: a little more scope in R1.1-B (next fix sprint): Auto, the fallback, tag reading.
- Cons: no leveling in the bit-perfect mode for now, so your daily driver stays uneven across albums.
What you'd hear: quiet and loud albums sit at one level in the processed mode, with no pumping or drift; the bit-perfect mode plays as recorded, as today.

**B. Keep the old auto-leveller as a visible fourth mode, "Leveling: Adaptive".**
What it means: the rider stays, but as something you choose rather than a side effect.
- Pros: keeps code that already ships; a live rider can suit a mixed, unanalysed playlist.
- Cons: a rider is compression by stealth — its makeup carries across tracks and quiet passages get pulled up.
- Cons: a second leveller to explain, and it still has to be unhooked from Intensity.
What you'd hear: in Adaptive, the level breathing through a quiet intro; otherwise as A.

**C. Leveling in the bit-perfect mode too, as a cut on the device's own volume.**
What it means: the stream stays untouched; the app lowers the device volume by the track's cut, the way it already lowers it for Master Gain in Pure (MPD's pattern). The players reviewer preferred this; the merged synthesis deferred it.
- Pros: leveling on your daily driver, with the stream still bit-perfect.
- Cons: the volume loan today reads any device change as *yours* and re-anchors, so each cut would compound; the loan must first learn to tell its own moves from yours.
- Cons: device volume steps are coarse on some outputs; more R1.1-B scope.
What you'd hear: even levels in Pure, in whole steps; the Mac's volume indicator moving on its own at track changes.

**D. Leave the plan as written.**
- Cons: two levellers the day S17 lands; the same fix scheduled in two sprints; the live guess moves the level mid-song; silence in the bit-perfect mode.

**Recommended: A.** It is the only option under which "faithful by default" survives Intensity's return, and it is the shape every mature player converged on. C is worth a follow-up once the volume loan can tell its own moves from yours.

**What it changes in the plan.** Lands in R1.1-B as written plus Auto, the fallback and tags; the duplicate scheduling under S12 is struck; S17's "map Intensity across loudness-comp" is struck.

---

## Card 2 — Intensity

**The question.** When the Intensity knob comes back (S17), what should it control: only the automatic effects (Clarity depth, spatial room amount), or also things you already switch by hand (Loudness, crossfeed, Leveling, EQ)?

**Why it matters to you.** Picture R3. You've set crossfeed Strong, Loudness on, Leveling Album. S17 lands with Intensity at zero. Does your Loudness switch go dark? One requirement says "0 = all stages bypassed", which silently overrides a switch you set; another says the default is 100%. The S17 row still lists crossfeed inside Intensity, which contradicts your 2026-10-14 decision that crossfeed plays at full strength whatever Intensity is. And Clarity (S16, the Clarity feature sprint) only runs inside the Intensity blend, which stays hidden until S17 — so the "core differentiator" ships into a path nobody can hear, and its A/B is skewed by a +3 dB bump the blend adds until S17 fixes it.

**How others solved it.** Roon has no macro knob: each filter has its own switch, and leveling sits outside the DSP engine altogether. FabFilter Pro-Q's one macro scales EQ shapes only, never level.

**Options.**

**A. Intensity scales only the automatic stages — Clarity depth and spatial room amount — and never a hand-set switch; Clarity gets its own switch, or S16 and S17 merge (Recommended).**
What it means: zero = "nothing automatic". Your switches are yours. S16 either gives Clarity an on/off and depth of its own (the pattern crossfeed took) or ships together with Intensity's return so it is audible.
- Pros: one hand per knob; nothing you set is undone by a slider.
- Pros: the faithful default survives — zero really is nothing automatic.
- Pros: S16 is audible the sprint it ships, with a fair A/B.
- Cons: the "one knob" idea narrows to two stages.
- Cons: a Clarity switch (or the merge) adds a little to S16.
What you'd hear: moving Intensity changes how much automatic detail and room you get; your tone, level and headphone settings stay put.

**B. Keep Intensity hidden for good; every stage gets its own control.**
- Pros: the simplest story; nothing left to contradict.
- Pros: no blend, so no level bump to fix.
- Cons: the "one knob" thesis is gone; the Reimagine section in the inspector becomes dead weight.
- Cons: two or three more switches to find and remember.
What you'd hear: the same sound as A, reached by more switches.

**C. Intensity as a visible macro that moves the other sliders.**
- Pros: one knob, literally, and honest because you see the others move.
- Cons: a sound knob that changes level and undoes your settings is exactly the surprise the faithful default forbids.
- Cons: nobody else does it; the hardest to explain.

**D. Leave as written.**
- Cons: contradicts the crossfeed decision already shipped; overrides hand-set switches; two defaults in two documents; Clarity inaudible in S16.

**Recommended: A.** A knob should change *sound*, not *level* or your own choices; keeping it to the automatic stages is what everyone else does and the only reading under which "0" still means faithful. The Clarity switch is cheap and makes S16 testable.

**What it changes in the plan.** S17's row and two requirement texts are rewritten now (cheap); S16 adds a Clarity switch or merges with S17; S14-lite builds its switch outside Intensity.

---

## Card 3 — Loudness compensation

**The question.** "Keep bass and treble at low volume" has to know how loud you are listening — which volume should it follow, and should it boost the extremes or gently cut the middle?

**Why it matters to you.** It's late; you leave Master Gain at 0 and turn the XM4 down with the volume keys. As planned, the feature reads only the app's own slider, so it does nothing — at any level you actually use, on either of your outputs. The sound engine has the processing but no idea of your volume; the bit-perfect mode knows the volume but has no processing. The feature also has two definitions (a tilt that costs no headroom, or a boost that spends it) and two caps (+12 dB versus +6/+4 dB). It is held behind two dependencies — ENG (new playback engine) and W2 — that it does not use: the code that reads the device volume already exists; it is just only switched on in the bit-perfect mode. Finally, "Leveling" and "Loudness" are the same word to a Spotify listener and a bass boost to a receiver owner; the "Loudness" EQ preset was already renamed to "Bass & Treble" for this reason.

**How others solved it.** JRiver keys Loudness to its own volume plus a one-time reference-level calibration you set. CamillaDSP's loudness follows its fader and, when the volume control sits *after* the processing (our case), switches to "attenuate-mid": cut the mids as the level drops, never boost the extremes — no headroom spent, cannot clip. Roon ships no loudness compensation at all.

**Options.**

**A. Follow Master Gain plus the device's own volume, against a one-time "this is my normal loud setting" reference; cut-the-mids form; one cap; decoupled from ENG and W2; plain names in one "Level" card; "not in bit-perfect mode" (Recommended).**
What it means: you set your normal listening level once. Below it the mids are eased down so bass and treble feel restored. The readout under the slider shows what is being applied now.
- Pros: follows the volume you actually turn, on headphones and soundbar.
- Pros: cannot clip and spends no headroom, so it stays outside the 12 dB cap.
- Pros: ships earlier — nothing it needs is in ENG or W2.
- Pros: plain names ("Even out track levels", "Keep bass and treble at low volume") end the Leveling/Loudness confusion.
- Cons: a one-time calibration step for you.
- Cons: easing the mids makes the whole track a touch quieter at low volume than a boost would (my inference, not from the reports).
- Cons: whether the XM4's own buttons report to the Mac's volume over Bluetooth is unverified; if not, it follows the Mac's volume only.
What you'd hear: turn down at night and the bass and presence stay; turn back up and it fades to nothing.

**B. Ship it as a manual "Loudness amount" slider, labelled as such.**
- Pros: honest; the smallest build; no level input needed.
- Cons: it is a tone control, not a loudness button; you adjust it yourself every time.
- Cons: nothing stops it stacking with your EQ's boosts.
What you'd hear: a fixed warmth you dial in; unchanged when you touch the volume.

**C. Boost form (bass and treble up), with its own pre-gain inside the headroom ledger of card 4.**
- Pros: what a receiver's loudness button does; the same volume input as A.
- Cons: spends the 12 dB cap; on loud masters it drives the safety net into constant work, which is compression.
- Cons: needs card 4's ledger first.

**D. Leave as written (wait for ENG and W2; follow Master Gain only).**
- Cons: waits on things it does not use; does nothing when you use the volume keys; two caps and two definitions stay unresolved.

**Recommended: A.** It is the only option that works on your actual setup — Bluetooth headphones and an HDMI soundbar, volume on the keys — and the cut-the-mids form is the one that can never clip or compress. If the device-volume read turns out not to be reachable inside the sprint, fall back to B and say so in the control's label.

**What it changes in the plan.** S14-lite loses "Depends on: ENG" and the "adaptive half waits for W2" line; one cap and one definition are written into the story; the two level controls get one home.

---

## Card 4 — Headroom

**The question.** Who keeps the running tally of every boost — your EQ, a headphone correction, compensation, leveling, Clarity — so the total never silently passes the 12 dB cap, and the safety net isn't quietly working all the time?

**Why it matters to you.** Today there are three separate 12 dB limits and nothing adds them; the plan adds four more boosters. A +12 dB taste point, +6 dB of compensation and +5 dB of correction in the same band is +23 dB asked of the bass before the safety net — and after S13 (headphone correction sprint) it is the auto-loaded correction spending the budget, not you. An AutoEq file arrives with its own "−6 dB preamp" line: apply it on top of our own level-matching and corrected headphones play 6 dB too quiet; drop it and bass-heavy tracks hit the −0.1 dB wired ceiling, where the safety net becomes a compressor. Filters beyond 12 dB would be silently clamped, so the graph would no longer draw what plays.

**How others solved it.** Roon has one fixed Headroom stage first in the chain (−3 dB by default) plus a clipping light that flags even one clipped sample. Equalizer APO sums its preamps in dB; Strawberry has one EQ preamp element.

**Options.**

**A. One headroom ledger: the per-band sum of the EQ layers held at +12 dB, one pre-gain applied once before the EQ, AutoEq's preamp line replaced by the ledger, the safety net's work metered and shown. Built as S14-lite's structural slice (Recommended).**
- Pros: the 12 dB cap becomes a real sum, in one place.
- Pros: the graph keeps drawing what plays ("held" shown where the sum was scaled).
- Pros: you can see when the safety net is working instead of guessing.
- Pros: one pre-gain replaces three competing level rules.
- Cons: adds structural scope to S14-lite, the first R2 sprint.
- Cons: leveling and Clarity's live gain sit outside the ledger, each capped by peak headroom — two rules, but explicit ones.
What you'd hear: stacked boosts stay inside the cap; loud masters with EQ on no longer pump; a readout tells you when they would have.

**B. Separate budgets per layer, with the sum displayed.**
- Pros: cheaper; each feature keeps its own cap.
- Cons: the sum can still pass 12 dB; a readout of a problem, not a fix.

**C. A smaller compensation budget (+6 dB) until the Arbiter arrives in S16.**
- Pros: delays the work.
- Cons: taste plus correction still stack with no sum; S16's clamp engine is two releases away.

**D. Leave as written ("respect the clamp, with its own headroom or a cap").**
- Cons: two rules in one sentence; nobody adds anything up.

**Recommended: A.** Your hearing-safety promise rests on a cap that today exists only per slider; the first sprint that adds a second boost is where it has to become a sum. It also settles the leveling cap for R1.1-B in passing.

**What it changes in the plan.** S14-lite's slice becomes the ledger; R1.1-B's leveling cap takes the ledger's rule; S12's AutoEq import drops the preamp line.

---

## Card 5 — Fold-down

**The question.** When a 5.1 or 7.1 file plays on stereo headphones or the soundbar, where should the fold to two channels happen — inside the sound engine before the one safety net, or after it with a second safety net of its own?

**Why it matters to you.** The fold adds the centre and surround channels into each side: +3 dB on a centred vocal, up to +7.7 dB in the worst case. A safety net placed after that works constantly on most dense surround masters (the chain reviewer's reading of the matrix maths) — compression by default on exactly the albums this sprint exists to fix. Crossfeed is stereo-only and runs *before* the fold, so with crossfeed on you would hear a folded surround album without it while the "XF" badge still shows. The channel layout (which channel is which) is rebuilt by four different sprints in turn, including S12 (parametric EQ sprint), which needs none of it. And the second half of the chain, where the plan puts the fold, has no controls and no safety net today.

**How others solved it.** JRiver: "Output Format must be processed first" — the fold is the first stage. CamillaDSP folds with explicit per-channel gains. mpv offers a normalised downmix, which it warns is "too quiet", or an un-normalised one that can clip.

**Options.**

**A. Fold inside the sound engine before the one safety net; one decoded channel layout per track, published once to both halves; the layout work moves from S12 into R1.1-B (Recommended).**
What it means: crossfeed, the safety net and every EQ gain see the same stereo signal that reaches your ears.
- Pros: one safety net, acting rarely, as designed.
- Pros: crossfeed works on folded surround albums.
- Pros: one owner of the channel layout; S12 shrinks to the EQ work.
- Cons: the engine's shape changes (surround in, stereo out) — a bigger R1.1-B.
- Cons: the spatial render (S18) must be placed in the same decision (card 8).
What you'd hear: surround albums at the right balance, uncompressed, with crossfeed if you use it.

**B. A per-track fold trim from the analyser (the folded peak), applied at the track change; keep the second safety net as a rarely-acting backstop; meter it.**
- Pros: a smaller change; the same "fixed gain capped by peak" rule as leveling.
- Pros: the second safety net rarely acts.
- Cons: still two safety nets in series; still no crossfeed on folded files.
- Cons: the second half of the chain still needs its own controls and layout feed.
What you'd hear: surround albums a few dB quieter than stereo ones, uncompressed; no crossfeed on them.

**C. Normalise the fold for the worst case (about −7.7 dB on everything).**
- Pros: transparent; the safety net never acts.
- Cons: audibly quieter surround albums — mpv's own warning.

**D. Leave as written (a bare second ceiling after the fold).**
- Cons: compression by default on surround; two safety nets; crossfeed silent on folded files; four owners of the layout.

**Recommended: A.** One safety net in one place is the only arrangement in which "transparent" is checkable, and it is the arrangement JRiver and Roon chose (fold or headroom first). If A will not fit R1.1-B's two weeks, B is the honest interim, with the meter so you can see what the backstop is doing.

**What it changes in the plan.** R1.1-B grows (fold placement, one layout owner); S12 loses the layout and "stage concept" work; a "5.1 → stereo" badge and the bit-perfect mode's wording land in R1.1-B.

---

## Card 6 — EQ layers

**The question.** Your own EQ, a headphone correction, parametric bands, imported AutoEq curves and the compensation tilt — one stack with one engine, one per-headphone memory and one meaning for Compare, or several separate things?

**Why it matters to you.** After S13 you hold Compare to judge your Warm curve and hear your headphones *uncorrected* — the wrong comparison. After S14-lite, if Compare also removes the compensation tilt, "matched loudness" is no longer true. Plugging in the XM4 would have three memories competing — the EQ pin, an S13 profile, a parametric set with no home — and no rule for which loads. By S16 there would be three different filter engines doing one job, each with its own smoothing. S12 as written is over its two-week cap. And the S13 row says identification was "delivered early" by the EQ pins; it wasn't — pins remember *your taste* per device, they don't recognise a headphone model.

**How others solved it.** Roon: parametric EQ, procedural EQ, convolution and Audeze presets are separate, re-orderable filters, each with its own switch ("great for A-B testing"). Equalizer APO: one ordered list with a summed preamp. AutoEq exports the same correction in both graphic and parametric form.

**Options.**

**A. One EQ program of ordered layers — correction, taste (graphic + parametric), compensation — designed once into one set of filters, with one read-back so the graph draws what plays and a bypass per layer. Compare keeps one meaning ("without *my* EQ"; correction and compensation stay). A separate latching "Bypass all processing". The existing per-output slot is the only per-device memory, extended with the parametric bands and the correction choice. S16's Arbiter feeds this program instead of running a second engine. S12 carries only the EQ part; the S13 row is rewritten honestly (Recommended).**
- Pros: one engine, one memory, one Compare — nothing to arbitrate.
- Pros: the graph stays honest once layers exist.
- Pros: S12 fits two weeks; the unpin bug that wipes the shared EQ is fixed where the memory lives.
- Cons: a bigger design step at the start of S12.
- Cons: S16's planned filter-fitter is narrowed or dropped.
- Cons: S13 is more work than its row admits (identification, a model-keyed layer, the profile model or its explicit cut).
What you'd hear: Compare answers "is my curve helping?" on corrected headphones; one toast on plug-in; the curve on screen is the curve playing.

**B. Accept three engines; write down which one owns phase.**
- Pros: each sprint builds its own piece; less design up front.
- Cons: two filter cascades in series add ripple and delay in overlapping bands.
- Cons: the engine's parameter block reshapes twice, and its reference test is re-recorded twice.
- Cons: the graph can't draw what plays without a composed read-back anyway.

**C. Compare opens a small menu — Without: my EQ / correction / Clarity / everything.**
- Pros: flexible.
- Cons: a hold-to-hear button with a menu is awkward; more to explain; still needs the layer model underneath.

**D. Leave as written.**
- Cons: Compare means three things; three memories with no rule; AutoEq's preamp fights our level-matching; S12 over its cap.

**Recommended: A.** One ordered stack is what Roon and Equalizer APO both do, and it is the only model under which "the graph draws what plays" and "Compare at matched loudness" stay true. The cost is paid once, in S12's design, instead of three times.

**What it changes in the plan.** S12 slimmed to the EQ part of its slice; S13's row rewritten (identification, correction layer, profile model or its cut); S16's Arbiter targets the program; the unpin bug fixed alongside.

---

## Card 7 — Correction and spatial switching themselves on

**The question.** Should headphone correction (S13) and the spatial render (S18, the spatial headphone sprint) switch themselves on when the app recognises your headphones, or be offered and remembered per device?

**Why it matters to you.** As written, a fresh install with the XM4 connected is corrected — and after S18 spatialised — before you touch anything, and the status badge names only Intensity and crossfeed, so nothing on screen says so. The documents give three different answers to whether correction even has a switch. If correction is written into the pinned taste memory, a second pair of the same model gets it twice through the model fallback. And "headphones" is a guess: a DAC feeding headphones reads as "USB" — the one coming to your desk included.

**How others solved it.** Roon's DSP is "disabled by default, except when it's required". Equalizer APO remembers a configuration per output device with an explicit catch-all. None of the reviewed players gates crossfeed by device class; they remember per device and let you override.

**Options.**

**A. Opt-in per device, off on a fresh install; "auto-load" means offer and remember, never apply; the device class only picks the default suggestion for a never-seen output; a status badge entry for every stage that plays (Recommended).**
- Pros: "a fresh launch plays the file as recorded" stays true.
- Pros: the badge is honest about everything that is playing.
- Pros: no double-apply; your USB DAC gets the same offer when it arrives.
- Cons: one more "yes" from you, once per device.
What you'd hear: a toast — "Sony WH-1000XM4 recognised. Apply its correction?" — and nothing changes until you say yes; next time it remembers.

**B. Auto-apply with a six-second Undo toast.**
- Pros: zero taps for those who always want it.
- Cons: the first sound from a fresh install is processed; Undo is a race against your attention.
- Cons: the promise is still broken for six seconds every time.

**C. One global "correct my headphones" switch, then automatic by device class.**
- Pros: one switch.
- Cons: the class guess misfires (DAC = "USB"); not per device; still silent in the badge unless added.

**D. Leave as written.**
- Cons: a processed first launch; three readings of the switch; double-apply on a second pair.

**Recommended: A.** It is the wording one of the backlog's own stories already uses ("offers to auto-load; manual switch also available"), it keeps the promise, and it matches how every reviewed player handles per-device effects.

**What it changes in the plan.** S13 and S18 rows and three requirement texts rewritten; the badge gains a chip per stage, first in S13.

---

## Card 8 — Headphones: one control or three

**The question.** On headphones there are three answers — crossfeed (shipped), the fold for surround (R1.1-B), the spatial render (S18). One control with positions Off / Crossfeed / Spatial, or separate switches?

**Why it matters to you.** The sound engine declares crossfeed and the spatial render mutually exclusive, with nothing enforcing it. S18 plans the render on by default; with crossfeed left on, both run — a smeared centre and a dull top — and the badge can't tell them apart. The render also has two planned homes: a stub inside the Intensity blend (which can't fold surround to stereo) and the device-boundary slot (which Intensity can't blend). The older spatial design the sprint still links to picks an Apple component the backlog bans. A surround album started in the bit-perfect mode already falls back to the processed mode; after R1.1-B it will get the fold and a ceiling you never chose, with only "Pure off: channels" to explain it.

**How others solved it.** Roon's crossfeed is one switchable filter that "simulates the experience of listening to stereo speakers" — the same job as a spatial render, offered as one choice. Strawberry and EasyEffects also treat it as one user-ordered filter.

**Options.**

**A. One "Headphones: Off / Crossfeed / Spatial" control, exclusive by construction, remembered per output; the render lives at the device boundary for every source width (stereo included); Intensity drives its room amount as a dial, not a wet/dry blend; retire the stub inside the engine; mark the old design superseded; the fold gets a "5.1 → stereo" badge and the bit-perfect reason says "…so Enhanced plays it, folded to stereo" (Recommended).**
- Pros: the conflict cannot happen; one place to look.
- Pros: per-device memory, like the EQ pin, so your XM4 and your soundbar each keep their own choice.
- Pros: surround and stereo both get the render, so the fold is truly interim.
- Cons: the render is not blendable by Intensity — only its room amount is.
- Cons: S18 must commit to one home now.
What you'd hear: pick Crossfeed or Spatial, never both; the badge names which; surround albums say they were folded.

**B. Two switches that grey each other out.**
- Pros: each feature keeps the switch it was designed with.
- Cons: two switches for one job; "why is this greyed?" moments.
- Cons: the arbitration code still has to be written.

**C. The render inside the engine for stereo only; keep the fold for surround permanently.**
- Pros: Intensity can blend it; the device-boundary half stays untouched.
- Cons: surround never gets the render; "replaces the fold in the same slot" is withdrawn.

**D. Leave as written.**
- Cons: both run; the engine's own comment calls that a bug; two homes; a banned component in the design.

**Recommended: A.** Three answers to one question need one control, and exclusivity by construction beats arbitration code. The fold's badge and the bit-perfect wording belong in R1.1-B whatever S18 decides.

**What it changes in the plan.** S18's design (one home, no blend); S17's Intensity mapping names "spatial room amount"; R1.1-B carries the fold badge and the bit-perfect wording.

---

## Card 9 — Who builds "one playback owner", and when

**The question.** W2 — one place owning play/pause/seek, with the engine sending events instead of the app asking 20 times a second — has no slot in the plan. Who builds it, and when?

**Why it matters to you.** This card is about plumbing, so what you'd notice is indirect. W2 is "funded by" agent control, and agent control "waits for" W2 — a circle. Its size cannot fit the two-week rule. The R3 sprints need its events, but their rows don't say so. S14-lite says "depends on ENG" and "waits for W2" and uses neither. Separately, ENG moves processing to the device's own rate, which exposes a known gap nobody owns: on a Bluetooth headset with its microphone on (it drops to 16 or 24 kHz), the EQ would silently play flat. And the −0.1 dB wired ceiling leaves about 0.3 dB before a conversion nobody has measured; no other player runs a ceiling above −1 dB.

**How others solved it.** No outside evidence applies to the sequencing; it is ours. On the ceiling: Roon starts its headroom at −3 dB; the broadcast standard is −1 dB.

**Options.**

**A. ENG delivers the engine half (it already says so); S15 (masking research spike) — the first R3 sprint and the first consumer — carries the transport reducer and command layer; "S14's adaptive half" is dropped as a funder; S14-lite loses "Depends on: ENG"; ENG's acceptance carries the R1.1 behaviours to re-prove plus the under-44 kHz EQ gap; keep the −1 dB ceiling everywhere until ENG measures the conversion (Recommended).**
- Pros: W2 has a named home and a size; the circle is broken.
- Pros: S14-lite can start earlier.
- Pros: the Bluetooth-mic case and the unmeasured conversion get an owner.
- Cons: S15 is a 7-point research spike today; it grows a structural slice.
- Cons: with EQ on over wired outputs, peaks sit 0.9 dB lower than today until card 4's pre-gain and meter replace the moving ceiling.
What you'd hear: nothing new from W2 itself; the EQ still works on a headset in call mode; the faint level step when Intensity moves off zero disappears.

**B. Make agent control an R2 sprint of its own that starts with W2.**
- Pros: W2 gets a whole sprint; agent control arrives sooner.
- Cons: R2 grows by a sprint; a standalone structural sprint is what the "no waves" rule forbids (ENG was the one exception).

**C. Say the R3 sprints need only "a track-change event with the track's identity" (which ENG delivers), strike "W2 events" from their needs, and let W2 wait for its trigger bug.**
- Pros: the smallest change; no new slot.
- Cons: reactive — a wrong-song bug stays the trigger; the command layer agent control needs still has no home.

**D. Leave as written.**
- Cons: circular funding; R3 scheduled on work nobody is scheduled to do.

**Recommended: A.** It gives the structural job a home in the first sprint that actually consumes it, and it frees S14-lite from two dependencies it never had. If S15 cannot absorb the slice, C is the honest fallback and should be written down as such.

**What it changes in the plan.** S14-lite's dependency line; the W2 "funded by" line; S15's row; ENG's acceptance list; the ceiling rule.

---

## Card 10 — Your own litmus test, and a name clash

**The question.** Should every processing sprint end with you doing a blind, level-matched A/B on your own headphones and soundbar — a stage that doesn't win ships off and hidden — and should the built-in EQ preset called "Clarity" be renamed before the Clarity feature arrives?

**Why it matters to you.** No story makes "familiar music sounds more transparent on an A/B" the last line of S14-lite, S16 or S18. S16 is the one most likely to fail it: the project's own adaptive-tone study found no published test in which automatic EQ beats a finished master, and the council's "Clarity only if it wins a blind test" reached no story. The spatial story's test proves you can *hear a difference*, not that you *prefer* it — the wrong bar. Without this, a stage ships because it measured right, you stop using the processed mode, and the thesis never meets its one user. And "turn on Clarity" would mean two things; the "Loudness" preset was renamed "Bass & Treble" for exactly this kind of clash.

**How others solved it.** Roon's per-filter switches are described as "great for A-B testing" — that is the tooling, not the bar. The bar is yours.

**Options.**

**A. One acceptance line on S14-lite, S16 and S18 — a blind, level-matched A/B on your own headphones and soundbar, using the ready-made ladder (about 23 trials, capped at 60); a stage that does not win ships off and hidden. Rename the preset's display name to "Detail", stored id unchanged (Recommended).**
- Pros: the product's thesis meets its one listener before it ships.
- Pros: cheap — one evening per sprint.
- Pros: a losing stage is hidden, not deleted; it can be retuned.
- Pros: toasts and test reports stop being ambiguous.
- Cons: one evening of your time per sprint.
- Cons: a preset you know as "Clarity" appears as "Detail" (saved presets survive; only the label changes).
What you'd hear: only processing that beat the untouched file in your own blind test, on your own gear.

**B. Ship every stage off by default and skip the test.**
- Pros: cheaper; no evening.
- Cons: S16 and S18 carry no proof of value; you never learn whether the processed mode is worth switching on.

**C. Make the test each sprint's demo-day event.**
- Pros: a ritual the team learns from.
- Cons: the same cost as A plus ceremony; the listening must still be blind.

**D. Rename the feature instead (say, "Unmask") and keep the preset's name.**
- Pros: no change to something already shipped.
- Cons: the feature name runs through every document; "Unmask" is jargon to a listener.

**Recommended: A.** Your litmus test is the only acceptance criterion that measures what the product is for; writing it into three stories costs nothing now and an evening later. The rename is a one-line change that removes a guaranteed confusion.

**What it changes in the plan.** A last acceptance line on S14-lite, S16 and S18; the preset rename rides with the next EQ change (S12).

---

## Suggested order to decide

**Sitting one — before R1.1-B starts. The root: nobody owns level.** Cards 4, 1 and 5 together, in that order. Card 4 sets the rule for who adds up boosts and headroom; card 1 then places leveling under that rule and retires the old auto-leveller; card 5 decides where the fold sits relative to the one safety net. Take two small pieces of later cards in the same sitting because they land in R1.1-B: the fold's "5.1 → stereo" badge and bit-perfect wording (card 8), and the shared "not in bit-perfect mode" state that every effect control will reuse (the wording from card 1).

**Sitting two — before S14-lite, the first R2 sprint.** Card 3 (which volume compensation follows; cut-the-mids form), the principle of card 2 (Intensity never touches a hand-set switch, so S14's switch is built outside it), card 9 (strike "Depends on: ENG"; give W2 its slot), and card 10's acceptance line (S14-lite is the first sprint it applies to). These settle in one sitting; card 3 depends on card 4 only if you choose the boost form.

**Sitting three — before S12 and S13.** Cards 6 and 7. Card 6 needs card 4 decided (the ledger is one of its layers); card 7 needs card 6 (where correction lives decides how "offer and remember" is stored).

**Can wait — before S16 and S18.** The rest of card 2 (Clarity's own switch versus merging S16 and S17) and the rest of card 8 (the render's one home). Correct the stale S17 row now anyway; it costs nothing.

## Three decisions that would most change what you hear

1. **Card 1 — Leveling retires the old auto-leveller.** Left as is, the day Intensity returns two levellers run under your music, one drifting a decibel a second mid-song, and "Leveling: Off" stops meaning off.
2. **Card 3 — Loudness compensation follows the volume you actually turn.** On your setup (XM4 over Bluetooth, soundbar over HDMI, volume on the keys), the planned version does nothing at any level you use; the cut-the-mids form is the one that can never clip.
3. **Card 5 — The fold happens before the one safety net.** Otherwise every surround album you own plays compressed by default and without crossfeed — on exactly the files that sprint exists to fix.

A close fourth is card 7: it decides whether the first thing you hear on a fresh install is the file, or a correction you never chose.
