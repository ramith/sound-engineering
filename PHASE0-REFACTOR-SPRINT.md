# 🔄 Phase 0 Sprint: Refactoring Specialist
**Task:** Fix playTrack(at:) Bug  
**Owner:** Refactoring Specialist  
**Duration:** 15 minutes  
**Blocker Status:** CORRECTNESS (silent bug, would break Phase 1.5 shuffle)

---

## The Bug

File: `Sources/AdaptiveSound/AudioViewModel.swift` (around line 200)

**Current code:**
```swift
func playTrack(at index: Int) {
  guard index < playlist.count else { return }
  startPlayback()  // ← BUG: plays whatever selectedTrackIndex already is!
}
```

**Problem:** 
User calls `playTrack(at: 3)` while track 0 is selected → still plays track 0 (not 3)

**Fix (one line):**
```swift
func playTrack(at index: Int) {
  guard index < playlist.count else { return }
  selectedTrackIndex = index  // ← ADD THIS
  startPlayback()
}
```

---

## Implementation (15 min)

### **Step 1: Locate the function (2 min)**

```bash
grep -n "func playTrack" Sources/AdaptiveSound/AudioViewModel.swift
```

### **Step 2: Add the fix (1 min)**

Insert `selectedTrackIndex = index` before `startPlayback()`

### **Step 3: Write a test (5 min)**

```swift
// In Tests/AudioViewModelTests.swift (create if not exists)
func testPlayTrackSelectsCorrectTrack() {
  let viewModel = AudioViewModel()
  viewModel.playlist = [
    AudioFile(url: URL(fileURLWithPath: "/tmp/track0.wav")),
    AudioFile(url: URL(fileURLWithPath: "/tmp/track1.wav")),
    AudioFile(url: URL(fileURLWithPath: "/tmp/track2.wav")),
  ]
  
  // Select track 2
  viewModel.playTrack(at: 2)
  
  // Verify correct track is selected
  XCTAssertEqual(viewModel.selectedTrackIndex, 2)
}
```

### **Step 4: Verify (5 min)**

- [ ] Code compiles
- [ ] Test passes
- [ ] No other references to `playTrack(at:)` are affected

---

## Acceptance Criteria

- [ ] One-line fix applied
- [ ] Test passes
- [ ] No regressions in other tests
- [ ] Ready to merge

---

## Done! ✅

This is literally a one-line fix. Once DSP and SwiftUI finish their Phase 0 tasks, this can ship immediately.

🚀
