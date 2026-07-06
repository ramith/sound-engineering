# AdaptiveSound — Layout Architecture: Implementation Plan

Status: **plan for sign-off** (2026-07-06). Companion to `layout-architecture-design.md` (the *what*); this is the *how*, grounded in web research of Apple/SwiftUI practice + the architect-reviewer + the-fool gate (GO-WITH-CHANGES). Founder chose **full scope** (all 5 tabs + the persistent footer transport, in one effort), built in gated slices L1–L5. Accuracy over speed: every risky mechanism below is tied to a documented API or a verified caveat.

## 1. Research-grounded technique decisions

Each replaces a "we've never actually run this" assumption the gate flagged with a documented macOS-26 API.

| Concern | Decision (documented API) | Source |
|---|---|---|
| Hide native titlebar, keep traffic lights | `.windowStyle(.hiddenTitleBar)` on the `WindowGroup` (removes title + toolbar background + separator; traffic lights stay) | nilcoalescing; HWS |
| Make the window draggable by the chrome band | **`.windowBackgroundDragBehavior(.enabled)`** on the `WindowGroup` — a native scene modifier. **Drop** the design's custom `WindowDragArea` NSView hack | nilcoalescing (macOS 15+) |
| Pin a header AND a footer | Stack `.safeAreaInset(edge: .top)` + `.safeAreaInset(edge: .bottom)` on the content — "you can apply safeAreaInset() multiple times; each takes into account the previous insets" | HWS |
| Kill the Library `NavigationSplitView` sidebar-toggle (R1) | **`.toolbar(removing: .sidebarToggle)`** on the sidebar (documented). Removes the toggle that the architect flagged as unaddressed | donnywals; Apple forums |
| No native title text projecting into the titlebar | Remove all `.navigationTitle` (4 sites); titles → in-content `ScreenHeader`. Optionally `.toolbarVisibility(.hidden, for: .windowToolbar)` as a global backstop | nilcoalescing |
| EQ interactive canvas + short window (R4) | EQ **does not scroll** its canvas. `DragGesture`-inside-`ScrollView` is a confirmed real conflict; instead the canvas **flexes** (`VisualizerSurface` min 220 / ideal 360 / max 460) and fits without scrolling at the 640 window-min | Apple forums; darjeelingsteve |
| "must-use-Screen" auto-enforcement (R2) | **Not buildable** — repo `.semgrep.yml` documents semgrep's Swift AST as unusable; only `pattern-regex` token bans work. Keep 2 negative bans (below); drop the positive rule | repo `.semgrep.yml` |

## 2. The footer decision — `safeAreaInset` (recommended) vs native `tabViewBottomAccessory`

macOS 26 ships `.tabViewBottomAccessory` — Apple's persistent-across-tabs "Now Playing" accessory (Liquid Glass). It IS available on macOS 26.0+. **But it requires the native `TabView`.** This app uses a *custom* top chrome (logo · device menu · segmented 5-tab `Picker`) — adopting native `TabView` would abandon that chrome, which is the founding premise of this whole design.

**Decision: custom `safeAreaInset(edge: .bottom)` footer (`NowPlayingBar`).** Keeps the custom chrome, is proven on macOS, gives full control over the transport bar's look/states. The native accessory is the right idiom *only if* we ever move to native-`TabView` chrome — recorded as the alternative, not chosen now.

## 3. Gate response — the 5 gates, addressed

- **R1 (Library chrome, BLOCKER):** `.toolbar(removing: .sidebarToggle)` on the sidebar + keep it pinned (`columnVisibility = .all`) + remove `.navigationTitle`s + `.toolbarVisibility(.hidden, for: .windowToolbar)` backstop. **Caveat to handle:** with the toggle removed, a user can still drag the split divider to collapse the sidebar and can't get it back → also add a **View ▸ Toggle Sidebar** command via `SidebarCommands()` as the accessible escape hatch. Verified in the L2/L4 make-run.
- **R2 (semgrep):** keep only regex-expressible bans — (a) no `.navigationTitle` under `Sources/AdaptiveSound/UI/`, (b) no window-level `.frame(minWidth:`/`.frame(minHeight:` under `UI/`. Drop the positive "body root must be `Screen`" (enforce by review). Symptoms 1/3/4 are prevented by the mechanism regardless; only symptom 2 (centering) degrades to convention — acceptable.
- **R3 (footer = product change):** full scope is the founder's call, so the footer IS in this effort — but sliced LAST (L3 after the shell), so the 4 bug fixes (L1+L2+L4) are independently shippable/testable before the transport relocation lands.
- **R4 (EQ drag):** EQ non-scrolling (§1). Fallback if the flex still feels cramped at 220: fixed graph region + scrolling controls below. Explicit founder make-run check.
- **R5 (tokens + full-screen):** reconcile token values to the code in L1 (below); add full-screen handling that reclaims the 80pt traffic-light inset when the lights are hidden.

## 4. The slices (each: `swift build` + `swiftlint --strict` + `make gate` + commit; SME review where noted; founder make-run at the milestones)

**L1 — primitives + tokens (additive, no behavior change; independently buildable).**
New under `UI/Shell/`: `AppShell<Header,Content,Footer>` (3-slot, `safeAreaInset` top+bottom), `Screen` (`.stack` = ScrollView+fill+top-align+insets+background; `.fill` = edge-to-edge child), `ScreenHeader` (the only title surface), `VisualizerSurface` (fill-width × aspect|min/ideal/max), `SectionCard`, `Hairline`. Tokens into `DesignSystem.swift` (§5). **No `WindowDragArea`** (native drag instead). Gate: builds in isolation; swiftui-pro review of the container APIs.

**L2 — shell swap (the riskiest slice; de-risk first).**
`ContentView` → `RootView` on `AppShell`; scene gets `.windowStyle(.hiddenTitleBar)` + `.windowBackgroundDragBehavior(.enabled)` + `.windowResizability(.contentMinSize)`; window-min moves into the shell; header = `ChromeBar` (today's `ToolbarView`, height/background lifted to the shell, +80pt traffic-light inset with full-screen reclaim); footer = a **stub** `NowPlayingBar` (empty, reserved height). Fixes bug 1 + bug 3's titlebar globally. **Before committing:** wire the Library tab under the shell and verify (build + founder make-run) that the sidebar toggle is gone, no toolbar band appears, and the sidebar's own Music-Folders footer clears the global footer — the R1 spike, done in-place.

**L3 — footer transport (`NowPlayingBar`).**
Relocate `PlayControlsView` + `TransportScrubberView` from `LeftPanelView` into `NowPlayingBar`; loaded/idle states (height always reserved → no jump); scope its `AudioViewModel` observation tightly (only the playback fields the bar shows, so the ~1s scrubber tick doesn't invalidate other tabs). Now Playing's left panel drops the transport. Gate: swiftui-pro + a check that seek/scrub + space-to-play still work.

**L4 — migrate tabs to `Screen`.**
EQ (non-scrolling flex canvas via `VisualizerSurface` + controls), Settings + Monitoring (`Screen(.stack)`, drop bespoke Spacer/ScrollView), Now Playing (`.fill`, drop `containerRelativeFrame` → `paneMinWidth` + equal priority; left pane a nested `Screen(.stack)`), Library (`.fill`, `.toolbar(removing:.sidebarToggle)`, remove `.navigationTitle`s, in-content `ScreenHeader` + a back control in `AlbumDetailView`). Fixes bug 2 + bug 4. Gate: founder make-run of all 5 tabs incl. EQ drag-vs-flex + Monitoring polling lifecycle (its `.task` start/stop must survive the `Screen` wrapper).

**L5 — enforcement + polish.**
Add the 2 semgrep bans to `.semgrep.yml`; `readableWidth` caps; delete dead `FixedHeaderView`; final make-run tuning (light+dark, full-screen, narrow width).

## 5. Token reconciliation (decide in L1; avoid silent visual drift — R5)
- `chromeHeight`: **keep 60** (current `ToolbarView`), not the design's 56 — no visual shift.
- `footerHeight`: **64** (new; 44 art thumb + padding).
- `windowMinHeight`: **640** (60 + 64 + ≥516 content) — intentional bump from 600.
- `windowMinWidth`: **880** (up from 800 — footer transport + two Now Playing panes at `paneMinWidth 360`).
- `spectrumBandHeight`: **keep 50** (current), not 52. `Artwork.detail`: **keep 148** (current), not 160. `sidebar` min/ideal/max: **keep 170/200/300** (current), not 190/220/300.
- EQ graph: **220 / 360 / 460** (new — replaces fixed 400; the canvas reads size dynamically via `onGeometryChange`, so this is correctness-safe).

## 6. Risk register + founder make-run checklist (offline gating can't cover these)
1. **Library under the shell** — sidebar toggle gone? no toolbar band? Music-Folders footer clears the transport footer? sidebar still reachable (View ▸ Toggle Sidebar)?
2. **Window drag** — does `.windowBackgroundDragBehavior(.enabled)` drag from the chrome band while the device menu + segmented tabs still click? double-click-to-zoom / tiling?
3. **Full-screen** — traffic lights hidden → the 80pt inset reclaimed (no dead space)?
4. **EQ** — drag-to-edit bands works (no scroll fighting); graph usable at the 220 min height?
5. **Footer transport** — controls playback from every tab; seek/scrub correct; space-to-play from EQ/Library; loaded↔idle no layout jump; no perf churn on other tabs.
6. **Now Playing** — panes don't collapse at 880 width; queue list still fills; nothing duplicated vs the footer.
7. **All tabs, light + dark** — tab bar in the identical position; content top-aligned; scroll on short window (Settings/Monitoring) with no clip.
8. **Chrome-fix (interim) silent-truncation check (architect Condition B)** — `AppShell` now hard-bounds + clips the content region (chrome is immovable). Until L4 gives them scroll, the tall `.fill` tabs (**Now Playing + Library**) will silently CLIP their bottom at the 640×880 minimum — verify at min-window that this is only bottom-truncation (chrome always intact) and confirm L4 actually makes them scroll (don't mistake the silent clip for "done"). Chrome-fix also: device pill fixed-width so the tab bar's left edge is invariant to device name; segmented tabs `.fixedSize()`.

## 7. Open decisions for founder
1. **Footer = custom `safeAreaInset` bar** (recommended) vs native `tabViewBottomAccessory` (requires abandoning the custom chrome). *Recommend custom.*
2. **Token reconciliation** per §5 (keep current 60/50/148/170-200-300; bump window to 880×640). *Recommend as listed.*
3. **Sidebar reachability** — with the toggle removed, add **View ▸ Toggle Sidebar** command as the escape hatch. *Recommend yes.*
4. **Slice order** — L1 → L2 (empty footer, bug 1+3) → L4 (bug 2+4) → L3 (footer transport) → L5. Bug fixes land before the transport relocation. *Recommend as listed.*

Sources: [macOS toolbar styles (nilcoalescing)](https://nilcoalescing.com/blog/AGuideToMacOSToolbarStylesInSwiftUI/) · [safeAreaInset (Hacking with Swift)](https://www.hackingwithswift.com/quick-start/swiftui/how-to-inset-the-safe-area-with-custom-content) · [remove sidebarToggle (donnywals)](https://www.donnywals.com/turn-off-sidebar-hiding-on-navigationsplitview-in-swiftui/) · [tabViewBottomAccessory (Apple)](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)) · [DragGesture in ScrollView (darjeelingsteve)](https://darjeelingsteve.com/articles/Preventing-Scroll-Hijacking-by-DragGestureRecognizer-Inside-ScrollView.html)
