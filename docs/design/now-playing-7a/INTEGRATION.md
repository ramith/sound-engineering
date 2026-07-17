# 7a Liquid Glass — Integration guide for `ramith/sound-engineering`

**Read this BEFORE README.md's generic process.** This guide maps the 7a/8a release design onto the actual codebase (audited @ main, 2026-07-16). The repo has a governed architecture — do NOT drop `NowPlayingView.swift` in as-is; it's a visual reference only.

## What the codebase already has (don't rebuild)
- **Teal→Lime spectrum**: `UI/Spectrum/SpectrumColorPalette.swift` already implements the exact palette + 0.82 vertical darken; `SpectrumAnalyzerView` already dims to 0.4 when paused, respects Reduce Motion, and runs off real FFT (`AudioViewModel.spectrumBars`, ~20 Hz). ✔ matches design.
- **Shell**: `AppShell` = fixed 60pt `ChromeBar` + bounded content + fixed 64pt footer `NowPlayingBar` (global transport). Native titlebar carries traffic lights.
- **Chrome**: `ChromeBar` = logo squircle + fixed-200pt device pill (`Menu`) + segmented `TabSelectorView`.
- **Now Playing tab**: `NowPlayingTabView` = 50/50 split; `LeftPanelView` (spectrum → master gain → track info, scrollable) + `RightPanelView` → `PlaylistView` (queue). *[Superseded by S10.7 PR 5: the 8a restructure replaced the split with hero-row + queue-flex + 260pt inspector; `LeftPanelView`/`RightPanelView` deleted.]*
- **Tokens**: `DesignSystem.swift` — dynamic light/dark colors (WCAG-audited), Dynamic Type fonts, spacing/radius scales, `ShellMetrics`, `Footer` metrics. New code must use these.
- Loudness meters (`UI/Loudness/LoudnessMetersView.swift`), format badges, queue rows with now-playing/selected tints — all exist.

## Design ↔ code conflicts to resolve (decide before coding)
1. **Transport location.** 7a puts prev/play/next + scrubber in the Now Playing hero; the app deliberately moved transport to the global footer (`NowPlayingBar`, L3 design doc `docs/sprints/l3-footer-transport-design.md`). **Recommendation: keep the footer transport** (it's global across tabs) and adopt 7a's hero as title + badges + analyzer only. Optionally restyle the footer with the glass recipe.
2. **Floating toolbar capsule.** `ChromeBar` is a full-width band under the native titlebar. Making it a detached floating capsule conflicts with the L2 window-drag setup and the "fixed top-left" invariant. **Recommendation: apply the glass material to the existing band** (background + specular bottom hairline) and to the device pill/tab control, not the floating geometry.
3. **Light mode.** 7a's recipes are dark-tuned; the app is dual-appearance via `DesignSystem.Color.dynamic(light:dark:)`. Every new glass fill needs a light variant (e.g. white-based glass `rgba(255,255,255,.55)` + dark hairlines).
4. **The design's 5-tab set** (adds "Monitoring") matches `TabSelection` — ✔ no change.

## Incremental implementation plan (small, safe PRs)
**PR 1 — Glass tokens.** Extend `DesignSystem` with a `Glass` enum: fills (`glassPanel`, `glassControl`), rim/hairline/bleed shadow values, radii (panel 22, lens 20), and a `.glassPanel()` ViewModifier built on `.ultraThinMaterial` + overlays. Respect `accessibilityReduceTransparency` (fall back to `Color.panel`). No visual change yet.
**PR 2 — Ambient glow.** Add the radial glow ZStack behind `NowPlayingTabView` (teal top-left, lime bottom-right, blue mid-right; dark appearance only, subtler in light).
**PR 3 — Analyzer lens.** Wrap `SpectrumAnalyzerView` in the glass lens: `.glassPanel(radius: 20)` + dB gridlines + 0 dB label + 20 Hz–20 kHz scale + peak-hold caps (new small overlay in the same file/folder; heights still from `spectrumBars`).
**PR 4 — Hero.** Restyle `NowPlayingInfoView` per 8a: 28pt/800 title (map to `DesignSystem.Font.displayTitle` weight override), artist + ENHANCED/format badges (reuse `FormatBadgeView`, add capsule glass variant), pulsing dot gated on Reduce Motion.
**PR 5 — Inspector.** Restyle `RightPanelView`'s siblings: master gain + intensity sliders (5pt carved tracks, 14pt knobs, glow fills), `LoudnessMetersView` bars, disabled crossfeed block at 55% opacity. Keep it in `LeftPanelView`'s scroll (current home) OR move to a 260pt trailing glass column per 8a — flag: that changes `NowPlayingTabView`'s 50/50 `containerRelativeFrame` split to queue-flex + fixed-260.
**PR 6 — Chrome + footer glass.** Apply glass materials to `ChromeBar` band, device pill, tab control, and `NowPlayingBar`. Keep all `ShellMetrics`/`Footer` metrics unchanged.

Each PR: `make run` visual check in BOTH appearances + Reduce Transparency/Motion, and the repo's strict CI (`scripts/strict-gate.sh`, swiftlint) must pass. The `.claude/agents/swiftui-pro.md` + `.claude/skills/macos-design/` agents in the repo are the right reviewers to invoke.

## Prompt to give Claude Code (VS Code)
> Implement the "7a Liquid Glass" release design per docs/design/now-playing-7a/INTEGRATION.md, following its 6-PR plan. Start with PR 1 (DesignSystem.Glass tokens). Visual reference: now-playing-base.html + the 8a card in Player Layout Variants.dc.html. Do not move the transport out of NowPlayingBar; do not change AppShell band structure. All colors via DesignSystem tokens with light+dark variants; respect Reduce Transparency and Reduce Motion.

## File map (design element → code home)
| Design (8a) | Code |
|---|---|
| Ambient glows | `NowPlayingTabView` background ZStack (new) |
| Toolbar glass | `UI/Shell/ChromeBar.swift` (+`DesignSystem.Glass`) |
| Device pill + 44.1 kHz readout | `ChromeBar.DevicePillView` (rate from `AudioEngineBridge+Devices`) |
| Hero title/badges | `UI/NowPlaying/NowPlayingInfoView.swift` |
| Analyzer lens + grid + peaks | `UI/Spectrum/SpectrumAnalyzerView.swift` (+ small overlays) |
| Spectrum palette | ✔ already `SpectrumColorPalette.swift` |
| Master gain slider | `UI/NowPlaying/MasterGainSliderView.swift` |
| Intensity slider | left panel (bridge: `AudioEngineBridge+IntensityControl`) |
| Loudness meters | `UI/Loudness/LoudnessMetersView.swift` |
| Crossfeed toggle | bridge: `AudioEngineBridge+CrossfeedControl` |
| Queue rows/tooltips | `UI/Playlist/PlaylistView.swift` + row views (tints: `rowNowPlaying`/`rowSelected`) |
| Transport | stays in `UI/Shell/NowPlayingBar.swift` (glass restyle only) |
