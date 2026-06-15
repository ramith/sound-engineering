# 📱 Phase 0 Sprint: SwiftUI Pro
**Task:** EQ Consolidation  
**Owner:** SwiftUI Pro  
**Duration:** 2 days (Wed 06/17 → Thu 06/18)  
**Blocker Status:** CRITICAL (consolidates two incompatible EQ implementations)

---

## Overview

The codebase has two competing EQ systems that don't talk to each other. You're consolidating them into a single, testable source of truth.

- **Keep:** `FrequencyResponseCanvas` (interactive drag UI) + `EQTabView` 
- **Delete:** `EQView.swift` (duplicate sliders)
- **Consolidate:** EQ preset data + dispatch to DSP kernel

---

## Files Involved

**Delete:**
- `Sources/AdaptiveSound/EQView.swift` (entire file)

**Modify:**
- `Sources/AdaptiveSound/EQViewModel.swift` (centralize presets, fix dispatch)
- `Sources/AdaptiveSound/UI/Tabs/EQTabView.swift` (wire canvas to ViewModel)
- `Sources/AdaptiveSound/UI/Components/ToolbarView.swift` (update tab references if needed)

**Keep (already good):**
- `Sources/AdaptiveSound/Models/AudioFile.swift`
- `Sources/AdaptiveSound/AudioViewModel.swift`

---

## Step-by-Step Implementation

### **Step 1: Backup & Clean (30 min)**

```bash
# Make safe copies
cp Sources/AdaptiveSound/EQView.swift Sources/AdaptiveSound/EQView.swift.backup
cp Sources/AdaptiveSound/EQViewModel.swift Sources/AdaptiveSound/EQViewModel.swift.backup

# List what we're keeping from EQView (if anything)
grep -n "func\|struct\|class\|enum" Sources/AdaptiveSound/EQView.swift | head -20
```

**Decision:** Is there any EQView code (helper functions, constants) we should keep? 
- If no → delete entirely
- If yes → extract to EQViewModel first

### **Step 2: Consolidate Preset Data (45 min)**

**Current state:**
- `EQViewModel.swift` has `EQPresetDefinition` (private struct with static preset names + gain arrays)
- `EQTabView.swift` has trigonometric formulas for computing presets (`gainForPresence()`, etc.)
- Values disagree (Presence: 4 dB vs ~7 dB)

**New state:**
- Single `EQPreset` enum with computed `gains: [Float]` property
- All formulas in one place

**Action:**

In `Sources/AdaptiveSound/EQViewModel.swift`, replace `EQPresetDefinition`:

```swift
enum EQPreset: String, CaseIterable {
  case flat = "Flat"
  case presence = "Presence"
  case warm = "Warm"
  case clarity = "Clarity"
  
  // Canonical preset data: one source of truth
  var gains: [Float] {
    switch self {
    case .flat:
      return Array(repeating: 0.0, count: 31)  // Unity on all bands
    
    case .presence:
      // Enhance 2 kHz and 5 kHz for presence/clarity
      let freqs = [20, 25, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]
      var g = Array(repeating: 0.0, count: 31)
      if let idx2k = freqs.firstIndex(of: 2000) { g[idx2k] = 3.0 }
      if let idx5k = freqs.firstIndex(of: 5000) { g[idx5k] = 4.0 }
      return g
    
    case .warm:
      // Boost bass and mids, roll off treble
      var g = Array(repeating: 0.0, count: 31)
      // Low bass: +3 dB at 80 Hz and below
      for i in 0...6 { g[i] = 3.0 }
      // Mids: +2 dB at 1 kHz
      for i in 16...18 { g[i] = 2.0 }
      // Treble roll-off: -2 dB above 5 kHz
      for i in 24...30 { g[i] = -2.0 }
      return g
    
    case .clarity:
      // Boost presence and treble
      var g = Array(repeating: 0.0, count: 31)
      for i in 18...30 { g[i] = 2.0 }  // Uniform boost 1 kHz–20 kHz
      return g
    }
  }
}
```

**Verify:** Print out the gains for each preset and compare with the old `EQPresetDefinition` values. Fix any discrepancies.

### **Step 3: Update EQViewModel for Dispatch (1 hour)**

Ensure `EQViewModel` has a clear dispatch path:

```swift
@Observable
final class EQViewModel {
  var bandGains: [Float] = Array(repeating: 0.0, count: 31)
  var selectedPreset: EQPreset = .flat {
    didSet {
      // When preset changes, update band gains
      bandGains = selectedPreset.gains
      // And dispatch to DSP kernel
      audioViewModel.updateEQBands(bandGains)
    }
  }
  
  var availablePresets: [String] {
    EQPreset.allCases.map { $0.rawValue }
  }
  
  func applyBandGain(_ band: Int, _ gain: Float) {
    bandGains[band] = gain
    // Dispatch to DSP kernel
    audioViewModel.updateEQBands(bandGains)
  }
}
```

### **Step 4: Wire EQTabView to ViewModel (1 hour)**

In `Sources/AdaptiveSound/UI/Tabs/EQTabView.swift`:

```swift
struct EQTabView: View {
  @Environment(AudioViewModel.self) var audioViewModel
  @Environment(EQViewModel.self) var eqViewModel
  
  var body: some View {
    VStack {
      // Preset picker
      Picker("Preset", selection: $eqViewModel.selectedPreset) {
        ForEach(EQPreset.allCases, id: \.self) { preset in
          Text(preset.rawValue).tag(preset)
        }
      }
      .pickerStyle(.segmented)
      
      // Canvas (keep existing FrequencyResponseCanvas)
      FrequencyResponseCanvas(
        gains: $eqViewModel.bandGains,
        frequencyLabels: frequencyLabels
      )
      
      // Optional: show preset gains vs. current
      Text("Preset: \(eqViewModel.selectedPreset.rawValue)")
    }
  }
}
```

### **Step 5: Delete EQView.swift (5 min)**

```bash
rm Sources/AdaptiveSound/EQView.swift
```

Update any imports or references in other files that mention `EQView`.

### **Step 6: Test End-to-End (30 min)**

```swift
// In AdaptiveSound.swift or main app, verify:
func testEQDispatch() {
  // 1. Select a preset in UI
  eqViewModel.selectedPreset = .presence
  
  // 2. Verify bandGains updated
  XCTAssertEqual(eqViewModel.bandGains[16], 4.0)  // 2 kHz should be +4 dB
  
  // 3. Drag a slider
  eqViewModel.applyBandGain(16, 5.0)
  
  // 4. Verify DSP kernel receives the change
  // (This will be verified by DSP Engineer's null test)
}
```

---

## Acceptance Criteria

- [ ] `EQView.swift` deleted
- [ ] `EQPreset` enum defined with all preset gains
- [ ] Preset dispatch works (select preset → bandGains update)
- [ ] Slider drag dispatches to DSP kernel
- [ ] End-to-end test passes (slider in UI → audio changes)
- [ ] No compiler warnings
- [ ] Code review approved

---

## Timeline

| Time | Task | Status |
|------|------|--------|
| Wed AM | Backup + review code | Start |
| Wed AM | Consolidate presets (Step 2) | In progress |
| Wed PM | Update ViewModel (Step 3) | Continue |
| Thu AM | Wire EQTabView (Step 4) | Complete |
| Thu AM | Delete EQView + test | Complete |
| Thu PM | Code review | Ship |

---

**Ready?** Start by reviewing both `EQView.swift` and `EQTabView.swift` side-by-side. List the differences.

Then consolidate preset data into a single source of truth.

Let's ship this! 🚀
