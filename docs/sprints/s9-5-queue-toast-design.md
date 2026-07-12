# S9.5 — Queue toast + truthful counts (design)

Status: **✅ SHIPPED (S9.5) — design record.** Companion to [s9-5-songs-search-design.md](s9-5-songs-search-design.md) §10.4 (the locked UX spec), decision #4 (visibility-gated toast) + OD-2 (truthful post-dedup count), and its [test plan](s9-5-songs-search-test-plan.md) §2.2 (TOAST-1/2/3, VM-Q-13/14/15).

## 1. What this is

Adds from the Library (Songs context menu → **Play Next** / **Add to Queue**) are currently **silent** — no confirmation the track landed. This ships the specced **bottom-center capsule toast** confirming the add, with a **truthful count** (actually-added, post-dedup), **gated** so it never shows on the Now Playing tab (whose right panel already *is* the queue). It's mostly UI + a tiny return-value change to two shipped queue verbs — but those verbs are gated behavior, so the change is regression-guarded.

## 2. Scope

**IN:** `playNext`/`appendToQueue` → `@discardableResult -> Int` (post-dedup added count); **all four `LibraryBrowseModel` queue-add forwarders fire the toast — the song `playNext`/`append` AND the album `playAlbumNext`/`appendAlbum`** (review swiftui #6 / arch #4: the album adds are on the same model and are the case most likely to want confirmation); toast state on the model; the `QueueToast` capsule (shell overlay, visibility-gated, coalesced, tappable → Now Playing, reduce-motion, VoiceOver); pure `QueueToastDecision` + tests.

**OUT:** Play Now / `playTrackNextNow` stay silent + `Void` (immediate playback, not a queue add). EQ/Settings queue-add sources (none exist yet → model-ownership over a global toast service is YAGNI-correct, arch #4). Customizable-columns UI, artwork column, A–Z rail, full a11y pass (separate S9.5 follow-ups). The S10 per-entry-id wrapper / intentional dups.

## 3. Behavior spec (from §10.4)

- **Fires on:** Play Next, Add to Queue. **Silent:** Play Now, `playTrackNextNow` (single-click play-now-jump).
- **Visibility gate:** render only when `viewModel.selectedTab != .nowPlaying`.
- **Copy (count = actually-added, OD-2):**
  - Add to Queue: N≥2 "Added N to Queue" · N==1 "Added to Queue" · N==0 "Already in Queue".
  - Play Next: N≥2 "Added N to Play Next" · N==1 "Playing Next" · N==0 "Already in Queue".
- **Coalescing:** multi-select → ONE toast (true count); a new add within the ~2 s window **replaces text + resets the timer** (never stacks).
- **Placement/style:** `.overlay(alignment: .bottom)` sibling of `ErrorBanner` on `TabContentView`; bottom-center, `.padding(.bottom, 16)` (floats above the footer). Style = the `EQRecallBanner` capsule exactly (`.ultraThinMaterial` in `.capsule` + `hairline` stroke; icon `accent`, text `Font.callout`/`label`, trailing `chevron.forward`/`labelTertiary`).
- **Tappable:** the whole capsule is a `Button` → `viewModel.selectedTab = .nowPlaying` (doorway; `.link` pointer).
- **Motion:** `.move(edge: .bottom) + .opacity`, `.easeInOut(0.25)`; **reduce-motion → `.opacity` only**; ~2.0 s auto-dismiss.
- **VoiceOver:** one `.isButton` element (label = message, hint "Opens Now Playing") + `AccessibilityNotification.Announcement(message)` on appear.

## 4. Backend — truthful count (OD-2)

`playNext`/`appendToQueue` in `AudioViewModel+Queue.swift` **already** call `dedupedAgainstQueue(_:)`, so the added count is the post-dedup `tracks.count`. Change both to `@discardableResult -> Int`:
- `appendToQueue`: `let tracks = dedupedAgainstQueue(tracks); guard !tracks.isEmpty else { return 0 }; …; return tracks.count`.
- `playNext`: empty → `0`; the no-current branch **returns `appendToQueue(tracks)`** (its count); else insert + arm, `return tracks.count`.
- `playNow`, `playTrackNextNow`, `armOnDeck`, `dedupedAgainstQueue` **unchanged**.

**Regression contract (refactoring-specialist checks this):** the change is return-value-only — the array mutation, `armOnDeck`, `QueueAdvance.appendArmIndex`, and on-deck/shuffle sequencing are byte-for-byte unchanged. The 25 auto-advance + VM-Q mock tests must stay green; `MockAdvanceController`'s `playNext`/`appendToQueue` mirror gains the `-> Int` for the VM-Q-13/14/15 count assertions.

## 5. Model deltas (`LibraryBrowseModel`) — revised per review

- **Toast state:** `private(set) var queueToast: QueueToastState?` where **`QueueToastState` is a real `Equatable, Sendable` struct `{ message: String; token: Int }`** — NOT a tuple typealias (tuples aren't `Equatable`, which would break `.onChange`/`.animation(value:)`; swiftui #4). The `token` is a monotonic key used by the VIEW as the **announce + animation trigger** so a coalesced replace with an *identical* string still re-announces/re-renders (swiftui #1/#5). *(There is no `@Observable` self-assign trap here — `queueToast` has no `didSet`; the token's job is the announce/anim key, not recursion avoidance.)*
- **Single cancellable dismiss task (NOT spawn-per-token):** hold `private var dismissTask: Task<Void, Never>?`; each raise does `dismissTask?.cancel()` then respawns. The task **re-checks cancellation after the sleep** — `try? await Task.sleep` swallows cancellation, so without the guard a coalesced replace's old task would clear the NEW toast (swiftui #3, the `EQTabView` anti-pattern):
  ```swift
  dismissTask?.cancel()
  dismissTask = Task { try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return }; queueToast = nil }
  ```
  The unstructured `Task` inherits the model's `@MainActor`, so `queueToast = nil` is race-free (Swift 6). The model is app-lifetime, so nothing is abandoned mid-window.
- **`dismissQueueToast()`** (NEW): nils `queueToast` + cancels `dismissTask`. Called on tap-through and on entering Now Playing — the render gate alone lets a stale toast **reappear** if the user returns to a gated tab within the ~2 s window (swiftui #2).
- **All four add-forwarders return the count + raise the toast** (arch #4): `playNext(_:) -> Int`, `append(_:) -> Int`, **`playAlbumNext(_:) async -> Int`, `appendAlbum(_:) async -> Int`** — each calls its audio verb, gets `added`, then `showQueueToast(.playNext/.addToQueue, added: added)`.
- **`showQueueToast(verb:added:)`**: `QueueToastDecision.message(verb:addedCount:isNowPlayingTab: audio.selectedTab == .nowPlaying)`; if non-nil, set `queueToast = QueueToastState(message:, token: bump())` and (re)arm the dismiss task.
- **Play Now / play-now-jump forwarders unchanged** (silent, `Void`).

## 6. View — `QueueToast` (revised per review)

- New `UI/Shell/QueueToast.swift`: reads `LibraryBrowseModel.queueToast`; renders the `EQRecallBanner`-style capsule when non-nil **and** `viewModel.selectedTab != .nowPlaying`. Mounted in `ContentView` as `TabContentView(...).overlay(alignment: .bottom) { QueueToast() }` beside the existing top `ErrorBanner`.
- **Announce keyed on the token, not `.onAppear`** (swiftui #1): the host stays mounted across a coalesced replace, so mirror `ErrorBanner`'s persistent-host pattern — `.onChange(of: queueToast?.token) { announce($0…message) }` + an `.onAppear` to catch an already-set-at-mount toast. `.onAppear` alone would announce only once (and `.onChange(of: message)` would drop a repeat of an identical string).
- **Idle host must be hit-transparent** (swiftui #8): `.allowsHitTesting(queueToast != nil && viewModel.selectedTab != .nowPlaying)`, else the bottom overlay swallows clicks to the Songs table's bottom rows when idle. (It sits at the *content region's* bottom, above the footer band — no transport-control conflict.)
- **Tap:** `.buttonStyle(.plain)` + `.contentShape(Capsule())` + `.pointerStyle(.link)`; action = `viewModel.selectedTab = .nowPlaying` **and `library.dismissQueueToast()`** (swiftui #2 — clear state, don't rely on the gate).
- **Split triggers** (swiftui #10): animate off `.animation(reduceMotion ? nil : .easeInOut(0.25), value: queueToast != nil)` (a text swap shouldn't animate the capsule out/in); announce off the token (above). Reduce-motion → opacity only, matching `ErrorBanner`.
- **Tokens** (swiftui #7): `DesignSystem.Spacing.medium` (16) not a raw literal; `DesignSystem.Color.accent/.label/.hairline` (ErrorBanner's references), not `EQRecallBanner`'s legacy `Color.asAccent`/`.asHairline` aliases.
- **VoiceOver:** `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(message)` + `.accessibilityHint("Opens Now Playing")` (Button supplies `.isButton`); `AccessibilityNotification.Announcement(message).post()`.

## 7. QA (folded into the loop — qa-expert authors the test hooks)

**Pure, unit-tested in `LibraryBrowseKit`** — `QueueToastDecision.message(verb:addedCount:isNowPlayingTab:) -> String?`:
- **TOAST-1:** `.playNow` → nil (silent); `.playNext`/`.addToQueue` → message; copy matches the 0/1/N buckets for both verbs.
- **TOAST-2:** `isNowPlayingTab == true` → nil (visibility gate), for every verb.
- **Count buckets:** 0 → "Already in Queue"; 1 → "Added to Queue" / "Playing Next"; N → "Added N to …".

**`swift test` on the mock** — truthful count (`AudioViewModelTests`):
- **VM-Q-13:** `playNext`/`appendToQueue` return the **post-dedup** count (2 new + 1 dup on a 3-track queue ⇒ 2).
- **VM-Q-14:** all-dup ⇒ 0; empty input ⇒ 0.
- **VM-Q-15:** multi-select add ⇒ one coalesced result carrying the true count.

**MANUAL (`make run`):** the ~2 s wall timer, motion/reduce-motion, bottom-center placement above the footer, tap-to-Now-Playing, silent-on-Now-Playing, coalesce-resets-timer, VoiceOver announce. (Wall-clock/motion/feel aren't headlessly automatable — the honest line from the test plan.)

## 8. Regression guard (refactoring-specialist)

Because §4 edits shipped, gated queue verbs, refactoring-specialist reviews the diff for **behavior preservation**: the `-> Int` change adds no control-flow branch that alters insertion/arming; `playNext`'s no-current delegation still appends identically; the mock mirror's return value matches the real verb; the 25 auto-advance + VM-Q suites stay green. Any divergence is a blocker.

## 9. Open questions (confirm at manual-review)

1. **Album adds toast too?** Reviews recommend **YES** — `playAlbumNext`/`appendAlbum` are on the same model and "Add whole album to Queue" is the case most likely to want confirmation. *(Recommended: yes, in scope now.)*
2. **`playTrackNextNow` toast?** *(Recommended: silent — immediate play-now-jump, not a queue add; matches Play Now = silent.)*
3. **Copy** — adopt §10.4's strings verbatim? *(Recommended: yes.)*

*(Toast-state-home is resolved: `LibraryBrowseModel`, wiring all its own add paths — arch #4. Not a global service.)*

## 10. Expert-review log (2026-07-09)

**swiftui-pro — GO-WITH-CHANGES.** Endorsed the architecture (pure `QueueToastDecision`, model-owned timing, `ErrorBanner`-style shell overlay; better than the `EQTabView` precedent). Required (all folded into §5/§6): **#1** announce on the **token** via `.onChange` (persistent host), not `.onAppear` (won't re-fire on a coalesced replace with an identical string); **#2** `dismissQueueToast()` on tap/navigate-away (render gate alone lets a stale toast reappear on return within the window); **#3** single cancellable dismiss `Task` with a post-sleep `!Task.isCancelled` guard (`try?` swallows cancellation → the `EQTabView` bug); **#4** `QueueToastState` must be an `Equatable` struct, not a tuple; **#5** correct the token rationale (no `@Observable` didSet trap here); **#6** album adds were silently exempt. Nits: **#7** `DesignSystem` tokens not raw literals; **#8** `.allowsHitTesting` gate on the idle host; **#9** `.buttonStyle(.plain)`/`.contentShape`/`.pointerStyle(.link)`; **#10** split animation vs announce triggers.

**architecture (inline) — GO-WITH-CHANGES.** `-> Int` count is correct for both verbs incl. `playNext`'s no-current double-dedup delegation (idempotent, count preserved); change is return-value-only (low regression, mock mirrors dedup faithfully → mirror `-> Int`); `QueueToastDecision` belongs in `LibraryBrowseKit` (clean boundary); **the album gap (swiftui #6) resolves toward model-ownership — wire `playAlbumNext`/`appendAlbum` through the same `showQueueToast`, NOT a global service (YAGNI)**; `audio.selectedTab` read at fire-time is fine (model already holds `audio`); testability gap — the mock can't prove the REAL `-> Int` (executable-not-importable), covered by code-review + refactoring-specialist + make-run-visible count.

**QA (inline) — test plan.** Automatable: `QueueToastDecision` TOAST-1/2 + count-buckets (`LibraryBrowseKitTests`); VM-Q-13/14/15 truthful count on the mock (`AudioViewModelTests`). Manual (`make run`): ~2 s timer, motion/reduce-motion, placement, silent-on-Now-Playing, coalesce-resets-timer, **tap→Now-Playing + no-reappear-on-return**, **VoiceOver announce on a coalesced replace**, album-add toasts. Regression: auto-advance ×25 + VM-Q green; golden master byte-identical (no DSP); `make strict-gate`. DoD = those gates green + the make-run checklist ticked.

**Consolidated must-fix before implement:** the four swiftui HIGH/MED (#1–#4), the album-forwarder wiring (arch #4 / swiftui #6), and the refactoring-specialist regression pass on the `-> Int` verbs. All are reflected in §2/§4/§5/§6 above; the LOW nits (#7–#10) are implementer-applied.
