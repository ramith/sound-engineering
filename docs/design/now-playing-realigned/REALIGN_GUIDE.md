# REALIGN GUIDE — Now Playing, PR by PR

Every PR below has: **(1)** what you will see change, **(2)** which file to edit, **(3)** the exact target values, **(4)** a SwiftUI code sample you can adapt, **(5)** a done-checklist. File paths were correct at commit `82bc287` — if a view moved, search for the type name, don't guess.

Shared tokens — add these to `DesignSystem` first if missing (PR-A):

```swift
// DesignSystem+Realign.swift  (new file, Sources/AdaptiveSound/UI/DesignSystem/)
extension Color {
    static let asTealBright = Color(hex: 0x3FD0BA)
    static let asTealMid    = Color(hex: 0x1FA893)
    static let asTealDeep   = Color(hex: 0x14897A)
    static let asTealText   = Color(hex: 0x6FE0D0)   // teal text on dark
    static let asTealTitle  = Color(hex: 0x7EE8D8)   // playing-row title
    static let asOnTeal     = Color(hex: 0x0C1413)   // dark text on teal fill
    static let asAmber      = Color(hex: 0xF0B429)   // true-peak warning
}
extension LinearGradient {
    static let asTealButton = LinearGradient(
        colors: [.asTealBright, .asTealMid, .asTealDeep],
        startPoint: .top, endPoint: .bottom)
    static let asTealMeter = LinearGradient(
        colors: [.asTealMid, .asTealBright],
        startPoint: .leading, endPoint: .trailing)
}
```

A reusable "styled glass" bar modifier used by PR-B and PR-G (no real blur — a fill plus one light hairline):

```swift
struct StyledGlassBar: ViewModifier {         // top bar: lightFrom = .top
    var lightFrom: UnitPoint = .top           // bottom bar: lightFrom = .bottom
    func body(content: Content) -> some View {
        content
            .background(LinearGradient(
                colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                startPoint: lightFrom,
                endPoint: lightFrom == .top ? .bottom : .top))
            .overlay(Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1),
                     alignment: lightFrom == .top ? .top : .top)
            // the 1px specular line ALWAYS sits on the top edge of the bar
    }
}
```

---

## PR-A — tokens (do this first)

1. Add the extension above. 2. Provide light-mode variants in the asset catalog or via `@Environment(\.colorScheme)` the same way existing tokens do. 3. Nothing visual changes yet. Checklist: builds, strict-gate passes.

---

## PR-B — toolbar tab strip  → `png/01-toolbar.png`

**File:** `Sources/AdaptiveSound/UI/Shell/ChromeBar.swift` (`TabSelectorView`)

**What changes:** the native segmented picker becomes a dark capsule track; the active tab is a glowing teal capsule with dark text; inactive tabs lighten on hover.

Target values:
- Track: height 34, corner radius 17 (capsule), fill `black 38%`, inner shadow (dark, y 1, blur 2), inner padding 3, tab spacing 2.
- Active tab: height 28, capsule, fill teal `#29B6A4` at 94% (or `asTealBright→asTealMid` vertical gradient), text `asOnTeal` bold 12.5pt, glow shadow `asTealMid 50%, radius 8, y 1`, plus a 1px white-30% highlight along its top inside edge.
- Inactive tab: text `white 60%` semibold 12.5pt; on hover fill `white 6%` and text `white 90%`.

```swift
struct TabCapsuleStrip: View {
    @Binding var selection: MainTab
    @State private var hovered: MainTab?
    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                let active = tab == selection
                Text(tab.title)
                    .font(.system(size: 12.5, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? Color.asOnTeal
                                     : Color.white.opacity(hovered == tab ? 0.9 : 0.6))
                    .padding(.horizontal, 15).frame(height: 28)
                    .background {
                        if active {
                            Capsule().fill(LinearGradient.asTealButton)
                                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    .blendMode(.plusLighter).mask(
                                        Capsule().fill(LinearGradient(colors: [.white, .clear],
                                            startPoint: .top, endPoint: .center))))
                                .shadow(color: Color.asTealMid.opacity(0.5), radius: 8, y: 1)
                        } else if hovered == tab {
                            Capsule().fill(Color.white.opacity(0.06))
                        }
                    }
                    .contentShape(Capsule())
                    .onHover { hovered = $0 ? tab : nil }
                    .onTapGesture { selection = tab }
                    .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.38))
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)) // inner-ish shadow ok
    }
}
```

Keep the existing keyboard navigation / accessibility labels from the picker. Animate selection change with `.animation(.snappy(duration: 0.18), value: selection)` — gate with Reduce Motion.

**Also in this PR** (same file, small): device pill — put the `48 kHz` mono readout *inside* the pill after a chevron, capsule radius, fill `white 8%` + top inner highlight `white 10%`; width ~240pt so "MacBook Pro Speakers" doesn't truncate.

Checklist: tabs match `png/01-toolbar.png`; hover works; VoiceOver reads tabs; strict-gate passes.

---

## PR-C — queue header consolidation  → `png/03-queue-header.png`

**Files:** `Sources/AdaptiveSound/UI/Playlist/PlaylistView.swift`, `PlaylistItemRow.swift`

**What changes:** everything above the list collapses into ONE 32pt-tall row, and drag handles become hover-only.

One row, left → right (see the PNG):
1. `QUEUE` — 13pt heavy, letter-spacing wide, `white 92%`.
2. `6 tracks` — 11.5pt mono, `white 40%`.
3. Three 28×28 icon buttons, radius 8, fill `white 6%` (hover `white 10%`): trash, shuffle, repeat. A toggled-on button (e.g. repeat active) uses fill `asTealMid 16%` + 1px ring `asTealMid 30%`, icon `asTealText`.
4. Up Next / Recent segmented pair: small capsule track (`black 35%`, padding 2), selected segment `white 12%` fill + bold `white 92%` text, unselected `white 55%`. 24pt high.
5. Spacer.
6. Filter pill, right-aligned: **190pt wide, 28pt high**, capsule, fill `white 7%`, magnifier icon + placeholder "Filter queue" at `white 40%`. This replaces the current full-width search bar. It is still a real `TextField`.

Delete the old floating "QUEUE / 6 tracks" block, the separately-floating action buttons, and the full-width filter bar.

**Drag handles:** in `PlaylistItemRow`, wrap the `≡` handle in `.opacity(isRowHovered ? 0.45 : 0)` with `.onHover` on the row and a 0.15s ease animation (skip animation under Reduce Motion). Reordering must still work while hidden — hover reveals it.

Checklist: header is a single row matching the PNG; filter still filters; drag-reorder still works; no leftover empty vertical space above the list.

---

## PR-D — playing row  → `png/04-playing-row.png`

**File:** `PlaylistItemRow.swift`

**What changes:** the heavy teal band + ▶ becomes a subtle tinted card, and the track number becomes 3 dancing bars.

Target values for the row whose track is currently playing:
- Fill `asTealMid` at **13%**, corner radius **10**, ring: 1px stroke `asTealMid 38%` (inset).
- Title: `asTealTitle` (#7EE8D8), weight semibold (650), 13.5pt.
- Format badge on this row: text `asTealText`, fill `asTealMid 18%` (other rows keep `white 45%` on `white 6%`).
- Where the number was: three vertical bars, each 2.5pt wide, radius 1, color `asTealBright`, container 12pt tall, 1.5pt gaps. Each bar animates `scaleY` between 0.34 and 1.0 (anchor bottom), ease-in-out, repeat forever, durations 0.8 / 1.05 / 0.9 s with staggered phase.
- The bars go **still (all at scaleY 0.34)** when playback is paused OR Reduce Motion is on. No ▶ triangle anywhere.

```swift
struct MiniEqualizer: View {
    var animating: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            EqBar(duration: 0.80, phase: 0.0, animating: animating)
            EqBar(duration: 1.05, phase: 0.4, animating: animating)
            EqBar(duration: 0.90, phase: 0.7, animating: animating)
        }.frame(width: 10.5, height: 12)
    }
}
// TimelineView(.animation) + sin() — pauses cleanly, respects Reduce Motion:
struct EqBar: View {
    let duration: Double; let phase: Double; let animating: Bool
    var body: some View {
        TimelineView(.animation(paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let s = animating ? 0.34 + 0.66 * (0.5 + 0.5 * sin((t / duration + phase) * 2 * .pi)) : 0.34
            RoundedRectangle(cornerRadius: 1).fill(Color.asTealBright)
                .frame(width: 2.5).scaleEffect(x: 1, y: s, anchor: .bottom)
        }
    }
}
```

Pass `animating: player.isPlaying && !reduceMotion`.

Checklist: matches the PNG; bars stop on pause; row still selectable/tooltipped; other rows unchanged.

---

## PR-E — inspector panel  → `png/05-inspector.png`

**Files:** `NowPlayingInfoView.swift`, `MasterGainSliderView.swift`, `LoudnessMetersView.swift`, container `RightPanelView.swift` / `NowPlayingTabView.swift`

Two independent changes — keep them as two commits inside this PR if easier.

**E1 — floating card.** The panel stops stretching to the window bottom.
- In the container, change the panel's alignment so it hugs content: put it in a `VStack { panel; Spacer(minLength: 0) }` or apply `.frame(maxHeight: .infinity, alignment: .top)` to the *wrapper*, never a fixed height on the panel.
- Panel styling: width 320, corner radius 18, fill dark `rgba(30,32,37)` at ~72% **with real material** (`.ultraThinMaterial` tinted dark, or the repo's existing glass recipe), 1px top inner highlight `white 13%`, hairline ring `white 6%`, drop shadow `black 60%, radius 25, y 18`.
- Behind/below the card: a blurred teal radial glow (`asTealMid 22% → clear`, blur ~18) so the empty area under the card reads intentional. It sits *behind* the card, extends ~20pt past its bottom.

**E2 — loudness meters.** Each of the three rows becomes: label (82pt column) + 4pt meter bar + right-aligned mono value.
- Integrated `−15.9 LUFS` → meter 62% filled, teal gradient.
- Short-term `−24.3 LUFS` → meter 41% filled, teal gradient.
- Peak: **first upgrade the measurement to true peak (4× oversampled inter-sample peak) in the audio engine, THEN rename the label to "True peak"** and show value in dBTP. When value > −1.0 dBTP: the meter's last ~8% and the value text turn `asAmber`. Below that: plain teal.

```swift
struct LoudnessRow: View {
    let label: String; let valueText: String
    let fraction: Double        // 0…1 meter fill
    let hot: Bool               // amber state (true peak only)
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                .frame(width: 82, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(hot
                        ? AnyShapeStyle(LinearGradient(colors: [.asTealBright, .asAmber],
                              startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(LinearGradient.asTealMeter))
                        .frame(width: geo.size.width * fraction)
                }
            }.frame(height: 4)
            Text(valueText).font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(hot ? Color.asAmber : .white.opacity(0.85))
        }
    }
}
```

**Also in this PR** (small, same files): master gain value must be signed (`+4.0 dB`); sliders get the slim custom style — 4pt carved track (`white 13%`), teal gradient fill, 15pt white round knob with drop shadow; headphones hint is the single line "Connect headphones to enable." with the long explanation moved to `.help()`; disabled headphone block at 50% opacity; section dividers are 1px `white 7%`.

Checklist: card height = content height with glow visible below; meters match PNG; amber only when > −1 dBTP; label says "True peak" only after the DSP truly measures it.

---

## PR-F — hero badges  → `png/02-badges.png`

**File:** hero view (evolved from `NowPlayingInfoView` / `NowPlayingWidget`)

Replace the three chips `ENHANCED` `48 kHz` `20 %` with exactly two:

1. **`● ENHANCED · 20%`** — teal chip: text `asTealText` bold 10.5pt letter-spaced, fill `asTealMid 16%`, 1px ring `asTealMid 28%`, radius 9, padding 11×5. The `●` is a 6pt teal dot with a soft teal glow that pulses opacity 1.0 → 0.35, 1.6s ease-in-out, forever (frozen at 1.0 under Reduce Motion). The `20%` is the live intensity value — one string, `ENHANCED · \(intensity)%`.
2. **`MP3 · 48 kHz`** — grey chip, mono font: text `white 60%` bold 10.5pt, fill `white 7%`, 1px ring `white 7%`, radius 9, same padding. `MP3` is the current track's file format (uppercase of the file extension / codec) — this adds the format, which the hero is currently missing. `48 kHz` is the engine sample rate readout already shown elsewhere.

Checklist: exactly two chips, values live-update on track change and intensity change, dot doesn't pulse with Reduce Motion.

---

## PR-G — glass on top + bottom bars  → `png/01-toolbar.png` and `png/06-transport.png`

**Files:** `ChromeBar.swift` (top), `Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift` (bottom)

Apply the `StyledGlassBar` modifier from PR-A. **No real blur** — nothing scrolls behind these bars.
- Top bar: gradient `white 5% → white 2%` top-to-bottom, 1px `white 9%` line on its TOP edge, 1px `black 35%` line on its bottom edge.
- Bottom bar: gradient `white 5% → white 2%` bottom-to-top (light source flipped), 1px `white 9%` line on its TOP edge (the edge that catches light), subtle inner shade below it.
- Bottom bar extras (see `png/06-transport.png`): play button gets an inner top highlight (`white 35%` 1px) + teal glow shadow; scrubber = 4pt track `white 14%`, teal gradient fill, 13pt white knob; right-side readout `● Enhanced · 48 kHz` — dot pulses like the hero badge (same Reduce Motion gate), "Enhanced" in `asTealText`.

Checklist: both bars match PNGs in both appearances; Reduce Transparency swaps any material for an opaque fill; strict-gate passes.

---

## Final pass

Open `html/Now Playing - Realigned Target.dc.html` in a browser next to the running app at 1440×920 and compare region by region (toolbar → hero → queue header → rows → inspector → transport). The mock has two toggles in its Tweaks: **reduceMotion** (what the app must look like with Reduce Motion on) and **peakHot** (amber vs calm true-peak state). The app must be able to show all four combinations.
