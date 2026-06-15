# Sprint 2 Phase 1b: UI/UX Redesign (Before DSP Implementation)

**📋 PLANNING: 2026-06-15**  
**Duration:** 2.5 days (~1 sprint week) — **BLOCKING:** Must complete validation before DSP implementation  
**Goal:** Redesign the GUI to eliminate wasted space, introduce tab-based navigation, and implement interactive EQ curve editing.

---

## Mission

The current Phase 1a UI wastes screen real estate with a centered logo/title and uses horizontal 31-band sliders, making poor use of the available canvas. This redesign introduces:
1. **Tab-based layout** (Now Playing | EQ | Settings)
2. **Header-fixed playback controls** (always visible)
3. **Side-by-side information dashboard** (Now Playing + DSP state)
4. **Interactive EQ curve editor** with click/drag interaction (not slider-based)
5. **Dropdown device menu** (compact, header-integrated)

**Acceptance Criteria:**
- ✅ BA/PM cross-reference and sign-off on user flows
- ✅ UI/UX experts validate information architecture
- ✅ SwiftUI Pro validates API usage and HIG compliance
- ✅ Design system documented (layout spec, component dimensions)
- ✅ Prototype built (not production code, visual validation only)
- ✅ Zero blockers before Phase 1b DSP kickoff

---

## Design Decisions (User-Driven)

### 1. **Layout Architecture**
- **Choice:** Tabs (top navigation)
- **Rationale:** Clear section separation (Now Playing | EQ | Settings), easy to extend
- **Implementation:** SwiftUI Picker with segmented control style

### 2. **Playback Controls Placement**
- **Choice:** Always in header (top bar)
- **Rationale:** Persistent access to Play/Stop/Volume across all views
- **Implementation:** Fixed header with HStack: Logo | Device Dropdown | Play/Stop | Volume Slider

### 3. **Device Selection**
- **Choice:** Dropdown in header
- **Rationale:** Compact, discoverable, doesn't waste main area
- **Implementation:** Menu button in header, selected device marked with checkmark
- **Interaction:** Clicking device immediately switches audio output

### 4. **EQ Curve Interaction**
- **Choice:** Both modes (click to adjust + drag to draw)
- **Rationale:** Power users can draw smooth curves; casual users can click individual frequencies
- **Implementation:** 
  - Click behavior: Taps raise/lower the band at that frequency (±dB increment)
  - Drag behavior: Smooth curve interpolation across adjusted points
  - Mode toggle: Button to switch between "Smooth Curve" and "Discrete Steps"

### 5. **EQ Visual Feedback**
- **Choice:** Curve + band indicators (dots at each of 31 band frequencies)
- **Rationale:** Shows exact band positions without cluttering the canvas
- **Implementation:** Small circles (●) at ISO 1/3-octave center frequencies along the curve

### 6. **Curve Interpolation**
- **Choice:** Smart blending (toggle smooth/discrete)
- **Rationale:** Smooth curves for music production, discrete steps for surgical tweaks
- **Implementation:** Two modes toggleable via button [Smooth Curve] / [Discrete Steps]

### 7. **Preset Integration**
- **Choice:** Both buttons + indicator dropdown
- **Rationale:** Quick access to presets + awareness of current state
- **Implementation:** 
  - Buttons: [Flat] [Presence] [Clarity] [Warm]
  - Dropdown: "Current Preset: [Flat ▼]" (shows "Custom" if user edited)

### 8. **Main Area Content (Now Playing Tab)**
- **Choice:** Now Playing + DSP Dashboard (side-by-side)
- **Rationale:** Show both track context and engine state without scrolling
- **Implementation:** 
  - Left (50%): Album art + track metadata + live spectrum analyzer
  - Right (50%): DSP Dashboard listing active modules + current device

### 9. **Main Area Layout**
- **Choice:** Side-by-side
- **Rationale:** Makes use of modern wide screens, balances information density
- **Implementation:** HStack with 50/50 split, VStack for nested content

### 10. **EQ Curve Canvas Size**
- **Choice:** Large (70% of viewport height)
- **Rationale:** Curve editing is primary task in EQ tab; deserves dominant space
- **Implementation:** GeometryReader to fill height, min 400pt width

### 11. **EQ Extras**
- **Choice:** Minimal (Reset button only)
- **Rationale:** Keep UI lean; undo/redo complexity deferred to Phase 1.5
- **Implementation:** Single [Reset to Flat] button, clears all edits

---

## Wireframe Layout

### **Header (Fixed, all tabs)**
```
┌─────────────────────────────────────────────────────────────────────┐
│  🎵 Logo  │ Device: [Built-in Speaker ▼] │ ▶ ⏹ Volume Slider: 58% │
└─────────────────────────────────────────────────────────────────────┘
```

### **Tab Navigation (Below header)**
```
┌─────────────────────────────────────────────────────────────────────┐
│ [Now Playing]  [EQ]  [Settings]                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### **Now Playing Tab (Main Area)**
```
┌────────────────────────────┬─────────────────────────────────────┐
│  NOW PLAYING (left 50%)    │  DSP DASHBOARD (right 50%)          │
│  ┌──────────────────────┐  │  ┌──────────────────────────────┐  │
│  │  Album Art (400x400) │  │  │ Active Modules:              │  │
│  │                      │  │  │ ✓ EQ: Flat                   │  │
│  └──────────────────────┘  │  │ ✓ Clarity: Off               │  │
│  Title / Artist / Album    │  │ ✓ Loudness: Off              │  │
│  [████████░] 1:23 / 3:45   │  │ ✓ BRIR: Off                  │  │
│                            │  │ ✓ Limiter: Active            │  │
│  Spectrum (live):          │  │                              │  │
│  ▁▂▃▄▅▆█▆▅▄▃▂▁▂▃▄▅▆█     │  │ Master Gain: 58%             │  │
│                            │  │ Output: Built-in @ 48 kHz    │  │
│                            │  │                              │  │
│                            │  │ (More state as needed)       │  │
└────────────────────────────┴─────────────────────────────────────┘
```

### **EQ Tab (Main Area)**
```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  FREQUENCY RESPONSE CURVE (Interactive - Click/Drag to adjust)     │
│  [70% height, dominant canvas]                                     │
│                                                                     │
│  +20dB  ┌─────────────────────────────────────────────────────┐   │
│         │                                                     │   │
│   0dB  ─┼──●──●──●──●──●──●──●──●──●──●──●──●──●──●──●──●──●┼─  │
│         │                      ╱╲                            │   │
│ -20dB  └─────────────────────────────────────────────────────┘   │
│        20Hz  100Hz  500Hz 1kHz 2kHz 5kHz 10kHz 15kHz 20kHz        │
│                                                                     │
│ Presets: [Flat] [Presence] [Clarity] [Warm]  Current: [Flat ▼]   │
│ Blending: [Smooth Curve] [Discrete Steps]  [Reset to Flat]        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Breakdown

### **Phase 1: Information Architecture & Validation** (1 day)
**Owner:** BA/PM + UI/UX Expert  
**Deliverables:**
- [ ] BA/PM cross-reference document (user flows, decision validation)
- [ ] UI/UX expert sign-off on information architecture
- [ ] SwiftUI Pro validates modern API usage + HIG compliance
- [ ] Design system spec (layout grid, component dimensions, typography)
- [ ] Final wireframe approved by all stakeholders

**Blockers:**
- Cannot proceed to implementation without stakeholder sign-off

### **Phase 2: SwiftUI Prototype** (1 day)
**Owner:** Frontend Developer + SwiftUI Pro  
**Deliverables:**
- [ ] Tab navigation working (Now Playing | EQ | Settings)
- [ ] Header with device dropdown + playback controls
- [ ] Now Playing tab with side-by-side layout (album art + DSP dashboard)
- [ ] EQ tab with interactive curve canvas (click/drag behavior stubbed)
- [ ] Preset buttons + curve mode toggle + reset button
- [ ] Full visual validation against wireframe

**Note:** This is a **prototype for visual validation only**, not production code yet.

### **Phase 3: Expert Validation & Sign-Off** (0.5 day)
**Owner:** UI/UX Expert + SwiftUI Pro + QA  
**Deliverables:**
- [ ] Visual prototype reviewed against wireframe
- [ ] All user interactions tested (click/drag, preset selection, device switching)
- [ ] Accessibility audit (VoiceOver, keyboard navigation, Reduce Motion)
- [ ] HIG compliance verified
- [ ] Sign-off document: "UI architecture ready for DSP implementation"

---

## Cross-Reference Checklist

### **For BA/PM Review**
- [ ] User flow: "Now Playing tab shows track + DSP state" — requirement satisfied?
- [ ] User flow: "Device selection quick & discoverable" — dropdown sufficient?
- [ ] User flow: "EQ editing is primary interaction in EQ tab" — 70% canvas justified?
- [ ] User flow: "Presets + manual curve both supported" — design accommodates both?
- [ ] Business requirement: "Tab structure extensible for future features" — confirmed?

### **For UI/UX Expert Validation**
- [ ] Information architecture: side-by-side layout balances cognitive load?
- [ ] Navigation: tabs are discoverable; tab switching is clear?
- [ ] Visual hierarchy: EQ curve dominates EQ tab; presets are secondary?
- [ ] Consistency: device dropdown ↔ header integration matches Apple patterns?
- [ ] Scalability: design works on 13" and 16" MacBook screens?

### **For SwiftUI Pro Validation**
- [ ] Modern API usage: GeometryReader, @Environment, property wrappers correct?
- [ ] HIG compliance: spacing, typography, colors follow Apple standards?
- [ ] Accessibility: all interactive elements have proper labels?
- [ ] Performance: tab switching doesn't reload entire view tree?
- [ ] No deprecated APIs (e.g., `foregroundColor()` → `foregroundStyle()`)?

---

## Success Criteria

**All must be green before DSP implementation begins:**

✅ **BA/PM Sign-Off:** User flows and business requirements satisfied  
✅ **UI/UX Expert Validation:** Information architecture sound, no cognitive overload  
✅ **SwiftUI Pro Review:** Modern APIs, HIG-compliant, accessible  
✅ **Visual Prototype:** Matches wireframe exactly, all interactions working  
✅ **Accessibility Audit:** VoiceOver, keyboard nav, Reduce Motion verified  
✅ **Design System Doc:** Grid, spacing, typography locked  

---

## Known Deferred Features (Phase 1.5+)

- Interactive curve dragging (smooth drawing) — stubbed in prototype, full implementation deferred
- Undo/Redo for EQ adjustments — deferred, minimal button only for Phase 1b
- Hover labels on frequency bands — deferred to Phase 1.5 polish
- ML-based genre detection for presets — deferred to Phase 1.5
- Linear-phase EQ toggle — deferred to Phase 1.5

---

## Next Steps (After Sign-Off)

1. **Phase 1b DSP Implementation** — Parallel agents for EQ module C++ + Swift integration
2. **Phase 1b Testing** — Unit tests + manual QA of EQ sound quality
3. **Phase 1c** — Clarity module (same UI/DSP workflow as Phase 1b)

---

**Document Status:** ✅ STAKEHOLDER REVIEW COMPLETE  
**BA/PM Review:** ✅ APPROVED (4 clarifications needed — see below)  
**UI/UX Validation:** ✅ APPROVED (design system specs documented)  
**SwiftUI Pro Review:** ✅ APPROVED FOR PROTOTYPE (API architecture sound)  
**Ready for DSP Implementation:** ✅ YES (pending prototype sign-off)

---

## Expert Review Sign-Offs

### **BA/PM Cross-Reference: APPROVED**
**Status:** ✅ Design satisfies user flows (Journeys 2.1–2.4, 2.6) and functional requirements

**4 Clarifications Needed (Before Prototype):**
1. **Settings tab content:** Specify controls (Hearing Profile, Device Correction EQ, Loudness Compensation, About/Help)
2. **Intensity knob placeholder:** Reserve UI slot in DSP Dashboard for Phase 1.5 "Reimagine" control (prevent layout thrash)
3. **Queue management scope:** Clarify if queue controls (FR-PLAY-03) ship in Phase 1b or Phase 1c
4. **Conversational Tuning placement:** Wire "Tell us what you hear" text input (Journey 2.7) — recommend below EQ curve or album art

**Sign-Off:** "Tab architecture provides clean foundation for Phase 1.5+ features (stem engine, Intensity knob). Ready to prototype with above clarifications documented."

### **UI/UX Expert Validation: APPROVED**
**Status:** ✅ Information architecture balanced; tabs follow macOS conventions; accessible

**3 IA Recommendations:**
1. **Tab active state:** Add underline or background highlight; include breadcrumb subtitle ("EQ Editing") on content switch
2. **Device dropdown iconography:** Specify speaker + chevron icon; show selected device name in closed state
3. **Preset affordance:** Highlight active preset button; add tooltip animation on apply

**3 Design System Specs (Document):**
1. **Grid & Spacing:** 8pt base grid, 16pt margins, 8pt gutters, EQ canvas 20pt top / 30pt bottom padding
2. **Typography:** Heading 18pt/600, body 16pt/400, labels 13pt/500 (WCAG AA ≥4.5:1 contrast)
3. **Components:** Buttons ≥44x44pt, dropdown 40pt, curve dots 8pt, slider thumb 16pt

**Sign-Off:** "IA sound. Recommend testing 50/50 split on narrow screens (13" MacBook ~1440pt). Ready for prototype."

### **SwiftUI Pro Review: APPROVED FOR PROTOTYPE**
**Status:** ✅ Modern API usage correct; HIG-compliant; accessibility path clear

**3 Technical Recommendations:**
1. **Header + Tabs:** Use `VStack { FixedHeader ... Picker ... }` with @State; avoid NavigationStack overhead
2. **Side-by-side layout:** GeometryReader + HStack at 50% split correct; add `.containerRelativeFrame(.horizontal)` for responsive scaling
3. **Curve canvas:** Implement as custom `Canvas` view with `onContinuousHover` + `DragGesture`; pre-compute interpolation in @State (not draw loop)

**2 HIG Compliance Notes:**
1. **Titlebar:** Respect macOS 14+ unified titlebar height (44pt); avoid traffic light overlap
2. **Device dropdown:** Use `Menu` with `checkmark.circle.fill`; device name + 8pt trailing padding

**Action:** Curve canvas requires custom `accessibilityAction(.increment/.decrement)` for keyboard; label bands with `accessibilityLabel("3kHz band")`

**Sign-Off:** "SwiftUI architecture is sound, proceed to prototype."

---

## Phase 2 Prototype Tasks (Ready to Begin)

### **Task 1: Clarify Scope with BA/PM — RESOLVED**
✅ **Settings Tab Content:** Full feature set
- Hearing Profile (FR-HEAR-01 link)
- Device Correction EQ toggle (FR-TONAL-02)
- Loudness Compensation (FR-TONAL-03)
- About/Help

✅ **Intensity Knob Placeholder:** Yes, reserve UI slot in DSP Dashboard
- Show disabled/grayed knob (0-100%) in Phase 1b
- Functional in Phase 1.5 (prevents layout thrash)

✅ **Queue Management:** Deferred to Phase 1c or later
- Now Playing tab shows only current track metadata in Phase 1b
- Queue controls (drag-to-reorder, skip) out of scope

✅ **Conversational Tuning Input:** Deferred to Phase 1.5
- Focus on core EQ + UI infrastructure in Phase 1b
- Text input ("Tell us what you hear") deferred; wire in Phase 1.5

### **Task 2: Build SwiftUI Prototype (1 day)**
- [ ] VStack header (Logo | Device Dropdown | Play/Stop | Volume)
- [ ] Picker tabs (Now Playing | EQ | Settings) with active state styling
- [ ] Now Playing content: side-by-side (album art + spectrum | DSP dashboard)
- [ ] EQ content: large curve canvas + presets + blending toggle + reset button
- [ ] Settings tab stub (placeholder for future controls)
- [ ] Apply design system (8pt grid, typography, component dimensions)

### **Task 3: Accessibility & HIG Validation (0.5 day)**
- [ ] VoiceOver: all tabs/buttons/sliders labeled
- [ ] Keyboard: tab navigation, curve canvas increment/decrement
- [ ] Dynamic Type: all text scales (no fixed sizes)
- [ ] Responsive: test 50/50 split on 13" MacBook; add fallback if needed
- [ ] Window resize: header respects safeAreaInsets
- [ ] Reduce Motion: tab switches smooth but respect prefersReducedMotion

### **Task 4: Expert Sign-Off (0.5 day)**
- [ ] UI/UX review: compare prototype vs. wireframe; spot visual gaps
- [ ] QA: test all interactions (click curve, drag curve, preset select, device switch, tab switching)
- [ ] SwiftUI Pro: code review (API usage, HIG, accessibility)
- [ ] Final approval: "Ready for Phase 1b DSP implementation"

---

**Prepared by:** Claude Code UI/UX Team  
**Date:** 2026-06-15  
**Next Review:** [BA/PM Cross-Reference]
