# The 2026-10 product council: report

**Dates:** 2026-10-13 to 2026-10-14. **Code reviewed:** `main` at `7d7c2cd` (the R1 release PR), re-baselined at
`9df49e3` (R1 plus its blocker fixes, PRs #88 and #89). **Decided by:** the founder, on 2026-10-14.
**Audience:** the founder and future contributors. The forward plan it produced lives in the
[roadmap](../../product/roadmap.md#the-post-r1-plan-council-2026-10-14), the
[sprint plan](../../sprints/sprint-plan.md#after-r1-the-council-re-plan-2026-10-14) and the
[backlog](../../product/backlog.md#post-r1-fix-pool-new--2026-10-13). This page explains why.

---

## 1. In one minute

**Recommendation, now adopted: fix what the founder hears first (R1.1), then build our own playback engine in a sprint
of its own, then ship the R2 features, each carrying only the restructuring it needs.**

- **R1 is a real library player.** Library, browse, playlists, queue, gapless, media keys, an honest 31-point EQ and
  the device-loss behaviour all work end to end. The C++ DSP core, the pure decision kits and the library store are
  well designed.
- **The default experience is not yet what the product promises.** A fresh launch plays *processed* sound, Master Gain
  comes back at its loudest, dragging the scrubber to the end of a 44.1 kHz track stops the music for good, and the
  Enhanced path rolls off the top octave. Each is a small fix.
- **The design debt sits in the app shell, not the DSP.** One play state machine is split between the view model and
  the bridge; there are two playback engines; threading rules are conventions; commands and engine events have no
  vocabulary. These block R2 and the MCP agent surface, not R1.1.
- **The gates guard the wrong layer.** Most CI time goes to C++ sanitizer runs of a stable DSP kernel. All 13 Sprint G
  blockers and the disconnect freeze were in Swift app logic, concurrency or real-hardware behaviour, where several
  tests checked copies of the code.

**Numbers:** about 230 raw findings were merged into **94 open rows** (8 structural, 60 significant, 25 local, and one
pointer to the 44 logged known issues), **9 rows fixed in R1**, and **20 claims refuted or corrected**. The full
register is [`working/stage5-architect.md` §1](working/stage5-architect.md#1-finding-register).

---

## 2. Why the council met, and its charter

R1 (v1.0.0-alpha) was about to ship after a long UX sweep (S10.7–S10.8), and R2 was next on the plan. Before
committing to R2, the founder asked for an honest, independent look at the product, the process, the architecture,
the roadmap and the code. The [charter](working/CHARTER.md) was agreed on 2026-10-13. Its rules:

- **The code is the truth.** Documents describe the code. Where a document and the code disagree and the code looks
  like a bug, the document describes the code *and* the gap becomes a finding. A requirement is never quietly rewritten
  to match broken code.
- **Review only.** No reviewer edited `Sources/` or `Tests/`. Code changes wait for the founder's decisions. (The R1
  blockers the council found were fixed in separate PRs, #88 and #89, by the normal delivery loop.)
- **Six criteria, a design-maturity bar, not "it passes lint":**
  1. architectural elegance, not brittle and not tactical;
  2. design patterns where required, and no pattern for its own sake;
  3. no duplicated code or duplicated capability;
  4. algorithmic correctness, checked against a reference and proven by tests;
  5. state of the art, compared with opened sources;
  6. maturity: testability, explicit error handling, no "trust me" escapes.
- **Outputs:** a ranked finding register with root causes; a short decision list for the founder; documents reconciled
  to the code; and this report, with the re-planned roadmap, as **one docs PR**.

---

## 3. Method

### 3.1 The six stages

| Stage | What it did | Papers |
|---|---|---|
| 1. Map and reconcile | A shared, factual codebase map (files, owners, the algorithm inventory). In parallel: docs ↔ code reconciliation (product docs, roadmap / planning / architecture docs), a product review (PM + BA), a process review and a review of the coordinator's memory. | [00-map](working/00-map.md), [docs-product](working/docs-product.md), [docs-arch](working/docs-arch.md), [product](working/product.md), [process](working/process.md) |
| 2. Architecture and areas | A macro architecture review, plus six area reviews against all six criteria. | [arch](working/arch.md), [area-viewmodels](working/area-viewmodels.md), [area-bridge](working/area-bridge.md), [area-dsp-cpp](working/area-dsp-cpp.md), [area-library](working/area-library.md), [area-ui](working/area-ui.md), [area-build-test](working/area-build-test.md) |
| 3. Duplication | A token-shingle clone detector (written for the council; no offline detector was available) plus a semantic pass for "two ways of doing the same job". | [duplication](working/duplication.md) |
| 4. Algorithm panels | Six adversarial panels, eight reports. A *breaker* built its own oracle or prototype and drove the real code; a *state-of-the-art* panelist checked against the literature and other players' opened sources. P2 and P3 had one of each, working independently. | [P1 EQ](working/panel-p1-eq.md), [P2 breaker](working/panel-p2-loudness-breaker.md) / [P2 SOTA](working/panel-p2-loudness-sota.md), [P3 breaker](working/panel-p3-path-breaker.md) / [P3 SOTA](working/panel-p3-path-sota.md), [P4 queue](working/panel-p4-queue.md), [P5a library](working/panel-p5a-library.md), [P5b browse / device / tokens](working/panel-p5b-browse-device-tokens.md) |
| 5. Cross-examination | The architect merged every report into one register, found the shared roots and resolved conflicts. A pre-mortem challenger ("the fool") attacked the council's own conclusions; the architect answered each point. | [stage5-architect](working/stage5-architect.md), [stage5-fool](working/stage5-fool.md) |
| 6. Synthesis | This report, the founder's decisions, the re-planned roadmap, and the docs PR. Two research pieces the founder asked for fed it: the engine survey and the virtual-DAC plan. | [engine-research](working/engine-research.md), [virtual-dac-plan](working/virtual-dac-plan.md) |

R1's blockers were found in Stages 2–4, while R1 was still untagged. They were fixed in PR #88, and each fix was
designed and then broken again by an independent breaker ([R1 fix papers](#r1-fix-designs-and-break-it-reports)).

### 3.2 The evidence standard

- **Every claim names file:line** in the code, with a short quote.
- **State of the art means opened sources**, not memory: Apple's SDK headers, SFBAudioEngine, Cog, VLC, mpv, JUCE,
  GRDB's documentation, the ITU / EBU standards and the papers behind them. Third-party sources are linked, not copied
  into this repo.
- **Algorithm verdicts come from real-code experiments.** Panelists built and ran harnesses in their own worktrees
  against the real `Sources/`, with their own oracles (Python / numpy, small C++ and Swift harnesses). No reviewer
  launched the app or played audio. Each verdict is one of PROVEN-CORRECT, CORRECT-UNPROVEN, DEFECT or QUESTIONABLE.
- **Re-baselined at the current commit.** Stages 1–4 read `7d7c2cd`. Stage 5 re-checked every STRUCTURAL rating and every
  "fixed in R1" claim at `9df49e3` (marked ✓ in the register), because R1's own fixes had moved the code.
- **Platform claims were re-probed.** One premise many reports shared ("Ogg / Opus need FFmpeg") was false on macOS 26:
  `AVAudioFile` opens them natively (R-19). The probe was re-run before the finding changed.

---

## 4. Results

### 4.1 Counts

| | Count |
|---|---|
| Raw findings from all reports | about 230 |
| **Open rows in the register** | **94**: 8 STRUCTURAL · 60 SIGNIFICANT · 25 LOCAL · 1 pointer (C-89, the 44 logged known issues) |
| Fixed in R1 (PRs #88, #89) | 9 rows (C-90 … C-98) |
| Refuted or corrected claims | 20 (R-1 … R-20) |
| Algorithm verdicts (8 panel reports; P2's and P3's rows judged twice, independently) | 259: 117 proven-correct · 38 correct-but-unproven · 27 questionable · 77 defects |

The eight STRUCTURAL rows are C-01 (one play state machine, two owners), C-02 (isolation by convention), C-03 (the
28k-line app monolith), C-05 (no command catalogue), C-06 (no engine event channel), C-07 (two playback engines), C-38
(a session-long leveller on the default path) and C-80 (tests that run on drifted copies of the code).

### 4.2 Verdict per criterion

| # | Criterion | Verdict | Why |
|---|---|---|---|
| 1 | Elegance | **Mixed: a strong core, a brittle shell.** | Good: the pure-C ABI over C++, the Realizer → triple buffer → kernel control plane, the pure decision kits (`OutputDevicePolicy`, `EQSession`, `FolderWalkSchedule`, `MasterGainLaw`), the store's open path. Brittle: the transport split across two owners with their own epochs (C-01), isolation by comment (C-02), god objects split into extension files to satisfy lint (C-11). |
| 2 | Patterns where required | **Missing exactly where they matter most.** | No transport state machine (C-01), no command pattern (C-05), no event channel (C-06), no reactive reads (C-58). Where patterns exist they are right: a decoder strategy, a facts → policy split, a repository-shaped store facade. The council's own first plan over-reached (pattern waves); the pre-mortem cut it back. |
| 3 | Duplication | **Little copy-paste; much "two ways to do one job".** | About 730 verbatim duplicate lines outside the test harnesses. The real duplication is semantic: two playback engines (C-07), four engine test doubles (C-80), three search semantics (C-61), four device classifications (C-30), six list scaffolds (C-70). Correct single owners exist, and older call sites bypass them (RC-8). 12 of 17 semantic findings had already diverged. |
| 4 | Algorithmic correctness | **The EQ is proven; the default sound chain, the Enhanced seams and the queue are not.** | P1 proved 38 of its 45 rows (the EQ, track loudness and the EQ session) against an independent oracle; its four defects are in the spectrum analyser. Defects cluster in the Enhanced seams and SRC (C-21–C-26), the loudness / limiter / crossfeed / blend chain (C-38–C-42), the transport and queue (C-14–C-17) and library identity and search (C-57, C-61). Several tests *pinned* a defect as correct (C-85). |
| 5 | State of the art | **Current in the DSP control plane and the store; behind in the Enhanced engine and in observability.** | Behind: the Normal-quality SRC (C-26), scheduling from `.dataPlayedBack` (C-21), a limiter whose dual release is dead code (C-39), a crossfeed that is not bs2b (C-42), no `os.Logger` (C-10), hand-rolled GCD where Swift 6 offers `Mutex` and actors (C-02). Current: the wait-free triple buffer, GRDB 7 usage, the EXPLAIN-QUERY-PLAN gate, the release provenance. |
| 6 | Maturity | **Strong gates for the DSP kernel; weak where the bugs were.** | Good: the C++ oracle suite, the drift guard that compiles real sources, tool pins, the plant-a-leak self-test. Weak: about 61 tests on mirrors (C-80), five harness cultures (C-81), wall-clock timing tests (C-84), 8 `@unchecked Sendable` types and 27 `@preconcurrency` imports (C-02), no diagnostics (C-10). |

### 4.3 The nine shared roots

| Root | In one line | Main rows |
|---|---|---|
| RC-1 | **The transport has two owners and no identity.** The engine reports anonymous counts, epochs filter samples not commands, and there is no pause primitive, so on Pure a pause is a device teardown. | C-01, C-14, C-15, C-17, C-100 |
| RC-2 | **Two engines; Enhanced hands its queue to `AVAudioPlayerNode`.** Position, seams, end and seek are re-derived from completion callbacks. Pure already has the right model. | C-07, C-21–C-26 |
| RC-3 | **Isolation and layering are conventions inside a monolith.** | C-02, C-03, C-11, C-27 |
| RC-4 | **No command / state / event vocabulary.** It is what EP-MCP collides with first. | C-05, C-06, C-12, C-58 |
| RC-5 | **A path is identity, and user data has one copy.** | C-04, C-54–C-57, C-101 |
| RC-6 | **The Realizer owns the EQ but not the rest of what is audible.** The default is processed. It is what S12–S14 collide with first. | C-09, C-38–C-50 |
| RC-7 | **Tests test copies and pin today's output; time is ambient.** It is why audible defects passed green gates. | C-80–C-85 |
| RC-8 | **Primitives get extracted, but older sites never move onto them.** | C-18, C-30, C-63, C-70, C-75 |
| RC-9 | **Operating a public release was never designed.** No logger, no crash reports, no licence file, no backup, a runtime-loaded C demuxer, settings that come back louder. | C-10, C-99, C-101, C-102, C-103 |

RC-1 and RC-2 reinforce each other: the view model owns pause *because* the Enhanced engine cannot express it. That is
why the founder's engine decision (FD-4) and the transport rework (W2) are linked in the plan.

### 4.4 The top findings by user impact

| What the user meets | Row | Where it is fixed |
|---|---|---|
| Dragging the scrubber to the end of any non-48 kHz track (most CD rips) stops the music for good | C-25 | R1.1-A |
| Every fresh launch plays processed sound: Intensity 20 % switches on a session-long leveller, a +2 dB blend and the limiter | C-41, C-38–C-40 | R1.1-A (FD-2) |
| Master Gain comes back at its loudest after a relaunch: a hearing-safety issue for in-ear listeners | C-102 | R1.1-A (FD-2) |
| "Remove Missing" deletes playlist entries whose drive is merely unplugged; removing and re-adding a folder resets your history | KI-LIB-01, C-54 | R1.1-A; "Use this drive" in R1.1-B |
| A 5.1 / 7.1 track on headphones loses its centre (the vocal), LFE and surrounds; ALAC / AAC 5.1 plays its centre on the left | C-43, C-44 | R1.1-B (FD-9) |
| The Enhanced path rolls the treble off (−8.25 dB at 20 kHz) and aliases 192 kHz files | C-26 | R1.1-A |
| Gaps, clicks and dropped channels at Enhanced track joins; the title and B's gain switch early | C-21–C-24 | Engine sprint |
| "Playing" over a silent engine; a dropped Pause; a song queued under the current one never plays | C-15, C-17 | R1.1-A |
| The title and play count name a song other than the one you hear, in narrow windows | C-14 | Engine sprint |
| Crossfeed hollows out vocals (a −4 to −6 dB notch near 1 kHz); the limiter ducks the music for about a second after one snare hit | C-42, C-39 | R1.1-A |
| FFmpeg parses every FLAC / Ogg / Opus file first, from a user-writable path, in an unsandboxed process | C-99 | R1.1-A (opt-in, FD-3) |
| Shuffle repeats songs and, with Repeat off, never ends | C-16 | R1.1-B |
| A Sinhala search returns the wrong words; NFD text can't be found | C-61 | R1.1-A (tokenizer + NFC) |
| On Pure, every pause and resume switches the DAC's rate twice | C-100 | Parked until a USB DAC (FD-5) |

### 4.5 What R1 fixed

The council found R1 blockers before the tag. They were fixed in **PR #88**, and **PR #89** made the new seam-window
tests deterministic. Each fix was designed, implemented, then broken again by an independent breaker.

| Row | What was wrong |
|---|---|
| C-92 | The render gate's close could starve (it failed main's CI) and teardown had a use-after-free window |
| C-97 | The library swept songs after an incomplete walk, after a walk of another drive with the same name, and from unbound roots: user data loss. **Narrowed, not closed** (C-54–C-56) |
| C-90, C-91 | Pure played endless silence on a channel mismatch; packed 24-bit overran a buffer; NaN / Inf were not scrubbed |
| C-93, C-94, C-98 | Pure played the old next track after an edit (D41), and two related arm races |
| C-95 | Play Next during a start's prime played the old pick |
| C-96 | Playback did not return to the headphones the user chose when they reconnected (N92) |

R1 shipped as **v1.0.0-alpha** on 2026-10-14: [GitHub release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha),
[release notes](../../releases/v1.0.0-alpha.md) (corrected in c95e2c6 to list surround-on-stereo and Remove Missing,
and to stop claiming Apple's Liquid Glass).

---

## 5. The founder's decisions (2026-10-14)

The council brought ten decisions, each with a recommendation, and the founder decided all ten. The last three lines
record how they apply. Where a decision differs from the council's recommendation, the decision wins, and the docs say
so.

| # | Decision | Rationale (short) |
|---|---|---|
| **FD-1** | **R1.1 fixes first, then features.** No standalone refactor waves: each feature carries only the structural slice it needs, under a 2-week cap, finish-or-revert. | The project's estimates have run far over (S10.8: 3 → ~45 SP; Sprint G: 4–5 h → ~18 h). A half-done strangler with two live owners is worse than today. A feature gives each slice an acceptance test. |
| **FD-2** | **A faithful default, and remember the listener's settings.** Intensity 0, leveling off, EQ off at a fresh launch. Remember Pure, Master Gain (never restored louder than it was left), crossfeed, shuffle / repeat and the chosen device. Hide Intensity until its effects are real. Leveling becomes its own setting (album / track gain from the existing analysis), off by default. | "Faithful > processed" is the founder's own rule. Intensity's wet stages are stubs today, so the control changes loudness, not sound. Master Gain restoring louder is a hearing-safety issue. |
| **FD-3** | **FFmpeg stays, as an opt-in, off by default.** Harden its load path; the metadata scan uses it only when it is on. *(The council recommended deleting it.)* | Format breadth (WavPack, APE, files Apple can't open) stays available to those who want it; off by default removes the attack surface for everyone else. |
| **FD-4** | **A dedicated Engine sprint, after R1.1 and before R2.** Study SFBAudioEngine at code level, then build our own engine as its own module behind a clean interface, compare the two at code level and by measurement, then decide. R1.1 keeps only the user-facing engine fixes (C-25, C-26). *(The council recommended a one-week SFB adoption spike instead.)* | The founder's words: "understand SFBAudioEngine (clone it and analyse), then build our own with that knowledge; we will compare at the code level which is better; it should be built as a different module/component which gets plugged in with a clean interface; find areas we can improve during the discovery phase; a sprint of its own." |
| **FD-5** | **No USB DAC for about two weeks.** The virtual-DAC rig goes on the back burner until the founder brings a hardware rig (HDMI cables plus a device). The USB-DAC check is still owed. | Pure's integer path has never run on real hardware. That stays a known gap, so the plan schedules no change to Pure's output path before the check (C-100 and C-31 are parked with it). |
| **FD-6** | **Merging stays as today:** the founder merges by hand, with no required checks. The council's "CI is the only gate" rule (C-83, rule 5) was **not adopted**. | The founder's call. The residual risk (merges and tags on an unfinished or red CI run) stays a known process risk; see §7. |
| **FD-7** | **The licence is Apache-2.0.** The LICENSE file itself, Developer ID and notarization, diagnostics (`os.Logger`, MetricKit), playlist export and backup, and the clean-Mac first run are **deferred** to a later "release readiness" item. | "Focus on features." The licence choice is made now; the paperwork lands when a wider release is called. |
| **FD-8** | **EP-MCP waits** for the full playback-ownership rework (W2) and the command layer, in R2 or later. *(The council recommended an early read-only spike.)* | An agent is a fast client, and today's transport breaks under single-client interleavings. One command layer, built once. |
| **FD-9** | **Surround on stereo uses the standard ITU-R BS.775 fold-down,** after the channel-order fix and with a ceiling after it. | Dropping four channels is worse than a standard matrix. It sits at the device boundary and is replaced in the same slot by the S18 binaural render. |
| **FD-10** | **A 20k-song target under today's rules:** no `missing_since` tombstone, no 100k performance gate. | Today's design is benchmarked at 10k–20k songs; the tombstone and an incremental reconcile wait for a larger target. KI-LIB-01 is still fixed in R1.1, without a tombstone. |
| Engine | **The Engine sprint replaces the SFB spike** (see FD-4), with three phases: discovery, build, then compare and decide, using the 11 checks in [engine-research §5](working/engine-research.md#5-recommendation-and-spike-plan-refines-stage5-architect-45). | |
| DAC | **The virtual-DAC rig is parked** ([plan](working/virtual-dac-plan.md)) together with the USB-DAC check (FD-5). | |
| Drive | **"Use this drive"** (LIB-VOL-1, C-54) comes "later, via the council list": R1.1-B. | |

**Defaults that stand unless the founder objects.** The architect's "decided by the plan" list
([stage5-architect §5](working/stage5-architect.md#5-founder-decisions-10)) still applies where no decision above
changed it. In short:
- shuffle becomes a permutation with history;
- a format-changing join is an honest short gap, and bit depth no longer breaks Pure gapless;
- crossfeed follows the bs2b ladder and can be enabled on any output;
- the EQ below 44.1 kHz uses a reduced band set;
- Pure shows its reason, and says "not bit-perfect" when the device's depth is lower;
- one search rule and a global ⌘F;
- loose-file Open… and drop;
- count the `.cue` files before S11;
- a single click selects and a double-click plays, everywhere;
- retire the test mirrors, and give `VerifyLibraryStore` `--filter` and continue-on-failure;
- delete dead C++ and placeholders, with no new lint fitness gate;
- at most 6 concurrent agents, and no new ceremonies.

The decisions changed four of these defaults:
- "SRC: Mastering now; the in-house converter only if SFB fails": R1.1 still takes the Mastering converter, but the
  Engine sprint builds our own engine regardless and compares it with SFB;
- the MCP spike is dropped (FD-8);
- the "until rule 5 holds" condition on ceremonies never fires (FD-6), so "no new ceremonies" simply stands;
- "Love + smart lists in R1.1-B" is not in the founder's R1.1-B list, so smart lists stay the post-R1 fast-follow
  they already were.

---

## 6. The plan

Detail and links per item: [roadmap](../../product/roadmap.md#the-post-r1-plan-council-2026-10-14) ·
[sprint plan](../../sprints/sprint-plan.md#after-r1-the-council-re-plan-2026-10-14) ·
[backlog](../../product/backlog.md#post-r1-fix-pool-new--2026-10-13).

```
R1 (shipped) → R1.1-A → R1.1-B → Engine sprint → R2: S14-lite → S12 → S13 → S11-lite → R3 (S15–S17, S18)
                                   (dogfood R1.1)      each R2 sprint carries its own structural slice
EP-MCP: after W2 + the command layer (R2 or later)
```

1. **R1.1-A, "faithful, durable, honest" (at most 2 weeks, small items).**
   - Faithful default and safe settings (FD-2): C-41, C-102, KI-SET-01, DEV-1.
   - The two engine fixes the user hears (FD-4): seek-to-end ends now (C-25); Apple's Mastering-quality converter with
     a passband / stopband gate (C-26).
   - Transport correctness: C-15 and C-17.
   - Audible DSP: C-39, C-42, C-46 and C-50. C-40 waits until Intensity returns.
   - Pure honesty: the reason shown in the UI (C-34, C-33).
   - FFmpeg opt-in (FD-3), plus scanning `.opus` / `.oga`.
   - Library and search: KI-LIB-01, C-55, C-58, and C-61's tokenizer + NFC.
   - UI: C-53, C-52 and C-51.
   - Hygiene: C-86, C-87 and C-88.
2. **R1.1-B, the decided medium items (at most 2 weeks).**
   - BS.775 fold-down (FD-9; C-43, C-44, C-45).
   - Shuffle as a permutation (C-16).
   - One search rule and ⌘F (C-61).
   - Atomic queue restore (C-65).
   - Loose files (C-69).
   - "Use this drive" (C-54).
   - The leveling setting (FD-2, C-38).
3. **The Engine sprint (FD-4).** Discovery → our own Enhanced engine as its own SwiftPM module behind a clean interface,
   designed so Pure's decode can share it later → a code-level and measured comparison with SFBAudioEngine on the 11
   checks → the founder decides. It carries the gapless and scheduling internals:
   - C-21, C-22, C-23, C-24;
   - C-14 / F1 (seam identity);
   - the rest of the former W4: C-07, C-08, C-28, C-36, C-37, C-48, and C-04's bounded-source half.
4. **R2, in the product's order:**
   - S14-lite, with a taste-only loudness neutrality (W5-min);
   - S12, with `EQProgram`;
   - S13;
   - S11-lite: CUE only if `.cue` files exist.
5. **Deferred:** release readiness (FD-7). **Parked:** the USB-DAC check and the virtual-DAC rig (FD-5). **Not
   adopted:** the CI rule (FD-6), the tombstone and the 100k gate (FD-10).

**W2, one owner for playback.** W2 is the reducer that gives the transport one owner, plus the command layer and the
engine event channel (C-01, C-05, C-06, C-15 in full, C-18, C-13).
- **Funded by** EP-MCP (FD-8), S14's adaptive half (it needs engine events) or crossfade.
- **Triggered by** any wrong-song or silent-playing bug reported after R1.1's transport fixes. That bug is W2's start
  signal, not another patch.
- The Engine sprint delivers the engine half (seam events that carry the track's identity, one seek, one end flag).
  So W2 is expected to shrink to the queue / transport reducer and the command layer.

---

## 7. Process lessons

1. **Gate by risk, not by history.** About 77 % of the 87-minute CI run is C++ sanitizer time on a stable kernel. All
   13 Sprint G blockers and the disconnect freeze were in Swift app logic, concurrency and real-hardware behaviour.
2. **Test the real code.** The playback view model was tested through a hand-kept mirror that had drifted. R1 started
   the fix (`AdaptiveSoundTests` imports the app); R1.1's transport fixes land with tests on the shipped view model.
3. **Independent oracles beat golden hashes.** Several tests pinned a defect as correct (the +2 dB blend, the 1.41
   back-surround weight, the SRC check that printed −7 dB and said PASS). A test must compare with something the code
   did not produce.
4. **Walk the product's own default.** The reports measured mechanisms well. They under-ranked user paths through those
   mechanisms (the default Intensity, seek-to-end, Master Gain at launch) until the pre-mortem walked them.
5. **Re-check platform facts and the current commit.** The Ogg / Opus premise was true once and false on macOS 26; R1's
   fixes made parts of the Stage 1–4 register stale within a day.
6. **Keep decisions few, each with a recommendation.** About 80 open questions across the reports became 10 decisions,
   each with the recommended option first, and the founder decided all ten.
7. **Structural work rides with features.** Capped, finish-or-revert, never two live owners at a sprint boundary
   (FD-1). The one exception is the Engine sprint, which the founder made a sprint of its own.
8. **Evidence must be durable.** The breakers' red tests and harnesses belong in the repo as regression tests, and the
   council's papers are committed in this PR (our own probes and harnesses only; third-party sources are linked).
9. **Timing tests need a stress run under load.** Five or more timing flakes in a week, one of them failing 13 of 20 runs
   under load, came from tests that assumed the scheduler.
10. **Merge policy is the founder's call (FD-6).** Without a required check, protecting `main` rests on habits the council
    recommends: read the gate's real exit code, wait for the main run before tagging, and quarantine a flaky test the day
    it flakes.

---

## 8. Conflicts with the existing docs, and how they are annotated

The decisions changed some earlier positions. The old text is annotated, not deleted.

| Earlier position | Changed by | Annotated in |
|---|---|---|
| LD-17 / FR-TONAL-05: "transparent LUFS normalisation" is part of the *default* chain | FD-2: leveling off by default; a named setting | [requirements.md](../../product/requirements.md) LD-17, FR-TONAL-05; backlog US-ENG-09 |
| FR-REIMAGINE-04 / US-RMG-01: the Intensity knob is shown, default 20 % | FD-2: default 0, hidden until S17 | requirements matrix; backlog US-RMG-01 |
| LD-9 / PRD §6 / US-REL-02: the licence choice is deferred | FD-7: Apache-2.0; only the file is deferred | requirements LD-9; PRD LD-9 and §6; backlog US-REL-02; root README |
| US-R1F-08: the recommended interim fold is Apple's `AVAudioEnvironmentNode` | FD-9: BS.775 (option b). This also keeps FR-SPAT-01's "Apple's spatial nodes are not used" rule | backlog US-R1F-08; known-issues KI-MC-01 |
| The "no naive downmix" rule | FD-9: a standard matrix at the device boundary is accepted until S18 replaces it in the same slot | roadmap R1.1-B; architecture.md §2.5; known-issues KI-MC-01 |
| Stage 5: "C-35 (FFmpeg seek) becomes moot once FFmpeg is deleted" | FD-3 keeps FFmpeg, so C-35 is live and rides with the opt-in work | backlog US-R1F-16 |
| Stage 5: "the SFB spike decides adopt vs in-house" | FD-4: build our own and compare | roadmap; backlog EP-PLAYENGINE |
| EP-MCP: "placement set by the council, after the command-layer refactor wave"; an early spike | FD-8: after W2 + the command layer, R2 or later; no early spike | roadmap, sprint plan, backlog EP-MCP, requirements FR-AGENT-01 |
| S11 → S12 → S13 → S14 order; R2 "after S14" | FD-1: S14-lite → S12 → S13 → S11-lite; R2 after S11-lite | sprint plan §3 and §7; roadmap |
| US-R1F-02: "candidate for S11" | FD-4: the Engine sprint | backlog |
| The playlist-folder data layer "stays dormant (re-enabling is free)" | Council default: delete the dormant data-access code the next time the store is touched (C-62); the tables stay | roadmap "Deferred"; sprint plan §Status |
| Playlist export (M3U) "deprioritized 2026-07-14" | FD-7: export returns as data safety inside release readiness; import stays deprioritized | roadmap "Deferred"; backlog US-REL-04 |
| NFR-QUAL-04 / US-ENG-06: SRC "Delivered", proven by `SRCQualityMeasure` | The council measured −8.25 dB at 20 kHz and −21 dB aliases, and the check passes a −7 dB error (C-26, R-6) | requirements matrix (status → Partial); backlog US-ENG-06 |
| CON-12 (permissive-only shipping) vs adopting SFB | SFB's mpg123, libsndfile, lame and tta-cpp are LGPL; adopting SFB as-is would need CON-12 amended, or those decoders left out | backlog US-PE-03 (a decide-phase check); requirements CON-12 |

---

## 9. Index of the working papers

All are in [`working/`](working/). They are evidence and rationale, not live status: whether a fix landed is in the
code and git. **The full finding register is [`working/stage5-architect.md` §1](working/stage5-architect.md#1-finding-register)**;
the roots are §2, the conflicts resolved §3, the slice catalogue §4.3, and the pre-mortem response §6.

**Charter and briefs:**
- [CHARTER.md](working/CHARTER.md): purpose, ground truth, the six criteria, the stages, the rules.
- [REVIEWER-BRIEF.md](working/REVIEWER-BRIEF.md): the Stage 2 reviewer brief and finding format.
- [PANEL-BRIEF.md](working/PANEL-BRIEF.md): the Stage 4 adversarial panel brief and the verdict scale.

**Stage 1, map and reconciliation:**
- [00-map.md](working/00-map.md): the shared codebase map, including the algorithm inventory (D- and N-rows).
- [docs-product.md](working/docs-product.md): the product docs reconciled to the code.
- [docs-arch.md](working/docs-arch.md): the roadmap, planning and architecture docs reconciled to the code.
- [product.md](working/product.md): the PM + BA assessment of R1, R2 and the thesis.
- [process.md](working/process.md): the sprint and process review, S10.8 → R1.

**Stage 2, architecture and areas:**
- [arch.md](working/arch.md): the macro architecture review (ARCH-1…12).
- [area-viewmodels.md](working/area-viewmodels.md): view models and app state (VM-1…13).
- [area-bridge.md](working/area-bridge.md): the audio engine bridge and its concurrency (BR-1…16).
- [area-dsp-cpp.md](working/area-dsp-cpp.md): the C / C++ / Objective-C++ DSP layer (DSP-01…17).
- [area-library.md](working/area-library.md): store, scan, browse kit, queue mirror (LIB-01…17).
- [area-ui.md](working/area-ui.md): SwiftUI views and the design system (UI-1…13).
- [area-build-test.md](working/area-build-test.md): test architecture, build and CI (BT-1…12).

**Stage 3:**
- [duplication.md](working/duplication.md): the tool-assisted clone pass and the semantic duplication pass (DUP-1…17).

**Stage 4, algorithm panels:**
- [panel-p1-eq.md](working/panel-p1-eq.md): the EQ, track loudness, spectrum and EQ session.
- [panel-p2-loudness-breaker.md](working/panel-p2-loudness-breaker.md) and
  [panel-p2-loudness-sota.md](working/panel-p2-loudness-sota.md): loudness, true peak, limiter, crossfeed, spatial,
  blend.
- [panel-p3-path-breaker.md](working/panel-p3-path-breaker.md) and
  [panel-p3-path-sota.md](working/panel-p3-path-sota.md): the signal path, gapless seams, Pure output, real-time
  infrastructure.
- [panel-p4-queue.md](working/panel-p4-queue.md): queue, transport and play statistics, and the D41 adjudication.
- [panel-p5a-library.md](working/panel-p5a-library.md): library scan, identity, store, search, sort, migration.
- [panel-p5b-browse-device-tokens.md](working/panel-p5b-browse-device-tokens.md): browse logic, device policy, design
  tokens.

<a id="r1-fix-designs-and-break-it-reports"></a>**R1 fix designs and break-it reports (PR #88):**
- [d41-design.md](working/d41-design.md) and [p4-d41-design-review.md](working/p4-d41-design-review.md): the
  "what plays next" contract and its adversarial review.
- [p3a-d41-cpp-break.md](working/p3a-d41-cpp-break.md) and [p4-d41-impl-break.md](working/p4-d41-impl-break.md):
  breaking the implemented D41 fix.
- [p3a-purefix-break.md](working/p3a-purefix-break.md): breaking the Pure safety fix.
- [panel-p3-rendergate-fix-check.md](working/panel-p3-rendergate-fix-check.md): the render-gate liveness fix.
- [p5a-libfix-break.md](working/p5a-libfix-break.md) and [p5a-libfix-recheck.md](working/p5a-libfix-recheck.md): the
  library sweep-evidence fix.
- [p5b-reconnect-break.md](working/p5b-reconnect-break.md) and
  [p5b-reconnect-recheck.md](working/p5b-reconnect-recheck.md): the device-reconnect fix (N92).

**Stage 5, cross-examination:**
- [stage5-architect.md](working/stage5-architect.md): the register, the roots, the conflicts, the plan, FD-1…10.
- [stage5-fool.md](working/stage5-fool.md): the pre-mortem challenger.

**Research for the founder's decisions:**
- [engine-research.md](working/engine-research.md): the engine survey (SFBAudioEngine, an own pull engine, BASS and
  others), the AVAudioEngine SRC measurements, and the 11 checks (P1–P11).
- [virtual-dac-plan.md](working/virtual-dac-plan.md): verifying Pure without a USB DAC (parked, FD-5).

**Experiments and tools:**
- [`working/experiments/`](working/experiments/): the panels' and reviewers' own probes, harnesses and logs, one folder
  per author (`exp-p1`, `exp-p4`, `engine-research/probes`, `fool-ogg`, …).
- [`working/tools/`](working/tools/): the live-check helpers used in the Sprint G passes (accessibility probes, CGEvent
  drivers, device mute, a hang scanner).

---

**Last updated:** 2026-10-14 (Stage 6: report and re-plan, after the founder's decisions).
