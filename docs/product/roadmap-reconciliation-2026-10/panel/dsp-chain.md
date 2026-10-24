# Roadmap review — the signal chain (gain staging, headroom, stages that fight)

Reviewer lens: stage order, gain stages, headroom, duplicated gain/EQ, assumptions one feature makes that another breaks.
Checkout: `.claude/worktrees/testrig-integration` (branch `testrig/integration`, HEAD e76edf6). Every code claim was read in this session; `Sources/...:line` is cited. Where a finding rests on a doc sentence with no code behind it, it says **docs only — not verified in code**. Where I reason from DSP principle rather than a doc or the code, it says **(DSP principle)**.

---

## 1. Today's chain (what the code does, 2026-10-23)

### Enhanced path (the only path with DSP)

```
AVAudioFile decode → StreamingResampler (Mastering, 48 kHz graph; bit-exact at equal rates)
→ AVAudioPlayerNode  [player.volume = Master Gain: turn-down only, 0 … −60 dB, then Silent]
→ effectsAU  (DSPKernel::process, N→N in place)           Sources/AudioDSP/DSPKernel.cpp:159-243
     scrub NaN/Inf (:175-181) → causal loudness tap sees the SOURCE (:185) → EQ adopts its target (:189)
     P0  Intensity settled 0 + EQ identity + crossfeed off, held 2 s → block returned untouched (:206-230)
     else EQ: 31 Simper SVF bells, interaction-solved + outputGainDb = −ΔL loudness-neutral gain (:250; EQ/EQModule.h:5-23)
       P1  Intensity 0: → Crossfeed → Limiter at the EQ-only ceiling (−0.1 dBTP wired, −1 dBTP wireless/unknown) (:251-262)
       P2  Intensity 1: → Clarity(STUB) → BRIR(STUB) → LoudnessModule (session AGC) → Crossfeed → Limiter −1 dBTP (:263-270)
       P3  blend: dry = EQ'd; wet = Clarity→BRIR (stubs); equal-power sin/cos; AGC contribution min(1, r/0.1) gliding ≤ 1 per 2 s; → Crossfeed → Limiter (:274-319)
→ spatialAU  (SpatialRenderKernel, N→M = min(N, device))   Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp:134-177
     M ≥ N: bit-exact copy (:163-169).  M < N: TRUNCATION — first M channels, rest dropped (:60-92, :170-176). No limiter here.
→ mainMixerNode (the player's Master Gain is applied at its input bus — per the code comment, see note) → outputNode → device
     device volume: NOT observed and NOT set on Enhanced (Sources/AdaptiveSound/AudioEngineBridge+MasterGain.swift:76-92, 140-156: watched only from enterPureVolume)
```

Stage reality: Clarity and BRIR are explicit pass-through stubs (`Sources/AudioDSP/Clarity/ClarityModule.h:26-34`, `Sources/AudioDSP/Spatial/BRIRModule.h:26-33`). Crossfeed is real bs2b, stereo-only, an output stage at full strength whatever Intensity is (`Sources/AudioDSP/Spatial/CrossfeedModule.cpp:18-22, 44-54`; `DSPKernel.cpp:321-331`). LoudnessModule is a real BS.1770 session AGC: target −16 LUFS, makeup clamped −20 … +12 dB, 1 dB/s, `enabled = 1` by default, run only on P2/P3 (`Sources/AudioDSP/Loudness/LoudnessModule.h:55-57`, `.cpp:276-299`; `Sources/AudioDSP/include/TargetState.h:60-66`). The limiter is real: 8× true-peak, 3 ms look-ahead, program-dependent release (`Sources/AudioDSP/Limiting/LimiterModule.h:13-37`; `include/AudioConstants.h:16-33`).

Default at a fresh install: Intensity 0, hidden (`Sources/AdaptiveSound/AudioViewModel.swift:188, 201`), EQ off, crossfeed off → **P0, bit-exact**.

### Gain stages that exist today (where, and their own clamp)

| # | Stage | Where | Range / clamp | Applies on |
|---|---|---|---|---|
| G1 | EQ points | UI → Realizer | ±12 dB per point (`Sources/EQEditKit/EQBands.swift:26`; `EQCurve.swift:42-47`; `Sources/AudioDSP/AudioEngine/Realizer.h:120-123`). The **realized** bells go beyond: "up to ~±33 dB on adversarial commands" (`Sources/AudioDSP/EQ/GraphicEQDesigner.h:43-45`) | P1–P3 |
| G2 | Loudness-neutral EQ gain −ΔL | `eq.outputGainDb`, rides the EQ smoother | clamped ±12 dB (`Sources/AudioDSP/Loudness/TrackLoudnessGain.cpp:13-14, 120`); 0 when the EQ is off (`:106-109`) | P1–P3 |
| G3 | Session AGC makeup | LoudnessModule, own atomic | −20 … +12 dB (`LoudnessModule.h:55-56`); faded by Intensity (`DSPKernel.cpp:37-43, 348-351`) | P2, P3 only |
| G4 | Blend hump | equal-power sin+cos on correlated wet=dry | +0 … +3.01 dB (`DSPKernel.cpp:285-287` comment; council C-40) | P3 only |
| G5 | Crossfeed | bs2b shelf + feed | direct path 0 … −1.8 dB HF; feed −4.5 … −9.5 dB (`TargetState.h:78-91`) | P1–P3, stereo only |
| G6 | True-peak limiter | last in effectsAU | −1 dBTP; −0.1 dBTP on P1 wired (`AudioConstants.h:16-21`; `Limiting/OutputCeiling.h:19-40`) | P1–P3 |
| G7 | Master Gain | player node, **outside the kernel** | 0 … −60 dB, turn-down only (`Sources/EQEditKit/MasterGainLaw.swift:16-48`; `AudioEngineBridge+MasterGain.swift:44-46`) | always |
| G8 | Device volume | HAL | observed/set only on Pure (`Sources/EQEditKit/MasterGainOnPure.swift:1-40`) | — |

The ±12 dB "trust clamp" is **three independent ±12s** (G1, G2, G3) plus a per-point UI ceiling; nothing clamps their sum. The architecture's cumulative +12 dB clamp is design only (`docs/architecture/architecture.md:346-348`).

Note on G7: `AudioEngineBridge+MasterGain.swift:13-14` says the player's volume "applies it at the mixer's input bus, after the DSP AUs (so after their limiter)". Apple's AVAudioMixing docs (opened) say `volume` is a mixer-input-bus property implemented only by the mixer/environment nodes; whether it propagates through two intermediate AUs was **not measured** here. Load-bearing fact either way: the kernel and the Realizer receive **no level intent at all** (`Realizer.h:118-146`: EQ, Intensity, crossfeed, track loudness, output transport — nothing else).

### Pure path
Decode → HAL direct. No DSP of any kind (`architecture.md:88`). Master Gain becomes a loan on the device's own volume (`MasterGainOnPure.swift:7-17`). The EQ strip says "Pure Mode is on — the EQ doesn't play" (`Sources/AdaptiveSound/UI/EQ/EQGraphStrip.swift:74-75`); the crossfeed "XF" chip hides on Pure (`Sources/AdaptiveSound/SignalPathInfo.swift:104-109`) but the crossfeed switch itself gates only on headphones, not on Pure (`UI/NowPlaying/InspectorColumn.swift:139-185`).

---

## 2. The chain after the plan (R1.1-B → S14-lite → S12 → S13 → S16 → S17 → S18), as the docs describe it

Items marked ⟂ are **docs only — not verified in code** (nothing exists yet). Items marked ✗ are where two docs, or a doc and the code, disagree.

```
decode → [Engine sprint: AVAudioSourceNode pull engine; graph at the DEVICE rate; "our two AUs unchanged"]  (roadmap.md:87; architecture.md:87)
→ effectsAU
     EQProgram ⟂ (S12, arch.md:346-351): ordered layers [correction (S13) | taste = 31-band + PEQ + AutoEq (S12) | compensation (S14)]
         → ONE SVF cascade with per-band (g, k, m1), SVF shelves, per-layer neutrality (−ΔL from the taste layer only — "W5-min", stage5-architect.md:276-277)
     → dry tap → Clarity ⟂ (S16: Arbiter in ERB + a SECOND filter engine: L-M-fitted TDF-II biquads, architecture.md:244-258)
                → BRIR ✗ (kernel slot here, DSPKernel.cpp:431-436 … but S18 says "the spatial AU's slot")
                → Intensity blend (S17: correlation-compensated, C-40)
     → Leveling ⟂ (R1.1-B: static Off/Album/Track gain from TrackLoudnessKit; placement unspecified) … and the AGC (G3) is still in the code unless removed ✗
     → Crossfeed (bs2b, full strength — code and founder 2026-10-14) ✗ S17 text says Intensity scales it
     → Limiter (−1 / −0.1 dBTP)
→ spatialAU: BS.775 fold ⟂ (R1.1-B, N→2 / N→6) → "a safety ceiling after the spatial stage" ⟂ = a SECOND true-peak limiter; S18 BRIR ⟂ "replaces it in the same slot"
→ mainMixer (Master Gain) → device (volume still unobserved on Enhanced until W2 — roadmap.md:96; arch.md:668)
```

New gain stages the plan adds: leveling (±? capped by true peak), compensation (+12 dB default cap per `backlog.md:561`; +6 / +4 dB per `requirements.md:354` — the backlog itself flags the disagreement at `:556`), correction (AutoEq filters + its own `Preamp:` line), Clarity's dynamic per-band gain (±12 dB per biquad, `architecture.md:266`), the fold's up-to-+7.7 dB (BS.775 Table 2 sums 1 + 0.707 + 0.707; council P2 breaker §2.5), the second ceiling.

---

## 3. Findings, ranked by harm to what the listener hears

### F1 — S16 ships Clarity into a path no default listener can hear
**Items:** S16 (Clarity, US-PERC-02/03) vs FD-2 / US-R1F-09 (Intensity hidden and held at 0 until S17) · **Type:** contradiction (sprint order).
**Code today:** Clarity runs only inside the coloration chain (`DSPKernel.cpp:431-436`), which only P2/P3 call (`:263-271, 283`); at Intensity 0 the kernel takes P0/P1 and never calls it (`:251-262`). Intensity is `static let offersIntensity = false` and `intensity: Float = 0`, never restored (`AudioViewModel.swift:188, 201`; `architecture.md:153` "Intensity is never kept").
**Plan:** roadmap.md:44 "Intensity is hidden until its effects are real (S17)"; sprint-plan.md:111 S16 = "Arbiter + Realizer v1 … A/B vs bypass"; S17 (sprint-plan.md:112) is where Intensity returns, and it *depends on* S16.
**Why it matters:** as scheduled, S16's "core perceptual differentiator" has no audible path until the following sprint; its "A/B vs bypass" can only be run on a developer build, and whatever S16 tunes will be re-tuned once the correlation-compensated blend (C-40) lands in S17 — equal-power blending of a correlated wet adds up to +3 dB (`DSPKernel.cpp:285-287`; council D50), so S16's A/B would be level-biased anyway.
**Severity:** must resolve before S16 starts.
**Resolution:** give Clarity its own switch and depth as an output-independent stage (the pattern crossfeed already took on 2026-10-14), or pull Intensity's return and the C-40 blend fix into S16 so the stage is audible the sprint it ships. Alternatives: merge S16 and S17 into one sprint.

### F2 — R1.1-B's leveling collides with the kernel's Intensity-gated AGC, and S14/S17 still describe the old model
**Items:** R1.1-B US-R1F-10 (leveling Off/Album/Track, static gain) vs today's LoudnessModule vs S14-lite / S17 · **Type:** contradiction.
**Code today:** the only leveler is the AGC: `LoudnessParams.enabled = 1` (`TargetState.h:64`), applied on P2/P3 only (`DSPKernel.cpp:267, 316-317`), its contribution a function of Intensity (`loudnessContributionAt`, `DSPKernel.cpp:348-351`; decision 33 glide `:37-43`); P1 is "No coloration, no normaliser" by design (`:253`). `LoudnessParams.makeupGainLinear` exists but has **no writer** (`TargetState.h:62`; grep — only the declaration).
**Plan:** US-R1F-10 (`backlog.md:1752-1763`) names Off/Album/Track, a static per-track gain "computed from the existing load-time analysis … applied sample-accurately at the seam … capped so the true peak stays under the ceiling without the limiter acting as a compressor" — but names **no placement**, does **not** retire the AGC, and does not say what Intensity > 0 does to it. S17 still says Intensity maps "0→1 across loudness-comp" (sprint-plan.md:112; roadmap.md:150). The stage5 slice catalogue puts "C-38 (static per-track/album gain + true-peak cap)" in **W5, at S12**, not R1.1-B (`stage5-architect.md:334`) — the two documents schedule the same fix in two sprints.
**Why it matters:** (a) with leveling a setting and Intensity 0, the gain must run on P1 — a path that today has no leveler and uses the −0.1 dBTP wired ceiling (`OutputCeiling.h:6-11`), so a Track-levelled quiet record is pushed into a 0.1 dB ceiling unless the TP cap is exact; (b) unless the AGC is deleted, the day S17 returns Intensity the session AGC (DRC in effect, council C-38; the FD-2 rationale) comes back on top of the static gain — two levelers, 1 dB/s drift over a user-chosen static level.
**Severity:** must resolve before R1.1-B starts.
**Resolution:** R1.1-B replaces the AGC's makeup with the static gain published by the Realizer through the unused `LoudnessParams.makeupGainLinear`, applied on every processed path (P1 included) and independent of Intensity; delete `loudnessContributionAt` and the AGC law, keep the causal meter only as the per-track fallback; and strike "loudness-comp" from S17's mapping. Alternatives: keep the AGC as an opt-in "Loud" mode (P2 sota P2-2 option B); or move leveling to S12's W5 slice as stage5 has it and ship only the Off switch in R1.1-B.

### F3 — Loudness compensation has no level to read; the level is observed exactly on the path that has no DSP
**Items:** S14-lite ("a level input (C-09)") vs Master Gain on Enhanced vs Master Gain on Pure (R1.1-A) · **Type:** contradiction.
**Code today:** no level reaches the kernel or the Realizer (`Realizer.h:118-146` — the whole intent surface). Master Gain is the player node's volume, outside the DSP (`AudioEngineBridge+MasterGain.swift:44-46`). The device's own volume is read and followed **only on Pure** (`watchDeviceVolume` is private and called only from `enterPureVolume`, `:76-92, 140-156`), and Pure has no DSP. So: Enhanced has the DSP and no level; Pure has the level and no DSP.
**Plan:** roadmap.md:96 "a level input (C-09)" for S14-lite, while "the system volume observed … waits for W2"; arch.md:668 says the same in full and adds "(4) Pure has no DSP, so the feature must be disabled there honestly". requirements.md:352 (FR-TONAL-03) requires "a per-device SPL calibration (the app cannot know absolute SPL otherwise)". US-TON-03's acceptance "volume reduced by 20 dB → bass +6–10 dB" (`backlog.md:559`) never says which volume.
**Why it matters:** with Master Gain as the only input, compensation reacts to the app slider but not to the volume keys, Control Center or the DAC's knob — the listener who leaves Master Gain at 0 dB (the default) and uses the Mac's volume gets **no compensation at any level**, and the one who uses Master Gain gets compensation referenced to an unknown SPL. That is not "the loudness button" (sprint-plan.md:84); it is a tone control that moves when one slider moves.
**Severity:** must resolve before S14-lite starts.
**Resolution:** define S14-lite's level as Master Gain + the device's dB volume read through the existing `DeviceHardwareVolume` seam on Enhanced too (a listener on the output device, the same one Pure already installs) + a per-device calibration offset the user sets once, published as one Realizer intent; if the device read is out of scope, label the control "Listening level" and make it manual, never "adaptive". Alternatives: W2 first (the roadmap's own fallback), accepting that S14-lite then ships a static tilt.

### F4 — Loudness compensation is "loudness-matched" in one document and "exempt from neutrality" in the other; they are different products with different headroom
**Items:** S14-lite · **Type:** contradiction (docs).
**Docs:** LD-17 and §9 say compensation includes "**loudness-matched makeup**" (`architecture.md:30, 333`; `requirements.md:352`). The council says the opposite — the neutral gain "would cancel the loudness-compensation tilt it exists to add", so the compensation layer is "**exempt from neutrality**" (`stage5-architect.md:57` C-09; `arch.md:343-344, 610`); the roadmap adopts the council's slice (roadmap.md:96).
**Code today:** neutrality is computed over the whole realized curve: `canonical_.eq.outputGainDb = loudness_.onDesign(design, eq_.isOn)` (`Realizer.mm:418`), so a tilt folded into today's single intent is indeed neutralised.
**Why it matters (DSP principle):** a neutral tilt (bass/treble up, mids down by −ΔL) costs no headroom and cannot hit the limiter; a boosting layer (+6 … +12 dB low end, per `requirements.md:354` / `backlog.md:561`) on a −9 LUFS master at −0.1 dBTP (the P1 wired ceiling) puts the limiter into sustained gain reduction — `OutputCeiling.h:6-8` documents exactly this behaviour at −1 dBTP ("> 1 dB of gain reduction up to 74 % of the time on a −9 LUFS master"). The two readings therefore decide whether S14-lite is transparent or is program limiting on loud records.
**Severity:** must resolve before S14-lite starts.
**Resolution:** choose "exempt from neutrality, capped by the track's true-peak headroom" (the council's reading, the one listeners mean by a loudness button), correct the LD-17 / FR-TONAL-03 wording, and add a true-peak field to the analyser profile (it has none — `TrackLoudnessProfile.h`, grep for peak: nothing; the P2 breaker says the same at `panel-p2-loudness-breaker.md:119`). Alternative: the neutral tilt — safer, cheaper, but then the control must not be sold as "boost bass and treble when I turn the volume down" (`backlog.md:552`).

### F5 — The ±12 dB trust clamp is a per-stage number, never a sum; the plan adds four more boosters to it
**Items:** S14-lite (compensation cap), S12 (PEQ/AutoEq), S13 (correction), S16 (Clarity), R1.1-B (leveling) vs principle (d) "±12 dB hearing-safety trust clamp on total boost" · **Type:** overlap / complication.
**Code today:** G1, G2, G3 in §1 each carry their own ±12, independently (`EQBands.swift:26`; `Realizer.h:120-123`; `TrackLoudnessGain.cpp:13-14, 120`; `LoudnessModule.h:56`); the realized bells reach ±33 dB (`GraphicEQDesigner.h:43-45`). No code sums them; the architecture's "cumulative gain-driven loudness change +12 dB, hard" is a table in a section headed DESIGN — NOT YET SHIPPED (`architecture.md:346-358`).
**Plan:** roadmap.md:96 "Compensation must respect the ±12 dB trust clamp, **with its own headroom or a cap**" and stage5-architect.md:277 "Give compensation its own headroom, **or** cap it" — "respect the clamp" (sum ≤ 12) and "its own headroom" (a second budget) are two different rules in one sentence. Clarity's fitter clamps ±12 per biquad (`architecture.md:266`); AutoEq filters arrive with their own gains and a negative `Preamp:` line (PipeWire man page, opened).
**Why it matters:** a +12 dB taste point + a +6 dB compensation + a +5 dB correction + a Clarity lift in the same band is +23 dB of request in the hearing-hazard band before any limiter — the clamp the founder relies on does not exist as a sum, and after S13 it is the auto-loaded correction, not the user, that spends part of the budget.
**Severity:** should resolve before S14-lite (the first sprint to add a second boost).
**Resolution:** define the clamp as a per-band sum over the realized EQProgram layers (correction + taste + compensation) at +12 dB, enforced in the Realizer at compose time by proportional scaling (architecture §4 rule 3, `architecture.md:238`) and shown on the graph as "held"; leveling and Clarity's dynamic gain sit outside it, each capped by true-peak headroom. Alternative: separate budgets per layer with the composed curve's peak reported.

### F6 — The BS.775 fold's "ceiling after the spatial stage" is a second limiter, and on 5.1 it is a program limiter by default
**Items:** R1.1-B US-R1F-08 / FD-9 (C-43) vs LD-17 "no program DRC by default" vs S18 · **Type:** complication / contradiction.
**Code today:** the graph is player → effectsAU → spatialAU → mixer (`AudioEngineBridge+Graph.swift:64-74`); the limiter is the last stage **inside the effects AU** (`DSPKernel.cpp:325-331`); the spatial kernel only copies (`SpatialRenderKernel.cpp:32-58, 76-92`) and has no limiter, no look-ahead, no TruePeakKernel.
**Plan:** roadmap.md:62 "a safety ceiling after the spatial stage"; `known-issues.md:262-264` "(the limiter sits before the spatial stage today — council C-43)"; the P2 breaker measured the fold's worst case at +7.7 dB (`panel-p2-loudness-breaker.md:229-231`) and said the alternative is worst-case normalisation.
**Why it matters (DSP principle):** Lo = L + 0.707 C + 0.707 Ls on a dense 5.1 master exceeds 0 dBFS routinely, so a ceiling placed after the fold does **sustained** gain reduction on most multichannel material — dynamic-range compression by default on exactly the files R1.1-B exists to fix, contrary to LD-17; it also adds a second 3 ms look-ahead (`AudioConstants.h:30`) in a second AU, needs its own transport-aware ceiling (the P1 −0.1 dBTP rule, `OutputCeiling.h`), and the effects AU's limiter is wasted work for N > M. S18's HRIR sum has the same property, so the slot inherits the problem.
**Severity:** should resolve before R1.1-B starts.
**Resolution:** keep the ceiling as a safety net but make it rarely act: the analyser already decodes every track ahead (`Sources/TrackLoudnessKit/TrackLoudnessAnalyzer.swift`), so compute the BS.775-folded true peak per track and apply a static fold trim = min(0, ceiling − TP_fold) at the seam — the same "static gain capped by true peak" rule R1.1-B adopts for leveling — and meter the second limiter's gain reduction so "transparent" is checkable. Alternatives: worst-case −7.7 dB fold normalisation (transparent, audibly quieter); the plan's bare ceiling with a GR meter.

### F7 — BRIR has two homes in the documents, and only one of them can fold or be blended
**Items:** S18 (BRIR "in the same slot" as the fold), S17 (Intensity scales spatial), the kernel's BRIR slot, crossfeed exclusivity · **Type:** contradiction.
**Code today:** `BRIRModule` is instantiated inside the effects AU, **N→N in place**, inside the Intensity blend (`DSPKernel.cpp:61, 431-436`; `BRIRModule.h:26-33`). The spatial AU is the device-boundary N→M stage (`SpatialRenderKernel.h:3-11`). `TargetState.h:100-105` records that crossfeed and BRIR are mutually exclusive and that no arbitration exists.
**Plan:** architecture.md:97 and :303 put BRIR in the kernel's coloration chain under the Intensity blend; roadmap.md:151, sprint-plan.md:113 and architecture.md:98 put the S18 render in the spatial AU, "replacing BS.775 in the same slot". The S4 design the sprint-plan still links as the fold's design chooses Apple's `AVAudioEnvironmentNode` (`docs/sprints/05-sprint-5b-s4-binaural-design.md:19-24`); backlog US-SPAT-01 says Apple's spatial nodes are "explicitly NOT used" (`backlog.md:1333`).
**Why it matters:** an N→N in-place module cannot render 5.1 to 2; a device-boundary renderer sits after the effects AU's limiter and outside the Intensity blend, so S17 cannot crossfade it and the "ceiling after" (F6) must cover it; and crossfeed (effects AU, before the limiter) plus BRIR (spatial AU) have no shared control to enforce the exclusivity, so a listener with crossfeed on gets a head-related cross-path applied twice.
**Severity:** should resolve before S17 (the Intensity mapping needs to know what it scales).
**Resolution:** BRIR renders at the device boundary (the spatial AU slot) for every source width, Intensity drives its room amount / spread as a parameter rather than a wet/dry blend, crossfeed is auto-held-off while BRIR plays, and the kernel's `BRIRModule` slot is retired; mark the S4 Apple-node design superseded. Alternatives: BRIR in the effects AU for stereo sources only, BS.775 kept for N > 2.

### F8 — S17's Intensity still claims three stages that now have controls of their own
**Items:** S17 / US-RMG-02 / SPIKE-REIMAGINE-MAP vs crossfeed (founder 2026-10-14), S14 (compensation slider), R1.1-B (leveling setting) · **Type:** contradiction.
**Code today:** crossfeed plays "at its preset's full strength whatever Intensity is" (`DSPKernel.cpp:321-324`; `TargetState.h:89-91`; `AudioViewModel.swift:190-193`), the KI-SND-05 fix the founder decided. The kernel still fades the **normaliser** with Intensity (`DSPKernel.cpp:348-351`).
**Plan:** sprint-plan.md:112 "Map intensity 0→1 across loudness-comp + clarity (+ crossfeed)"; roadmap.md:150 the same; `backlog.md:2158` SPIKE-REIMAGINE-MAP "crossfade + spatial spread + unmask depth". S14 gives compensation its own fraction/level (US-TON-03); R1.1-B gives leveling Off/Album/Track.
**Why it matters:** a listener who set crossfeed Strong, compensation 50 % and leveling Album, then moves Intensity, has two hands on each of those knobs; and the stale crossfeed text will mislead whoever picks up S17.
**Severity:** should resolve before S17; the crossfeed text should be corrected now.
**Resolution:** Intensity scales only what has no control of its own — Clarity depth and BRIR spread — and never crossfeed, leveling or the compensation slider; strike "loudness-comp" and "(+ crossfeed)" from S17 and the spike. Alternative: Intensity as a visible macro that moves the other sliders (then every slider must show it moved).

### F9 — Four EQ sources, two filter engines, one cascade, one Compare
**Items:** S12 (PEQ + AutoEq + `EQProgram`/`FilterSpec`/SVF shelves), S13 (correction + taste "on one graph"), S16 (Clarity's L-M biquad fitter), hold-to-Compare (shipped) · **Type:** complication.
**Code today:** one engine — 31 fixed-centre SVF bells whose gains are interaction-solved by weighted least squares so the cascade plays the drawn points (`EQ/GraphicEQBands.h:9-17`; `EQModule.h:5-14`); the tick hard-codes bell mixing and a fixed per-band prewarp (council P1: `panel-p1-eq.md:220-227` — shelves need per-band (g, m0, m2) and a gliding g). The graph "draws what plays" by reading back the real coefficients (`architecture.md:115`). Compare = publish the EQ **off** at matched loudness (`Sources/EQEditKit/EQSession.swift:159-170`; `AudioViewModel.swift:473-475` → `Realizer.mm:410` publishes an identity design with gain 0).
**Plan:** `arch.md:346-351` — layers [correction, taste, compensation] into "one RT cascade"; architecture §4 — Clarity realized by a **different** engine (greedy-add + Levenberg–Marquardt, TDF-II biquads, ±12 per section, `architecture.md:244-266`); AutoEq files carry LSC/HSC shelves and a negative `Preamp:` (PipeWire man page, opened).
**Why it matters:** (i) once PEQ sections and shelves sit in the same cascade the 31-band WLS solve no longer plays the drawn points unless the solver includes them — the honest-graph promise needs a composed read-back; (ii) AutoEq's `Preamp:` and our −ΔL (`TrackLoudnessGain.h:3-9`) are two headroom rules for one cascade — apply both and the corrected headphones play a few dB too quiet, drop one and loud masters limit; (iii) "hear the song without the EQ" is undefined once correction and compensation are layers: if Compare removes the headphone correction and the level-dependent compensation, it is no longer level-fair (compensation is exempt from neutrality, F4), and if it keeps them, "without the EQ" is false; (iv) two minimum-phase cascades in series (SVF graphic + Clarity biquads) in overlapping bands sum their group delay and ripple, and the Arbiter rule that an auto layer cannot counter a user move in its band (`architecture.md:234`) is design only (`architecture.md:208`).
**Severity:** should resolve before S12 starts.
**Resolution:** one `EQProgram` with one composed read-back; Compare defined per layer (taste only by default — correction and compensation stay, and the control says so); AutoEq's `Preamp:` discarded on import and replaced by −ΔL plus the true-peak cap; Clarity realised as a dynamic layer of the same cascade rather than a second engine. Alternative: keep two engines behind one combined phase/ripple gate in the C++ null test.

### F10 — Correction that loads "right out of the box" breaks the faithful default
**Items:** S13 / US-TON-02 vs FD-2 / US-R1F-09 · **Type:** contradiction.
**Plan:** `backlog.md:537` "automatically apply a frequency response correction for my AirPods Pro … right out of the box"; `backlog.md:1742-1746` "a fresh launch … no leveller, no blend, no EQ"; sprint-plan.md:83 S13 "device-correction EQ **auto-load** by identified device".
**Code today:** the per-output memory already auto-loads a pinned slot by device UID with a model-UID fallback (`Sources/EQEditKit/EQStore.swift:46-57, 97-107`); a fresh install's EQ is Flat and Off (`architecture.md:152`). If S13 writes correction into the pinned taste slot, a second pair of the same model double-applies through the model fallback and the pin's promise "exactly what was last heard on it" (`EQStore.swift:97-98`) breaks; if it is a separate layer that auto-enables, a new install on identified headphones no longer plays the file as recorded.
**Severity:** should resolve before S13 starts.
**Resolution:** correction is a separate layer keyed by model UID, **offered** (a toast) and never on at first launch; auto-load applies only to a device the listener already enabled it for; the pin stays taste-only. Alternative: correction on by default only when the listener opted into "correct my headphones" globally.

### F11 — Every planned sound feature is Enhanced-only, and no story says so
**Items:** R1.1-B leveling, S14 compensation, S13 correction, S16 Clarity, S18 BRIR vs Pure Mode and "Master Gain drives the device volume in Pure" · **Type:** complication (honesty).
**Code today:** Pure bypasses the whole DSP (`architecture.md:88`). The EQ strip is honest (`EQGraphStrip.swift:74-75`); the Reimagine section is dimmed on Pure (`InspectorColumn.swift:90-133`) but hidden anyway; the crossfeed switch gates only on headphones (`InspectorColumn.swift:139-185`) and stays live on Pure while its chip hides (`SignalPathInfo.swift:104-109`). Master Gain on Pure is a device-volume loan at the same dB reading (`MasterGainOnPure.swift:7-17`; `AudioViewModel+MasterGain.swift:21-25`).
**Plan:** US-R1F-10, US-TON-03, US-TON-02, US-PERC-03, US-SPAT-01 (`backlog.md:1752-1763, 552-566, 534-548, 1496-1500, 1325-1339`) — none mentions Pure; US-R1F-13 "Pure says why" covers only bit-perfect reasons; arch.md:668 (4) flags it for S14 only.
**Why it matters:** a listener with correction + leveling + compensation on Enhanced who flips Pure loses all of them silently while Master Gain still reads the same dB — the plan's "one honest level" (US-R1F-05) becomes one honest level and four silent losses.
**Severity:** should resolve, with R1.1-B's leveling as the first instance.
**Resolution:** one rule, applied in R1.1-B and reused — every DSP setting's control says "not in Pure Mode" the way the EQ strip does, and the Pure badge lists what is bypassed. Alternative: offer "Switch to Enhanced to hear this" inline when a DSP setting is turned on while Pure plays.

### F12 — Leveling's seam-accurate gain is built on the seam path the Engine sprint deletes
**Items:** R1.1-B US-R1F-10 vs the Engine sprint (EP-PLAYENGINE) · **Type:** complication (sequencing).
**Code today:** the only "track became audible" event is the Enhanced roll's `trackBecameAudible` (`AudioEngineBridge+Gapless.swift:232`; `+Playback.swift:200`) → `Realizer::setCurrentTrack` (`Realizer.mm:295-310`) — the event the loudness-neutral gain already rides, and which the council found early ("B's gain is applied to the last ≤ ~190 ms of A", `panel-p1-eq.md:244-246`). architecture.md:131: "The Engine sprint replaces this engine (one decode-and-convert worker feeding a ring, counted on the render side)". The kernel work itself survives: "our two audio units unchanged" (roadmap.md:87; `backlog.md:1951`). The Engine sprint also moves the graph to the device rate (architecture.md:87), which makes C-48 live: the limiter's look-ahead caps at 192 kHz (`AudioConstants.h:31-33`) and the EQ designs only ≥ 44 kHz (`GraphicEQDesigner.h:63`).
**Severity:** should resolve (R1.1-B scoping).
**Resolution:** R1.1-B applies the static gain through the existing `setCurrentTrack` path, accepts today's ≤ 190 ms seam tolerance, and writes its test against the engine's seam contract (`GaplessContractTests`) so the Engine sprint inherits it — no second seam mechanism. Alternative: defer the sample-accurate wording to after the Engine sprint.

### F13 — Multichannel: the levelers measure six channels, the listener hears two, and crossfeed silently stops
**Items:** R1.1-B fold + leveling, shipped crossfeed, S18 · **Type:** complication.
**Code today:** the analyser and the AGC measure the N-channel source with BS.1770 weights (`TrackLoudnessProfile.h:6-14`; `LoudnessModule.cpp:235-251`); crossfeed is stereo-only and sits upstream of the fold at width N (`CrossfeedModule.cpp:18-22, 49-54`), so on a 5.1 file on headphones it does nothing while the "XF" chip keys only on the path (`SignalPathInfo.swift:107-109`).
**Why it matters (DSP principle):** after a BS.775 fold of uncorrelated channels the stereo loudness sits roughly 1–2 LU under the weighted 5.1 figure (fold power 2 + 2 vs weights 1+1+1+1.41+1.41) — a small Track/Album leveling error; the silent crossfeed is a wrong chip.
**Severity:** note (S18 replaces crossfeed for N > 2).
**Resolution:** the chip and the switch read the kernel's `isBypassed` (`CrossfeedModule.cpp:37-42`), crossfeed is documented stereo-only until S18, and leveling for N > M uses the folded loudness once the fold's true peak is analysed (F6).

### F14 — Crossfeed's shipped gate contradicts its own acceptance text
**Items:** US-R1F-12 (R1.1-A, shipped) · **Type:** contradiction (doc vs code).
**Code today:** `crossfeedPlays = crossfeedEnabled && deviceIsHeadphones` (`AudioViewModel.swift:233-235`); the UI says "Connect headphones to enable." (`InspectorColumn.swift:168-174`); `followHeadphones` holds it off on non-headphones (`AudioViewModel+Devices.swift:24-33`).
**Doc:** `backlog.md:1783` "It can be enabled on any output, and wired headphones in the built-in jack are detected as headphones" — the first clause is not what shipped (the second is). The council's own recommendation was "Leave crossfeed user-enableable on any output rather than auto-gated" (`panel-p2-loudness-breaker.md:265`).
**Severity:** note (fix the sentence, or decide the gate).
**Resolution:** correct US-R1F-12's acceptance to the shipped headphones-only gate, or lift the gate with the existing tooltip's rationale.

---

## 4. Checked, no conflict

- **P0's bit-exact anchor survives the plan.** Every added stage is opt-in or gated (leveling Off default, EQ Off, crossfeed off, correction offered not forced per F10's resolution), so Intensity 0 + EQ off + leveling off stays `memcmp`-identical (`DSPKernel.cpp:206-230`); the C++ null test's golden master stays meaningful.
- **Limiter last inside the effects AU, crossfeed before it** (`DSPKernel.cpp:321-331`): right order — crossfeed can add level, and the ceiling holds with it on (`known-issues.md:780`, `Limiter_TruePeak_CeilingWithCrossfeed`).
- **Master Gain can never create an over**: turn-down only, 0 dB at the top (`MasterGainLaw.swift:5, 45-48`); never restored louder (`Sources/SettingsKit/ListeningSettings.swift:79`). Whether it sits before or after the limiter changes only how hard the limiter works, not the ceiling.
- **Master Gain on Pure vs leveling / compensation**: no fight — Pure has neither (the honesty gap is F11, not a chain conflict).
- **Loudness-neutral EQ gain vs leveling**: different quantities (−ΔL is the EQ curve's own loudness change on the source profile; leveling is the source's distance from a target) that add in dB; the profile is of the **source**, before the EQ (`TrackLoudnessProfile.h:6-14`), so leveling cannot chase the EQ.
- **Shelves on the SVF**: feasible by Simper's mixing (`panel-p1-eq.md:220-223`); S12's "SVF shelves" is blocked by the tick's fixed m0/m2 and prewarp, not by the SVF.
- **EQ-only ceiling follows the output**: `Realizer::setOutputTransport` (`Realizer.mm:279-291`) is republished on every device change (`AudioViewModel.swift:119`); consistent with per-output EQ pins keyed by UID (`EQOutputKey.swift:6-29`).
- **Crossfeed persisted as chosen, not as the output allows** (`ListeningSettings.swift:30-32`; `AudioViewModel.swift:210-235`): consistent with the headphone gate.
- **Channel-layout ownership is sequenced, not conflicting**: today the layout bypasses the Realizer (`AUAudioUnit.mm:153-157`; `AudioEngineBridge+ChannelLayout.swift:53-55`); R1.1-B fixes the weights (C-45), S12 moves ownership into the Realizer (C-45's rest) — fine, provided R1.1-B's fix re-publishes after re-allocation (council D70) rather than waiting for S12.
- **The Engine sprint and the kernel**: "our two AUs unchanged" keeps every kernel/Realizer change from R1.1-B and S14 intact; only the seam-event timing (F12) and the rate domain change.
- **Mastering SRC ahead of the kernel**: bit-exact at equal rates, no gain stage; nothing in the plan stacks on its old behaviour.
- **MCP server-side clamps** (`backlog.md:1991`) match the Realizer's trust boundary (`Realizer.h:120-123`) — same ±12 rule, one place.
- **Hold-to-Compare today** is level-fair and well-defined (EQ off = identity + 0 dB gain, `Realizer.mm:410`; `TrackLoudnessGain.cpp:106-109`); it only becomes ambiguous once layers exist (F9).

---

## 5. Sources opened

Repository (this checkout): `docs/product/roadmap.md`, `docs/sprints/sprint-plan.md`, `docs/product/backlog.md` (§§ EP-TONAL, EP-ADAPT, EP-DEVICE, EP-SPAT, EP-PROFILE, EP-PERCEPTUAL, EP-REIMAGINE, post-R1 fix pool, EP-PLAYENGINE, spikes, open items), `docs/architecture/architecture.md` (§0, §2.5, §4, §5, §7–§11), `docs/design/adaptive-tone/README.md`, `docs/design/eq-lens/README.md`, `docs/product/requirements.md` (FR-SPAT-03, FR-TONAL-02/03/05/07, FR-ADAPT-05), `docs/product/known-issues.md` (KI-SND-01…05, KI-MC-01/02, KI-EQ-01…03, KI-PURE-01), `docs/reviews/2026-10-council/working/stage5-architect.md` (§E, §4.3–4.6), `panel-p1-eq.md`, `panel-p2-loudness-breaker.md`, `panel-p2-loudness-sota.md`, `engine-research.md` §5, `arch.md` (ARCH-7, W5, S12–S14 rows), `docs/sprints/05-sprint-5b-s4-binaural-design.md` §1, `docs/sprints/qw1-quick-win-differentiators-design.md` (intensity/crossfeed).
Code: `Sources/AudioDSP/DSPKernel.cpp`, `include/DSPKernel.h`, `include/TargetState.h`, `include/AudioConstants.h`, `EQ/EQModule.h`, `EQ/GraphicEQBands.h`, `EQ/GraphicEQDesigner.h`, `Loudness/LoudnessModule.{h,cpp}`, `Loudness/TrackLoudnessGain.{h,cpp}`, `Loudness/TrackLoudnessProfile.h`, `Limiting/LimiterModule.h`, `Limiting/OutputCeiling.h`, `Spatial/CrossfeedModule.{h,cpp}`, `Spatial/SpatialRenderKernel.{h,cpp}`, `Spatial/BRIRModule.h`, `Clarity/ClarityModule.h`, `AudioEngine/Realizer.h`, `AudioEngine/Realizer.mm` (grep), `AudioEngine/AUAudioUnit.mm:145-175`; `Sources/EQEditKit/MasterGainLaw.swift`, `MasterGainOnPure.swift:1-120`, `EQOutputPin.swift`, `EQOutputKey.swift`, `EQStore.swift`, `EQCurve.swift`, `EQBands.swift`, `EQSession.swift:150-182`, `EQAudibleState.swift`; `Sources/TrackLoudnessKit/TrackLoudnessAnalyzer.swift` (grep); `Sources/AudioFormatKit/MultichannelFormat.swift:40-105`; `Sources/AdaptiveSound/AudioEngineBridge+Graph.swift:1-140`, `+MasterGain.swift`, `+IntensityControl.swift`, `+ChannelLayout.swift:40-80`, `AudioViewModel.swift` (grep + :185-245), `AudioViewModel+MasterGain.swift`, `AudioViewModel+Devices.swift`, `SignalPathInfo.swift:95-125`, `UI/NowPlaying/InspectorColumn.swift:84-185`, `UI/EQ/EQCompareButton.swift` (grep), `UI/EQ/EQGraphStrip.swift` (grep); `Sources/SettingsKit/ListeningSettings.swift` (grep).
Web: Apple — AVAudioMixing (https://developer.apple.com/documentation/avfaudio/avaudiomixing) and AVAudioMixing.volume (https://developer.apple.com/documentation/avfaudio/avaudiomixing/volume); PipeWire parametric-equalizer man page for the AutoEq `ParametricEQ.txt` layout (https://man.archlinux.org/man/extra/libpipewire/libpipewire-module-parametric-equalizer.7.en); AutoEq fork README (https://github.com/Blah029/AutoEq). ITU-R BS.775-4 and BS.1770-5 figures are taken from the council's P2 reports, which opened the PDFs; I did not re-open them. ISO 226:2023 was not opened (no finding depends on the contour values).
