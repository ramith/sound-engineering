# Music Folders footer — inline accordion (design)

Status: **UI designed** (ui-designer, 2026-07-08). Small, well-scoped sidebar-component change — no new state beyond one persisted bool, no model deltas, no Swift written here. Grounded on the current `LibrarySidebar`/`MusicFoldersView` code and the `macos-design` HIG skill.

## 0. Founder request (verbatim)

"I would like this music folder display to be a foldable accordion" — clarified: "(I can expand collapse in place)." Replace the `.popover` overlay entirely with an **inline** expand/collapse in the sidebar footer: clicking "Music Folders" reveals the folder list right there, growing within the footer, not as a floating card on top of the sidebar.

## 1. Problem

Today, "Music Folders" opens a `.popover` — a detached, 340pt-wide floating card that overlaps whatever sits to the sidebar's right and vanishes on outside click. The founder wants the list to live in place: expand downward inside the sidebar itself, like a native outline-view disclosure (Mail's mailbox groups, Finder's sidebar sections), so managing folders never feels like a separate overlay.

## 2. Before → after

**Before** (`.popover`, detached overlay):
```
┌─ Library sidebar ──────────┐
│  ♪  Songs                  │
│  ◆  Albums                 │
│  ◇  Artists                │
│  ▤  Genres                 │
│  ▦  Years                  │
│                             │  ← List scrolls; footer is pinned below
│┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│  (scan-status row, optional)
│ 🗀 Music Folders       ﹢  │  ← footer, pinned, unchanged on click
└─────────────────────────────┘
              │ click "Music Folders"
              ▼
        ┌───────────────────────────────┐
        │ Music Folders                 │  ← FLOATS above/beside the
        │ 🗀 ~/Music                 ⊖ │    sidebar column; can overlap
        │ 🗀 ~/Downloads/DJ Sets     ⊖ │    content to its right;
        │ 🗀 ~/Backup (Scanning…)    ⊖ │    dismisses on outside click
        └───────────────────────────────┘
```

**After** (inline accordion, same column, no overlay):
```
┌─ Library sidebar ──────────┐
│  ♪  Songs                  │
│  ◆  Albums                 │
│  ◇  Artists                │
│  ▤  Genres                 │
│  ▦  Years                  │
│                             │  ← List still scrolls; visually shares
│┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│    space with the accordion below
│ ﹀ 🗀 Music Folders     ﹢  │  ← trigger row (chevron rotated open)
│┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│
│    🗀 ~/Music             ⊖│  ← expanded content, INLINE, same
│    🗀 ~/Downloads/DJ Sets ⊖│    width as the sidebar column
│    🗀 ~/Backup (Scanning…)⊖│    (clamped height, scrolls past ~5–6)
└─────────────────────────────┘
   collapsed again: ﹀ rotates back to ﹁, content disappears, no overlay ever existed
```

## 3. Trigger + disclosure indicator

**Recommendation: a custom chevron + `Button`, not the bare SwiftUI `DisclosureGroup`.** See Fork 1 (§12) for the reasoning; the short version is that the trigger row must keep the trailing "+" button as an independent sibling control, and composing that around `DisclosureGroup`'s built-in label/disclosure hit-target is more fragile than owning the row directly.

- **Symbol**: `chevron.forward` (not `chevron.right` — `.forward` auto-mirrors under RTL locales, matching how the real NSOutlineView disclosure triangle also flips).
- **Placement**: leading, before the folder glyph — `[chevron] [folder icon] Music Folders`. This is the native outline-view order (Mail's mailbox list: triangle → folder icon → name), and it reads as "this row has children," which the plain folder-icon-only trigger today doesn't communicate.
- **Rotation**: `.rotationEffect(.degrees(isExpanded ? 90 : 0))` — points forward when collapsed, rotates to point down when expanded. Standard SwiftUI hand-rolled disclosure idiom (also what `DisclosureGroup` itself renders as on iOS).
- **Hit target / keyboard**: the whole chevron+icon+label cluster is one `Button` (not a bare `.onTapGesture`) so Space/Return-to-activate and the VoiceOver button trait come for free — same reasoning the codebase already applies everywhere else a tap needs full accessibility for free.
- **"+" stays a separate sibling `Button`** in the same `HStack`, trailing — unaffected by whichever way the trigger is implemented. See §6 for its recommended position (unchanged from today).

## 4. Expanded content

The expanded region reuses `MusicFoldersView`'s existing content essentially verbatim, relocated from `.popover` payload to inline content below the trigger row, with two trims:

- **Drop the internal "Music Folders" section title.** The trigger row directly above already carries that label — repeating it inside the expanded body is redundant now that there's no popover chrome separating the two.
- **Drop `.frame(width: 340)`.** The content now spans the sidebar column's own width (matching the trigger row and the rest of the footer) instead of a popover's fixed card width.

Everything else is unchanged: folder icon + middle-truncated path + optional "Scanning…" secondary line + per-row remove button, hairline between rows.

**Height: keep the existing clamp, don't remove it.** The footer is a `.safeAreaInset(edge: .bottom)` sitting above the scrolling category `List`; growing the inset's height doesn't shrink the `List`'s own layout logic, but both share the same finite sidebar column height (bounded by the window). At the 640pt window-height minimum, the sidebar column has maybe ~500pt total to split between five short category rows and the footer. A library with a dozen folders, rendered at full unclamped height (12 rows × ~44–52pt ≈ 550–650pt), could squeeze the category list to near-nothing. Recommend carrying the popover's already-tuned `maxHeight: 280` forward unchanged, wrapping the folder rows in the same internal `ScrollView`: with few folders the region hugs its natural (shorter) height, and past ~5–6 folders it clamps and scrolls internally — identical behavior to today, just relocated. (This is the same lesson as the EQ controls redesign's §11.3 addendum: don't rely on "the common case fits," keep a structural backstop for the case that doesn't.)

No extra indentation for the folder rows under the trigger: although outline-view convention often nests children further right, the sidebar is only `LayoutMetrics.sidebarIdeal` (200pt) wide, and that headroom is already spent on middle-truncated paths plus a remove button. Keep the same horizontal padding the rows use today (`Spacing.medium`) rather than compounding it with a nested indent.

## 5. Animation

`withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2))` around the `isFoldersExpanded.toggle()` — matches the exact idiom already used for the other structural expand/collapse-style transitions in this codebase (`ContentView`'s tab switch, `ChromeBar`'s tab-selector animation both use `.easeInOut(duration: 0.2)` gated on `@Environment(\.accessibilityReduceMotion)`). The chevron's rotation animates implicitly as part of the same state change; the content below appears/disappears via a `.transition(.opacity.combined(with: .move(edge: .top)))`-style fade+slide (or just `.opacity` if that reads as janky in `make run` — flag for visual tuning, not a hard requirement). With Reduce Motion on, skip the animation entirely: the chevron snaps to its new angle and the content appears/disappears instantly, exactly like every other `reduceMotion ? nil : …` call site in this app.

## 6. Empty state + "+" placement

Empty-state copy is unchanged: "No folders in your library yet. Use ＋ below to add one." (shown only while expanded, same as today — you only see this message once you've opened the list).

**Recommendation: keep "+" where it is today — trailing in the always-visible trigger row, not inside the expanded content.** Reasoning:
- Adding a folder is likely the single most frequent action in this footer; keeping it always reachable avoids forcing an expand-then-add detour for the most common case.
- It's the lower-risk, smaller diff for what's meant to be a small, well-scoped change — the row's structure (chevron+label leading, "+" trailing) doesn't change shape between collapsed and expanded, so there's nothing to reflow.
- It sidesteps the DisclosureGroup-vs-custom question in §3/§12 entirely: whichever trigger implementation is chosen, "+" is simply an unrelated sibling `Button`, exactly as it is today.

The alternative — moving "+" inside the expanded content (e.g., a trailing "Add Folder…" row under the list, or beside the empty-state message) — is now technically possible since the content is no longer a transient popover (see §7 below), and it would tighten the empty-state copy's "use + below" into pointing at something immediately adjacent rather than a disconnected footer button beneath a floating card. That's a genuine, reasonable alternative if the founder wants a more decluttered collapsed row; it's called out as Fork 2 in §12 rather than assumed, per the brief.

## 7. On the popover-era "+" constraint

`MusicFoldersView`'s header comment explains why "Add" lives in the footer today: an `.fileImporter`/`NSOpenPanel` hosted inside a *transient* popover gets torn down when the panel steals focus. That constraint is specific to `.popover`'s dismiss-on-outside-interaction lifecycle — it does not apply to inline content that's part of the same persistent view hierarchy as the rest of the footer (nothing about an expanded accordion section gets programmatically torn down when an `NSOpenPanel` takes focus). Recommend keeping `.fileImporter` attached at the `LibrarySidebar` level exactly as today regardless of where "+" ends up sitting (§6) — this is an implementation note, not a design decision, but worth flagging so the stale rationale in `MusicFoldersView`'s header comment gets updated/removed rather than copy-pasted forward.

## 8. Persistence of expand/collapse state

**Recommendation: `@AppStorage("library.foldersExpanded.v1")`, default `false` (collapsed).** This matches the `.v1`-key-versioned `@AppStorage` convention already established for `EQTabView`'s interpolation-mode toggle, needs no `LibraryBrowseModel` changes, and remembers whatever the user leaves it as across app relaunches. As a bonus, it also survives `LibrarySidebar` being recreated mid-session — the exact class of concern this file's own header comment cites as the reason `selectedCategory` is bound to the model instead of kept as local `@State` ("survives tab teardown"). A plain local `@State` would be lost on that same teardown; `@AppStorage` (backed by `UserDefaults`, not view-instance memory) is not.

Alternative: session-only local `@State`, always starting collapsed on every launch and every sidebar recreation. Simpler mental model, but likely to read as a regression to anyone who deliberately leaves the list open (e.g. to watch scan progress across a session). Not recommended.

## 9. States

No change to any of the per-row behaviors — only the container moves from popover to inline. Confirmed unchanged:

- **Collapsed** (default first-launch state, or whatever was last left): trigger row only — chevron forward, folder icon, "Music Folders," "+" trailing. No folder content occupies layout space.
- **Expanded, folders present**: trigger row (chevron rotated down) + hairline + the folder list, clamped/scrollable per §4.
- **Scanning-in-progress row**: unchanged — driven by `model.scanningRootID`, renders the "Scanning…" secondary line under that root's path exactly as today.
- **Empty** (`model.roots.isEmpty`, expanded): single message row, no scroll, no hairlines. "+" per §6.
- **Remove-confirm alert**: unchanged — per-row "⊖" opens the same destructive/cancel `.alert` with the same copy. `.alert` is a window-level modal in AppKit/SwiftUI regardless of whether the presenting view is inline or inside a popover, so no behavioral difference is expected — flag as a build-verify checkpoint rather than a design change.

## 10. Accessibility

- **VoiceOver, disclosure state**: the trigger `Button`'s label content (chevron + folder icon + "Music Folders") should announce as a single element reading just **"Music Folders, button"** — mark both the chevron `Image` and the folder-glyph `Image` `.accessibilityHidden(true)` (they're decorative; the text label already says what this is) and add `.accessibilityValue(isExpanded ? "Expanded" : "Collapsed")` on the button, so VoiceOver reads "Music Folders, button, collapsed" / "…expanded" — the same announcement contract a native `DisclosureGroup` gives you for free, reproduced by hand. Update the existing `.accessibilityHint` ("Add or remove the folders in your library") to reflect the new toggle behavior, e.g. "Show or hide your music folders."
- **Keyboard**: Space/Return toggle the trigger — inherited automatically from using a real `Button`, not a custom gesture recognizer (no extra work). Tab order proceeds trigger → "+" → (when expanded) each folder row's remove button → the category list, matching the visual left-to-right, top-to-bottom order; no explicit `accessibilitySortPriority` expected to be needed.
- **Dynamic Type**: label text already uses `Font.caption` (scales). Apply the same `Font.caption` (or an equivalent `.imageScale`) to the chevron glyph so it scales in step with the label — an unscaled fixed-size chevron next to text that grows at larger Dynamic Type sizes is a common, easy-to-miss mismatch.
- **Reduce Motion**: per §5, both the rotation and the content transition are skipped (state changes instantly) when `accessibilityReduceMotion` is on.

## 11. View tree

**Current (popover-based):**
```
LibrarySidebar
├─ List(selection:) { categories }                    // scrolls independently
├─ .safeAreaInset(edge: .bottom) { footer }            // pinned
│   └─ footer: VStack
│       ├─ (optional) scan-status row + hairline
│       └─ HStack                                       // header row
│           ├─ Button("Music Folders", icon: folder) { showManageFolders = true }
│           └─ Spacer + Button("+", icon: plus) { showFolderImporter = true }
├─ .fileImporter(isPresented: $showFolderImporter, …)
└─ .popover(isPresented: $showManageFolders) { MusicFoldersView() }   // ← floating, detached
     └─ MusicFoldersView  (.frame(width: 340))
         ├─ Text("Music Folders")  // section title
         ├─ (if empty) empty-state Text
         └─ (else) ScrollView(maxHeight: 280) { rootRow × N + hairlines }
             └─ rootRow: folder icon + path (+ "Scanning…") + remove button → .alert
```

**New (inline-accordion-based):**
```
LibrarySidebar
├─ List(selection:) { categories }
├─ .safeAreaInset(edge: .bottom) { footer }
│   └─ footer: VStack(spacing: 0)
│       ├─ (optional) scan-status row + hairline
│       ├─ HStack                                       // trigger row
│       │   ├─ Button (toggles @AppStorage isFoldersExpanded, withAnimation)
│       │   │   └─ HStack { chevron.forward (rotates 90° when expanded, .accessibilityHidden)
│       │   │                · folder icon (.accessibilityHidden) · "Music Folders" }
│       │   └─ Spacer + "+" Button (unchanged position — §6)
│       ├─ (if expanded) hairline
│       └─ (if expanded) MusicFoldersAccordionContent    // was MusicFoldersView, minus title + fixed width
│             ├─ (if empty) empty-state Text
│             └─ (else) ScrollView(maxHeight: 280) { rootRow × N + hairlines }
│                 └─ rootRow: unchanged (icon + path + "Scanning…" + remove button → .alert)
├─ .fileImporter(isPresented: $showFolderImporter, …)   // unchanged; no .popover anymore
```

## 12. Tokens & spacing

| Slot | Value | Token |
|---|---|---|
| Trigger row padding | 16 / 8 | `Spacing.medium` (h) / `Spacing.small` (v) — unchanged from today's footer row |
| Chevron ↔ folder icon ↔ label gap | 8 | `Spacing.small` |
| Folder-list clamp height | 280 | inline literal, carried over from the popover (`MusicFoldersView`'s existing `maxHeight: 280`); optional cleanup (out of scope) — promote to a named constant now that it's a load-bearing footer-layout invariant, not a self-contained popover detail |
| Row vertical padding | 4 | `Spacing.xSmall` (unchanged, `rootRow`) |
| Hairline | 0.5 | `DesignSystem.Color.hairline` / `ShellMetrics.hairline` |
| Label / row type | 12 regular (trigger, path secondary bits) / 14 regular (path) | `Font.caption` / `Font.body` |
| Label / row color | secondary / primary | `Color.labelSecondary` / `Color.label` |
| Chevron rotation | 0° ↔ 90° | inline literal |
| Animation | 0.2s easeInOut, `nil` under Reduce Motion | inline literal, matches `ContentView`/`ChromeBar` precedent |
| Persisted key | `library.foldersExpanded.v1`, default `false` | `@AppStorage`, matches `EQTabView`'s `.v1` convention |

## 13. Forks (recommended first)

**Fork 1 — trigger implementation.**
- **A. Custom chevron + `Button` + local toggle (RECOMMENDED).** Keeps full control over the row's three independent parts (chevron, label, trailing "+"), so the "+" button's hit-testing is never ambiguous. Small diff (one image, one rotation, one toggle); still gets standards-based keyboard/VoiceOver behavior for free by building on `Button`, with two explicit accessibility touches added by hand (§10).
- **B. Native `DisclosureGroup(isExpanded:label:content:)`.** Zero custom chevron/rotation/animation code, automatic native VoiceOver "collapsed/expanded" announcement and keyboard handling. Downside: the trailing "+" has no natural slot in `DisclosureGroup`'s two-part (label/content) API without either embedding it inside the label closure (reintroducing the same tap-target ambiguity Option A avoids) or moving "+" out of the trigger row entirely (Fork 2, option B). Reasonable if the founder is fine with "+" moving — flag the dependency between the two forks.

**Fork 2 — "+" placement.**
- **A. Keep it in the always-visible trigger row, unchanged (RECOMMENDED).** Adding a folder stays a one-click action regardless of expand state; smallest diff; sidesteps Fork 1's tension entirely.
- **B. Move it inside the expanded content** (next to the folder list or the empty-state message). Now technically viable since the content isn't a transient popover anymore (§7); declutters the collapsed row and tightens the empty-state copy's "below" reference. Costs an extra click (expand, then add) for what's likely the most frequent action here.

**Fork 3 — persistence.**
- **A. `@AppStorage("library.foldersExpanded.v1")`, default collapsed (RECOMMENDED).** Remembers the user's last state across launches and across in-session sidebar recreation; no model changes; matches the existing `EQTabView` `.v1` convention.
- **B. Local `@State`, always starts collapsed.** Simpler, but resets more often than users likely expect (every launch and every sidebar teardown), including losing the state mid-session in a way `selectedCategory` was specifically changed to avoid.

---

*Next: swiftui-pro implements the trigger/content relocation in `LibrarySidebar.swift` (`MusicFoldersView` trimmed per §4, `.popover` replaced with the inline conditional content) behind build/lint/test/periphery; founder `make run` verifies the expand/collapse feel, the 280pt clamp with a large folder count, and VoiceOver's collapsed/expanded announcement.*
