# Audio Quality Validation Strategy

**Purpose:** Define comprehensive validation gates for the DSP core (EQ / loudness / limiter / clarity). *(Historical note: authored for the pre-pivot "Phase 1c / Sprints 4–6" framing; the gate definitions below remain current — for the current phase map see [../product/roadmap.md](../product/roadmap.md) and [../sprints/sprint-plan.md](../sprints/sprint-plan.md).)*  
**Scope:** Unit tests, integration tests, listening panels, regression gates, soak tests  
**Approval:** QA Expert + Audio DSP + Project Lead  
**Maintenance:** Update per sprint

> **Sprint numbering:** canonical sprints are **4 = loudness, 5 / 5b = EQ + multichannel, 6 = adaptive clarity** (see [../sprints/00-sprint-model.md](../sprints/00-sprint-model.md)). Older drafts of this doc used 1/2/3; those map to 4/5/6 respectively.
>
> **Test-harness reality (read first):** the DSP correctness gate is the **C++ null-test golden-master harness** (`bash scripts/build-null-test.sh`). `swift test` (native swift-testing) runs the Swift suites headless as part of `make strict-gate`, but it is **not** the DSP golden-master gate. The fictional `./AdaptiveSound --input … --intensity N` CLI does **not** exist; bit-exact and frequency-response checks are C++ harness tests. Sections below have been corrected to match.

---

## Validation Philosophy

**Three Pillars:**
1. **Automated Testing** — Catch regressions quickly (null-test / bit-exact bypass, golden master, frequency response, libebur128 LUFS/true-peak oracle; THD+N is planned — no THD+N test exists yet)
2. **Integration Testing** — Verify end-to-end behavior (soak tests, device switching, parameter automation)
3. **Listening Panel** — Validate perceptual quality (professional audio engineers, MUSHRA-style) *(2026-10-23: for the processing sprints S14-lite, S16 and S18 the gate is the founder's own blind, level-matched ladder — [Verifying the 2026-10-23 sound decisions](#verifying-the-2026-10-23-sound-decisions); the MUSHRA panel is the later, wider protocol)*

**Principle:** Automated tests verify code correctness. Listening panel validates that DSP actually sounds good.

---

## Per-Merge Gates (Automated, < 15 Minutes)

**Runs on every PR to `main`** (CI: `.github/workflows/strict-ci.yml` runs `make strict-gate` on GitHub-hosted `macos-26`). Must pass before merge. *(Reconciled to the code 2026-10-13, product council; counts and targets re-checked after R1, 2026-10-14.)*

### Gate 1: DSP Test Harness (C++ null-test) — the primary gate

```bash
bash scripts/build-null-test.sh
```

This builds and runs the standalone C++ harness (`Tests/DSPKernelNullTest.cpp` + the `*.inc` area files). It is the **canonical DSP gate**.

**Requirements:**
- All harness tests pass (0 failures; the harness reports the count — 220 registered as of 2026-10-14, after R1) — bypass/identity, EQ, limiter, loudness/BS.1770, multichannel, spatial passthrough, Pure-Mode policy/format/decode/round-trip, gapless seams, crossfeed, Realizer, intensity ramp, the libebur128 LUFS/true-peak oracle, the 31-band FR sweep, the graphic-EQ designer vs its Python oracle, track-loudness profiling, EQ transitions and the RT EQ engine paths, the loudness-neutral gain, the Sprint EQ break-it / fix-round regressions, the device-list policy, the render gate, the Pure gapless arm contract and the Pure format / conversion refusal table (both R1, PR #88), RT-allocation soaks and snapshot no-tear.
- Stereo **golden master** signature `0xE7AF0C67F9340785` (`GoldenMaster_StereoN2_v1`, `Tests/MultichannelTests.inc:45`: FNV-1a over the processed L+R of a deterministic chirp through +6 dB @ 1 kHz EQ + active limiter) must match. Any one-ULP change to stereo output flips it; re-baseline only on a founder-approved DSP change. *(Re-baselined in Sprint EQ's EQ1b, when the +6 dB moved to the accurate SVF graphic EQ; it was `0xE7267654BA01D315`.)*
- Fixtures are written + read in `<repo>/test-data/` (never `/tmp`); generated WAV/bin are git-ignored.

**`swift test` runs headless** (native swift-testing) and **is** part of the pre-merge `make strict-gate`. The Swift test targets (`AdaptiveSoundTests` — added in R1, PR #88, the one target that imports the app itself to test the shipped view model — `PlaybackQueueKitTests`, `LibraryBrowseKitTests`, `EQEditKitTests`, `OutputDeviceKitTests`, `SettingsKitTests`, `TrackLoudnessKitTests`, `DesignTokenKitTests`, `AudioDSPTests`, and `RigKitTests`, the test rig's own proof) use the Swift Testing framework; the DSP golden-master gate, however, remains the C++ null-test harness, not `swift test`.

**Companion offline checks (`swift run`, headless):**
- `swift run VerifyAUGraph` — proves the custom v3 AU registers, instantiates, sits in the AVAudioEngine graph, and renders.
- `swift run SRCQualityMeasure` (in `make gate`, R1.1-A) — the Enhanced SRC gate. It drives the production converter (`AudioFormatKit.StreamingResampler`: `AVAudioConverter`, Mastering, max quality) in the app's 8192-frame chunks over every conversion the app makes (44.1 / 88.2 / 96 / 176.4 / 192 / 352.8 / 384 / 32 / 22.05 kHz → 48 kHz, 48 kHz → 44.1 / 88.2 / 96 / 176.4 / 192 kHz) and fails unless the passband is within 0.1 dB to 20 kHz, every image and alias is ≤ −100 dB (a weighted least-squares tone reading, the wanted tone removed first), equal rates are bit-exact, and it streams ≥ 2× real time. A control — the pre-R1.1 Normal algorithm — must fail both the passband and the stopband, or the gate fails itself (council R-6: the old tool printed −7.23 dB at 20 kHz and passed). `AdaptiveSoundTests` (`EnhancedResamplerTests`) checks the same on the real bridge: a 44.1 kHz file plays 20 kHz level with 1 kHz.

### Gate 2: Bit-Exact Bypass (intensity-0 null test)

**Purpose:** Verify that intensity 0% with the EQ flat or off produces bit-identical output.

This is **not** a CLI invocation — it is the harness test `IntensityZero_BitExactPassthrough` (+ `IntensityZero_MultiChunkBitExact`) in `DspBypassTests.inc`, with `EQ_Off_BitExact` / `EQ_BitPerfect_P0` / `EQ_FlatIsBitTransparentBypass` for the EQ side. Intensity is ramped (τ = 32 ms); once it has settled at 0 the kernel runs EQ → limiter (path P1), and after a 2 s hold with an identity (flat or off) EQ it takes the bit-perfect path P0 and returns the block untouched (`DSPKernel.cpp:191-212`; since Sprint EQ, decision 25, Intensity 0 alone is no longer the bypass). The test settles the ramp with silent buffers, then compares byte-for-byte (`memcmp`) against the input. The Pure-Mode software-chain bit-exactness is covered by `RoundTripTests.inc` (decode → `convertFloatToNative`, zero tolerance, 16/24-bit).

**Acceptance:** byte-identical (zero tolerance) for both the kernel bypass and the Pure software-chain round-trip. (Run via Gate 1.)

### Gate 3: EQ Frequency Response (baseline regression)

**Purpose:** Confirm a band boost changes the signal by the right amount, with no boundary click.

Harness tests `EQ_FrequencyResponseAccuracy` and `EQ_CoefficientSwapNoClick` (`EqTests.inc`, plus the N-channel variants in `MultichannelTests.inc`): apply a known band boost, measure the settled-RMS delta vs. flat, assert within tolerance; and verify a large coefficient swap produces no audible boundary discontinuity (zipper).

**Acceptance:** measured band gain within the harness tolerance; no zipper artifact. (Run via Gate 1.)

### Gate 4: Sanitizers + clang-tidy (C++23)

The C++ modules build under **`gnu++2b` / C++23** (see `Package.swift` `cxxLanguageStandard: .gnucxx2b` and `scripts/lib/cxx-analysis-flags.sh` `cxx_analysis_core_flags`: `-std=gnu++2b`, shared by `build-null-test.sh`, clang-tidy and the pre-commit hook) — **not** C++17. All of it runs from `make strict-gate`:

```bash
make sanitize               # the null test under ASan + UBSan
make tsan                   # the null test under ThreadSanitizer
make sanitize-library-store # VerifyLibraryStore under ASan (the FFmpeg metadata bridge)
make leak-check             # leaks(1) — Apple-Silicon ASan ships no LeakSanitizer
# clang-tidy: the repo .clang-tidy (WarningsAsErrors "*"), pinned LLVM 23, over Sources/AudioDSP,
# Sources/AudioDSPTestBridge and Tests/ (.cpp/.mm/.cc), with the flags in scripts/lib/cxx-analysis-flags.sh
```

*Also per merge (the gate: `scripts/gate/steps.tsv` run by `scripts/gate/run.sh`; `make strict-gate`): SwiftFormat / SwiftLint / clang-format drift, semgrep (`.semgrep.yml`), the suppression policy, the migrator never-erase and playlist reference-add guards, Kit-purity / Dynamic-Type guards, cppcheck (pinned, required), Periphery, `swift build`, `swift test`, `make gate`, `make main-thread-stall`, the null-test source-coverage guard and a `--release-strict` (-O2, -Werror) compile.*

**Acceptance:** zero sanitizer errors, zero clang-tidy violations.

### Gate 5: Library Store Verify (S8+ persistent store)

The library store (`LibraryStore`, GRDB.swift over system libsqlite3) has no place in the DSP null-test; it is gated by its own headless harness — a `swift run` executable that mirrors the `VerifyAUGraph` idiom (headless-gate parity, not XCTest):

```bash
swift run VerifyLibraryStore     # or: make library-store-verify
```

**Acceptance:** all numbered checks PASS (S8.1 schema/migration/corruption/restart-durability + CRUD/integrity, facets, WAL concurrency ending in `PRAGMA integrity_check=ok`, idempotency+identity, filesystem-divergence; plus scan/reconcile, metadata + artwork, folder watch, move-match, reachability, FTS5 search, sort and play tracking, playlists, additive-migration convergence, album artists, store-open safety, genre covers), process exits 0. `make gate` runs Gate 1 + `VerifyAUGraph` + this in one command.

---

## Nightly Regression Suite (Full, ~30 Minutes)

> **Aspirational — no nightly job exists.** CI runs `make strict-gate` on every PR / push to `main` (`strict-ci.yml`) and the release build on `v*` tags (`release.yml`); there is no scheduled workflow. Each item below is marked with what covers it today.

Designed to catch subtle regressions.

### Test 1: Biquad Fitting Stress
```cpp
// Generate 1000 random gain curves
for (int i = 0; i < 1000; i++) {
  std::vector<float> gains(31);
  for (int j = 0; j < 31; j++) {
    gains[j] = (float)(rand() % 41 - 20) / 10.0f; // ±20 dB
  }
  
  // Compute biquad coefficients
  auto coeff = eqModule.realizer(gains);
  
  // Assert stability (poles inside unit circle)
  assert(coeff.isStable());
  
  // Assert gain accuracy
  float measured = frequencyResponseAt(coeff, 1000.0f);
  assert(abs(measured - expectedGain) < 0.5f); // ±0.5 dB tolerance
}
```

**Acceptance:** All 1000 curves stable, gains within tolerance

> **Covered per merge instead** (the bell fitter above was retired in Sprint EQ): the `GraphicEQDesigner` suite in `EqDesignerTests.inc` — `EQ_ACGE_Ramo1000` (1000 binary and integer ±12 dB commands), `EQ_ACGE_Hard`, `EQ_ACGE_SingleBand`, `EQ_Designer_MatchesOracle`, at 44.1–192 kHz.

### Test 2: 20-Track Corpus End-to-End

> **Aspirational — no batch CLI exists.** There is no `./AdaptiveSound --input … --intensity N` command; the app is GUI-only. This corpus pass would need a small offline driver (e.g. extend `VerifyAUGraph` / a dedicated harness) that decodes each track, runs the kernel/graph offline, and measures the metrics below against `ffmpeg ebur128`. Until that driver exists, corpus-level LUFS/BRIR/RT metrics are measured ad hoc or via the C++ harness's synthetic signals.

Planned measurements over a 20-track corpus (varied genres, dynamic range):
- LUFS accuracy (vs. `ffmpeg ebur128`)
- BRIR convolution correctness (correlation to reference) — *pending the BRIR module (forward-plan S18; currently a pass-through stub)*
- RT-safety metrics (no xruns, p99.9 render ≤ 5 ms)

**Acceptance (when the driver exists):**
- LUFS accuracy ±0.1 LUFS
- BRIR correlation ≥ 0.95
- p99.9 render ≤ 5 ms
- xruns = 0

### Test 3: Parameter Sweep (Zipper Noise Detection)
```cpp
// Sweep single EQ band from −20 to +20 dB over 10 sec
for (int frame = 0; frame < 480000; frame += 2400) { // 50 ms steps
  float gain = -20.0f + (frame / 480000.0f) * 40.0f;
  eqModule.setGain(band, gain);
}

// Analyze output for spectral glitches
// Assert: no 20 kHz spikes (zipper noise indicator)
```

**Acceptance:** No spectral artifacts detected

> **Covered per merge instead:** the EQ-transition harness (`EQ_Transitions_Realistic` / `_Adversarial` / `_SinglePoints`, `BreakIt_Transitions_LowBandGestures`, `EqEngineFixTests.inc`) and `EQ_CoefficientSwapNoClick`. (`eqModule.setGain` is not an API; the EQ takes 31 points through the Realizer.)

### Test 4: Clarity Masking Model (Reference Check)
```cpp
// Synthetic masking test: 1 kHz (loud) + 4 kHz (soft)
auto signal = generate1kHz_loudPeak() + generate4kHz_soft();

// Compute masking threshold at 2 kHz
float threshold = clarityModule.maskingThresholdAt(2000.0f);

// Compare to Moore-Glasberg reference (lookup table)
float reference = mooreGlasbergReference(2000.0f);

assert(abs(threshold - reference) < 1.0f); // ±1 dB
```

**Acceptance:** Threshold ≤ ±1 dB of reference

> **Aspirational — not built.** `ClarityModule` is a pass-through stub with no masking model; this belongs to S15–S16 (SPIKE-MASKING-MODEL).

---

## Per-Sprint Final Validation (Manual + Scripted)

> **Listening-panel status: NOT YET EXECUTED.** The MUSHRA listening-panel rounds below are the planned acceptance protocol; no panel has been run and no `LISTENING-PANEL-*.md` reports exist yet. Automated harness tests (Gate 1–4) are the gate that has actually run. Sprint headings use the canonical 4/5/6 numbering (Sprint 4 + 5/5b DONE; Sprint 6 not yet shipped).

### SPRINT 4: Loudness Safety & Transparent Dynamics

#### Automated Tests (see [../sprints/04-sprint-4-loudness-safety.md](../sprints/04-sprint-4-loudness-safety.md))
- [x] Limiter null-test: bypass = bit-identical (`Limiter_BypassIsIdentity`)
- [x] True-peak enforcement: output ≤ −1 dBTP (`Limiter_TruePeak_CeilingGuarantee_vs_ebur128`)
- [x] GR response: < 2 ms (`Limiter_GRResponseWithin2ms`)
- [ ] Soak test: 1 hour, zero XRuns
- [ ] Hearing-safety clamp: proportional scaling verified

#### Manual Tests (Scripted)
- [ ] Play 5 reference tracks (vocal, acoustic, electronic, classical, orchestral)
- [ ] Listen for limiter artifacts (pumping, swelling, breathing)
- [ ] Verify no audible artifacts
- [ ] Log observations to `VALIDATION-SPRINT-4.log`

#### Listening Panel
- [ ] Recruit 5–10 audio engineers
- [ ] MUSHRA protocol: original vs. limiter-processed (30 sec clips)
- [ ] Record: "Inaudible" / "Subtle" / "Obvious" ratings + artifact reports
- [ ] Pass: ≥80% rate "Inaudible" or "Subtle"
- [ ] Generate report: `LISTENING-PANEL-SPRINT-4.md`

#### Sign-Off
- [ ] Audio DSP lead: ✅ DSP quality approved
- [ ] QA lead: ✅ All acceptance criteria met
- [ ] Project lead: ✅ Ready to proceed to Sprint 5

---

### SPRINT 5 / 5b: Minimum-Phase EQ Wiring & Spectral Correction

#### Automated Tests (see [../sprints/05-sprint-5-eq-foundation.md](../sprints/05-sprint-5-eq-foundation.md))
- [x] Biquad stability: all random curves stable (now the graphic-EQ designer: `EQ_ACGE_*`)
- [x] Null-test: 0 dB = bit-identical (`EQ_FlatIsBitTransparentBypass`, `EQ_Off_BitExact`)
- [ ] Frequency response: ±0.5 dB per band center *(gated at ±1.0 dB: `EQ_Sweep31Bands_48k` / `_44k`)*
- [ ] Gain linearity: ±20 dB range both directions
- [ ] Phase coherence (min-phase): no pre-ringing
- [x] Parameter ramping: no zipper noise (`EQ_Transitions_*`, `EQ_CoefficientSwapNoClick`)
- [ ] AutoEq profile loading: 5/5 profiles parse, apply *(not built — S12)*

#### Manual Tests (Scripted)
- [ ] Log-sweep test: apply known curve → measure response
- [ ] Before/after spectrum: visual comparison (screenshot evidence)
- [ ] Device profile switching: 3 devices tested
- [ ] Slider responsiveness: latency < 50 ms measured
- [ ] THD+N: ≤ −90 dB across all settings
- [ ] 5-minute soak: zero xruns, stable audio

#### Listening Panel
- [ ] MUSHRA protocol: 5 reference tracks × 3 tests (null, presence peak, bass boost)
- [ ] Blind A/B: original vs. EQ-processed
- [ ] Record: "Identical" / "Prefers B" / "Artifacts" ratings
- [ ] Pass: ≥70% detect intended EQ, ≤20% report artifacts
- [ ] Generate report: `LISTENING-PANEL-SPRINT-5.md`

#### Sign-Off
- [ ] Audio DSP lead: ✅ EQ quality approved
- [ ] QA lead: ✅ All acceptance criteria met
- [ ] Project lead: ✅ Ready to proceed to Sprint 6

---

### SPRINT 6: Adaptive Clarity & Loudness Compensation

> *(2026-10-23: the loudness-compensation and Clarity items below are the historical plan; the decided measurements — a bass-only tilt following the volume the listener turns, Clarity with its own switch feeding the one EQ program, the founder's blind ladder as the last line — are in [Verifying the 2026-10-23 sound decisions](#verifying-the-2026-10-23-sound-decisions).)*

#### Automated Tests (see [../sprints/06-sprint-6-adaptive-clarity.md](../sprints/06-sprint-6-adaptive-clarity.md))
- [ ] Masking threshold: ±1 dB vs. reference
- [ ] Clarity gain limits: ≤ +3 dB/band, < +2 dB cumulative
- [ ] Loudness compensation: ±1 dB contour accuracy
- [ ] Arbiter composition: multi-contributor integration
- [ ] Conversational tuning: 90%+ phrase parsing success
- [ ] Content-aware: genre detection + EQ adaptation working
- [ ] 2-hour soak: zero XRuns, no perceptual glitching

#### Manual Tests (Scripted)
- [ ] Clarity perceptual: orchestral passage, can you hear more detail?
- [ ] Loudness compensation A/B: soft level with comp vs. without
- [ ] Conversational tuning: 20 diverse requests, ≥18/20 sound intended
- [ ] Arbiter end-to-end: device + loudness + clarity + content compositing
- [ ] Content-aware transition: 2-song skip (genre change), smooth or jarring?
- [ ] Parameter automation: Reimagine knob sweep, smooth ramping

#### Listening Panel
- [ ] MUSHRA protocol: 5 reference tracks × 5 tests
  - Test 1: Clarity unmask (no clarity vs. clarity)
  - Test 2: Loudness compensation transparency
  - Test 3: Conversational tuning naturalness
  - Test 4: Arbiter composition coherence
  - Test 5: Overall adaptive experience
- [ ] Blind A/B + subjective ratings
- [ ] Pass: ≥75% rate "Highly adaptive" or "Natural"
- [ ] Generate report: `LISTENING-PANEL-SPRINT-6.md`

#### Sign-Off
- [ ] Audio DSP lead: ✅ Adaptive DSP quality approved
- [ ] QA lead: ✅ All acceptance criteria met
- [ ] Project lead: ✅ Phase 1c MVP ready for release

---

## Verifying the 2026-10-23 sound decisions

The founder's decisions of 2026-10-23 on the sound roadmap ([roadmap reconciliation](../product/roadmap-reconciliation-2026-10/README.md), "Decisions taken") each come with the measurement that proves them — the sound engineer's figures ([sound-truth.md, Part 2](../product/roadmap-reconciliation-2026-10/brainstorm/sound-truth.md), [quality-pass-sound.md, Part B](../product/roadmap-reconciliation-2026-10/brainstorm/quality-pass-sound.md)). This is the acceptance list an implementing engineer or agent runs; the sprint rows and the [known issues](../product/known-issues.md) point here. Numbers are pass bars.

**The rigs.** **harness** = the C++ null test (Gate 1: `Tests/*.inc`, with the vendored libebur128 oracle — `Loudness_Oracle_Integrated_vs_ebur128` at ±0.2 LU, `Loudness_Oracle_TruePeak_vs_ebur128`, `Limiter_TruePeak_CeilingGuarantee_vs_ebur128`; the limiter's gain reduction read from the module); **Swift Testing** = `swift test` (`AdaptiveSoundTests` for the view model, the chips and the badges; `EQEditKitTests`, `SettingsKitTests`, `TrackLoudnessKitTests` for the stores and rules); **the founder's ear** = the one listening lane (agents never play audio). "GR" is the limiter's gain reduction. "The ceiling" is −1 dBTP on Bluetooth and unknown outputs, −0.1 dBTP where the link is lossless and the output runs at the engine's 48 kHz (the scope below).

### Leveling (card 1 — R1.1-B)

- [ ] **harness:** the published leveling gain per track and per album equals (−18 − libebur128's integrated LUFS) within 0.2 LU, and never exceeds (C_work − the track's true peak, C_work = the ceiling − 0.27 dB, the limiter's working ceiling): the analyser's new true-peak field against `Loudness_Oracle_TruePeak_vs_ebur128`.
- [ ] **harness:** GR = 0 dB over the whole leveled corpus (the true-peak cap holds; the net sleeps).
- [ ] **harness:** an Intensity sweep 0 → 1 → 0 with Leveling Off leaves integrated LUFS within 0.1 dB — the old auto-leveller is gone, not hidden (no code path left that integrates the session and rides the gain; `Intensity_EndpointsBitExact_Settled` keeps the endpoints bit-exact).
- [ ] **harness:** a gapless pair in Album mode shows one constant gain across the seam; a gapless group takes the album gain even in Track mode; until the Engine sprint "at the seam" means as the engine counts it (KI-GAP-02's 0–186 ms at a resampled seam).
- [ ] **Swift Testing:** the unknown-loudness cut is −5 dB exactly, applied only with Leveling on; a file tag (ReplayGain / R128) is read only for a track not yet analysed, our own analysis first; the target shown is −18; Off is the identity.
- [ ] ~~**Swift Testing + the XM4 (Pure):** the device-volume loan carries the cut — ten track changes leave the device at (the level found − the playing track's cut) within one device step, no creep; the loan's own set never re-anchors (`MasterGainOnPure.sameLevel`, 0.05 dB, keeps telling the listener's move from its own); the soundbar (`.fixed`) gets no cut and the badge says so; the give-back returns the level found.~~ *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)* *This check moves with it and runs on the DAC.*
- [ ] **Swift Testing (R1.1-B):** in Pure the Leveling row shows the shared state — "Leveling off (bit-perfect)" — and Pure's output is unchanged (the Pure round-trip stays bit-exact).
- [ ] **Swift Testing + the founder on the Mac's built-in output (R1.1-B; the toast is Master Gain's loan, not leveling's):** with Master Gain below 0 dB in Pure, the end of the queue puts the device volume back and "Volume restored" shows once; no toast when Pure lowered nothing.
- [ ] **Swift Testing (decided 2026-10-25, as recommended):** the analysis survives a relaunch from its derived-data file beside the library, and the library DB has no loudness column; Album mode before an album is fully analysed uses the album tags when every track has them, else each track's own gain until the next seam across silence — no step at a continuous seam; a Leveling mode change mid-song glides at once, and no automatic change moves the level inside a song.
- [ ] **the founder's ear, on the XM4 (Enhanced):** a mixed-era shuffle with Leveling on Auto — albums even, nothing moves inside a song.

### The peak-safe turn-down (card 4, R1.1-B) and the headroom ledger (card 4, S14-lite)

- [ ] **harness (R1.1-B):** the cap C_cap = C_work − (the track's true peak + the leveling gain + the curve's largest boost), C_work = the ceiling − 0.27 dB (the limiter's working ceiling); the published offset beyond leveling G = min(−ΔL, C_cap) — C_cap may be positive, never clamped to 0 — and the turn-down shown T = G − (−ΔL) ≤ 0, applied once before the EQ; with it, GR = 0 dB on a −9 LUFS master with +6 dB of bass at the wired −0.1 dBTP ceiling (the `OutputCeiling.h` case: today > 1 dB of GR up to 74 % of the time at −1 dBTP, EQ On up to 2.75 dB under Off); Compare is level-matched to it within 0.2 dB.
- [ ] **harness (S14-lite, the full ledger):** the stacked worst case — taste +12 dB at 60 Hz, compensation at full depth, an HD 650 correction — on a bass-heavy −9 LUFS master at the wired ceiling: the ledger's per-band sum ≤ +12 dB in-band, GR < 0.1 dB, and the whole program's LUFS change vs Off within the compensation's own designed amount.
- [ ] **harness:** the drawn-vs-played log sweep through the chain against the composed read-back, ≤ 0.1 dB.
- [ ] **harness:** as soon as the analysis can, the turn-down is measured from the EQ'd track's real peak, not bounded by the curve's largest boost: over the corpus the measured number turns down less than or equal to the bound on every track, never more.
- [ ] **Swift Testing:** an imported AutoEq file's `Preamp:` line is dropped and the ledger's number shown; a band the ledger holds is marked *protected* on the graph; the GR meter's readout appears when the net would have worked.

### Loudness compensation (card 3 — S14-lite)

- [ ] **harness:** a 20 dB fader step changes the realised response by the designed bass tilt — at the 50 % starting depth (a 20 dB turn-down) about +3 dB at 100 Hz, +4 at 50 Hz, +5 at 20 Hz *relative to 1 kHz*, nothing above 1 kHz (the full ISO 226 80 → 60 phon difference: +6.2 dB at 100 Hz, +8.2 at 50 Hz, +10.5 at 20 Hz, +3.9 at 200 Hz, +1.2 at 500 Hz, ~0 from 1 to 8 kHz); **every band ≤ 0 dB absolute** — ease-the-mids; the bass cap is +6 dB; nothing above 1 kHz is ever boosted.
- [ ] **harness:** GR = 0 dB on a −9 LUFS master with compensation at full depth — the mids are eased, never boosted (the boost form would show sustained GR).
- [ ] **harness:** the level-loop check — the level is read as (fader − the layer's own broadband loudness change), the fixed point the Realizer solves off the audio thread: after the listener restores loudness with the fader, the published tilt equals the one designed for the perceived level (not the ~23 % under-compensation an unread cut would give).
- [ ] **Swift Testing:** the level the button follows = Master Gain + the device's own volume where the Mac can read it, against the one-time "my normal loud setting"; on an output whose volume reads `.fixed` (the HDMI soundbar) the control is a labelled manual "Loudness amount"; the reading includes Leveling's gain and the turn-down; the device-volume listener works on Enhanced without painting a device volume onto Enhanced's readout (the KI-SET-03 regression); Enhance never turns Loudness on before the reference is set; "Off in bit-perfect mode" in Pure.
- [ ] **the founder's ear, before the depth is fixed:** one evening on the XM4 — the curve pre-rendered at 40 / 50 / 60 % of the hearing-model difference, at a 20 dB turn-down, on three familiar loud masters; settles the depth and the cap. One check owed: whether the XM4's own buttons move the Mac's volume slider (if not, the caption says "use the Mac's keys").
- [ ] **the founder's ear, the last line of S14-lite:** the blind ladder below, at the real late-night level with the reference set, "with" vs "without" nudged to equal loudness.

### The fold (card 5 — R1.1-B interim; the Engine sprint final)

- [ ] **harness:** the analyser's folded true peak vs libebur128's true peak of the actually folded stereo (the TP oracle's own tolerance); the folded loudness vs libebur128 on the folded stereo within 0.2 LU — Leveling uses the folded figure for N > 2 (it sits 1–2 LU under the six-channel measurement when the surrounds carry a modest share).
- [ ] **harness:** a C-only sine folds to −3.0 dB per side (0.7071); L = R = C at equal level sums to +4.6 dB per side; the coherent worst case (1 + 0.7071 + 0.7071) is +7.66 dB.
- [ ] **harness:** with the per-track trim, GR ≈ 0 dB over the founder's surround albums (`SpatialTests.inc` / `MultichannelTests.inc`); the LFE rule — an LFE coherent with the mains' low band → omit; one carrying energy the mains do not → full level per side; unknown → omit; the trim computed with that gain.
- [ ] **harness (the Engine sprint):** a stereo-in-5.1 file (C / LFE / Ls / Rs silent) through the fold then crossfeed nulls against the plain stereo file through crossfeed, within 1.5e-7 sample for sample (`Crossfeed_MatchesBs2bReference`'s tolerance). Until then R1.1-B proves the opposite honestly: no "XF" chip on a folded file (KI-SND-06); `Crossfeed_NonStereo_PassThrough` guards the kernel.
- [ ] **the founder's ear, pass / fail before it ships:** on the XM4, one album whose LFE has bass the mains don't and one whose LFE is a copy; a bass-heavy passage three ways (omit / −6 dB / full) with the trim applied.
- [ ] **prototype first:** the folded-peak histogram over the founder's 5.1 albums — trims mostly within 0–3 dB say the per-track trim is clearly right; a cluster near 7 dB says a fixed trim is nearly as good.

### The EQ program and Compare (card 6 — S12; its first layer in S14-lite)

- [ ] **harness:** a log sweep through the chain vs the composed read-back of the layered program (correction | taste | compensation, designed once), ≤ 0.1 dB at every band centre; the existing `EQ_Sweep31Bands_48k` / `_44k` stay at ±1.0 dB per band.
- [ ] **harness:** Compare's LUFS with vs without "my EQ" within 0.2 dB, with correction and compensation left in, over every broadband offset the program adds — the loudness-neutral gain, the peak-safe turn-down and Leveling included.
- [ ] **Swift Testing:** a bypass per layer; "Bypass all processing" is a separate latching control; the per-output memory carries the parametric bands and the correction choice; pin, edit, unpin — the shared slot is unchanged (KI-EQ-01); the "Clarity" preset displays as "Detail" with its stored id unchanged.
- [ ] **Swift Testing:** two devices of the same model — one correction, never two (the model fallback does not double-apply).

### Intensity (card 2 — S17) and Clarity (S16)

- [ ] **harness:** pink noise with a correlated wet (Clarity at minimal depth): output LUFS flat within 0.2 dB across a slow 0 → 1 sweep — no mid-knob hump (today's equal-power blend adds up to +3 dB at r = 0.5 on correlated material, `DSPKernel.cpp:286-287`; the decided Intensity scales parameters, never crossfades).
- [ ] **harness (control plane):** the Loudness / crossfeed / Leveling state bytes in `TargetState` are unchanged across the sweep; Intensity 0 ≡ every automatic stage off ≡ P0-eligible with the EQ off.
- [ ] **Swift Testing:** Intensity never changes a hand-set switch; Clarity has its own on / off, depth and chip; "Clarity depth" and "Room amount" are visible rows of their own; Intensity's default is 0.
- [ ] **the founder's ear, the last line of S16:** the blind ladder — adaptive vs the static "Detail" preset, then vs the original; a stage that does not win ships off and hidden.

### Headphones (card 8 — S18; correction before the render, S13; the offers, card 7)

- [ ] **Swift Testing:** `crossfeed.enabled && brir.active` is unreachable — one "Headphones: Off / Crossfeed / Spatial" control, exclusive by construction, remembered per output (`TargetState.h:101-105` records the invariant with "no arbitration code yet").
- [ ] **harness:** a sweep through Spatial with room amount at every Intensity shows no comb structure in the magnitude (the signature of a wet / dry crossfade against a delayed wet); the render's responses are headphone-equalised, so Spatial changes space, not tone — the magnitude through Spatial vs the timbre-matched dry reference within the headphone-equalisation's own tolerance.
- [ ] **harness:** a fresh-install null with the XM4 connected and a correction available: bit-identical to the source (nothing auto-applies; the offer's preview plays level-matched only while held).
- [ ] **the founder's ear, the last line of S18:** the blind ladder against a timbre-matched dry reference (same correction, headphone-equalised responses) with the artifact checklist — no smeared centre, no hollow tone, bass intact; "I can tell them apart" proves nothing.

### The ceiling (Sprint EQ decision 29, scoped 2026-10-23) — measured in the Engine sprint

- [ ] **the USB DAC, a HAL tap or loopback:** a −0.1 dBTP signal through the 48 → 44.1 kHz AUHAL path, its peak read after the conversion. The limiter's working ceiling is −0.1 − 0.27 ≈ −0.37 dB (`LimiterModule.h:103-105`: a < 0.17 dB detector under-read plus a 0.10 dB guard), so about −0.2 dBTP reaches the conversion; an overshoot beyond that margin keeps the rate condition. Until measured: −0.1 dBTP only where the link is lossless *and* the output runs at the engine's 48 kHz (the HDMI soundbar, a 48 kHz DAC); −1 dBTP on Bluetooth and on any other-rate output. With the peak-safe turn-down in place the net is expected to sleep at either ceiling.

### The blind ladder — the last acceptance line of S14-lite, S16 and S18 (card 10)

- **Founder decision (≠ the recommendation): the blind test runs at the end of each processing sprint only.** There is no Clarity-prototype test before S15 and no spatial-demo test before S18.
- **The protocol** is the adaptive-tone study's Stage 1 ([adaptive-tone README §6](../design/adaptive-tone/README.md#6-how-we-would-prove-it-the-evaluation-ladder)): the founder's own blind A/B on their own gear — the XM4 over Bluetooth and the soundbar over HDMI — with pre-registered tracks and a sequential test: about 23 trials if the effect is real, capped at 60.
- **Level-matched within 0.2 dB over *every* offset the engine adds** — Leveling, the peak-safe turn-down, the compensation's own level change. Otherwise the test measures loudness, not quality.
- **The bar:** "I can't tell" for anything that plays by default; "I prefer it" for anything Enhance turns on. Loudness at the real late-night level with the reference set; Spatial against a timbre-matched reference with the artifact checklist.
- **A stage that does not win ships off and hidden**; its sprint is still spent. Enhance never turns on a stage that lost.
- The MUSHRA panels below stay as the later, wider protocol; they are not the processing sprints' gate.

---

## Listening Panel Protocol

### Panel Composition
- **Size:** 5–10 audio professionals (mixing engineers, mastering engineers, audio researchers)
- **Qualification:** ≥3 years professional audio work + familiarity with DAWs/EQ
- **Recruitment:** Contact local studios, universities, audio communities
- **Incentive:** Free copy of final product + acknowledgment in credits

### Test Environment
- **Room:** Quiet (≤ 30 dB ambient)
- **Hardware:** Neumann NDH20 headphones (reference, matched pairs)
- **Calibration:** SPL meter (85 dB @ 1 kHz reference)
- **Session Duration:** ~90 min per panelist
- **Fatigue:** 10-min breaks every 30 min

### MUSHRA Test Format

**Per test:**
1. Listen to reference anchor (original, unprocessed) — 30 sec
2. Listen to hidden candidates (A, B, C, ...) — 30 sec each
3. Rate each candidate on 5-point scale:
   - 5: Excellent (identical to anchor / very natural)
   - 4: Good (minor differences / slightly colored)
   - 3: Fair (noticeable differences / obvious EQ)
   - 2: Poor (significant artifacts / unnatural)
   - 1: Bad (severe artifacts / unusable)
4. Force-choice preference (if candidates differ)
5. Open-ended comments (artifacts, unexpected changes, etc.)

### Data Collection
- Record ratings in spreadsheet (panelist × candidate × test)
- Audio-record or video-record comments (optional)
- Save waveforms + spectrograms of test signals

### Data Analysis
- **Consensus:** ≥80% of panelists rate ≥ 4 (good/excellent)
- **Artifacts:** Count reports of clicking, zipper, pumping, etc. (≤20% max)
- **Preference:** Aggregate force-choice votes (>50% indicates clear preference)
- **Confidence Intervals:** Report 95% CI on mean ratings

### Report Format
```markdown
# Listening Panel Report: Sprint 6

**Date:** 2026-06-XX  
**Panelists:** 8 audio professionals (5 mixing engineers, 2 mastering, 1 researcher)  
**Duration:** 90 min per panelist

## Test 1: Clarity Unmask (Orchestral Passage)

### Results
- Candidate A (no clarity): 3.6 ± 0.9 (avg rating ± SE)
- Candidate B (clarity 50%): 4.3 ± 0.8
- Preference: 75% prefer B

### Comments
- "Violins clearer in B, without sibilance spike"
- "B reveals more bow noise detail"
- "No artifacts detected"

### Consensus
✅ Pass: ≥80% rated B ≥ 4, <10% reported artifacts

...
```

---

## Regression Gates (Post-Release)

**Ongoing:** After Phase 1c MVP ships, run these weekly to catch degradations.

### Weekly Regression Tests
1. Biquad fitting stress (1000 curves) — < 30 sec
2. 20-track corpus end-to-end — < 15 min
3. LUFS measurement accuracy (vs. ffmpeg) — < 5 min
4. True-peak ceiling enforcement — < 5 min

### Monthly Deep Dive
- Full listening panel (subset: 3–5 panelists)
- New music corpus (update test set)
- Real device testing (Bluetooth, new headphones)

---

## Success Metrics (Phase 1c MVP)

| Metric | Target | Status |
|--------|--------|--------|
| C++ harness pass rate (220 tests as of 2026-10-14; the harness reports the count) | 100% (0 failures) | DONE — passing |
| Stereo golden master | `0xE7AF0C67F9340785` match (re-baselined in Sprint EQ; was `0xE7267654BA01D315`) | DONE — matching |
| Code coverage (signal path) | ≥80% | TBD |
| Null-test accuracy (THD+N) | ≤ −120 dB | TBD |
| LUFS measurement accuracy | ±0.1 LUFS | Gated at ±0.2 LU vs libebur128 (`Loudness_Oracle_Integrated_vs_ebur128`); ±0.1 LU vs ffmpeg via `scripts/validate-lufs.sh` (manual) |
| True-peak enforcement | ≤ −1 dBTP | DONE — gated (`Limiter_TruePeak_CeilingGuarantee_vs_ebur128`) |
| EQ frequency response | ±1 dB | DONE — gated (`EQ_Sweep31Bands_48k` / `_44k`, ±1.0 dB) |
| Listening panel consensus | ≥80% ≥4 rating | TBD |
| Artifact reports | ≤10% of panelists | TBD |
| Soak test (2 hr) | Zero XRuns | TBD |
| Code quality (ASAN/TSan) | Zero violations | DONE — gated per merge (`make sanitize`, `tsan`, `sanitize-library-store`, `leak-check`) |

---

**Status:** Sprint 4 + 5/5b automated gates DONE (C++ harness passing, golden master matching); listening panels NOT YET EXECUTED.  
**Next:** Run the Sprint 4/5 listening panels; build out Sprint 6 (clarity/loudness-comp) tests as that DSP lands.  
**2026-10-23:** the acceptance list for the founder's sound decisions added ([Verifying the 2026-10-23 sound decisions](#verifying-the-2026-10-23-sound-decisions)); the founder's blind ladder is the last line of S14-lite, S16 and S18.  
**2026-10-25:** the leveling list amended to the founder's answers at R1.1-B's plan check — leveling in Pure deferred until the USB DAC (its check moves to the DAC); the R1.1-B Pure checks (the row state, the "Volume restored" toast) run on the Mac's built-in output; leveling's by-ear check is on the XM4 in Enhanced.
