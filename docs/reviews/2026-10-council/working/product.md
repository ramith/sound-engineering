# Product council: PM + BA assessment of R1 (v1.0.0-alpha)

*2026-10-13 · product-manager, with the business-analyst lens (requirements traceability, journey fit).
Ground truth is the code at `main` @ a206107; every important claim below cites `file:line`. Docs are
cited only for decisions and rationale. Read-only. Two other agents are rewriting the docs, so doc drift
is noted only where it changes a product decision.*

---

## 0. Bottom line

1. **R1 is a real library player.** Library, browse, playlists, queue, gapless, media keys, an honest
   31-point EQ and the device-loss behaviour all work end to end in the code. It is credible as a daily
   driver for its maker.
2. **The headline promise is not yet the default experience, and it is not hardware-verified.**
   - Pure Mode (bit-perfect) is off at every launch. It is never persisted (`AudioViewModel.swift:98`).
   - A fresh launch plays Enhanced at Intensity 20 % (`AudioViewModel.swift:132`). So the normaliser and
     the limiter run, and the kernel's bit-exact path is skipped (`DSPKernel.cpp:186-212`).
   - The true integer bit-perfect path (USB DAC) has never run on real hardware
     (`docs/sprints/09-phase-b-bit-perfect-pure-mode.md:3,102`).
3. **The "Reimagine Intensity" slider is hollow in R1.**
   - Its wet chain is Clarity → BRIR → Crossfeed (`DSPKernel.cpp:401-407`), and Clarity and BRIR are
     pass-through stubs (`ClarityModule.h:33`, `BRIRModule.h:9,32`).
   - So 0–10 % only fades the loudness normaliser in (`DSPKernel.cpp:37-39,318-321`). From 10 % to 100 %
     nothing audible changes unless crossfeed is on.
   - A control that changes nothing goes against the founder's own Sprint EQ rule: what the screen shows
     must be what plays.
4. **S11 (CUE) is the wrong first step after R1.** What a daily user hits first is a cluster of small
   gaps, none of them in S11–S14:
   - settings forgotten at every launch;
   - no favourites;
   - search limited to one category at a time. The store already has sectioned global search, but the
     app never calls it.
   - roughly 40 logged post-R1 defects.

   Recommendation: a short **R1.1 "daily-driver" sprint**, then **S14 loudness compensation as the first
   R2 sprint**, because it is the earliest and cheapest proof of the "adaptive" thesis.
5. **Phase 2 is only half convincing as written.** The market gaps the research found are transparent,
   user-visible adaptations: level-aware tone, device correction shown on one graph with your taste, and a
   loudness-matched Compare. Masking-aware "Clarity" is unproven. It also pulls against the founder's
   stated taste (faithful over processed). Gate it on a blind listening test.

---

## 1. R1 against the PRD and the user journeys

Legend: ✅ works end to end · 🟡 partial · ❌ missing · ↔ deliberately changed (the docs are stale, the
code is intended).

### 1a. PRD features (P0 = player MVP; P1 = mix core) and the P1 functional requirements

| Requirement | Status | Evidence (code) | Note |
|---|---|---|---|
| P0-1 / FR-PLAY-01 local formats | ✅ | `LibraryScanner.swift:38-39` (flac, mp3, wav, aac, m4a, alac, aiff, aif, ogg); `FileDecodeSource.cpp:7-13` (Apple first, FFmpeg only as a fallback) | Opus/.oga play but are never scanned (known post-R1 item). |
| FR-PLAY-02 controls + media keys | ✅ | `NowPlayingController.swift:89,278,307` (`MPRemoteCommandCenter` / `MPNowPlayingInfoCenter`) | |
| FR-PLAY-03 queue, reorder, shuffle, repeat | ✅ | S10.2 queue; Sprint G fixed mid-song repeat/shuffle | Logged post-R1: shuffle on with repeat off never ends; repeat off mid-song leaves a gap. |
| FR-PLAY-04 metadata + art | ✅ | `TrackInfoCard.swift`, `MetadataExtractor.swift` | |
| FR-PLAY-05 restore last state | 🟡 | Queue, cursor, offset, shuffle and repeat restore (`AudioViewModel+QueueHydration.swift:65-78`) | (1) Saved only on a **clean quit** (`:102-105`): a crash or force-quit loses your place. (2) **Pure, Master Gain, Intensity and crossfeed are not persisted** (`AudioViewModel.swift:98,132,143,184-185`). (3) The restored song shows `--:--` with a dead scrubber (breaker B post-R1 #6). |
| FR-PLAY-06 unsupported-format message | ❌ | Unsupported extensions are skipped silently (`LibraryScanner.swift:182`) | Low value; re-scope it to "tell me what was skipped". |
| P0-7 / FR-TONAL-01 manual EQ, live curve | ↔ | 31-point graphic EQ that plays what it draws (Sprint EQ, PR #73); `EQAudibleState.swift:34-50` | The parametric engine is still S12. |
| FR-TONAL-06 ≥ 8 presets | 🟡 | 7 built-ins (`EQBuiltInPreset.swift:23-43`) plus My Presets | Fine; just reword the requirement. |
| P0-8 / FR-SPAT-03 crossfeed | ✅ | `InspectorColumn.swift:132-210`; `CrossfeedModule` | The founder's by-ear check is still pending (QW1). |
| P0-9 library, queue, drag-and-drop | ✅ | S8–S10; launch catch-up `LibraryModel+Scan.swift:57-67` | |
| P0-10 / FR-TONAL-07 true-peak limiter | ↔ | `OutputCeiling.h:21-22`: −0.1 dBTP on wired outputs, −1 dBTP on Bluetooth/AirPlay | Founder decision 29. The −1 dBTP requirement is stale. |
| P0-10 / LD-17 LUFS normalisation | 🟡 **needs a decision** | `LoudnessModule.cpp:264-287`; `LoudnessModule.h:49-53` | It is enabled only by Intensity's 0–10 % band (`DSPKernel.cpp:37-39`). The meter resets only on `initialize` / channel reconfigure (`LoudnessModule.cpp:51-56,231`), not per track. As I read it, it is a slow (1 dB/s) leveller integrated over the **session**, not track or album gain. There is no ReplayGain read (no match in `Sources/`). Routed to the DSP algorithm panel to confirm. The product meaning is undefined (§6, D5). |
| P0-3 / FR-ADAPT-01 content-aware EQ | ❌ | `ClarityModule.h:33` is a pass-through | S15–S16. |
| P0-4 / FR-TONAL-03 / FR-ADAPT-05 loudness compensation | ❌ | No ISO 226 / equal-loudness code in `Sources/` | S14. |
| P0-5 / FR-DEVICE-01..03 device detect + classify | 🟡 | Enumeration hides private aggregates (Sprint G, `DeviceListPolicy`). Pause on loss: `OutputDevicePolicy.swift:9,110-112`. Per-output EQ pin by UID: `EQStore.swift:91-112` | Classification is a heuristic: wireless or USB = headphones (`AudioViewModel.swift:166-171`), so a USB DAC driving speakers counts as headphones. It only gates crossfeed. |
| P0-6 / FR-TONAL-02 device correction (AutoEq) | ❌ | No AutoEq code in `Sources/` | S12/S13. The market says this is table stakes (`eq-market-research.md` §2.1 item 6). |
| FR-DEVICE-04 named profiles | ❌ | EQ presets + per-output pin only | No sprint home (orphan). |
| FR-DEVICE-06 sample-rate match | ✅ | Pure rate-match (`SignalPathInfo.swift:15-20`: `fullBitPerfect` / `rateMatchedFloat`); Enhanced resamples (SRC measured) | |
| P1-10 A/B with matched loudness | ✅ (**early**) | Hold-Compare (`EQAudibleState.swift:10,48-50`) on a loudness-neutral EQ (`EQTargets.h:26`) | **Already delivered.** Remove it from S12. |
| P1-17 / FR-REIMAGINE-01 Intensity knob | 🟡 **hollow** | UI `InspectorColumn.swift:76-130`; wet chain `DSPKernel.cpp:401-407` with stubs | See §0.3. |
| FR-REIMAGINE-02 / NFR-QUAL-03 "0 % = bit-faithful" | ↔ | Kernel bit-exact path needs Intensity 0 **and** an identity EQ (`DSPKernel.cpp:193-212`) | Founder decision 25. LD-16 in the PRD is stale. |
| NFR-QUAL-03 bit-perfect on real hardware | 🟡 | Pure HAL path + C++ null test | **The integer DAC path has never been exercised on a USB DAC** (`09-phase-b…md:102`; backlog US-ENG-07). |
| NFR-QUAL-01 THD+N | ❌ | No oracle (sprint-plan §2 "open QA gap") | |
| P1-1 / FR-SPAT-01,05,06,07 BRIR + speaker width | ❌ | `BRIRModule.h:9,32` stub | S18; speaker M/S width has no sprint (orphan). |
| FR-SPAT-04 head tracking; FR-ADAPT-04 ambient mic; FR-TONAL-04 bass enhancement | ❌ | none | **Orphans:** P1 requirements with no sprint and no "Won't" tag. |
| FR-UI-01 / 02 / 06 Now Playing, EQ panel, dark/light | ✅ | S10.7 / S10.8 | |
| FR-UI-03 / LD-19 menu-bar extra | ✅ | `AdaptiveSound.swift:198` | |
| FR-UI-04 onboarding wizard | ❌ (spec obsolete) | First-run empty states only | The spec's mic step belongs to unscheduled ambient sensing. |
| FR-UI-05 / NFR-ACC VoiceOver + keyboard | ✅ / 🟡 | Sprint G a11y lanes | Release note: VoiceOver keeps the app busy. The founder's one-time keyboard/VoiceOver walk was the last R1 check; confirm it happened. |
| NFR-L10N-01 externalised strings | ❌ | No `.xcstrings` / `.strings` under `Sources/AdaptiveSound` | Decide: drop or defer. |
| NFR-PRIV-05 sandbox | ❌ (deliberate?) | No `.entitlements` | Fine for direct download. Re-scope the requirement. |
| NFR-INSTALL-01 drag to Applications | 🟡 | `Makefile:41,63-77` ad-hoc signing; `release.yml:9` "Apple trust … later" | Not notarized, so Gatekeeper asks for "Open Anyway". |
| Library domain (FR-LIB reserved) | ✅ | Multi-folder, live watch, launch catch-up, move-match, missing-file handling | Paused folders and reconcile failures are invisible (breaker A post-R1 #8). |
| Playlists (FR-PLIST reserved) | ✅ | S10.1 / S10.3 | Single-click plays on playlist rows (inconsistent; post-R1 #9). |
| "Search" (R1 roadmap claim) | 🟡 | Per-category Filter only: Songs = FTS prefix, grids = substring (breaker A #7) | The sectioned **global** search (`LibraryStore+Search.swift:16-31`) is built and gated, but **no app code calls it** (only `VerifyLibraryStore`). |
| Favourites / ratings | ❌ | `loved` / `rating` columns exist (`Schema.swift:8,183-186`) | No UI anywhere. |

### 1b. User journeys

| Journey | Status | Fit with R1 |
|---|---|---|
| 2.1 First-run onboarding | ❌ as written | The spec is obsolete (mic step, "adapting" tooltip). R1's real first run is "add a music folder", and no journey describes it. |
| 2.3 Normal listening session | 🟡 | Steps 1, 2, 5 and 6 work (gapless, resume). Steps 3–4 (genre and volume adaptation) are missing. Step 1's "same profile" fails for Pure / gain / crossfeed (not persisted). |
| 2.4 Switching output mid-session | ✅ but the spec is **wrong** | The journey says "continues uninterrupted". The founder decided that a disconnect **pauses** (`OutputDevicePolicy.swift:9`), and the freeze is fixed (PR #86). The spatial-mode step is missing (stub). |
| 2.5 Room gets noisy (mic) | ❌ | Orphan: no sprint, not cut. |
| 2.6 System-wide | Won't (this horizon) | Correctly tagged. |
| **Not written at all** | — | The journeys that ARE R1: *add folders → find an album → play*; *build and reorder a playlist*; *resume tomorrow*; *plug in the DAC → Pure*; *tune the EQ for these headphones*. **BA finding:** R1 was accepted through ledgers and break-it passes, not journeys. Writing these 5 player journeys gives R2 an acceptance spine and gives the dogfood week a script. |

### 1c. What R1 claims but doesn't really deliver

1. **"Pure Mode: bit-perfect output straight to your device"** (`docs/releases/v1.0.0-alpha.md`).
   - It is unverified on the hardware it is for (a USB DAC, integer path).
   - It is not the default, and it is forgotten at every launch.
   - On built-in and Bluetooth outputs it is "rate-matched float" (the label is honest:
     `SignalPathInfo.swift:15-20`). On Bluetooth it falls back to Enhanced (the notes say so).
2. **The Intensity slider (in the UI, not the notes):** "Off ↔ Full Blend" over a blend of stubs (§0.3).
   R1's real leveller is hidden in its first 10 %.
3. **"Search"** (roadmap R1 row): filtering within one category only. The global search is built but not
   wired.
4. **"The open list is in known-issues.md"** (release notes): `known-issues.md` lists SEQ-1, DUR-1 (both
   closed) and ENH-001/002. It has none of the alpha's notable issues and none of the ~40 logged post-R1
   items, which live in `s10-8-g-breakit-*.md` and `s10-8-sweep-ledger.md:1261-1349`. The docs-recon PR
   should fix this pointer; it is the first thing an outside tester clicks.
5. **"VoiceOver and full-keyboard support":** credible (Sprint G), but the founder's one-time walk was
   listed as a remaining R1 check. Confirm it happened.
6. *Housekeeping:* I found no local `v1.0.0-alpha` tag ref (`.git/refs/tags` and `packed-refs` are empty
   for it). It may exist only on origin. Confirm that the GitHub Release exists and is marked pre-release
   (`release.yml:72-73`).

---

## 2. Are R2 and R3 still the right next bets?

### 2a. What a daily R1 user hits first. None of it is in S11–S14.

Ranked by how soon and how often you would hit it (product triage of the logged post-R1 items plus the
gaps verified in the code). Effort: S ≤ 2 days, M ≤ 1 week.

| # | Item | Hit | Effort | Source |
|---|---|---|---|---|
| 1 | **Settings forgotten at launch**: Pure, Master Gain, Intensity, crossfeed, Keep-on-device | Every launch | S | `AudioViewModel.swift:98,106,132,143,185`; breaker B #4 |
| 2 | **Restored song shows `--:--`, dead scrubber** until Play | Every launch | S | breaker B #6 |
| 3 | **Cursor saved only on a clean quit** (crash or force-quit loses your place) | After any crash | S | `AudioViewModel+QueueHydration.swift:102-105` |
| 4 | **No global search**: wire the existing sectioned `search()` to ⌘F | Daily | S–M | `LibraryStore+Search.swift:16-31`; breaker A #7 |
| 5 | **No Love / favourites**: the columns exist; add a heart plus a "Loved" list | Daily | S | `Schema.swift:8,183-186` |
| 6 | **Basic smart lists**: Most Played, Recently Added, Loved, from data already stored | Weekly | S–M | play_count / frecency (S10.6) |
| 7 | **Inconsistent click model**: playlist rows play on one click; a paused queue row restarts from 0:00 | Daily | S | breaker A #9, breaker B #10 |
| 8 | **Restore previous queue restores the wrong queue** | Weekly | S | breaker A #4 |
| 9 | **Multi-select drag adds one song** | Weekly | S | breaker A #5 |
| 10 | **Genre "/" split** ("Hip-Hop/Rap" becomes two tiles); case variants split facets | On browse | S | breaker A #2, #10 |
| 11 | **Play stats skewed**: a queue double-click logs two plays; stalled ticks count as played | Silent | S | ledger :1264, :1349 |
| 12 | **Pure correctness tail**: listener leak (a later unplug stops other playback); Pure toggle not applied at a gapless seam; double attenuation after Pure → Enhanced | Pure users | S–M | breaker B #2, #3, #5 |
| 13 | **Unpin silently overwrites the shared EQ** (destructive) | Occasional | S | breaker B #7 |
| 14 | **Paused folders / external drive invisible**; Remove Missing can't tell "unplugged" from "deleted" | External-drive users | M | breaker A #8, #13 |
| 15 | **No explicit volume-leveling setting** (Off / Album / Track; ReplayGain) | Every album | M | §1a LUFS row |

Nice-to-haves from the deferred list:
- **Scrobbling:** a "Could". The play-through rule already uses Last.fm-style thresholds
  (`PlayThroughTracker.swift:5,14`). Do it only if you use Last.fm.
- **Sleep timer:** a "Could".
- **Tag editing: recommend NO.** Mp3tag and Kid3 exist, and "this app never writes into your music files"
  is a trust property worth keeping for a bit-perfect player. Offer "Reveal in Finder" and "Re-read tags"
  instead.

### 2b. Pull forward, cut, re-scope

| Item | Recommendation | Why |
|---|---|---|
| **R1.1 daily-driver sprint** (items 1–13 above, built from the dogfood week) | **Pull forward, before S11.** Timebox: 1–2 weeks. | A daily driver is the R1 exit criterion. These are cheap, and they compound. |
| **S14 loudness compensation** | **Pull forward to be the first R2 feature.** | The cheapest and earliest proof of "adaptive" (§3). It needs only Master Gain (now an honest dB law, `AudioViewModel.swift:179-185`), the device volume, and the accurate 31-point realizer that already exists. |
| **S12 "A/B LUFS-matched bypass"** | **Cut from S12, already shipped** | Hold-Compare on a loudness-neutral EQ (`EQAudibleState.swift:10`, `EQTargets.h:26`). |
| **S12 PEQ realizer + AutoEq import; S13 device correction (two-layer)** | **Keep; do them right after S14** | Table stakes for enthusiast tools. AutoEq's narrow-Q filters need the true parametric realizer (a ⅓-octave graphic engine renders broad shapes, not narrow peaks; `eq-market-research.md` §3.1). |
| **S13 profile JSON import/export** | **Cut to "Could"** | Low value for a solo user. |
| **S11 WavPack / APE** | **Cut to "Could"** | FFmpeg is a fallback only and needs the user to install Homebrew FFmpeg (`FileDecodeSource.cpp:7-13`). Niche on the Mac. |
| **S11 lossy encoder-delay trim (gapless 2b)** | **Re-check, likely cut** | Apple decodes first and trims through the edit list. Only FFmpeg-decoded lossy files are affected, and Opus/.oga aren't even scanned. |
| **S11 CUE** | **Decide on evidence** (D4) | Run `find ~/Music -iname '*.cue' \| wc -l` on your real library. If it is about zero, CUE drops to "Could". |
| **S11 FLAC seek-table / fast-seek check; "metadata panel"** | Keep the seek check (cheap). The metadata panel already exists (`TrackInfoCard.swift`, ⌘I). | |
| **S18 BRIR** | **Keep last, spike-gated** | Highest risk. Apple's own stereo spatialisation with head tracking is the free competitor (R-11 / R-12). |
| **Intensity slider in the UI** | **Hide or replace it in R1.1** (D3) | Honesty. It comes back in S17 when it maps to something real. |

### 2c. Is S11 the right first step after R1? **No.**

S11 is "format breadth for other people's libraries". Your next risk is not breadth. It is whether you
yourself reach for another app during the week, and whether the "adaptive" idea survives contact with your
ears. Recommended order:

**dogfood week → R1.1 (1–2 wk) → S14 loudness compensation → S12 PEQ + AutoEq → S13 device correction
→ S11-lite (FLAC seek check, plus CUE only if your library has it) = R2 → S15 spike, gated (§3) → S16 / S17
→ S18 spike.**

---

## 3. The differentiation thesis

**What the market research actually supports** (`eq-market-research.md` §3.3, opened sources):
- No consumer player documents a **loudness-matched Compare**. We now ship one.
- Nobody shows **device correction and your taste on one graph**.
- **Level-aware tone** exists only as Sonos's static Loudness toggle.

These are real, cheap and *transparent* gaps. The research found **no evidence** that listeners want
opaque, content-adaptive processing on their music.

**Market check on the wedge.** Apple Music on macOS still doesn't switch the device sample rate by itself
(Apple forum, Sept 2025, Sonoma/Tahoe). But the free LosslessSwitcher app does it, and Audirvana, Roon and
Swinsian already offer exclusive or bit-perfect playback. **"Bit-perfect" is table stakes for this
audience, not a differentiator.** It earns entry; it doesn't win.

**Why Phase 2 as written is only half convincing:**
1. **S15–S16 Clarity (masking-aware)** is unproven for music playback. It carries the biggest
   perceptibility risk (R-2: "the EQ is moving"). It also cuts against the primary persona's taste: the
   founder is persona B, and their own recorded preference is "faithful > processed". If the maker lives in
   Pure, Clarity has no user in the house.
2. **S18 BRIR** competes with Apple's free, head-tracked spatial audio on AirPods. Generic-HRTF BRIR
   quality is the known risk (R-12).
3. The roadmap still says adaptation follows "content, level, device, **and hearing**". Hearing was cut on
   2026-07-12.

**Reframe (recommended):** *"It adapts to your device and your volume, visibly, and it never colours what
you didn't ask for."* R3 = loudness compensation + device correction with a strength control + Clarity
**only if it wins a blind test**.

**The smallest demonstrable slice of "adaptive":** level-aware tone (S14-lite).
- **Step 0 (no code, this week):**
  1. The "Bass & Treble" built-in preset (`EQBuiltInPreset.swift:56,69`: bass +5, presence +1, air +3.5)
     is a static stand-in for loudness compensation.
  2. Listen late at night at low volume, then at your normal level, and toggle it with hold-Compare.
  3. Note when you want it.
  4. Read the result: if you want it **only at low volume**, the level-dependent thesis holds for you. If
     you never want it, rethink S14's value before building it.
- **Step 1 (≈ 1 sprint):**
  - **Input:** Master Gain's dB (now honest) plus the device volume, against a one-time "this is my normal
    level" anchor (no SPL meter needed).
  - **Processing:** a fraction (start at 50 %) of the ISO 226 contour difference feeds the existing
    31-point realizer.
  - **Display:** a **ghost curve on the EQ graph** that moves with the volume.
  - **Comparison:** hold-Compare A/Bs it.
- **Validation metric:** in blind trials at −20 dB you prefer compensated ≥ 7/10; at your reference level
  it is ≈ 0 dB, so nothing to tell apart. Never perceived as "moving" (the PRD's own R-2 gate).
- **S15's exit criterion should be the same kind of test:** Clarity vs the static "Clarity" preset,
  blind, on your gear. If it doesn't win, S16 is cut and the effort moves to device-correction depth.

---

## 4. Risks

| Risk | Likelihood / impact | Evidence | Mitigation |
|---|---|---|---|
| **The headline claim is unverified** (integer bit-perfect on a USB DAC) | High / High | `09-phase-b…md:102`; backlog US-ENG-07 | Buy a USB DAC or an audio interface with digital loopback. Run NFR-QUAL-03's loopback bit-compare (MD5) and a by-ear smoke **before** anyone else downloads. Until then, drop "bit-perfect" from public copy. |
| **The default path contradicts the positioning** (Enhanced + leveller at launch; Pure forgotten) | Certain / Medium | `AudioViewModel.swift:98,132`; `DSPKernel.cpp:186-212` | D2: remember Pure; a fresh install is faithful (EQ Off, leveling Off). |
| **Hollow controls erode trust** (Intensity) | Certain / Medium | §0.3 | D3. |
| **A public release with no license** | Certain / Medium | `README.md:11,157-159`; no LICENSE file | Without a license nobody may legally reuse or contribute. GRDB (MIT) ships inside the app, so its notice must ship too. D7. |
| **Not notarized, plus a hidden blocker for notarizing** | Certain / Medium | `Makefile:41,63-77`; `release.yml:9` | Notarizing needs the Hardened Runtime. Its library validation blocks `dlopen` of the user's Homebrew FFmpeg (`FileDecodeSource.cpp:12`) unless the app carries `com.apple.security.cs.disable-library-validation`. Plan that entitlement plus a clean-Mac smoke test (decision 13's "clean-Mac" item was never done). |
| **Quality debt in older core code** | Medium / High | Sprint G found **13 R1 blockers in older code**, including library data loss (G-LIB-01) and audio continuing after unplug; the freeze needed PR #86 | The council's code review covers it. Product-wise: keep a whole-app break-it in every sprint's close-out (retro G-1); don't let the parked concurrency cleanup stay parked past R2. |
| **Solo-founder capacity** | High / High | S10.8 estimated at 3 SP, re-estimated to ~45 SP (`sprint-plan.md:56`); the UX re-gate took about 3 months (2026-07-17 → 2026-10-13); agents were lost to usage limits and permission prompts | Timebox every sprint. The full adversarial panel only for DSP/algorithm work (decision 18 already did this for UX). One PR per sprint stays. Cut S11 breadth (§2b). |
| **The persona is n = 1, and its taste may contradict Phase 2** | Medium / High | Your "faithful > processed" preference | The dogfood path-mix metric (§5) decides it with data. |
| **Market: the wedge is table stakes; Apple can close the gap** | Medium / Medium | Apple forum (Sept 2025); LosslessSwitcher | Differentiate on transparent adaptation (§3), not on bit-perfect alone. |
| **Distribution: no telemetry, no crash reports** | Certain / Low (solo) / Medium (public) | Logging is NSLog-only (`UXLog.swift:7-8`) | For the week: run from Terminal with stderr to a file, and check `~/Library/Logs/DiagnosticReports`. Later (S): move to `os.Logger` with a subsystem so Console can filter it. |

---

## 5. Dogfooding plan: "live on R1 for a week"

**Setup (do once):**
- Use the **release DMG build on your real library**, not a DEBUG / test-library build. The DEBUG launch
  rescan hid G-LIB-05 through every earlier live pass (`s10-8-sweep-ledger.md:1286-1288`).
- Back up `~/Library/Application Support/AdaptiveSound/` with the app quit.
- Make it the **only** player. Every time you open another app, write down why.
- On some days, launch it from Terminal so the `[UX]` log persists. Per your earlier finding, an
  `open`-launched app's NSLog never reaches `log show`.
  `mkdir -p ~/as-dogfood && /Applications/AdaptiveSound.app/Contents/MacOS/AdaptiveSound 2>>~/as-dogfood/ux.log`
- At any beach ball: `sample AdaptiveSound 10 -file ~/as-dogfood/freeze-$(date +%H%M).txt`
- Each day: check `~/Library/Logs/DiagnosticReports/` for AdaptiveSound crash reports.

**Daily metrics (2 minutes, one line per day):**

| Metric | How | Target |
|---|---|---|
| Sole-player days | Tally | 7 / 7 |
| "Reached for another app" | Count + reason | ≤ 3 for the week, none for a missing must-have |
| Plays per day | `sqlite3 -readonly "$HOME/Library/Application Support/AdaptiveSound/library.sqlite3" "SELECT SUM(play_count) FROM tracks;"`, diffed daily (read-only) | Trend only (counts are skewed by item 11) |
| Defects | Blocker (music stopped / wrong song / data lost) · annoying · cosmetic, with time and what you did | 0 blockers |
| **Path mix** (the thesis signal) | Share of listening in Pure vs Enhanced; EQ on/off; Intensity touched; crossfeed used | No target; this decides D6 |
| **Adaptive moments** | Each time you changed volume or EQ to compensate (late-night low level, different headphones, a bright recording) | Raw material for S14 / S13 |
| Friction | Re-enabling Pure after launch; failed searches; playlist mis-clicks; restarts | Feeds R1.1 |

**Scenarios to run once each during the week:**
- add music while the app is closed, then launch;
- unplug headphones mid-song;
- the DAC in Pure (if you have one);
- a long gapless album;
- shuffle a playlist to its end;
- sleep and wake mid-song;
- a clean quit and relaunch; a force-quit and relaunch (expect the place to be lost);
- a Bluetooth device;
- a quick VoiceOver pass;
- the late-night "Bass & Treble" test (§3 step 0);
- by-ear: crossfeed and the presets (the QW1 / Sprint EQ checks are still open).

**End of week (30 min):**
1. Sort every note into R1.1 / R2 / logged / won't, using the post-R1 lists as the base.
2. Exit to R2 when you had 7/7 days, 0 blockers, and no "missing must-have" switch-aways.
3. Use the path mix to decide D6.

---

## 6. Decisions for the founder (recommended option first)

- **D1. What comes right after R1?**
  - **(A) Recommended:** the dogfood week, then a 1–2 week **R1.1** of daily-driver fixes (§2a items
    1–13). Then S14.
  - (B) Start S11 (CUE + formats) as planned.
  - (C) Go straight to the Phase 2 spike (S15).
- **D2. What plays by default, and does the app remember it?**
  - **(A) Recommended:** remember Pure Mode, Master Gain, crossfeed and Keep-on-device across launches. A
    fresh install plays faithfully: EQ Off, leveling Off. (S effort.)
  - (B) Remember settings, but keep today's processed default (Intensity 20 %, leveller on).
  - (C) Leave it as it is.
- **D3. What happens to the "Intensity" slider until S17?**
  - **(A) Recommended:** hide it, and replace its hidden job with an honest **"Volume leveling"** setting.
    Crossfeed keeps its own switch.
  - (B) Keep it, but caption what it really does today.
  - (C) Keep it as it is.
- **D4. Is S11 (CUE) worth doing?**
  - **(A) Recommended:** count the `.cue` files in your library first. If there are about none, CUE becomes
    a "Could"; keep only the FLAC fast-seek check; drop WavPack/APE and the lossy-gap trim.
  - (B) Do S11 in full.
  - (C) Drop S11.
- **D5. What should "volume leveling" mean?**
  - **(A) Recommended:** album-aware leveling from the analysis the app already runs; use ReplayGain tags
    when a file has them; Off by default; a named choice in Settings.
  - (B) Track-by-track leveling.
  - (C) Keep today's session-long leveller, pending the DSP panel's check.
- **D6. Which "adaptive" do we bet on first?**
  - **(A) Recommended:** S14 loudness compensation first, with a visible ghost curve; then device
    correction (S12/S13). S15 Clarity proceeds only if it wins a blind test against the static Clarity
    preset on your gear.
  - (B) Keep the plan's order (S11 → S14, then S15–S17).
  - (C) Drop Clarity now and make R3 "device + volume aware".
- **D7. Is R1 public or yours alone?**
  - **(A) Recommended:** treat it as public:
    - pick a license now;
    - join the Apple Developer Program and notarize (including the FFmpeg library-validation
      entitlement);
    - run a clean-Mac smoke test;
    - verify bit-perfect on a USB DAC before announcing anywhere.
  - (B) Keep it "founder's Mac only": leave it a quiet pre-release, unannounced, with notarization later.
  - (C) Announce it as it is.
- **D8. Which license?**
  - **(A) Recommended:** **GPL-3.0**. Anyone may use and change it, but shared changes stay open. It also
    lets you bundle FFmpeg or other copyleft code later (your memory says LGPL/GPL is OK).
  - (B) **MIT**: the most permissive; closed forks are allowed.
  - (C) No license: legally, nobody may reuse the code.
- **D9. Favourites, smart lists, global search: R1.1 or later?**
  - **(A) Recommended:** R1.1. The data and the search already exist.
  - (B) After R2.
- **D10. Tag editing?**
  - **(A) Recommended: no.** The app never writes into your music files. Add "Reveal in Finder" and
    "Re-read tags" instead.
  - (B) Basic tag editing post-R2.

---

## 7. BA notes for the docs reconciliation (traceability only, not edits)

- **Orphans.** These P1 requirements have no sprint and no "Won't" tag: FR-ADAPT-01, -04, -07, -08;
  FR-TONAL-04; FR-SPAT-04, -06; FR-DEVICE-04; FR-UI-04; NFR-L10N-01; NFR-PRIV-05. Each needs a release
  tag: R2 / R3 / Won't / Withdrawn.
- **Deliberate deviations to record as decisions, not defects:**
  - FR-TONAL-07 → decision 29 (−0.1 dBTP on wired outputs);
  - LD-16 / FR-REIMAGINE-02 / NFR-QUAL-03 → decision 25 (0 % is bit-exact only with the EQ Off);
  - FR-TONAL-01 → the 31-point graphic EQ;
  - Journey 2.4 → pause on disconnect (commit 94b263c).
- **Code-looks-like-a-bug cases.** Per the charter, raise these as findings; never rewrite the
  requirement to match:
  - FR-PLAY-05: settings not persisted; cursor saved only on a clean quit;
  - FR-PLAY-06: silent skip of unsupported files;
  - the normaliser's semantics.
- **Backlog.** The shipped S8–S10 stories (US-LIB-01..08, US-PLIST-01..08, US-PLAY-02..05 and -10,
  US-UI-01/04/05) still carry Planned bodies. S12's A/B story is already delivered.
- **Add the 5 player journeys** (§1b) as R2's acceptance spine. Replace the PRD's Phase-0 KPIs (MAU, D7,
  NPS: no telemetry exists, and LD-9 rules out conversion analytics) with the personal-use KPIs in §5.

---

## Sources

- In-repo:
  - `docs/product/eq-market-research.md` (23 products, opened sources);
  - `docs/sprints/s10-8-g-breakit-library.md`, `s10-8-g-breakit-playback-shell.md`,
    `s10-8-sweep-ledger.md`;
  - `docs/sprints/09-phase-b-bit-perfect-pure-mode.md`;
  - `docs/sprints/s10-8-glass-sweep-plan.md` §B decisions.
- Web (market check):
  - [Apple Community: Apple Music on macOS does not auto-adjust sample rate (2025)](https://discussions.apple.com/thread/256138473)
  - [LosslessSwitcher (GitHub)](https://github.com/vincentneo/LosslessSwitcher)
  - [Darko.Audio: LosslessSwitcher adds bit-perfect Apple Music playback to macOS](https://darko.audio/2022/04/losslessswitcher-adds-bit-perfect-apple-music-playback-to-macos/)
