# Council stage 3: the duplication pass (charter criterion 3)

Repo `/Users/ramith/code/sound-engineering` @ `main` `7d7c2cd`, read-only. Scratch work in `scratchpad/council/exp-dup/`.
Criterion 3: "No duplicated code or functionality": copy-paste logic AND two ways of doing the same job.

This pass folds in, and re-checks against the code, the duplication notes of `area-bridge.md` (BR-2, BR-8, BR-10, BR-12),
`area-viewmodels.md` (its 8-item list, VM-3, VM-5, VM-8), `area-library.md` (LIB-01, LIB-05, LIB-07, LIB-12, LIB-13, LIB-16)
and `area-build-test.md` (BT-1, BT-2). Each fold-in is marked **verified**, **verified + extended**, or **refuted**.

## Summary

- **Part 1 (tool):** no clone detector was available offline (no `jscpd`, `pmd`/`cpd`, `simian` on PATH or in the npx cache),
  so I wrote a CPD-style token-shingle detector. Over `Sources/` it finds **55 verbatim clone pairs (45 classes)**,
  **297 pairs once literals are normalised**, and **4,165 Type-2 pairs (163 classes)** once identifiers are normalised too;
  3,518 of those Type-2 pairs are inside the `VerifyLibraryStore` harness. Over `Tests/` it finds 187 verbatim pairs
  (53 classes) and 2,096 Type-2 pairs. Across `Sources/`×`Tests/` (production code copied into tests) it finds 42 pairs.
- **Verdict on copy-paste:** production code has little raw copy-paste. Outside the harnesses the verbatim duplication is
  about 730 lines (in 33 classes). The real duplication in this codebase is **semantic**: the same job done two to ten ways, and in most of
  the cases below **the copies have already diverged**.
- **Part 2 (semantic):** 17 findings: 2 STRUCTURAL, 10 SIGNIFICANT, 5 LOCAL. 12 of the 17 show divergence that already exists in the code.

---

## Part 1: tool-assisted copy-paste detection

### 1.1 Tool and settings

- **Script:** `exp-dup/clones.py` (detector), `exp-dup/classes.py` (groups pairs into clone classes),
  `exp-dup/view.py` / `exp-dup/showclasses.py` (inspection). Run from `exp-dup/` (outside the repo) as
  `python3 -I clones.py /Users/ramith/code/sound-engineering --roots Sources --mode weak --out src-weak`, and likewise with
  `--roots Tests`, and `--roots Sources Tests --cross` (only pairs whose two copies are in different roots).
- **Input:** `git ls-files` for `*.swift *.cpp *.mm *.h *.c *.inc`. Comments, `import` / `#include` / `#import` / `#pragma`
  lines are dropped. String literals are lexed whole, including Swift `"""`, raw `#"…"#`, interpolation, C++ `R"(…)"` and `@"…"`.
- **Algorithm:**
  1. Rabin-Karp hash over every window of **K = 40 tokens**.
  2. For every bucket pair that is left-maximal, extend forward while the normalised tokens agree.
  3. Keep matches that are **≥ 40 tokens and ≥ 6 lines in both copies**.
  4. Merge fragments between the same two files that overlap or sit within 12 tokens of each other on both sides
     (near-miss Type-3).
  5. Re-align each clone with `difflib`. **coverage** = matched normalised tokens / span. **similarity** = the share of
     identifier and literal positions whose raw text is identical (1.0 = verbatim).
- **Three normalisation modes:**
  - **strict:** nothing normalised (Type-1).
  - **mild:** literals become `$str` / `$num`; identifiers are kept (copy-paste with changed constants).
  - **weak:** identifiers become `$id` as well (Type-2, CPD's `--ignore-identifiers --ignore-literals`).
- **Kinds:** T1 = sim ≥ 0.98 and coverage ≥ 0.98; T2 = full coverage with renames; T3 = gapped; REP = one file repeating
  itself, an overlapping periodic run such as a table.
- **Clone classes:** connected components over pairs whose regions overlap, so "one block in five files" counts once.

### 1.2 Raw counts

| Scope | Files | Tokens | strict pairs / classes | mild pairs / classes | weak pairs / classes | weak kinds T1 / T2 / T3 / REP |
|---|---|---|---|---|---|---|
| `Sources/` | 577 | 312,093 | **55 / 45** | 297 / 88 | **4,165 / 163** | 7 / 3,922 / 196 / 40 |
| of which `VerifyLibraryStore` only | (44) | | 20 / 12 | 239 / 40 | 3,518 / 23 | |
| of which everything else | | | 35 / 33 | 58 / 48 | 645 / 140 | |
| `Tests/` | 148 | 222,802 | **187 / 53** | 272 / 92 | **2,096 / 156** | 39 / 1,938 / 88 / 31 |
| `Sources/` × `Tests/` cross | 725 | 534,895 | **4 / 3** | 5 / 4 | **42 / 17** | 2 / 33 / 7 / 0 |

How to read it:
- **weak** mode on highly regular code (SwiftUI modifier chains, SQL builders, token tables, `CheckCase` bodies) yields many
  structural look-alikes.
- **strict** and **mild** are the copy-paste signal.
- 15 (Sources) and 8 (Tests) weak hash buckets had more than 60 occurrences and were capped. These are boilerplate windows
  (`static let … = …` runs), not clones.

### 1.3 Hot spots by module (lines inside at least one clone; % of the module's lines)

| Module | LOC | weak dup lines (%) | mild dup lines (%) | strict dup lines (%) | What it is |
|---|---|---|---|---|---|
| `Sources/VerifyLibraryStore` | 10,791 | 4,720 (43.7) | 1,741 (16.1) | 252 (2.3) | ~150 check bodies re-typing one scaffold (open store → make root → write files → scan → `guard … printFail`), plus helpers copied between check files |
| `Tests/` C++ harness (`*.inc`, `TestSupport.h`) | 24,022 | 8,520 (35.5) | 2,547 (10.6) | 1,914 strict total in `Tests/` | kernel set-up / chirp / golden-hash pipelines, signal generators, WAV writers re-inlined per suite |
| `Sources/LibraryStore` | 5,479 | 1,309 (23.9) | 74 (1.4) | 74 (1.4) | parallel read/SQL-builder APIs (mostly benign); the move / play-count / builtin-guard twins (real) |
| `Sources/DesignTokenKit` | 1,694 | 681 (40.2) | 72 (4.3) | 0 | token data tables (benign) |
| `Sources/AudioDSP/AudioEngine` | 2,772 | 501 (18.1) | 266 (9.6) | 213 (7.7) | **the two AU wrappers** and the HAL engine's format tails (real) |
| `Sources/AudioDSP/Spatial` | 569 | 138 (24.3) | 18 (3.2) | 18 (3.2) | two route loops, and the two stub modules |
| `Sources/AudioDSP` (root) | 3,738 | 654 (17.5) | 111 (3.0) | 108 (2.9) | `CoreAudioDevice` HAL boilerplate; FFmpeg dlsym table; decode-backend getters |
| `Tests/LibraryBrowseKitTests` | 3,918 | 1,315 (33.6) | 175 (4.5) | | per-test fixtures (temp dirs, songs) |
| `Tests/AudioViewModelTests` | 2,702 | 891 (33.0) | 154 (5.7) | | mirror set-up repeated per suite |
| `Tests/DesignTokenKitTests` | 3,077 | 884 (28.7) | 250 (8.1) | | the contrast-audit helper re-typed in ~8 files |
| `Sources/AdaptiveSound/UI` | 13,325 | 695 (5.2) | 300 (2.3) | 163 (1.2) | toasts, row chrome, now-playing readouts, keyboard glue |
| `Sources/AdaptiveSound` (root) | 11,865 | 697 (5.9) | 75 (0.6) | 73 (0.6) | bridge: completion closures, tap installers, roll prologues |
| `Sources/VerifyAUGraph` | 1,374 | 262 (19.1) | 33 (2.4) | | its own graph builder, re-done per check |

### 1.4 Triage (every class ≥ 55 tokens or verbatim outside the harness; the rest sampled)

REAL = logic that must change together. BENIGN = boilerplate, data, deliberate parallel structure or fixtures.
GENERATED = machine-shaped tables.

| # | Copies (file:lines) | Tokens / sim | Verdict | Note → finding |
|---|---|---|---|---|
| S1 | `AudioDSP/AudioEngine/AUAudioUnit.mm:54-169, 198-215, 264-288` ↔ `SpatialRendererAU.mm:144-269, 306-354` | 223 / 1.0 (216-token T1 block) | **REAL** | AU v3 scaffold twice: init, kernel capture, busses, allocate-negotiation, `setRequestedSampleRate`, registration. Already diverged (the spatial render block guards `pull == nullptr`; the effects one does not) → DUP-15 |
| S2 | `AudioEngineBridge+Playback.swift:211-223` ↔ `+PureMode.swift:347-359` ↔ `+GaplessRoll.swift:207-215` | 63 / 0.93 | **REAL** | schedule-segment-with-passthrough-epoch completion ×3 (BR-10) → DUP-1 |
| S3 | `+GaplessRoll.swift:34-40` ↔ `:72-78` | 59 / 0.91 (T1 42) | **REAL** | the two roll handlers' prologue → DUP-1 |
| S4 | `AudioEngineBridge+Graph.swift:176-217` (`installBeforeTap` ↔ `installAfterTap`) | 123 / 0.82 (T1 67) | REAL, LOCAL | identical but for the node and the analyzer array → `installPerChannelTap(on:analyzers:)` |
| S5 | `AudioViewModel+AutoAdvance.swift:54-62` ↔ `+Playback.swift:117-125` | 48 / 0.67 | **REAL** | arm-next bookkeeping (VM list item 5) → DUP-12 |
| S6 | `AudioViewModel+SpectrumTimer.swift:17-29` ↔ `:34-42` | 61 / 0.85 | REAL, LOCAL | two 20 Hz `Timer`s (VM-3) → DUP-12 |
| S7 | `UI/EQ/EQBringBackMessage.swift:54-61` ↔ `UI/Shell/ShellToast.swift:116-124` ↔ `UI/Library/QueueRestoreToast.swift:23-31` ↔ `UI/Shell/ErrorBanner.swift:81-88` | 69 / 0.93 (T1 67) | **REAL** | toast chrome ×4, already diverged → DUP-5 |
| S8 | `UI/NowPlaying/HeroBand.swift:27-35, 93-98, 162-176` ↔ `UI/Shell/NowPlayingBar.swift:16-28, 389-394, 423-435` ↔ `MenuBarView.swift:10-19` | 53 / 1.0 | **REAL** | current-track derivation + pulsing status dot → DUP-6 |
| S9 | `UI/Library/NavRow.swift:62-81` ↔ `UI/Playlist/PlaylistItemRow.swift:111-133` ↔ `PlaylistDetailView.swift:297-303` ↔ `UI/Library/LibraryRowChrome.swift:35-45` | 81 / 0.95 | **REAL** | row-card chrome ×3, ring opacities differ → DUP-4 |
| S10 | `UI/Library/LibrarySidebar.swift:286-306` ↔ `UI/Playlist/PlaylistDetailView.swift:150-169` | 67 / 0.80 (T1 43) | **REAL** | per-list keyboard-cursor glue → DUP-4 |
| S11 | `UI/Library/BrowseKeyboard.swift:33-43, 70-86` ↔ `UI/Library/ListSelectionKeyboard.swift:54-65` | 62 / 0.96 | REAL, LOCAL | focus/type-select scaffold of the two keyboard modifiers → DUP-4 |
| S12 | `UI/Library/DetailTrackRow.swift:25-35` ↔ `SongRow.swift:22-33`; `DetailTrackList.swift:64-73, 138-143` ↔ `SongsListView.swift:81-92, 232-239` | 58 / 0.84 (T1 45) | REAL, LOCAL | two song-list implementations (Songs vs detail pages) sharing the modifier but re-typing row content and wiring → DUP-4 |
| S13 | `UI/Library/AlbumArtworkView.swift:25-30` ↔ `UI/Library/BrowseArt.swift:30-35` | 47 / 1.0 | REAL, LOCAL | two artwork views with the same hairline frame |
| S14 | `DesignSystemGlass.swift:157-169` ↔ `DesignSystemGlassControls.swift:51-58, 81-88` | 66 / 0.96 (T1) | REAL, LOCAL | the "carved" capsule ×2 (the shade height is a `2` literal in one and `innerShade = 2` in the other) → DUP-14 |
| S15 | `UI/Loudness/LoudnessMetersView.swift:22-38` ↔ `UI/Playlist/TrackInfoCard.swift:80-87` ↔ `UI/NowPlaying/InspectorColumn.swift:88-98, 145-150` ↔ `MasterGainSliderView.swift:16-26` | 49 / 0.94 | **REAL** | uppercase micro label re-typed; the font has diverged from the token → DUP-7 |
| S16 | `UI/Playlist/AddToPlaylistMenu.swift:42-55` ↔ `:131-147` ↔ `LibrarySidebar.swift:261-266` | 57 / 0.96 | REAL, LOCAL | the playlist-list menu built twice |
| S17 | `UI/Library/LibraryEmptyStateView.swift:23-60` ↔ `LibrarySidebar.swift:112-117`; `LibraryNoResultsView.swift:13-21` ↔ `UI/Playlist/QueueHistoryList.swift:69-77` | 49 / 0.77 | REAL, LOCAL | per-screen empty states (no shared `EmptyState` view) |
| S18 | `UI/Library/ArtistsView.swift:24-39` ↔ `GenresView.swift:21-36` | 94 / 0.69 | BENIGN | two configurations of the shared `BrowseGridRoot` (good) |
| S19 | `UI/EQ/EQDeletePresetDialog.swift:8-18` ↔ `UI/Playlist/PlaylistDeleteDialog.swift:8-18` | 67 / 0.92 | BENIGN | two thin wrappers over the shared `AppDialog` (good) |
| S20 | `Models/LibraryTrackDragItem.swift:8-17` ↔ `PlaylistEntryDragItem.swift:8-17` | 60 / 0.71 | BENIGN | `Transferable` boilerplate |
| S21 | `UI/Tabs/MonitoringTabView.swift:95-100` ↔ `SettingsTabView.swift:22-27`; `UI/Monitoring/MonitorColors.swift:28-36` ↔ `UI/Spectrum/SpectrumColorPalette.swift:13-21` | 65 / 0.58 | BENIGN | tab scaffolding; two cached ramp builders over different token ramps |
| S22 | `LibraryStore/LibraryStore+DAO.swift:198-216, 244-251, 305-314` ↔ `+MoveMatch.swift:72-85, 111-122` | 67 / 0.96 (T1 63) | **REAL** | `moveTrack` vs `moveMatchedLocked` pre-flight + catch-UNIQUE; `upsert` vs `upsertReconciling` loop (LIB-16) → DUP-11 |
| S23 | `LibraryStore/LibraryStore.swift:213-243` | 105 / 0.90 | **REAL** | `incrementPlayCount(url:)` / `(id:)` twins → DUP-11 |
| S24 | `LibraryStore+Playlists.swift:215-221` ↔ `:233-239` | 58 / 1.0 | REAL, LOCAL | "user playlist exists and is not built-in" guard ×2 → DUP-11 |
| S25 | `LibraryStore+BrowseReads.swift:38-235` ↔ `+Reads.swift:29-134`, `+Facets`, `+DAO`, `+Playlists`, `+PlaylistFolders` (classes C14, C24, C32) | 120 / 0.87 | BENIGN (one LOCAL note) | parallel read APIs over one SQL builder. Note: two pagination idioms (`paginationClause` vs `limited:`) |
| S26 | `LibraryStore+FacetDrilldown.swift:70-129`; `+AlbumGrouping.swift:81-99` ↔ `+FacetSweep.swift:24-43`; `Schema.swift` ↔ `Schema+AlbumArtists.swift` | 102 / 0.69 | BENIGN | parallel SQL builders; migration steps |
| S27 | `LibraryStore/LibraryTypes.swift` + 16 files (class C19) | 104 / 0.72 | BENIGN | memberwise inits / `Codable` / `Sendable` value types |
| S28 | `DesignTokenKit/Palette.swift`, `GlassDecor.swift`, `*Layout.swift`, `SpectrumRamp.swift`, `SampledGlow.swift` (C5, C9, C18, C52) | 174 / 0.82 | BENIGN | token data tables |
| S29 | `AudioDSP/Limiting/LimiterModule.h:193-215` ↔ `Loudness/LoudnessModule.cpp:94-116` | 97 / 1.0 (T1) | REAL, LOCAL | `process()` prologue (frames / channels / gather `float*` array). `MultichannelView` should hand out the pointer array |
| S30 | `AudioDSP/FileDecodeSource.cpp:244-264` ↔ `:718-738` | 90 / 1.0 (T1 85) | BENIGN-ish, LOCAL | five identical format getters in the Apple and FFmpeg backends (a shared `SourceFormat` member) |
| S31 | `FileDecodeSource.cpp:351-380, 426-455` | 164 / 0.44 | **GENERATED** | the libav dlsym struct + resolve list (an X-macro would generate both) |
| S32 | `AudioDSP/AudioEngine/HALOutputEngine.mm:682-715` ↔ `:723-753` (+ `149-226`, `578/793`) | 164 / 0.79 (T1 40) | REAL, LOCAL | "copy AU output-scope format to the input scope, read back, cache" ×2 → DUP-15 |
| S33 | `AudioDSP/CoreAudioDevice.cpp:48-139, 196-289, 363-461, 520-547` (C10, C41, C53) | 126 / 0.83 | REAL, LOCAL | HAL get-property boilerplate ×8 (no `getProperty<T>`); see DUP-3 for the semantic copy in `HALOutputEngine.mm` |
| S34 | `AudioDSP/Loudness/ChannelLayoutDecoder.cpp:58-108, 149-237` | 179 / 0.79 | BENIGN | per-layout tables |
| S35 | `AudioDSP/PureModeFormat.cpp:64-95, 120-145, 167-200` | 101 / 0.76 (T1 47) | REAL, LOCAL | int16 / int24 / int32 pack loops ×3 (one template) |
| S36 | `AudioDSP/GaplessSource.cpp:143-155` ↔ `:157-168` | 58 / 0.90 (T1 44) | REAL, LOCAL | slot teardown in `clearNext` / `reapRetired` (a `releaseSlot(Track*)`) |
| S37 | `AudioDSP/Spatial/SpatialRenderKernel.cpp:33-47` ↔ `:76-90` | 76 / 0.92 (T1 56) | REAL, LOCAL | two route loops sharing the copy |
| S38 | `AudioDSP/Loudness/LufsMeter.h:268-275` ↔ `:286-295`; `DSPKernel.cpp:331-339` ↔ `:386-394`; `EQ/GraphicEQDesigner.cpp:108-177` | 64 / 0.90 (T1 57) | BENIGN / LOCAL | parallel per-window updates; solver passes |
| S39 | `AudioDSP/Clarity/ClarityModule.h:6-41` ↔ `Spatial/BRIRModule.h:6-40` | 74 / 0.84 | BENIGN (note) | two identical identity **stubs** (product.md: wet stages are placeholders) |
| S40 | `AudioDSP/EQ/EQDesignBridge.cpp:44-54` ↔ `Loudness/TrackLoudnessBridge.cpp:154-163` | 48 / 0.92 | REAL, LOCAL | `asLoudnessPredictChangeDb` re-runs the design; that C-ABI has **no production caller** (tests and the leak harness only) → DUP-15 |
| S41 | `AudioDSP/` headers ×14 (class C47) | 76 / 0.79 | BENIGN | deleted copy/move + atomics boilerplate |
| S42 | `LibraryScan/FileSignature.swift:63-71` ↔ `VerifyLibraryStore/ScanFixtureBuilder.swift:165-171` | 43 / 1.0 (T1) | REAL, LOCAL | the harness re-implements the stat → (dev, inode) read it should call → DUP-13 |
| S43 | `AdaptiveSound/EQDesigner.swift:34-42` ↔ `VerifyAUGraph/VerifyEQReallocation.swift:56-64`; `AudioEngineBridge+Graph.swift:71-85` ↔ `VerifyAUGraph/VerifyMultichannel.swift:59-67`; `VerifyAUGraph` internal (C36, C99, C135) | 87 / 0.88 | **REAL** | `VerifyAUGraph` re-wraps the design C-ABI and builds its own graph, not the bridge's → DUP-13 |
| S44 | `AdaptiveSound/Spectrum/SpectrumAnalyzer.swift:214-226` ↔ `SRCQualityMeasure/Spectrum.swift:65-76` | 70 / 0.77 | REAL, LOCAL | the measuring tool replicates the production analyzer and resampler setup (BT note) |
| S45 | `AdaptiveSound/Debug/*` (SheetFixture, SheetVariant) | 96 / 0.95 | BENIGN | fixtures |
| S46 | `VerifyLibraryStore` class C1 (40 files, 3,475 pairs) | 276 / 1.0 | BENIGN pattern, REAL helpers | no fixture DSL: the same 6–10-line scaffold in ~150 checks. Also verbatim private helpers copied between check files (`makeSolidPNG` in `ChecksArtworkCache.swift:74-97` and `ChecksArtworkMap.swift:106-129`; `ChecksMoveMatch.swift:22-40` ↔ `ChecksPlaylistScan.swift:27-44`) → DUP-13 |

**Tests, verbatim classes (top):**

| # | Copies | Tokens | Verdict | Note |
|---|---|---|---|---|
| T1 | `Tests/CrossfeedTests.inc:95-154` ↔ `MultichannelTests.inc:35-102` ↔ `DspBypassTests.inc:187-214` | 461 | **REAL** | the golden-master pipeline (chirp, kernel set-up, FNV hash) and **the committed hash `0xE7AF0C67F9340785` in two files**: a re-baseline must edit both |
| T2 | `Tests/LimiterTruePeakTests.inc:137-158`, `LoudnessOracleTests.inc:50-72`, `MultichannelTests.inc:580-614`, `LoudnessTests.inc:24-30`, `lufs-tool.cpp:81-86` | 149 | REAL, LOCAL | in-phase stereo sine generator ×5; `TestSupport.h` has none |
| T3 | `Tests/FileDecodeTests.inc:38-72` ↔ `:288-322` (+ `1548-1570` ↔ `2047-2069`, `1673-1717` ↔ `2194-2238`) | 316 | REAL, LOCAL | two WAV writers (int16 / float32) and repeated decode-and-compare blocks in one file |
| T4 | `Tests/GaplessContractTests.inc:81-432` ↔ `SoakRtAllocTests.inc:421-431`; `GaplessContractTests` ↔ `PureGaplessTests.inc:396-413` | 151 | REAL, LOCAL | Pure gapless source set-up re-inlined |
| T5 | `Tests/DspBypassTests.inc` ↔ `LimiterTests.inc:30-55`; `LimiterTests.inc:99-318` ↔ `MultichannelTests.inc:396-1243` ↔ `TestSupport.h:384-389` | 104 | REAL, LOCAL | kernel / limiter set-up re-inlined next to an existing `TestSupport` helper |
| T6 | `Tests/EqEngineBreakItMeasurements.inc:1440-1455` ↔ `EqEngineFixTests.inc:979-994` (+ 4 other EQ pairs) | 186 | REAL, LOCAL | the gated suite and the un-gated measurement suite share code by copying |
| T7 | `Tests/DesignTokenKitTests/*AuditTests.swift` (8 files, class C15 / C31) | 137 | REAL, LOCAL | the contrast-assert helper re-typed per audit |
| T8 | `Tests/LibraryBrowseKitTests/GridKeyboardCursorTests.swift` ↔ `ListKeyboardCursorTests.swift`; `ListSelection*Tests` | 96 | BENIGN | parallel suites for parallel types |
| T9 | `Tests/AudioViewModelTests/AutoAdvance*Tests.swift` + `AudioViewModelTests.swift` (class C34) | 90 | BENIGN (symptom) | per-suite mirror set-up (the mirror is the issue, DUP-2) |
| T10 | `Tests/*.inc` constant blocks (class C3: `MultichannelTests.inc:1296-1486`, `TestSupport.h:85-142`) | 331 | BENIGN | `constexpr` tables (structure only, sim 0.67) |

**Production code copied into tests (cross run):**

| # | Copies | Tokens / sim | Verdict |
|---|---|---|---|
| X1 | `Sources/AudioDSP/Loudness/LufsMeter.h:179-200, 352-386` ↔ `Tests/MultichannelTests.inc:665-798` | 282 / 0.875 | **REAL (oracle independence).** The "in-file BS.1770 oracle" (`makeOracleKWeight`) is the production K-weighting re-typed with the **same production constants** (`kKwShelfF0Hz`, `kKwShelfQ`, …). A wrong constant passes both → DUP-13 |
| X2 | `Sources/AdaptiveSound/AudioViewModel+Queue.swift:89-97, 178-184`, `+Playlist.swift:99-108`, `+AutoAdvance.swift:92-106` ↔ `Tests/AudioViewModelTests/MockAdvanceController.swift:191-318` | 49 / 0.95 | **REAL, drifted** → DUP-2 |
| X3 | `Sources/AdaptiveSound/SignalPathInfo.swift:44-67` ↔ `Tests/AudioViewModelTests/MockAudioEngine.swift:21-29` | 42 / 0.72 | **REAL, drifted** → DUP-2 |
| X4 | `Sources/AdaptiveSound/Debug/SplitMix64.swift:7-21` ↔ `Tests/AudioDSPTests/EQTests+Helpers.swift:52-66` | 70 / 0.96 | REAL, LOCAL (the app can't be imported, so the RNG is copied) |
| X5 | `Sources/VerifyLibraryStore/ChecksWalkOverlap.swift:37-43` ↔ `Tests/LibraryBrowseKitTests/LibraryBreakItGTests.swift:63-69` | 56 / 0.90 | REAL, LOCAL (one walk fixture in two harness cultures, BT-2) |
| X6 | `Sources/AudioDSP/FileDecodeSource.cpp:171-179, 226-232, 299-306` ↔ `Tests/FileDecodeTests.inc:42-60, 292-328` | 65 / 1.0 | BENIGN (CFURL / ExtAudioFile boilerplate in a test WAV writer) |
| X7 | `PureModeFormat.cpp`, `GraphicEQBands.h`, `AudioConstants.h`, `RtSwappableResource.h` ↔ `TestSupport.h` / `*.inc` (sim 0.0) | ≤ 76 | BENIGN (structural only: constant tables, guard prologues) |

**Triage totals (Sources, non-harness, 140 weak classes):** about 34 REAL (11 of them significant enough to feed Part 2;
23 LOCAL extract-a-helper items), about 104 BENIGN (tables, parallel APIs, boilerplate, fixtures), 2 GENERATED-style.
The tool's yield is modest. Part 1 mainly locates *where* the semantic duplication of Part 2 has left textual traces.

---

## Part 2: semantic duplicated capability

Severity counts: **STRUCTURAL 2 · SIGNIFICANT 10 · LOCAL 5.** Ordered by risk, divergence that already exists first.

### DUP-1 Two transport engines, and inside Enhanced four "restart at X", three seek paths and three completion closures, STRUCTURAL. Criteria: 3, 1, 4
- **Evidence (BR-2 / BR-8 / BR-10, verified + extended):**
  - **Restart at X ×4:**
    1. `startAudio(startAt:)` → `playFile` (`AudioEngineBridge+Playback.swift:180-224`);
    2. `seek` → `seekEnhancedBestEffort` / `seekEnhancedResampler` (`+PureMode.swift:173-240`, `+EnhancedResampler.swift:177-216`);
    3. `reestablishEnhancedAfterConfigChange` → the same helpers, on `configChangeQueue` (`+ConfigChange.swift:97-120`);
    4. Pure move at the playhead, owned by the **view model** (`AudioViewModel+Devices.swift:80-93`, `startPlayback(resumeFrom:)`).
  - **Completion-with-epoch closure ×3, near-verbatim** (clone S2, sim 0.93): `+Playback.swift:211-223`,
    `+PureMode.swift:347-359`, `+GaplessRoll.swift:207-215`.
  - **The copies already disagree on the same input:**
    - *Out of range.* `playFile`'s private `startFrame` clamps an out-of-range start to the last frame and rejects
      non-finite input (`+Playback.swift:276-280`: `guard seconds > 0, seconds.isFinite …; min(…, file.length - 1)`).
      The seek helpers instead **silently do nothing** out of range (`+PureMode.swift:329-331`, `+EnhancedResampler.swift:200-202`).
    - *Non-finite input.* The seek helpers compute `AVAudioFramePosition(seconds * sampleRate)` with no finiteness check;
      a NaN traps in Swift's integer conversion.
    - *Position base.* `seek` writes the base **before** the reschedule and keeps it on failure (BR-8). Re-establish writes
      it **after** (`+ConfigChange.swift:118`).
    - *Error.* Pure throws `seekFailed`; both Enhanced variants never do.
  - **Gapless twice:**
    - Pure: `GaplessSource` (C++, render-side frame accounting, atomic seam, `ended`).
    - Enhanced: two EOF hooks + four roll variants + a `playFile` fallback on a global queue (`+GaplessRoll.swift`);
      two end flags (`gaplessEndedFlag` vs `pureModeEnginePlaybackEnded`); two invalidation generations
      (`resampleGeneration`, `passthroughGeneration`) for one job ("ignore completions of a superseded schedule").
    - The roll prologue is itself duplicated (clone S3).
- **Root cause:** the Enhanced path delegates the audio queue to `AVAudioPlayerNode`'s schedule. Every operation therefore
  re-derives position, seam and schedule (BR-2), and the "restart" policy ended up split between bridge and VM.
- **Why it matters:** every transport bug fix has to land in up to four places. The divergence above (clamp vs ignore,
  finite-check vs trap, base before vs after) is exactly how wrong-song / scrubber-jump bugs reappear. R2 transport
  features (crossfade, A-B repeat, ReplayGain seams) would multiply it.
- **Structural remedy:**
  - **Target:** one transport model for both paths (BR-2: `AVAudioSourceNode` pulling the same `FileDecodeSource` +
    `GaplessSource` ring Pure uses; SFBAudioEngine's `AudioPlayer` is the opened reference).
  - **Interim, valuable on its own:** one `restart(at: FramePosition, epoch:)` command on the engine domain, used by
    start-with-offset, seek, re-establish and the Pure device move. It takes a validated `FramePosition` type (finite,
    clamped once, the same rounding on both paths) and returns a typed result. Plus one `scheduleSegment(…, epoch:)`
    helper that owns the completion closure.
- **Effort:** M (interim) / L (BR-2). **Risk:** med / high. **Depends on:** BR-2, BR-3, BR-8.

### DUP-2 Test mirrors of app logic, already drifted, and two fakes of the engine, STRUCTURAL. Criteria: 3, 6
- **Evidence (VM-8 / BT-1, verified + extended):**
  - Append still dedupes in the mirror (`Tests/AudioViewModelTests/MockAdvanceController.swift:307-325`,
    `dedupedAgainstQueue`), while production dropped dedupe (`AudioViewModel+Queue.swift:17-19, 173-187`).
  - The `playTrack(at:)` copy lacks `resumePoint = nil` (`Tests/AudioViewModelTests/AudioViewModelTests.swift:20-24`
    vs `+Transport.swift:10-15`).
  - **New:**
    - `SignalPathInfoMirror` (`MockAudioEngine.swift:21-32`) carries two fields production no longer has
      (`exclusiveHog`, `rateMatched`) and lacks five it has (`interrupted`, `deviceVolume`, `deviceVolumeSet`,
      `intensityLinear`, `crossfeedStrength`; `SignalPathInfo.swift:52-95`).
    - The protocol mirror says of itself "models the engine's state; NOT the current protocol's shape"
      (`MockAudioEngine.swift:34-40`).
    - There are **two fakes of one protocol**: `Debug/SheetEngine` conforms to the real `AudioPlaybackEngine`;
      `MockAudioEngine` conforms to the mirror.
- **Root cause:** the belief that the executable target can't be imported by tests (VM-8 showed it can, on this toolchain,
  for a plain target). Logic copied to be testable, then the original kept moving.
- **Why it matters:** N12–N21 (transport epochs, auto-advance, queue verbs) are "proved" against code that no longer ships.
  Tests VM-Q-11 and VM-Q-13..15 assert retired behaviour.
- **Structural remedy:** test the real `AudioViewModel` against one `FakeEngine: AudioPlaybackEngine` (promote
  `SheetEngine`), and delete the mirror types. If the bridging flags block `@testable import`, extract the model layer
  into a library target (VM-8 step 3).
- **Effort:** S spike / M migration. **Risk:** low. **Depends on:** VM-8, BT-1.

### DUP-3 Output-device facts are classified and read in four places with different partitions and failure values, SIGNIFICANT. Criteria: 3, 4
- **Evidence:**
  - **Four transport-type classifiers:**
    1. `CoreAudioDevice::classifyDeviceType` (`AudioDSP/CoreAudioDevice.cpp:321-345`): BT, BT-LE and **AirPlay** →
       `Wireless`, USB, BuiltIn, else a **name heuristic** ("AirPods", "Bluetooth").
    2. Capability booleans `isLossyWireless` / `isVirtualOrAggregate` (`:499-505`), which feed the Pure policy.
    3. `eqOnlyCeilingLinear` (`Limiting/OutputCeiling.h:24-40`): a wired list (BuiltIn, USB, FireWire, TB, PCI, HDMI,
       DP, AVB), else the lossy ceiling.
    4. `AudioViewModel.deviceIsHeadphones` (`AudioViewModel.swift:166-171`): `.wireless || .usb`, derived from (1)
       and documented as a heuristic.
  - **Two nominal-rate readers with different failure semantics:**
    - `CoreAudioDevice::getDeviceSampleRate` (`CoreAudioDevice.cpp:246-265`): scope *Output*; on failure it logs and
      returns **48 000**, and that value becomes `cap.currentRate` for the Pure decision (`:489`).
    - `HALOutputEngine.mm:279-293 getNominalRate`: scope *Global*; on failure returns **0**.
  - **HAL property access in three layers:** `CoreAudioDevice.cpp` (17 calls), `HALOutputEngine.mm` (12, overlapping on
    `NominalSampleRate`, `Streams`, `PhysicalFormat`, `VirtualFormat`), and Swift (`+MasterGain.swift` volume reads,
    `+OutputDeviceMonitor.swift` alive / default / device-list).
  - **"Make X the output" three ways:** `selectDevice` (`+Devices.swift:91-106`, bypasses `OutputDevicePolicy`),
    `applyTargetChange` (`+OutputDeviceMonitor.swift:151-160`), `alignOutputForEnhancedStart` (`:137-147`).
  - **Validity by string compare:** `selectOutputDeviceC` checks validity by comparing against the literal
    `"Unknown Device"` that `CoreAudioDevice` returns (`AUAudioUnit.mm:341` ↔ `CoreAudioDevice.cpp:235`).
  - The `CADefaultDeviceAggregate-` prefix ×2 (`DeviceListPolicy.cpp:26`, `EQOutputKey.swift:33`; known from the map,
    tied only by a comment).
- **Divergence already present:**
  - An **AirPlay speaker counts as "headphones"**, so crossfeed stays enabled on it. A USB interface to monitors also
    counts.
  - An HDMI output is `unknown` type (sorted last; never "headphones") but "wired" for the ceiling.
  - A failed rate read tells the bit-perfect policy the device runs at 48 kHz.
- **Root cause:** no single "output facts" value. Each consumer re-derives what it needs from raw transport / name.
- **Why it matters:** crossfeed, limiter ceiling, Pure viability and the device menu can each disagree about the same
  device. R2's per-output profiles need one classification.
- **Structural remedy:**
  - One `OutputFacts` read once per device in C++ (`transportClass: wired/wireless-lossy/virtual/unknown`, `isHeadphone:
    Bool?` from `kAudioDevicePropertyDataSource` where available, `nominalRate: optional`), carried in `CDeviceInfo` →
    `AudioDeviceModel`.
  - Every consumer derives from it (policy in `OutputDeviceKit`).
  - One `getProperty<T>(object, selector, scope)` helper returning `std::optional` (no silent 48 k).
  - User pick goes through `OutputDevicePolicy` as an event like the others.
- **Effort:** M. **Risk:** low-med. **Depends on:** none (the algorithm panel for N92–N97).

### DUP-4 Track lists, row chrome, keyboard handling and song menus are per-screen copies that have already diverged, SIGNIFICANT. Criteria: 3, 1
- **Evidence:**
  - **Track-list implementations ×4:** Songs (`UI/Library/SongsListView.swift`), detail pages (`DetailTrackList.swift`),
    playlist page (`UI/Playlist/PlaylistDetailView*.swift`), queue (`UI/Playlist/PlaylistItemList.swift`).
  - **Row-card chrome ×3** (clone S9): `LibraryRowChrome.swift:20-50`, `NavRow.swift:55-84`, `PlaylistItemRow.swift:105-135`
    (+ `PlaylistDetailView.swift:297-303` re-typing `PlaylistItemRow`'s metrics).
    - Two metric systems: `LibraryRowSize` vs `DesignSystem.QueueRow`.
    - **The "playing / active row" ring opacity differs per copy:** 0.36 (`LibraryRowChrome.swift:28`), 0.30
      (`NavRow.swift:68`), 0.38 (`PlaylistItemRow.swift:129`). Other accent rings add 0.35 (`NowPlayingTabView.swift:93`)
      and 0.28 (`HeroBand.swift:198`); none is a token.
  - **Keyboard:**
    - `ListSelectionKeyboard` (Home/End/PageUp/PageDown, type-select, ⌘A, Esc, ⌘↩, ⇧⌘↩, ⌘I) serves Songs and the detail
      pages only.
    - Sidebar, playlist page, queue and EQ presets hand-roll ↑/↓ + Return (`LibrarySidebar.swift:286-310`,
      `PlaylistDetailView.swift:150-175`, `PlaylistItemList.swift:232-250`, `EQPresetList.swift:31`).
    - **The key-repeat fix was applied to some copies only:** `BrowseKeyboard` / `ListSelectionKeyboard` /
      `PlaylistDetailView` handle Return on `phases: .down` ("a held Return must not open again and again"), but
      `LibrarySidebar` uses `onKeyPress(keys: [.return])` and `PlaylistItemList` uses `onKeyPress(.return)` (default
      phases include `.repeat`).
  - **Song context-menu verbs ×3:**
    - `LibrarySongMenu.swift:27-35`: Play, Play Next, Add to Queue, Add to Playlist, Info.
    - The playlist page's inline menu (`PlaylistDetailView.swift:249-257`): Play, Play Next, move, Remove. **No Add to
      Queue, Add to Playlist or Info for the same song.**
    - The queue's `queueRowMenu` (`PlaylistItemList.swift:180`).
- **Root cause:** the kit owns the pure decisions (`ListKeyboardCursor`, `ListSelection`), but there is no shared *view*
  component for "a list of songs". Each screen assembles one, and fixes land where the bug was seen.
- **Why it matters:** the charter's own example of tactical duplication ("per-view copies of a control"). Users get
  different keys and verbs for the same object depending on the tab. Accessibility and selection fixes have to be
  re-applied four times.
- **Structural remedy:**
  - One `SongList` component (rows + `LibraryRowChrome` + `ListSelectionKeyboard` + one `SongMenu` builder taking a
    capability set: `canReorder`, `canRemove`), used by Songs, detail, playlist and queue.
  - Row ring / fill as tokens in `DesignTokenKit` (one `rowNowPlayingRing` value).
  - Sidebar and EQ preset list adopt `ListSelectionKeyboard` (single-select mode).
- **Effort:** M. **Risk:** med (UI regressions, but the sheets + songs-perf harness catch layout). **Depends on:** none.

### DUP-5 Four transient-message components with two timers and diverged chrome, SIGNIFICANT. Criteria: 3, 1
- **Evidence:** clone S7.
  - `ShellToastSlot`/`ShellToastHost` (`UI/Shell/ShellToast.swift:14-135`) is shared by three slots (good), but:
    - `QueueRestoreToast` (`UI/Library/QueueRestoreToast.swift:16-34`) re-types the capsule with **`.glassPanel(.overlay(.bar))`
      and a literal `lineWidth: 0.5`**, while the host and the EQ capsule use `.overlay(.ultraThin)` and
      `DesignSystem.ShellMetrics.hairline`. It also has no VoiceOver announcement and no Reduce Motion branch.
    - `EQBringBackMessage` (`UI/EQ/EQBringBackMessage.swift:45-90`) runs its **own** countdown (`ContinuousClock`,
      pause-on-hover, resume remaining) instead of `ShellToastSlot`'s dismiss task.
  - `ErrorBanner` (`UI/Shell/ErrorBanner.swift:60-91`) is a fourth chrome.
- **Root cause:** `ShellToastSlot` arrived after two of them; the host has no action-button or pause variant, so new
  toasts copy the chrome.
- **Why it matters:** three looks and two timing behaviours for one concept; hover-pause and announcement fixes reach only
  some.
- **Structural remedy:** one `TransientMessage` model (message, optional action, lifetime, pause-on-hover, announce) +
  one host view with an `action` slot. `QueueRestoreToast` and `EQBringBackMessage` become slots. The substrate and
  hairline come from tokens only.
- **Effort:** S. **Risk:** low.

### DUP-6 "What is playing" is derived about ten times and the signal-path status is rendered twice, differently, SIGNIFICANT. Criteria: 3, 1
- **Evidence (VM list item 1, verified + extended: 10 sites, not 6):**
  - `guard let index = selectedTrackIndex, index < …count` appears in `NowPlayingBar.swift:19-24`, `HeroBand.swift:27-31`,
    `MenuBarView.swift:12-17`, `NowPlayingTabView.swift:54-57`, `NowPlayingController.swift:179, 325, 344`,
    `AudioViewModel+PlayingTrack.swift:11`, `+PlayTracking.swift:38`.
  - **Divergence already present:**
    - Only `selectedSlotID` checks `>= 0` (`AudioViewModel.swift:315-317`).
    - `NowPlayingController.updateCommandEnablement` enables Play / Toggle on `selectedTrackIndex != nil` with **no
      range check** (`:308`), so Control Center can offer Play for an index past the queue end.
  - **Signal-path status twice** (clone S8):
    - `HeroBand` says **"Device disconnected"**; its dot is amber only on fallback, else `accentBright`.
    - `NowPlayingBar` says **"Disconnected"**; its dot is amber on fallback **or** interrupted, `accent` on Pure, else
      `accentBright` (`NowPlayingBar.swift:395-442`).
    - The pulse gates also differ.
    - The spoken texts are built separately (`HeroBand.swift:231`, `NowPlayingBar.swift:445-452`).
- **Root cause:** no "now playing" projection on the VM (VM-6) and no presentation model for the signal path; each view
  re-derives from raw VM state.
- **Why it matters:** the same state reads differently in the footer and the hero. Remote-command enablement can disagree
  with the UI.
- **Structural remedy:**
  - `AudioViewModel.nowPlaying: NowPlayingItem?` (one guarded derivation, also used by `NowPlayingController`).
  - A pure `SignalPathPresentation(info, isPlaying, reduceMotion) → (word, dotColorToken, pulses, spokenText)` in a kit,
    unit-tested, used by both views.
- **Effort:** S. **Risk:** low. **Depends on:** VM-6.

### DUP-7 Formatters exist but are bypassed: sample rate ×5, placeholders ×3, the micro label in two fonts, SIGNIFICANT. Criteria: 3
- **Evidence:**
  - **Rate:**
    - `SignalPathInfo.rateString` calls itself "the app's one rate formatter" (`SignalPathInfo.swift:101-118`;
      `AudioDeviceModel.swift:66-72` uses it).
    - But `Helpers/QualityFormatter.swift:9-15`, `UI/Playlist/TrackInfoCard.swift:214-225`,
      `UI/Library/SongsColumnModel.swift:60-63` and `UI/EQ/EQReadout.swift:16,38` each format kHz themselves.
    - **They disagree:**
      - `String(format: "%.1f")` (always ".") vs `.formatted(.number.precision…)` (locale decimal: "44,1 kHz" in a German
        locale, in the Songs column next to "16/44.1" in the Quality column).
      - Only `TrackInfoCard` shows "Hz" below 1 kHz.
      - Unknown is "-- kHz", "" or "unknown rate".
  - **Duration:**
    - One `formatDuration` (good), but the unknown placeholder is "--:--" (`NowPlayingBar.swift:242`,
      `PlaylistItemRow.swift:107`), "" (`SongsColumnModel.swift:58`) or a bare "0:00" (`DetailTrackRow.swift:61`).
    - The spoken form is `spokenDuration` for Songs rows but `formatDuration` ("1:13 of 3:45") in the footer's
      accessibility value (`NowPlayingBar.swift:358`).
  - **Uppercase micro label:**
    - `DesignSystem.Font.micro` is documented "pair with `.tracking(0.5).textCase(.uppercase)`"
      (`DesignSystem.swift:179-180`) and used by `MonitorStageView.swift:22`.
    - Five sites use `.caption.weight(.semibold)` instead: `InspectorColumn.swift:91, 147`,
      `MasterGainSliderView.swift:19`, `TrackInfoCard.swift:82`, `LoudnessMetersView.swift:24`. **The same label renders
      at two sizes.**
  - A second colour vocabulary, `Color.as*` aliases (`Color+Brand.swift:11-25`, 10 files), sits beside
    `DesignSystem.Color` (273 uses).
- **Root cause:** helpers live in the app target as free functions or statics with no ownership rule. Semgrep bans colour
  literals, but not ad-hoc formatting or fonts.
- **Why it matters:** inconsistent display and VoiceOver output for the same value, and locale bugs. Every new surface
  picks a different helper.
- **Structural remedy:**
  - A `DisplayFormat` namespace in a kit (pure, unit-tested, locale-injected): `rate(_:)`, `rateSpoken`,
    `duration(_:, unknown:)`, `durationSpoken`, `quality(…)`.
  - A `.microLabel()` modifier.
  - Retire the `Color.as*` aliases.
  - A semgrep rule against `String(format:` and `" kHz"` outside the kit.
- **Effort:** S. **Risk:** low.

### DUP-8 Async coordination is re-implemented per site: 8 newest-wins loaders, 4 debouncers, 3 latest-value slots, SIGNIFICANT. Criteria: 3, 1, 2
- **Evidence (LIB-01, LIB-12, BR-12, verified + extended):**
  - **Loaders:** `loadRoots` (`LibraryBrowseModel.swift:233-239`), `loadAlbums` (`:260-289`), `loadSongs` (`:294-325`),
    `runFilter` (`:360-370`), `loadFlatFacet` ×2 (`+Facets.swift:60-105`), `loadHistory` (`+History.swift:10-27`),
    `PlaylistsModel.loadTree` (`:108-131`), `loadDetail` (`:245-275`).
    - 9 hand-rolled `Int` epochs, while **`LibraryBrowseKit.SearchEpoch`** (a tested newest-wins type,
      `SearchFilterDecisions.swift:9-28`) is used once.
    - The generic `loadFlatFacet` (written "ONCE so that newest-wins is correct by construction") serves 2 of the 8.
    - Two `LoadState` enums (`LibraryBrowseModel.swift:20-27` with `firstRun`, `PlaylistsModel.swift:25-31` without).
    - The copies differ: albums / songs / facets re-guard after the second `roots()` await; history / tree have no
      first-run state.
  - **Debounce ×4:**
    - Queue mirror: `Task` + sleep 250 ms, not cancellable after the sleep, so a debounced write and the quit flush can
      both be in flight (`AudioViewModel+QueueMirror.swift:25-31`).
    - Reconcile: `Task.sleep(1000)` per folder (`LibraryModel+Reconcile.swift:110-118`).
    - Songs filter: `.task(id:)` + 120 ms (`UI/Library/SongsView.swift:32-37`).
    - **`CoalescingWriter`** (a kit type, tested, used only by `PlaylistsModel.orderWriter`).
  - **Latest-value slot + one drain ×3:** Realizer pending slots (C++), `requestDeviceVolume` (`+MasterGain.swift:44-68`),
    `CoalescingWriter`. Enhanced Master Gain does **not** use it: a FIFO `engineQueue.async` per slider tick (`:24-29`, BR-12).
- **Root cause:** primitives were extracted to kits for the case at hand, but older and newer sites were not moved onto them.
- **Why it matters:** every new list or writer copies a subtle two-await race guard. Behaviour already differs per list.
  The queue mirror has an unproven ordering (LIB-12).
- **Structural remedy:**
  - One `LoadSlot<Value>` (state + cancellable `Task`; GRDB reads are cancellable) or GRDB `ValueObservation` (LIB-01),
    with one `LoadState`.
  - One `Debouncer` / `CoalescingWriter` used by the queue mirror, reconcile and filter.
  - One `LatestValueSink<Value>` used by device volume and Enhanced gain.
- **Effort:** M. **Risk:** med (loaders) / low (writers). **Depends on:** LIB-01.

### DUP-9 Three text-matching semantics and three gating policies for "filter this list", SIGNIFICANT. Criteria: 3, 1
- **Evidence (LIB-05, verified + extended):**
  - Songs: FTS5 prefix-AND tokens (`LibraryStore+Search.swift:42-48`, `searchMatchingIDs`). Gated at ≥ 2 chars
    (`SearchQueryGate`) and debounced 120 ms.
  - Albums / Artists / Genres grids: `FacetTextFilter` substring, `localizedStandardContains`, any length, no debounce
    (`UI/Library/BrowseGridRoot.swift:53-54`).
  - Queue: the same substring rule but **title only** (`UI/Playlist/PlaylistView.swift:153`, `file.name`).
  - A third, bm25-ranked `search()` has no app caller.
  - Typing "ear" finds Pearl Jam in Artists but not in Songs. A queue filter for an artist name finds nothing.
- **Root cause:** each list chose its own matcher; no product rule for "search".
- **Why it matters:** inconsistent results by tab; three paths to maintain; blocks an R2 global search.
- **Structural remedy:** decide one semantic (founder), then one `LibraryMatcher` (FTS-backed for the library, an
  in-memory equivalent for the queue that tokenises the same way) and one gate / debounce policy. Delete the dead
  `search()` or adopt it.
- **Effort:** S–M. **Risk:** low. **Depends on:** a product decision.

### DUP-10 Library rules held in two layers: album year (opposite ties), playlist reorder, title fallback ×4, album folder, SIGNIFICANT. Criteria: 3, 4
- **Evidence (LIB-13, LIB-07, map; verified, one part refuted):**
  - **Album year:**
    - `AlbumGrouping.dominantYear` ties to the **latest** (`LibraryStore/AlbumGrouping+Years.swift:22-31`; it writes
      `al.year`).
    - `FacetAlbumGrouping.albumYear(of:)` ties to the **earliest** (`LibraryBrowseKit/FacetAlbumGrouping.swift:96-108`).
    - The kit rule runs only when `albumYear` is 0 / nil but songs carry years, so the conflict is latent. Two
      implementations of one concept, tied by nothing.
    - The kit already imports `LibraryStore` and `dominantYear` is `public`, so the fix is a one-line call.
  - **Reorder:** `ListOrder.applying` (`LibraryBrowseKit/ListOrder.swift:1-17`) and `reorderPlaylist`
    (`LibraryStore+Playlists.swift:367-377`) are the same rule written twice. The kit's doc says "Keep the two rules in
    step"; no test compares them.
  - **Title fallback ×4:** `COALESCE(NULLIF(title,''), name)` in `LibraryStore+SearchIndex.swift:29`,
    `Schema.swift:265`, `LibraryStore+BrowseReads.swift:304`, plus the Swift decode (`BrowseReads.swift:22-35`).
  - `selectTrackIDByURLSQL` is defined twice (`+DAO.swift:47`, `+MoveMatch.swift:27`).
  - **Refuted:** LIB-13's "disc-folder parsing ×2". The kit's `DiscFolder` calls the store's
    `AlbumGrouping.discNumber(ofFolderName:)` (`LibraryBrowseKit/LibraryTrackDisplay+DetailTrack.swift:13`), so there is
    one parser (good). What *is* duplicated is the **album-folder** derivation: the kit takes the disc folder's parent;
    the store's `albumFolder(ofTrackPath:)` (`AlbumGrouping+Names.swift:47-60`) also folds bonus folders. They can differ
    for `Set/CD 1/Bonus/x.flac`.
- **Root cause:** `LibraryStore` cannot import the kit, so rules the kit needs in memory were re-typed instead of being
  made public in the store (or a lower `AlbumKit`).
- **Why it matters:** album ordering and year can differ between the grid and the pages. Reorder correctness rests on a
  comment.
- **Structural remedy:**
  - Store-owned public pure functions (`AlbumGrouping.dominantYear`, `albumFolder`, a generic `OrderRule.apply`) called
    by both layers.
  - The title fallback as one SQL view or generated column (LIB-07).
  - A cross-test only where a rule must exist in SQL and Swift.
- **Effort:** S. **Risk:** low. **Depends on:** none. Panel: N49–N52, N76, N78.

### DUP-11 Store write twins: move ×2, play-count ×2, the built-in guard ×2, upsert loops ×2, LOCAL. Criteria: 3
- **Evidence (LIB-16, verified):**
  - `moveTrack` (`LibraryStore+DAO.swift:236-252`) vs `moveMatchedLocked` (`+MoveMatch.swift:106-124`): the same
    pre-flight `selectTrackIDByURLSQL` + `URLConflict` + catch `SQLITE_CONSTRAINT`.
  - `upsert` vs `upsertReconciling` batch loops.
  - `incrementPlayCount(url:)` / `(id:)` (`LibraryStore.swift:211-238`; the app uses `url:` only as a fallback,
    `+PlayTracking.swift:73`).
  - The built-in guard in `renamePlaylist` / `deletePlaylist` (`+Playlists.swift:215-239`).
- **Remedy:** `relocate(db, id:, to key:, …)` as the one move primitive; `recordPlay(db, trackID:)` with url→id inside;
  `requireUserPlaylist(db, id)`. **Effort:** S. **Risk:** low.

### DUP-12 View-model transport bookkeeping repeated: three 20 Hz loops, track-change resets ×4, play counting ×4, LOCAL. Criteria: 3, 1
- **Evidence (VM list items 2, 3, 5, 7, verified):**
  - **Polling loops:** two `Timer`s at `1.0 / 20.0` (`AudioViewModel+SpectrumTimer.swift:18, 35`) plus
    `MonitoringViewModel`'s `Task.sleep(50 ms)` loop reading the engine directly (`UI/Monitoring/MonitoringViewModel.swift:47-56`).
  - **"Zero position / duration, refresh duration, re-arm next"** in `handleTrackTransition` (`+AutoAdvance.swift:37-62`),
    the reconfigure advance (`+SpectrumTimer.swift:109-120`), `removeTrack` (`+Playlist.swift:85-87`) and `startPlayback`
    (`+Playback.swift:37, 110-125`).
  - **`countPlayIfNaturalEndQualifies()`** at 4 sites with the same "before the index moves" rule
    (`+AutoAdvance.swift:27, 37`, `+SpectrumTimer.swift:113, 126`).
- **Remedy:** a `trackBecameCurrent(_:reason:)` transition (VM-2's reducer) owning all of it, and one engine-sampling
  loop publishing to subscribers (VM-3). **Effort:** S–M. **Risk:** med. **Depends on:** VM-2, VM-3.

### DUP-13 Test infrastructure: five harness cultures, helpers copied instead of shared, an "oracle" copied from production, SIGNIFICANT. Criteria: 3, 6, 4
- **Evidence (BT-2, verified + extended):**
  - **Runners:** swift-testing; the C++ runner in `TestSupport.h`; `VerifyLibraryStore` and `VerifyAUGraph`, each with
    its own `fail(_:) -> Never` (`VerifyLibraryStore/main.swift:34`, `VerifyAUGraph/main.swift:59`; the former says it
    "mirrors … EXACTLY"); DEBUG rigs in the app.
  - **Graph builders ×3:** `VerifyAUGraph` builds its own AU graph and re-wraps the design C-ABI (clone S43). The stall
    rig builds another. Neither uses `AudioEngineBridge+Graph`.
  - **C++ helpers re-inlined:**
    - a stereo sine generator ×5 (T2);
    - the golden-master pipeline and **its hash in two files** (T1: `CrossfeedTests.inc:100`, `MultichannelTests.inc:45`);
    - two WAV writers in one file (T3);
    - kernel set-up next to an existing `TestSupport` helper (T5).
  - **Not independent:** `MultichannelTests.inc:647-687 makeOracleKWeight` is the production K-weighting with the
    production constants (X1). libebur128, already a test dependency, would be the independent oracle.
  - **Harness re-implements production:** `ScanFixtureBuilder.swift:165-171` re-implements `FileSignature`'s stat (S42).
    `SRCQualityMeasure` replicates the resampler and analyzer (S44).
  - **Per-file copies:** the contrast-audit helper in 8 `DesignTokenKitTests` files (T7); `SplitMix64` ×2 (X4).
  - **No fixture DSL in `VerifyLibraryStore`:** ~150 checks re-type one scaffold, and private helpers are copied
    between check files (S46).
- **Root cause:** BT-1. With no shared test library per language, each suite copies what it needs.
- **Why it matters:** re-baselining the golden master needs two edits. A shared-mode K-weighting error passes the
  multichannel "oracle". Harness bulk (VLS 10.8k LOC) hides the real assertions.
- **Structural remedy:**
  - One `TestSupport` per language: `Signals.sine/chirp/noise`, `Wav.write`, `GoldenMaster.hash(kernelSetup:)` with
    **one** hash constant, `assertContrast`.
  - Swap the multichannel oracle for libebur128 with channel weights.
  - A `withScannedFixture { root, store in … }` DSL for the store checks.
  - Migrate `Verify*` to swift-testing (BT-2).
- **Effort:** M. **Risk:** low.

### DUP-14 Layout metrics and design tokens live in six homes, LOCAL. Criteria: 3, 1
- **Evidence:**
  - App side: `DesignSystem.swift` (`ShellMetrics`, `LayoutMetrics`, `Footer`, `SongsList`, `QueueRow`, `Meters`,
    `QueueHeader`, `Artwork`), `UI/Controls/ControlMetrics.swift` ("moved here unchanged from `DesignSystem.QueueHeader`"),
    `UI/Library/LibraryRowMetrics.swift`.
  - Kits: `DesignTokenKit` (`EQScreenLayout`, `NowPlayingLayout`, `MonitorLayout`, `SettingsLayout`,
    `DevicePillMetrics`, `FilterPillMetrics`, `GlassDecor`) and `LibraryBrowseKit/DetailListMetrics.swift`.
  - Literals at call sites, by policy ("grid-cell and detail-hero sizes are literals at their own call sites",
    `DesignSystem.swift:296-298`).
  - The carved capsule is drawn twice (S14). Hairline width is a token (`ShellMetrics.hairline = 0.5`) and a literal in
    6 views (`lineWidth: 0.5`).
- **Remedy:** a single rule: geometry tokens live in `DesignTokenKit` (pure, gate-checked); `DesignSystem` only bridges
  them to SwiftUI. Move `ControlMetrics` / `LibraryRowMetrics` / `QueueRow` in. A semgrep rule against literal
  `lineWidth:` / opacity in `UI/`. **Effort:** S–M. **Risk:** low.

### DUP-15 Native-layer duplicates: two AU wrappers, a second publish plane, dead C-ABI, a duplicated format tail, LOCAL. Criteria: 3, 6
- **Evidence:**
  - **AU scaffold ×2** (S1, 216-token verbatim block + 3 more). Already diverged: the spatial render block returns
    `kAudioUnitErr_NoConnection` on a nil `pull`; the effects block dereferences `pull` unguarded
    (`AUAudioUnit.mm:88-108` vs `SpatialRendererAU.mm:176-199`).
  - **A second control plane** kept for tests: `publishTargetState` (`AUAudioUnit.mm:220-226`, "a SECOND publish plane
    parallel to the Realizer").
  - **Dead C-ABI with no caller in Sources or Tests:** `createAdaptiveAudioUnit`, `destroyAdaptiveAudioUnit`,
    `setAUParameter`, `getAUParameter` (`include/AudioUnitBridge.h:49-78`, impl `AUAudioUnit.mm:364-412`; the first two
    have zero callers, the stubs are documented dead). Periphery does not scan C++.
  - **Test-only production C-ABI:** `asLoudnessPredictChangeDb` (`Loudness/TrackLoudnessBridge.cpp:146-170`; callers:
    `TrackLoudnessTests.inc`, `HandleLeakHarness.mm`) re-runs the EQ design that the Realizer already owns (S40).
  - The HAL format-adopt tail ×2 (S32); `MultichannelView` pointer gathering ×2 (S29); int pack loops ×3 (S35).
- **Remedy:**
  - An `AdaptiveAUBase` (Obj-C++ base or a C++ helper struct) for the bus / allocate / registration scaffold.
  - Delete the dead C-ABI.
  - Move test-only entry points behind a test bridge target (`AudioDSPTestBridge` already exists for this).
- **Effort:** S–M. **Risk:** low.

### DUP-16 Duplicated constants and rate domains, SIGNIFICANT (one item needs the algorithm panel). Criteria: 3, 4
- **Evidence:**
  - **Graph rate 48 000** written seven times in Swift (`+EQControl.swift:53`, `+Reconfigure.swift:105`,
    `+Lifecycle.swift:46`, `+Graph.swift:98`, `+Playback.swift:287`, `EngineSnapshot.swift:20`,
    `SpectrumAnalyzer.swift:88`) beside C++ `kDefaultSampleRate` (`include/AudioConstants.h:9`), which the bridge cannot
    see.
  - **Three "supported rate" domains:**
    - EQ designer 44 k–768 k (`EQ/GraphicEQDesigner.h:63-64`);
    - loudness profiler 8 k–192 k (`Loudness/TrackLoudnessProfile.h:67-68`);
    - limiter look-ahead capacity sized at 192 k (`AudioConstants.h:31-33`; at 384 kHz the 3 ms look-ahead is capped to
      576 frames = 1.5 ms).
  - The 20 Hz tick ×3 (DUP-12). Debounce intervals inline (DUP-8).
  - The `CADefaultDeviceAggregate-` prefix ×2 (DUP-3). The `"Unknown Device"` sentinel compared as a string across files
    (DUP-3).
  - The golden hash ×2 (DUP-13).
- **Divergence:** a device above 192 kHz (or below 44 kHz) is "supported" by one stage and out of domain for another.
  At 384 kHz: the EQ designs; the loudness profile is refused (falls back to the causal / pink prior); the limiter's
  look-ahead halves.
- **Remedy:**
  - Export one `AudioDomain` (graph default rate, min / max supported rate) from `AudioConstants.h` through the C bridge
    and use it in Swift.
  - Make each stage's domain derive from it, or document a deliberate difference with a test.
  - Route the >192 k behaviour to the algorithm panel (D20, D31–D36, D21–D27).
- **Effort:** S. **Risk:** low (constants) / panel (domains).

### DUP-17 Settings and state persistence: keys in four places, one setting bound by two views, the queue split across two stores, LOCAL. Criteria: 3, 1
- **Evidence (VM-5, verified + extended):**
  - `"songs.columns.v2"` is an `@AppStorage` literal in **two** views, each owning a binding with its own default
    (`UI/Library/SongsListView.swift:30`, `SongsHeader.swift:30`).
  - Raw keys in `QueueCursorKey` (`AudioViewModel+QueueHydration.swift:24-30`), `EQViewModel.Key`, and `EQToneCard`'s
    `foldedKey`.
  - The queue's restore state is split: the rows go to GRDB's built-in "current" playlist (debounced 250 ms), while the
    cursor, offset, shuffle and repeat go to `UserDefaults` only at clean quit (`+Lifecycle.swift:125`). After a crash
    the two halves come from different moments (partly mitigated by `positionTrackID`).
  - Logging is a cousin of this (one mechanism per concern): `NSLog` direct ×17, `logUX` (an `NSLog` wrapper) ×117,
    C++ `AsLog`, no `os.Logger`. **One production `print`** reports a graph-reconfigure abort to stdout, invisible in
    Console (`AudioEngineBridge+Reconfigure.swift:203`).
- **Remedy:**
  - One `SettingsStore` with typed keys (VM-5).
  - The column config owned by one model, read by both views.
  - The queue cursor stored with the rows (the same GRDB transaction, or a `queue_state` row) so restore is atomic.
  - One `os.Logger` per subsystem / category.
- **Effort:** S–M. **Risk:** low.

---

## Fold-in verification ledger

| Source claim | Status | Note |
|---|---|---|
| BR-10 "restart at X" ×4, three completion closures | **verified** | clone S2 (sim 0.93). Extended with the clamp vs ignore, NaN-trap and base-order divergences (DUP-1) |
| BR-8 three seek implementations, base set before success | **verified** | `+PureMode.swift:218` vs `+ConfigChange.swift:118` |
| BR-12 Master Gain FIFO vs Pure latest-wins; slot + drain ×3 | **verified** | DUP-8 |
| BR duplicated-capability list (device target ×3, end flag ×2) | **verified** | DUP-1, DUP-3 |
| VM list 1 current-track derivation | **verified + extended** | 10 sites; range-check divergence (DUP-6) |
| VM list 2–7 | **verified** | DUP-12, DUP-3 (headphone class), DUP-17 |
| VM-8 / BT-1 mirrors drifted | **verified + extended** | `SignalPathInfoMirror` field drift; two fakes (DUP-2) |
| LIB-01 8 loaders, 2 `LoadState`s | **verified + extended** | an unused kit `SearchEpoch` and a 2-of-8 generic loader already exist (DUP-8) |
| LIB-05 three filter semantics, dead `search()` | **verified + extended** | queue filters title only; gates differ (DUP-9) |
| LIB-07 title fallback ×4, `selectTrackIDByURLSQL` ×2 | **verified** | DUP-10 |
| LIB-12 hand-rolled debounce vs `CoalescingWriter` | **verified** | DUP-8 |
| LIB-13 album-year opposite ties | **verified** | latent (DUP-10) |
| LIB-13 disc-folder parsing duplicated | **refuted** | the kit calls the store's `discNumber(ofFolderName:)`. The album-folder derivation is what differs |
| LIB-16 move / play-count twins | **verified** | DUP-11 |
| BT-2 five harness cultures, `fail` ×2 | **verified + extended** | graph built ×3; golden hash ×2; copied oracle (DUP-13) |

## What is GOOD (one owner already; copy the pattern)

- **One FFmpeg loader:** the decode and the metadata reader share `FileDecodeSource`'s dlopen'd libav table
  (`include/MetadataBridge.h:8-9`).
- **The 31-band grid** is defined in Swift and C++ but pinned by a cross-language test (`EQ_Bands_MatchKit`,
  `Tests/EqDesignerTests.inc:874`). The "played curve" uses the same C++ designer the engine plays (`EQ_ReadbackEqualsEngine`).
  This is the template for any rule that must exist in two languages.
- **Shared rules:** `OutputDevicePolicy` (one device rule; the gap is only the user-pick path, DUP-3), `ShellToastSlot`,
  `BrowseGridRoot`, `AppDialog`, `ListSelectionKeyboard`, `loadFlatFacet`, `CoalescingWriter`, `SnapshotChannel`,
  `formatDuration`, `SignalPathInfo.rateString`. Each is a correct single owner. The duplication is the call sites that
  bypass them.
- **The disc-folder parser** is one function used by both store and kit (LIB-13 partly refuted).

## Open questions for the founder

1. Search semantic (DUP-9): Apple-Music-style substring filter everywhere, or ranked FTS prefix everywhere?
2. Should a song on a playlist page offer the same verbs as on an album page (Add to Queue, Add to Playlist, Info) (DUP-4)?
3. Is AirPlay "headphones" for crossfeed (DUP-3)? Recommended: no. Classify by DataSource where available, else ask once
   per device.
4. Supported device-rate domain for Enhanced (DUP-16): cap at 192 kHz everywhere, or extend loudness and limiter to 768 kHz?
