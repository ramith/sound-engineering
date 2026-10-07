# S10.8 part 2 — glass sweep ledger

Per-sprint record for [s10-8-glass-sweep-plan.md](s10-8-glass-sweep-plan.md): each sprint's
plan check, PR record, filled acceptance matrix, founder findings with their triage tag, and the
mini-retro that adjusts the next sprint (plan §D). The plan carries the *why*; this carries the
evidence.

## Sprint A — foundation

### Plan check (2026-10-06)

Started by a swiftui-pro agent (stopped by the coordinator at the founder's request once its
probes had answered the open questions) and completed by the coordinator from the agent's
scratchpad evidence plus a code read. Corrections to the plan's Sprint A:

1. **A4 is proven feasible as designed.** A throwaway debug renderer rendered the *real*
   `ContentView` (Now Playing and Library › Songs) from fixture models, offscreen, in dark,
   light and dark + Increase Contrast, before the single-instance guard and without opening the
   library store. It produced the first-ever light render of Now Playing. No fallback needed.
2. **A1 visual change is negligible.** The probe's before/after crops (analyzer lens, hero
   chips, filter pill, Songs rows) show only the halos disappearing. Badges (chips, pills, the
   device pill) get **no** drop shadow — they never had a designed one; what looked like their
   shadow was the text halo.
3. **A2 needs two tokens, not one.** Moving teal text to the existing `accentText` would
   brighten approved dark text (#29B6A4 → #6FE0D0). So: `accentFill` (tints, fills, glyph fill
   layers) and `accentForeground` (text, glyphs), each with **dark = today's #29B6A4** and only
   the light value changed. Inventory: 8 `.tint` sites (6 of them the `.borderedProminent`
   buttons), 13 teal-text sites, 2 two-layer glyphs; ~14 decorative strokes and fills keep
   `accent`. The primary pill reuses the shipped teal gloss + `onAccent` text (already audited
   as R4-TAB-01) — dark text on the deeper teal would fail AA in light.
4. **A3 is smaller than planned.** The queue already scrolls its cursor into view; only Songs,
   playlist detail and the sidebar need scroll-into-view. The focus ring uses `accentText`'s
   values (≥ 3:1 against every row fill, both appearances).
5. **Order:** all four PRs are independent → built **in parallel** (founder request), each in
   its own worktree, merged by the coordinator, then one `make strict-gate` on the merge.

### PR record

Built in parallel by four swiftui-pro agents, each in its own worktree; replayed onto
`sprint/s10-8-a-foundation` by the coordinator (one palette conflict — both sides' new tokens
kept). Combined: `swift build` + 224 tests + format + lint + semgrep green before the full gate.

| PR | Commits | Scope | Tests |
|---|---|---|---|
| A1 | `d73b40c` | Card shadow cast by the background fill shape only; `SurfaceRole.castsShadow` (panel, lens true; badge, overlay false). No GlassDecor value changed | RES-06 |
| A3 | `295f693` `a46f1f8` `dffd1a8` | `focusRing` token (= `accentText` values); `keyboardCursorRing` on Songs, queue, playlist detail and the rail; scroll-into-view on Songs, playlist detail and the rail (the queue already had it) | R4-FOCUS-01, R4-FOCUS-02 (queue rows over the dark glow) |
| A2 | `4ce0d9a` `fd2dd24` `d01ed17` `4b2e4f5` | `accentFill` / `accentForeground` (dark = today's teal); text, glyph and switch-tint sites migrated; `PillButtonStyle` (shipped teal gloss + dark text) replaces the 6 `.borderedProminent` buttons; semgrep `ui-no-bordered-prominent`, `ui-no-accent-as-text` | R4-TINT-01…03 |
| A4 | `bed2bb4` `e60eae5` `2f1dd91` | Debug picture-sheet renderer (`-ASRenderSheets`, fake audio engine, fixture models, isolated settings suite) + `make sheets`: 5 tabs × 6 appearances × 2 sizes = 60 sheets | renderer smoke run (60/60, live app untouched — checked with `lsof`) |

### Deviations from the plan (accepted by the coordinator, with evidence)

1. **No app-wide root tint (A2).** An offscreen render showed an inherited `.tint` recolours
   every plain and bordered button in dark (white text → teal text on a teal wash) and turns
   default-action buttons white-on-teal (~2.5:1) — a dark-look change the founder rule forbids
   and the exact failure A2 removes. The menu-bar menu is native; a tint does nothing there.
   *Corrected in the review round:* A2 had instead tinted the one untinted switch ("Keep
   playback on this device") teal — but that switch drew in the system accent (blue), so it was
   itself a dark-look change. Reverted; Sprint F restyles Settings.
2. **Increase Contrast sheets use a private AppKit selector (A4).** `NSAppearance(named:)`
   silently maps the high-contrast names to plain appearances; only the private
   `_darkAquaAppearanceWithAccessibility:` renders true Increase Contrast. Debug-only, never in
   the release binary, checked at runtime and failing loudly rather than faking.
3. **EQ persistence takes an injected settings store (A4)**, defaulting to the app's standard
   store with unchanged keys — so the renderer cannot write the founder's EQ settings.

### Found by the first picture sheets (to triage at the founder check)

- Now Playing, light, 880×640: the "Filter queue" placeholder is cut off; the Crossfeed switch
  is barely visible (light — Sprint B).
- Songs, light + Increase Contrast, 880×640: the count subtitle wraps onto three lines; row
  highlights touch the card's right edge.
- The teal Play pill is ~6pt taller than the system Shuffle button beside it (Shuffle is
  restyled in Sprint E).
- The keyboard ring shows as soon as the rail and the queue auto-focus, and after a mouse click.

### Gate and reviews

- **Strict gate, first run:** failed before any code check — swiftlint crashed (SIGILL) walking
  the agents' worktrees under `.claude/worktrees/` (full repo copies with their own `.build/`).
  Fixed at the root: `.claude/` excluded in `.swiftlint.yml` and `.swiftformat` (`3f30e7e`),
  merged worktrees removed. **Second run: exit 0.**
- **code-reviewer:** no blocker; MAJOR = the Settings switch tint above; MINORs = ring and keys
  could act on different rows, the ring showed on auto-focus and clicks, semgrep gaps (the
  Monitoring "BEFORE" tag reads `accent` through a variable — deferred to Sprint G), badge
  shadows also dropped under Reduce Transparency / Increase Contrast (judged from the sheets).
- **swiftui-pro:** no blocker; MAJOR = the ring should mean *keyboard* focus (macOS convention);
  MAJOR = the pill taller than its neighbours (primary actions stand out by fill, not height);
  MINORs = capsule focus shape, drop-target outlines and one play disc still on bare `accent`,
  a stale doc, the debug seed's anchor.

### Review fix round (swiftui-pro, 10 commits `816906c`…`1612820`; 236 tests)

| # | Fix |
|---|---|
| prep | `PlaylistItemList` moved to its own file (PlaylistView.swift 488 → 216 lines) |
| 1 | `KeyboardFocusVisibility`: one app-wide input-mode tracker; the ring draws only after Tab / arrow / Home / End / Page keys (or always with Full Keyboard Access), never on open or after a click; ⌘-arrows (track skip) don't count |
| 2 | `ListKeyboardCursor` in LibraryBrowseKit (11 tests): ring, arrows, Return and Delete resolve one row; a first arrow press selects the ring row; Return / Delete act only on a selected or ringed row; lists with no cursor-able row aren't focus stops |
| 3 | Settings switch untinted again (above) |
| 4 | Pill height from `controlSize`: 24pt regular (measured = system bordered), 30pt large; capsule focus shape |
| 5–6 | Drop-target outlines and the Recently Played disc on `accentFill`; R4-TINT-04 (dark-on-teal glyph ≥ 3:1) |
| 7–9 | Doc fix; debug seed sets the anchor; `ui-no-bordered-prominent` widened to `.glassProminent` and the style initialisers |

**Behaviour changes to put in front of the founder:** with the keyboard ring on the queue's
playing row, Delete removes the playing track (the "one row" rule); every pill is now 24pt
(was 30).

**Plan amendment:** §H's Sprint G check "Space works pills and switches" is reworded — Space is
the app-wide play / pause key by design (it is matched before a focused button); Return
activates a focused pill.

### Break-it pass (qa-expert + the-fool, read-only, 2026-10-07)

**Decisive fact:** Full Keyboard Access is **on** on the founder's Mac (`AppleKeyboardUIMode` = 2,
verified). With it, the review round's "ring only for keyboard" and "Delete acts on the ring row"
combined into a data-loss bug: one ⌫ in the queue (which auto-focuses) removed the playing track,
and in playlist detail removed entry 1 — on main, Delete required a selection.

**R1 blockers → fix round 2:**

| # | Finding (reviewer) | Fix |
|---|---|---|
| 1 | ⌫ removes an unselected row — the playing track, or a user playlist's first entry; repeated ⌫ at the queue's end reaches the playing row (both) | Delete requires a real selection; an unanchored ⌫ only claims the row; after deleting the last row the cursor moves to the new last row |
| 2 | Full Keyboard Access forced the ring on permanently (the-fool) | FKA no longer forces the ring; Tab / arrows still switch to keyboard mode |
| 3 | First ↓ in the queue appears to do nothing (stays on the playing row) (the-fool) | Steps from the playing row |
| 4 | Monitoring "BEFORE" tag is teal text at 2.5:1 in light — reached `Text` through a parameter, so semgrep missed it (QA) | `accentForeground` |
| 5 | Songs: ⌘-click to deselect, then Return plays the deselected row (QA) | Anchored only while it is selected |
| 6 | Sheets lie: Increase Contrast without Reduce Transparency (impossible on macOS), stale PNGs never cleared, display-profile PNGs, a 0-sheet run exits 0 (both) | IC implies RT; per-commit output dir; sRGB; usage error |

**Triaged to later sprints (not Sprint A blockers):**

- **Sprint D (R1 blocker there):** the Songs count subtitle wraps onto three lines at the
  880×640 minimum window, in dark too — pre-existing, pixel-identical before Sprint A.
- **Sprint E:** the queue cursor is a *position*, not a track — drag-reorder or a removal above it
  moves the cursor onto a different track (pre-existing); Songs keeps one merged anchor while E1's
  ⇧-arrow needs the anchor and the moving row separate (extend `ListKeyboardCursor`, don't fork).
- **Sprint F (R1 blocker there):** "Keep playback on this device" is system blue on an app-drawn
  card; the Monitoring AFTER tag (app blue, 3.7:1 in light) and the BEFORE swatch.
- **Sprint G:** Space on a focused button or switch under Full Keyboard Access toggles playback
  (the menu's Space key is matched first — pre-existing); the ring stays drawn when the window is
  inactive.
- **Rule hardening (next sprint that touches `.semgrep.yml`):** the accent-as-text rule misses
  `foregroundColor`, `Color.accentColor`, values passed through a variable, and multi-line calls;
  flip it to an allow-list (bare `accent` only inside `stroke` / `strokeBorder` / `fill` /
  `background`). With no root tint, every system control in Sprints D–G needs its own tint —
  added to the plan's §F rules.

**Renderer blind spots — matrix cells pre-marked "live-only":** system controls draw in the
inactive-window state (switch tints and segmented selections can't be judged from sheets);
Materials (banners, toasts); real album art (and so the art-sampled glow); the titlebar strip;
large text; window sizes other than 1000×720 and 880×640; any screen not yet in the fixture
(Albums, Artists, Genres, detail pages, playlists — fixture routes are part of Sprints D and E).

**Tried to break, held:** A1's dark look (shadow pixels match the probe; the lens changes by at
most 4 levels — only the halos); both teal tokens' dark values equal today's teal; Sprint A's
teal text measures 6.0–8.6:1 in light; the keyboard monitor ignores ⌘-shortcuts, modifiers,
typing, Space, Return and Esc; all 6 pill swaps kept their disabled bindings, labels and
shortcuts; the renderer can't be reached by `make run` and never touches the founder's store,
settings or audio; the rail stands down during drill-downs and renames.

**Founder check additions (≈ 90 seconds), because nothing in Sprint A's original check exercised
what Sprint A changed:** open an album and look at Play; open a playlist and look at Play beside
the other buttons; launch, and without clicking press ↓ once in the queue (it moves); press ⌫
before selecting anything (nothing happens).

### Founder check (2026-10-07, dark + a light glance)

| Step | Founder found | Outcome |
|---|---|---|
| Now Playing look | Unchanged in dark | ✅ accepted |
| Light mode | "OK for an undesigned state" | ✅ accepted — designed in Sprint B |
| Album page Play | First click did nothing; on retry it played (log: `playNow: 2 track(s)`) | ✅ works — the first click most likely only activated the window |
| No Shuffle beside Play on the album page | — | Not a bug: the coordinator's check script was wrong (album pages have Play + More; Shuffle is on artist / genre pages) |
| "‹ Library" from an album returns to the top of the grid, not where the founder was | — | **New R1 Must → Sprint D** (the Albums grid keeps its scroll position) |
| Playlist page "looks different" | — | Expected: playlist pages get their glass card in Sprint D and header in Sprint E |
| Queue: click a song, Backspace → not removed | **R1 blocker** | **Fixed** (`e6310dd`, `ebbdb59`) — confirmed by the founder |

**The Backspace bug — root cause.** `.onKeyPress(.delete)` never fires on macOS: Backspace arrives
as U+007F while `KeyEquivalent.delete` is U+0008. The handler had been dead in both the queue and
playlist detail since before Sprint A; Sprint A's check exposed it. Both lists now use
`.onDeleteCommand` (⌫, ⌦ and Edit ▸ Delete), keeping the Sprint A rule (only a selected row is
removed); semgrep `swift-no-keypress-delete` keeps it out. Verified on the running app with real
mouse and key events (queue: `removeTrack:` logged; playlist detail: entry removed; Songs and
the rail: ↓ moves).

**How it was found without more founder time.** The coordinator drove the real app with macOS
accessibility automation and a direct-binary launch that captures the `[UX]` log. One trap,
recorded so it is not repeated: System Events `click at` performs an element's *accessibility
action*, not a mouse click — it produced a false "the device menu holds focus" diagnosis until
the fix agent switched to real mouse and key events.

**Side effect, disclosed to the founder:** testing a playlist row replaced the founder's queue
(by design); the agent restored it as it was at launch, deleted only throwaway test tracks, and
a few test songs played briefly.

### Mini-retro — Sprint A

1. **Parallel worktrees paid off; merging cost little.** Four PRs built at once; one palette
   conflict. But the worktrees crashed swiftlint until `.claude/` was excluded — any future
   parallel sprint starts with that exclusion in place (done).
2. **Break-it found what review missed — twice.** Reviews passed a Delete rule that, with Full
   Keyboard Access on (the founder's real setup), deleted the playing track; the founder check
   then found a Delete handler that had never worked. **Change for Sprint B on:** every
   keyboard / focus change is tested live with Full Keyboard Access on, using the automation
   harness, before the founder sees it.
3. **The check script must exercise what the sprint changed.** The original one did not (the
   devil's advocate caught it); the founder's 10 minutes found a pre-existing bug. Keep writing
   checks from the sprint's diff, not from the plan's wording.
4. **Picture sheets earned their keep** (60 → 70 sheets, ring and empty variants) but cannot
   show live interaction, real art, or system-control tint — those stay founder-only.
5. **Next sprint's plan check** reads this retro, adds the live FKA keyboard pass to Sprint B's
   loop, and starts Sprint B with the light options render (B1).

**Late founder finding (same check):** in Songs, multi-select by keyboard (Shift + ↑/↓, ⌘A,
type-to-find) doesn't exist; Shift + click and ⌘ + click work, and right-click → Add to Queue /
Play Next adds the selection. **Founder decision: keep the keyboard set in Sprint E** (E1), built
once for Songs and every detail page. Also noted: the selected-row tint is very faint (≈ 1.2:1
in dark), which makes a multi-selection hard to see — a Sprint B light-design item that also
covers dark.
