# Council Stage 5: the fool (pre-mortem challenger)

Role: attack the council's own conclusions before the founder acts on them. Read-only. Nothing built in the main checkout,
the app was never launched.

**Baseline warning.** Every Stage 1–4 report was written against `a206107`. `origin/main` is now `7761693`. R1 added 19
commits that touch 87 files (+7,401 / −1,236 lines: 4,905 in tests, 2,432 in sources). I checked claims at `7761693` with
`git show 7761693:<path>`. Several findings are now fixed, or partly fixed: LIB-02 / P5A-01/02 (refusal layer), D41,
D71 / DSP-03, D74 / DSP-04 (packed 24-bit), D76 (NaN), N92 and D63 (RenderGate liveness). BT-1 / VM-8 / W0 are partly done:
`AdaptiveSoundTests` already `@testable import`s the app (`Package.swift:267-270`, commit 1060665). **The register must be
re-verified at 7761693.** Otherwise agents will be sent to fix things that are already fixed.

My own experiments are in `scratchpad/fool-ogg/` (outside the repo):
- **`probe.swift`:** `AVAudioFile` on generated test files.
- **`meta.swift`:** `AVURLAsset` metadata on the same files.
- **Read-only `gh api` calls:** the repo settings.

---

## 0. Bottom line

1. **The plan is a rewrite in disguise, sequenced so that it blocks features.** W0→W5 gate every roadmap item:
   - EP-MCP waits for W2/W3;
   - S11 waits for W4;
   - S12–S14 wait for W5;
   - S14 also waits for W2.

   Two of the waves are L with high risk. Given this project's estimation record (below), the waves will become R2, and
   the founder will break the sequence halfway. A half-done strangler, with two live transport owners, is worse than
   today.
2. **The council re-invents an established library it cites about 15 times.** W4 ("one source pipeline") is
   SFBAudioEngine's design. SFB is MIT-licensed, ships as a SwiftPM package, and is actively maintained. It has decoders
   for FLAC, Ogg, Opus, WavPack, APE and DSD, a region decoder (CUE), a ReplayGain analyser, TagLib metadata, and
   `modifyProcessingGraph:` to insert our effects AUs. Nobody evaluated adopting it, against the founder's own rule:
   "I would rather use a well-established lib".
3. **One premise behind W4 / ARCH-6 is false on the macOS 26 floor.** `AVAudioFile` opens Ogg Vorbis and Ogg Opus
   natively, and `AVURLAsset` reads Vorbis comments, including ALBUMARTIST. The FFmpeg path is therefore nearly
   redundant. It is also the app's largest attack surface: a C demuxer runs **first** on every FLAC, Ogg and Opus file
   during the background scan, in a process with no sandbox, loaded from a user-writable path. **Delete FFmpeg** instead
   of routing every path through it.
4. **The council audited architecture, not the product people hear.**
   - The default sound path is processed:
     - Intensity 0.20 gives a leveller that integrates over the whole session;
     - the blend adds +2 dB;
     - the limiter's fast release is dead.
   - Dragging the scrubber to the end of a 44.1 kHz track leaves the app silent and never moving on. That is the
     common sample rate.
   - Master Gain resets to unity (the loudest setting) at every launch.

   All three are small (S) fixes, and none of them is in any wave.
5. **Process: one rule fixes most of it.** CI is the only gate: merges happen by auto-merge on a green required check,
   main runs are never cancelled, and flaky tests are quarantined the same day. Lanes run only a fast local check. That
   one rule removes merging mid-CI, contention on the founder's Mac, the swiftformat blind spot (CI checks a normal
   checkout), and much of the burn against session limits.

---

## 1. Pre-mortem: "It is April 2027. The remediation plan failed. Why?"

### PM-1 The waves became the roadmap, and the founder broke the sequence halfway (likelihood HIGH, impact HIGH)
- **The story:**
  - W0 and W1 slip from "with R1.1" to six weeks.
  - W2 starts. It is built "beside and switch per event family" (`arch.md:607`).
  - In week 4 the founder pulls EP-MCP or S14 forward, as they pulled EP-MCP *into* the council on 10-13.
  - W2 is parked with the new `Player` reducer live for some events and the view model still owning the others. That is
    three transport owners, not one.
  - No user-visible change ships for a quarter, and the dogfood friction (settings, search, defaults) stays.
- **Evidence:**
  - **Estimation record:** S10.8 was estimated at 3 SP and re-estimated at ~45 (`product.md:247`). The UX re-gate took
    ~3 months. Sprint G was planned at "4–5 hours" and ran ~18 h plus the freeze fix (`process.md:84-85`).
  - **The R1 fixes:** approved as 3 lanes, they grew to 5 lanes, then "add all 3 extras", then a flake-fix PR, for
    +7.4k lines (memory `project-council-review-2026-10`; `git diff --numstat a206107 7761693`).
  - **The founder's appetite:** EP-MCP was added mid-council (10-13 22:20). The memory index holds many side quests
    (generative reimagination, the remaster spike, vocal separation, karaoke, system-wide DSP).
  - **The founder's last call on this exact work was to park it:** "freeze fix only, decide later"
    (`project-concurrency-cleanup-parked`). W2 un-parks it as L / high.
- **Early warning:**
  - W1 has not merged 3 weeks after start;
  - any wave runs past 2× its estimate;
  - the founder asks "when can I use X?" during a wave;
  - a wave is paused with both the old and the new path live.
- **Prevention:**
  - No wave sequence. Each structural item rides **only** with the feature that needs it, scoped to the slice that
    feature needs.
  - A 2-week cap per slice.
  - **Finish-or-revert:** a strangler is never left with two live owners at a sprint boundary.

### PM-2 We rebuilt SFBAudioEngine by hand, without the hardware to verify it (likelihood MED-HIGH, impact HIGH)
- **The story:**
  - W4 replaces `AVAudioPlayerNode` scheduling with an `AVAudioSourceNode` over the C++ ring, which is "exactly
    SFBAudioEngine's architecture" (`area-dsp-cpp.md` DSP-01).
  - It lands in two languages, with new seam, latency and format-change bugs.
  - The founder finds them by ear, as they found the freeze. There is still no USB DAC, so the bit-perfect integer path
    the whole product is anchored on has still never run on hardware (`product.md:241`).
- **Evidence:**
  - The council opened SFB's source (`exp-p3-sota/ref-sfb/SFBAudioEngine` @ 9ed712d, 2026-09-18). It is MIT
    (`LICENSE.txt`) and a SwiftPM package, macOS 11+.
  - Its decoders cover FLAC, Ogg Vorbis/Opus/Speex, WavPack, Monkey's Audio, MPEG, Musepack, TTA, DSD (DSF, DSDIFF, DoP)
    and libsndfile.
  - It has the `SFBAudioRegionDecoder` (a frame range of a file: the "bounded source" ARCH-4 wants for CUE) and the
    `SFBReplayGainAnalyzer` (D5's album and track leveling).
  - On the `SFBAudioPlayer`:
    - `modifyProcessingGraph:` is at `SFBAudioPlayer.h:302`;
    - `setOutputDeviceID:` is at `:287`;
    - its delegate events (`decodingStarted`, `nowPlayingChanged`, `:345,381`) are the event channel ARCH-8 asks for.
  - **No report asks "why not adopt it?"** The founder's rule (`feedback-prefer-established-libs`) says to evaluate
    established libraries *first*.
- **Prevention:**
  - A **1-week adoption spike** before any in-house W4: SFB for the Enhanced path, with our two AUs inserted via
    `modifyProcessingGraph:`.
  - Measure, at minimum:
    - where the sample-rate conversion happens, and at what quality;
    - gapless at 44.1 → 48 and 48 → 48;
    - the latency of seek and of a device change.
  - Pure keeps its own HAL engine. Buy a USB DAC before any wave touches the audio path.

### PM-3 The gate cried wolf, so the founder stopped trusting it (likelihood HIGH, impact MED-HIGH)
- **The story:**
  - W2 and W4 add the most flake-prone kind of test (concurrency and timing).
  - Once required checks exist, flakes block merges and the founder bypasses them. Without required checks, red is
    ignored. Either way the gate loses its authority, and the next escape ships.
- **Evidence:**
  - 5+ timing flakes in the 7 days before R1 (`process.md:271-273`).
  - Then `ArmContract_ArmWhileSeamClaimed` on PR #88, which failed 13 of 20 runs under load (memory).
  - The founder merged #85, #86, #87 and #88 before CI finished, and said "tag now, fix test after".
  - Today: `main` is not protected (`gh api …/branches/main/protection` → 404), auto-merge is off, rulesets are empty,
    and `cancel-in-progress: true` still applies to main (`strict-ci.yml:12-14`).
- **Prevention:** §5. Required checks **plus** same-day quarantine. Neither works alone.

### PM-4 Agents cost more than they saved (likelihood MED, impact HIGH)
- **The story:**
  - Each high-risk wave runs the founder's full loop: design → SME panel → architect + the-fool gate → implement →
    break-it → fix → re-break.
  - The coordinator's context saturates, and agents die at their usage limits mid-wave.
  - Knowledge lives in `/private/tmp` (wiped on reboot), in a local unpushed WIP branch, and in per-laptop memory. The
    founder works across several laptops (`user-ramith`).
  - A reboot or a switch of laptop loses the thread.
- **Evidence:**
  - **The cost of one bug class, the D41 wrong song:** P3a found it, P3b contradicted it, P4 adjudicated. Then came a
    design agent, a design review, an implementer, two breakers, three extra fixes, and a flake fix whose test failed
    13/20 under load. That is about 10 agent runs.
  - **Machine load today:** 22 worktree folders using 26 GB (`du -sh .claude/worktrees`).
  - **Losses:** ≥5 usage-limit kills; agents built in the main checkout twice (`process.md:116-121`).
  - The breakers' red tests are uncommitted, so they are not in the gate. Examples: P4's VM harness, P5a's disk-image
    tests, P3's seam replicas (`panel-p5a-library.md:361-363`, `panel-p5b…:430-437`).
- **Prevention:**
  - A cap of ≤6 concurrent agents.
  - Lanes run only the fast check; CI runs the heavy gate (§5).
  - Every breaker's red test is merged as a regression test, or deleted.
  - Council and sprint state is pushed to the repo, not kept in `/tmp`.

### PM-5 The council's output was too big to decide on (likelihood MED, impact MED)
- **The story:**
  - About 150 findings and ~300 severity-tagged lines.
  - **67 founder questions in the 11 main reports:**
    - arch 8, bridge 4, build-test 5, dsp 6, library 5, ui 5, vm 5, d41 4, duplication 4, process 11, product 10;
    - plus docs-arch's 11 roadmap questions and the panels' decisions.
  - The founder decides fast, from a recommendation, in small chunks (`feedback-questions-need-recommendations`). With
    ~80 decisions, the founder either rubber-stamps them or stalls.
- **Prevention:** the synthesis brings **≤10 decisions**. Everything else is "coordinator default, revisable"
  (`process.md` §6.2).

---

## 2. Over-reach: gold-plating for a one-founder alpha, and the cheaper path

| Recommendation | Why it is over-reach | Cheaper alternative that gets most of the value |
|---|---|---|
| **W4: build the unified C++ source pipeline in-house** (ARCH-6, BR-2, DSP-01; L, high) | It re-implements SFBAudioEngine. The audible defects it would fix are each S. | (a) Fix the measured defects in place, in about a week: SRC `.mastering` (one line; measured flat to 21 kHz at 0.9–3.5 % of a core, `panel-p3-path-breaker` D38); clamp seek-to-end (D37, S); an arm-time channel-count guard (BR-7, S); pre-schedule track B at arm time to close the 48 kHz seam gap (rev-sota M2 fix 1). (b) The 1-week SFB adoption spike (PM-2). |
| **ARCH-6: an `AudioSourceFactory` routing every path Apple → FFmpeg** | Its premise is false on macOS 26 (see §4, check 3). | **Delete FFmpeg** (decode fallback, `MetadataBridge`, dlopen, version guard), or make it opt-in. Add `opus` and `oga` to the scanner list (`LibraryScanner.swift:51`). This also removes the hardened-runtime `disable-library-validation` problem that notarization would bring (`Makefile:63-64`). |
| **W5 / ARCH-7: `EQProgram` with `FilterSpec`, per-band `(g, k, m1)`, a bigger `TargetState` and a golden-master re-baseline "before S14"** | S14 needs one extra layer that is exempt from neutrality, not parametric filters. Today the neutral gain is `loudness_.onDesign(design, …)` over one curve (`Realizer.mm:409-431`). | For S14, realize taste + compensation, but compute neutrality from the **taste** design only. That is one extra design call inside the 31-point contract. A 50 % ISO-226 contour fits ±12 dB. Build the full `EQProgram` only when S12 (PEQ / AutoEq) is actually scheduled. |
| **W1: a Codable `AppCommand` catalogue + `CommandDispatcher` + `ClientPolicy` + scopes + rate limits + typed `CommandError` + generated MCP schemas** | Built before MCP has a single user. "Every surface already calls the same VM verb" is mostly true: there is one `togglePlayPause`, and media keys call it (`NowPlayingController.swift:93`). App Intents may not even register in a SwiftPM-plus-`bundle-app.py` build; arch itself flags this as unverified (`arch.md:570-571`). | Turn the 4 `didSet`-commands into intent methods (S). Do SP-MCP-01 as a 2–3-day spike: about 8 hand-written tools over the existing `@MainActor` verbs (read-only state, search, enqueue by `tracks.id`, transport). Generalise into a catalogue only if the founder uses MCP weekly. |
| **"EP-MCP must wait until after W2/W3"** (`arch.md:618-621`) | An MCP tool that hops to the main actor and calls the same verb is exactly what media keys do today. The G-RACE classes were *engine-internal* (config-change queue vs `engineQueue`, `+ConfigChange.swift:32-120`). They do not come from the number of main-actor clients. | Ship read-only MCP plus transport tools after R1.1. Hold gain and EQ tools until the domain clamps are re-confirmed (they already sit below the VM, `arch.md` §2.5). |
| **W3: a 5-module split + `package` access + `defaultIsolation(MainActor)`** | Most of the value is one fact: "main cannot name AVFAudio". | Extract **one** library target, `PlaybackEngine` (the bridge, with its AVFAudio and HAL members `internal`). Add `semgrep --test` fixtures for the rules that stay (BT-5, S). Create `AgentGateway` as a module only when MCP grows past the spike. |
| **ARCH-2: `actor PlayerEngine` + the app-wide concurrency model (a)–(g) + typed throws** | It converts 4.1k LOC across 23 files to actor isolation to close four known false-confinement sites. | BR-1's own cheap step: `configChangeQueue` and the global-queue fallback (`+GaplessRoll.swift:161-178`) *enqueue a command* on `engineQueue`, which deletes the TOCTOU and `isReestablishing`. Add `Mutex<Shared>` for `stateLock` (BR-5). M, not L. |
| **ARCH-10: a fitness function for type size across extension files** | A new lint budget plus the founder's "never fight lint" rule means agents contort code to pass it. That is how the extension sprawl happened (`arch.md:418-421`). | Skip it. Decomposition happens inside the real refactors. |
| **BT-2: retire `VerifyLibraryStore` (12k lines, 157 checks, "the project's best asset") into swift-testing** | Idiom uniformity, at L effort and medium risk to the best gate. | Add `--filter` and continue-on-failure to the existing runner (S). |
| **LIB-01: migrate every list to `ValueObservation`** (L) | Eight loaders work, and none is a reported bug. | LIB-01's own remedy 3: one `LoadSlot` (~40 lines) when the next list is added. |
| **DSP-02: typed opaque structs + an ObjC protocol + evaluate Swift↔C++ interop** | A rewrite of a working boundary. | One named enum for the Pure start-failure reason (the user-visible part). Delete the dead C-ABI (DSP-12). |
| **ARCH-9: a typed-error taxonomy with a "recovery owner" per type** | Ceremony. | `os.Logger` behind `logUX` + `AppNotice` per source (VM-9). Both S. |

---

## 3. Under-reach: what every report missed or under-weighted

Ordered by risk to the founder. Each item says what to do about it.

1. **Security: FFmpeg parses untrusted files in-process, automatically.**
   - `MetadataExtractor.swift:59-64` runs FFmpeg **first** on every `flac`, `ogg`, `oga` and `opus` during the
     background metadata pass.
   - The libraries are dlopened from `/opt/homebrew/lib/` (user-writable), `/usr/local/lib/`, or a **bare leaf name**
     (`FileDecodeSource.cpp:386-399`, the `""` prefix). For a process that is not hardened, a bare name means a
     `DYLD_LIBRARY_PATH` / current-directory search.
   - The app has no sandbox (`product.md:84`) and no XPC isolation.
   - One crafted file in a downloaded album therefore means code execution with the user's full rights. The planned
     notarization adds `disable-library-validation`, which means loading unsigned code by design.
   - **Nobody wrote "attack surface", "CVE" or "untrusted".**
   - **Fix:** delete FFmpeg (§2). If it stays, make it opt-in, drop the bare-name prefix, and parse in an XPC helper.
2. **The anchor promise has no hardware path, and Pure pause is a device teardown.**
   - Pause = stop (`AudioViewModel+Transport.swift:45-52`). On Pure, stop runs `tearDownPure()`
     (`+Playback.swift:251-252`), which releases hog mode and **restores the original nominal rate**
     (`HALOutputEngine.mm:350-351, 877-885`).
   - So every pause and resume of a 44.1 kHz file on a DAC that sits at 48 kHz switches the DAC's rate twice. Many DACs
     mute or click their relays when that happens, and another app can grab the device during the pause.
   - Not verified, because there is no DAC.
   - **Fix:** buy a USB DAC (~$100–200) before W-anything. Add pause and resume to the HIL checklist.
3. **User-data durability is missing from the wave plan.**
   - R1 shipped only LIB-02's refusal layer. LIB-02's layer 2, the `missing_since` tombstone, is in no wave (W0–W5).
   - The R1 known issue stands: removing and re-adding a folder resets play counts, loved and ratings.
   - There is no playlist export (no M3U match in `Sources/`) and no "back up library data". The only non-rebuildable
     data sits in one SQLite file, with backups made before migrations only.
   - **Fix:** M3U8 export (S); "Back up library data…" via `VACUUM INTO` (S); the tombstone (M) before any new
     scan or watch feature.
4. **Hearing safety: Master Gain resets to unity (the loudest setting) at every launch.**
   - `masterGain: Float = MasterGainLaw.unity`, not persisted (`AudioViewModel.swift:193-195`).
   - A user who turned down by 20 dB for sensitive IEMs gets +20 dB on the first play after relaunch (Enhanced path).
   - The council framed persistence as convenience (VM-5, product item 1). It is also a safety fix.
   - **Fix:** persist the turn-down. Never restore a value above the last one stored.
5. **Observability and the alpha's feedback loop do not exist.**
   - No `os.Logger` (`import os` appears only for locks: `AudioEngineBridge.swift:5`, `+SharedState.swift:3`,
     `TransportSnapshot.swift:10`); 141 `NSLog` / `logUX` call lines.
   - No MetricKit crash payloads.
   - No "Copy Diagnostics" item.
   - No issue template (`.github/` has only `dependabot.yml` and two workflows).
   - The public release has no channel back to the founder.
   - **Fix (S each):** `os.Logger(subsystem:category:)` behind `logUX`; `MXMetricManager` crash diagnostics written to
     the data folder; a Help ▸ "Copy Diagnostics" item (versions, device list, last-hour log); an issue template.
6. **Distribution and identity.**
   - The build is ad-hoc signed (`Makefile:61-74`), so every release is a new code identity. Any TCC grant (removable or
     network volumes, where the audiophile persona keeps music) is likely asked again after each update. Unverified.
   - On macOS 26 a first launch needs System Settings ▸ Privacy & Security ▸ "Open Anyway".
   - There is no updater, so alpha users never learn about R1.1.
   - There is still no LICENSE (`gh api`: `"license": null`; `README.md:11,157-159`), and the GRDB MIT notice is not
     bundled.
   - There are 11 no-op `startAccessingSecurityScopedResource` calls in 8 files for an app with no sandbox, plus an
     unused `bookmark` column (`LibraryStore+DAO.swift:114`).
   - **Fix:** decide D7 (public or private). If public: add the LICENSE and notices, join the Developer Program, and
     notarize (easier once FFmpeg is gone); run a clean-Mac first-run test (decision 13's item, never done). Commit to
     "Developer ID, never sandbox" and delete the scope calls, or create real bookmarks now.
7. **Large libraries: no target size, no performance gate.**
   - The design is benchmarked at 10k–20k (`area-library.md:140`, Q4).
   - LIB-08 (an O(library) walk, regroup and four full reloads per file-system event) and LIB-15 (the full in-memory
     sorted list) are fine at 20k and unknown at 100k. Audiophile collections are often 50k–200k tracks.
   - **Fix:** pick a target (recommend 100k). Add a nightly smoke test on a synthetic 100k store (`make stress-library`
     exists): launch to first paint, a sort click, and one-file reconcile latency.
8. **Energy was never measured.**
   - Two 20 Hz main-thread timers run from engine-ready to shutdown, including while paused and in menu-bar mode
     (`+SpectrumTimer.swift:14-41`).
   - The analyser workers poll forever (DSP-09).
   - **Good news:** `AVAudioEngine` is stopped on pause (`+PureMode.swift:254-268`), so the device can idle.
   - **Fix:** gate both timers on `isPlaying || visible` (S); add one Activity Monitor "Energy Impact" reading (idle,
     paused, playing) to the release checklist.
9. **Accessibility beyond VoiceOver is better than feared.**
   - Reduce Motion is honoured at 21 sites, Increase Contrast at 7, Reduce Transparency at 4.
   - Gap: `accessibilityDifferentiateWithoutColor` has 0 uses, so check whether any signal-path or meter state is
     colour-only. LOCAL.
10. **The council's evidence is not durable.**
    - The breakers' harnesses that found real bugs are uncommitted.
    - The council WIP branch is local and unpushed.
    - The scratchpad lives under `/private/tmp`.
    - **Fix:** commit the red tests as regression tests (or delete them), and push `review/2026-10-council-wip`.

---

## 4. Severity sanity: 11 spot-checks at `7761693` (unreproduced claims first)

| # | Claim (report) | My verdict | Evidence (read at 7761693) | Corrected severity |
|---|---|---|---|---|
| 1 | D37: the Enhanced resampler hangs on a seek to the end (P3 breaker, SIGNIFICANT) | **UNDERSTATED** | The scrubber drag sends `seek(to: dragFraction * duration)` (`NowPlayingBar.swift:332-333`). The VM passes it through with no clamp (`AudioViewModel+Playback.swift:133-143`). The bridge bumps both generations, *then* refuses at `frame < totalFrames` (`+EnhancedResampler.swift:193-202`): silent forever, never advances. The resampler path is every file that is not 48 kHz, so it includes 44.1 kHz CD rips. It is not in product's R1.1 list. | **R1.1 blocker** (the product's own definition: "music stopped") |
| 2 | Default path: D20 (session-integrated leveller) + D50 (+2 dB hump) + D34 (dead fast release) at Intensity 0.20 (P2; each SIGNIFICANT) | **UNDERSTATED as a product issue** | `var intensity: Float = 0.20` (`AudioViewModel.swift:142`). Every fresh launch is processed, against "faithful > processed". Fixing the *default* is one line. | **R1.1 item #1** (D2/D3) |
| 3 | ARCH-6 / DSP-01: an Ogg/Opus file only FFmpeg can decode fails in Enhanced (DSP-01 adds "plays in Pure") | **OVERSTATED / WRONG on macOS 26** | Probe: `AVAudioFile` opens Ogg Vorbis (44.1k) and Ogg Opus (both `.ogg` and `.opus`). `AVURLAsset` returns `vorb/TITLE…ALBUMARTIST…TRACKNUMBER`. The extractor already maps `vorb/ALBUMARTIST` and `vorb/COMPILATION` (`MetadataExtractor+AVFoundation.swift:67-80`), so the "FFmpeg first" comment at `MetadataExtractor.swift:55-56` is stale. DSP-01's "plays in Pure" contradicts the code: Pure viability needs `AVAudioFile` (`+PureMode.swift:47-50`). | **LOCAL**; reverse the remedy (delete FFmpeg) |
| 4 | ARCH-7: S14 needs `EQProgram` first (SIGNIFICANT, W5 before S14) | **OVERSTATED for S14** | Neutrality is `loudness_.onDesign(design, eq_.isOn)` on the one realized curve (`Realizer.mm:430`). Compute it from a taste-only design and realize taste + compensation. Still accurate for S12 (narrow-Q PEQ). | SIGNIFICANT for S12 only |
| 5 | ARCH-4: the URL is identity at every layer, so store, play counts, playlists and MCP need a non-URL id (STRUCTURAL) | **PARTLY OVERSTATED** | The store already has a durable `tracks.id`. Play counts use it: `incrementPlayCount(id:)` (`LibraryStore.swift:228`) via the queue's `trackID` (`+PlayTracking.swift:66-71`). Playlists reference `track_id`. Only CUE (`tracks.url UNIQUE`) and the VM/engine identity are blocked. | STRUCTURAL **only if CUE is wanted** (D4: count the `.cue` files first) |
| 6 | VM-10: overlapping `refreshDevices` Tasks let an older device list win (SIGNIFICANT) | **OVERSTATED** | The enumerations serialise on `engineQueue` (FIFO), and `showEngineOutput` reads the live engine device (`+Devices.swift:44-67`), so the newest list lands last. The on-deck half was fixed by R1's ticket gate. | LOCAL |
| 7 | VM-2: the stop/pause epoch is taken inside the Task, and a "starting" state is missing (STRUCTURAL) | **ACCURATE; split** | Stop and pause take their epoch inside `Task` (`+Lifecycle.swift:152,160,174`). That is latent: there is no stop-then-start caller. The start gap is real: `isPlaying` is set only after start + prime (`+Playback.swift:60-75`), so a second press restarts the song and Pause is dropped (`+Transport.swift:45-63`). | The epoch is LOCAL (latent). The start gap is SIGNIFICANT (UX, known post-R1). |
| 8 | BR-1: config-change and the gapless fallback drive the engine off-domain (STRUCTURAL) | **ACCURATE, unreproduced** | `reestablishEnhancedAfterConfigChange` runs `engine.start` / `stop` and touches the player on `configChangeQueue`, with a TOCTOU re-check (`+ConfigChange.swift:32-120`, `:86-93`). `openNextFileOrRestart` runs `playFile` on `DispatchQueue.global()` with no intent or epoch check (`+GaplessRoll.swift:151-178`). | Keep STRUCTURAL; **the remedy should be the cheap "enqueue a command" step (M), not the actor conversion (L)** |
| 9 | W0 / BT-1 / VM-8: "test the real code" is S | **STALE** | R1 already added `AdaptiveSoundTests` with `@testable import AdaptiveSound` and `OnDeckEngineModel` (`Package.swift:267-270`; 1060665). What remains is migrating about 61 mirror tests and deleting the mirrors. That is M, and there are now **three** engine fakes (`MockAudioEngine` mirror, `OnDeckEngineModel`, `DeviceTestEngine`), so DUP-2 grew. | M; re-scope W0 |
| 10 | ARCH-9: no `os.Logger` (SIGNIFICANT) | **ACCURATE, UNDERSTATED vs cost** | See §3 item 5. | S, do it in R1.1 |
| 11 | LIB-02: the sweep deletes on absence (STRUCTURAL, fixed in R1) | **NARROWED, NOT CLOSED** | R1 added the refusal layer. The tombstone (layer 2) is in no wave, and remove + re-add still resets annotations (R1 known issue). | Keep STRUCTURAL OPEN (data durability) |

Pattern: the reports measured **mechanism**. Where a claim depends on platform behaviour (Ogg decoding) or on the
current tree (R1), it drifted. Where it is a user path through a measured defect (seek-to-end, the default Intensity),
it was under-ranked, because no one walked the product's own default.

---

## 5. Process truth: the smallest change that removes most of the risk

**One rule: "CI is the only gate, and a merge happens only on green."** Four concrete pieces:

1. **Repo settings:**
   - turn on `allow_auto_merge`;
   - add a ruleset on `main`: require the `strict-gate` check, no force-push, the founder can bypass in an emergency.
   - **The founder's habit change is one button.** They click **"Enable auto-merge"** on the one consolidated PR instead
     of "Merge", and walks away. This keeps one-PR-per-sprint and the founder's speed ("combine then test", "let CI run").
2. **One YAML line:** `cancel-in-progress: ${{ github.event_name == 'pull_request' }}` (`strict-ci.yml:14`). Every main
   commit gets a verdict; f115cca's run was cancelled at 66 minutes.
3. **Same-day flake quarantine.** A test that fails without a code cause goes onto a skip list read by the required job
   (`swift test --skip`, plus a `--skip` flag in the C++ runner, which is BT-3 step 2, S). It gets a ledger line and a
   nightly 50×-under-load job, and it must be fixed at the root or deleted within the sprint.
   - **Required checks without quarantine fail:** the founder bypasses them, as with #88.
   - **Quarantine without required checks also fails:** red gets ignored.
4. **Lanes run only `make check` locally:** format and lint over `git ls-files`, build, and `swift test` for the touched
   targets. The heavy gate runs once, on CI.
   - GitHub-hosted macOS runners are free for public repos.
   - This removes the contention of 22 worktrees on one Mac, agents waiting out 45-minute gates until they hit session
     limits, and the swiftformat worktree blind spot.
   - Still fix that blind spot at the root with one line: lint the tracked file list instead of a directory walk with
     `--exclude docs,.claude` (`.swiftformat:5`).

**What this removes:**
- merging before CI finishes;
- main runs with no verdict;
- tags on red SHAs (also add the `release.yml` check that the tagged SHA's `strict-gate` passed);
- the swiftformat blind spot;
- most local contention;
- part of the session-limit burn.

**What it does not remove:** new timing tests. Add one line to the PR template: "a new or changed concurrency or timing
test: `make stress-test N=200` under load, result pasted". That would have caught the 13/20 `ArmContract` flake before
#88.

**Second priority** (worth it because auto-merge waits on CI):
- split the 87-minute serial job into parallel jobs;
- take the accuracy sweeps out of the sanitizer builds (`process.md:257-262`).

**Do NOT add:**
- an echo-back ceremony per task;
- a rotating break-it per sprint on top of this;
- a pinned "Now" issue.

All are reasonable, but the founder already called the loop "never-ending" once (decision 18). Add them only if the
core rule holds for a month.

---

## 6. Roadmap direction: player-first vs "R2 = fix the base"

**Steelman A (player maturity first, keep shipping features):**
- The founder is the only user, and the product's own triage shows that what they hit first are features and S fixes
  (settings, search, favourites, the click model), not architecture (`product.md` §2a).
- Refactors with no feature attached have no acceptance test, and they stall (PM-1).
- Feature work exercises the seams and pays for the fixes. S14 is the cheapest proof of the adaptive thesis.
- The founder's motivation is features. A quarter of plumbing risks losing them to a side quest.

**Steelman B (R2 = fix the base first):**
- Sprint G found 13 R1 blockers in *old* code the day before release, and R1 then needed +7.4k lines of fixes.
- The bug classes are ownership bugs: wrong song, zombie audio, the freeze, data loss. Every R2 feature (CUE, PEQ, S14,
  MCP) touches exactly those seams.
- Agents generate code faster than it can be verified, so debt compounds. "Elegance is a must" is the founder's own
  rule.

**Recommendation: neither in pure form. "Faithful and durable first, then features that each carry their own
structural slice."**

1. **Dogfood week + R1.1, "faithful and durable" (≤2 weeks, mostly S):**
   - Defaults: faithful (Intensity 0, leveller off).
   - Persistence: settings, including the Master Gain turn-down.
   - Playback fixes:
     - the seek-to-end clamp;
     - SRC `.mastering`;
     - the channel-count arm guard;
     - pre-schedule track B (the 48 kHz gap).
   - Observability: `os.Logger` + Copy Diagnostics.
   - Licence: the LICENSE file and notices.
   - Data: M3U export + backup.
   - Library:
     - wire up global search;
     - favourites;
     - scan `opus` / `oga`.
   - Clean-up: delete FFmpeg.

   These are product fixes that also remove base risk.
2. **Spikes, in parallel and time-boxed:**
   - SFBAudioEngine for Enhanced (1 week, PM-2);
   - SP-MCP-01, read-only (2–3 days);
   - buy a USB DAC and run the HIL pass on Pure, including pause and resume.
3. **R2 = the player-first features in the product's order** (S14 → S12 → S13 → S11-lite). Each one funds only its own
   slice:
   - S14: a two-layer Realizer + an observed system volume + one engine event;
   - S12: `EQProgram`;
   - S11: CUE only if `.cue` files exist.

   Transport ownership (W2) is done only when a feature needs it. If the SFB spike wins, W2 shrinks to the queue
   reducer, because SFB owns the player.
4. **The guardrail stays:** no Phase 2 until R1.1 is the founder's daily driver for a week.

---

## 7. What I would change in the plan (for the synthesis)

1. **Re-baseline the register at `7761693`.** Mark what R1 fixed, and re-scope W0, which has partly landed.
2. **Replace the W0–W5 sequence** with feature-funded slices, a 2-week cap and finish-or-revert.
3. **Before any in-house W4:** a 1-week SFBAudioEngine adoption spike. Delete FFmpeg now, since the macOS 26 native
   decode is verified.
4. **R1.1 leads with the S fixes in §6.1**, starting with the faithful default and seek-to-end.
5. **Process: the §5 rule** (auto-merge + required check + uncancelled main + quarantine + fast local check).
6. **Hardware: buy a USB DAC before any change to the audio path.** Add Pure pause and resume to HIL.
7. **Add the under-reach tickets:** tombstone, export and backup, the Master Gain safety, diagnostics, LICENSE, the
   100k performance target, the energy reading, the clean-Mac first run.
8. **EP-MCP:** a read-only spike over existing verbs after R1.1. The catalogue comes only after proven weekly use.
   Verify that App Intents register in a SwiftPM-built bundle before promising "one catalogue for UI + MCP + Intents".
9. **The founder gets ≤10 decisions.** The rest are coordinator defaults.

**The ≤10 decisions I would put to the founder (recommended option first):**
1. **R1.1:** "faithful and durable" first (yes), or start the waves (no).
2. **Default sound:** faithful (Intensity 0, leveller off), or keep processed.
3. **FFmpeg:** delete it, or make it opt-in.
4. **Enhanced engine:** spike SFBAudioEngine first, or build W4 in-house.
5. **Buy a USB DAC now:** yes or no.
6. **Merge policy:** auto-merge + required check + quarantine, or as today.
7. **Release:** public (licence, notarize, diagnostics), or private alpha.
8. **EP-MCP:** a read-only spike after R1.1, or wait for W2/W3.
9. **Big-library target:** 100k tracks, or 20k.
10. **Transport ownership (W2):** only when a feature needs it, or now as a standalone wave.

---

### Appendix: the experiments
- **Test files (built in `scratchpad/fool-ogg/`):** `ffmpeg` generated `v.ogg` (Vorbis, `-c:a vorbis -strict -2`),
  `o.ogg` / `o.opus` (Opus) and `f.flac`. `ft.flac` / `ot.opus` carry tags.
- **`afinfo`:** opens all of them (`Oggf`, `vorb` / `opus`).
- **`probe.swift`** (`AVAudioFile(forReading:)`) printed `v.ogg OK 44100 88256 · o.ogg OK 48000 96000 · o.opus OK
  48000 96000 · f.flac OK 44100 88200`.
- **`meta.swift`** (`AVURLAsset.load(.metadata)`):
  - `ft.flac`: 7 items, format `org.xiph.vorbis-comment`, including `vorb/ALBUMARTIST=AA` and `vorb/TRACKNUMBER=3`;
  - `ot.opus`: 4 items, including the title and artist.
- **Limits:** one machine (macOS 26, M-series) and synthetic files. Run it over a real corpus before deleting FFmpeg.
  The corpus should include embedded `PICTURE` blocks, multichannel and 32-bit FLAC, and ID3-prefixed FLAC.
- **Repo state:** `gh api repos/ramith/sound-engineering` → `allow_auto_merge: false`, `license: null`; branch protection
  → 404 "Branch not protected"; rulesets → `[]`. The main CI run on `7761693` was still in progress when checked.
