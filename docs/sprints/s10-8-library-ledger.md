# S10.8 part 2 — Library "Twin Panels" implementation ledger

Implementation record for the Library redesign against the handoff at
[docs/design/library-twin-panels/](../design/library-twin-panels/README.md)
(README + LIBRARY_GUIDE + LIBRARY_GUIDE_ADDENDUM + png/00-08). Every PR: built,
`strict-gate` green. **PR-A..D are merged to `main` via PR #63 (2026-10-06, hosted CI green).**
**Founder verification cells are OPEN** — this session can't screen-capture (Screen Recording
TCC absent), so every ☐ is the founder's dark + light + Reduce-Motion + Reduce-Transparency
pass.

| PR | Commit | Scope | Founder cells |
|---|---|---|---|
| A | `c96eca8` | Lift the shared `MiniEqualizer` out of `PlaylistItemRow` (scaffolding, no visual change) | ☐ n/a |
| B | `3182fd1` | Window base + single teal glow behind the cards (`GlowField.libraryGlows`) + `R4-GLOW-LIB-01` audit | ☐ dark glow ☐ RT/light fallback |
| C | `b6c31ca` | Nav rail → floating glass card (`NavRow`, inline folders, shared `huggingGlassPanel`) | ☐ dark ☐ light ☐ hover ☐ VO ☐ keyboard/drop/rename |
| polish | `dd55025` | Idle nav labels → dedicated `labelNav` ~72% tier (matches the mock) | ☐ founder validated the ~72% look |
| D | `5f4f007` + `b6c6070` (default column order) | Songs list → custom column-customizable glass card (replaces the SwiftUI `Table`) | ☐ default view ☐ playing eq ☐ columns show/hide ☐ click-sort ☐ h-scroll ☐ RM/RT/light |

Hashes are `main`'s (PR #63 was rebase-merged, so they differ from the old
`sprint/s10-8-polish` hashes). Two tooling commits rode along in that PR, both caused by brew
moving on during the Jul→Oct idle gap, neither touching the Library: `1dba11a` (swiftformat
0.63.0 / swiftlint 0.65.1 pins) and `71ffbda` (clang-tidy major pinned to LLVM 23, its new
checks adopted across the C++). **Not yet built:** the "Fast-follows" list, deviations 6 and 8,
and the guide's PR-E / PR-F / final pass — these land on a fresh branch off `main`, not on the
merged sprint branch.

## Deliberate deviations from the handoff (each needs a founder OK or a follow-up)

1. **Guide samples predate the Kit** — the handoff's `Color(hex:)` / `asTeal*` / `GlassCard` /
   `StyledGlassBar` don't exist as symbols; everything routes through `DesignTokenKit`/`Palette` →
   `DesignSystem`/`DesignSystemGlass` (same as the Now Playing wave's deviation #1).
2. **Card radius = `GlassDecor.panelRadius` (22), not the mock's 18** — reuses the NP floating-card
   radius (one shared card radius; the NP wave already took 22 over 18, its deviation #6).
3. **Library glow is a SINGLE teal pool** (`libraryGlows`), not NP's 3-glow field — per the mock
   (png/00) + guide PR-B. Founder-tunable center/size; left at the computed spot pending eyes.
4. **Idle nav ~72%** — added `labelNav` (a new audited label tier) because no existing tier is 72%
   (founder chose this over the too-dim `labelSecondary` 55%).
5. **Music Folders collapse accordion retired** — the mock shows folders inline; the content-height
   card + scroll handle overflow. Add/remove/scan-hint preserved.
6. **Right pane = a glass card for ALL categories** (founder decision) — done iteratively: Songs
   card first (PR-D), then Albums/Artists/Genres/facet/playlist dropped into the shared
   `libraryDetailCard` (pending).
7. **Column model reconciled via the ADDENDUM** — kept full customization: clean 5-col default,
   teal Columns pill (show/hide), show-on-demand glass column-header row (click-sort), horizontal
   scroll on overflow, JSON-persisted `SongColumnConfig` (replaces the Table-only
   `TableColumnCustomization`).
8. **Gold lossless format tag DEFERRED** — the mock's `#CBB26A` gold FLAC/WAV tag needs a split
   text/fill token pair (gold-on-gold@14% fails AA at 9pt); reuses `FormatBadgeView` (playing=teal,
   else muted) for now.
9. **Column RESIZE dropped** — the addendum specifies fixed widths (Title is the only flexible
   column); the old Table's drag-resize is intentionally gone.

## Founder round 1 (2026-10-06) — first eyes on PR-A..D

The founder ran the merged build and compared it against the mock; seven fixes followed, on
`sprint/s10-8-library-founder-round-1`. Each was confirmed on the founder's screen the same day
(dark appearance; light / Reduce Motion / Reduce Transparency are still the open cells above).

| # | What the founder saw | Root cause | Fix |
|---|---|---|---|
| 1 | Sort pill read a bare "⌄ Sort:" — no value, no capsule | `.menuStyle(.borderlessButton)` hands the label to an AppKit pop-up button that keeps ONE image + ONE text, drops the rest, and never re-renders | `pillMenuStyle()` (`.menuStyle(.button)` + `.buttonStyle(.plain)`) — the label is a real, live SwiftUI view |
| 2 | Columns pill was plain white text, no teal capsule | same | same |
| 3 | Column header "TRA…" (Track #) | the header upper-cased the full menu label; a 44pt column cannot hold it | the mock's capitalisation; compact header labels (Track / Disc / Plays); Track No 44 → 52, Disc 40 → 44; **SLOT-04** holds every header to its column |
| 4 | Rows looser than the mock | the guide's row area is "6×12 padding" (6 above/below, 12 each side, no inter-row gap); the first cut used the 6 as row spacing and dropped the 12 | spacing 0 (48pt pitch) + the 12pt side inset, budgeted in the width math |
| 5 | Cards did not look like the mock's | NOT the fill (see below) — the NP 8a "bottom light bleed" put a ~24pt band along both cards' bottom edge that nearly doubled the fill's lightness | the card is flat to its edge (`SurfaceRole.hasBottomBleed`, **RES-05**) — shipped in round 1 as a separate `libraryCard` role, folded back into `.panel` in round 2 |
| 6 | Device pill: truncated name, an inner box, a blank right half | the borderless menu again: AppKit's bezel insets ate the name's width, and the rate had to sit outside the label to update, leaving a dead half | the whole pill is one live menu label; it hugs its content (≤ 302pt) and shows the rate only while one is known |
| 7 | Footer said "Unknown Artist" for a tagged song | the Now Playing refresh cleared the SYSTEM session for a stopped track and returned before resolving the display metadata the footer also reads | `NowPlayingRefreshPlan` separates the two; a stopped / restored track resolves artist + cover (**NP-08..10**) |

Also fixed, same root cause as 1–2: the playlist missing-file warning triangle had been drawing
grey — the borderless menu redraws its label as a template image and drops the amber token.

**Recorded so nobody "fixes" them:**

- **The card FILL was measured and left alone.** Card-vs-window luminance contrast is 1.11 in the
  app and 1.09–1.11 in the mock — equal. The app reads ~4 levels darker overall only because its
  window base is the D10 deep base (`#0E1013`, locked in S10.7) where this mock assumed
  `#131418`. Lifting the fill would drop `labelTertiary` (track numbers, dates) below AA at the
  glow peak (4.61 → ~4.45).
- **Deviation 10 — two column widths depart from the addendum** (Track No 52, Disc 44): at the
  addendum's 44 / 40 even the compact header plus the sort arrow does not fit.
- **Deviation 11 — the device pill hugs its content** instead of the fixed 302pt slot. The fixed
  width existed to keep the tab strip from sliding; the tabs moved to the chrome's right edge in
  part 1's founder round, so only the pill's own trailing edge moves now.
- **How this was verified without screen capture:** an in-process offscreen render
  (`NSHostingView` → `cacheDisplay`) of the menu-label variants reproduced the broken pill
  exactly and showed the plain style rendering — and live-updating — correctly. Usable again for
  any "does macOS actually draw this control" question; it cannot show Materials or the real app.

**Now Playing findings from the same session** — approved by the founder and fixed the same
day as *founder round 2*; recorded in the [realign ledger](s10-8-realign-ledger.md). One
consequence lands here: once the NP inspector card went flat too, `SurfaceRole.libraryCard`
(added in round 1) had nothing left to distinguish it from `.panel`, so it was removed — the
Library cards and the inspector are one role again, flat to the edge. The rail's bottom inset
also dropped from the 24pt bleed run to the guide's 10pt.

## Where the open work went (2026-10-06)

The remaining Library work — other categories into the card, PR-E / PR-F, empty states, and
the light / Reduce Transparency cells above — is now planned in
[s10-8-glass-sweep-plan.md](s10-8-glass-sweep-plan.md) (Sprints B, D and E). From the
fast-follows below, the **keyboard cluster is promoted to an R1 Must** (Sprint E); drag-a-header
reorder and the frozen title column stay deferred.

## Fast-follows (PR-D shipped the validated core; these land right after)

- **Drag-a-header reorder** (founder chose full apparatus; deferred as the fragile bit — the
  codebase's `.draggable`/`.dropDestination` pattern). Column ORDER already persists.
- **Frozen #+Title pin on horizontal scroll** (no native SwiftUI frozen-columns; robust versions
  have a translucent-card visual compromise). Only matters while horizontally scrolled.
- **Keyboard cluster** — ⌘A, ⌘↑/↓, ⇧-arrow range-extend, type-to-select (a11y-review-flagged; mouse
  ⌘/⇧ multi-select + ↑/↓ + Return + double-click all work today).

## Verified by machine (per PR)

- `R4-GLOW-LIB-01` (label + labelSecondary AA over the Library glow) + `R4-LEG-LIB-01` (labelNav AA
  on the panel card) — both green; the audit folds `libraryGlows` through the same `compositeBackdrop`
  the render reads.
- Accessibility review (PR-D): the row's single VoiceOver element is env-object-free → the old
  Table's EXC_BREAKPOINT a11y-relayout crash class is structurally impossible; labels/traits/actions
  preserved or improved (now-playing surfaced, selected trait deterministic).
- One crash caught + fixed pre-commit: `SongColumnConfig` RawRepresentable+Codable recursion
  (encoded `self` → re-read `rawValue`); now encodes `entries`, runtime-verified.
