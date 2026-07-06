# AdaptiveSound — Layout Architecture (clean-slate design)

Status: **vetted design, awaiting founder sign-off** (fresh-look panel: ui-designer composition + swiftui-pro mechanics, 2026-07-06). Triggered by the founder's judgment that a cluster of make-run layout bugs were symptoms of **no coherent layout system**. This designs the *system*; implementation follows in gated slices (§8) after sign-off.

## 1. Problem — why the bugs kept coming

Four make-run symptoms, one root cause: **no owner of the window's vertical axis, and no shared "fill the region" contract.**
1. Shrink the window → the top tab bar clips off (chrome + content share one `VStack` that centers on overflow).
2. EQ content floats mid-window (EQ has no vertical fill; other tabs happen to fill).
3. Library shows a second, native macOS titlebar (its `NavigationSplitView` + `.navigationTitle` project into the window titlebar the app never owned).
4. Settings would clip its lower sections on a short window (stacked content, no scroll).

Patching the four instances leaves the next tab free to reintroduce the class. This design removes the class **structurally**.

## 2. The three container primitives (the whole system)

Everything routes through three containers under `UI/Shell/` + layout tokens. A tab's only freedoms are *mode*, *edge-to-edge*, and *content* — none can reintroduce §1.

### `AppShell<Header, Content, Footer>` — owns the vertical axis
A **three-slot canvas**: a pinned **header**, a flexible **content** region, a pinned **footer** — the header/footer reserved via `.safeAreaInset` (top/bottom), so they can never be clipped, centered, or pushed off, and content lays out *between* them.

```swift
struct AppShell<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)     // content owns the flexible region
            .safeAreaInset(edge: .top, spacing: 0) {              // header: pinned + reserved + un-clippable
                header().frame(height: ShellMetrics.chromeHeight).frame(maxWidth: .infinity)
                    .background(WindowDragArea()).background(DesignSystem.Color.window)
                    .overlay(alignment: .bottom) { Hairline() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {           // footer: pinned + reserved + un-clippable
                footer().frame(height: ShellMetrics.footerHeight).frame(maxWidth: .infinity)
                    .background(DesignSystem.Color.panel).overlay(alignment: .top) { Hairline() }
            }
            .background(DesignSystem.Color.window)
            .frame(minWidth: ShellMetrics.windowMinWidth, minHeight: ShellMetrics.windowMinHeight)
            .toolbar(.hidden, for: .windowToolbar)                // no tab can project chrome into the titlebar
    }
}
```
Scene: `WindowGroup { RootView() }.windowStyle(.hiddenTitleBar).windowResizability(.contentMinSize)` — the app **owns its chrome**; native traffic lights stay (float top-left; the header reserves `trafficLightInset ≈ 80pt` so the logo clears them). The header band is the window-drag handle (`WindowDragArea`, a tiny `mouseDownCanMoveWindow` NSView); the footer is **not** draggable (it's interactive transport). `ContentView` → `RootView` supplies the three slots (header = `ChromeBar` = today's `ToolbarView` re-inset; footer = `NowPlayingBar`, §4).

### `Screen` — the fill/scroll/inset/background contract
The **only** sanctioned way to occupy the content region. Always fills + top-aligns + paints the background. Two modes:
- `.stack` — vertical section stack, standard insets, **scrolls on overflow / fills on underflow** (EQ, Settings, Monitoring).
- `.fill` — hands the child the whole region edge-to-edge; the child owns its own scrolling/panes (Now Playing, Library).

`.stack` wraps content in a `ScrollView`; `readableWidth: true` caps form-like screens at `Layout.readableMaxWidth`. Rule table: fill width always; fill height + **top-align** (never center); overflow scrolls (`.stack`) or child-owned (`.fill`); background `window`; **never `.navigationTitle`** (titles live in an in-content `ScreenHeader`); screens never set window-level frames.

### `VisualizerSurface` — the drawing-surface contract
Kills the magic pixel heights (EQ `400`, spectrum `50`, artwork `168`, channel row `72`). Each drawing surface (EQ graph, spectrum, artwork) is **fill-width × (aspect-ratio OR min/ideal/max height)**, tokenized. The Canvas draws to the size it's given; the *slot* decides the size.

## 3. Layout tokens (add to `DesignSystem.swift`)
`ShellMetrics` (chromeHeight 56, footerHeight 64, trafficLightInset 80, windowMinWidth 880, windowMinHeight 640, hairline 0.5) · `Layout` (screenInsetH 20, screenInsetV 16, sectionGap 20, readableMaxWidth 720, sidebarMin/Ideal/Max 190/220/300, paneMinWidth 360) · `Visualizer` (responseGraph min/ideal/max 220/360/460, spectrumBandHeight 52, channelRowHeight 72) · `Artwork` (thumb 44, cell 168, detail 160).

New components under `UI/Shell/`: `AppShell`, `Screen`, `ScreenHeader` (the only sanctioned title surface), `VisualizerSurface`, `SectionCard` (dedupes card+clip+hairline), `NowPlayingBar` (§4), `WindowDragArea`, `Hairline`.

## 4. The footer — `NowPlayingBar` (persistent transport)
A **persistent compact transport bar on every tab** (Apple Music / Spotify pattern) — the founder's header/footer requirement. Row: `[art thumb] · [title/artist, 2 lines] —flex— [prev · play-pause · next] —flex— [elapsed · scrubber · remaining]`.

**Always present; height always reserved; content has two states** (so play/stop never resizes the content region → no layout jump):
- **Loaded** (`selectedTrackIndex != nil`): the full transport row.
- **Idle**: muted placeholder + "Nothing playing", disabled controls, a low-key "Browse Library" button (→ `selectedTab = .library`).

`TransportScrubberView` + `PlayControlsView` **relocate** from `UI/NowPlaying/` into `NowPlayingBar` (one home each, not rewritten). **Scan-status stays in the Library sidebar** — footer = transport only; header = identity/nav/global status (a global scanning hint, if ever wanted, goes in the header near the tabs, not the footer).

## 5. Per-tab re-composition
Footer is shell-level (identical on all five tabs). Each tab body root becomes a `Screen`:

| Tab | Screen mode | Content |
|---|---|---|
| **Now Playing** | `.fill, edgeToEdge` | **Left** (`Screen(.stack)`, scrolls): hero art + **full metadata** · spectrum (`VisualizerSurface`) · loudness · master gain · intensity · headphones. **Right:** queue `List`. **No transport/scrubber** (footer owns it). Drop `containerRelativeFrame`; use `paneMinWidth` + equal priority so panes can't collapse. |
| **Library** | `.fill, edgeToEdge` | Keep `NavigationSplitView`, sidebar pinned (`.all`), **remove every `.navigationTitle`**; titles move in-content (`ScreenHeader` on the grid; existing header on detail + an in-content **back** control via `dismiss`/`path`). Zero window-titlebar footprint. |
| **EQ** | `.stack, readableWidth` | `VisualizerSurface(min 220 / ideal 360 / max 460){ FrequencyResponseCanvas }` + `EQControlsSection`; recall banner = `.overlay(alignment:.bottom)`. Drop the fixed 400 + ad-hoc VStack. |
| **Monitoring** | `.stack` | Header + channel rows; **drop the bespoke `ScrollView`** (`.stack` provides it). |
| **Settings** | `.stack, readableWidth` | Sections in `SectionCard`; **remove the trailing `Spacer` + top-aligned frame** (`Screen` fills + scrolls). |

**Duplication ledger (Now Playing vs footer):** only track *identity* overlaps, deliberately at two fidelities — footer = glanceable (thumb + title/artist), tab = full metadata (album, year, format, signal path, hero art). Everything else has one home.

## 6. Why this prevents the whole class
| Symptom | Structural rule that makes it unreachable |
|---|---|
| 1 — toolbar clips on shrink | Header reserved via `.safeAreaInset(edge:.top)`; content owns the flexible axis + clips/scrolls internally. No shared stack to overflow-center. |
| 2 — EQ floats mid-window | `Screen` **always** applies `.frame(maxHeight:.infinity, alignment:.top)`. Centering is impossible for any tab. |
| 3 — Library second titlebar | `AppShell` owns the window (`.hiddenTitleBar`) + hides the window toolbar globally; `Screen` forbids `.navigationTitle`. Nothing can project into the titlebar. |
| 4 — Settings clips | `Screen(.stack)` wraps stacked content in a `ScrollView` (scroll on overflow, fill on underflow). |
| (bottom edge) | Footer pinned via `.safeAreaInset(edge:.bottom)` — mirror of the header; unconditional height reservation → no jump on play/stop. |

**Enforcement:** a semgrep rule (repo already runs semgrep in the strict gate) — a tab-set type's body root must be `Screen(...)`; no view under `UI/` may call `.navigationTitle` or set window-level `.frame(minHeight:600)`. "Forgot `Screen`" fails the gate.

## 7. Key insight from the tactical pass (swiftui-pro)
Pinning the chrome is **necessary but not sufficient** for symptom 1: a tall tab (EQ's ~760 intrinsic) re-inflates a plain `maxHeight:.infinity` slot and re-clips. **Tall tabs must be genuinely collapsible (`ScrollView`)** so the window min (640) is honored and short windows scroll instead of clip. That's why `Screen(.stack)` wraps a `ScrollView` — the design bakes it in.

## 8. Implementation slices (each: build + swiftlint + make gate + commit; founder make-run at the end)
- **L1 — primitives + tokens (no behavior change):** add `ShellMetrics`/`Layout`/`Visualizer`/`Artwork` tokens + the `UI/Shell/` containers (`AppShell`, `Screen`, `ScreenHeader`, `VisualizerSurface`, `SectionCard`, `WindowDragArea`, `Hairline`). Unit-buildable in isolation.
- **L2 — shell swap:** `ContentView` → `RootView` on `AppShell` (header = `ChromeBar`, footer = a *stub* `NowPlayingBar`), `.hiddenTitleBar`, window min in the shell, `.toolbar(.hidden, for:.windowToolbar)`. Fixes bugs 1 + 3's titlebar globally.
- **L3 — footer transport:** build `NowPlayingBar` (relocate `PlayControlsView` + `TransportScrubberView`), loaded/idle states. Now Playing left panel drops the transport.
- **L4 — migrate tabs to `Screen`:** EQ, Settings, Monitoring (`.stack`), Now Playing + Library (`.fill`); remove `.navigationTitle`s + add Library in-content back; adopt `VisualizerSurface` on the EQ graph / spectrum / artwork. Fixes bugs 2 + 4.
- **L5 — enforcement + polish:** semgrep rule; readable-width caps; make-run tuning.

## 9. Open decisions for founder sign-off
1. **Own the window chrome (`.hiddenTitleBar`, traffic lights over the band)** vs keep the native titlebar and only suppress Library's nav. *Recommend: own it* (single consistent chrome; structurally kills the Library leak).
2. **Persistent footer transport bar** (relocates Now Playing's transport). *Recommend: adopt* (it's the header/footer requirement; playback controllable from every tab).
3. **Now Playing keeps full metadata in-tab** (identity shown at two fidelities) vs minimize to avoid any repetition. *Recommend: keep full metadata.*
4. **Window min 880×640** (up from 800×600, to fit header 56 + footer 64 + content ≥520). *Recommend: accept.*
5. **Implement as slices L1–L5** (each gated + committed) vs one big change. *Recommend: slices.*
