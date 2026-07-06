# L3 — Footer Transport Bar (Design Spec)

Status: ready to implement · Author: ui-designer · Consumer: swiftui-pro
Target file: `Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift` (+ small edits listed in §13)

This is the persistent 64pt transport footer that lives on **every** tab. It replaces the
idle "Nothing playing" stub and becomes the app's single, global transport. The prev/play/next
controls and the scrubber are **relocated here** from the Now Playing left panel and removed there
(§13). This spec is exhaustive — implement the numbers verbatim; make no visual guesses.

---

## 1. Layout decision (read first)

**Single-row, four-region horizontal transport**, left → right:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 16                                                                                    16  │
│  ┌── R1: Now Playing info ──┐  20  ┌ R2: controls ┐ 16 ┌──── R3: scrubber ────┐ 16 ┌ R4 ┐ │
│  ┌────┐  Kind of Blue            ⏮   ⬤    ⏭        1:12 ▬▬▬▬▬▬●───────── 9:26   ● Pure  │ │
│  │ art│  Miles Davis                                                              96 kHz │ │
│  └────┘                                                                                   │
│  (button → Now Playing tab)  (fixed 130)      (flexible fill, min 228)         (fixed 120) │
└────────────────────────────────────────────────────────────────────────────────────────┘
   ^ 64pt tall, full window width. Band height + panel background + top hairline are painted
     by AppShell — this view paints none of them.
```

Why single-row (and not Music.app's 2-row centred "LCD" block): the band is only 64pt. A single
row keeps every element on one 32pt midline with generous breathing room, avoids a cramped
two-line centre, and matches the region breakdown requested. "Music.app-style" is honoured
through **compact control sizing, a hover-reveal scrubber thumb, click-info-to-open-Now-Playing,
and restraint** — not through copying its exact block geometry.

### 1.1 Width budget — proof it never clips at the 880 minimum

Horizontal inset = 16pt each side (matches the chrome header). Usable width at the 880 window
minimum = **880 − 32 = 848pt**.

| Region | Min width | Ideal/Max | Grows? | Truncates? |
|---|---|---|---|---|
| Gap: leading inset | 16 | 16 | no | — |
| **R1 Now Playing info** | 174 | 240 (cap) | no (capped) | yes — title/artist tail-ellipsis inside the text column |
| Gap R1→R2 | 20 | 20 | no | — |
| **R2 Transport controls** | 130 | 130 | no | never |
| Gap R2→R3 | 16 | 16 | no | — |
| **R3 Scrubber + times** | 228 | ∞ | **yes — absorbs all surplus** | no (track flexes; time labels fixed) |
| Gap R3→R4 | 16 | 16 | no | — |
| **R4 Signal slot** | 120 | 120 | no | condensed line tail-ellipsis inside slot |
| Gap: trailing inset | 16 | 16 | no | — |

At 880 with R1 at its **ideal** 240: `240+20+130+16+228+16+120 + 32 inset = 802` → **46pt of
slack**, all handed to the scrubber track (track grows from its 120 min to ~166). Nothing clips.
As the window widens, every extra point goes to the scrubber track. As it narrows toward 880,
R1 collapses from 240 toward 174 (title/artist ellipsis) and the scrubber toward its 228 min;
controls, time labels, art, and the signal slot are size-invariant. The window can't go below 880
(`ShellMetrics.windowMinWidth`), so the min column always fits.

**Fixed vs. flexible, one line:** art thumb, both time labels, all three control buttons, and the
signal slot are **fixed**; only the scrubber **track** flexes; only the title/artist text
**truncates**.

---

## 2. Bar container rules

`AppShell` already does all of this — **do not repeat it in `NowPlayingBar`**:
- Frames the footer to exactly `ShellMetrics.footerHeight` (64pt).
- Paints `DesignSystem.Color.panel` as the background.
- Draws the top `Hairline()` (0.5pt `Color.hairline`) separating footer from content.

So `NowPlayingBar.body` is just:
- One `HStack(alignment: .center, spacing: 0)` (regions carry their own gaps via `Spacer`/padding, or use explicit `.padding` — see below) inside `.padding(.horizontal, 16)`.
- `.frame(maxWidth: .infinity, maxHeight: .infinity)` so content centres vertically in the 64pt band.
- Reads `AudioViewModel` from the environment (`@Environment(AudioViewModel.self)`).
- No background, no height, no hairline, no additional shadow (restraint — the hairline is the only separator).
- Clamp Dynamic Type: `.dynamicTypeSize(.small ... .xLarge)` on the whole bar (see §10).

Recommended concrete gap handling: build the row as
`HStack(spacing: 0) { R1; Spacer().frame(width: 20); R2; Spacer().frame(width: 16); R3; Spacer().frame(width: 16); R4 }`
— fixed gaps, not elastic `Spacer()`s, so region positions are deterministic and only the scrubber
track flexes.

---

## 3. Region 1 — Now Playing info (button → Now Playing tab)

A single `Button` (`.buttonStyle(.plain)`) whose action is `viewModel.selectedTab = .nowPlaying`.
Its label is an `HStack(spacing: 10)`:

**Art thumb**
- Size: `DesignSystem.Artwork.thumb` = **44×44** (reuse the existing token).
- Corner radius: `DesignSystem.Radius.control` = 8, `.continuous`.
- Overlay stroke: `RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Color.hairline, lineWidth: 0.5)` (matches `AlbumArtworkView`).
- Content today: placeholder = `Image(systemName: "music.note")` at 18pt over a `DesignSystem.Color.card` fill; glyph colour `DesignSystem.Color.labelTertiary`. (When a per-track artwork key is wired, swap the placeholder for `AlbumArtworkView(key:, side: 44)` — it already renders this exact placeholder on a miss, so the look is identical.)

**Text column** — `VStack(alignment: .leading, spacing: 1)`:
- Title: `DesignSystem.Font.trackTitle` (13 / semibold — **new token, §12**), colour `DesignSystem.Color.label`, `.lineLimit(1)`, `.truncationMode(.tail)`. Source: current track's `name` (filename-derived).
- Artist/subtitle: `DesignSystem.Font.trackSubtitle` (11 / regular — **new token, §12**), colour `DesignSystem.Color.labelSecondary`, `.lineLimit(1)`, `.truncationMode(.tail)`. Source: artist metadata when available; today falls back to `"Unknown Artist"` (consistent with `NowPlayingWidget`).

**Region frame**: `.frame(minWidth: 174, idealWidth: 240, maxWidth: 240, alignment: .leading)`. `layoutPriority(0)` (yields growth to the scrubber). The text column is the part that ellipsises; the art is fixed.

**Hover / press affordance** (loaded only): on hover, fill a `RoundedRectangle(cornerRadius: DesignSystem.Radius.control)` behind the whole region with `DesignSystem.Color.label.opacity(0.06)` and set the pointing-hand cursor (`.onHover { NSCursor.pointingHand.push()/pop() }` or `.pointerStyle(.link)` on macOS 15+). On press, drop region opacity to 0.7. Animate the hover fill with `.easeOut(duration: 0.12)`, gated by Reduce Motion.

**Determining the current track** (mirror `NowPlayingWidget`):
```
if let i = viewModel.selectedTrackIndex, i < viewModel.playlist.count { track = viewModel.playlist[i] } // loaded
else { idle }
```

---

## 4. Region 2 — Transport controls

`HStack(spacing: 18)` of prev · play/pause · next. Fixed intrinsic width ≈ **130pt**; apply
`.fixedSize()` so it never compresses or stretches. Vertically centred (the 34pt play button in a
64pt band leaves 15pt of breathing room top and bottom).

**Previous / Next — plain glyphs (no background circle):**
- Symbols: `backward.fill` / `forward.fill`.
- Symbol size: **15pt, weight `.medium`**; colour `DesignSystem.Color.label`.
- Hit target: 30×30 via `.frame(width: 30, height: 30).contentShape(Rectangle())`.
- Hover: colour stays `label` but raise from a rest opacity of 0.85 to 1.0 (subtle). Pressed: opacity 0.6.
- Actions: `viewModel.previousTrack()` / `viewModel.nextTrack()`.
- This is a **compact, background-less** variant. The existing `TransportButton` draws a card-filled circle (52pt) — do **not** reuse it as-is here; either add a `plain` style to `TransportButton` or inline a small button. Recommended: add `enum TransportButtonStyle.Kind { case plain, filled }` to the existing component so both footer skips and any future filled use share one type.

**Play / Pause — gradient circle (the app's signature control):**
- Diameter: **34×34**, `Circle()` filled with `DesignSystem.Gradient.iconFill` (the teal squircle gradient used by the logo).
- Symbol: `pause.fill` when `viewModel.isPlaying` else `play.fill`; **14pt, weight `.semibold`**; colour `DesignSystem.Color.onAccent` (white — reads on the teal in both appearances).
- `.clipShape(Circle()).contentShape(Circle())`.
- **No drop shadow** (the old 72pt version's radius-10 shadow is far too heavy for a flat, clean footer). Pressed: opacity 0.7.
- Action: `viewModel.isPlaying ? viewModel.pause() : viewModel.play()`.

Prev/next stay **enabled** whenever a track is loaded (matches current behaviour; the view model
no-ops at playlist ends). Dimming them at the ends is optional and not required.

---

## 5. Region 3 — Scrubber + times (the flexible fill)

Port `TransportScrubberView`'s internals with the compact adjustments below. `HStack(spacing: 8)`:

`[ elapsed time ] [ track (flex) ] [ duration time ]`

**Time labels** (both):
- Font: `DesignSystem.Font.monoSmall` (11pt monospaced) + `.monospacedDigit()`.
- **Fixed width 46pt each** (accommodates `h:mm:ss` for long classical tracks — no track jitter as digits change). Leading (elapsed) label `alignment: .trailing`; trailing (duration) label `alignment: .leading`.
- Elapsed = `displayPosition` (the drag position while scrubbing, else `playbackPosition`); colour `labelTertiary`, promoting to `labelSecondary` while dragging (keep existing `prominent` logic). Duration = `formatDuration(duration)` or `"--:--"` when `duration <= 0`; colour `labelTertiary`.
- Both `.accessibilityHidden(true)` (the track element carries the value — see §10).

**Track:**
- Capsule track height **3pt**, hit-area height **20pt** (`.frame(height: 20)`), centred.
- Track background: `DesignSystem.Color.card`. Filled portion: `DesignSystem.Color.accent` when playing, `accent.opacity(0.5)` when paused, `labelTertiary` when `signalPath.interrupted` (keep existing `fillColor`).
- **Thumb reveals on hover/drag only** (cleaner than the current always-on thumb): hidden at rest; on hover or drag show a **10pt** `Circle().fill(DesignSystem.Color.label)` with a subtle shadow (`.black.opacity(0.3), radius 3, y 1`) and hover-scale 1.15. Hidden entirely when `duration <= 0`.
- `.frame(maxWidth: .infinity)` on the track so it absorbs all surplus width. This region carries `layoutPriority(1)`.

**Tooltip:** keep — shown during drag only, `monoSmall` semibold inside a `card` capsule with a 0.5 `hairline` stroke, positioned above the track (`yOffset: -20`), clamped to stay in bounds, `.allowsHitTesting(false)`.

**Region min width:** 46 + 8 + 120 + 8 + 46 = **228pt**.

**Interaction:** `DragGesture(minimumDistance: 0)` → `onChanged` updates the drag fraction (live
elapsed label + tooltip); `onEnded` commits `viewModel.seek(to:)`. Because `minimumDistance` is 0,
a simple click-to-seek works too. Gesture attached only when `duration > 0`. Pointing-hand cursor
on hover over the track.

---

## 6. Region 4 — Signal slot (rightmost, informational)

A fixed **120pt** slot showing a **condensed** signal-path readout (audiophile at-a-glance).
Do NOT drop the full multi-segment `SignalPathBadge` here — an HStack of many segments truncates
poorly and could clip. Instead show a compact indicator:

- `HStack(spacing: 5)`:
  - Status dot: `Circle()` 6×6. Colour = `DesignSystem.Color.accent` when path is `.pure`, `DesignSystem.Color.statusWarning` when interrupted or fell back, else `labelTertiary`.
  - One condensed line: `"{Path} · {rate}"` e.g. `"Pure · 96 kHz"` / `"Enhanced · 48 kHz"`. Font `monoSmall`, colour `labelSecondary`, `.lineLimit(1)`, `.truncationMode(.tail)`. Interrupted state: warning triangle + `"Disconnected"`.
- `.frame(width: 120, alignment: .trailing)`.
- The full detailed badge (bits, decoder, intensity %, crossfeed) remains in the Now Playing tab — the footer stays terse.

The slot is a **reserved fixed width even when idle** (empty content), so the scrubber's width is
identical in idle and loaded states — guaranteeing zero horizontal reflow when playback starts
(§7). Reuse `SignalPathInfo.formattedRate` for the rate string.

---

## 7. Idle vs Loaded — identical 64pt, zero jump

Both states are the same height (AppShell fixes the band at 64pt) **and** the same horizontal
geometry (R4 is reserved, R1 is fixed-width). Nothing moves vertically or horizontally when
playback starts/stops — only content and enabled-ness change.

| Element | Idle (no track selected) | Loaded |
|---|---|---|
| R1 art | 44pt placeholder, `music.note` in `labelTertiary` over `card` | same frame; artwork/placeholder |
| R1 title | "Nothing playing" — `trackTitle`, `labelSecondary` | track `name` — `trackTitle`, `label` |
| R1 subtitle | "Select a track to play" — `trackSubtitle`, `labelTertiary` | artist / "Unknown Artist" — `trackSubtitle`, `labelSecondary` |
| R1 button | disabled (no navigation, no hover highlight) | enabled → opens Now Playing tab |
| R2 prev/next | shown, disabled, colour `labelDisabled` | enabled, colour `label` |
| R2 play | `play.fill` on a **flat `card`-filled circle**, glyph `labelDisabled`, disabled (no gradient) | gradient circle, `onAccent` glyph, enabled |
| R3 track | 0 fill, thumb hidden, no gesture | filled, hover thumb, drag-to-seek |
| R3 times | `--:--` / `--:--`, `labelTertiary` | live elapsed / duration |
| R4 signal slot | empty (reserved 120pt) | condensed path readout |

Idle is detected exactly as `NowPlayingWidget` does: `selectedTrackIndex == nil || >= playlist.count`.

---

## 8. Interaction summary

- **Click R1 (track info):** `viewModel.selectedTab = .nowPlaying`. Hover highlight + pointing-hand cursor. (This is the mini-player-opens-full-player convention, adapted to a tabbed app — the most Music.app-like behaviour available here.)
- **Play/pause click:** toggle `play()`/`pause()`.
- **Prev/next click:** `previousTrack()` / `nextTrack()`.
- **Scrubber:** hover reveals the thumb + pointing cursor; drag (or click) scrubs, live-updating the elapsed label and tooltip; seek commits on release.
- **Keyboard (recommended, optional):** if not already owned by a `Commands`/menu, wire Space → play/pause via a hidden `Button(...).keyboardShortcut(.space, modifiers: [])` on the play control. Do NOT add if a global shortcut already exists (avoid double-fire). Skip shortcuts are not required for L3.
- The footer is **not** a window-drag region (that's the chrome header). No right-click menu.

---

## 9. Accessibility (VoiceOver / Dynamic Type / Reduce Motion)

**VoiceOver** — expose regions as separate elements (do not merge the bar):
- R1 button: label `"Now Playing, {title}, {artist}"` (idle: `"Nothing playing"`); hint `"Opens the Now Playing tab"`; `.disabled` when idle.
- Play/pause: label `"Play"` / `"Pause"` (keep existing).
- Prev/next: `"Previous track"` / `"Next track"` (keep existing).
- Scrubber: keep `TransportScrubberView`'s pattern — `.accessibilityElement(children: .ignore)`, label `"Playback position"`, value `"{elapsed} of {duration}"` (+ interrupted note), and the `accessibilityAdjustableAction` ±5s (2% of duration, min 5s). Time labels stay `.accessibilityHidden(true)`.
- Signal slot: label `"Signal path"`, value the spoken form (`"Pure mode, 96 kilohertz"` etc.). Reuse the badge's `accessibilityValue` phrasing.

**Dynamic Type** — the band is fixed at 64pt and cannot grow, so clamp: apply
`.dynamicTypeSize(.small ... .xLarge)` to the whole bar. This lets small/large system sizes track
while preventing accessibility sizes from overflowing the fixed chrome (HIG-acceptable for a
persistent transport, like the menu-bar clock). Time labels are monospaced at a fixed 11pt. Never
add a scrolling/marquee title — truncate with tail ellipsis (respects Reduce Motion and restraint).

**Reduce Motion** — gate every animation on `@Environment(\.accessibilityReduceMotion)`: the thumb
hover-scale, the info hover-fill fade, and the tab-switch transition (the tab picker already
animates conditionally). With Reduce Motion on, state changes are instant.

---

## 10. Light + Dark appearance

Every colour is an existing appearance-reactive `DesignSystem.Color.*` token, so light/dark come
for free — no per-view `colorScheme` branching.
- Footer bg = `panel` (white in light, white·0.06 over the dark window in dark). Painted by AppShell.
- Art placeholder fill = `card`; glyph = `labelTertiary`. Hairline stroke = `hairline`.
- Skip glyphs = `label`; play gradient (`Gradient.iconFill`) and its white `onAccent` glyph are appearance-independent and read on both.
- Scrubber: filled = `accent` (both); track bg = `card`; times = `labelTertiary`; thumb = `label`.
- Info hover highlight = `label.opacity(0.06)` (a faint gray on the light panel, a faint white on the dark panel — correct in both).
- Idle/disabled text & glyphs = `labelDisabled` (WCAG-exempt).
- No hard-coded shadows that assume a dark background (the play button has no shadow now — good for light mode too). Contrast: `labelSecondary`/`labelTertiary` already clear WCAG AA on `panel` per the token comments.

---

## 11. Micro-motion

- Play↔pause symbol swap: instant (no cross-fade) — matches system transport.
- Fill colour play→pause (accent→accent·0.5): `.easeOut(0.15)`, Reduce-Motion gated.
- Thumb reveal/scale: `.easeOut(0.12)`, Reduce-Motion gated.
- Info hover fill: `.easeOut(0.12)`, Reduce-Motion gated.
- Tab switch on info click: uses the existing conditional `.easeInOut(0.2)` from `selectedTab`.

---

## 12. Token delta (add to `DesignSystem.swift`)

Reused as-is (no change): `Color.panel/card/hairline/label/labelSecondary/labelTertiary/labelDisabled/accent/onAccent/statusWarning`, `Gradient.iconFill`, `Radius.control`, `Font.monoSmall`, `Artwork.thumb` (44), `ShellMetrics.footerHeight` (64).

**New — Typography** (compact media pairing; no existing token matches — `body` is 14, `sectionTitle` 15, `caption` 12, `micro` 11-semibold):
```swift
// in DesignSystem.Font
static let trackTitle    = SwiftUI.Font.system(size: 13, weight: .semibold) // compact now-playing title
static let trackSubtitle = SwiftUI.Font.system(size: 11, weight: .regular)  // compact artist/subtitle
```
Rationale: 13/11 semibold-over-regular is Apple's compact-media rhythm (Music mini-player, control-centre now-playing). Reusable by any future mini/now-playing surface.

**New — Footer metrics** (keeps the footer free of magic numbers, mirroring how `ShellMetrics`/`Visualizer`/`Artwork` already group sizing; the whole reason `DesignSystem` exists per the GUI review):
```swift
enum Footer {
    static let hInset: CGFloat            = 16   // matches the chrome header inset
    static let infoMinWidth: CGFloat      = 174
    static let infoIdealWidth: CGFloat    = 240
    static let artGap: CGFloat            = 10
    static let controlSpacing: CGFloat    = 18
    static let playButton: CGFloat        = 34
    static let playSymbol: CGFloat        = 14
    static let skipButton: CGFloat        = 30   // hit target
    static let skipSymbol: CGFloat        = 15
    static let scrubberTrackMinWidth: CGFloat = 120
    static let scrubberTrackHeight: CGFloat   = 3
    static let scrubberHitHeight: CGFloat     = 20
    static let thumbSize: CGFloat         = 10
    static let timeLabelWidth: CGFloat    = 46
    static let signalSlotWidth: CGFloat   = 120
    static let regionGapInfoToControls: CGFloat = 20
    static let regionGap: CGFloat         = 16   // controls→scrubber, scrubber→signal
}
```
(Art size stays `Artwork.thumb`; band height stays `ShellMetrics.footerHeight`.)

---

## 13. Implementer file map

**Edit `Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift`** — build the full transport described above. Read `AudioViewModel` from the environment. Paint no height/background/hairline (AppShell owns them).

**Edit `Sources/AdaptiveSound/UI/NowPlaying/LeftPanelView.swift`** — REMOVE `TransportScrubberView()` and `PlayControlsView()` from the stack (they now live in the footer). Keep `SpectrumAnalyzerView`, `MasterGainSliderView`, the hairline, and `NowPlayingInfoView`. Re-check vertical rhythm after removal.

**Extract/port the scrubber** — factor `TransportScrubberView`'s track/thumb/tooltip/gesture into the footer (or reuse the view with the compact tokens from §5 and §12). The old file can be deleted once the footer owns the scrubber, or kept and re-parameterised — implementer's choice, but the footer must not import the 72/52pt sizing.

**`TransportButton.swift`** — add a `plain` (background-less) style kind for the footer skips (§4), or inline a compact skip button in the footer. Do not use its current 52pt card-circle look in the footer.

**Delete/retire `PlayControlsView.swift`'s 72/52pt sizing** — those sizes are dead once the footer is the sole transport. If the file is removed, drop it from any preview/target references.

**`DesignSystem.swift`** — add the tokens in §12.

**Do not** add third-party frameworks. **Do not** change `AppShell`'s footer framing.
