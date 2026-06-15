# 🚀 Team Kick-Off Meeting Agenda
**Date:** 2026-06-16 (Today) / 2026-06-17 (First Day)  
**Duration:** 30 minutes (review) + 15 min Q&A  
**Attendees:** Full team (DSP Engineer, SwiftUI Pro, Refactoring Specialist, QA Expert, C++ Expert)

---

## Agenda Items

### **1. Review Fixing Plan (10 min)**
📄 **Documents:**
- [`TEAM-FIXING-PLAN-SYNTHESIS.md`](TEAM-FIXING-PLAN-SYNTHESIS.md) — 2-minute overview
- [`TEAM-FIXING-PLAN.md`](TEAM-FIXING-PLAN.md) — Details as needed

**Key Points:**
- Phase 0 (Critical, 2-3 days) must complete before Phase 1
- Parameter ramping & bypass are foundational
- Limiter is Phase 1 highest priority (1b shipping blocker)
- All 4 module stubs require implementation

---

### **2. Confirm Ownership Assignments (8 min)**

| Owner | Domain | Phase 0 | Phase 1 | Phase 2 |
|-------|--------|---------|---------|---------|
| 🔌 **Audio DSP** | C++ modules | Ramping + bypass | Limiter, Loudness, Clarity, BRIR | — |
| 📱 **SwiftUI Pro** | UI/data flow | EQ consolidation | Device enum | File split, @Observable |
| 🔄 **Refactor Spec** | Architecture | playTrack fix | Bridge extraction | Cleanup |
| ✅ **QA Expert** | Testing | — | Null + sweep tests | Regression |
| 🔧 **C++ Expert** | Code review | Review ramping | Module reviews | Quality audit |

**Confirm:** Does everyone agree with their Phase 0 assignment?

---

### **3. Identify Blockers & Risks (7 min)**

**Critical Blockers to Resolve:**
- [ ] Parameter ramping must complete before module work (are we aligned?)
- [ ] Intensity bypass + null test blocks all testing (acceptable?)
- [ ] EQ consolidation is architectural (SwiftUI Pro: any concerns?)
- [ ] Limiter is 1b critical (DSP Engineer: confident in 2-day estimate?)

**Team Questions:**
- Anyone see a risk we haven't addressed?
- Dependencies we missed?
- Resource conflicts?

---

### **4. Kick-Off Phase 0 (5 min)**

**Tomorrow (Wed 06/17):**

1. ✅ Parameter Ramping Sprint (DSP Engineer + C++ Expert code review)
   - Start: EQModule.mm, add ramping state
   - Target: Spectrogram shows smooth transitions

2. ✅ EQ Consolidation Sprint (SwiftUI Pro)
   - Start: Delete EQView.swift, wire EQTabView to EQViewModel
   - Target: End-to-end slider → DSP kernel

3. ✅ playTrack Bug Fix (Refactoring Specialist)
   - 15-min task: add `selectedTrackIndex = index`
   - Test: select track 3, play, verify it plays (not track 0)

---

### **5. Q&A (5 min)**

**Open Floor:**
- Questions on plan?
- Clarifications needed?
- Concerns on timeline?

---

## Post-Kick-Off: Start Work

### **Immediate Actions (Next Hour)**

1. **DSP Engineer:**
   - [ ] Read `Sources/AudioDSP/EQ/EQModule.mm` (understand current gain application)
   - [ ] Open `Sources/AudioDSP/EQ/EQModule.h` (add ramping state struct)
   - [ ] Sketch one-pole smoother math: `y[n] = α·y[n-1] + (1-α)·x[n]`

2. **SwiftUI Pro:**
   - [ ] Back up `Sources/AdaptiveSound/EQView.swift`
   - [ ] Review `Sources/AdaptiveSound/UI/Tabs/EQTabView.swift` (FrequencyResponseCanvas)
   - [ ] Plan EQViewModel dispatch integration points

3. **Refactoring Specialist:**
   - [ ] Locate `playTrack(at:)` in `AudioViewModel.swift`
   - [ ] Write 1-line fix + test case

4. **QA Expert:**
   - [ ] Draft null test skeleton in `Tests/DSPKernelNullTest.cpp`
   - [ ] Plan frequency sweep test structure

5. **C++ Expert:**
   - [ ] Review ramping sketches from DSP Engineer
   - [ ] Verify no memory order issues

---

## Daily Standup Format

**Every 9:00 AM (before work):**
- Each owner: 1-2 min update
  - What did you finish yesterday?
  - What are you starting today?
  - Any blockers?

**Example:**
> DSP Eng: "Parameter ramping skeleton done, spectrogram looks clean. Starting null test framework today. No blockers."

---

## Phase 0 Completion Criteria

**By Friday 06/19, 5 PM:**

- [ ] Parameter ramping compiles, no zipper noise on spectrogram
- [ ] EQ consolidation complete, slider→DSP dispatch works end-to-end
- [ ] Intensity bypass implemented, null test passes (MD5 bit-exact)
- [ ] playTrack bug fixed, correct track plays
- [ ] All code passes pre-commit hooks (format, lint, ASAN/TSan)
- [ ] Pull request review complete (C++ Expert signs off)

**Ship Phase 0 → Move to Phase 1 Monday 06/23**

---

## Important Links

- **Full Plan:** [`TEAM-FIXING-PLAN.md`](TEAM-FIXING-PLAN.md)
- **Executive Summary:** [`TEAM-FIXING-PLAN-SYNTHESIS.md`](TEAM-FIXING-PLAN-SYNTHESIS.md)
- **Architecture Docs:** [`docs/architecture/architecture.md`](docs/architecture/architecture.md)
- **Code Review:** Comprehensive review above (code-review summary in conversation)

---

## Questions Before We Start?

**Please confirm:**
1. ✅ You've reviewed the fix plan
2. ✅ You're ready to start Phase 0 tomorrow
3. ✅ You understand your ownership assignment
4. ✅ You have no blockers to beginning work

---

**Kick-off Time:** 30 min  
**Start Phase 0:** Wed 06/17 (tomorrow)  
**Expected Phase 0 Complete:** Fri 06/19  

Let's ship this! 🚀
