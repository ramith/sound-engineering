# S10.4 — macOS system control — design

**Status:** Vetted (architect-reviewer + swift-expert design, both SDK/doc-grounded; Fool frame-pass; founder brainstorm 2026-07-15). Awaiting implementation. Last R1-gating sprint (R1 = S10.1–S10.4).

Media keys + Now Playing / Control Center (MediaPlayer) + a couple of app-wide keyboard shortcuts, plus (folded in per the founder) fixing the on-screen footer/mini-player to show real track metadata via the same resolver.

## 0. Locked decisions (founder brainstorm 2026-07-15)

| # | Decision | Choice |
|---|---|---|
| D1 | New shortcuts | **Stop (⌘.)** + **Jump to Now Playing (⌘0)**. No seek/volume shortcuts (system volume keys own volume; `masterGain` is a distinct DSP gain). |
| D2 | Footer/mini-player metadata | **Fold the fix into S10.4** — reuse the new resolver so `NowPlayingBar`/`NowPlayingWidget` show real artist/album/artwork instead of the hardcoded "Unknown Artist" + placeholder. |
| D3 | Loose (non-library) files | Now Playing shows **title only** (`trackID == nil` → no artist/album/art). |
| D4 | M4A duration | **Two-push** (track-change push may carry duration 0, `refreshDuration` completion re-pushes the real duration) rather than delaying playback. |
| D5 | ⌘←/⌘→ latent bug | **Fix in passing** — add the `keyboardFocus.isTextEntryFocused` guard to Next/Prev (today ⌘← steals "move to line start" while typing). |

## 1. Reality checks (from the research/SDK, not assumptions)
- MediaPlayer (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, `changePlaybackPositionCommand`, `playbackState`) is **macOS 10.12.2+** — the online "iOS/tvOS only" badge is a misread. App targets macOS 14, so **no `@available` guards**.
- **macOS requires `MPNowPlayingInfoCenter.default().playbackState` to be set explicitly** (`.playing`/`.paused`/`.stopped`) — it is NOT inferred (the #1 gotcha for appearing in Control Center + capturing media keys).
- **No entitlement / Info.plist / background-mode change** — verified (no `.entitlements`/sandbox in the repo; `UIBackgroundModes` is iOS-only). `MediaPlayer.framework` auto-links via `import`.
- **Media-key play/pause is best-effort on macOS** (can trigger Music.app; no API to force key ownership). Reliable surfaces: Control Center, the menu-bar Now Playing widget, next/prev. Maximize reliability: register commands at launch, set `playbackState` + fresh `nowPlayingInfo` on first play, enable only handled commands.
- **Metadata gap:** the queue's `AudioFile` carries only title/format/url/duration/`trackID` — artist/album/artworkKey live in `LibraryTrackDisplay`, resolved by id via `store.tracksDisplay(ids:)`. S10.4 builds the first `playing-track → display-metadata` resolver (D2 makes the footer/widget reuse it).

## 2. Architecture
- **`@MainActor final class NowPlayingController`** — a composition-root peer (like `EQViewModel`/`LibraryBrowseModel`), a read-only consumer of `AudioViewModel` + caller of its existing transport verbs. No new playback state, no engine change.
- **Wiring (one-directional, house idiom):** VM exposes `var onNowPlayingRefresh: (() -> Void)?` (mirrors `onEngineReady`/`onError`); the composition root wires `audio.onNowPlayingRefresh = { [weak nowPlaying] in nowPlaying?.scheduleRefresh() }`. The controller holds `weak var audio` to pull snapshot state + call verbs (like `LibraryBrowseModel`). Metadata/artwork resolvers injected as closures over `library.store` (controller stays store-agnostic).
- **Fire the hook from existing funnels:** `selectedTrackIndex.didSet` (already exists) covers track change incl. gapless advance; add `isPlaying.didSet` (covers every play/pause/stop/end-of-queue/device-loss); explicit calls in `seek(to:)` + `refreshDuration` completion. **Never** from the 20 Hz tick.
- **Coalescing:** `scheduleRefresh()` sets a flag + hops one runloop (guarded), so the burst of `didSet`s at a track start collapses into ONE push.

## 3. Sync (event-driven, extrapolated scrubber)
Each coalesced push builds a pure `NowPlayingSnapshot` and writes `nowPlayingInfo` (title/artist/album/duration/elapsed/rate/artwork) **then** `playbackState`. Elapsed comes from `viewModel.playbackPosition` (authoritative on the main actor); the system extrapolates via `elapsed + PlaybackRate(0/1) + wall-clock`.
- Track change → full rebuild (re-resolve metadata + artwork; elapsed 0 or `resumeFrom`).
- Play/pause → rate + elapsed + `playbackState` (no metadata re-resolve).
- Seek → elapsed (re-anchor); rate/state unchanged.
- `refreshDuration` completion → duration only (closes the M4A 0-scrubber flash, D4).
- Stop / end-of-queue → `playbackState = .stopped`, `nowPlayingInfo = nil`.

## 4. Commands
Registered ONCE at launch (never per-track — re-adding stacks duplicate handlers); toggle with `.isEnabled`. Handlers fire off-main → `Task { @MainActor in vm.<verb>() }`, return `.success` synchronously. Keep the target tokens; remove on teardown.

| Command | enabled when | verb | return |
|---|---|---|---|
| togglePlayPause / play | track loaded | `togglePlayPause()` / `play()` | `.success` / `.noSuchContent` |
| pause | `isPlaying` | `pause()` | `.success` |
| nextTrack | `canGoNext` | `nextTrack()` | `.success` / `.noSuchContent` at end |
| previousTrack | `canGoPrevious` | `previousTrack()` | `.success` / `.noSuchContent` |
| changePlaybackPosition | `duration > 0` | `seek(to: event.positionTime)` | `.success` |
| (all others) | disabled | — | — |

`canGoNext`/`canGoPrevious` = new computed props on the VM reusing `computeNextIndex(manualSkip:true)`/`computePreviousIndex` (single source of truth with the verbs). Recomputed per push.

## 5. Artwork
Current `trackID` → resolve `LibraryTrackDisplay` (same `tracksDisplay(ids:)` round-trip as the metadata) → decode via an `ArtworkThumbnailStore` (own instance, 512 px thumb) off-main → `MPMediaItemArtwork(boundsSize:) { _ in image }`. Push text immediately (warm-cache peek if available); apply artwork asynchronously ONLY if the track token still matches (stale-guard). No artwork (`trackID`/`artworkKey` nil or miss) → omit the key. Swift-6: if the request handler is `@Sendable` and can't capture `NSImage`, capture the JPEG `Data` and build `NSImage(data:)` inside the block.

## 6. Footer / mini-player metadata (D2, folded in)
`NowPlayingBar` + `NowPlayingWidget` currently hardcode "Unknown Artist" + a placeholder. Feed them the SAME resolved metadata (artist/album/artwork for the current `trackID`). Simplest: the resolved display metadata for the current track becomes observable VM/controller state the footer reads (exact placement decided at impl — reuse the resolver, don't duplicate it).

## 7. Lifecycle
Register commands + build the controller at launch. First `nowPlayingInfo` push on first `startPlayback`. Persist while playing even when the window closes (`.accessory` menu-bar mode keeps playing). Clear deterministically on quit: `AppDelegate` holds a `weak nowPlaying` and calls a synchronous `clear()` (`nowPlayingInfo = nil`, `playbackState = .stopped`) inside the `applicationShouldTerminate` teardown (don't rely on the coalesced Task before process exit).

## 8. Shortcuts (D1 + D5)
Extend `CommandMenu("Controls")`: **Stop (⌘.)** → `stopPlayback()`; **Jump to Now Playing (⌘0)** → `selectedTab = .nowPlaying`. Both ⌘-combos produce no text → no focus guard needed. **Fix D5:** add `|| keyboardFocus.isTextEntryFocused` to the existing Next (⌘→) / Prev (⌘←) `.disabled` so they don't steal text-navigation while a field is focused.

## 9. Testability + QA

**As-built note (deviation from the pre-impl plan, recorded not excised):** the planned pure
`infoDictionary()` + `RemoteCommandIntent` types were NOT created. The MP dict needs MediaPlayer key
constants, so it can only live in the executable `AdaptiveSound` target — which SPM cannot
`@testable import` (the same constraint that forces every `AudioViewModel` test through a mock
mirror). Extracting them buys no testable surface over the inline code. All *decision-bearing* pure
logic — rate 0/1, artist-omitted-when-empty, album-omitted-when-nil, elapsed/duration passthrough —
is isolated in `NowPlayingSnapshot` (PlaybackQueueKit, library) and IS unit-tested. The remaining
glue (`push()` mapping snapshot→MP keys 1:1; the command→verb table; `updateCommandEnablement`;
`canGoNext`/`canGoPrevious` `!= nil` wrappers over the already-tested `computeNext/PreviousIndex`)
is thin and its correctness is a manual-verify concern (does Control Center render / drive).

- **Pure (`swift test`):** `NowPlayingSnapshot` — rate 0/1 by state, artist omitted when empty,
  album omitted when nil/empty, title/duration/elapsed/artworkKey/token passthrough (NP-01..04).
- **VerifyLibraryStore:** none new (only reads the already-gated `tracksDisplay(ids:)`).
- **Manual / by-ear (founder):** appears in Control Center + the menu-bar Now Playing widget; media
  keys (F7/F8/F9) + Control Center buttons + scrubber drive playback; artwork + title/artist/album
  render; scrubber tracks smoothly (extrapolation) + re-anchors on seek; the footer/mini-player now
  show real metadata; behavior while menu-bar-only (`.accessory`). **The system-integration itself
  is manual-verify — no headless test proves "appears in Control Center".** A qa-expert + Fool
  break-it runs on the impl.

## 10. Files (as built)
New: `Sources/AdaptiveSound/NowPlayingController.swift` (`@Observable @MainActor` impure shell — also
the single resolved-metadata source the footer/widget read, D2); `Sources/PlaybackQueueKit/NowPlayingSnapshot.swift`
(pure) + `NowPlayingSnapshotTests.swift`. Edit: `AudioViewModel.swift` (`onNowPlayingRefresh`,
`isPlaying.didSet`, `selectedTrackIndex.didSet` fire, `canGoNext`/`canGoPrevious`),
`AudioViewModel+Playback.swift` (fire in `seek`/`refreshDuration`), `AdaptiveSound.swift` (own+wire
controller as Edge 4; inject into environment; extend Controls menu with Stop ⌘. + Jump ⌘0; D5
guard on ⌘←/⌘→), `AppDelegate.swift` (weak controller + `clear()`), `NowPlayingBar.swift` +
`NowPlayingWidget.swift` (real artist + artwork via the controller's token-guarded accessors, D2).
