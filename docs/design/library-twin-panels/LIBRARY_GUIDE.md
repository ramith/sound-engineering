# LIBRARY GUIDE — Twin Panels, PR by PR

Each PR has: **(1)** what changes, **(2)** which file, **(3)** exact target values, **(4)** a SwiftUI sample, **(5)** a done-checklist. Paths were correct at the last audit — if a view moved, search the type name, don't guess. Compare every step against the matching PNG.

Assumed already present from the Now Playing work (if not, port them first):
`Color.asTealBright/asTealMid/asTealDeep/asTealText/asTealTitle/asOnTeal`, `LinearGradient.asTealButton`, the `StyledGlassBar` modifier, and the `MiniEqualizer` / `EqBar` views. This guide reuses all of them.

Add one shared shape for the two cards (PR-A):

```swift
// GlassCard.swift  (new, Sources/AdaptiveSound/UI/DesignSystem/)
struct GlassCard: ViewModifier {
    var opacity: Double = 0.70          // rail 0.72, list 0.66 in the mock — close enough
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.12).opacity(opacity)))          // dark tint over the material
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))    // hairline ring
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.13), .clear],
                    startPoint: .top, endPoint: .center), lineWidth: 1)) // top highlight
            .shadow(color: .black.opacity(0.5), radius: 25, x: 0, y: 18)
            .compositingGroup()
    }
}
extension View { func glassCard(opacity: Double = 0.70) -> some View { modifier(GlassCard(opacity: opacity)) } }
// Reduce Transparency: when accessibilityReduceTransparency, replace .ultraThinMaterial
// with a solid Color(white:0.12) fill and drop the two overlays' translucency.
```

---

## PR-A — scaffolding (do first)

1. Confirm the Now Playing tokens/`StyledGlassBar`/`MiniEqualizer` exist; if not, port them.
2. Add `GlassCard.swift` above.
3. Nothing visual changes yet. Checklist: builds, strict-gate passes.

---

## PR-B — window background + shared glow  → `png/00-full-window.png`

**File:** `Sources/AdaptiveSound/UI/Library/LibraryView.swift` (the screen root, below the toolbar and above the transport bar).

**What changes:** the flat gray Library body gets the dark window base + one soft teal glow behind everything.

- Base fill: `Color(hex: 0x131418)`.
- Glow: a single radial `asTealMid` at 16% → clear, ~1100×640, blurred ~8, positioned upper-left-of-center (see PNG). It sits BEHIND both cards, in a `ZStack` at the very back, `.allowsHitTesting(false)`.

```swift
ZStack {
    Color(hex: 0x131418)
    RadialGradient(colors: [Color.asTealMid.opacity(0.16), .clear],
                   center: .init(x: 0.34, y: 0.30), startRadius: 0, endRadius: 560)
        .frame(width: 1100, height: 640)
        .blur(radius: 8).offset(x: -180, y: 40)
        .allowsHitTesting(false)
    libraryContent   // the HStack of the two cards, PR-C/PR-D
}
```

Checklist: matches the PNG's background + glow; no glow leaks over the top/bottom bars.

---

## PR-C — left navigation as a glass card  → `png/01-rail.png`

**File:** `LibrarySidebarView.swift` (or wherever the source list / outline lives).

**What changes:** the native `List`/sidebar becomes a fixed-width floating glass card of custom nav rows.

- Card: width **234**, `.glassCard(opacity: 0.72)`, inner padding 12×10, row spacing 3. It hugs its content at the TOP (`VStack { card; Spacer() }`), it does NOT stretch to the window bottom.
- Nav row (`NavRow`): height 38, corner radius 10, 11pt gap between icon and label.
  - Idle: icon + label `white 72%`, transparent background; hover `white 6%`.
  - Active: background `asTealMid 14%`, 1px ring `asTealMid 30%`, icon + label `asTealText`, label weight semibold.
  - Optional trailing count (playlists) in mono `white 40%`; optional trailing remove glyph (folders) in `white 35%`.
- Sections, in order: **Songs / Albums / Artists / Genres**, divider, **PLAYLISTS** header (+ add button `asTealText`) then playlist rows, divider, **MUSIC FOLDERS** header (+ add) then folder rows. Section headers: 10.5pt heavy, letter-spaced, `white 42%`.

```swift
struct NavRow: View {
    let icon: String; let label: String
    var count: Int? = nil; var removable = false; var active = false
    @State private var hover = false
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 13))
                .frame(width: 18).foregroundStyle(active ? Color.asTealText : .white.opacity(0.72))
            Text(label).font(.system(size: 13.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.asTealText : .white.opacity(0.72))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if let c = count { Text("\(c)").font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4)) }
            if removable { Image(systemName: "minus.circle").font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35)) }
        }
        .padding(.horizontal, 12).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(active ? Color.asTealMid.opacity(0.14) : (hover ? Color.white.opacity(0.06) : .clear)))
        .overlay(active ? RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.asTealMid.opacity(0.30), lineWidth: 1) : nil)
        .contentShape(Rectangle()).onHover { hover = $0 }
    }
}
```

Suggested SF Symbols: Songs `music.note`, Albums `square.grid.2x2`, Artists `person`, Genres `guitars`, playlist `music.note.list`, folder `folder`. Keep the existing selection binding + accessibility labels.

Checklist: matches `png/01-rail.png`; card is content-height (glow visible below it); selecting a section still works; VoiceOver reads rows.

---

## PR-D — song list as a glass card  → `png/02-list-card.png`, `png/03-list-header.png`

**File:** `LibrarySongListView.swift` / `LibraryContentView.swift`.

**What changes:** the plain table becomes the second floating glass card: a header strip, a hairline divider, then the scrolling rows INSIDE the card.

- Card: fills remaining width, `.glassCard(opacity: 0.66)`, `clipped()` so rows scroll within the rounded corners. Unlike the rail, this card DOES fill the available height.
- Header strip (`png/03`): padding 16×20 top / 14 bottom.
  - Left: "Songs" 20pt heavy white; under it `379 songs · 41 hrs 23 min` 11.5pt mono `white 42%` (use real counts).
  - Right: a **filter pill** (230pt, height 30, radius 15, fill `black 26%`, magnifier + "Filter Songs" `white 40%` — this is the real search field) and a **sort pill** ("Sort: Title ↑", the value in `asTealText`, chevron). Both are `black 26%` inset pills.
- Divider: 1px `white 7%`, inset 20 horizontally.
- Row area: `ScrollView` with 6×12 padding.

Row (`png/04`, `png/05`) — a 5-column grid, height 48, corner radius 11, horizontal padding 12:

| col | width | content |
|-----|-------|---------|
| 1 | 34 | mini-equalizer if playing, else track number (11.5pt mono `white 30%`) |
| 2 | flex | title + format tag |
| 3 | 190 | artist (`white 55%`, truncating) |
| 4 | 96 | date added (mono `white 40%`) |
| 5 | 60 | duration (mono `white 40%`, right-aligned) |

- Idle row: transparent; hover `white 5%`.
- **Playing row:** background `asTealMid 12%`, 1px ring `asTealMid 36%`, title `asTealTitle` semibold, and column 1 shows the `MiniEqualizer` (teal `#3FD0BA` bars) which freezes on pause / Reduce Motion. **No artwork thumbnails, no play-triangle in the row** — the number/equalizer column is the only indicator (this was an explicit design decision).
- Format tag: 9pt bold, radius 4. Lossy (MP3): `white 42%` on `white 6%`. Lossless (FLAC/WAV): gold `#CBB26A` on `rgba(203,178,106,.14)`. Playing row: `asTealText` on `asTealMid 18%`.

```swift
struct SongRow: View {
    let track: Track; let index: Int; let isPlaying: Bool; let playing: Bool // playing = engine running
    @State private var hover = false
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if isPlaying { MiniEqualizer(animating: playing) }   // freezes when !playing or Reduce Motion
                else { Text("\(index + 1)").font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3)) }
            }.frame(width: 34)
            HStack(spacing: 9) {
                Text(track.title).font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                    .foregroundStyle(isPlaying ? Color.asTealTitle : .white.opacity(0.9))
                    .lineLimit(1).truncationMode(.tail)
                FormatTag(track.format, playing: isPlaying)
                Spacer(minLength: 0)
            }
            Text(track.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                .lineLimit(1).frame(width: 190, alignment: .leading)
            Text(track.dateAdded).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4)).frame(width: 96, alignment: .leading)
            Text(track.duration).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4)).frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 11).fill(
            isPlaying ? Color.asTealMid.opacity(0.12) : (hover ? Color.white.opacity(0.05) : .clear)))
        .overlay(isPlaying ? RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Color.asTealMid.opacity(0.36), lineWidth: 1) : nil)
        .contentShape(Rectangle()).onHover { hover = $0 }
    }
}
```

Keep existing row interactions (double-click to play, context menu, multi-select, sort/filter). Only the styling changes.

Checklist: matches PNGs; playing row equalizer animates and freezes correctly; NO thumbnails in rows; filter + sort still work; rows scroll within the rounded card.

---

## PR-E — top & bottom bars  → shared with Now Playing

The Library screen must show the SAME glass toolbar (with the tab pill strip, `Library` active) and the SAME glass transport bar as Now Playing. If those are already app-level chrome, this PR is just verifying the Library screen sits between them correctly with no double background. If Library currently draws its own toolbar, delete it and use the shared one. Checklist: toolbar `Library` tab is the active teal capsule; transport bar identical to Now Playing; no seams between bars and the window.

---

## PR-F — states & polish

- **Reduce Motion:** playing-row equalizer freezes (all bars at scaleY 0.34); transport "Enhanced" dot stops pulsing. Verify.
- **Reduce Transparency:** both `GlassCard`s swap material for opaque `Color(white:0.12)`; glow can stay (it's decorative) or be dropped.
- **Empty / loading:** if a folder has no songs, the list card shows a centered muted line (e.g. "No songs in this folder") — don't leave a blank card.
- **Light appearance:** provide light variants of the card tint and text opacities the same way the Now Playing tokens do.

Checklist: all four combinations (motion on/off × transparency on/off) look right in both appearances; strict-gate passes.

---

## Final pass

Open `html/Library - Twin Panels.dc.html` next to the running app at 1440×920 and compare region by region: window+glow → rail → list header → rows → bars. Toggle the mock's **reduceMotion** tweak to confirm the frozen-equalizer state matches the app.
