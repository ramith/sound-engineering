# Design-deviation report — Now Playing vs release design 8a (7a + polish)

**For: Claude (fable 5) session in VS Code, repo `ramith/sound-engineering`.**
Visual truth: `Player Layout Variants.dc.html` → card **8a** (turn 8). Material recipes: `README.md` §"Liquid Glass adoption layer". Screenshot audited: 2026-07-19 implementation build.

General verdict: layout skeleton is right (hero title + analyzer, queue left, inspector right, footer transport). The deviations are mostly **material language (glass), control styling, and queue-row treatment**. Work through the numbered items; each lists the likely code home (verify — some views may have moved since commit `82bc287`).

---

## 1. Toolbar / ChromeBar — biggest visible gap
File: `Sources/AdaptiveSound/UI/Shell/ChromeBar.swift`
- **Tabs are a native segmented picker with divider lines and no active fill.** Design: capsule track (`rgba(0,0,0,.35)` fill, radius = height/2, inset shadow) with the ACTIVE tab as a teal gradient capsule (`#4FD2C0→#1FA893` vertical, dark text `#0c1413`, inner top highlight, soft teal glow) and hover states on inactive tabs. Replace `.pickerStyle(.segmented)` in `TabSelectorView` with a custom capsule control (keep the accessibility labels and reduce-motion animation gating).
- **Device pill truncates** ("MacBook Pr…"). The fixed 200pt width is too narrow once the 48 kHz readout moved outside it. Design: name + `48 kHz` mono readout INSIDE one pill, width ~240pt (keep fixed-width invariant), capsule radius (17) not rect-8, glass fill (white 9% + specular rim) instead of `Color.asCard`.
- **Logo glyph**: uses `music.note`; design/brand mark is the 5-bar waveform. Use the existing brand asset or `waveform` SF Symbol, squircle radius 9, teal gradient (already correct).
- Whole bar: apply glass material (blur + saturation, specular bottom hairline) per README §2 — currently flat.

## 2. Spectrum analyzer — bars are LED-segmented, design is solid
Files: `Sources/AdaptiveSound/UI/Spectrum/SpectrumAnalyzerView.swift` (+ whatever view wraps it in the hero lens now)
- **Bars render as dashed/segmented LED columns with dotted floating peak marks.** Design 8a: **solid smooth bars** (vertical gradient per bar, top radius 1.5) with a single **2px peak-hold cap** hovering 4px above each bar at 50% opacity of the bar color. Remove the segmentation; keep `SpectrumColorPalette` (correct).
- **Lens styling missing**: the panel is a flat dark rect with a plain border. Apply the glass-lens recipe: radius 20, fill `rgba(16,18,21,.42)` + blur/saturation, specular top rim, hairline, bottom light bleed, drop shadow; 4 horizontal gridlines (white 4–6%).
- Scale labels exist (good) — keep `0 dB` top-right and 20 Hz–20 kHz row.

## 3. Queue — row treatment and header
Files: `Sources/AdaptiveSound/UI/Playlist/PlaylistView.swift`, `PlaylistItemRow.swift`
- **Drag handles (≡) are permanently visible on every row.** Design has none — rows lead with the index number (active row: animated 3-bar equalizer). Show the handle only on hover, or rely on drag-anywhere reordering.
- **Active row**: currently a heavy full-bleed teal band with a play triangle. Design: subtle `teal 16%` fill + 1px teal ring, radius 12, title in `#8AF0E0` semibold, index replaced by the 3-bar mini equalizer (animates only while playing; respect Reduce Motion). Remove the play-triangle glyph.
- **Filter field**: full-width giant bar. Design: compact right-aligned capsule pill (~30pt high, magnifier + "Filter queue") in the queue header row.
- **Header**: "QUEUE / 6 tracks" mono block floats far above the list, and queue action buttons (trash/shuffle/repeat/play) float separately mid-right. Consolidate into ONE header row directly above the list: `Queue` (14pt bold) · `6 tracks · <total>` (11pt mono, 40% white) · spacer · actions + filter pill. Keep the Up Next / Recent segmented control but style it as a small capsule pair, left-aligned in the same header block rather than centered in open space.
- Row format badge: keep, but capsule radius (9) and fixed 18pt height per 8a.
- Missing: full file-path tooltip on rows (`.help(track.url.path)`).

## 4. Inspector column (Master Gain / Intensity / Loudness / Headphones)
Files: `NowPlayingInfoView.swift` (ReimagineSectionView, HeadphonesSectionView), `MasterGainSliderView.swift`, `LoudnessMetersView.swift`, container `NowPlayingTabView.swift`/`RightPanelView.swift`
- **Panel is a flat full-height dark card touching the content edges with a large empty bottom region.** Design: floating glass panel — radius 22, glass fill + blur, specular rim, hairline, drop shadow, inset 16pt from window right/bottom, top aligned with the queue header, height hugging content (no stretch; let the glow background show below).
- **Sliders are native NSSlider style.** Design: 5pt carved track (`inset` shadow), teal gradient fill with subtle glow, 14pt white round knob. Build one custom slim slider style, reuse for gain + intensity (keep bindings/accessibility).
- **Master gain value** shows `4.0 dB` → must be signed `+4.0 dB`.
- **Loudness**: Integrated/Short-term are text-only and Peak is a bare bar with no value. Design: all three rows = label (62pt) + 6pt gradient meter bar + right-aligned mono value; True peak tips into amber `#FFB347` and its value turns amber above −1 dBTP. Label "True peak", not "Peak".
- **Headphones section**: the long parenthetical paragraph is always visible. Design: single line "Connect headphones to enable." — move the long explanation into a `.help()` tooltip or info popover. Whole block at 55% opacity when disabled (currently 50% — fine), grey knob.
- **"Bypass / Full Blend" caption row**: keep (useful), but style 9.5pt mono 32% white, directly under the intensity slider.
- Section dividers: use gradient-fade hairlines (transparent → white 12% → transparent), not solid.

## 5. Ambient background glow — wrong hue
Home: background of the Now Playing tab (wherever the glow ZStack was added).
- Current glow reads **amber/olive top-left**. Design: **teal** `rgba(41,182,164,.28)` top-left, **lime** `rgba(200,240,106,.12)` bottom-right, **blue** `rgba(79,178,214,.10)` mid-right — all heavily blurred, dark appearance. Check that the teal glow isn't compositing over a warm base or using the wrong color token.

## 6. Hero badges
File: hero view (evolved from `NowPlayingWidget`/`NowPlayingInfoView`)
- Currently three badges: `ENHANCED` / `48 kHz` / `20 %`. Design: two — `ENHANCED · 20%` (one badge, pulsing 5px dot, teal glass) and `MP3 · 48 kHz` (format + rate combined, grey glass). Fold intensity into the ENHANCED badge and add the missing **format** (MP3/FLAC) segment. Fixed 22pt height, capsule radius, artist separated from badges by a 3px dot.

## 7. Footer transport (NowPlayingBar)
File: `Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift`
- Keep structure (correct per INTEGRATION.md). Apply glass restyle only: specular top hairline on the bar, scrubber → 5pt carved track + teal gradient fill + 14pt knob, play button gains inner top highlight + bottom shade. Right-side `Enhanced · 48 kHz` readout is correct.

## 8. Cross-cutting
- All new colors via `DesignSystem` tokens with light-mode variants; respect `accessibilityReduceTransparency` (opaque fallback) and Reduce Motion (no pulse/equalizer animation).
- Alignment grid: floating panels inset 16pt from window edges; 26–28pt left text gutter (repo uses 28 — keep repo value consistently); inspector top aligns with queue header row.
- Run both appearances + `scripts/strict-gate.sh` before each commit; work as small PRs in the order: analyzer → toolbar → queue → inspector → glow → badges → footer.

## Suggested opening prompt for the session
> Fix the Now Playing screen's deviations from the release design per docs/design/now-playing-7a/DEVIATIONS.md, one numbered section per PR, starting with §2 (analyzer). Visual truth is the 8a card in Player Layout Variants.dc.html. Don't restructure AppShell or move the transport; all colors through DesignSystem tokens; respect Reduce Transparency/Motion; strict-gate must pass.
