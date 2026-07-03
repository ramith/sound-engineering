# 🎯 Team Fixing Plan — Final Synthesis

> **📦 ARCHIVED — historical session note (2026-06-16).** Synthesis of the Phase-0/1 team fixing plan; the work shipped. Retained for provenance, not a current plan.

**Status:** ✅ COMPLETE — All 5 domain experts delivered  
**Date:** 2026-06-16  
**Ready:** For immediate team execution

---

## Team Contributions Summary

| Expert | Focus | Status | Key Contributions |
|--------|-------|--------|-------------------|
| 🔌 **Audio DSP Engineer** | C++ signal chain, real-time safety, module stubs | ✅ Complete | Parameter ramping, bypass, FTZ/DAZ, 4 module implementations, null test strategy |
| 🔧 **Modern C++ Expert** | Type safety, RAII, memory safety, modernization | ✅ Complete | void* pointer replacement, memory ordering clarification, error handling improvements |
| 📱 **SwiftUI Pro** | Deprecated APIs, data flow, accessibility, structure | ✅ Complete | @Observable migration, file structure split (8→72 files), A11y fixes |
| 🔄 **Refactoring Specialist** | Architecture, DRY violations, testability | ✅ Complete | EQ consolidation plan, AudioEngineBridge extraction, device enumeration wiring |
| ✅ **QA Expert** | Testing strategy, regression prevention, CI integration | ✅ Complete | Null test framework, frequency sweep tests, soak test procedures |

---

## **PHASE 0: CRITICAL BLOCKERS (2-3 Days)**
*Must complete before Phase 1c work begins*

### **Issue #1: Two EQ Implementations** ⚠️ ARCHITECTURAL
- **Owners:** SwiftUI Pro, Refactoring Specialist
- **Effort:** 2 days
- **Blocker:** Phase 1.5 (ML presets, auto-EQ, device correction)
- **Action:** Consolidate EQTabView + EQViewModel into single source of truth
- **Risk:** Medium (UI/dispatch wiring change)

### **Issue #2: Parameter Ramping** 🔊 AUDIO QUALITY
- **Owner:** Audio DSP Engineer
- **Effort:** 1.5 days
- **Blocker:** Phase 1b (EQ dragging sounds bad without ramping)
- **Action:** Implement 32 ms linear/one-pole ramp on all parameter changes
- **Risk:** Low (isolated to EQModule + stubs)

### **Issue #3: Bypass at Intensity=0** 🔐 VERIFICATION
- **Owner:** Audio DSP Engineer
- **Effort:** 0.5 days
- **Blocker:** Phase 1b null test failure (MD5 bit-exact guarantee)
- **Action:** Add intensityLinear == 0 early-exit in DSPKernel::process()
- **Risk:** Low (2-line change)

### **Issue #4: playTrack(at:) Bug** 🐛 CORRECTNESS
- **Owner:** Refactoring Specialist
- **Effort:** 0.25 days
- **Blocker:** Phase 1.5 shuffle/auto-advance would play wrong track
- **Action:** `selectedTrackIndex = index` before startPlayback()
- **Risk:** Low (single-line fix)

**Phase 0 Total:** ~4 days (can parallelize to 2 days with 2+ engineers)

---

## **PHASE 1: HIGH-PRIORITY FEATURES (5-8 Days)**
*Before Phase 1c DSP features ship*

### **Module Implementations (Priority Order)**

| # | Module | Effort | Priority | Owner | Blocks |
|---|--------|--------|----------|-------|--------|
| 1️⃣ | **Limiter** (true-peak safety) | 2d | CRITICAL | DSP Eng | 1b shipping |
| 2️⃣ | **Loudness** (LUFS normalization) | 2.5d | HIGH | DSP Eng | 1c loudness |
| 3️⃣ | **Clarity** (dynamic EQ) | 2d | HIGH | DSP Eng | 1c clarity |
| 4️⃣ | **BRIR** (spatial audio) | 3d | MEDIUM | DSP Eng | 1c spatial |

### **Infrastructure & Architecture**

| Task | Effort | Owner | Blocker |
|------|--------|-------|---------|
| Extract AudioEngineBridge → protocol | 1d | Refactoring | ViewModel testability |
| Wire device enumeration → CoreAudio | 1.5d | SwiftUI Pro | Device-aware features |
| **Null test framework** | 1d | QA Expert | All DSP testing |
| **Frequency sweep tests** | 1.5d | QA Expert | Module acceptance |
| FTZ/DAZ denormal handling | 0.5d | DSP Eng | Battery/thermal |

**Phase 1 Total:** ~14 days critical path (9d Phase 0-1, 5d Phase 1c optional)

---

## **PHASE 2: TECHNICAL DEBT (1-2 Weeks)**
*After Phase 1c MVP ships*

### **API Modernization**
- `.cornerRadius()` → `.clipShape()` (5+ sites)
- `@ObservableObject/@Published` → `@Observable` (1 class, 6 usages)
- `String(format:)` → `FormatStyle` (3+ sites)
- `Task.detached + await MainActor.run` → plain `Task {}` (6+ methods)
- `Task.sleep(nanoseconds:)` → `Task.sleep(for:)` (1+ site)

### **Accessibility**
- Icon-only buttons → accessible labels (shuffle, repeat, jump)
- `.caption2` → `.caption` for readability

### **File Structure**
- Split 8 multi-type files into 72 single-type files
- 8 → 72 files (better navigability, testability)

### **C++ Code Quality**
- Replace `void*` with forward-declared handle classes
- Fix memory ordering in `DoubleBufferSnapshot` (relaxed vs. acquire)
- Encapsulate vDSP setup lifecycle
- Log/propagate vDSP setup creation errors

---

## **Critical Dependencies**

```
Phase 0 (Blockers)
├── Parameter Ramping (1.5d) ──┐
├── Intensity Bypass (0.5d) ───┼──► must complete before:
└── EQ Consolidation (2d) ─────┘    - Any module implementation
                                    - Parameter dispatch tests
                                    - End-to-end feature tests

Phase 1 (Features)
├── Limiter (2d) ◄─── blocks Phase 1b shipping
├── Loudness (2.5d)
├── Clarity (2d)
├── BRIR (3d)
├── AudioEngineBridge extraction (1d) ◄─── unblocks ViewModel tests
├── Device enumeration (1.5d) ◄─── unblocks US-DEVICE-08
├── Null test framework (1d) ◄─── gates all DSP commits
└── Frequency sweep tests (1.5d) ◄─── gates module acceptance
```

---

## **Team Assignments**

### **Audio DSP Engineer** (Primary: module implementation + testing)
- [ ] Parameter ramping (1.5d)
- [ ] Intensity bypass (0.5d)
- [ ] FTZ/DAZ setup (0.5d)
- [ ] Limiter module (2d)
- [ ] Loudness module (2.5d)
- [ ] Clarity module (2d)
- [ ] BRIR module (3d)
- **Total:** ~14 days

### **SwiftUI Pro** (UI/data flow)
- [ ] EQ consolidation (2d)
- [ ] Device enumeration wiring (1.5d)
- [ ] @Observable migration (Phase 2, 1d)
- [ ] File structure split (Phase 2, 1d)
- [ ] A11y fixes (Phase 2, 0.5d)
- **Total:** ~6 days (parallel with DSP)

### **Refactoring Specialist** (Architecture)
- [ ] playTrack(at:) bug fix (0.25d)
- [ ] AudioEngineBridge extraction (1d)
- [ ] Deprecated API cleanup (Phase 2, 1.5d)
- **Total:** ~2.75 days

### **QA Expert** (Testing)
- [ ] Null test framework (1d)
- [ ] Frequency sweep tests (1.5d)
- [ ] Soak test procedures (1d)
- [ ] CI/pre-commit integration (0.5d)
- **Total:** ~4 days

### **Modern C++ Expert** (Code review)
- [ ] Parameter ramping review (0.25d)
- [ ] C++ API modernization (Phase 2, 1d)
- [ ] Code quality audit (Phase 2, 1d)
- **Total:** ~2.25 days (on-demand review)

---

## **Timeline: Day-by-Day**

### **Week 1: Phase 0 (Critical Path)**

| Day | Task | Owner | Status |
|-----|------|-------|--------|
| **Wed 06/17** | Kick-off + assign | Team | Start |
| **Wed 06/17** | Parameter ramping (1.5d) | DSP Eng | In progress |
| **Wed 06/17** | EQ consolidation (2d) | SwiftUI Pro | In progress |
| **Thu 06/18** | (continue above) | Both | In progress |
| **Fri 06/19** | Intensity bypass + null test | DSP Eng + QA | Complete |
| **Fri 06/19** | playTrack bug fix | Refactor Spec | Complete |
| **Fri 06/19** | **PHASE 0 COMPLETE** | ✅ All | |

### **Week 2: Phase 1 (High Priority)**

| Day | Task | Owner | Status |
|-----|------|-------|--------|
| **Mon 06/23** | Limiter module (2d) | DSP Eng | Start |
| **Mon 06/23** | FTZ/DAZ (0.5d) | DSP Eng | Quick win |
| **Mon 06/23** | AudioEngineBridge extraction (1d) | Refactor Spec | Start |
| **Mon 06/23** | Device enumeration wiring (1.5d) | SwiftUI Pro | Start |
| **Tue 06/24** | (continue) | All | In progress |
| **Wed 06/25** | Loudness module (2.5d) | DSP Eng | Start |
| **Wed 06/25** | Frequency sweep tests (1.5d) | QA Expert | Start |
| **Thu 06/26** | (continue) | Both | In progress |
| **Fri 06/27** | Clarity module (2d) | DSP Eng | Start |
| **Mon 06/30** | (continue Clarity, BRIR 3d) | DSP Eng | In progress |
| **Wed 07/02** | **PHASE 1 COMPLETE** | ✅ All | |

### **Week 3-4: Phase 2 (Technical Debt)**

| Week | Task | Owner | Effort |
|------|------|-------|--------|
| **Jul 07–11** | File structure split (8→72) | SwiftUI Pro | 2d |
| **Jul 07–11** | @Observable migration | SwiftUI Pro | 1d |
| **Jul 07–11** | Deprecated API cleanup | Team | 1d |
| **Jul 14** | **PHASE 2 COMPLETE** | ✅ All | |

---

## **Success Criteria**

### **Phase 0 (By Fri 06/19)**
- ✅ EQ consolidation: single source of truth, end-to-end dispatch working
- ✅ Parameter ramping: EQ drag produces no audible clicks
- ✅ Intensity bypass: null test passes (MD5 bit-exact at intensity=0)
- ✅ playTrack bug: correct track plays when selected

### **Phase 1 (By Wed 07/02)**
- ✅ Limiter implemented: true-peak ≤ −1 dBTP, no artifacts (listening test)
- ✅ Loudness implemented: LUFS normalization transparent (libebur128 oracle)
- ✅ Clarity implemented: dynamic EQ unmasks detail without artifacts
- ✅ BRIR implemented: spatial audio renders without clicks (impulse test)
- ✅ AudioEngineBridge extracted: ViewModel unit tests pass without live audio
- ✅ Device enumeration: real devices listed with correct IDs/sample rates
- ✅ Null test gates all commits (pre-commit hook passes)
- ✅ Frequency sweep test validates all filter modules

### **Phase 2 (By Mon 07/14)**
- ✅ All deprecated APIs migrated
- ✅ All accessibility labels added
- ✅ File structure split (navigability improved)
- ✅ C++ code quality improved (no void*, proper error handling)

---

## **Risk Assessment & Mitigation**

| Risk | Level | Mitigation |
|------|-------|-----------|
| EQ consolidation breaks UI dispatch | Medium | End-to-end test on familiar music before commit |
| Parameter ramping introduces latency | Low | 32 ms window is imperceptible; test fast drags |
| Limiter peaking algorithm accuracy | Medium | Unit tests with synthetic peaks; libebur128 oracle |
| Module stubs → full implementations | High | Null test gates each; soak test (1h) before ship |
| Device enumeration real data fallback | Low | Fallback to hardcoded if CoreAudio enum fails |
| Shipping 1b without Limiter | CRITICAL | Limiter is highest Phase 1 priority; non-negotiable |

---

## **How to Use This Plan**

1. **Print or open in IDE:** `2026-06-16-team-fixing-plan.md` (full detailed version)
2. **Track progress:** Check boxes above as tasks complete
3. **Dependencies:** Respect critical path (ramping → bypass → modules)
4. **Daily standup:** Reference timeline above to stay aligned
5. **Ownership:** Each expert owns their domain; cross-review before merge

---

## **Integration with Existing Docs**

- **Architecture rationale:** [docs/architecture/architecture.md](../architecture/architecture.md)
- **Sprint execution:** [docs/sprints/07-phase-1b-part-b-kickoff.md](../sprints/07-phase-1b-part-b-kickoff.md)
- **Validation strategy:** [docs/architecture/validation-strategy.md](../architecture/validation-strategy.md)
- **Product roadmap:** [docs/product/roadmap.md](../product/roadmap.md)

---

## **Final Checklist**

- [ ] **Team reviews plan** (ASAP)
- [ ] **Confirm ownership assignments** (ASAP)
- [ ] **Identify blockers/risks** (ASAP)
- [ ] **Kick off Phase 0 tomorrow** (Wed 06/17)
- [ ] **Check Phase 0 complete by Fri 06/19**
- [ ] **Start Phase 1 Mon 06/23**
- [ ] **Ship Phase 1c by Wed 07/02**

---

**Compiled By:** Audio DSP Agent, Modern C++ Expert, SwiftUI Pro, Refactoring Specialist, QA Expert  
**Last Updated:** 2026-06-16 (all 5 domain experts completed)  
**Status:** ✅ **READY FOR EXECUTION**

