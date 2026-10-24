# Roadmap brainstorm — what each answer does to the plan

*Business-analyst view, 2026-10-23. Input: technical-synthesis.md and the four reports beside it; the plan as written (roadmap "post-R1 plan", sprint-plan §3–§4 and §7, the backlog stories the reports cite, requirements, the architecture registry and §11, known issues). Read-only. Every impact claim below traces to one of those; anything I sized is marked "(estimate)". Nothing here is a decision; where an option would change something the founder already decided (FD-1…10, Sprint EQ decisions 25/29/31, the 2026-10-14 crossfeed decision), it is flagged "amends FD-x — needs the founder's word".*

**The rules the plan runs under:** each feature carries only the structural slice it needs; at most 2 weeks per slice; finish-or-revert; no standalone refactor waves (FD-1) — the Engine sprint is the one exception; one PR per sprint; the founder merges by hand.

**Plain words used throughout (defined once):**
- *the kernel* — the processing block inside the Enhanced path's effects unit, where the EQ, crossfeed and the limiter run.
- *the Realizer* — the off-thread planner that turns settings into filter numbers for the kernel.
- *the two units* — the effects unit (N channels in, N out) and the spatial unit (N in, M out) that make up the Enhanced graph; the limiter is the last stage of the effects unit today.
- *the old leveller* — the session-long automatic gain control that still sits in the kernel and runs only when Intensity is above 0.
- *the per-track gain owner* — the existing per-track loudness-neutral gain the EQ already uses; it follows the audible track and does nothing in Pure.
- *the golden master* — the bit-exact checksum the C++ null test compares against; any change to the kernel's parameter block re-baselines it (a deliberate, recorded step).
- *true-peak cap* — limit a gain so the loudest sample after it stays under the ceiling, so the limiter never has to act.
- *the fold* — the 5.1 / 7.1 → stereo mix-down (FD-9).
- *BRIR* — the binaural room render: a measured head-and-room response applied on headphones to put the sound outside the head (S18).
- *the ledger* — one place that adds up every gain request (EQ, correction, compensation, import preamp) and applies one pre-gain once.
- *W2* — one owner of playback: a transport reducer, a command layer and an engine event channel. Not scheduled today.
- *the per-output slot* — the EQ memory kept per output device (the "Used on …" pin).
- *Compare* — the hold-to-Compare button on the EQ.
- *attenuate-mid* — cut the mids as the level drops instead of boosting bass and treble; needs no headroom and cannot clip.

---

## A. Impact per decision

Columns: **Absorbed by** names the sprint that takes the work and whether it *grows / fits / shrinks* against its 2-week cap. **What moves** names items that change sprint. **Cost** is a rough size plus the risk it carries. Document changes are listed per option under each table, one line per document.

### Decision 1 — Leveling (R1.1-B)

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **1a (recommended)** one static per-track / album gain through the per-track gain owner, on every processed path; the old leveller retired in the same change (its on/off driven by the Leveling setting, default off); Off / Auto / Album / Track; a fixed gain for unknown loudness; a displayed target; tags read when present; Pure = "Leveling off (bit-perfect)" in the badge | R1.1-B — **grows**: Auto, the fallback, tags, the target readout and the retirement sit on top of a 5 sp story (a few days, estimate); fits the cap only if nothing else in R1.1-B grows (5a also grows it — see §C) | C-38 leaves the S12 / W5 slice row where it is scheduled a second time [C-38]; "loudness-comp" leaves S17's mapping [S17]; the "sample-accurate at the seam" acceptance becomes "at the seam as the engine counts it, within a buffer until ENG" [KI-GAP-02 stays ENG's]; "leveling at the seam" joins ENG's carry list as a contract test | A few days beyond the story (estimate). Risks: touches the kernel's path selection (audio-thread code); Off = identity so the golden master should hold, but a parameter-block change re-baselines it (estimate); seam timing inherits KI-GAP-02 until ENG |
| **1b** keep the old leveller as a visible fourth mode, "Adaptive" | R1.1-B — **grows more**: two levellers to document, test and keep exclusive | Nothing leaves S17: Intensity's blend still has a level stage to "absorb" its +3 dB hump, so C-40's fix is still owed there | A few days more than 1a (estimate). Risks: C-38's drift and session carry-over stay in the product as a mode; decision 2's "two hands on one knob" stays open |
| **1c** (other-players report) on Pure, leveling as a cut-only offset on the device-volume loan, the loan taught that its own moves are not the listener's | R1.1-B or a later Pure item — **grows**: touches the Pure volume loan | Nothing between sprints; adds a Pure line to US-R1F-10 and a "Leveled on the device, −4.2 dB" readout | About a week (estimate: the loan's journal, its re-anchor rule, device-step quantisation). Risks: FD-5 says nothing that changes Pure's output path runs before the USB-DAC check; a leveling step misread as the listener's change compounds across tracks |
| **1d** (architect alt b) defer leveling to after ENG (S14-lite or S12); R1.1-B ships only the setting shell | R1.1-B — **shrinks** by ~5 sp; S12 (already overloaded) or S14-lite grows | US-R1F-10 → S12 or S14-lite; the R1.1 release row loses "the leveling setting"; FD-2's "leveling becomes its own setting" slips past the daily-driver week | A day of doc moves. Risks: the founder lives a week on R1.1 with no leveling; "sample-accurate" becomes true on ENG's path, but S12's overload (decision 6) gets worse |

Documents that change — 1a:
- roadmap, R1.1-B row 7: Off / Auto / Album / Track; the old leveller retired; Pure wording.
- roadmap S17 row and Phase 2 table; sprint-plan S17 row: strike "loudness-comp" from the mapping.
- sprint-plan, R1.1-B row: the leveling scope line.
- backlog US-R1F-10: the stage it lives in; the retirement; Auto; the fixed fallback; the "Open: tags" line resolved; a Pure line; the seam tolerance until ENG.
- backlog US-RMG-02 and SPIKE-REIMAGINE-MAP: no level stage in the map.
- requirements LD-17 and FR-TONAL-05 annotations: leveling = a static gain; the old leveller is retired, not hidden.
- architecture §2.5 "What persists" and §9 dynamics bullet: the normaliser line.
- council slice catalogue, W5 row: C-38 annotated as moved (the catalogue is a review record, not a to-do list — annotate, don't edit).
- known issues: none new.

1b: as 1a, plus US-R1F-10 gains a fourth option and its copy; LD-17 keeps "DRC in effect" as an opt-in mode; the S17 row must say whether Intensity still scales it. 1c: US-R1F-10 (Pure behaviour); architecture "What persists" (the loan's rule); FD-5's hardware check list ("leveling on the device"); a known-issue entry if the loan's re-anchor rule changes. 1d: roadmap R1.1-B row 7 and the R1.1 release row; sprint-plan R1.1-B and S12 / S14 rows; US-R1F-10 scheduled line; FD-2 annotation.

**Cost of not deciding:** R1.1-B builds a leveling gain with no stage named, beside the old leveller (two levellers in the code), on an acceptance the current engine cannot meet; S17 later re-enables the old leveller on top of it; the fix then costs a second pass through the kernel and the S17 row.

### Decision 2 — Intensity (S17) and Clarity (S16)

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **2a (recommended)** Intensity scales only the automatic stages — Clarity depth and the spatial room amount — never crossfeed, leveling, compensation, the EQ or correction; 0 = "nothing automatic"; Clarity gets its own switch (the pattern crossfeed took) so S16 is audible when it ships; S16 and S17 stay separate | S17 **shrinks** (two stages fewer to map); S16 **grows a little** (a switch, a chip, an inspector row — a day or two, estimate) | Crossfeed and loudness-comp leave S17's mapping [S17, SPIKE-REIMAGINE-MAP]; the Clarity switch + chip move into S16; the correlation-compensated blend (C-40) stays in S17 per the roadmap — or moves into S16 if S16's A/B must be level-fair (the chain report's point; a choice inside 2a) | Docs: a day now. The code cost lands in S16 / S17 and is mostly work they owed. Risk: the "one knob" thesis narrows to two stages — a product-story change, not a code one |
| **2a-merge** (chain report) merge S16 and S17 so Clarity ships with Intensity visible and the blend fixed | A merged sprint of 9 + 6 sp — **grows past the cap** unless cut to Clarity + the blend only | S17's Intensity return and C-40 into S16; S17 becomes mapping polish or disappears; the R3 release row ("after S17") changes | A day of docs. Risk: the merged sprint is the "wave with a feature on top" shape FD-1 forbids |
| **2b** keep Intensity hidden for good; every stage gets its own control | S17 disappears (its 6 sp become per-stage controls in S16 and S18, which each **grow** by a control) | US-RMG-02, SPIKE-REIMAGINE-MAP and the C-40 blend fix → cut or parked; the kept Reimagine inspector section removed; the R3 theme ("steerable Reimagine") changes; LD-16 and ADR-008 parked | A day of docs; removing a shipped primitive is a few days and a golden re-baseline if the blend leaves the kernel (estimate). Risk: the thesis loses its headline control; the proven S6 blend primitive is thrown away |

Documents that change — 2a:
- roadmap S17 row and Phase 2 table: "across Clarity depth + spatial room".
- sprint-plan S17 row: the same; S16 row: Clarity's own switch and chip.
- backlog US-RMG-02, SPIKE-REIMAGINE-MAP: the mapping's targets; US-ADAPT-05: default 100 % → matches FD-2's 0, and "never scales a hand-set switch"; US-PERC-03: its own switch.
- requirements FR-REIMAGINE-02: "0 = nothing automatic; hand-set stages still play"; FR-ADAPT-08: same.
- architecture §0 LD-16 annotation and §5: which stages the knob scales.
- known issues: none (KI-SND-05's closure stands).

2a-merge: roadmap Phase 2 table and R3 release row; sprint-plan S16 / S17 rows, Phase 2 total, §7 R3 milestone; backlog US-RMG-02 forward. 2b: roadmap strategy paragraph, Phase 2 table, R3 row; sprint-plan S17 row, §4 preamble, §7; backlog EP-REIMAGINE, US-RMG-02, SPIKE-REIMAGINE-MAP, US-ADAPT-05; requirements FR-REIMAGINE-01…04 annotated parked; architecture §0 LD-16, ADR-008, §5; known issues KI-SND-01's "returns in S17" line.

**Cost of not deciding:** S16 builds Clarity into a path no default listener can hear and tunes it against a +3 dB level bias; S14's Loudness switch and S17's knob both drive compensation; FR-REIMAGINE-02's "all stages bypassed" silently overrides a switch the listener set.

### Decision 3 — Loudness compensation (S14-lite)

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **3a (recommended)** level = Master Gain + the Enhanced device's own volume through the volume listener that already exists for Pure, relative to a one-time "this is my normal loud setting" reference (no SPL model); attenuate-mid form; decoupled from ENG and W2; one cap; one "Level" card with plain names and a net-gain readout; "not in Pure" | S14-lite — **about fits**: "waits for W2" disappears (the listener is a lift of a Pure-only gate, not an engine event); the "taste-only neutrality" slice shrinks to "sum a second layer before the design" if LD-17's reading stands; the reference step and the card add a few days (estimate) | "Depends on: ENG" leaves S14-lite's row; "S14's adaptive half" leaves W2's funder list [W2]; US-ADAPT-03 (volume tracking) folds into S14-lite instead of waiting; SPIKE-LOUDNESS-COMP-TUNING's "10+ listeners" test → the founder's blind ladder (decision 10) | The feature (8 sp) plus a few days (estimate). Risks: lifting the device-volume listener out of its Pure-only gate touches the code R1.1-A wrote to keep a device volume from being painted onto Enhanced (KI-SET-03's closure) — a regression test is owed; outputs with no readable volume ("Set on device": HDMI, some Bluetooth) get Master-Gain-only compensation and must say so |
| **3b** a manual "Loudness amount" slider, or "follows Master Gain" with the caption saying so | S14-lite — **shrinks** (no listener lift, no reference) | US-ADAPT-03 stays parked for W2 / S14-adaptive; the "loudness button" claim and the "boost when I turn the volume down" story text are withdrawn for -lite | A day of docs; the feature shrinks. Risk: it is the "Bass & Treble" preset under another name (listener report); the R2 release claim "loudness compensation" is thin; the adaptive half still needs a later slot |
| **3c** (architect alt b) run S14-lite before ENG — nothing it touches is in ENG's scope | The order becomes R1.1-B → S14-lite → ENG → S12 …; sizes unchanged | S14-lite ahead of ENG; the "live a week on R1.1" guardrail is spent during S14-lite instead of ENG; S12's "Depends on: S14-lite" still holds | A day of docs. Risk: S14's seam-related tests are re-proven after ENG; two sprints of kernel / Realizer change before the engine swap widen ENG's comparison surface slightly (estimate). Amends the post-R1 sequence FD-1/FD-4 set — needs the founder's word |
| **3a-boost** (chain report) the boost form per C-09 — "exempt from neutrality, capped by true-peak headroom" — instead of attenuate-mid | S14-lite — **grows**: the analyser needs a true-peak field and decision 4's ledger must own the pre-gain | Couples 3 to 4 (the ledger becomes mandatory in S14-lite) | A few days more. Risk: on a loud master at the −0.1 dBTP wired ceiling the limiter does sustained gain reduction — the thing LD-17 forbids |

Documents that change — 3a:
- roadmap R2 row 1: the slice text, the dependency, the Pure line, the plain names; "How structural work is paid for": W2's funders.
- sprint-plan S14 row: "Depends on" (drop ENG), the form, one cap, the card.
- backlog US-TON-03: which volume counts, attenuate-mid, one cap, a Pure line; US-ADAPT-03: forward → S14-lite, "the volume listener, not engine events"; SPIKE-LOUDNESS-COMP-TUNING: the founder's blind test instead of MUSHRA.
- requirements FR-TONAL-03: the form; "per-device SPL calibration" → a one-time reference; the cap set chosen; LD-17: "loudness-matched makeup" becomes moot in the cut form (or amended per C-09 if the boost form is kept).
- architecture §0 LD-17, §9 compensation bullet, §2.5 level note (the device volume is read on Enhanced too).
- council needs table, S14 row: "W2 events" struck.
- known issues: none — an entry for "compensation follows Master Gain only" is avoided.

3b: sprint-plan S14 row (the claim); US-TON-03 (story text; "updates on every volume change" dropped for -lite); US-ADAPT-03 stays forward; FR-TONAL-03 annotated "as built, -lite"; roadmap R2 row 1. 3c: roadmap post-R1 sequence line, critical path, R2 order note; sprint-plan critical path, §Status "next", S14 row; backlog forward lines. 3a-boost: LD-17 and FR-TONAL-03 amended to "exempt from neutrality"; the adaptive-tone rule "loudness-neutral always" amended; US-TON-03 keeps the boost AC; the analyser profile gains a true-peak field.

**Cost of not deciding:** S14-lite waits on an ENG dependency it does not use; it compensates against a slider most listeners never touch (no compensation at any level on the founder's own setup); two caps and two definitions stay in the docs; its layer is written into a contract S12 then replaces.

### Decision 4 — Gain and headroom owner

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **4a (recommended)** one ledger in the Realizer — a per-band sum over the EQ layers ≤ +12 dB with proportional scaling, one pre-gain applied once before the EQ, AutoEq's preamp dropped on import and replaced by the ledger, the limiter's gain reduction metered and shown — as S14-lite's structural slice | S14-lite — **grows**: the ledger replaces the "taste-only neutrality" slice; about a week (estimate); S12, S13 and S16 then **shrink** (their gains become entries, not new rules) | The cumulative +12 dB clamp moves from S15–S16's design (architecture §11) into S14-lite; AutoEq's preamp rule moves from S12's import into the ledger; the GR meter from §9's re-sum design into S14-lite; the EQ's neutral gain becomes a ledger entry with one glide law (other-players report) | A week (estimate). Risks: the Realizer's design step (off the audio thread) and a pre-gain field in the parameter block → golden-master re-baseline likely (estimate); a "held" indication on the graph is a small UI item |
| **4b** separate budgets per layer, the sum displayed | S14-lite, S12, S13 each carry their own cap — each **grows a little**; S16 still owes the sum | Nothing between sprints; a sum display in S14-lite or S12 | A few days spread. Risk: +12 taste + +6 compensation + +5 correction in one band before the limiter (the chain report's +23 dB case) — the clamp the founder relies on is still not a sum until S16 |
| **4c** (architect alt a) a smaller compensation budget (+6 dB) until S16's Arbiter | S14-lite — **shrinks** (no ledger) | The ledger stays with the Arbiter in S16 | A day. Risk: S13's correction (AutoEq filters to ±20 dB) still has no sum rule; the "picture lies" clamp on import stays |

Documents that change — 4a:
- roadmap R2 row 1: "the Realizer sums and clamps the layers", not "respect the clamp".
- sprint-plan S14 row (the slice), S12 row (preamp dropped on import), S16 row (the Arbiter emits into the ledger).
- backlog US-TON-03 (the cap is the ledger's), US-TON-02 and S12's AutoEq import (the preamp line), US-PERC-01 (the clamp is enforced by the ledger), US-MCP-05 (server-side clamps = the ledger, one place), SPIKE-HEARING-SAFETY-VALIDATION (re-scoped to the ledger).
- requirements FR-TONAL-02: correction gains counted by the ledger, never clipped silently.
- architecture §11 header: the sum clamp ships in S14-lite, the per-band table stays design; §9: the GR meter shipped; §2.5: what "EQ Off" and the bit-perfect badge mean per layer.
- known issues: none new.

4b: roadmap R2 row 1 clarified ("its own headroom" = a second budget); sprint-plan S14 / S12 / S13 rows each name a cap; US-TON-03, US-TON-02; architecture §11 unchanged. 4c: sprint-plan S14 row, US-TON-03, FR-TONAL-03 (+6 / +4 kept).

**Cost of not deciding:** S14-lite ships a second boost against a per-point clamp that sums nothing; S12 imports AutoEq files whose preamp and filter gains are silently clamped; after S13 the auto-loaded correction, not the listener, spends the budget; the only summing owner is two releases away.

### Decision 5 — The fold-down (R1.1-B)

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **5a (recommended)** fold inside the kernel before the one limiter (so crossfeed, the limiter and the EQ's gains see the stereo signal that reaches the device); one decoded channel layout per item, published to both units through one call; "C-45's rest" and C-47's minimal form move from S12 into R1.1-B | R1.1-B — **grows**: US-R1F-08 (5 sp) takes the layout owner and a stage position; the effects unit becomes N-in / M-out (its bus formats change) and the spatial unit becomes an identity route — about a week on top of the fold (estimate); R1.1-B is over its cap unless a non-sound item leaves (§C) | C-45's rest + C-47 (minimal) S12 → R1.1-B [S12 shrinks]; the second ceiling disappears; the layout's source for ENG is named now (the decode source carries it from day one, as US-PE-02 already promises); S18's "replaces it in the same slot" now means the kernel's N→M slot | A week beyond the story (estimate). Risks: changes the two-unit graph's bus formats (what R1's multichannel work pinned); golden re-baseline if the parameter block grows (estimate); audio-thread code. Amends FD-9's "with a ceiling after it" — needs the founder's word |
| **5b** keep the fold in the spatial unit; a per-track static fold trim from a folded true peak the analyser computes; the second ceiling kept as a rarely-acting net with its gain reduction metered; still one layout owner from R1.1-B, C-45 / C-47 moved | R1.1-B — **grows** in different places: the spatial unit needs a control plane (roles, trim, ceiling), a second limiter and a publish path; the analyser gains a folded-true-peak field — about a week (estimate) | As 5a for C-45 / C-47; adds "a true-peak field in the analyser" to R1.1-B (also what leveling's cap wants) | A week (estimate). Risks: two limiters in series (6 ms look-ahead), a second transport-aware ceiling rule, crossfeed still runs before the fold (a 5.1 album on headphones has no crossfeed; the chip must say so); FD-9's wording kept |
| **5c** the plan as written, documented: a bare ceiling after the fold, two limiters, no layout move; S12 keeps C-45's rest and C-47 | R1.1-B **fits** as sized (5 sp); S12 stays overloaded | Nothing | Nothing now. Risks: compression by default on dense 5.1 masters (against LD-17); the layout rebuilt in four sprints (R1.1-B, ENG, S12, S18); S18 inherits the slot problem |
| **5d** (mpv-style) worst-case normalisation: the fold always trims −7.7 dB; no analysis, no second ceiling | R1.1-B — **shrinks** | Nothing | A day. Risk: every surround album plays audibly quieter; leveling must know about the trim |

Documents that change — 5a:
- roadmap R1.1-B row 1: placement, one limiter after the fold, crossfeed sees the fold, the chip and the Pure wording; R2 row 2: S12 loses the layout and the stage concept; S18 row: the slot.
- sprint-plan R1.1-B row ("with a ceiling after it"), S12 row, S18 row; §9 FD-9's wording annotated.
- backlog US-R1F-08: acceptance (one limiter after the fold; what crossfeed does on a folded file; the layout owner; the chip; the Pure reason); US-PE-02: the layout carried (confirm); US-SPAT-01: the slot.
- architecture §2.5 two-unit graph (the effects unit N→M, the spatial unit identity) and §7 interim text.
- known issues KI-MC-01 and KI-MC-02: the FD-9 annotation "with a ceiling after it" → "one limiter after the fold".
- council report §5 FD-9 line: annotated.

5b: as 5a except the architecture graph note (the spatial unit gains a control plane and a limiter), US-R1F-08 (the trim rule; GR metered), a known-issue note on crossfeed-before-fold. 5c: a known-issue entry (double-limiting and latency on surround; crossfeed off on folded files); a US-R1F-08 acceptance note. 5d: US-R1F-08 (a fixed trim, "quieter by design"); a known-issue note.

**Cost of not deciding:** R1.1-B opens a second control path into the spatial unit and a second limiter; S12 then moves the layout into the effects unit's Realizer, which cannot reach the spatial unit; ENG changes the layout's source; S18 needs the layout in the unit that never receives it — one part rebuilt four times, with compression by default on surround files in between.

### Decision 6 — EQ layers, Compare, per-device memory

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **6a (recommended)** one EQ program = ordered layers [correction \| taste (graphic + parametric) \| compensation] → one design step → one set of filter numbers, one composed read-back so the graph draws what plays, a bypass per layer; Compare keeps one meaning ("without *my* EQ"; correction and compensation stay) and a separate latching "Bypass all processing" delivers US-PROF-02; the per-output slot is the only per-device memory, extended with the parametric bands and the correction choice (KI-EQ-01 fixed in the same change); S16's Arbiter emits into that program; S12 carries only the EQ part of W5; S13's row rewritten honestly | S12 — **shrinks** (loses the layout and the stage concept) **and grows** (slot extension, KI-EQ-01, "Bypass all", composed read-back): about the same size, at the cap (estimate); the layer principle is applied already in S14-lite so its compensation layer is not rebuilt; S13 clarifies; S16 **shrinks** (no second filter engine) | C-45's rest + C-47 out of S12 (decision 5); the A/B row out of S12 ("already shipped") and US-PROF-02's "Bypass all" into S12 (or S16, where Clarity's A/B first needs it); KI-EQ-01 from the pool into S12; the L-M fitter (US-PERC-02) narrowed to the FIR / linear-phase opt-in or dropped; the profile model (US-DEVICE-04 / -05) either S13's explicit third part or cut to "correction + taste" | The design a few days; the slot extension, KI-EQ-01 and Bypass-all a few days more (estimate) — most of it work S12 owed. Risk: the parameter block changes shape once (a deliberate golden re-baseline, the council's own note) instead of twice (S12 and S16) |
| **6b** accept three filter engines; name which owns phase; S12 as written | S12 as is (overloaded); S16 builds its own fitter; S13 adds a third per-device memory | Nothing | Nothing now. Risks: three glide rules; the golden master changes shape at S12 and again at S16; Compare means three things; per-device memory has three owners and no rule |
| **6c** (architect alt) run S12 before S14-lite so the compensation layer lands on the final contract | Order becomes ENG → S12 → S14-lite → S13; S12 unchanged; S14-lite **shrinks** | The "cheapest proof of adaptive" is no longer first in R2; S12's "Depends on: S14-lite" reverses | A day of docs. Risk: the adaptive thesis's first proof slips a sprint. Amends FD-1's R2 order — needs the founder's word |
| **6d** (architect F11 alt) narrow S13 to "import an AutoEq file and attach it to the current output" — manual, no identification, no profile model | S13 — **shrinks sharply** (a few days); US-DEVICE-04 / -05 leave R2 | Identification, the 20-profile library and profile JSON → later or the pool; the R2 release row's "device correction" becomes "manual correction import" | A day of docs. Risk: "headphone correction" in the Phase 1 exit criterion becomes manual-only |

Documents that change — 6a:
- roadmap R2 row 2: S12's slice = the EQ part of W5 (program, shelves, glide) — no layout, no stage concept; R2 row 3: S13 = identification + a correction layer + the profile decision; "Where everything else went" pool line: KI-EQ-01 leaves the pool.
- sprint-plan S12 row (scope, slice, the A/B sentence resolved), S13 row (strike "delivered early"; the three parts), S16 row (the Arbiter emits into the program; the fitter narrowed).
- backlog US-TON-02 (a layer keyed by model, separate from the taste slot), US-DEVICE-04 / -05 (profile = the output's slot, or cut), US-PROF-02 (scheduled: "Bypass all"), US-PERC-02 (fitter narrowed), US-R1F-06 / KI-EQ-01 forward.
- requirements FR-TONAL-02 (correction as a layer under taste, toggled per device); FR-TONAL-01 note (the program).
- architecture §2.5 EQ paragraph (program = layers; Compare's one meaning; "EQ Off" per layer), §4 (name the perceptual Realizer something other than the shipped control-plane Realizer), §8.
- known issues KI-EQ-01: scheduled → S12.
- EQ design README (the Compare rule) — a design doc.

6b: architecture §4 / §8 (which engine owns phase; two cascades in series); sprint-plan S16 row; a known-issue note on summed group delay and ripple. 6c: roadmap R2 table order and both "R2 order" lines; sprint-plan R2 order line, §Status, critical path; backlog forward lines; FD-1 annotation. 6d: roadmap R2 row 3 and the R2 release row; sprint-plan S13 row; backlog US-TON-02 ("identified" dropped for R2), US-DEVICE-04 / -05 forward; FR-TONAL-02 annotated.

**Cost of not deciding:** S12 starts as a refactor wave with a feature on top (parametric + import + shelves + glide + program + layout + stage concept) under a cap it cannot meet; S14-lite's layer is built in a contract S12 replaces; S13 keys correction to the pin and inherits KI-EQ-01; S16 adds a third filter engine.

### Decision 7 — Correction and spatial: opt-in or auto-on

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **7a (recommended)** correction and spatial are opt-in per device and off on a fresh install; "auto-load" means *offer and remember* (US-DEVICE-04's own wording), never *apply*; the device class only chooses the default for a never-seen output; a hero chip for every stage that plays | S13 (correction) and S18 (spatial) each **grow a little** (an offer toast and a chip — a day or two each, estimate); S12's slot extension (decision 6) carries the correction choice | Nothing between sprints; US-SPAT-01's "default-on for headphones" is rewritten; the crossfeed text-vs-code gap (US-R1F-12) is settled by the same rule: per-output memory + class default + manual override | A day of docs now; a day or two of UI per sprint later. Risk: none to the sound; "right out of the box" softens to "offered out of the box" |
| **7b** auto-apply with a 6-second Undo toast | S13 / S18 — similar size | Nothing | Same size. Risks: a new install plays corrected (then binauralised) before the listener touches anything; a second pair of the same model double-applies through the model fallback if written into the taste slot; the chip must appear or the honesty promise fails. Amends FD-2's faithful default — needs the founder's word |
| **7c** (chain report alt) correction on by default only when the listener opted into "correct my headphones" globally | S13 — a global switch plus per-device memory | Nothing | Same size. Risk: a global opt-in applied to never-seen devices is still class-gated (a DAC feeding headphones is "USB") |

Documents that change — 7a:
- sprint-plan S13 row ("auto-load" → "offer and remember") and S18 row (opt-in per device).
- backlog US-TON-02 (story text "automatically apply … right out of the box" → "offered"), US-DEVICE-04 (confirmed as the rule), US-SPAT-01 ("default-on" → opt-in per device), US-R1F-12 (crossfeed text aligned to the shipped gate and the rule).
- requirements FR-TONAL-02 (add "off by default; offered"), FR-SPAT-01 (default).
- user journeys 2.4 step 2 ("loads generic profile" → "offers").
- architecture §2.5 "What persists" (the correction and spatial choices live in the per-output slot; a hero chip per stage).
- known issues: none.

7b: as 7a plus FD-2's annotation carves out an exception; architecture "What persists" (a new install is corrected on identified headphones). 7c: as 7a plus a Settings row.

**Cost of not deciding:** S13 ships "automatically apply … right out of the box" against FD-2; the docs keep three readings of whether correction has a switch; the hero chip names only Intensity and crossfeed, so nothing on screen says a correction plays.

### Decision 8 — Headphones: one control, one BRIR home

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **8a (recommended)** one "Headphones: Off / Crossfeed / Spatial" control, exclusive by construction, remembered per output; BRIR renders at the one N→M slot for every source width (stereo = the externalisation case); Intensity drives its room amount as a parameter, not a wet/dry blend; the kernel's BRIR stub retired; the S4 design marked superseded; the fold gets a chip ("5.1 → stereo") and the Pure reason reads "…so Enhanced plays it, folded to stereo" | S18 — **about fits** (the stub retirement is a removal; the control replaces the crossfeed section); R1.1-B takes the chip and the Pure wording (a day, estimate); S17 **shrinks** (BRIR leaves its blend) | BRIR out of the Intensity blend; the exclusivity rule from "enforce in the kernel at S18" to the control (one owner); the S4 design doc superseded (it chose Apple's environment node, which the backlog bans) | A day of docs now; the S18 work is S18's own. Risk: "0 = nothing automatic" must read "room 0, Spatial still on if chosen" — the copy must say so |
| **8b** two switches (Crossfeed, Spatial) that grey each other out | S18 — same size; the arbitration in the Realizer | Nothing | Same. Risk: two switches for one job; the "XF" chip cannot tell them apart without a second chip |
| **8c** (architect / chain alt) BRIR in the effects unit for stereo sources only; the fold stays permanently for N > 2 | S18 — **shrinks** (no N→2 render); R1.1-B's fold becomes permanent, so its quality bar rises | US-SPAT-01's surround case → cut or parked | A day of docs. Risk: surround albums never get the binaural render the thesis promised; the fold's rule-bend becomes permanent. Amends FD-9's "replaced in the same slot" — needs the founder's word |

Documents that change — 8a:
- roadmap S18 row and Phase 2 table; R1.1-B row 1 (chip, Pure reason).
- sprint-plan S18 row (the S4 design link marked superseded), S17 row (room amount as a parameter).
- backlog US-SPAT-01 (the slot; the control; default per decision 7), US-SPAT-03 (room amount via Intensity), US-R1F-08 (chip, Pure reason), US-R1F-12 (crossfeed remembered per output).
- requirements FR-SPAT-03 ("largely subsumed by BRIR" → "exclusive with Spatial; one control"), FR-SPAT-01.
- architecture §0 LD-14 annotation, §5 (the blend's stages), §7 (BRIR's home; the S4 note), §2.5 kernel paths (the coloration chain loses BRIR).
- the S4 binaural design doc: header "superseded".
- known issues: a note that crossfeed is stereo-only until S18 and the chip reads the kernel's bypass (chain report F13).

8b: as 8a minus the control redesign; US-SPAT-01 gains the arbitration rule (Spatial on ⇒ crossfeed forced off). 8c: roadmap R1.1-B row 1 (strike "S18 replaces it"), S18 row; sprint-plan same plus §9 FD-9 annotation; US-R1F-08, US-SPAT-01; architecture §7; KI-MC-01 forward.

**Cost of not deciding:** S18 arrives with two BRIR homes — one inside the blend, one at the device boundary — only one of which can fold and only one of which can be blended; crossfeed and BRIR run together (the kernel's own comment calls that a bug); a Pure listener's surround album plays through a matrix with only "Pure off: channels" to explain it.

### Decision 9 — W2's slot and ENG's neighbours

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **9a (recommended)** ENG delivers the engine half of W2 (it already says so); S15, the first consumer, carries the transport reducer + command layer; "S14's adaptive half" dropped as a funder; S14-lite loses "Depends on: ENG"; ENG's acceptance carries the R1.1 contract tests (one-converter seam, seek-to-end, roles-from-labels, leveling-at-the-seam) and C-49 / C-48; −1 dBTP everywhere until ENG measures the output-side conversion | ENG — **fits** (acceptance grows, build unchanged); S14-lite — **fits** (one dependency fewer); S15 — **grows**: the reducer + command layer is sized "L" by the council — the one place the cap is at real risk (estimate: the spike plus the reducer's first event family) | W2's transport half into S15's row (a named slot); "S14's adaptive half" off W2's funders; "Depends on: ENG" off S14-lite; C-49 into ENG's carry (it is in the catalogue's R1.1-B row but in neither roadmap table); the −0.1 dBTP wired ceiling (Sprint EQ decision 29) → −1 dBTP until measured; EP-MCP becomes a consumer after S15, not W2's funder | A day of docs now; later, S15 grows by about a week (estimate). Risk: a reducer that owns play / pause this fortnight and seek / advance the next is two live owners mid-sprint unless cut per event family under finish-or-revert. Amends decision 29 and FD-8's "funded by EP-MCP" wording — needs the founder's word |
| **9b** make EP-MCP an R2 sprint of its own that starts with W2 (FD-8 allows "R2 or later") | A fifth R2 sprint — R2 **grows by a sprint**; S15 then fits | W2, the command layer and the MCP spike into R2; "R2 ships after S11-lite" changes; the R2 release row grows ("agent control") | A sprint. Risks: R2 slips a sprint; MCP is off-thesis for the sound features the founder froze on. Within FD-8 but changes R2's content — needs the founder's word |
| **9c** (architect alt b) state that S15–S18 need only "a seam event that carries the track's identity" (ENG delivers it); strike "W2 events" from the needs table; W2's transport half stays bug-triggered | Nothing new; ENG and S15 **fit** | Nothing; the needs table and the S15–S18 rows are corrected | A day. Risk: the pre-mortem's "W2 is never funded, the wrong-song class persists" stays open; EP-MCP keeps waiting on a thing nobody builds |

Documents that change — 9a:
- roadmap "How structural work is paid for" (W2's funders and slot = S15), R2 row 1 (dependency), the Engine sprint section (acceptance carry list, C-49, the ceiling measurement), the Agent control surface paragraph (EP-MCP a consumer).
- sprint-plan ENG row (carries), S14 row (depends), S15 row (slice + "Depends on: ENG events"), S16–S18 rows (the dependency named or struck).
- backlog US-MCP-00 (funded-by / slot), US-PE-01 (the discovery list names the contract tests), US-PE-03 (the switch and the loser are deleted inside the sprint), US-TON-03 (depends).
- requirements NFR-QUAL-04 note (the ceiling until measured).
- architecture §2.5 (decision 29 annotated; C-49 named as latent until ENG).
- known issues: a C-49 entry (the EQ plays flat below 44 kHz — latent, becomes live the day the graph follows the device rate) and a KI-GAP-02 forward note (leveling's tolerance until ENG).
- council needs table, S15–S18 row: "W2 events" → named.

9b: roadmap post-R1 sequence line, R2 table (a fifth row), R2 release row, the Agent control paragraph; sprint-plan R2 order, §4 "Planned, not yet scheduled", §7 R2 milestone; backlog EP-MCP status, US-MCP-00. 9c: the council needs table; sprint-plan S15–S18 dependencies; roadmap W2 paragraph (funders: EP-MCP or a bug); S14 row depends.

**Cost of not deciding:** R3 is scheduled on a slice nobody is scheduled to build; S14-lite waits on ENG for nothing it uses (if ENG overruns, R2's first feature waits on nothing); ENG's acceptance names council rows but not the R1.1 behaviours that must be re-proven; C-49 goes live the day the graph follows the device rate, with no owner.

### Decision 10 — The founder's blind A/B as acceptance; the "Clarity" name

| Option | Absorbed by | What moves | Cost and risk |
|---|---|---|---|
| **10a (recommended)** one acceptance line on every processing sprint — a blind, level-matched A/B on the founder's own headphones and soundbar (the adaptive-tone §6 Stage 1 ladder, about 23 trials); a stage that does not win ships off and hidden; the preset's display name becomes "Detail", stored id unchanged | S14-lite, S16, S18 each gain one acceptance line and an evening of the founder's listening (by-ear is the founder's lane; agents never play audio); the rename is a day anywhere before S15 (the pool or S12) — all **fit** | SPIKE-LOUDNESS-COMP-TUNING's "10+ listeners MUSHRA" → the founder's ladder; US-SPAT-01's ABX "difference" → "preference"; the council's "Clarity only if it wins a blind test" reaches the S16 row | A day of docs; an evening per processing sprint; the rename a day (a display-name change like decision 31). Risk: a stage that measured right may fail the founder's ear and ship hidden — that is the point; its sprint is still spent |
| **10b** ship every processing stage off by default and skip the test | Nothing; cheaper | Nothing | Nothing. Risk: S16 / S18 carry no proof of value; the thesis never meets its one user |
| **10c** (listener alt) the same test as each sprint's demo-day close | As 10a plus the sprint model's done-done template | As 10a | As 10a |
| **rename alt** rename the S16 feature ("Unmask") and keep the preset | S16's docs — many more places than one display name | Nothing | A day. Risk: "Clarity" is the thesis's word in every doc |

Documents that change — 10a:
- sprint-plan S14 / S16 / S18 rows: the last acceptance line; S16's exit = "wins the blind A/B or ships off and hidden".
- backlog US-TON-03, US-PERC-03, US-SPAT-01 (acceptance), SPIKE-LOUDNESS-COMP-TUNING (re-scoped), SPIKE-BRIR (ABX → preference).
- requirements FR-TONAL-03 ("audibly noticeable but not artificial" gains a test), FR-SPAT-01.
- roadmap Validation framework, "By-ear" bullet: the blind ladder is the processing sprints' exit.
- architecture validation gate note; the adaptive-tone README (its ladder becomes the shared protocol).
- the EQ preset's display name (the EQ design README; a neighbour to glass-sweep decision 31).
- known issues: none.

10b: sprint-plan rows and backlog defaults only. Rename alt: roadmap / sprint-plan S16 rows, US-PERC-03, architecture §4 / §5.

**Cost of not deciding:** S16 — the item most likely to fail the founder's own litmus test — ships on measurements alone; "Clarity vs Clarity" cannot be written in a test report; the output toast "AirPods Pro · Clarity" is ambiguous after S16.

---

## B. The order the decisions must be taken in

Hard orderings (each from a report's dependency, not a preference):
1. **5 before 8** — 5 fixes where the one N→M slot lives; 8's "BRIR at the device boundary" then has exactly one home (that slot). 8's R1.1-B halves (the fold chip, the Pure wording) go with 5.
2. **5 before 6** — whether C-45's rest and C-47 leave S12 is 5's answer; 6 sizes S12 after that.
3. **1 before 2** — retiring the old leveller (1a) removes the level stage from Intensity's blend; 2 then has nothing level-like to scale, and S17's "loudness-comp" text is struck as a consequence of 1.
4. **4's principle before 1's cap and 3's cap** — R1.1-B needs only the one-line rule ("leveling is a true-peak-capped static gain, counted by the ledger when it exists"); 3 and the ledger itself need the full answer before S14-lite.
5. **3 and 9 together** — 3a's "decoupled from ENG and W2" *is* 9a's "S14-lite loses Depends on: ENG" and "S14's adaptive half leaves W2's funders"; one answer, two rows.
6. **1 before 9's ENG half** — ENG's acceptance can only carry "leveling at the seam" once 1 has named where leveling lives.
7. **6's principle before 3** — "S14-lite's compensation is the first layer of the one EQ program" is what keeps it from being rebuilt in S12; the full program design can wait until before S12.
8. **7 before 6's slot design** — S12 extends the per-output slot with the correction choice; it needs to know the choice is per device and opt-in.
9. **10 before S14-lite ships** (the acceptance line) and the rename before S15.
10. **2's S16/S17 shape before S15** (own switch vs merge) — cheaper decided when 10 sets S16's exit bar.

Grouped into sittings:

- **Sitting 1 — now, before R1.1-B starts (the frozen sprint):** **1** (leveling's home, the old leveller retired, Off / Auto / Album / Track, Pure wording) · **5** (fold placement, one layout owner, C-45's rest + C-47 into R1.1-B) · **4's one-line principle** (true-peak cap now; the ledger later) · **8's R1.1-B halves** (fold chip, Pure reason) · the doc consequence of 1: strike "loudness-comp" and "(+ crossfeed)" from S17 · the R1.1-B cap question that 1a + 5a raise (see §C — a proposal, not one of the 10).
- **Sitting 1½ — before ENG starts (can be the same evening):** **9's ENG half** (the acceptance carry list, C-49 / C-48, the engine half of W2 named, the ceiling measured; −1 dBTP meanwhile).
- **Sitting 2 — before S14-lite (during ENG's compare phase at the latest):** **3** · **4 in full** (the ledger as S14-lite's slice) · **9's S14 and S15 halves** (drop "Depends on: ENG"; the reducer's slot) · **6's principle** (one program, layers; Compare's one meaning) · **2's rule** ("never a hand-set switch"; Clarity gets its own switch — cheaper before S14 ships its switch) · **7's rule** (opt-in per device; it also settles US-R1F-12's text) · **10** (the acceptance line; the rename).
- **Sitting 3 — before S12:** **6 in full** (program design, slot extension, KI-EQ-01, "Bypass all", the S13 rewrite, the profile model kept or cut) · **7 confirmed** in the slot design.
- **Can wait:** **8's control and BRIR home** (before S18 — after 5 it is a confirmation) · **2's merge-or-switch** (before S15) · **9b / 9c as fallbacks** if S15 cannot carry the reducer under the cap (before S15).

In one line: **5 → 1 → (4-principle) → 9-ENG → [3 + 4 + 9-S14/S15 + 6-principle + 2-rule + 7-rule + 10] → 6-full (+7) → 8 → 2-shape.**

---

## C. The plan if every recommended answer is taken

Legend: **+** added · **−** removed · **→** moved · net scope per sprint in bold.

**R1.1-B — the decided medium items** (**grows** by roughly a week to a week and a half, estimate — over its cap)
- + Leveling: Off / Auto / Album / Track through the per-track gain owner; the old leveller retired; a fixed unknown-loudness gain; a displayed target; tags read when present; "Leveling off (bit-perfect)" on Pure [US-R1F-10, C-38].
- + The fold inside the kernel before the one limiter; one decoded layout per item published to both units; C-45's rest and C-47's minimal form [US-R1F-08 ← S12]; no second ceiling.
- + The fold's chip ("5.1 → stereo") and the Pure reason wording [US-R1F-08, from decision 8].
- + The shared "Not in Pure Mode" row state — first instance, reused by every later DSP control.
- + (if 5b instead of 5a, or for leveling's cap) a true-peak field in the analyser profile — estimate, a day or two.
- unchanged: shuffle as a permutation [US-R1F-01], one search rule + ⌘F [US-R1F-14], atomic queue restore [US-R1F-01], loose files [US-LIB-02, US-PLIST-02], "Use this drive" [US-R1F-03].
- *BA proposal (not a decision in the 10):* keep the cap by splitting R1.1-B into **B1 — sound** (the fold, leveling, the Pure row state) and **B2 — player** (the five others), each under 2 weeks, one PR each, B1 first since it is what the review froze on; or move loose files and "Use this drive" to the next sprint that touches the library. Either is the founder's call; "Use this drive" was placed in R1.1-B by the founder (§9 item 11), so moving it needs the founder's word.

**ENG — the Engine sprint** (**fits**: acceptance grows, build unchanged)
- + Acceptance names the R1.1 contract tests to re-prove: the one-converter seam, seek-to-end, roles-from-labels, leveling-at-the-seam [US-PE-01].
- + C-49 (the EQ below 44 kHz) and C-48 in the carry list; the engine half of W2 named as a deliverable; the output-side conversion measured and the ceiling settled; the developer switch and the losing path removed inside the sprint [US-PE-03].

**S14-lite — loudness compensation** (**at the cap**: the ledger is about a week, the neutrality rework disappears — estimate)
- − "Depends on: ENG"; − "waits for W2".
- + Level = Master Gain + the device's own volume through the existing listener, relative to a one-time reference; attenuate-mid; one cap; written as the first layer of the one EQ program [US-TON-03, US-ADAPT-03].
- + The headroom ledger as the slice (replaces "taste-only neutrality"): per-band sum ≤ +12 dB, one pre-gain, the limiter's gain reduction metered [architecture §11 → shipped in part].
- + One "Level" card in signal order with a net-gain readout; "not in Pure"; the blind A/B as the last acceptance line.

**S12 — parametric EQ + AutoEq import** (**at the cap**, honest: loses two things, gains three of its own)
- − C-45's rest → R1.1-B; − C-47 → R1.1-B; − the A/B row (Compare keeps one meaning).
- + The one EQ program (ordered layers, composed read-back, a bypass per layer); the per-output slot extended with the parametric bands and the correction choice; KI-EQ-01 fixed ← pool; AutoEq's preamp dropped on import (the ledger); "Bypass all processing" [US-PROF-02] (or → S16); the preset's display name → "Detail".

**S13 — headphone and device correction** (**grows or shrinks by the profile decision**)
- − the "delivered early" claim.
- + Identification (headphone model → correction entry); a correction layer keyed by model inside the program, separate from the taste slot; offer-and-remember, off on a fresh install; a chip. The profile model [US-DEVICE-04 / -05] either an explicit third part (grows past 7 sp, estimate) or cut to "correction + taste" for R2 (fits).

**S11-lite** — unchanged.

**S15 — masking spike** (**grows**: the one real cap risk)
- + The transport reducer + command layer (W2's transport half) as its slice, cut per event family under finish-or-revert; + S16's exit bar named (the blind A/B). Fallbacks: 9b (an EP-MCP sprint in R2) or 9c (strike "W2 events").

**S16 — Clarity** (**shrinks and grows**: net about the same)
- − a second filter engine (the Arbiter emits into the program; the fitter narrowed to the FIR opt-in).
- + Clarity's own switch and chip, audible the sprint it ships; the blind A/B as the last line — "wins or ships off and hidden".

**S17 — Intensity returns** (**shrinks**)
- Mapping = Clarity depth + spatial room amount only; − loudness-comp, − crossfeed, − BRIR wet/dry; the correlation-compensated blend (C-40) stays; default 0; the row, US-ADAPT-05 and FR-REIMAGINE-02 rewritten.

**S18 — BRIR** (**about the same**)
- + One "Headphones: Off / Crossfeed / Spatial" control, remembered per output; BRIR at the one N→M slot for every width; − the kernel's BRIR stub; the S4 design superseded; opt-in per device; the blind A/B as the last line.

**EP-MCP** — a consumer of S15's command layer, not W2's funder; "R2 or later" unchanged.

**Net:** R1.1-B grows (the only sprint that needs a scope move to hold its cap); ENG's acceptance grows; S14-lite and S12 stay at their caps with honest contents; S13 and S15 depend on one choice each (the profile model; the reducer's slot); S16, S17 shrink; S18 holds.

---

## D. Open items the reports left for the founder that are not among the 10

One line each, with the reports' recommended answer.

- **Leveling target, −16 vs −14 LUFS** — display it; −14 matches Roon and Spotify, −18 matches ReplayGain files; the reports lean −14 (other-players F8). Today's −16 is "not wrong, just undeclared".
- **ReplayGain / R128 tags** (US-R1F-10's own "Open") — read them when present, analysis otherwise; every open-source player does, Roon opt-in.
- **Unknown-loudness fallback** — a fixed cut (Roon's −5 dB) when leveling is on, instead of the live estimate that moves the level during a song.
- **The −0.1 dBTP wired ceiling (Sprint EQ decision 29)** — keep −1 dBTP everywhere until ENG measures the output-side conversion; if "EQ On sounds quieter" returns, solve it with the ledger's pre-gain and a GR meter, not a moving ceiling. Amends a founder decision — needs the founder's word.
- **The compensation cap numbers** — one set; the listener report recommends FR-TONAL-03's +6 / +4 dB as the listener-safe pair, with ±12 dB as the ceiling, not the target. (Moot in the attenuate-mid form; relevant if the boost form is kept.)
- **Where the "Level" card lives** — one place, in signal order (Master Gain, "Even out track levels", "Keep bass and treble at low volume"); the listener report says Settings or the inspector, not which — a UI call.
- **The "Clarity" preset rename** — display name "Detail", stored id unchanged (as decision 31 did for "Loudness"); a day, any time before S15. (The tail of decision 10, listed here because it stands alone.)
- **The Pure give-back** — a toast ("Volume restored") when Pure hands the device volume back at the end of the queue; on Pure the readout shows both numbers ("−6 dB · device at −18 dB"); add "volume keys during Pure, then end of queue" to FD-5's hardware check list.
- **The shared "Not in Pure Mode" row state** — one rule, first instance in R1.1-B, reused by Leveling, Loudness, Correction, Clarity, Spatial and crossfeed; the Pure badge lists what is skipped.
- **US-R1F-12's crossfeed sentence vs the shipped gate** — the text says "any output", the code gates to headphones; align the text now, and let decision 7's rule (per-output memory, class default, manual override) decide the gate later.
- **Crossfeed on a folded 5.1 file** — stereo-only until S18; the chip and the switch should read the kernel's bypass so "XF" never shows when nothing plays.
- **A true-peak field in the analyser profile** — none exists; leveling's cap and the fold trim both want it; a day or two in R1.1-B (estimate).
- **SPIKE-LOUDNESS-COMP-TUNING's "MUSHRA, 10+ listeners"** — not something one founder can run; replace with the adaptive-tone Stage 1 ladder (decision 10's protocol).
- **US-SPAT-01's ABX "audible difference"** — the wrong bar; preference on a blind, level-matched A/B.
- **S13's "identification delivered early"** — the pins are taste memory per device, not headphone-model identification; the row should say so whatever decision 6 picks.
- **The stale slice-catalogue rows** (C-46, C-50 under W5; C-12, C-30 under R1.1-B — already closed in R1.1-A) — annotate the catalogue as a record, not a to-do list, so no sprint re-does them.
- **US-PE-03's "two engines never ship"** — state that the developer switch and the losing path are deleted inside the sprint (a reverted build with the switch left in is still two engines).
- **Leveling for a folded file** — after the fold the stereo loudness sits 1–2 LU under the six-channel figure; use the folded loudness once the fold's true peak is analysed (a note on US-R1F-10, not a blocker).
- **The two things called "Realizer"** — the shipped control-plane planner and the designed perceptual one; name the second thing before S16 so the rows stop conflating them.
