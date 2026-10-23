# Council: docs ↔ code reconciliation — roadmap, planning, architecture

**Worktree:** `.claude/worktrees/docs-recon-arch`, branch `docs/council-recon-arch` (base `origin/main` @ `7d7c2cd`). Docs only; nothing pushed. 12 commits:

| Commit | Scope |
|---|---|
| `6f791b0` | architecture.md §2.5 reconciled (Sprint EQ engine, the kernel's four paths, golden master, threading-rule fixes, two findings) |
| `7f0e4bb` | architecture.md: null-test count = 202 |
| `77f5c4c` | sprint-plan.md (S10.7/S10.8 closed with back-links, R1 = v1.0.0-alpha in progress, forward links, delivered-early facts) |
| `3ddc97e` | roadmap.md |
| `c475a87` | validation-strategy.md |
| `dc18d25` | DEVELOPMENT.md |
| `caca181` | the five design READMEs |
| `426bbe1` | audio-pipeline-stage-choices-review.md, main-thread audit banner, DSP survey banner |
| `de91ab9` | root README.md (the repo's front-door index; it was also stale) |
| `7dcc497` | docs/README.md |
| `acb6e29` | docs/sprints/README.md, docs/reviews/README.md |
| `0db1899` | architecture.md §9–§10 |

R1 tag check: `git tag -l "v*"` and `git ls-remote --tags origin` are both empty, and `gh release list` is empty. The release PR #87 merged on 2026-10-13. Every doc therefore says **"R1 = v1.0.0-alpha (release in progress)"**, never "shipped".

Method: I verified architecture.md, sprint-plan and roadmap myself against the code, citing file:line. Two read-only Explore subagents checked validation-strategy + DEVELOPMENT, and the design READMEs + pipeline review + audit + survey. I spot-checked their load-bearing claims before editing. One correction to a subagent: it counted 202 null tests, I had first counted 178, and 202 is right.

---

## 1. Per-document counts (MATCHES / STALE / WRONG) and notable changes

| Doc | M | S | W | Notable changes |
|---|---|---|---|---|
| architecture/architecture.md | ~42 | ~20 | 4 | Described below |
| sprints/sprint-plan.md | ~14 | ~12 | 4 | Described below |
| product/roadmap.md | ~12 | 6 | 1 | Described below |
| architecture/validation-strategy.md | ~27 | 19 | 3 | Described below |
| development/DEVELOPMENT.md | ~41 | 18 | 11 | Described below |
| design/eq-lens/README.md | 22 | 13 | 0 | Described below |
| design/library-twin-panels/README.md | 10 | 4 | 1 | Described below |
| design/now-playing-7a/README.md | 12 | 4 | 1 | Described below |
| design/now-playing-realigned/README.md | 7 | 4 | 0 | Described below |
| design/adaptive-tone/README.md | 23 | 9 | 0 | Described below |
| architecture/audio-pipeline-stage-choices-review.md | 10 | 5 | 2 | Described below |
| architecture/main-thread-audio-audit-2026-10.md | 19 | 2 | 0 | Described below |
| architecture/evidence/main-thread-stall-2026-10/README.md | 7 | 0 | 0 | No change |
| architecture/dsp-apple-silicon-survey.md | 0 | 0 | 0 | Described below |
| docs/README.md | ~6 | 4 | 1 | Described below |
| sprints/README.md | ~15 | 3 | 1 | Described below |
| reviews/README.md | ~6 | 0 | 0 | Described below |
| README.md (repo root) | ~10 | 8 | 3 | Described below |

### architecture/architecture.md

**What I rewrote in §2.5:**
- Added a module map of every target.
- Added a table of the kernel's four paths, with `DSPKernel.cpp:145-301` cited:
  - **P0** is bit-perfect only when Intensity is 0 **and** the EQ is flat or off.
  - **P1** is EQ → limiter, using the −0.1 dBTP EQ-only ceiling.
  - **P2** is the full chain.
  - **Blend** is the remaining case.
- Replaced the description of the EQ chain. It used to be `FrequencyResponseCanvas`, `publishEQGains`, `publishEQBandGains`, `setPendingEqGains` and `EQSafetyClamp`. None of those exist any more. It is now `EQSession` → `publish()` → `publishEQ` → C-ABI → `Realizer::setPendingEq` → `GraphicEQDesigner`. I also added the loudness-neutral EQ and the Master Gain paths.

**Stale facts corrected:**
- `dspAudioUnit` is now `EffectsUnit`.
- `DSPKernel.mm` is now `.cpp`.
- `pureModeEngineSetNextTrack` is now `pureModeOpenDecodeSource` + `pureModeEngineArmOpenedNextTrack`.
- `scheduleFile` is now `scheduleSegment`.
- `TargetState.h:41` is now `:64`.
- Every EQ line number was refreshed.
- The golden master is now `0xE7AF0C67F9340785`. It was re-baselined in EQ1b; it used to be `0xE7267654BA01D315`.
- The null test has 202 tests, not 120.

**Threading rules:**
- The list of publishes is corrected: it now includes Master Gain and output transport, and drops layout and loudness.
- Added the 4th semgrep rule, `main-thread-no-concrete-bridge`, and the `PureModeSession.swift` exclusion.
- Cited where the queues are declared.
- Everything else checks out: the queue table, the sync directions (nothing `.sync`s onto `engineQueue`), epochs, `stateLock`, `withPureEngine`, the 30 Hz clock, the 25 ms / 1% / 5 ms bounds, the device model and `OutputDevicePolicy`.

**WRONG items fixed:**
- "the shipped case M == N". M < N is reachable and truncates (Finding F1).
- "the golden master verifies the intensity-0 bypass". The hash fences the *processed* chain; memcmp tests cover the bypass.
- ADR-001's "one custom AU, Swift/C++ interop". There are two AUs, and the bridge is a C-ABI over a bridging header.
- The §14 quality floor, "bit-transparent = intensity 0". It now requires the EQ to be flat or off too.

**Annotations (none deleted):**
- LD-16 and §5 are annotated for decision 25.
- §4 now names the shipped EQ designer.
- §11 now lists what ships for safety.
- §9 now gives the shipped numbers: 3 ms look-ahead, 8× true-peak, −16 LUFS.
- §10 now has a design banner.
- §6, §12, §13 and the Phase 1.5 / Phase 2 rows are marked **won't, this horizon**.

### sprints/sprint-plan.md

- **§Status rewritten:** S10.7 ✅ (#61) · S10.8 ✅ (#62–#86) → R1 = v1.0.0-alpha, release in progress (PR #87; tag pending). Next is the council.
  - The founder decisions are kept as compact rationale.
  - The S10.8 play-by-play now links to the ledgers instead.
- **§2:**
  - The baseline now runs through S10.8.
  - "Perceptual Realizer scaffold" was WRONG and is now "control-plane".
  - Added forward-links to the post-R1 logged lists.
- **Rows:**
  - Every done row has PR back-links.
  - S10.8 links to every ledger section: A–G, Sprint EQ, the disconnect freeze, the break-it reports, the audit and the evidence.
  - S8 Gate 1 is annotated closed (#53).
  - The S9 A–Z rail is annotated → S10.5 cut.
  - S11–S18 are forward-linked to backlog stories.
- **WRONG items fixed:**
  - §4 said S14 and S12 "already delivered".
  - S17 said "on/off wiring done in S12". It was QW1.
  - **The S11–S14 rows had dropped out of the table** because a prose line split it. They now have their own header.
- **SP totals:** Phase 1 is ~146 SP, up from ~103, after the S10.8 re-estimate. S10 is ~82 SP.
- **§5** now lists the cuts, the deprioritized items and the generative direction.

### product/roadmap.md

- R1 is v1.0.0-alpha (in progress), after S10.1–S10.4 + S10.7/S10.8.
- The S10 row now covers S10.1–S10.8.
- Sprint EQ's delivered-early items are noted.
- Golden master, strict-gate contents and THD+N status are corrected.
- WRONG fixed: Phase 2 said it adapts to "hearing". Hearing personalization was cut on 2026-07-12.
- The Deferred section gains the folder/S10.5 cuts, the smart-playlist fast-follow, the generative direction, and the Adaptive Tone proposal as "awaiting a founder decision".

### architecture/validation-strategy.md

- Golden master, test count (202) and the seven Swift test targets corrected.
- The bypass gate now describes P0, with the real test names.
- The sanitizers and clang-tidy are now the make targets.
- The full strict-gate list is added.
- **No nightly job exists**, so that section is marked aspirational.
- The tests for the retired fitter and for `setGain` are pointed at the real suites.
- The Clarity masking test is marked not built.
- The checklists and metrics are ticked where a named test gates them.

### development/DEVELOPMENT.md

- Tool pins added: SwiftFormat 0.63.0, SwiftLint 0.65.1.
- Periphery is required; leaks comes via xcrun; clang-format comes from keg-only LLVM, not Xcode.
- CI runs on hosted `macos-26`, not a self-hosted runner.
- The full strict-gate order is listed.
- The suppression-policy rules and examples are corrected.
- The Swift control-plane section is rewritten. It showed `ObservableObject`, `weak var audioEngine: AudioEngineProtocol?` and an `@Atomic` wrapper that isn't valid Swift. It now shows `any AudioPlaybackEngine`, `snapshot()`, `@MainActor @Observable` and the semgrep rules.
- Build notes corrected:
  - clang-tidy isn't part of `swift build`.
  - There is no `-O3`.
  - ASan has no LeakSanitizer.
  - The warning names are clang's, not GCC's.

### design/eq-lens/README.md

- Added a shipped banner: PR #73, plus a ledger link.
- "Why" is retitled as pre-Sprint-EQ rationale; the files it cites were deleted.
- What was built is annotated for each of: E1 (SVF on NEON), headroom (superseded by decision 26), the FR test, the headroom readout, Low Volume → Bass & Treble, and the open questions.

### design/library-twin-panels/README.md

- PR-A..D shipped via #63 (+#65/#66); PR-E/F moved to the sweep plan.
- WRONG: `DesignSystem+Realign.swift` doesn't exist. The real files are now named.
- Noted the no-blur fills and the deferred gold tag.
- Listed png/06–08.

### design/now-playing-7a/README.md

- Implemented as 8a in S10.7 (#61), then superseded by the Realigned Target (#62).
- WRONG: `design_handoff_5a/` was never committed.
- As-built deltas noted.

### design/now-playing-realigned/README.md

- PR-A..G shipped via #62, with a link to the realign ledger.
- The inspector's fill deviation is noted.

### design/adaptive-tone/README.md

- Still a proposal: there is no code and no poc directory.
- EQ2 is now built.
- Line references refreshed; the old commit is pinned.

### architecture/audio-pipeline-stage-choices-review.md

- WRONG fixed: the EQ publish chain, and the golden master as the "bypass" hash.
- The EQ is now described as SVF/NEON, not `vDSP_biquad`.
- libebur128 is noted as the test oracle.
- The −0.1 dBTP EQ-only ceiling and the M < N truncation are added.

### architecture/main-thread-audio-audit-2026-10.md

- Fixes merged in PR #86 (`dd5e02d`).
- The file:line references are pinned to `457f895`.

### architecture/dsp-apple-silicon-survey.md

It makes no claims about the codebase. I added a "pre-build survey / as shipped" banner.

### docs/README.md

- WRONG: the tagline said "steer in plain language". That was cut.
- Added R1 status.
- The reading order gains design/, releases/, reviews/, the audit and known-issues.
- Phasing is annotated.

### sprints/README.md

- WRONG: it called S6 "DSP-gate hardening". S6 is the architecture gate; S7 is the DSP gate.
- The S10.1–S10.8 records are indexed with their PRs.
- Golden master corrected.

### reviews/README.md

- Added the stage PR ranges.
- Named the council as the next review.

### README.md (repo root)

**WRONG items fixed:**
- It said `AudioFormatKit` = decode. It is the format resolver.
- It said the pre-commit hook runs ASan/TSan. It doesn't.
- It promised plain-language steering, which was cut.

**Stale items fixed:**
- Status said "current focus: S8".
- The test badge said 120 / 71.
- The module map was missing the kits.
- The store is GRDB.
- Golden master corrected; `make dist` and the release workflow added.

---

## 2. Stale roadmap / sprint-plan items, and what changed

| Item | Was | Now |
|---|---|---|
| S10.7 row | 🔨 | ✅. Closed 2026-07-19, PR #61, with retro and visual-matrix links |
| S10.8 row | No status | ✅. Done: part 1 (#62), Twin Panels (#63/#65/#66), A #68 · B #69 · C #70 · pull-forward #71 · D #72 · Sprint EQ #73 · E #74 · F #75 · G #85 · disconnect freeze #86, each linked to its sweep-ledger section |
| §Status | "S10.8 🔨 → R1 (next)" plus a long play-by-play | "S10.8 ✅ → R1 = v1.0.0-alpha, release in progress (PR #87; tag pending a green CI)". Next is the council; any re-plan is the founder's call |
| §2 "Where we are" | Baseline S6–S9; "perceptual Realizer scaffold" | Baseline through S10.8; "control-plane Realizer"; post-R1 logged items forward-linked |
| §7 / roadmap R1 | "after S10.1–S10.4" | After S10.1–S10.4 + S10.7/S10.8; = v1.0.0-alpha (in progress) |
| S8 row | Gate 1 "stays open until S10.1" | Closed by S10.1 (#53) |
| S9 row | A–Z rail → S10.5 | → S10.5, *cut 2026-07-17* |
| S11 "Stage 2b lossy trim" | AAC/MP3 trim open | Code fact added: AAC/MP3 decode through Apple on both paths, which trims priming (`FileDecodeSource.cpp:7-11`). What remains is the FFmpeg fallback's trim plus a seam test. No CUE code and no CUE backlog story |
| S12 delivered-early | Presets + Reimagine knob (QW1) | Plus Sprint EQ: re-voiced and user presets, per-output pins, **hold-to-Compare at matched loudness** (the EQ's A/B). No PEQ or AutoEq code |
| S13 delivered-early | Crossfeed (QW1) | Plus the per-output-pin **auto-load-by-identified-output** mechanism (`EQOutputPin.swift`). What remains is the correction profiles + JSON import/export |
| S14 | — | "Not started": no ISO-226 code |
| §4 Phase 2 intro | "S14 already delivered … S12 planted" | Future tense; what is already in place; the 2026-07-12 cuts |
| S17 | "beyond the on/off wiring done in S12" | "…delivered early in QW1" |
| S18 | — | Also replaces the spatial AU's interim M < N truncation |
| Phase 1 / S10 SP | ~103 / ~34 | ~146 / ~82, after the S10.8 3 → ~45 re-estimate (old figures quoted) |
| Phase 2 (roadmap) | Adapts to "…and hearing" | "Hearing" removed: cut 2026-07-12 |
| Deferred (both) | Missing cuts | Playlist-folders UI and S10.5 cuts, smart playlists as a fast-follow, NL/hearing cut, generative re-imagination as "won't, this horizon" |
| Forward links | None | S11 US-PLAY-07 · S12 US-TON-02 / SPIKE-DEVCORRLIB / US-PROF-02 · S13 US-TON-02 / US-DEVICE-02/-04/-05 · S14 US-TON-03 · S15 SPIKE-MASKING-MODEL / US-PERC-01 · S16 US-PERC-02/-03 · S17 US-RMG-02 / SPIKE-REIMAGINE-MAP · S18 SPIKE-BRIR / US-SPAT-01/-03. These link to backlog.md by ID, not by anchor, so the other agent's edits can't break them |

No future sprint was re-planned, re-ordered or re-scoped.

---

## 3. CODE-LOOKS-LIKE-A-BUG findings

I described both findings in the docs (architecture §2.5) and raise them here.

**F1 — SIGNIFICANT: a multichannel source on a stereo output silently loses channels.**
- **Evidence:** `AudioFormatKit/MultichannelFormat.swift:90-94` sets M = min(N, device). When M < N, `Spatial/SpatialRenderKernel.cpp:61-81` (`routeBinauralStub`, "TODO(S4)") copies the first M channels and **discards the rest**. On a 5.1 FLAC through headphones you hear front L/R only: no centre (dialogue / lead vocal), no LFE, no surrounds.
- **History:** this was a planned S0–S3 interim (`05-sprint-5b-multichannel-epic-plan.md` risk 8). But the binaural fold moved to S18, the behaviour now ships in R1, and it is **not in known-issues**.
- **Doc correction:** architecture.md claimed M == N was "the shipped case". That was wrong.
- **Remedy options:** a founder decision. One is an interim Apple downmix (`AVAudioEnvironmentNode` / `AUSpatialMixer`, as the S4 design already chose) ahead of S18. At minimum, add a known-issue.

**F2 — LOCAL: `.opus` files never reach the library.**
- `LibraryScan/LibraryScanner.swift:38-40` (`supportedExtensions`, "the SINGLE SOURCE OF TRUTH for which files a walk admits") has no `opus` or `oga`.
- Yet the decoder plays Opus via the FFmpeg fallback (`FileDecodeSource.cpp:12-13`), and the metadata extractor handles it (`MetadataExtractor.swift:55,78`).
- `VerifyLibraryStore` tests Opus extraction by calling the extractor directly, so the gate never sees that the scanner skips these files.
- The backlog (US-PLAY-01) lists Opus as shipped.
- Fix: add the extensions, plus a scan check.

**Code-comment / tooling drift.** These are LOCAL items, not product bugs, for the code reviewers. Docs-side I fixed what lives in docs.
- Bridge comments still say `dspAudioUnit` (`AudioEngineBridge+Graph.swift:11`, `+Reconfigure.swift:10`).
- `Package.swift` and `VerifyLibraryStore/main.swift:2` still say "swift test is broken".
- `strict-ci.yml:27,50` names `FileDecodeSource.mm`.
- The `.clang-tidy:19-20` comment says strict-gate doesn't run clang-tidy.
- `.githooks/pre-commit:116` says "graceful skip", and its install hint says `llvm`, not `llvm@23`.
- `scripts/check-suppressions.sh:79-84` resolves only `opt/llvm`.
- `scripts/build-eq-clamp-test.sh` is dead: it references the deleted `EQSafetyClamp`.
- The `strict-gate.sh:306-311` allowlist comment is stale: LoudnessMeterBridge is now null-tested.
- The Makefile help says main-thread-stall bounds are "under 5 ms"; the code is 25 ms max, ≤1% over 5 ms.
- The comment at `Palette.swift:56` gives `#148979`, but the value is `#14897A`.

---

## 4. Broken links

**Fixed: none needed.** A relative-link and anchor checker (GitHub slug rules) over all 147 `docs/**/*.md` files plus the root README found **0 broken links**, both before and after my edits. Every link and anchor I added, including the sweep-ledger section anchors, resolves.

**Unresolved:** none. Two *non-link* path references were wrong. I annotated both rather than deleting them:
- `design/now-playing-7a/README.md`: `design_handoff_5a/README.md` was never committed.
- `design/library-twin-panels/README.md`: `DesignSystem+Realign.swift` doesn't exist. I named the real files.

---

## 5. Roadmap questions for the founder (not decided)

1. **S12 A/B:** Sprint EQ's hold-Compare is already a loudness-matched A/B of the EQ. Does S12 still owe a whole-chain (Intensity) A/B, or is that item done?
2. **S13 scope:** per-output pins already auto-load an EQ per identified output, including the model-UID fallback. That leaves S13 with the correction profiles + JSON import/export. Keep 7 SP, or re-size?
3. **S11 Stage 2b:** AAC/MP3 encoder-delay trim already happens on both paths (Apple decode). Narrow the item to the FFmpeg fallback's trim + a seam test? Also, CUE has no backlog story yet.
4. **F1 (M < N truncation):** accept until S18, add a known-issue now, or pull an Apple-native interim downmix / binaural forward?
5. **F2 (.opus):** OK as a quick fix outside a sprint?
6. **The post-R1 logged items** need a home before S11 or alongside it: the 25 breaker items, the G logs, the disconnect-freeze follow-ups and the parked concurrency cleanup. For example, a hardening mini-sprint?
7. **Adaptive Tone proposal** (2026-10-10): place it on the roadmap (it overlaps S15–S17) or keep it parked? It is listed now as "awaiting a founder decision".
8. **Smart playlists:** §Status says "post-R1 fast-follow", but §5 lists them under "opportunistic, never planned scope". Which one is right?
9. **Generative re-imagination:** now written into §5 and the roadmap as "won't, this horizon / research direction". Please confirm the wording.
10. **Phase 1 grew to ~146 SP**, mainly from S10.8. Does R2's framing ("after S14") need restating?
11. **By-ear checks pending a USB DAC:** the roadmap still says the Pure-path + QW1 checks are "pending a USB DAC". Is that still true?
