# Quality pass — the twelve cards re-ranked by what a music lover hears

> *Correction, 2026-10-25: Pure declines Bluetooth, so on the founder's XM4 the app always plays Enhanced; where this record calls Pure the founder's daily mode, that premise was wrong. Leveling in Pure was deferred until the USB DAC arrives ([sprint plan §11](../../../sprints/sprint-plan.md)).*

*2026-10-23 · product manager · read-only. Rule for this pass: rank by the end product as a listener meets it; cost, sprint fit and delivery time ignored. Sound facts are the sound engineer's, taken as given; where I go beyond the documents it is marked "my judgement". Pages opened: Apple's AirPods Pro page (apple.com/airpods-pro), Sony's help guide and Tom's Guide's write-up of Sony's "Find Your Equalizer", Spotify's volume-normalization page (support.spotify.com/us/article/volume-normalization).*

## The criteria, with three refinements

Q1 nothing wrong · Q2 nothing surprises · Q3 consistent · Q4 full at low volume · Q5 headphones like a room · Q6 the blind A/B — plus faithful by default, honesty, hearing safety. Three refinements a music lover would make (my judgement):
- **Q6 splits in two.** For anything that plays *by default*, the bar is "I can't tell it from the file". For anything Enhance turns on, the bar is "I prefer it" — "can't tell" is harmless but not worth a switch.
- **Q3 is not "sounds the same on every output"** (a soundbar never sounds like headphones). It is "the same controls do the same things on every output, and the app says, in words, when an output can't do one of them."
- **Q7, "I can say what it did."** A listener's trust rides on the chip naming the change in plain words, not on the sound being right. This is the honesty promise extended from bit-perfect to every stage.

## Part A — the cards

### Card 1 — Leveling
1. **A + C** — albums at one level in both modes, including the bit-perfect mode the listener lives in; nothing ever moves inside a song. Wins Q1, Q2, Q3. C's costs: Pure levels come in whole steps and cut-only; the Mac's volume readout moves on its own at track changes (a small Q2 wobble unless the readout explains it); the soundbar gets nothing in Pure (no volume the Mac can set).
2. **A alone** — the same, but "Leveling off (bit-perfect)" on the daily driver: honest, and a Q3 loss the listener meets every time they shuffle across eras in Pure.
3. **D** — ≡ A once it lands (only the date differs, which this pass ignores); until then no leveling at all.
4. **E** — leveling exists, but an unanalysed track gets a live guess that moves the level during the song (Q1, Q2), and the day Intensity returns a second leveller wakes underneath (Q1, real).
5. **B** — compression by stealth: the intro turned up, the chorus squashed, the gain carried into the next song. Fails Q1, Q2 and Q6 outright.

**Experience-best:** A with C added, plus the sound engineer's three must-says (removed, not switched off; a true-peak number; a gapless album takes the album gain). **Differs from the README?** Yes, in one thing: the README parks C as a follow-up for risk and cost. By experience, leveling that doesn't work in the listener's daily mode is the one feature they'll expect to "just work" and find doesn't. In the interim they lose even levels in Pure, and they will notice — it is why people turn leveling on.

### Card 2 — Intensity and Clarity
1. **A ≡ B to the listener** — the same sounds; A reaches them with one knob over the automatic stages, B with one control per stage. Both honour every hand-set switch (Q2) and leave zero = nothing automatic (faithful). My judgement on the tie: a music lover looks for "room amount" next to the Headphones control and "Clarity depth" next to Clarity; one knob that moves both means you can't have a full room with light Clarity. A is fine only if those two settings stay visible on their own rows and Intensity is a convenience over them.
2. **D** — Clarity reachable only through the knob: fine until Spatial arrives and the same knob moves the room too (a small Q2 loss against A).
3. **C** — your Loudness or crossfeed setting moves when you touch a different knob: Q2 and trust ("did I set that?").
4. **E** — Intensity at zero silently switches off a Loudness you turned on; a level hump mid-knob fools every A/B (Q1, Q2); Clarity ships into a path nobody hears.

**Experience-best:** A built as settings, with B's layout visible underneath. **Differs?** No. Either way the mid-knob level hump must go — a knob that gets louder in the middle reads as "better" and is a lie.

### Card 3 — Loudness compensation
Level source:
1. **A** — on the XM4, turn the headphones down and the bass stays (Q4); on the soundbar an honest manual amount. The one-time "this is my normal loud setting" is a setup step listeners accept for personalisation — Sony's "Find Your Equalizer" and Apple's Personalized Spatial Audio profile are both setup steps. Open: whether the XM4's own buttons reach the Mac's slider (unverified in the docs); if not, the listener must learn "use the Mac's keys", a Q2/Q3 catch the caption has to state.
2. **B** — a warmth you dial in once; honest, never surprising, but it does not follow the volume, so it is a tone control wearing the loudness button's name; stacks with your EQ.
3. **C** — does nothing at any volume the listener actually uses on either output (Q4 fail) while its switch says it's on (Q2, Q7).

Form (at the same final loudness all three sound the same — given):
1. **Cut the mids, with the "volume minus its own cut" rule** — never squashes (Q1); the only cost is one notch of volume. The sound engineer's combined form (loudness-matched for the level reading, cut-the-mids for headroom) has neither the notch nor the headroom cost and is the one to prototype first.
2. **Loudness-matched** — no notch to nudge, but touches the net mildly on the loudest records on the XM4 (small Q1).
3. **Boost** — the net works constantly on loud familiar masters on the XM4: squashed. Fails Q1 and Q6 on the records the listener knows best.

**Experience-best:** A, cut-the-mids with the rule (or the combined form), caps +6/+4. **Differs?** No. Q3 note: the soundbar getting a manual amount is unavoidable (the Mac cannot read its volume) and matters less than it looks — late-night listening is the headphones case (my judgement).

### Card 4 — Headroom
1. **A** — stacked boosts stay inside the cap; a loud record with a big EQ plays a little quieter instead of pumping; the graph says "held" instead of drawing something it doesn't play; a readout shows when the net is working. Wins Q1, Q2, Q7.
2. **C** — nothing stacks until correction arrives, then taste and correction meet in the bass with nobody adding (Q1 small now, real after S13).
3. **B** — the net does the adding by squashing and the display tells you afterwards (Q1 real once three layers meet; Q7 half-honest).
4. **D** — nobody adds anything; the graph lies past 12 dB (Q1 real, Q2).

**Experience-best:** A. **Differs?** In timing only — and the timing is audible. The README gives R1.1-B just the one-line principle and builds the peak-safe turn-down in S14-lite because that is the first sprint with a *second* boost. But the squash exists with *one* boost: the documented cost of EQ-on at the Bluetooth ceiling is the net working up to three-quarters of the time on a very loud master. A listener with a bass lift on a loud record on the XM4 hears that now and until S14-lite, on familiar music. By experience, the true-peak number card 1 adds should cap every gain the engine applies, not just leveling's (my judgement: it needs only what R1.1-B already adds, the true peak and the drawn curve's biggest boost).

### Card 5 — The fold
1. **A's final arrangement** — a dense surround album plays unsquashed and only as much quieter as it needs to; crossfeed and later the spatial render work on it exactly as on a stereo album; one net. Wins Q1, Q3, Q5.
2. **A's interim** — unsquashed from R1.1-B on (Q1 win), but no crossfeed on surround albums and a second, rarely-acting net. The second net is inaudible by design; the missing crossfeed is not: a crossfeed user hears surround albums "in the head" and stereo albums "in a room" (Q3, Q5), and the badge must not show XF.
3. **B as written** — crossfeed on surround, but without the trim the net works constantly on dense masters: squashed (Q1 real).
4. **C** — unsquashed, but every surround album about 8 dB quieter than the stereo albums around it, and a quiet classical surround recording made quieter for nothing (Q3 real; leveling hides most of it when on, but it is off by default).
5. **D** — squashed by default, two nets, XF showing when nothing plays (Q1, Q2).

**Experience-best:** A's final arrangement. **Differs?** Not in destination. The interim's loss is crossfeed on surround — a crossfeed user notices on every surround album; a non-user never does. The thing a listener would push back on hardest isn't on the option list: the fold drops the LFE channel (the docs record this as decided), and on music mixes that put real bass there the bottom octave disappears — "where did the bass go?" is a Q1 fail heard without trying. The "one listen before it ships" should be a pass/fail on such an album, not a formality.

### Card 6 — EQ layers, Compare, per-headphone memory
1. **A** — the curve on screen is the curve playing (Q2, Q7); Compare answers the question a listener actually asks ("is *my* curve helping?") on corrected headphones (Q6 fair); one toast on plug-in; one memory. The full S13 inside it — recognise the headphones, offer their correction — is the one "this app knows my headphones" moment.
2. **D** — ≡ A in the end product (order only).
3. **C** — the same sound; a hold-to-hear button that opens a menu is awkward in the hand, and "without everything" already exists as Bypass all.
4. **E (S13 narrowed to manual import)** — the sound is right for whoever imports a file; nobody else ever meets the feature. A music lover doesn't know what an AutoEq file is; the offer toast is how they'd discover correction at all. They'd notice by absence, not by sound.
5. **B** — where two engines overlap, small ripples and a graph that no longer matches what plays (Q2 small, growing with each layer).
6. **F** — Compare means three things, three memories compete on plug-in, an imported correction plays 6 dB too quiet or hits the ceiling (Q1, Q2).

**Experience-best:** A with the full S13. **Differs?** No — the README recommends A and keeps identification in S13. If S13 were ever narrowed to E for size, the loss is the recognition moment. Cutting the third "profile" part down to "correction + taste" loses nothing a music lover would look for (my judgement: per-output memory plus Enhance covers it).

### Card 7 — Correction and spatial switching themselves on
1. **A, with a hold-to-hear preview on the offer** (my addition) — the first sound from a fresh install is the file; the toast says "Sony WH-1000XM4 recognised — hold to hear it corrected"; one tap keeps it for these headphones; remembered. Faithful, Q2, Q7, and the better sound one hold away (see B.1).
2. **A as written** — the same minus the preview: the listener must say yes to something they haven't heard. Honest; a weaker first impression.
3. **C** — one switch is simple, but headphones on a DAC read as "USB" and get nothing, and a second pair of the same model isn't told apart. Q3 fails on the gear coming to the desk.
4. **B** — the first thing a fresh install plays is a correction the listener never chose; on the XM4 it pulls bass out and reshapes the top (a reasonable expectation, not a measurement). Undo is a race; the surprise repeats on every new output. Fails faithful-by-default and Q2 — the "messed with my headphones" first impression.
5. **D** — processed first launch, three readings of the switch, double-apply on a second pair.

**Experience-best:** A with the preview. **Differs?** Only by the preview. The README's A is right on faithfulness; the preview is what makes it also win the first impression.

### Card 8 — Headphones: one control or three
1. **A** — pick Crossfeed or Spatial, never both; surround and stereo albums get the same treatment (Q3, Q5); the badge names which (Q7).
2. **B** — ≡ A until a bug lets both run (smeared centre, dull top — Q1); two switches for one job.
3. **C** — surround albums never get the render (Q3), and a render that Intensity blends risks the hollow comb tone (Q1).
4. **D** — both run; the engine's own comment calls it a bug.

**Experience-best:** A. **Differs?** No. One listener addition (my judgement): each position needs one line of plain words and a hold-to-hear, or "which do I pick?" becomes the question.

### Card 9 — One playback owner; the Engine sprint's neighbours
Nothing here changes the sound except two lines inside A: the ceiling stays at −1 dB on any output whose rate differs from the engine's until the conversion is measured, and the Bluetooth-headset-with-mic case (the EQ silently playing flat) gets an owner.
1. **A ≡ B in sound** — A names the two lines. The ceiling line costs under 1 dB of level on a non-48 kHz wired output with EQ on — below what a listener notices — and keeps EQ-on from adding any clipping risk the file itself doesn't carry (Q1). The mic case is a Q2/Q7 fail today: the screen says EQ on, the ears get flat.
2. **C** — the smallest change; the mic case and the conversion stay unowned, so the Q2 fail persists.
3. **D** — as C, with R3 scheduled on nobody.

**Experience-best:** A. **Differs?** No.

### Card 10 — The litmus test; the name clash
1. **A** — only processing that beat the file on the listener's own gear ever ships on; a loser is hidden, not deleted. This card *is* Q6. "Detail" for the preset reads naturally.
2. **C** — ≡ A in the end product; the loser is found later, and the listener never meets it either way.
3. **D** — same sound; "Unmask" is a word a listener has to learn.
4. **B** — stages ship off with no proof; the listener never learns whether switching Enhanced on is worth it, and the Enhance front door cannot exist (it needs winners).

**Experience-best:** A, with two refinements (my judgement): the bar for a stage Enhance turns on is "prefer", not "can't tell"; and the test runs on both outputs and at the volume the listener actually uses (the Loudness test quietly — already scoped). **Differs?** No.

### Card 11 — An "Enhance" front door
1. **A** — one tap to the better sound, a chip that names what's on in plain words, the per-stage switches underneath for the curious. Q6 by construction; Q7 if the chip is honest.
2. **B** — nothing wrong, nothing nicer: the listener must know what "crossfeed" and "loudness compensation" mean before they hear either. Most won't — Roon's own default is MUSE off, and most leave it there.
3. **C** — turns on stages that lost; the surest route to "messed with my music".

**Experience-best:** A. **Differs?** No. Two things a listener will expect that the card doesn't say (my judgement): Enhance is per output — the XM4's winners and the soundbar's are different sets, and the chip must say which — and Enhance in Pure needs one honest line and one tap out of Pure. The listener sees two "untouched" states (Pure, and Enhanced with nothing on) and one "on" state, and will ask why there are two; the Pure card should answer that in a sentence.

### Card 12 — What proceeds now
**A ≡ B ≡ C in the end product** — the same features arrive either way; nothing here touches the sound. A is the only one where the listener (the founder) is listening to Enhanced while the sound decisions are made, which is what the dogfood rule needs. **Experience-best:** A. **Differs?** No.

## Part B — the music lover's questions

**1. Out of the box.** Apple's page says Adaptive EQ "uses inward-facing microphones to tune music to your ears in real time" — automatic, part of what the headphone *is*, with no "before" the listener can miss (apple.com/airpods-pro). Sony's stock sound is Sony's own voicing; the app's EQ and "Find Your Equalizer" are opt-in — you play your own music, pick the sound you prefer from a few choices, and it saves your picks (the feature is listed in Sony's help guide; the flow is described in Tom's Guide's XM5 set-up piece). Spotify's leveling shows "Normal" as the default level (support.spotify.com) — leveling being the one change listeners accept unasked, because it never changes how a song *sounds*, only how loud. So the pattern listeners already know is: the *maker's* voicing is automatic and invisible; a *third party's* change is offered and chosen. We are the third party, and the listener's reference is the headphone they bought and like. A published correction takes bass out of the XM4 — on first play, many hear "thinner", not "truer". Judged by first impression alone, auto-apply is a coin flip; judged by trust it is a certain loss, because the one thing it teaches is "this app changes my sound on its own". Offer-and-remember as written wins on trust and loses the first impression (a yes/no to something unheard). The third way keeps both: the offer carries a hold-to-hear — the Compare mechanic inverted, "hold to hear it corrected, at the same loudness" — and one tap keeps it for these headphones; Enhance is that same one tap for everything that won; and, borrowing Sony, a one-minute "Tune for my headphones" that plays the listener's own song with and without, blind, and turns the stage on only if they picked it — card 10's ladder in miniature, run by the listener rather than for them (my judgement). The first sound is always the file; the better sound is one hold away. Leveling is the only stage a listener might expect on by default, and even there the faithful rule says off — Enhance is where it turns on.

**2. Push-backs.** Card 1: "Leveling does nothing in the mode I use every day?" Card 3: "It got quieter when I turned it on" (the cut-the-mids notch — the caption should say "nudge the volume up a notch") and "it works on my headphones but not my soundbar?" Card 5: "Where did the bass go on this album?" (the dropped LFE) and "why do my surround albums sound in my head?" (no crossfeed until the Engine sprint). Card 7: the Apple-trained listener's "Why didn't it just turn on?" — answered by the preview. Card 4: "I drew +12 and it says 'held'" — the word should say it *protected* the sound, not that it refused. Card 6: "Compare doesn't take the correction off, so how do I hear what the correction did?" — the per-layer bypass exists, but they'll look for a hold-to-hear on the correction's own row. Card 8: "Crossfeed or Spatial — which?" Card 2: "One knob that moves room *and* detail together?" Card 11: "What did Enhance actually do?" — the chip must answer. Card 10: no push-back from the founder-listener; any other listener would note the winners were decided on someone else's gear. Cards 9 and 12: nothing audible to push on.

**3. Pressing Enhance.** It should feel like one thing getting better *now*, at the same loudness, with nothing else moving: no fade-in over seconds (a fade reads as the app doing something behind you), no level jump (louder reads as "better" for ten seconds and "loud" after that), nothing you set by hand touched. The chip should say what it did in the listener's words, not the engine's — "Enhance: even levels · full at low volume · headphones in a room" — and holding the chip should play the file without it, at matched loudness, so the claim can be checked in one second. Where Enhance changes the level by design (leveling turning a loud master down), the chip should say so ("−6 dB to match your other albums") so quieter isn't read as worse. Off returns the file as recorded and the chip goes away. In Pure it reads "Not in bit-perfect mode — leave Pure?" with one tap. It never turns on a stage that lost, and it never shows "ENHANCED" alone.

**4. The one decision each way.** "Nicer": card 11 with card 10 under it — Enhance is the only path on which a non-expert ever hears the processing; without it the app is faithful and nothing more. The stage most likely to earn the word is the loudness button at night (card 3), the one benefit felt without an A/B. "Messed with my music": card 1 taken wrong — a level that moves during a song on ordinary stereo music is the one failure a non-expert hears as the app being broken, and it is armed by the very knob they'd turn to try Clarity (the sound engineer's verdict, which I share). Card 7 taken as auto-apply is the runner-up: it loses trust on the first launch rather than the sound on the hundredth.

**5. Consistency across outputs.** Where the plan gives the three outputs different experiences: (a) the loudness button follows the volume on the XM4 (if its buttons reach the Mac's slider — unverified; if not, only the Mac's keys count and the listener must learn that) and is a manual amount on the soundbar — the soundbar half is unavoidable, the Mac cannot read its volume; (b) headphones on the USB DAC read as "USB", so they get no crossfeed by class and no correction offer — avoidable: one per-output question, "What's plugged into this output?", remembered, and everything headphone-shaped follows (my judgement); (c) the ceiling is −1 dB on Bluetooth and on any wired output not at 48 kHz, −0.1 dB on the soundbar — under 1 dB, below notice, and right to keep; (d) in Pure the soundbar ignores the app's volume slider, and leveling-in-Pure (card 1's C) cannot reach it — unavoidable, needs the plain "Set on device"; (e) the Bluetooth-mic case plays the EQ flat on the XM4 only — avoidable, and card 9 gives it an owner; (f) Enhance's winners differ per output by construction — expected, provided the chip says which. The avoidable ones are (b) and (e); the rest need honest words, not engineering.

## Part C — three sentences

1. Card 1: ranked by experience, leveling in the bit-perfect mode is part of the answer, not a follow-up — the listener's daily mode would otherwise be the only one without even levels, and that is exactly where they'd expect them.
2. Cards 7 and 11: the first impression is won neither by auto-apply nor by a bare yes/no offer but by a hold-to-hear preview on the offer and on the Enhance chip — faithful first sound, better sound one hold away, and the claim checkable in a second.
3. Card 4: the peak-safe turn-down belongs with card 1's true-peak number, not two sprints later — EQ on a loud master at the Bluetooth ceiling is squashed with one boost, and a listener with a bass lift on the XM4 hears it on familiar music now.
