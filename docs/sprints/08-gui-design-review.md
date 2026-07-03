# GUI Design Review — AdaptiveSound (app-wide)

> **✅ HISTORICAL design review (2026-06-16), retained for provenance.** Forward schedule: [sprint-plan.md](sprint-plan.md).

**Document ID:** GUI-REVIEW-001
**Version:** 1.0
**Date:** 2026-06-16
**Reviewers:** swiftui-pro (implementation / macOS HIG / a11y / performance) + ui-designer (visual system / UX), synthesized
**Method:** **Source-level** review — no running app/screenshots this session. Items tagged **[visual]** require `make run` to confirm.
**Scope:** the whole SwiftUI surface (`Sources/AdaptiveSound/**`), branch `feat/sprint-4-loudness-safety`. Feeds Sprint 4 M4 (metering UI), M5, and Sprint 5 UI work.

---

## Cross-validated findings (both reviewers flagged independently → highest confidence)

1. **Playback progress is hardcoded to `0.0`.** `NowPlayingWidget` fills `geo.width * (0.0 / duration)`; `AudioViewModel` has no `currentPositionSeconds`. A player whose progress never advances reads as frozen. **Critical (UX).**
2. **Window chrome not integrated.** Custom `HStack` toolbar + flat `asWindow` sit under the real macOS title bar → two-tone seam; no `.windowStyle`, no menu-bar `.commands` (no ⌘-Space play/pause, no File ▸ Open). **[visual]** Biggest non-native tell. **High.**
3. **Brand colors hardcoded, dark-only** (`Color+Brand.swift`). White labels over near-white in Light Appearance; `asAccent` ignores the system accent; `asLabelTertiary` (white 42 %) fails WCAG AA for the 10–11 pt text. **[visual]** **High.**
4. **`BrandFont` defined but unused** — typography is ad-hoc `Font.system(size:)` across 10+ files; no enforced token layer (`design-system.md` was removed in the merge). **Medium.**
5. **Right panel is static scaffolding** — "Active Modules" hardcoded (incl. a **"BRII" → BRIR** typo), Intensity locked, `NowPlayingWidget` duplicates the left panel. **Medium-High.**
6. **EQ canvas** (`FrequencyResponseCanvas`) — undiscoverable interaction (no cursor change/hover), too few grid labels for precision, polyline (not spline) curve, no fill-under-curve. Plus a real bug (below). **Medium-High.**

---

## Correctness bugs (mostly swiftui-pro) — real defects, not just polish

| # | File | Bug | Fix |
|---|------|-----|-----|
| C1 | `FrequencyResponseCanvas.swift` | Drag/`applySmoothShoulder` clamp to ±20 dB and write `bandGains` directly, bypassing `EQViewModel.applyBandGain`'s ±/+12 dB DSP clamp → out-of-range params reach the kernel | Route drag edits through a clamped `EQViewModel` batch method; clamp to [−20, +12]; relabel the axis (+12 not +20) |
| C2 | `PlaylistView.swift` | `startAccessingSecurityScopedResource()` released by `defer` before the async `loadMusicFolder` Task runs → silent empty playlist on sandboxed builds | Move start/stop inside the `Task` (around the async load) |
| C3 | `AudioViewModel.swift` | `setParameter` / `shutdown` use bare `try` in `Task{}` with no `catch` → EQ/gain/device failures vanish | Wrap in do/catch → set `errorMessage` |
| C4 | `AdaptiveSound.swift` | `AudioViewModel()` constructed twice (property initializer + `init()`); first instance discarded, risks a model split with `EQViewModel` | Declare without initializer; build once in `init()` |
| C5 | `EQPresetPickerView.swift` | `Picker` binding + `onChange` both apply the preset → `dispatchAllBands` fires twice | Drive selection through one path (computed `Binding` set → `selectPreset`); drop `onChange` |
| C6 | `AudioViewModel.swift` | `movePlaylistItems` reads `playlist[destination].id` after the move → can mis-select | Capture moved item's `id` before `move` |

No-op affordances to remove or wire (design pass): toolbar volume slider (wired to nothing), "Jump to Now Playing" (empty action), Settings chevrons on disabled placeholder rows.

---

## Design-system gap (ui-designer)

11 font sizes, 11 spacing values, 8 vs 9 pt radii — no governing scale. Recommended `DS` token starter to replace scattered magic numbers in one pass:

- **Color:** accent / accentDeep / accentSubtle(.14) / accentMid(.24); surfaces windowBg / cardBg / **panelBg(.06, new)** / insetBg; hairline / accentBorder; labelPrimary/Secondary/Tertiary / **labelDisabled(new)**; **statusOK/Warning/Error (new)**. Move to an asset catalog for light/dark variants.
- **Type (5 rungs):** displayTitle 22/bold · sectionTitle 15/semibold · body 14 · caption 12 · micro 11/semibold (+`.tracking(0.5).textCase(.uppercase)`) · mono 12.
- **Space:** xs4 / sm8 / md16 / lg24 / xl32.
- **Radius:** chip4 / control8 / container10 (pick one pair, standardize).
- Follow the **system accent** (`.tint(.accentColor)`) for interactive controls; reserve `asAccent` for the logo/brand decoration.

---

## macOS-native feel & UX

- No first-run onboarding / empty-state CTA (PRD Journey 2.1 unimplemented) — new users have no obvious path to load music.
- No hover states on transport/playlist buttons; double-click uses `onTapGesture`+`Task.sleep` hack instead of `List(selection:)`; key shortcuts duplicated on rows *and* container (double-handling).
- Spectrum at 50 pt reads "decorative" (consider ≥80 pt); 88 individually-animated `RoundedRectangle`s → one `Canvas` + precomputed gradients; fade-to-0.4 when stopped looks broken (hide instead).
- `FixedHeaderView` is dead UI (never instantiated). Several private types per file violate the one-type-per-file rule (`ToolbarView`, `PlaylistView`, `SettingsTabView`, `NowPlayingWidget`).
- No `#Preview` macros anywhere — regressions in the EQ canvas (historically fragile) are hard to catch.

---

## Items requiring a live visual check (`make run`)

Light Appearance rendering · window-chrome seam · tertiary-label contrast on the now-playing row · spectrum bar density (88 × 2 pt @ ~400 pt) · EQ asymmetric margins (50 L / 20 R) · EQ polyline angularity · 10 pt format-badge legibility · Settings double `.padding(.horizontal, 16)` · segmented tab icon-weight mix · device-pill string (`name` vs `displayName`).

---

## Recommended sequencing

1. **Now:** fix correctness bugs C1–C6 (small, high-value; this commit).
2. **M4 (metering UI):** build the loudness meters (the `LoudnessModule` already exposes lock-free getters) *and* land the `DS` token layer + wire `currentPositionSeconds` / progress + integrate window chrome (`.commands`, `.windowStyle`).
3. **M5 + Sprint 5:** onboarding/empty state, EQ canvas polish (spline + fill + cursor/hover + handles), native accent, hover states.
4. **Then:** `make run` visual pass against the **[visual]** list.

---

**Status:** Review captured. C1–C6 fixed in the same change set; design-system + chrome + progress deferred to M4.
