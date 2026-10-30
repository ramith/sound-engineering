# R1.1-B — sprint record

**Sprint:** R1.1-B — the decided medium items · **Routine:** the full loop, plus the whole-app break-it (it closes the R1.1 release) · **Size:** ~3 weeks as sized against the 2-week cap · **Branch:** `r1.1b/integration`
**What to build and how each item is proven:** [roadmap — R1.1-B](../product/roadmap.md#r11-b-the-decided-medium-items) · [the sound plan](../product/roadmap.md#the-sound-plan-decided-2026-10-23) · **How it runs:** [sprint plan — R1.1-B, how it runs](sprint-plan.md#r11-b--how-it-runs-the-plan-check) · **Process:** [00-sprint-model.md](00-sprint-model.md)

*This record holds the plan check, the founder's decisions at the gates, measured results, the done-done checklist and the retro. Status stays in code and git.*

---

## Plan check (step 0)

The full draft — seams S1–S5 with signatures, the Kit per rule, one owner per file, the design-note questions P1–P6, the counter-examples, the test plan per lane, risks, lane briefs — is [r1-1b-plan-check.md](r1-1b-plan-check.md), drafted read-only from `main` @ 0215f777. Its §0 found nine places where the plan as written did not match the code (Pure declines Bluetooth; album gain has no data source; the fold's peak arithmetic ignored the leveling gain; the engine cannot tell Compare from EQ Off; crash restore is not `QueueRestorePoint`; loose slots cannot persist; "Use this drive" cannot reuse the move-match; the search rule's two halves disagree; size). The answers below settle the founder-facing ones; the rest are design inputs the lanes carry.

## Decisions at the gates

**Plan check — the founder, 2026-10-25** (asked in plain language with options; "≠ R" where the answer differs from the recommendation):

1. **Leveling in Pure is deferred until the USB DAC arrives.** A correction came first: Pure declines Bluetooth, so the XM4 always plays Enhanced; the 2026-10-23 premise that Pure is the founder's daily mode was wrong. R1.1-B ships leveling in Enhanced; Pure shows "Leveling off (bit-perfect)"; the Pure cut on the device volume lands with the USB-DAC check, verified there. The "Volume restored" toast stays — it belongs to Master Gain's existing loan.
2. **Two PRs: the player PR first, then the sound PR.**
3. **The sound parts get a design note and the blind three-reviewer panel** before their code (the one analysis pass, the leveling gain and turn-down, the fold's arithmetic); the state rules and the player lanes get the normal architect + the-fool review.
4. **The founder names a few surround albums and loud masters; the coordinator runs a read-only analysis tool on them**; agents never read the founder's library; the founder does the LFE listen.
5. **Search: one word-start rule everywhere** — each tab keeps its own sort, ⌘F ranked; "eyon" no longer finds "Beyoncé" in the tab filters (accepted).
6. **"Use this drive": rebind silently; songs not on the new drive are removed with their history (≠ R); refused when none are found** — the founder kept the R1 "never wipe on an empty walk" floor when asked about a wrong drive.
7. **Shuffle: Previous at the first song of a pass** — Repeat All goes back into the last pass, Repeat off restarts the song; Up Next keeps the queue's own order this sprint.
8. **The Leveling setting lives in Settings (≠ R)**; S14-lite's Level card is built there too unless the founder decides otherwise then.

**Decided as recommended, unless the founder objects:** track analysis persists in a rebuildable derived-data file beside the library (keyed by file identity), never in the library DB; an album's tracks are analysed in the background once any of its tracks is queued; no library-wide sweep this sprint. Album mode before an album is fully analysed: album tags if every track has them, else the track's own gain until the next seam across silence — the level never steps at a continuous seam. A Leveling mode change mid-song applies at once with a short glide. Sinhala zero-width joiners are folded away in the index and the query (one additive index rebuild).

**The sound design — the founder, 2026-10-26** (after the design note `docs/design/level-and-fold/`, its blind three-reviewer panel and the author's one revision; asked as plain-language options; all as recommended):

1. **Album leveling anchors on the album's loudest song** at −18 LUFS (AES77; Tidal; Grimm 2017) — not the album's average. Either anchor can be switched later without re-analysis.
2. **Auto in shuffle keeps the decided rule:** album level only when the neighbouring song is from the same album; shuffled songs each at their own track level.
3. **The first play of an unmeasured surround track** plays quieter and clean (up to ~9 dB under its eventual level, the limiter never acting), the badge reading "5.1 → stereo · measuring"; exact from the second play.
4. **Albums are measured ahead only within the next ~2 hours of the queue** — Play on a genre or artist never becomes a library sweep.
5. **7.1 → stereo:** the four surrounds at half level each.
6. **Unknown loudness:** −5 dB for now; revisited once the founder's named files are measured.
7. **A never-measured song with an EQ on** starts at once; its level settles within the first second, on that first play only.

**During the build — the founder, 2026-10-28 / 30:**
- **Lanes stay at two agents at once** (asked when lane 1 sized at 13 days and was split; "measure" waited for a slot).
- **A scrub while playing saves your place at once, like a pause** (asked when the crash-restore stress test showed a
  small backward scrub could resume up to ~5 s off). Only the song's own progress waits for the 5 s cadence.
- **In Track mode, a run of songs that join without a pause shares the level of the run's own loudest member**, not
  the whole album's (asked when lane 3 sized and found backlog item 7 and plan check §6 disagreeing). When the run
  is the whole album the two are the same; the level never steps mid-music either way.
- **Only silence is a gap (2026-10-30):** two songs are continuous unless the edge between them is near-silent (below
  −70 LUFS, BS.1770's silence gate), replacing the design's −50 LUFS. On the founder's live show, applause and room
  sound ran through 3 of 4 pauses, and at −50 the level stepped 6.9 dB inside the applause at 34:15 (lane 3-A, corpus
  9i). Two separate recordings with room sound at their edges now join one run (0 dB change on the corpus album 9g).
- **The first play of an unmeasured surround track may be ~10.5 dB under its measured level on Bluetooth
  (2026-10-30)**, not the "~9 dB" first stated: the safe trim also covers Bluetooth's headroom, and the limiter never
  acts. Exact from the second play.
- **Next on a shuffle pass's last song with Repeat off** stays enabled but does nothing (the design's rule). Logged as
  polish (KI), no change to PR 1.
- **The sound UI (2026-10-30, after the SwiftUI review):**
  - Leveling stays second in Settings, after Output Device.
  - On a folded file with Pure asked for, Now Playing shows the "5.1 → stereo" badge, not a second "Pure off:
    channels" chip (once the badge row's overflow is fixed).
  - **All EQ editing is inactive in Pure**: the graph, presets, Reset and Save as well as the switch and Tone.
    Nothing you can't hear can be changed, and the switch never flips by itself. **The presets' Rename and Delete
    stay inactive too**: one rule for the whole list (asked after the UI fix round, which found that they don't
    change the sound).
  - The shared note reads **"Off in bit-perfect mode"** (was "Not in bit-perfect mode", which read as "Pure is off").
  - **VoiceOver keeps an inactive control's value and gives the state as a hint** ("Leveling, Auto, dimmed" + "Off
    in bit-perfect mode"); US-R1F-20's VoiceOver line changes with it.
  - Coordinator: the EQ strip's "Open Settings" is aligned on "Leave Pure" (one name for one action).
- **Coordinator, on lane 3-A's report:** the scheduler's QoS rule is kept (due within 10 min → `.utility`; further
  ahead → `.background` if it still finishes in time, else `.utility`; one job below 2× real time). Measured: no
  playback, UI or resampler deadline misses with two DXD analyses at `.utility`; a 4-album horizon, hi-res included,
  done in 314 s. A gain tag implying a loudness outside −70…0 LUFS is ignored, and tags never raise a track.
- **A song that can't be played is skipped (2026-10-30, after the break-it's LOW-4):** the banner says why, and
  playback moves on to the next song, whether Play was pressed on it or the queue reached it. The song stays in the
  queue, unmarked. If no song left can play (one full pass fails, under Repeat All and in shuffle too), playback
  stops with the message. Before, the queue stopped at the broken song.
- **The words for a song that can't play (2026-10-30):** "This file type isn't supported (.xyz)." / "This file can't
  be read — it may be damaged (.flac)." / "macOS can't decode this kind of file (.opus)." (5.1 Opus; a FLAC with
  blocks under 192 samples, which is legal but which Apple's decoder refuses) / "This file can't be found — it may have
  been moved, or its drive disconnected." / "Skipped “<song>”. <reason>" / "Playback stopped — no song left in the
  queue can be played. <reason>". The banner names the song by its title as the queue shows it, falling back to the
  file name. Before, every failure read "This file type isn't supported". **When the last song can't play** (nothing
  left to move on to after one song), the banner names it: "Couldn't play “<song>”. <reason>" — not "Playback
  failed: …" (VM-AA-08 pins it).
- **Coordinator, on the break-it (2026-10-30):**
  - **A resume keeps the song's level; a new play decides it again.** Pause → Play continues the same listen, so the
    level never steps mid-song, even when the analysis landed during the pause. Play after Stop, after the queue
    ended, Previous restarting the song, or Repeat One is a new listen, and takes the measured level.
  - **In shuffle every song plays at its own level, in Auto and in Track mode.** A run shares its loudest member's
    level only between songs that join without a pause in play order; shuffled songs never join.
- **Coordinator, in the sound fix round (2026-10-30):**
  - **Off follows the same play-order run rule**: a song played alone or shuffled keeps its own fold trim, not its
    run's worst; songs that join in play order share the run's, so the fold never steps at a continuous seam.
  - **`LevelingSetting` stays, for now, as an alias of LevelingKit's `LevelingMode`** (one enum; the stored words
    unchanged); folding the alias away is a later tidy-up (review N6).

**Test data — the founder, 2026-10-28:** the sprint proceeds on the test corpus as it stands; the gaps are recorded
below ([Test material](#test-material)), and the founder supplies the missing data later. No lane waits for data.

Still the founder's, by ear: **the LFE include level** (−6 dB per side recommended; full level; +4 dB) — decided by the two-album listen; all three are measured, so no re-analysis. Not this sprint: a ten-minute by-ear Compare match before S14-lite's blind tests.

## How it runs (revised after the plan check)

At most two agents at once. The player PR comes first.

| Step | Slot A | Slot B |
|---|---|---|
| Before the lanes | **Coordinator:** the integration branch's first commit — the new targets in `Package.swift` (LevelingKit + tests, empty), the S5 slot type `QueueSlotRef`, migration numbers assigned (v10 queue state → lane 4; v11 search re-index → lane 5) | — |
| W1 — player | **Lane 4 — transport** (Swift): shuffle permutation + history; the atomic crash-restore record `QueueResumeRecord` with one coalescing writer; loose slots persisted by path (S5) | **Lane 5 — library** (Swift): `SearchRule` + ⌘F; loose files (Open…, drop, Open With, into a playlist); "Use this drive" (S4: re-root by relative path, missing removed, refused at none found) |
| W2 — player close-out ∥ sound design | **Player PR:** combine → T3 → slow checks (10k library, ⌘F with FKA; 100 kills) → review + break-it (QA agent + the-fool: store/library, transport) → one fix round → T4 → founder's check → **PR 1** | **The design note** (audio-DSP): `docs/design/level-and-fold/` — the analysis pass, album pooling (P2), the cap and turn-down with the leveling gain and the N-channel peak (P1, P3, P5), the LFE rule (P4), Compare (P6) |
| W3 — the panel | Reviewer 1 — the breaker; then reviewer 3 — architect + the-fool | Reviewer 2 — the state-of-the-art challenger; then the author's one revision |
| W4 — sound build | **Lane 1 — sound core** (audio-DSP): the analysis pass + persistence, the level stage, the turn-down, Compare matched, the old leveller deleted | **Lane 2 — fold** (a fresh audio-DSP): the matrix from roles, the per-track trim with the leveling gain, the LFE gain, the backstop + meter, the crossfeed-bypass signal (S2) |
| W5 — sound UI | **Lane 3 — leveling app side + sound UI** (Swift, SwiftUI review): LevelingKit (Auto, sources, album scope), the coordinator, the Leveling row in Settings, the shared "Not in bit-perfect mode" state, the "5.1 → stereo" badge, the Pure reason, the XF chip from S2, "Volume restored" | — |
| Sound close-out | **Sound PR:** combine → T3 → slow checks (the founder's corpus via the read-only tool; the gain-reduction meter) → review + break-it (audio) + **the whole-app break-it** (release close-out) → one fix round → T4 → founder's check incl. the two LFE albums → **PR 2** → the R1.1 release decision | — |

Lane 3 is one lane again: with the Pure loan deferred, the plan check's 3a / 3b split no longer pays.

## Measured results

*(filled as lanes land: the measurement named by each acceptance line, as a number)*

- **Mono on the founder's XM4 (live, 2026-10-26):** a 44.1 kHz mono file opened in the sprint build plays in **both ears, centred** — the offline render's left-only result (design verify, F8) does not happen on the real device. Mono keeps today's format; the design's +3.01 LU mono correction stands.
- **The live keyboard pass (10k test library, Full Keyboard Access on):** ⌘F from all five shell tabs lands in the Search page's field; ⌥⌘F in Songs / Albums / Artists / Genres keeps the category and focuses its own filter; "ada" shows results 0.74 s after typing starts, "ada lau" 0.43 s; idle CPU 0.7 %. A single CJK ideograph is below the 2-character gate and shows nothing — fixed in the fix round.
- **The combined check (T3) on the player half:** 29/29, exit 0 (1,035 Swift tests, 245 C++ null tests, the main-thread stall check, VerifyLibraryStore 176/176).
- **The player fix round (2026-10-26)** — review + break-it gave 16 library/store and 6 transport findings.
  - **Transport:** 6/6 fixed: the launch join as a Kit rule, a bulk shuffle edit writes once, a playhead-only write
    builds no record, a failed restore read retried once and the writer kept closed after a second failure, removing
    the selected song under shuffle selects the pass's next, and the old "current" playlist entries cleared after
    the first record write.
  - **Library and store:** 15/16 fixed:
    - **Migration v12:** a removed song's id is never handed to another.
    - **"Use this drive":** keeps the drive's own path spelling and (dev, inode), deletes the missing songs
      first, refuses any other clash, says "Checking the drive…", and rebinds the other paused folders on the
      same old drive.
    - **Migration v13:** a lone combining mark is no word; variation selectors are ignored. The index form is pinned
      and VerifyLibraryStore checks it.
    - **One search gate everywhere:** two characters, or one ideograph, kana, Hangul syllable or Brahmic syllable.
    - **⌘F:** a superseded search is cancelled.
    - **Open With and drops:** they wait for the store to open, then match the library, off the main thread and in order.
    - **File types:** `.mpga`, `.wave`, `.bwf` and `.adts` play; Info.plist no longer claims `public.mpeg-4-audio`.
  - **Not fixed:** N8. SwiftUI has no placement for the Find menu items alone; the reason is recorded beside the command.
  - **Two break-it tests changed at the fix, as their lane reported.** BI-P05 was rewritten: its stand-in store meant both
    "opening" and "never opens", so it now opens while the store is opening and checks that the open waits. BI-P01/P02's
    precondition required the reused id, which is the bug itself.
- **The combined check (T3) after the fix round (2026-10-26):** 29/29, exit 0 — 1,082 Swift tests, 245 C++ null
  tests, the main-thread stall check, VerifyLibraryStore (schema v13, 182 checks). Both fix branches applied cleanly.
- **The sound lanes (2026-10-28 / 30)** — each lane's acceptance numbers; "provisional" marks a result on stand-in data
  ([Test material](#test-material)):
  - **The analysis against the answer key:** 61 of 61 EBU / ITU loudness signals with a verdict pass (integrated within
    ±0.1 LU, worst 0.048; true peaks within +0.2 / −0.4 dB); 19 of 19 voice files resolve every channel's role to its
    label's, in every codec order.
  - **F1 on the corpus, through the real bridge:** every voice in its labelled slot (AAC and ALAC 5.1 at 44.1 kHz: 0 of
    16 windows before, 16 of 16 after); Pavlik's 5.0 at 88.2, 96 and 352.8 kHz plays all five channels (C, Ls, Rs were
    absent).
  - **The fold's backstop over the corpus's surround files:** under 0.01 dB of gain reduction with the trim (worst
    0.004 dB); untrimmed it would have worked up to 6.15 dB (THX *Amazing Life*). Provisional.
  - **The leveled corpus (lane 3-A's harness, Bluetooth):** the 15 loud masters at −18.00 LUFS in Track mode, the
    limiter 4.2–9.0 dB clear (provisional); no level step at any continuous seam of the continuous albums or the live
    show, in any mode (provisional); the lossless classical album 9g anchored on its loudest song, Album and Auto
    one gain for all four (not provisional).
  - **The analysis's cost (M4 Pro, one job, a 4-minute track):** under two minutes for every class at default QoS
    (hi-res about one minute); 3.8–4.4 minutes for hi-res multichannel at `.background`, which the scheduler's deadline
    rule answers. A four-album horizon, hi-res included, analysed in 314 s with no playback, UI or resampler deadline
    missed.
- **The combined check (T3) on the sound half (2026-10-30):** 29/29, exit 0 — 1,206 Swift tests, 294 C++ null
  tests, the main-thread stall check, VerifyAUGraph, VerifyLibraryStore.
- **The sound break-it and the whole-app break-it (2026-10-30)** — 2 HIGH, 3 MEDIUM, 6 LOW; 12 red tests (BI-S01…S03,
  S05…S12, S20), plus BI-S04 (the crash harness's control) and BI-S21 (a store guard), which pass:
  - **HIGH:** KI-PB-22 proven — a FLAC with blocks under 192 samples killed the app on Play at any rate but 48 kHz and
    at any gapless seam into one (BI-S01…S03); mono leveled 3.01 dB loud in every mode (BI-S09; corpus 05 at −15.3
    LUFS).
  - **MEDIUM:** a direct replay kept the first, unmeasured play's decision (BI-S06, S07); Auto in shuffle took a
    continuous run's level (BI-S10); 48 kHz AC-3 / E-AC-3 tracks ended about 1 s early (BI-S05).
  - **−18 LUFS end to end** — the app's own analysis → the decision → the real bridge → ffmpeg's `ebur128`: stereo at
    22.05 kHz through the resampler **−18.0**; a loud classical track (g −7.80) **−18.0**; THX *Eclipse* folded
    **−17.9** (true peak −3.0 dBTP, the backstop at 0 dB); cap-bound by design: *Vienna 1728* 5.0 −18.6, corpus 34
    −21.1, Dohnányi −18.8. **The first unmeasured surround play** (corpus 34, forced): −31.6 LUFS, **10.5 dB under**
    its measured play, clean (gain reduction 0).
  - **TSan:** 0 warnings over 97 Swift tests (the leveling bridge, fold, coordinator, store, scheduler, seams, seeks,
    resampler, end of queue, engine lifecycle, crossfeed, sound UI, "Use this drive", multichannel sources).
  - **The library at 10k:** the stress library (10,043 files) scans into a temporary store in **4.65 s**; searches take
    **≤ 4 ms**; a Sinhala name is found with and without its zero-width joiner; FTS syntax finds nothing, with no error.
  - **Picture sheets:** 226 of 226.
  - **Cleared:** truncated files end at their cut, with no crash and no hang (KI-PB-23); the other broken files are
    refused at open without a crash.
- **The sound fix round (2026-10-30)** — four lanes in two waves, the reader and leveling, then the analysis and the
  UI; each new test was first seen failing, and the stress runs (20 of 20) and TSan were clean on every lane.
  - **The reader** closed HIGH-1 (KI-PB-22: the bridge reads through its own counted reader, probes every file at open
    and at every seam, and never touches `framePosition`), MEDIUM-3 and LOW-6 (a lossy 48 kHz file streams through the
    reader unconverted and ends on its last frame), LOW-3 (three kinds of refusal, each with its words) and LOW-4 (the
    founder's "move on").
  - **Leveling** closed HIGH-2 (review B1: mono's width), MEDIUM-1 (a start says resume or new play; review B2, N2,
    N3), LOW-1 (a mode change's decisions name their songs; review S2), and review S1, S3, S4, S7, N4, N5, N12, N14 and
    N16 (one glide law).
  - **The analysis** closed MEDIUM-2 (a run is shared only in play order), LOW-2 (the store never deletes a file it
    could not lock; review N9), and review N1, N6, N8, N10, N11; "· measuring" shows only while a measurement is
    coming; a new play starts the loudness readout afresh.
  - **The UI** closed the UI review's must-fixes M1–M4 and its S1–S6, the sound review's N13 and S6 (a Semgrep rule
    holds every DSP control to its row; Intensity, never registered, now is), the founder's UI decisions, the rows
    going live when Pure paused, and the missing-file words.
  - **Became known issues:** review S5 (KI-MC-03, ~1–1.5 days, the W2 transport owner) and N15 (KI-LEV-03, ~1.5
    days), the break-it's LOW-5 (KI-LEV-01) and its ReplayGain 1 observation (KI-LEV-02), the analysis lane's
    candidates (KI-LEV-04…06) and the reader lane's (KI-PB-26; KI-GAP-01's evidence).
  - **Measured after it, on the corpus through the real bridge:** corpus 05 (mono) **−18.0 LUFS** (was −15.3);
    corpus 34 over its first 20 s, measured play then Pause → Play, **−30.0 / −30.0**, and replay after Stop **−30.0**
    against −40.5 for its first, unmeasured play; THX *Eclipse* measured / after resume / first unmeasured / replay
    after Stop −35.0 / −35.0 / −40.2 / −35.0 (20 s figures are relative); files 45, 43, 42 and 32 (AC-3 / E-AC-3 at
    48 kHz) **end on their last frame** (they ended ~1 s early); truncated 111 and 112 end exactly at their cut; a mode
    change that trades g for the trim swells **0.055 dB** (was 1.18 dB, LG-1).
  - **Tests changed at the fix, as their lanes reported:** LB-2 pinned the bug ("a fresh start of the same song sends
    nothing") and now pins the resume / new-play rule; LB-6 was retired with the fallback it pinned; VM-AA-08 and
    REARM-OPEN-FAILS pinned "a refused start stops the queue" and now pin "move on"; DEC-05 and DEC-10 now state the
    album order they meant.
- **The combined check (T3) after the sound fix round (2026-10-30):** 29/29, exit 0 — 1,283 Swift tests, 294 C++
  null tests, the main-thread stall check, VerifyAUGraph, VerifyLibraryStore.

## Test material

The sound half is measured on the test corpus at `~/music-test-data`. It lives outside the repo and is never
committed or shared. Its `README.md` maps every file to the lane, acceptance line or check that uses it. The parts:

- `manifest.json`: what Apple's decoder reports, per-channel level, BS.1770 loudness and true peak as is and on the
  BS.775 fold.
- `conformance.json`: the loudness answer key.
- `tools/`: rebuild and re-measure everything.

The corpus was gathered 2026-10-26 and is not the founder's library. Agents may use it, playing only through the
test-library app. What it covers:

- **The IAA channel test:** a voice per channel. It is the ground truth that Apple's decoder labels every channel
  correctly in every codec order, so a voice in the wrong ear is our bug.
- **The official loudness signals:** EBU Tech 3341/3342 v05 and ITU-R BS.2217. The 65 signals with published answers
  all pass on a BS.1770-4 meter, and **the analyzer must match them**.
- **Real music:**
  - Pavlik Records stereo and 5.0 classical, up to 352.8 kHz
  - Dolby and THX trailers
  - five loud tracks the founder named from their own collection, −7.2 to −12.4 LUFS. They are MP3s; ffmpeg
    decodes them to +2 dBFS, but Apple's MP3 decoder clamps at 0 dBFS, so the app receives them already clipped.
  - the founder's 37.5-minute live orchestral show, cut into a nine-piece live album
- **Generated material:** loud masters (limited, hard-clipped to +4.3 dBTP, float with peaks above full scale), a
  continuous album in seven variants (ReplayGain complete, partial, none, wrong; gapless MP3; gapless and padded AAC),
  a mixed-level album, every rate from 8 to 384 kHz and every bit depth, and broken files.

**The gaps, recorded 2026-10-28.** The founder supplies these later; `~/music-test-data/WANTED.md` is the search brief.
Until they arrive, **any acceptance result that rests on a stand-in is marked "provisional (stand-in data)"** in this
record and re-run when the real file arrives.

| Missing | Stand-in now | What stays provisional |
|---|---|---|
| A lossless 5.1 music album whose LFE carries music | The Atmos music tracks decoded to 24-bit 5.1 FLAC; THX *Amazing Life* (film LFE) | The founder's LFE include-level listen, and the LFE rule's measured cases |
| A lossless loud master | The founder's loud MP3s; the generated lossless loud masters | Leveling's loud-master acceptance (turn-down, the cap, the limiter never acting) on a lossless real master |
| A lossless real album whose tracks run into each other | The live show cut into nine pieces (the source is an MP3); the generated continuous album | Album leveling and the seam checks on a lossless real album |
| Report ITU-R BS.2217; EBU Tech 3341 | The 65 judged signals; true-peak answers for 3341 signals 15–23 from memory (all pass) | The 8/10/12/24-channel conformance signals: no verdict until the channel maps arrive |

**Corpus findings for the sound build and its break-it** (the README has the files):

1. **F1 can be reproduced on demand.** Three sets of files trigger it:
   - AAC and ALAC 5.1 at 44.1 kHz, in the C L R Ls Rs LFE order
   - voice files at 3–8 channels and 44.1 kHz
   - real 5.0 music at 88.2, 96 and 352.8 kHz
2. **Many multichannel WAVs carry no layout at all** (the ITU and EBU signals arrive as D0…Dn), so the role
   resolver's count fallback must assume WAV order.
3. **The fold overloads on real music:** Schumann 5.0 +0.7 dBTP, *Vienna 1728* 5.0 +0.9, *Live up the Night* +0.1;
   trailers reach +2.0. The per-track trim is not optional.
4. **A suspected crash.** On a FLAC with blocks under 192 samples, Apple's decoder throws on read, and setting
   `AVAudioFile.framePosition` raises an uncaught NSException. The app sets it in `AudioEngineBridge+EnhancedResampler.swift`
   and `+GaplessRoll.swift`. The whole-app break-it proves or clears it.
5. **The other broken files fail softly.** 5.1 Opus won't open on macOS 26, although the scanner admits `.opus`.
   Truncated files open with their full length and fail at the cut.
6. **Gapless depends on the encoder.** LAME MP3 and Apple-encoded AAC are sample-exact. ffmpeg-made AAC comes back
   padded to whole packets, which the app cannot fix.
7. **ReplayGain's album gain is not the app's album anchor.** It differs by 1.3 dB on a mixed-level album, by design.

## Done-done

```
Sprint R1.1-B — the decided medium items · routine: full · SP 8+8+player items · cap 2 weeks (≈3 as sized)
Plan check   ☑ routine named ☑ owners and seams named (stubs agreed) ☑ Kits named
             ☑ lanes and waves ☑ counter-examples for rule changes ☑ founder check written
Build        ☑ every acceptance line of the roadmap row met by its named measurement
               (stand-in results marked provisional; the LFE include level waits on the founder's listen)
             ☑ tests on the real code ☑ every breaker's red test committed
Gates        ☑ T3 combine-check exit 0 (both halves, and after each fix round)
             ☐ T4 strict-gate / CI exit 0, run complete — PR 1's: 35/35, exit 0; the sound half's is running
             ☑ break-it findings fixed, or logged in known issues with a forward (both fix rounds)
             ☑ the whole-app break-it (release close-out)
Founder      ☐ checklist passed (by ear / eye / hand) ☐ the two LFE albums, pass / fail
               — the player half's check was done before PR 1 merged; the sound check, the two LFE albums
                 included, is pending
Merge        ☑ PR 1 (player) merged by the founder (#101) ☐ PR 2 (sound) merged by the founder
             ☐ main CI green on the merge commit — the founder watches CI
Close        ☐ this record + five-line retro ☐ known issues ☐ sprint-plan §Status line
             ☐ documents reconciled (plan + reasons only) ☐ memory updated
             ☐ worktrees removed (no running app inside) ☐ points and duration recorded
               — the close items: drafted with PR 2, ticked at the close; the retro after the merge
```

## Retro

*(at close-out)*
