# LIBRARY GUIDE — Addendum 1: PR-D column model

**Supersedes the row-grid parts of PR-D only.** Everything else in `LIBRARY_GUIDE.md` and `README.md` stands. This resolves the conflict between the app's 15-column customizable `Table` and the mock's fixed 5-column list. New reference images: `png/06-columns.png` (full expanded window), `png/07-columns-card.png` (the list card), `png/08-columns-header.png` (the glass header row).

## The four answers

**1. Keep customization — do NOT drop it to a fixed set.** Users rely on show/hide + reorder, so it stays. What changes is the *default*: the list opens in an **opinionated 5-column view** (#/eq · Title+format · Artist · Date Added · Duration) with **no visible column-header row** — that's the clean `png/02`/`png/03` state. Customization is available but out of the way until asked for. So both mock states are the same list in two configurations, not two different designs.

**2. Affordance = a "Columns" pill in the header strip + a glass column-header row that appears only when needed.**
- Add a third pill to the header strip, right of the Sort pill: a teal-tinted **Columns** pill (`png/07`, top-right — icon + "Columns", fill `asTealMid 16%`, ring `asTealMid 30%`, text `asTealText`). It opens a menu/popover listing every column with a checkmark to show/hide (the existing Columns menu, restyled).
- The **glass column-header row** (`png/08`) is hidden in the default 5-column view and **appears automatically whenever the visible set differs from the default** (any column added/removed/reordered). It is a slim strip (height ~30, `white 4.5%→1.2%` gradient fill, 1px bottom hairline) sitting directly under the header strip, above the row area. Labels are 10.5pt heavy letter-spaced `white 50%`; the active sort column is `asTealText` with a teal ↑/↓ arrow. This row is where **drag-to-reorder** lives (grab a header, drop between others) and where **click-to-sort** lives — so headers are only present when the user has opted into the richer table, keeping the default clean.
- Rationale: a header-less card is right for the 90% "just my songs" case; power users flip on columns and get a real table header back. One control (the pill) reveals the whole apparatus.

**3. Default + optional columns, and how the grid adapts.**

Default visible (in order): **# / equalizer · Title (+format tag) · Artist · Date Added · Duration.**

Full optional set (the existing 15, restyled — all toggleable/reorderable): Title, Artist, Album, Genre, Year, Duration, Date Added, Quality, Sample Rate, Bit Depth, Track No, Disc, File Size, Play Count, Last Played.

Grid adaptation rules (see `png/06`):
- **# and Title are a frozen leading group** — always first, always visible, and they stay pinned when the card scrolls horizontally (note the faint 1px divider to the right of Title in `png/06`/`png/07` marking the freeze line). Title is the only flexible column: `minmax(240px, 1fr)` — it takes leftover space and shrinks to 240 before scrolling kicks in.
- **Every other column is a fixed width** (mono numerics right-aligned): Artist 150, Album 150, Genre 100, Year 52, Time 58, Date Added 96, Quality 84, Sample Rate 82, Bit Depth 64, Track No 44, Disc 40, File Size 74, Play Count 56, Last Played 96.
- **The card scrolls HORIZONTALLY; it never wraps and never shrinks metadata columns to fit.** When the sum of visible fixed columns + Title(min 240) exceeds the card width, a horizontal scrollbar appears inside the card (visible at the bottom of `png/06`). The header row scrolls in lockstep with the rows. Wrapping a table row was explicitly rejected — it destroys column alignment.
- Vertical scroll of rows is unchanged.

**4. Sort: the pill and header-click are one and the same state — confirmed.** The "Sort: Title ↑" pill is always present (even in the header-less default) and opens a menu of sortable fields; picking one sets the sort key + direction. When the glass header row is visible, clicking a header sets the *same* sort state (and shows the arrow on that header); the pill's label updates to match. There is exactly one `sortKey`/`sortAscending` model behind both — your existing sort machinery maps straight onto it. So: pill replaces header-click **in the default view** (no headers to click), and **coexists with it** in the expanded view, both writing the same state.

## Revised PR-D checklist (replaces the row-grid checklist)

- Default view: 5 columns, no header row, matches `png/02`/`png/03`.
- Columns pill opens the show/hide + reorder menu; toggling any non-default column reveals the glass header row.
- Header row: slim glass strip, active sort column in teal with arrow, drag-to-reorder works, click-to-sort works and matches the pill.
- Frozen # + Title stay pinned on horizontal scroll; Title is the only flexing column; all other columns fixed width, right-aligned mono for numerics.
- Card scrolls horizontally when columns overflow — no wrap, no metadata squish; header scrolls with rows.
- Playing row treatment (teal tint, ring, equalizer, teal title) and format/quality colors (lossy muted, lossless gold `#CBB26A`, playing teal) are identical in both views.
- Persist the user's column set, order, widths, and sort across launches (keep whatever persistence the current Table uses).
- Reduce Transparency / Reduce Motion behavior unchanged from the main guide.

## SwiftUI shape (adapt to your existing column model)

```swift
struct ColumnSpec: Identifiable, Codable {
    let id: SongColumn          // your existing enum: .title, .artist, .album, ...
    var visible: Bool
    // width: nil == flexible (Title only); else fixed points
    var width: CGFloat?
    var alignment: HorizontalAlignment
}

// default configuration = the opinionated 5
static let defaultColumns: [ColumnSpec] = [
    .init(id: .index,    visible: true, width: 34,  alignment: .center),
    .init(id: .title,    visible: true, width: nil, alignment: .leading),   // frozen + flexible
    .init(id: .artist,   visible: true, width: 150, alignment: .leading),
    .init(id: .dateAdded,visible: true, width: 96,  alignment: .leading),
    .init(id: .duration, visible: true, width: 58,  alignment: .trailing),
    // …all other SongColumn cases present but visible:false, with their fixed widths
]

var headerRowVisible: Bool { columns != Self.defaultColumns }   // show glass header when customized
var frozen: [SongColumn] { [.index, .title] }                   // pinned on horizontal scroll

// Layout: a horizontal ScrollView; frozen group in an overlay/pinned leading stack,
// remaining columns in the scrolling region. Header row and body share the same
// column widths and the same horizontal scroll offset.
```

Build the row/header from the SAME `columns` array so they can never drift. When `headerRowVisible` is false, render only the body (the default clean list).
