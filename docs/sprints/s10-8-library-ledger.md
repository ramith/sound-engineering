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
