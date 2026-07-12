# S9.5 — Customizable Songs columns (implementation plan)

Status: **✅ SHIPPED (S9.5) — execution record.** Execution layer for the **already-locked** design in [s9-5-songs-search-design.md](s9-5-songs-search-design.md) §11 (spec) + §12 (founder decisions D-A/B/C + play-tracking) + §12.5 (pre-change reviews). This doc is the *how* — the SwiftUI wiring, persistence, the one backend delta, and the risks.

## 1. What's already true (so this is mostly UI)

- **Backend catalog fully projected** — `LibraryTrackDisplay` has `trackNo`, `format`, `albumArtistName`, `genreName`, `playCount`, `lastPlayed` (the needs-read columns landed with the full-catalog work; Album-Artist LEFT JOIN + Genre correlated subquery already `EXPLAIN`-gated via SS3/SS4).
- **Sort cases exist** for every sortable column EXCEPT Track #: `TrackSort` has `albumArtistAsc/Desc`, `playCountAsc/Desc`, `lastPlayedAsc/Desc`, `formatAsc/Desc`, etc.
- **Current table = 10 columns** (Artwork · Title · Artist · Album · Time · Date Added · Quality · Year · Disc # · File Size), all fixed/always-visible, model-owned `sortOrder`.

## 2. The delta this chunk adds

**A. One backend delta — `TrackSort.trackNoAsc/.trackNoDesc`** (§11.1 marks Track # sortable). Add to `LibrarySortOrders` + `trackOrder` + `descendingTrackSorts` + `ChecksSongsSort` SS1/SS2 rows — mirrors the shipped `artistName*` pattern exactly. (Trivial int-column sort; index-order or accepted filesort per EXPLAIN.)

**B. Five new display columns** (cells + `TableColumn`s): **Track #**, **Format** (bare codec, distinct from Quality), **Album Artist**, **Genre**, **Play Count**. Value formatting per §11.1 (all `DesignSystem` tokens; nil/0 → blank; Play Count 0 → blank; Album-Artist sentinel id-0 → blank; Genre display-only).

**C. `SongSortMapping` additions** (`LibraryBrowseKit`): keypaths `albumArtistName → albumArtist*`, `playCount → playCount*`, `trackNo → trackNo*`. **Genre has NO sort** (BR5 temp-b-tree hazard, §12.5) → no `sortUsing` on that column, not in the mapping.

**D. `TableColumnCustomization` wiring** — the core (§3 below).

## 3. TableColumnCustomization + persistence (the SwiftUI core)

- `Table(model.visibleSongs, selection: $selection, sortOrder: $model.sortOrder, columnCustomization: $columnCustomization)`.
- Every column gets `.customizationID("<stable-id>")` (the §11.1 `code` set: `artwork`/`title`/`artist`/`album`/`time`/`dateAdded`/`quality`/`year`/`trackNo`/`format`/`discNo`/`fileSize`/`albumArtist`/`genre`/`playCount`).
- **Default-hidden** (`.defaultVisibility(.hidden)`): Track #, Format, Disc #, File Size, Album Artist, Genre, Play Count. **Default-visible** (`.automatic`): Title, Artist, Album, Time, Date Added, Quality, Year. *(Note: the current always-visible Disc #/File Size become default-HIDDEN per §11.2's default set — confirm at review; it changes today's visible layout.)*
- **Always-on locks (§11.2) — via API, not menu-omission (revised per swiftui #2):** Artwork = **no `.customizationID`** (excluded from customization entirely; correct + idiomatic for a fixed leading column). Title = keep its `.customizationID("title")` but add **`.disabledCustomizationBehavior([.visibility, .reorder])`** so even the *native* header context-menu can't hide or reorder it (still resizable) — menu-omission alone does NOT stop the native menu, which would let Title be hidden into the degenerate state §11.6 claims is impossible. Floor of Artwork+Title ⇒ no "0 columns" state. **Every other column carries a stable, distinct `.customizationID`; Artwork carries none.**

**IMPL-1 — persistence via the NATIVE `@AppStorage` overload (revised per swiftui #1).** SwiftUI ships a first-class `@AppStorage` initializer for `TableColumnCustomization` (macOS 14+), so **no `RawRepresentable`/`Codable`/JSON bridge is needed** — it collapses to one line, kept in the VIEW (NOT the model — `@AppStorage` inside an `@Observable` doesn't trigger updates, and view-side `@AppStorage` re-reads UserDefaults on rebuild so it survives the tab-`switch` teardown *and* persists across launches, strictly better than `sortOrder`'s model ownership):
```swift
@AppStorage("songs.columns.v1")
private var columnCustomization = TableColumnCustomization<LibraryTrackDisplay>()
```
Absent/garbage → falls back to the `wrappedValue` (fresh default) automatically — the documented `@AppStorage` behavior; no bespoke fail-soft. Bump the `.vN` suffix on any catalog/lock change. *(This deletes the planned wrapper type, risk R-A, and the bridge round-trip test.)*

## 4. Sorting coexistence (§11.5)

- `sortOrder` (left-click → triangle) and `columnCustomization` (right-click menu + drag) are orthogonal bindings on the same `Table` — coexist natively.
- **Hiding the active-sort column** must clear the triangle (no invisible sort key). **Reset `sortOrder = []`, NOT the Artist anchor (revised per swiftui #3)** — the composite default is visually the *Artist* triangle (`sortOrder = [KeyPathComparator(\.artistName)]`), and Artist is itself hideable, so "reset to the Artist anchor" could point the triangle at the just-hidden column. Clearing to `[]` drops the triangle while the model's grouped `songSort = .artistAlbumTrack` still governs the actual order.
  ```swift
  .onChange(of: columnCustomization) { _, custom in
      guard let key = model.sortOrder.first?.keyPath,
            let id = customizationID(for: key), custom[visibility: id] == .hidden
      else { return }                 // idempotent: no-ops when sort already cleared / column visible
      model.sortOrder = []            // clear triangle; composite still applies
  }
  ```
  No feedback loop (writes `sortOrder`, never `columnCustomization`). This handler also fires on **resize/reorder** drags — keep it to the cheap visibility check, nothing else.
- **Launch reconciliation:** `columnCustomization` persists (`@AppStorage`) but `sortOrder` resets to the Artist anchor each launch, and `.onChange` never fires for the initial value — so if the user hid Artist and relaunched, boot would show the Artist triangle on a hidden column. In the load path, if the seeded sort column isn't visible in the restored customization, clear `sortOrder` once.
- Re-showing a column does NOT auto-restore its sort. Genre / Artwork have no comparator → never the sort key.

## 5. The Columns button (§11.3, D-B)

- A thin trailing `Menu` in `SongsHeader` (after the filter field), glyph `slider.horizontal.3`, `.help("Columns")`. Shown only when the header is (rows exist).
- It is a **view over the SAME `columnCustomization` state** (`customization[visibility: id]` toggles) → no drift with the native header context-menu. Carries the show/hide `Toggle`s **plus Reset to Default** (assign a fresh `TableColumnCustomization()`), which the native menu can't offer. Title/Artwork not listed (locked).

## 6. A11y / dark (§11.6) — unchanged rules
Composed row VO label stays stable regardless of visible columns (never strip a hidden field from VO). Sortable headers announce name+direction. Columns `Menu` entries are `Toggle`s with on/off state; Reset is a button; keyboard-only users show/hide via this menu. Native menus use system material (appearance-correct); glyph `labelSecondary`→`accent` on hover. `.dynamicTypeSize(.small ... .xxLarge)` clamp unchanged.

## 7. File map
- **Edit** `SongsView.swift` — add `columnCustomization` binding + `.customizationID`/`.defaultVisibility` per column; 5 new cells + columns; the Columns `Menu`; sort-coexistence `onChange`. The `@AppStorage` `Codable`-bridge wrapper (new small type, same file or a `SongsColumnStore.swift`).
- **Edit** `LibrarySortOrders.swift` / `LibraryStore+BrowseReads.swift` / `ChecksSongsSort.swift` — the `trackNo*` sort delta (A).
- **Edit** `LibraryBrowseKit/SongSortMapping.swift` — 3 keypath additions (C) + tests in `SongSortMappingTests`.
- **No schema change / no migration** (all fields already persist).

## 8. Risks
- **R-A — RESOLVED (swiftui #1):** no bridge — the native `@AppStorage` overload handles `TableColumnCustomization` + fail-soft directly. No wrapper, no bridge test.
- **R-B — default-visibility change to Disc #/File Size.** Today they're always-visible; §11.2 makes them default-hidden. That changes the out-of-box layout — founder confirm (§9).
- **R-C — selection latency (<100ms, OD-1) with up to 15 columns.** More columns = more per-row views; watch the R1 gate at make-run. Art column already validated; Genre correlated-subquery projection already gated at 20k (SS4).
- **R-D — Genre must have no `sortUsing`** (BR5). A stray comparator would trip EXPLAIN. Enforced by omission + no mapping entry.
- **R-E — column identity vs `sortOrder`.** `.customizationID` strings must be stable and distinct; reordering must never perturb `sortOrder` (orthogonal bindings, §11.5).

## 9. Open questions (founder, at manual-review)
1. **Default-visible set** — adopt §11.2 exactly (Disc #/File Size become **default-hidden**, off the initial layout)? Or keep today's Disc #/File Size visible by default? *(Recommended: adopt §11.2 — matches the Finder/Music-style lean default; the columns are one click away in the menu.)*
2. **Track # sortable** — add the `trackNoAsc/Desc` backend delta (recommended, §11.1), or ship Track # display-only? *(Recommended: add it — small, honors the spec.)*
3. *(Persistence — RESOLVED by review: native view-side `@AppStorage` overload, no bridge.)*

## 11. Expert-review log (2026-07-09)

**swiftui-pro — GO-WITH-CHANGES** (validated by type-checking probes on the macOS 26.5 SDK). Required (folded into §3/§4/§8): **#1** use the **native `@AppStorage` overload** for `TableColumnCustomization` (macOS 14+) — delete the `RawRepresentable`/JSON bridge, R-A, and the bridge test; keep it view-side (NOT the model). **#2** enforce Title's no-hide with **`.disabledCustomizationBehavior([.visibility, .reorder])`** (menu-omission doesn't stop the native header menu). **#3** the sort-reset must clear `sortOrder = []`, not the hideable Artist anchor, + reconcile once at launch. Confirmed correct: the 4-binding `Table` init, mixed sortable/non-sortable columns under both bindings, Artwork = no-`customizationID`, `TableColumnCustomization` is `Equatable`/`custom[visibility: id]` subscript works, `trackNo*` delta is genuinely absent (add is real), the 3 mapping additions, reset-via-fresh-`TableColumnCustomization()`. Nits: Columns-menu `Toggle` needs a `Visibility`→`Bool` binding bridge (cold path, fine) or use `Button`+action; verify Artwork pins leftmost at make-run; fixed the line-24 doc inconsistency (Artwork carries no id). **15 columns don't threaten the <100ms gate** (hidden columns render nothing).

**architecture (inline) — GO-WITH-CHANGES.** Concur on all three. The native overload makes persistence *cleaner* (no bespoke bridge, no migration); the `trackNo*` backend delta is well-contained (mirrors the shipped `artistName*` pattern, SS1/SS2-gated); the sort-reset `onChange` is loop-free. No added concerns. Blast radius: additive to the shipped table (5 columns + the customization binding + the sort-reset handler) — refactoring-specialist verifies no regression to existing sort/filter/selection at implement.

## 12. Implementation outcomes (2026-07-09)

**Backend (inline):** `TrackSort.trackNoAsc/Desc` + `trackOrder` + `descendingTrackSorts` + `SongSortMapping` (+trackNo/albumArtistName/playCount) + SS1/SS2 rows + mapping tests. Gated: VerifyLibraryStore 77/77, LibraryBrowseKit 20 tests.

**UI pass 1 (swiftui-pro):** all 14 columns customizable + locked Artwork (no id) / Title (`.disabledCustomizationBehavior`); native `@AppStorage` persistence; Columns menu + Reset; sort-coexistence + launch reconcile. `SongsView.swift` split into `SongsView`/`SongsHeader`/`SongsTable`/`SongsColumns` (file-length rule).

**UI pass 2 (swiftui-pro):** full a11y pass (row = one VO element composed on the artwork cell, others `.accessibilityHidden`; stable label from the track model per §11.6; default action Play + custom actions; header sort announcements; `.dynamicTypeSize` clamp; tooltips) + type-to-select (native, focus-based).

**A–Z RAIL — DEFERRED.** swiftui-pro confirmed against the macOS 26 SDK interface that SwiftUI `Table` has **no scroll-to-row API** (`ScrollViewProxy.scrollTo` can't reach Table rows; no `scrollPosition` hook on `Table`). Per its COULD / first-to-defer status, the rail is deferred rather than forced; it rides the OD-1 `NSTableView` escape hatch (`scrollRowToVisible`) whenever the table drops to AppKit. No unused tokens/model were added (would fail periphery).

**refactoring-specialist — GO-WITH-CHANGES → resolved:** no behavior regression (file split byte-faithful, coexistence loop-free, a11y interaction-safe, `trackNo` order-only). (1) Disc#/File-Size default-hidden = founder-approved (§11.2 lean default). (2) MEDIUM-1 desync footgun FIXED: `SongsColumns.defaultVisibility(for:)` is now the single source the table's `.defaultVisibility` modifiers read, so it can't drift from `defaultHidden`/`isVisible`.

**Manual-only (founder make-run):** VoiceOver row read + custom actions; customization persistence across relaunch; Columns menu + Reset; hide-active-sort-column → triangle clears; Artwork/Title can't hide; light/dark; the Disc#/File-Size now-hidden default; type-to-select.

**Crash found + fixed at make-run (2026-07-09).** Clicking a column header crashed (`EXC_BREAKPOINT`) — Thread 0: `EnvironmentValues.subscript.getter` assert via `swift_getAtKeyPath` during `GraphHost.updatePreferences()`/`NSHostingView.layout()`. **Root cause:** `AlbumArtworkView` (the row-artwork cell) read `@Environment(LibraryBrowseModel.self)`; a `Table` cell's `@Environment(Observable)` property is refreshed in a DETACHED graph host during the sort-driven preferences/accessibility pass, where the injected object is unresolvable → assert. (The album grid escapes it — no sortable-header re-layout path.) **Fix:** `AlbumArtworkView` takes `model` as a plain `let` (passed by its 3 callers), removing the only `@Environment(Observable)` from the artwork subtree — no `EnvironmentBox` to trap. Two earlier attempts (a11y-wrapper ZStack; then confirming the mechanism) narrowed it; the `let model` change is the fix, **founder-confirmed working**. (First "still crashed" report was a stale-instance test — the reference-build-verify stale-build trap.) **Lesson:** never read `@Environment(Observable)` inside a SwiftUI `Table` cell subtree — pass observables in as plain values.

## 10. Test hooks
- **`VerifyLibraryStore`:** SS1/SS2 rows for `trackNoAsc/Desc` (order/tiebreak/NULLs + EXPLAIN no-`SCAN TABLE tracks`).
- **`LibraryBrowseKitTests`:** `SongSortMapping` — the 3 new keypaths → correct `TrackSort` (asc/desc); Genre keypath (if ever passed) → composite default. The `@AppStorage` bridge round-trip + garbage→default (if the wrapper is a pure `RawRepresentable`).
- **Manual (`make run`):** header right-click show/hide/reorder/resize; the Columns button + Reset; hide-active-sort-column → snaps to default; layout persists across relaunch; Artwork/Title can't be hidden; 15-column selection latency; VO row label stable across hidden columns; light/dark.
- Gate: `make strict-gate` green (**periphery** must stay clean — the new columns consume `trackNo`/`format`/`albumArtistName`/`genreName`/`playCount`, closing any remaining projected-but-unused fields), golden master byte-identical (no DSP).
