# PHASE 1B PART B: Critical Path Kickoff

**Unblocks:** Phase 1c (Sprint 1–3)  
**Timeline:** 2026-06-18 → 2026-06-21 (effort-driven; calendar is target only)  
**Owner:** You (solo dev)  
**Status:** Ready to start

---

## Vision

Phase 1b Part B delivers the **critical path items** that make Phase 1c possible. Without progress/seek/auto-play, DSP testing is crippled. Without a working test suite, DSP changes can't be validated.

---

## Critical Path (Must-Have, 2.5 Days)

### 1. Progress Bar + Polling (1 Day)

**What:**
- Playback position display (elapsed / total duration)
- Real-time polling (playerNode.playerTime every 100 ms)
- Slider UI (user can see where they are in track)

**Why:** DSP validation requires knowing playback position (can't test if you can't see where you are)

**Acceptance Criteria:**
- [ ] Progress bar visible on Now Playing view
- [ ] Updates every ~100 ms (smooth, not twitchy)
- [ ] Format: "1:23 / 3:45" (MM:SS / MM:SS)
- [ ] Accuracy: ±150 ms (polling-based variance acceptable)
- [ ] No crashes on rapid time changes

**Implementation Notes:**
- Use `playerNode.playerTime` property (polling is simplest)
- Update Timer every 100 ms (or use DispatchSourceTimer)
- Format time strings with DateComponentsFormatter
- Store elapsed / total in @State (observable)
- No RT considerations (UI-side only)

**Testing:**
- Play music, watch progress bar advance
- Verify time display matches audio progress (spot-check 3–4 points)
- Test edge cases: jump from 0:00, reach end

---

### 2. Seek Implementation (1 Day)

**What:**
- Draggable progress slider
- Click/tap slider → resume playback at that position
- Frame-accurate positioning (±1 frame @ 48 kHz = ~21 µs, imperceptible)

**Why:** Essential for DSP testing — can't validate EQ effect mid-song without seeking

**Acceptance Criteria:**
- [ ] Slider thumb draggable (SwiftUI Slider)
- [ ] Drag to position → seek happens immediately
- [ ] Resume playback at new position (no pause)
- [ ] Accuracy: within ±100 ms (human perception threshold)
- [ ] No glitches/clicks at seek point
- [ ] Stress test: 5 rapid seeks, no crash

**Implementation Notes:**
- AVAudioPlayerNode: call `stop()`, then `scheduleFile()` with targetFrame
- targetFrame = (seekTime * sampleRate) in frames
- currentFile.audioFormat.sampleRate gives frame rate
- No RT considerations (seek is scheduled off-RT)

**Core Code:**
```swift
func seekTo(seconds: Double) {
  playerNode.stop()
  
  let targetFrame = Int64(seconds * Double(audioEngine.sampleRate))
  let audioFile = currentFile.audioFile // cached reference
  
  let range = AVAudioFramePosition(targetFrame) ..< audioFile.length
  playerNode.scheduleSegment(audioFile, fromSamplePosition: range.lowerBound, 
                             framesToPlay: UInt32(range.count), at: nil) { }
  
  if !playerNode.isPlaying {
    try? audioEngine.start()
    playerNode.play()
  }
}
```

**Testing:**
- Play music, drag slider to 50% mark
- Verify audio resumes at correct position (no gap, no glitch)
- Repeat at 25%, 75%, 95%
- Rapid-fire seeks (5 consecutive seeks in 2 seconds)
- Verify no crashes, no audio artifacts

---

### 3. Auto-Play Next Track (0.5 Day)

**What:**
- When current track finishes naturally → auto-advance to next track
- Respect repeat mode (all/once/off)
- Smooth transition (no gap)

**Why:** Realistic playback (users expect auto-play). Required for soak tests (continuous playback).

**Acceptance Criteria:**
- [ ] Track completion detected (AVAudioPlayerNodeBufferCompletion callback)
- [ ] Next track loads + plays automatically
- [ ] Repeat all: loop to first track after last
- [ ] Repeat once: stop after track finishes
- [ ] Repeat off: auto-advance, but stop at end of playlist
- [ ] No gap between tracks (smooth transition)
- [ ] Spectrum continues reading smoothly

**Implementation Notes:**
- Install completion handler on playerNode
- In handler: check repeat mode → advance or stop
- Load next track via audioViewModel.advance()
- Call playerNode.play() to resume

**Core Code:**
```swift
playerNode.installTapOnBus(0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
  // This tap fires when buffer is consumed
  // Schedule next track when current is about to end
  DispatchQueue.main.async {
    if self?.shouldAutoAdvance() ?? false {
      self?.advance()
    }
  }
}

// Or use completion callback (cleaner):
playerNode.completionHandler = { [weak self] in
  DispatchQueue.main.async {
    if self?.shouldAutoAdvance() ?? false {
      self?.advance()
    }
  }
}
```

**Testing:**
- Play 3-track playlist, let it run
- Verify first track plays → second auto-starts (no gap)
- Verify second → third transition
- Test repeat modes: all/once/off
- Listen for audio gap (none should be present)

---

### 4. Fix Test Suite (0.5 Day)

**What:**
- Add `.testTarget()` to Package.swift
- Restore EQTests.swift to running state (currently may be broken)
- Run `swift test` — all tests pass

**Why:** Validates EQ coefficient math. Non-negotiable for Phase 1c (can't validate DSP changes without tests).

**Acceptance Criteria:**
- [ ] Package.swift has testTarget with correct dependencies
- [ ] swift test runs successfully (0 failures)
- [ ] EQTests.swift covers: null-test, frequency response, gain linearity, stability
- [ ] All tests pass
- [ ] No timeouts (each test < 5 sec)

**Implementation Notes:**
- In Package.swift, add:
  ```swift
  .testTarget(
    name: "AudioDSPTests",
    dependencies: ["AudioDSP"], // your audio DSP target
    path: "Tests/AudioDSP"
  )
  ```
- Move/create EQTests.swift under Tests/AudioDSP/EQTests.swift
- Import AudioDSP, XCTest
- Test structure:
  ```swift
  func testNullResponse() {
    let eq = EQModule()
    let input = [Float](repeating: 0.5, count: 1000)
    let output = eq.process(input, gains: [0] * 31) // All 0 dB
    XCTAssertEqual(input, output, accuracy: 1e-6)
  }
  ```

**Testing:**
- Run `swift test -v` — verbose output
- Each test should complete < 5 sec
- No skipped tests
- All assertions pass

---

## High-Value (Optional, Deferred if Tight, 2 Days)

### Metadata Extraction (1 Day)

**What:**
- Read ID3 tags (MP3), Vorbis comments (FLAC/OGG), MP4 atoms
- Populate Now Playing widget: title, artist, album, artwork
- Fallback to filename if metadata missing

**Why:** Conversational tuning needs track context ("Make this song's vocals pop"); filename fallback acceptable for Phase 1c.

**Defer if:** Part B is running over schedule

---

### Queue Persistence (1 Day)

**What:**
- Save full track list + playback position to UserDefaults
- Restore on app launch
- Handle missing files gracefully

**Why:** User testing (realistic workflow); in-memory session acceptable for Phase 1c MVP.

**Defer if:** Part B is running over schedule

---

## Execution Plan

### Day 1: Progress + Seek
- [ ] Implement progress bar polling
- [ ] Test progress bar (5 min manual)
- [ ] Implement seek via playerNode reschedule
- [ ] Test seek (rapid-fire, 10 min manual)

### Day 2: Auto-Play + Test Suite
- [ ] Implement auto-play completion handler
- [ ] Test auto-play on 3-track playlist (10 min)
- [ ] Fix test suite (add testTarget, restore EQTests)
- [ ] Run `swift test` (verify all pass)

### Optional (If Time):
- [ ] Metadata extraction (async AVAsset lookup)
- [ ] Queue persistence (UserDefaults encode/decode)

---

## Success Criteria (Part B Done-Done)

- [ ] Progress bar displays correctly (100 plays → 1:23 / 3:45)
- [ ] Seek works: click slider → audio resumes at position ±100 ms
- [ ] Auto-play next track: no gap, respects repeat mode
- [ ] Test suite running: `swift test` passes all tests
- [ ] Manual soak test: 10-min playlist playback, zero xruns
- [ ] Code review: no obvious bugs, swiftlint passes

---

## Blockers & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| Seek implementation more complex than estimated | Low | Spike early (first day); escalate if > 4h overrun |
| Test suite broken (dependencies missing) | Low | Check Package.swift dependencies carefully |
| Auto-play completion handler timing issues | Medium | Test with short (10 sec) test file first |

---

## Next Step: Phase 1c (Sprint 1–3)

Once Part B ships, Phase 1c Sprint 1 kickoff begins:
- EQ wired into AU graph
- Limiter + LUFS normalization (true-peak ceiling, loudness metering)
- Listening panels scheduled
- Validation strategy ready

---

**Status:** 🟢 Ready to start  
**Start Date:** 2026-06-18  
**Target Completion:** 2026-06-21 EOD  
**Owner:** You (solo dev)
