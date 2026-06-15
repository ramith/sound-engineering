# Sprint 3 Kickoff — Music File Playback Implementation

**Start Date:** 2026-06-16 (tomorrow)  
**Target Duration:** 1.5 days (wall-clock, 2–3 parallel developers)  
**Status:** 🟢 GO  
**Plan Reference:** [03-music-playback-implementation.md](03-music-playback-implementation.md)

---

## **Solo Execution (One Developer, Two Laptops)**

**Timeline:** ~3–4 days (sequential, with breathing room)  
**Approach:** Complete one Part per day, with inter-day integration testing

| Day | Owner | Work | Checkpoint |
|-----|-------|------|-----------|
| **Day 1** | You | Part 1a + 1b (Architecture: @Observable + Toolbar) | Build passes, app launches, no jank |
| **Day 2** | You | Part 2 + Part 3a (File picker + FFT setup) | File loading + spectrum tap working |
| **Day 3** | You | Part 3b + Part 4a (Playlist nav + Progress) | Play/pause/next/previous + progress bar working |
| **Day 4** | You | Part 4b + Tasks 4a–4e (Seek + UI polish + accessibility) | Full manual testing, sign-off |

---

## **Day 1: Architecture Foundation**

**Goal:** Complete Part 1a + 1b. App launches, tabs work, no visual regressions.

```
PART 1a: @Observable Migration (2–3 hours)
├─ AudioViewModel: Remove ObservableObject, add @Observable
├─ All @Published properties → plain var
├─ AdaptiveSound.swift: @StateObject → @State
├─ All views: @EnvironmentObject → @Environment(AudioViewModel.self)
├─ Build + test tab switching, device dropdown, volume slider
└─ COMMIT: "Part 1a: @Observable migration + smoke test"

BREAK / LUNCH

PART 1b: Toolbar Restructure (2–3 hours)
├─ HeaderView: move device dropdown → toolbar
├─ Toolbar: Logo | Device | Tabs | Volume (60pt)
├─ Test fit at 800pt window width
├─ Verify no visual regression vs. baseline
└─ COMMIT: "Part 1b: toolbar restructure to 60pt, device dropdown moved"

EOD: Build clean, app launches, tab switching smooth, pre-commit gate passes
```

---

## **Day 2: File System Integration**

**Goal:** File picker works, recursive enumeration works, metadata extraction works.

```
PART 2a–2b: File Picker + Enumeration (3–4 hours)
├─ .fileImporter modal trigger
├─ FileManager.enumerator recursive scan (background queue)
├─ Audio file format filter (WAV, FLAC, MP3, AAC, ALAC)
├─ Folder path bar display + "N files · recursive" count
└─ Manual test: "Choose Folder…" → select folder → list populates

LUNCH

PART 2c: Metadata Extraction + Queue Persistence (2–3 hours)
├─ AVAsset + AVMetadataItem (background task, non-blocking)
├─ Title, artist, album, artwork extraction
├─ Missing metadata → placeholder (no crash)
├─ Full queue persistence: save absolute paths to UserDefaults
├─ Restore on relaunch: repopulate playlist, skip missing files
└─ Manual test: pick file, close app, relaunch → queue restored

EVENING: Integration test
├─ Pick folder → see file list
├─ Metadata populates for one file
├─ Close app, relaunch → folder + queue restored
└─ COMMIT: "Part 2: file picker + enumeration + metadata + persistence"

EOD: File system layer complete. Pre-commit gate passes.
```

---

## **Day 3: Playback Core + Spectrum**

**Goal:** Audio plays through file system, spectrum animates, progress updates.

```
PART 3a: File Loading + FFT Setup (3–4 hours)
├─ AVAudioFile(forReading:) on background queue
├─ scheduleFile() replacing reference tone
├─ Security-scoped URL lifecycle (startAccessing/stopAccessing)
├─ installTap on playerNode for spectrum data
├─ vDSP_fft_zrip + DoubleBufferSnapshot<SpectrumSnapshot>
├─ TimelineView + Canvas (64 bars, log-frequency)
└─ Manual test: pick file, press Play → audio plays, spectrum animates

LUNCH + START 5-MIN SOAK TEST (background)

PART 3b: Playlist Navigation (2–3 hours)
├─ Click file in list → loadFile() + play()
├─ Previous / Next buttons advance queue
├─ Auto-play next on completion (natural-end only, not seek)
├─ Active row highlighting + mini-EQ indicator animation
└─ Manual test: click file → plays, Next button works, auto-advance on completion

EVENING: Integration test
├─ Pick folder, play multiple files in sequence
├─ Auto-play advances correctly
├─ Spectrum animates continuously
└─ COMMIT: "Part 3: file loading + FFT spectrum + playlist navigation + auto-play"

EOD: Playback layer complete. Soak test still running (finish tomorrow morning).
```

---

## **Day 4: Seek + Progress + Polish + Testing**

**Goal:** Seek works accurately, progress bar works, accessibility complete, manual testing passes.

```
MORNING: Soak test check
├─ Verify 5-min soak completed without xruns or memory growth
└─ ASAN clean (run with AddressSanitizer if available)

PART 4a: Progress Polling (1–2 hours)
├─ @Published playbackPosition updated every 100ms
├─ Progress bar shows elapsed / total (e.g., "1:23 / 3:45")
├─ Slider interactive: drag to seek
└─ Manual test: play file, watch progress update, drag slider

PART 4b: Seek Implementation (2–3 hours)
├─ Serial dispatch queue for stop/schedule/play
├─ targetFrame calculation (file native sample rate)
├─ Clamping to file duration
├─ Only natural-end triggers auto-play (seek doesn't)
├─ Accuracy test: seek to 1:30, verify within ±1 frame
└─ Stress test: 5 rapid seeks, no crash

LUNCH

TASK 4c: Module Toggles Display-Only (1 hour)
├─ 2-column grid: EQ (checked), others (unchecked), hardcoded state
├─ Visual styling correct (teal = checked, gray = unchecked)
└─ No functionality yet (Phase 1c)

TASK 4d: Deprecated API Cleanup (1 hour)
├─ foregroundColor() → foregroundStyle() (~8 sites)
├─ cornerRadius() → clipShape(.rect(cornerRadius:)) (~2 sites)
├─ onChange() one-param → two-param form
└─ Build clean

TASK 4e: Accessibility Audit (2 hours)
├─ VoiceOver: all controls labeled, progress slider announces time
├─ Keyboard: Tab navigation, arrow keys on sliders, Space/Return on buttons
├─ Reduce Motion: spectrum animation pauses when enabled
├─ Dynamic Type: text scales correctly, no fixed sizes
├─ 44pt tap targets: all buttons, sliders, rows meet minimum

EVENING: Full Manual Testing Checklist (1–2 hours)
├─ All 20+ test items from Section 5 of the plan
├─ Edge cases: missing metadata, unsupported format, seek past end, rapid seeks
├─ Regression check: Phase 1a features (device, volume, EQ canvas) still work
└─ COMMIT: "Part 4: seek + progress + accessibility + full testing complete"

EOD: Code review own changes, pre-commit gate passes, ready for founder sign-off
```

---

## **Critical Decisions Locked In**

| Decision | Reason | Impact |
|----------|--------|--------|
| **Team 1 owns AudioViewModel on Day 1** | Prevents concurrent writes during migration | Team 2 starts afternoon, after Part 1a checkpoint |
| **64-bar log-frequency spectrum** | Moderate complexity, good visual tradeoff | Budget 1–2 hours for bin-mapping lookup table |
| **Only natural-end triggers auto-play** | Prevents double-advance on rapid seek | Seek's completion handler only sets `isPlaying=false` |
| **Sequential gating on Part 1a** | @Observable affects all views | Checkpoint commit gate before Team 2/3 proceed |
| **Soak test starts Day 2 afternoon** | 5 min minimum; must finish before Day 3 EOD | Runs in background while other work proceeds |

---

## **Pre-Day-1 Checklist (Tonight, ~1 Hour)**

- [ ] Test audio files in `/test-data/`: test.wav, test.flac, test.mp3, test-44khz.wav, test-no-metadata.wav
- [ ] Visual baseline confirmed: `make run` — tabs/header/EQ look good (already done, but fresh confirmation)
- [ ] Pre-commit hook works: `make clean run && pre-commit run --all-files` (or just `swiftformat && swiftlint`)
- [ ] Map out @Observable migration call sites locally (grep for `@EnvironmentObject`, `@StateObject`, `@Published` in all Swift files)
- [ ] Identify deprecated APIs to fix: `grep -r "foregroundColor\|cornerRadius\|onChange.*)" Sources/AdaptiveSound` (fix on Day 1 morning before Part 1a)
- [ ] Verify current branch is `feat/sprint-2-stem-separation` and up-to-date: `git log --oneline | head -5`
- [ ] Both laptops synced: push current work, pull on the other laptop, verify `make run` on both

---

## **Solo Execution Notes**

**No standup needed.** Work heads-down per the day-by-day schedule above.

**Commit discipline (solo):**
- Commit at end of each Part (checkpoint per day)
- Push to remote at EOD to sync both laptops
- Before Day 2 morning: pull from remote on the other laptop to sync

**Switching laptops between days:**
1. EOD: `git push origin feat/sprint-2-stem-separation`
2. Next morning on other laptop: `git pull origin feat/sprint-2-stem-separation`
3. Verify build succeeds: `make clean run`
4. Continue with the next day's work

---

## **Done-Done Acceptance Criteria (Founder Sign-Off)**

**20+ Manual Testing Steps** (from plan Section 5):
- [ ] File picker: choose folder → files populate
- [ ] Format support: WAV, FLAC, MP3, 44.1 kHz transparent SRC
- [ ] Playback: audio begins within 500ms, no dropout
- [ ] Spectrum: bars animate with audio in real-time, pause when paused
- [ ] Progress bar: updates every 100ms, accurate to ±100ms
- [ ] Seek: drag slider to any position, resumes at ±1 frame
- [ ] Rapid seek: 5 consecutive seeks, no crash or glitch
- [ ] Auto-play: file completion → next track plays automatically
- [ ] Metadata: title/artist/album populate from tags, placeholder for missing
- [ ] Session persistence: close app mid-track at 2:34, relaunch → queue + position restore
- [ ] Module display: EQ checked, others unchecked (display-only, no processing)
- [ ] Accessibility: VoiceOver on controls, keyboard navigation, Reduce Motion respected
- [ ] Robustness: unsupported format → error message, no crash; delete file mid-playback → graceful handling
- [ ] 5-min soak: no xruns, no memory growth, no heap corruption (ASAN clean)

---

## **Known Risks + Mitigations**

| Risk | Mitigation | Owner |
|------|-----------|-------|
| Day 1 concurrent writes to AudioViewModel | Sequential gating via Part 1a checkpoint | Team 1 gate-keeper |
| Seek's completion handler triggers auto-play twice | Code comment: only natural-end calls playNext() | Team 2 code review |
| 64-bar bin-mapping implementation scope creep | Use placeholder linear mapping if short on time, mark TODO | Team 2 estimation |
| FFT latency causes perceivable lag | Test 30fps TimelineView cadence locally Day 1 afternoon | Team 2 smoke test |
| @Observable migration leaves dangling @Published | Compile-time check insufficient; code review mandatory | Team 1 code review |
| Session restore fails on sandboxed path strings | Code comment explaining security-scope dependency | Team 3 code comment |

---

## **If You Hit a Blocker**

1. **Search the docs:** Check the full plan (03-music-playback-implementation.md) for guidance
2. **Check Apple SDK:** Use local Xcode docs or check the macOS SDK headers directly
3. **Prototype locally:** Open a test file or Playground to verify the API behavior
4. **Defer to next day:** If unresolved after 30 min, skip that subtask, do adjacent work, circle back next day
5. **Example:** Stuck on `scheduleFile(startingFrame:)` API? Prototype in a test file locally, confirm the param name and types work, then integrate into the sprint work.

**No coordination needed** — just solve it solo and move forward.

---

## **Rollback Plan**

If Day 2/3 reveals a compound failure (e.g., @Observable migration has a silent bug that broke playback state), the rollback point is **Part 1a checkpoint commit**. Revert to that commit and:

1. Diagnose the migration issue on a branch
2. Fix and re-merge Part 1a
3. Rebase Teams 2–3 work on the corrected Part 1a
4. Proceed

This is why the Part 1a checkpoint is hard and required to finish before other work proceeds.

---

## **Success Criteria**

✅ All 20+ manual tests pass (founder sign-off)  
✅ ASAN/TSan clean  
✅ 5-min soak complete, no xruns  
✅ Pre-commit hook passes  
✅ No Phase 1a regressions (device, volume, EQ canvas still work)

---

## **Reference Documents**

- [03-music-playback-implementation.md](03-music-playback-implementation.md) — Full plan
- [Team Review Summary](#) — BA/PM, Audio DSP, SwiftUI Pro feedback
- `test-data/` — Audio test files (WAV, FLAC, MP3, 44.1 kHz, no-metadata)
- `.githooks/pre-commit` — Gate (swiftformat, swiftlint, clang-tidy)

---

## **Last-Minute Questions?**

Ask now. Once Day 1 starts, teams stay heads-down. Use the escalation path above for blocking issues during execution.

---

**Assigned by:** Claude Code + Team Review  
**Date:** 2026-06-15 (evening kickoff brief)  
**Status:** 🟢 READY TO EXECUTE

