# Brainstorm — the sound-truth check on the ten decisions

*2026-10-23 · senior audio-DSP engineer · read-only. Inputs: `../technical-synthesis.md` (the ten decisions), the four reviewer reports beside it, and the code in `the testrig/integration checkout` @ e76edf6. Part 1 is for the founder, in plain words. Part 2 is the appendix with `Sources/…:line`, where a peer report is wrong or overstated, the measurement that settles each question, and what to prototype first.*

*Labels: a claim rests on the code (cited in Part 2), on a reviewer report, on a named reference, or is marked **(from DSP principle)**. Anything I could not check is marked **unverified**. Nothing below is called a founder decision unless a document already does.*

---

## Words used in Part 1

- **The sound engine** — everything Enhanced does to the music before it reaches the output.
- **Bit-perfect / the anchor** — the file goes out untouched, and the app can prove it byte for byte. Today a fresh launch is bit-perfect on Enhanced (nothing is on), and Pure Mode is bit-perfect by construction. Over Bluetooth the promise ends at the Mac: the link re-encodes the audio (that is why the ceiling is lower there).
- **The safety net** — the last stage of the sound engine. It watches for peaks that would go over a ceiling and, only in that instant, turns the sound down a little so they don't. It never turns anything up. On Bluetooth and AirPlay the ceiling is 1 dB under full scale; on a wired output with only the EQ on it is 0.1 dB under.
- **The ceiling** — that limit.
- **The volume** — whichever control sets how loud it is at your ear: the app's Master Gain slider, the Mac's volume keys, or the headphones' own buttons. On Enhanced, Master Gain is applied *after* the whole sound engine, so the engine never knows where it is.
- **Leveling / the level matcher** — a fixed turn-down or turn-up per track or album so songs sit at a similar loudness.
- **The old automatic leveller** — the thing in the engine today: it measures as the music plays and keeps nudging the level toward a target, 1 dB per second, for as long as the session lasts.
- **Loudness (the "loudness button")** — bass and treble brought back when you listen quietly, because the ear loses them first at low level.
- **"Squashed"** — what you hear when the safety net is working constantly rather than on the odd peak: the loud parts stop getting louder, drums lose their snap, the mix feels pressed flat.

**Your gear, and what it means for the sound.** Sony WH-1000XM4 over Bluetooth: the ceiling is −1 dB, the volume lives on the headphones, and the link is lossy either way. The soundbar over HDMI: locked to 48 kHz, which is also the engine's rate, so no hidden conversion after the engine; the Mac cannot set its volume ("Set on device"). The USB DAC coming: wired, so the EQ-only ceiling is −0.1 dB; if it runs at a rate other than 48 kHz there is a conversion after the engine that nobody has measured yet.

Risk scale: **none** / **small** (you might notice in a careful A/B) / **real** (you would notice on familiar music without trying).

---

# Part 1 — for the founder

## Decision 1 — Leveling (R1.1-B)

**Option A (the synthesis's pick): one fixed gain per track or album, set from the analysis the app already does; the old automatic leveller retired; Off / Auto / Album / Track; Pure says "Leveling off (bit-perfect)".**
- *What you'd hear:* on an album with a quiet intro and a loud chorus, nothing moves inside the song — the intro stays quiet, the chorus hits, exactly as mastered, only the whole album sits at your chosen level. Shuffle across a 1980s pop record and a modern loud master: the loud one is turned down to match. Nothing ever gets louder than the file can take without the safety net acting.
- *Sound risk:* **none** when Off; **none** when On, provided the gain is capped by each track's true peak (so the net stays asleep). The only thing you could notice is a gapless live album in Track mode — Auto handles that by using one album gain for it.
- *Faithfulness:* yes. Off is the default and leaves the anchor intact; On is a single constant multiply, the most transparent processing there is.

**Option B: keep the old automatic leveller as a visible "Adaptive" mode.**
- *What you'd hear:* the quiet intro gets turned up over about ten seconds; when the chorus arrives the engine is still turned up, so the chorus slams into the ceiling and the net squashes it; over the next minute the engine slowly eases back; the next track starts with whatever gain the last one left. On a quiet classical track after a loud pop record, the quiet one stays too quiet. This is the behaviour the council called "compression by default".
- *Sound risk:* **real** — pumping on loud records, a level that drifts during a song, carry-over between tracks.
- *Faithfulness:* yes only if it is off by default. But as a leveller it is technically unsound: it decides from a running average of the whole session and can ask for +12 dB, which the net then has to undo. No mature player ships this as leveling.

**Option C (added — from the players' report): on Pure, leveling as a cut on the device's own volume (the way MPD does it).**
- *What you'd hear:* Pure stays bit-perfect and loud tracks are turned down on the headphones' own volume; quiet tracks cannot be turned up (the device volume can only be lowered safely). The steps on Bluetooth volume are coarse, so "−4.2 dB" might land as −3 or −4.5 **(unverified on the XM4)**. *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)* The soundbar has no volume the Mac can set, so it gets nothing.
- *Sound risk:* **small** — coarse steps, cut-only.
- *Faithfulness:* yes; the file is never touched.

**My pick:** A, exactly as the synthesis has it, with Auto as the default once leveling is on. **AGREE.** Add C later for Pure if you want leveling there; "off and says so" is the honest first step. One thing to insist on in the story: the old leveller is *removed*, not just turned off — if it stays wired to the Intensity knob, the day Intensity comes back it comes back with it.

## Decision 2 — Intensity (S17)

**Option A (the synthesis's pick): Intensity scales only the automatic stages — how deep Clarity goes, how much room the spatial renderer adds — and never a switch you set by hand (Loudness, Leveling, crossfeed, EQ, correction).**
- *What you'd hear:* turning the knob changes *character* — more or less of the automatic clarity work, more or less room — and never changes how loud the music is or whether your own switches are honoured. At 0 you hear your own settings and nothing automatic.
- *Sound risk:* **none** — *if* the knob sets a parameter inside each stage. **Real** if it is built as a crossfade between dry and processed: today's crossfade adds up to 3 dB in the middle of the knob (so "half" sounds louder, which fools every A/B), and crossfading a room-rendered signal with a dry one makes a hollow, comb-like tone **(from DSP principle)**.
- *Faithfulness:* yes; at 0 the automatic stages are off and the anchor holds.

**Option B: keep Intensity hidden for good; every stage gets its own control.**
- *What you'd hear:* the same sounds, one control each. Nothing hidden behind a macro.
- *Sound risk:* **none.**
- *Faithfulness:* yes.

**Option C (added — from the chain report's alternative): Intensity as a visible macro that moves the other sliders, each of which shows it moved.**
- *What you'd hear:* as A, plus your Loudness or crossfeed setting changing when you touch the knob. Two hands on each control.
- *Sound risk:* **small** sound-wise, but it is the design most likely to make you distrust what you hear ("did I set that, or did the knob?").
- *Faithfulness:* yes if 0 means "my settings".

**My pick:** A, built as parameters, never as a crossfade; B is just as safe and simpler if the "one knob" idea isn't worth its cost. **AGREE** with the synthesis, with one addition it doesn't say outright: the current blend's +3 dB hump has to go whatever you choose, and the cleanest way is for the knob not to blend at all.

## Decision 3 — Loudness compensation (S14-lite)

First, the fact that makes this decision simple. Every form on the table is **the same tone curve** — bass and treble raised relative to the mids, growing as the volume drops. The only difference between the forms is *where the whole curve sits*: lifted so the mids stay put and the bass and treble go up ("boost", how the stories word it); dropped so the bass and treble stay put and the mids go down ("cut the mids", what CamillaDSP does when the volume is after the processing — our case); or set in between so the track's loudness doesn't change ("loudness-matched", how the architecture's LD-17 words it). At the same final loudness at your ear, **all three sound the same**. They differ in what they cost.

**Option A (the synthesis's pick): level = Master Gain + the device's own volume, relative to a one-time "this is my normal loud setting"; the cut-the-mids form; one cap; plain names; "not in Pure".**
- *What you'd hear:* at night you turn the headphones down and the bass and warmth stay with you instead of thinning out; the music gets a touch quieter than the volume alone would make it (the mids came down), so you nudge the volume up one notch. On a loud master nothing is squashed — the net never wakes, because nothing was turned up.
- *Sound risk:* **none** from the net. **Small** from one catch: when you nudge the volume up to make up for the cut, the engine reads "louder" and compensates a little less. Easy to fix in the design: the engine should measure the level as "volume minus its own cut". Say it in the story.
- *Faithfulness:* yes; off by default, and at your reference level the curve is flat.
- *A note on your setup:* with the XM4, the volume that matters is the one on the headphones. If pressing their buttons moves the Mac's volume slider, the engine can see it **(unverified — check once: press the headphone button, watch the Mac's slider)**. The soundbar's volume is invisible to the Mac, so there the engine only knows Master Gain — see B.

**Option B: a manual "Loudness amount" slider, labelled as such.**
- *What you'd hear:* a bass-and-treble tilt you set yourself and that stays put. It is a tone control, honestly named.
- *Sound risk:* **none.** But it does not do the one thing the feature exists for — follow the volume.
- *Faithfulness:* yes; off by default.
- *Where it belongs:* as the fallback for an output whose volume the Mac cannot read (your soundbar).

**Option C (added — the architecture's own wording, LD-17): the loudness-matched form — bass and treble up a little, mids down a little, the track's loudness unchanged.**
- *What you'd hear:* the same tone as A, with no volume nudge needed and no "reads louder" catch.
- *Sound risk:* **small** — the "up a little" costs headroom: on a loud master at the Bluetooth ceiling the net will act on the loudest passages, mildly. About half the cost of the boost form.
- *Faithfulness:* yes.

**Option D (the form the stories currently describe, US-TON-03: boost bass +6–10 dB, cap +12 dB).**
- *What you'd hear:* on a loud familiar master, with the headphones turned down, the net working constantly — squashed. The stories' numbers are also larger than the hearing model asks for: a 20 dB turn-down calls for roughly +5–8 dB in the deep bass at the *full* contour difference and about half that at the usual 50 % **(approximate; the standard's tables were not opened — unverified to the decibel)**. A +12 dB cap is a number nothing reaches unless you turn down 40 dB.
- *Sound risk:* **real** on loud masters on your XM4.
- *Faithfulness:* yes when off; but as a default-on "loudness button" it fails your litmus test on loud records.

**My pick:** A, with the "volume minus its own cut" level rule, the +6 bass / +4 treble figures as the cap (the model, not the cap, then decides), B as the fallback for outputs with no readable volume, and the stories reworded away from "boost". **AGREE** with the synthesis. One naming point for the cards: in this form the honest caption is "keep bass and treble at low volume", never "boost".

## Decision 4 — Headroom

**Option A (the synthesis's pick): one ledger in the engine that sums every tone layer per band, holds the sum at +12 dB, applies one turn-down ahead of the EQ so the net rarely has to act, and shows how hard the net is working.**
- *What you'd hear:* the curve you drew is the curve that plays, up to the clamp; beyond it the graph says "held" instead of lying. Loud records with a big EQ play a little quieter rather than squashed. An imported headphone correction plays at the right level without its author's worst-case turn-down making it needlessly quiet.
- *Sound risk:* **none** — this is the option that removes a risk.
- *Faithfulness:* yes; nothing in it runs unless a layer is on.

**Option B: separate budgets per layer, with the sum displayed.**
- *What you'd hear:* the same until the layers stack. Then the net does the summing by squashing, and the display tells you so after the fact.
- *Sound risk:* **real** once correction + taste + loudness meet in the bass: the net on constantly on loud records.
- *Faithfulness:* yes.

**My pick:** A. **AGREE.** This is the structural piece that keeps 3, 5 and 6 honest; put it in the first sprint that adds a second boost, as the synthesis says.

## Decision 5 — The 5.1 / 7.1 fold-down (R1.1-B)

Background in one line: folding six channels to two adds the centre and the surrounds into left and right; on a dense surround master the result goes over the ceiling on every loud passage (worst case +7.7 dB).

**Option A (the synthesis's pick): fold inside the sound engine, before the one safety net; one owner of the channel layout; the plumbing moved into R1.1-B.**
- *What you'd hear:* crossfeed works on surround albums (today it silently doesn't), there is one net instead of two in a row, and the EQ's level logic sees the stereo that reaches your ears. **But on its own this is still "squashed by default" on dense 5.1 masters** — the net is in the right place, and still working constantly. A quiet surround mix (classical) would be fine.
- *Sound risk:* **real** on dense surround masters unless paired with a trim (below); **none** on quiet ones.
- *Faithfulness:* yes for stereo files (untouched); for surround files there is no bit-perfect option anyway (Pure declines them).

**Option B: a fixed per-track turn-down computed from the folded true peak the analyser already can measure, so the net rarely acts; the second net kept as a rarely-acting backstop.**
- *What you'd hear:* a dense surround album plays 3–7 dB quieter and completely unsquashed; a quiet one barely changes. One brief hot peak in a track sets that track's turn-down, so the odd album is quieter than it needed to be — the classic trade of peak-based protection.
- *Sound risk:* **none** in the sound; **small** in level consistency between tracks (leveling fixes that when on).
- *Faithfulness:* yes.

**Option C (added — the question you asked): turn every surround file down 7.7 dB, no analysis.**
- *What you'd hear:* every surround album unsquashed and about 8 dB quieter than the stereo albums around it — a lot. Transparent, dumb, and always safe.
- *Sound risk:* **none** in the sound; **real** in level (you reach for the volume on every surround album).
- *Faithfulness:* yes.

**My pick:** A's *place* and B's *trim* together — fold inside the engine before the one net, and trim each surround track by its own folded peak so the net is a backstop; C only as the fallback when a track has no analysis yet. **DISAGREE** with the synthesis presenting A and B as either/or: A answers "where", B answers "how much", and dense surround masters need both. (The synthesis's "+3 dB on centred vocals" is also the wrong direction for a vocal that lives only in the centre channel — that vocal comes out 3 dB quieter per side; it is a vocal present in *both* centre and left/right that adds up. Detail in Part 2.)

One sound note on the fold the docs already decided (FD-9, "no LFE"): some music surround mixes put real bass in the LFE channel; dropping it loses the bottom octave on those albums. Worth a listen on one such album before it ships, not a re-decision.

## Decision 6 — EQ layers (S12 / S13 / S16)

**Option A (the synthesis's pick): one EQ programme = correction | taste | loudness layers → one design → one set of filters; one read-back so the graph draws what plays; Compare means only "without my EQ"; a separate "Bypass all processing"; one per-output memory.**
- *What you'd hear:* the graph is true; holding Compare takes away your taste curve and leaves your headphone correction and the loudness tilt in place — the fair comparison; "Bypass all" gives you the file.
- *Sound risk:* **none.**
- *Faithfulness:* yes.

**Option B: accept three filter engines in series, name which owns phase.**
- *What you'd hear:* mostly the same tone; in bands where two engines overlap, small ripples and a graph that no longer matches what plays. The phase shifts of ordinary minimum-phase EQ are not the audible problem; the broken "draws what plays" promise and a level logic that only knows one engine are.
- *Sound risk:* **small** today, growing with every layer.
- *Faithfulness:* yes.

**My pick:** A. **AGREE.** One sound detail for the engineers: Clarity's slow per-band changes fit inside the existing filters' own glide; it does not need a second engine.

## Decision 7 — Correction and spatial: opt-in or auto-on

**Option A (the synthesis's pick): off on a fresh install; the app *offers* and remembers; a chip for every stage that plays.**
- *What you'd hear:* on day one, the file as recorded. If you say yes to correction on the XM4, it is remembered for the XM4.
- *Sound risk:* **none.**
- *Faithfulness:* yes — this is what keeps "a fresh launch plays the file as recorded" true.

**Option B: auto-apply with a six-second Undo toast.**
- *What you'd hear:* on day one with the XM4 connected, a noticeably different headphone — a Harman-target correction on the XM4 pulls a good deal of bass out and reshapes the top **(the size is a reasonable expectation, not a measurement — unverified)** — before you touched anything. Later, spatial rendering on by default on any headphones. Undo helps once; the surprise repeats on every new output.
- *Sound risk:* **real** as a trust break; none as an artifact.
- *Faithfulness:* no.

**My pick:** A. **AGREE.** Also the only option that cannot double-apply a correction when a second pair of the same model shows up.

## Decision 8 — Headphones: one control or two

**Option A (the synthesis's pick): one "Headphones: Off / Crossfeed / Spatial" control; the spatial renderer at the output boundary for every source width; Intensity drives its room amount as a parameter.**
- *What you'd hear:* one thing at a time. Crossfeed: the gentle "speakers in a room" narrowing you have today. Spatial: the full room. Never both.
- *Sound risk:* **none.**
- *Faithfulness:* yes; Off is the default.

**Option B: two switches that grey each other out.**
- *What you'd hear:* the same, until a bug lets both run — then the centre vocal is smeared and the top dulled, because two head-shadow filters stack.
- *Sound risk:* **small** (it rests on the greying never failing).
- *Faithfulness:* yes.

**My pick:** A. **AGREE.** And the two sound rules this decision should carry: the room amount is a parameter inside the renderer, never a crossfade with the dry signal (crossfading a room-rendered signal with a dry one gives a hollow, comb-like tone); and with Decision 5A the fold happens before crossfeed, so a surround album on headphones gets crossfeed for free.

## Decision 9 — Sequencing (W2, ENG, S14-lite's dependencies)

**Option A (the synthesis's pick): ENG does the engine half of W2; S15 carries the rest; S14-lite loses "Depends on: ENG".**
**Option B: EP-MCP becomes an R2 sprint that starts with W2.**
- *What you'd hear:* nothing different — this is about order and ownership, not sound. The loudness button needs the device's volume, which already has a listener in the app (used only for Pure today); it does not need the new engine.
- *Sound risk:* **none** either way.
- *Faithfulness:* unaffected.

The one sound line hidden in this decision: **keep the ceiling at −1 dB on any output whose rate is not the engine's 48 kHz until the conversion after the engine is measured.** Your soundbar is 48 kHz-locked — no conversion, the −0.1 dB wired ceiling is safe there. A USB DAC at 44.1 or 96 kHz has a conversion after the engine that can push a −0.1 dB peak over. (Fair to note: a bit-perfect Off of the same hot master goes through that conversion at full scale too, so the EQ-only ceiling does not make things worse than the file itself — it just doesn't make them better.)

**My pick:** A, with the ceiling note scoped to "rate differs from the engine's". **AGREE.**

## Decision 10 — One blind A/B acceptance line; rename the "Clarity" preset

- *What you'd hear:* nothing changes in the sound; this is the thing that decides whether a stage ships on. The ladder already written in the adaptive-tone study (your own blind A/B, about 23 trials, loudness-matched within 0.2 dB, the baseline being the *static* version not Flat) is the right one.
- *Sound risk:* **none.** The risk is in not doing it: Clarity is the stage with no published evidence that automatic EQ beats a finished master.
- *Faithfulness:* a stage that doesn't win ships off and hidden — that *is* the faithfulness rule.

**My pick:** yes, with two scoping notes. For Loudness, run it quietly — that is the only level where it does anything — and the "A" is "with", the "B" is "without, nudged to the same loudness". For Spatial, the question is preference *and* "no smeared centre, no hollow tone"; a test that only shows "I can tell them apart" proves nothing. Rename the preset ("Detail"). **AGREE.**

---

## The six questions

**a. Loudness: "boost bass and treble when quiet" vs "cut the mids when quiet" — do they sound the same at the same final volume?**
Yes. Same curve, different starting height; once you have set the volume so the music is as loud as you want, the tone is identical. The catches: the *boost* form turns things up inside the engine, so on a loud record the safety net wakes up and squashes it — on your XM4 (ceiling −1 dB) on every loud familiar master. The *cut* form never wakes the net, but it makes the music a little quieter, you nudge the volume up, and the engine then thinks you are listening louder than you are and compensates slightly less — unless the design measures the level as "volume minus its own cut", which is a one-line rule to write down. The in-between "loudness-matched" form (the architecture's own wording) has neither catch in full and half the headroom cost; on Bluetooth it still touches the net on the loudest passages of loud records.

**b. Leveling: a fixed per-track gain vs the old automatic leveller, on an album with a quiet intro and a loud chorus.**
Fixed gain: the whole track moves once, by one number, before it starts — the intro stays as quiet relative to the chorus as the artist made it. The old leveller: it hears the quiet intro, decides the track is quiet, and turns it up by up to 12 dB over about ten seconds; the chorus then arrives into an engine that is turned up and hits the ceiling, and the safety net holds it down — that is a compressor, with the net as its gain control; then the leveller slowly backs off over the next minute; and whatever it ended on carries into the next track. "Compression by default" because the net was doing the levelling's dirty work on every loud passage, and because it ran whenever Intensity was above zero — not because anyone turned a compressor on.

**c. The fold: fold-then-net vs per-track trim vs "everything down 7.7 dB."**
Dense surround mix: fold-then-net squashes every loud passage (the net is working constantly); per-track trim turns the whole album down 3–7 dB once and leaves it unsquashed; −7.7 dB does the same, a little more than needed. Quiet surround mix (a classical recording): fold-then-net is fine (nothing reaches the ceiling); per-track trim leaves it almost untouched; −7.7 dB makes a quiet recording 8 dB quieter for no reason. So: trim per track, and fold *inside* the engine so crossfeed and the one net see the stereo you actually hear.

**d. Intensity as one knob over your own Loudness switch: what would you hear from 0 to 1?**
At night: the bass and treble coming back as you turn the knob up — the knob now doing the loudness button's job. In the daytime at your reference level: nothing, because there is no compensation to scale. So the same knob does something in one chair and nothing in the other, and at 0 it switches off a thing you turned on by hand. That is why it should never scale a hand-set switch.

**e. Correction + taste + loudness in one band: how loud can it get, and does the net protect hearing?**
As a request, +12 (taste) +6 (loudness) +5 or more (correction) = over +20 dB in the bass before anything stops it; today nothing sums them. The safety net protects the *signal* from going over the ceiling; it does **not** protect your ears from level. Put simply: the net stops the digital signal from clipping, not the music from getting louder at your ear. A heavily boosted and then net-held signal has the same *peak* as the untouched file and can be far *louder* on average — that is exactly what a mastering limiter does on purpose. What does protect hearing today: the taste EQ is loudness-neutral by design (it cannot make a track louder), Master Gain only turns down, and the headphones' own volume is yours. What would: the ledger's +12 dB *sum* clamp (Decision 4), and the hearing-safety loudness clamps in the architecture, which are design only and not shipped.

**f. Which single decision, taken wrong, would most likely make you stop using Enhanced?**
Decision 1 — leveling with the old automatic leveller left in the engine. It is the one wrong answer that makes the level *move during a song* on ordinary stereo music, and it is armed by the very knob (Intensity) the roadmap hands you to try Clarity: the first time you turn Intensity up to hear Clarity, the old leveller comes back underneath, and you would blame Enhanced. A level that drifts fails a level-matched A/B by definition — you cannot level-match something that moves. Runner-up: Decision 3 built in the "boost" form on your XM4 — the net squashing every loud familiar master at the −1 dB ceiling.

---

# Part 2 — Technical appendix

## The chain today, as it bears on the decisions

- Four kernel paths, selected by the settled Intensity ramp and the normaliser's glide: P0 bit-exact return (`Sources/AudioDSP/DSPKernel.cpp:210-230`), P1 EQ → crossfeed → limiter at the EQ-only ceiling (`:251-262`), P2 EQ → Clarity → BRIR → Loudness → crossfeed → limiter (`:263-270`), P3 equal-power blend of the EQ'd dry tap with the (stub) coloration chain, then the normaliser with its contribution weighted by `min(1, r/0.1)` and a ≥ 2 s glide (`:274-319`, `:348-351`). Crossfeed and the limiter are the output stages on every processed path (`:325-331`).
- The normaliser: `LoudnessParams{makeupGainLinear = 1, lufsTarget = −16, enabled = 1}` (`Sources/AudioDSP/include/TargetState.h:60-66`). Nothing outside `LoudnessModule` writes any of those fields — a grep over `Sources/` finds only the declaration (`TargetState.h:62`); `Realizer.mm` never touches `canonical_.loudness`. Its makeup is session-integrated: target = clamp(lufsTarget − integrated, −20, +12), slewed 0.1 dB per gated block ≈ 1 dB/s (`Sources/AudioDSP/Loudness/LoudnessModule.cpp:276-299`); `currentMakeupDb_` is reset only in `initialize()` (`:60`). The *meter* resets whenever a layout is published (`configureGraphForSource` → `publishChannelLayout`, `Sources/AdaptiveSound/AudioEngineBridge+ChannelLayout.swift:65-77` → worker reconfigure → `LufsMeter::configureChannels` → `reset()`, `Sources/AudioDSP/Loudness/LufsMeter.h:239-245`), i.e. per fresh start, not at a gapless seam — the council's C-38 reading holds.
- The loudness-neutral EQ gain is a different object: `TrackLoudnessGain` publishes −ΔL into `eq.outputGainDb` (`Sources/AudioDSP/AudioEngine/Realizer.mm:418`, `:483-493`), 0 when the EQ is Off or flat (`Sources/AudioDSP/Loudness/TrackLoudnessGain.cpp:104-109`), clamped ±12 (`:13-14, :120`), with its own glides and the gapless-group rule (`:247-270`).
- The limiter: 3 ms look-ahead, 8× polyphase true-peak detector, two-branch dB-domain release (`Sources/AudioDSP/Limiting/LimiterModule.h:13-37`); working ceiling = ceiling × 0.969 (`:103-105`); ceiling −1 dBTP, or −0.1 dBTP on P1 for wired transports (`Sources/AudioDSP/Limiting/OutputCeiling.h:19-40`; `Sources/AudioDSP/include/AudioConstants.h:16-21`). The documented cost at −1 dBTP with the EQ on: > 1 dB of GR up to 74 % of the time on a −9 LUFS master (`OutputCeiling.h:6-8`).
- Master Gain on Enhanced is `playerNode.volume` (`Sources/AdaptiveSound/AudioEngineBridge+MasterGain.swift:44-46`), turn-down only (`Sources/EQEditKit/MasterGainLaw.swift:43-48`); the kernel and Realizer receive no level intent at all (`Sources/AudioDSP/AudioEngine/Realizer.h:118-146`). The device's volume is read and followed only while Pure holds it (`+MasterGain.swift:140-156, 171-185`).
- The spatial AU only copies (`Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp:76-92, 163-176`); it derives N and M from bus formats alone (`Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:249-252`); it has no limiter. The graph is player → effects → spatial → mixer (`Sources/AdaptiveSound/AudioEngineBridge+Graph.swift:64-73`). The `ChannelLayout` the fold and S18 need already carries weights, azimuths and the LFE flag (`Sources/AudioDSP/include/ChannelLayout.h:17-24`; `Sources/AudioDSP/Loudness/ChannelLayoutDecoder.cpp:159-231`).
- Crossfeed: bs2b re-implemented, stereo-only (`Sources/AudioDSP/Spatial/CrossfeedModule.cpp:49-54`), gain law `1/(1 − G_hi + G_lo)` folded into the numerators (`Realizer.mm:52-58, 84-92`), so a centred signal passes at exactly 0 dB at DC and no path alone exceeds unity.

## Decision 1 — Leveling

**Facts.** Routing leveling through `TrackLoudnessGain` → `eq.outputGainDb` works on P1 (the EQ module applies its output gain whether or not any bell is active; the identity test requires 0 dB, `Sources/AudioDSP/EQ/EQModule.h:25-28`), so a leveled track with the EQ Off leaves P0 — correct, it is not bit-exact — and plays the gain alone. Two things the story must add: (i) a **true-peak field in the analyser profile** — `TrackLoudnessProfile` has none (`Sources/AudioDSP/Loudness/TrackLoudnessProfile.h:88-108`); the 8× `TruePeakKernel` the limiter shares with the meter's readout (`LimiterModule.h:99-101`) is the oracle-verified detector to reuse, so the cap "ceiling − TP" is exact and the limiter never acts; (ii) a rule for the **gapless-group lock** (`TrackLoudnessGain.cpp:247-270`): in Track mode a continuous seam would hold the previous track's gain — the right answer is Auto's album gain for a gapless group, which is what Roon's Auto rule gives anyway (players' report F8).
**Where a peer is overstated.** The synthesis's "rides a seam the engine counts a buffer early (KI-GAP-02)": that issue is scoped to *resampled* seams to another rate or width (`docs/product/known-issues.md:52, 218`); same-format seams are not early. Minor.
**Option B is unsound as a leveller (from DSP principle):** a session-integrated gain with a 1 dB/s slew, a +12 dB cap and a true-peak limiter downstream is a slow feed-forward compressor whose gain computer is the limiter; EasyEffects' Autogain is the only shipping analogue and nobody calls it leveling.
**Measurement.** (1) libebur128 oracle on the published gain per track/album. (2) GR meter = 0 dB over the whole leveled corpus (the TP cap holds). (3) An Intensity sweep 0 → 1 → 0 with Leveling Off: integrated LUFS unchanged within 0.1 dB (proves the AGC is gone, not hidden). (4) Seam test: a gapless pair in Album mode shows one constant gain across the seam.
**Prototype first.** Nothing — it is a removal plus one published number. Add the TP field to the profile and run (2) on the founder's loudest albums.

## Decision 2 — Intensity

**Facts.** The blend is equal-power on correlated wet ≈ dry: +3.01 dB at r = 0.5 by the kernel's own comment (`DSPKernel.cpp:285-288`); today "the normaliser downstream absorbs" it only on P3 — with Leveling Off nothing absorbs it. Clarity and BRIR are pass-through stubs (`Sources/AudioDSP/Clarity/ClarityModule.h:26-34`; `Sources/AudioDSP/Spatial/BRIRModule.h:26-33`). Crossfeed is outside the blend at full strength (`DSPKernel.cpp:321-331`; `TargetState.h:89-91`).
**The sound rule (from DSP principle).** A Clarity whose wet is an EQ-like change of the dry is near-fully correlated: any wet/dry crossfade has a level hump unless correlation-compensated (C-40), and a BRIR'd wet crossfaded with dry produces comb filtering from the BRIR's delays against the undelayed dry. Scaling *parameters* (Clarity depth, room gain) has neither problem and makes Intensity 0 ≡ stage off ≡ P0-eligible.
**Measurement.** Pink noise and a correlated wet (Clarity at minimal depth): output LUFS flat within 0.2 dB across a slow 0 → 1 sweep; the Loudness/crossfeed/leveling state bytes in `TargetState` unchanged across the sweep (a control-plane assertion).
**Prototype first.** The level-vs-knob sweep on today's blend with a "wet = dry + 0.5 dB shelf" stand-in — one plot that shows the hump and settles the crossfade-vs-parameter question.

## Decision 3 — Loudness compensation

**Facts.** No compensation code exists. Today's −ΔL is computed over the whole realised design (`Realizer.mm:418`), so a tilt folded into the single EQ intent *is* neutralised — the C-09 observation is correct for the current contract. The level problem is real: Master Gain is downstream of the kernel; the HAL volume listener exists but is gated to Pure (`+MasterGain.swift:140-156, 171-178`). JRiver keys Loudness to internal volume + a reference calibration; CamillaDSP switches to `attenuate_mid` when the volume is after the DSP (players' report §1, README opened).
**The three forms are one family (from DSP principle).** Let C(f, V) be the contour-difference tilt at volume V. Boost = C; loudness-matched = C − ΔL(C, track) (the architecture's "loudness-matched makeup", which the existing predictor can compute per track); attenuate-mid = C − max_f C. At equal final loudness the spectra are identical; they differ in headroom (max C, ~ΔL less, 0) and in the level-reading loop. The attenuate-mid under-compensation: if the listener restores loudness by raising the fader, the effective compensation is reduced by a factor ≈ 1/(1 + f) where f is the dB-of-cut per dB-of-turn-down (~0.3 at 50 % of the contour difference → ~23 % less than designed). Fix: define level := fader − (the layer's own broadband loudness change), i.e. use the loudness-matched offset *for the level reading* while publishing the attenuate-mid offset *for headroom*. Then there is no loop and no headroom cost.
**Numbers.** ISO 226:2023 was not opened (neither by me nor by the peers); from memory the 80 → 60 phon difference is roughly 5–8 dB at 50–100 Hz and 1–3 dB at 8–12 kHz — so FR-TONAL-03's +6/+4 caps are the right order and US-TON-03's "+6–10 dB bass, +12 cap" exceeds the full contour difference. **Unverified to the decibel; the spike should tabulate it.**
**Bluetooth volume.** Whether the XM4's own buttons move the Mac's HAL volume (AVRCP absolute volume) is **unverified**; if they do, the existing listener sees them; if not, no app can. The HDMI soundbar reads `.fixed` (`+MasterGain.swift:209-213`) — level unknown → manual slider fallback.
**Measurement.** (1) A 20 dB fader step: the realised response changes by the designed tilt (sweep through the chain, read back the composed curve). (2) GR meter = 0 dB on a −9 LUFS master with compensation at full depth (attenuate-mid never engages the net; the boost form would show sustained GR — the OutputCeiling.h number is the prediction). (3) The level-loop check: after the listener restores loudness, the published tilt equals the designed one at the *perceived* level. (4) The blind ladder at low level, with vs without, loudness-nudged.
**Prototype first.** One evening on the XM4: the same curve in the three offsets, pre-rendered, at a 20 dB turn-down, on three familiar loud masters. It settles form, cap and the loop in one sitting and needs no product code.

## Decision 4 — Headroom

**Facts.** Three independent ±12 s: EQ points (`Sources/EQEditKit/EQBands.swift:26`; `Realizer.mm:209`), −ΔL (`TrackLoudnessGain.cpp:13-14, 120`), AGC makeup (`LoudnessModule.h:55-56`); realised bells reach ±33 dB on adversarial commands (`Sources/AudioDSP/EQ/GraphicEQDesigner.h:43-45`). No sum exists; the architecture's cumulative +12 dB clamp is design only (`docs/architecture/architecture.md:346-358`). AutoEq's `Preamp:` is peak-based (`−compound.max_gain`, players' report F4); ours is loudness-based.
**What the ledger must publish (from DSP principle).** Two different numbers that today are conflated: a *loudness* offset (−ΔL over the composed curve, per track — exists) and a *peak-safe* pre-gain = min(0, ceiling − (TP_track + max boost of the composed curve)) — needs the profile's TP field (Decision 1) and the composed read-back (Decision 6). The published broadband gain is the smaller of the two. With the wired −0.1 dBTP ceiling this pre-gain is what prevents "EQ On squashed" without moving the ceiling; decision 29 then stands on its loudness reason alone.
**Where a peer conflates two things.** "+23 dB of request in one band" (synthesis #4) is right as a *peak* request and wrong as a *hearing* figure: the taste layer is loudness-neutral, so its loudness contribution is ~0; only the layers exempt from neutrality (compensation; correction if its preamp is dropped without −ΔL covering it) raise loudness. The hearing-safety argument belongs to the architecture §11 loudness clamps, not to the point clamp.
**Measurement.** Stacked worst case (taste +12 at 60 Hz + compensation at full + an HD 650 correction) on a bass-heavy −9 LUFS master at the wired ceiling: ledger output ≤ +12 dB in-band, GR meter < 0.1 dB, LUFS change of the whole program vs Off within the compensation's own designed amount. The drawn-vs-played log sweep through the chain against the composed read-back.
**Prototype first.** The stacked worst case above with a GR meter — one number per track on the founder's corpus.

## Decision 5 — The fold

**Facts.** The limiter is inside the effects AU (`DSPKernel.cpp:325-331`); the spatial AU has none; crossfeed is bypassed at N ≠ 2 (`CrossfeedModule.cpp:49-54`) and sits upstream of the fold at width N. BS.775-4 Table 2: L′ = L + 0.7071·C + 0.7071·Ls (players' report, PDF opened). Worst-case coherent sum 1 + 0.7071 + 0.7071 = 2.414 → +7.66 dB.
**Where the peers are wrong.** "+3 dB on centred vocals" (synthesis #5, players' F2): a vocal present *only* in C folds to 0.7071 in each of L′ and R′ — **−3.0 dB per side**, and equal overall loudness (two channels at half power). A vocal present at equal level in L, R *and* C sums coherently to 1.7071 → **+4.6 dB per side**. Phantom-centre-only (L = R, no C) is unchanged. So the fold does not threaten the ceiling on the ordinary film/music centre-channel vocal; it threatens it on dense mixes where correlated content sits in front *and* centre or front *and* surround.
**Loudness after the fold (from DSP principle).** Uncorrelated: stereo loudness = P_L + P_R + P_C + 0.5(P_Ls + P_Rs) vs the 5.1 figure P_L + P_R + P_C + 1.41(P_Ls + P_Rs) — the fold reads 1–2 LU under the 5.1 measurement when surrounds carry a modest share; leveling for N > M should use the folded figure (chain report F13 is right).
**Why A and B are not alternatives.** A fixes location (one net; crossfeed and the EQ's gains see the stereo reaching the device; S18 renders in the same place). B fixes magnitude (static trim from the analysed folded TP so the net is a backstop). A alone is sustained GR on dense masters (the OutputCeiling.h behaviour, now on every loud passage); B alone keeps two nets and no crossfeed on surround files. The −7.7 dB constant is the no-analysis fallback. The "one brief peak sets the trim" trade can be softened by trimming to a high percentile of the folded TP and letting the backstop catch the remainder — a tunable, to be decided by the histogram below.
**Measurement.** (1) The analyser's folded TP vs the measured TP of the actually folded stereo (oracle). (2) GR meter on the founder's surround albums with the trim: ~0. (3) C-only sine: −3.0 dB per side. (4) A stereo-in-5.1 file (C/Ls/Rs silent): the folded crossfeed output equals the stereo crossfeed output (null).
**Prototype first.** Run the folded-TP analysis over the founder's 5.1 albums and histogram the trims — if most sit within 0–3 dB, the per-track trim is cheap and the −7.7 constant is clearly too much; if they cluster near 7 dB, the constant is nearly as good.

## Decision 6 — EQ layers

**Facts.** One engine: 31 SVF bells, WLS-solved so the cascade plays the drawn points (`GraphicEQDesigner.h:9-21`); the graph reads back the finished coefficients (`:22-24`). Compare publishes the identity with 0 dB gain (`Realizer.mm:399-401, 410`; `TrackLoudnessGain.cpp:106-109`) — level-fair by construction today. The predictor is already defined for any band response, not just the 31-band design (`TrackLoudnessProfile.h:123-126`), so a composed `EQProgram` gets −ΔL over its sum for free.
**Sound truth on two engines (from DSP principle).** Two minimum-phase cascades in series sum their phase and ripple; the phase is not the audible issue at EQ-sized gains, the mismatch between the drawn and played curve is (the WLS solve assumes it alone plays the targets). Shelves are feasible on the SVF by Simper's mixing (council P1 via chain report §4).
**Measurement.** Log sweep through the chain vs the composed read-back (≤ 0.1 dB); Compare's LUFS with vs without within 0.2 dB with correction and compensation left in.
**Prototype first.** None needed; the contract change is the work.

## Decision 7 — Correction / spatial defaults

**Facts.** Fresh install: EQ Flat and Off, Intensity 0 hidden and never persisted, crossfeed off (listener report §3; `Sources/AdaptiveSound/AudioViewModel.swift:188, 201`). The per-output pin auto-loads by UID with a model fallback (listener report F7) — the double-apply path if correction were written into it.
**Measurement.** A fresh-install MD5 null with the XM4 connected and a Harman correction available: bit-identical to source. A two-devices-same-model test: one correction, not two.
**Prototype first.** None.

## Decision 8 — Headphones

**Facts.** `TargetState.h:100-105` records the exclusivity with "no arbitration code yet"; `BRIRModule` is N → N in the effects AU inside the blend (`DSPKernel.cpp:61, 431-436`) while S18's render is N → M at the spatial AU — only one can fold. bs2b never boosts (gain law above), so crossfeed before the limiter costs nothing.
**Measurement.** A state-machine test that `crossfeed.enabled && brir.active` is unreachable; a sweep through Spatial with room at every Intensity: no comb structure in the magnitude (the signature of a wet/dry crossfade with a delayed wet).
**Prototype first.** None until S18's spike.

## Decision 9 — Sequencing; the ceiling note

**Facts.** S14-lite's code lives in the Realizer, which ENG leaves alone; the device-volume listener is a HAL listener, not an engine event (`+MasterGain.swift:150`). The graph runs at 48 kHz on every edge; a device at another rate gets AUHAL's output-side conversion, unmeasured (architecture report §1; `docs/architecture/architecture.md` §2.5). The EQ-only working ceiling is −0.1 dBTP × 0.969 ≈ −0.37 dB, with a < 0.17 dB detector under-read (`LimiterModule.h:103-105`), so ~−0.2 dBTP reaches the conversion.
**Verdict.** Keep −1 dBTP for any output whose rate ≠ the graph rate until measured; the soundbar (48 kHz-locked) and the EQ-only wired case are unaffected. The synthesis's "nobody runs above −1 dBTP" is true but the relevant comparison is the bit-perfect Off of the same master, which crosses the same conversion at 0 dBFS — the EQ-only ceiling matches that exposure, it does not add to it.
**Measurement.** A −0.1 dBTP test signal through the 48 → 44.1 kHz AUHAL path, peak measured at a HAL tap or loopback; if the overshoot exceeds the 0.27 dB margin the ceiling rule needs the rate condition.
**Prototype first.** That one measurement, on the USB DAC when it arrives.

## Decision 10 — The acceptance line

**Facts.** The ladder: three conditions (original, static, adaptive), loudness-matched within 0.2 dB, pre-registered tracks, Stage 1 = the founder's own blind A/B with a sequential test (~23 trials if real, cap 60), baseline = the static version not Flat (`docs/design/adaptive-tone/README.md` §6). The study's own finding: no published test shows automatic EQ beating a finished master (`:50`).
**Per-stage scoping.** Loudness: run at a 20 dB turn-down, "with" vs "without nudged to equal loudness". Clarity: adaptive vs the static "Detail" preset, then vs original. Spatial: preference plus an artifact checklist (centre smear, comb/hollow tone, bass mono integrity); ABX difference is not the bar.
**Prototype first.** The blind player with pre-rendered files the study already proposes (no product code).

## Corrections to the peer reports, collected

1. "+3 dB on centred vocals" from the fold (synthesis #5; players' F2): −3 dB per side for a C-only vocal; +4.6 dB only when the vocal is in C *and* L/R. Direction matters for whether the net acts on vocals.
2. "+23 dB in one band" as a hearing figure (synthesis #4): a peak request, not a loudness one; the taste layer is loudness-neutral.
3. KI-GAP-02 "a buffer early" (synthesis #1): only at resampled seams to another rate or width.
4. "Nobody runs above −1 dBTP" (synthesis #10): true, but the exposure on the EQ-only wired path equals the bit-perfect Off's, not more; the rate condition is the real refinement.
5. The synthesis's Decision 5 as "either/or": location and magnitude are separate problems; dense surround masters need both.
6. LD-17 "loudness-matched makeup" vs C-09 "exempt from neutrality" (architecture report F9 vs chain report F4): not a contradiction to pick a side on — the two are different broadband offsets of one curve; use the loudness-matched offset for the level reading and the attenuate-mid offset for headroom, and both documents are satisfied.
