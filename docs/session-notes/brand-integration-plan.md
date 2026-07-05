# Brand Kit Integration Plan — AdaptiveSound

> **⚠️ SUPERSEDED — this is NOT the shipped identity (2026-07-05).** The visual identity that actually shipped is the **teal `DesignSystem`** — neutral surfaces (no warm tint), system fonts, and a plain-text header — see `Sources/AdaptiveSound/DesignSystem.swift`, `Sources/AdaptiveSound/Color+Brand.swift` (now compatibility aliases delegating to `DesignSystem`), and `Sources/AdaptiveSound/UI/Components/HeaderView.swift`. The **Sunset gradient (pink → orange → gold), the "Flux" mark, and Space Grotesk typography described below were NOT adopted.** This document is retained only as provenance (being archived to `docs/session-notes/`); do not treat any part of it as current guidance.

## Overview

The brand kit provides a cohesive visual identity around the "Flux" mark (eighth note + adaptive waveform) with a **Sunset gradient** (pink → orange → gold) and **Space Grotesk typography**.

**Assets Location:** `assets/` folder (SVG source of truth + PNG rasterized)

---

## Integration Roadmap

### **Phase 1: App Icon & macOS Bundle (IMMEDIATE)**

**Goal:** Make the app look native with proper branding on macOS.

**Tasks:**

1. **Copy app icon to project**
   - Copy `assets/png/app-icon-512.png` → `Sources/AdaptiveSound/Assets.xcassets/AppIcon.appiconset/`
   - Create `Contents.json` with icon asset configuration
   - Update `Info.plist` to reference the app icon

2. **Update app icon in Info.plist**
   ```xml
   <key>CFBundleIconName</key>
   <string>AppIcon</string>
   ```

3. **Integration in macOS bundle**
   - Add icon to `Contents/Resources/` in app bundle
   - Verify appearance in Dock and Finder

**Estimate:** ~30 min

---

### **Phase 2: App Branding & UI Theme (THIS PHASE)**

**Goal:** Infuse the app UI with brand colors, typography, and the Flux mark.

**Tasks:**

1. **Create SwiftUI Color constants**
   ```swift
   extension Color {
       static let asPink = Color(red: 0.973, green: 0.004, blue: 0.569)     // #F80791
       static let asOrange = Color(red: 1.0, green: 0.392, blue: 0.016)     // #FF6405
       static let asGold = Color(red: 0.992, green: 0.749, blue: 0.145)     // #FDC025
       static let asDark = Color(red: 0.078, green: 0.047, blue: 0.039)     // #140C0A
       static let asInk = Color(red: 0.129, green: 0.082, blue: 0.063)      // #211510
       static let asPaper = Color(red: 0.998, green: 0.984, blue: 0.973)    // #FEFBF8
   }
   ```

2. **Add Sunset gradient helper**
   ```swift
   extension LinearGradient {
       static let sunset = LinearGradient(
           gradient: Gradient(colors: [.asPink, .asOrange, .asGold]),
           startPoint: .bottomLeading,
           endPoint: .topTrailing
       )
   }
   ```

3. **Update HeaderView with Flux mark & gradient**
   - Replace generic waveform icon with `app-icon.svg` (embedded as SF Symbol or image)
   - Apply Sunset gradient to title text
   - Use Space Grotesk font (Google Fonts)

4. **Update status card, device picker, error banner**
   - Use `asDark` for backgrounds (#140C0A)
   - Use `asInk` for text (#211510)
   - Highlight states: `asPink` or gradient for selected items

5. **Font integration**
   - Load Space Grotesk from Google Fonts via CSS/Font link
   - Apply to:
     - Title: "Adaptive Sound" (Space Grotesk 700, gradient text)
     - Subtitle: "Audio Enhancement Engine" (Space Grotesk 400, secondary color)
     - Device picker: Space Grotesk 500

**Estimate:** ~1-2 hours

---

### **Phase 3: README & Documentation Update**

**Goal:** Update project README to reflect brand identity and guide contributors.

**Tasks:**

1. **Update README.md**
   - Add brand section with Flux mark SVG/PNG
   - Document brand colors (hex + OKLCH)
   - Document typography (Space Grotesk weights)
   - Gradient spec for CSS/SVG
   - Usage guidelines (min size, clearspace, don'ts)

2. **Add brand colors to README**
   ```markdown
   ## Brand Identity
   
   **Mark:** Flux — eighth note + adaptive waveform  
   **Gradient:** Sunset (pink → orange → gold)  
   **Colors:**
   - Primary (note head): `#F80791` (pink)
   - Mid: `#FF6405` (orange)
   - Accent (wave): `#FDC025` (gold)
   - Dark surface: `#140C0A`
   - Text: `#211510` (ink)
   - Light surface: `#FEFBF8` (paper)
   
   **Typography:** Space Grotesk (400/500/600/700)
   ```

3. **Add brand asset links**
   - Link to `assets/README.md` for detailed specs
   - Guidance on when to use which variant (mark vs. lockup, gradient vs. ink)

**Estimate:** ~30 min

---

### **Phase 4: Favicon & Web Assets (OPTIONAL, Phase 2+)**

**Goal:** Extend brand to web presence (if any).

**Tasks:**

1. **Favicon setup (when web interface exists)**
   - Use `favicon.svg` as primary (modern browsers)
   - Fallback to `favicon-16/32/48.png` for legacy

2. **Apple touch icon**
   - Use `apple-touch-icon-180.png` for iOS home screen

3. **HTML wiring** (when web interface exists)
   ```html
   <link rel="icon" type="image/svg+xml" href="/assets/svg/favicon.svg">
   <link rel="icon" type="image/png" sizes="32x32" href="/assets/png/favicon-32.png">
   <link rel="apple-touch-icon" sizes="180x180" href="/assets/png/apple-touch-icon-180.png">
   ```

**Estimate:** ~15 min (when needed)

---

## Implementation Order

### **Immediate (Next Sprint):**
1. ✅ Phase 1: App icon + macOS bundle integration
2. ✅ Phase 2: SwiftUI colors, fonts, HeaderView redesign
3. ✅ Phase 3: README update

### **Deferred (Phase 2+):**
- Phase 4: Web/favicon assets (when web interface planned)

---

## File Checklist

### **Assets to Copy**
- [ ] `assets/png/app-icon-512.png` → App bundle + Assets.xcassets
- [ ] `assets/svg/app-icon.svg` → Use in app header (scale to fit)
- [ ] `assets/svg/mark.svg` → Logo reference in README
- [ ] Brand colors & gradient CSS/SVG examples → README.md

### **Code Changes**
- [ ] Create `Color+Brand.swift` extension (brand colors)
- [ ] Create `LinearGradient+Brand.swift` extension (Sunset gradient)
- [ ] Update `HeaderView.swift` to use brand colors + mark
- [ ] Update `Info.plist` with CFBundleIconName
- [ ] Update `README.md` with brand section

### **Build Integration**
- [ ] Update `build-app.sh` to include icon in app bundle
- [ ] Verify icon appears in Dock

---

## Success Criteria

✅ App icon appears in Dock with correct branding  
✅ App header displays Flux mark + "Adaptive Sound" with Sunset gradient  
✅ UI uses brand colors consistently (dark backgrounds, ink text)  
✅ Space Grotesk font loaded and applied to headings  
✅ README documents brand identity & usage guidelines  
✅ No warnings on build  

---

## Notes

- **SVGs are source of truth** — update SVGs if changes needed, then re-export PNGs
- **Wordmark is live text** — don't bake the text into the icon, use the Space Grotesk font
- **Gradient must be exact** — use the 40deg linear-gradient with specified color stops
- **Clearspace & min size** — maintain brand guidelines (mark ≥20px, clearspace ≥note-head height)

---

**Created:** 2026-06-14  
**Status:** Ready for implementation
