# S10.8 — one browse grid for Albums, Artists and Genres (design)

*2026-10-08. From the founder's test-library feedback ("Genres is a list while the others have a
thumbnail"), reviewed by ui-designer and product-manager in parallel; founder decisions 19 and 20 in
the [sweep plan](s10-8-glass-sweep-plan.md) §B. Builds in Sprint D (D4/D5) and the behaviour
pull-forward (arrow keys). Throwaway renders of the options were in the session scratchpad.*

## Decisions

- **Genres becomes a tile grid on the same tile as Albums and Artists** (decision 19, a recorded
  exception to the sweep's "no new arrangements" rule). A genre's art is a **2×2 mosaic** of its
  four albums with the most songs (Music.app builds playlist art the same way). The small new library
  read (four cover keys per genre) is approved with it.
- **Arrow keys move between tiles** on all three grids, built with the keyboard work in the behaviour
  pull-forward (decision 20).
- **No Sort pill on the grids for R1** (it would add an element); if it comes, it sits right of Filter.
- **Songs stays rows** (many, attribute-heavy, sortable; no thumbnails — the Twin Panels decision).

## What was wrong (diagnosis)

| | Today | Fix |
|---|---|---|
| Container | Albums / Artists / Genres sit on the glow, no card | D1: one card for the whole Library pane |
| Header | small count label beside a wide square field, no title | D2 / D4: the Songs card header (title, mono count line, Filter pill) |
| Genres body | system `List`, 24pt rows with separators | the shared tile grid (this doc) |
| Name / count gap | `lineLimit(2, reservesSpace: true)` leaves an empty line under one-line names (~40pt gap; Albums too) | one line per field, full name in tooltip + VoiceOver |
| Grid geometry | fixed 168pt tiles centred in wider columns: 48pt gaps across vs 24pt down, ragged right edge | tiles fill the width exactly |
| Hover | only a Play button | a plate behind the whole tile, plus Play |
| Keyboard | Tab only, with the system ring (blue by default) | the Sprint A teal ring; arrow keys (decision 20) |
| Missing art | `card` fill + ♪ — a hole in dark, invisible on the white card in light | `hoverWash` fill + the section's rail glyph |

## The shared grid

**Header:** identical to Songs — title (`.title3` heavy), count line (`monoSmall`, `labelTertiary`:
`857 albums` / `343 artists` / `27 genres`; `N results` while filtering), the Filter pill (⌘F focuses,
Esc clears). Insets 16 / 20 / 14; 1pt hairline inset 20.

**Grid:** area insets 12 × 6; 12pt spacing both ways; `columns = max(2, ⌊(W − 24 + 12) / 172⌋)` (160pt
minimum tile), tiles fill the width (880 → 3 columns, 1000 → 4, 1440 → 6); the cover lines up with the
header text.

**Tile:** plate padding 8, plate radius 16 (`Radius.control` + 8, concentric); square art, radius 8,
0.5pt hairline; title `bodyMedium` / `label`, 1 line, 8pt below the art; subtitle `caption` /
`labelSecondary`, 1 line, 2pt below. Album: title / album artist. Artist: name / "N songs". Genre:
name / "N songs".

**Art (one view):** 4+ cover keys → 2×2 mosaic (genres); 1–3 → the first cover full size; 0 → the
placeholder (`hoverWash` + the rail glyph — `music.note`, `music.mic`, `guitars` — in `labelTertiary`
at 28% of the side; no monograms, which break on CJK / RTL / emoji names).

**States, one rule for rows and tiles:** rest = no plate; hover = `controlHover` plate + Play; keyboard
focus = the A3 ring via `keyboardCursorRing(_, cornerRadius: 16)`, keyboard mode only, system focus
effect off; selected (reserved for multi-select) = `rowSelected` plate. The plate and hit area live
inside the Button label.

**Keyboard and VoiceOver:** ←/→, ↑/↓ (a row), Home / End, Page Up / Down, type-to-select, Return opens;
one element per tile, "title, subtitle" (albums add the year), with Play / Play Next / Add to Queue.

**So the three grids can't drift:** one `BrowseTile`, one `BrowseArt`, one `BrowseGridRoot` scaffold
(generalising today's `FacetListRoot` — load states, header, filter, grid); each section supplies only
data closures (items, noun, subtitle, art keys, route, queue reference, glyph). Metrics in one
`DesignSystem.BrowseGrid` enum; the column maths a pure, unit-tested function in LibraryBrowseKit; the
2-D keyboard cursor reuses `ListKeyboardCursor`'s rules. One picture-sheet variant per grid.

## Costs and risks

- **Genres on the grid + the cover read:** about +1–2 points over D5 as planned. The read is store
  work: a VerifyLibraryStore check (including the query plan) and a break-it pass.
- **Arrow keys:** about +2 points. The plan check of the behaviour pull-forward decides whether the
  `BrowseGridRoot` scaffold (structure only) moves forward with them, so the keys are wired once.
- **Density:** about 3 genres fully visible at the 880×640 minimum window (10 as rows); with hundreds
  of genres, Filter is the way in. The plan check asks for a 300-genre stress case.
- **No art:** a genre gathers many albums, so a mosaic usually finds covers; the placeholder rule
  covers the rest.

## Founder check (under 2 minutes)

1. Songs → Albums → Artists → Genres: the card, the header and the left edge stay still.
2. All three grids show the same tiles; a one-line name has its count right under it.
3. Hover a tile: the whole tile highlights and Play appears; clicking Play plays it.
4. Arrow keys move the teal ring between tiles; Return opens the page; going back returns to the
   same place (D6).
5. Type "ja" in Filter on Genres: it narrows; Esc brings everything back. Flip to light once.
