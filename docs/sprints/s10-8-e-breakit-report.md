# Sprint E break-it — detail pages and playlists

**Base:** `sprint/s10-8-e-detail` @ `9dc00a0`. **Red tests:** `Tests/LibraryBrowseKitTests/DetailPageBreakItTests.swift`, commits `239be5d`, `7d6ded3` and `d6a8542` on `worktree-agent-a02b7b1638fab4495`.
**`swift test`: exit 1** — 589 tests, 581 pass, 8 fail (13 issues). Every failure is one of the eight new tests. A code review and its fix rounds ran in parallel; findings here are behaviour, not style.

**Result:** no crash and no data loss found. One MAJOR (wrong play order), twelve MINOR. No BLOCKER.

How each finding is proved:
- **test** — a failing test. The page tests build a small library through the store’s own write path, in a temporary folder, and lay the page out exactly as `LibraryBrowseModel.detailContent` does, so a fix in the scan, the read or the kit turns them green.
- **replica** — a small standalone program that copies the view’s structure, run invisibly off screen with posted mouse events. It is not the app: confirm in the live pass. Sources are in `break-it-e-evidence/`.
- **code** — the app target can’t be imported by a test, so these are traced through the code, with steps to reproduce.

“Carried in” means the behaviour was there before Sprint E; “new” means Sprint E added it.

## Findings

| # | Severity | What was attacked | Proof | Expected | Actual | Origin |
|---|---|---|---|---|---|---|
| 1 | **MAJOR** | Album page order: a set ripped one folder per disc (`CD 1`, `CD 2`), with track numbers but no disc tags | test `discFoldersPlayDiscByDisc` | Disc 1’s songs, then disc 2’s | The discs interleave: 1, 1, 2, 2, 3, 3, each pair in title order. Play, double-click and Return all play it that way | Carried in (the old page interleaved by row id). `AlbumTrackOrder` now owns the rule, and its title tie-break is what interleaves |
| 2 | MINOR (visible) | Artist page: the year on an album header | test `artistPageHeaderShowsTheAlbumsYear` | The album’s year, as on its own page | The year of whichever song is read first. “Bombay” (1995) shows no year because its bonus song has none; a compilation (1992) shows 1974, the year of the artist’s one song on it | Carried in (S9.6 `FacetAlbumGrouping`) |
| 3 | MINOR (visible) | Artist page: the “Unknown Album” header | test `looseSongsHeaderHasNoYear` | No year: it is a bucket of unrelated songs | “Unknown Album · 2001” — the first loose song’s year | Carried in |
| 4 | MINOR | Genre page: order inside an album | test `genrePageKeepsAlbumOrder` | The album’s playing order, as on its own page | As read: a song with no disc tag plays before disc 1 (3, 4, 1, 2), and a song with no number plays first | New gap: the E3 review commit says “album track order on every page”, but the genre page still uses the read’s order |
| 5 | MINOR | Artist and genre pages: which album comes first | test `albumOrderDoesNotDependOnScanOrder` | An order that means something (year or title) | Store row id, which is scan order. The same four songs scanned in the other order swap the two albums. Songs with no album always come first | Carried in |
| 6 | MINOR | Artist page: the number on a song with no track tag | test `untaggedSongShowsNoNumberOnTheArtistPage` | Blank, as on the album page (the rule in `DetailTrackLayout.albumRows`) | “1” — the page numbers by place whenever this artist’s songs on the album are all untagged, even if the album has numbers. VoiceOver reads “Track 1” | New |
| 7 | MINOR | Selection: ⌘A, then ⇧↓, ⇧End or ⇧-click | test `shiftAfterSelectAll` | The selection stays a range | It collapses to one row (`[2]`, `[5]`, `[4]`). With no anchor, ⇧ acts as a plain move, and a page just opened has none | Shared kit (E1); reached by default on a page |
| 8 | MINOR | Album and artist pages: a click between two rows | replica `seam-replica.swift`; `LibraryRowChrome.swift:32–35` against `PlaylistItemRow.swift:142–143` | Every point of the list takes a click, as in the queue | The 2 pt seam between two 34 pt cards takes none: the row’s `contentShape` is set before its seam padding (the queue row sets it after). About 1 click in 18 at a random height does nothing — no select, no double-click play | New (the 36 pt pitch). Check live |
| 9 | MINOR | Artist page: Page Up / Page Down | code `DetailTrackList.rowsPerPage` (line 177) | A page moves a screenful less one row | The page size counts rows only, never the 44 pt headers. In a 500 pt list it moves 12 rows; where every album holds one song that is 960 pt, so from the second press on, six rows a press are never shown | New |
| 10 | MINOR | Right-click ▸ Play on a selected row, when another selected row is no longer shown | test `menuActsOnShownSelection`; code `LibrarySongMenu.swift:28–29` | The one visible row plays as a single row does | The menu counts hidden ids, so it plays “the selection”: one song, replacing the whole queue with no undo. Songs: ⌘-click two songs, filter so one hides, right-click the other ▸ Play. A page: the same after a reload removes a selected row. VoiceOver also announces the stale count | Shared kit; the menu became shared in E2 |
| 11 | MINOR | Playlist Shuffle, then “Restore previous queue” | code `PlaylistsModel.shufflePlaylist` (line 306), `AudioViewModel.restorePreviousQueue` | Undo puts playback back as it was | The queue comes back, but shuffle stays on, so the restored album now plays in random order | New |
| 12 | MINOR | Remove Missing while the library changes | code `PlaylistsModel.removeMissingEntries` (line 369), `PlaylistMoreMenu.swift:22` | The irreversible remove never acts on files that only look missing | The scan gate is on the menu item alone: once the dialog is open, Remove is not gated and the files are not checked again, so it removes by the snapshot taken when the page loaded. If the count falls to none while it is open, the dialog reads “Remove 0 missing songs?” | Carried in; the dialog is new |
| 13 | MINOR (rare) | A failure arriving while the Remove Missing confirmation is open | replica `sheet-replica.swift both` | A click meant for one dialog never presses the other | The notice replaces the confirmation in place, and OK sits where Remove sits. A double-click on OK pressed OK, then Remove, 120 ms apart. Only a late reorder-save failure can arrive then, so it is rare | New |

### Detail and suggested fixes

1. **Disc folders (MAJOR).** The store folds `CD 1` and `CD 2` into one album on purpose (S10.8 C2), but nothing gives their songs a disc number, so the album holds two songs numbered 1, two numbered 2, and so on. Either read the disc from the folded folder name at scan time, or keep each disc folder’s songs together on the page. A tie-break by path alone is not enough: it still gives 1, 1, 2, 2. The same gap shows on an album whose songs have titles but no track numbers: it plays A to Z even when its files are named `01 …`, `02 …`.
2. **Header years (2, 3).** The read gives each row the song’s own year. Carry the album’s shown year (`albums.year`) on the row, and give the no-album group none.
3. **Genre order (4, 5).** Apply `AlbumTrackOrder` to each album’s run on the genre page, or order the read. For the album order, the store already has a year order for an artist’s albums (`albums(byArtist:sortedBy: .year)`); the page’s read uses `album_id`.
4. **Seam (8).** Swap the two modifiers in `LibraryRowChrome` so the seam is inside the content shape.
5. **Menu (10).** Decide when the item is chosen, not when the row is built: if the selection resolves to one visible song, act as the single-row menu does.
6. **Dialogs (12, 13).** Check the files again inside `removeMissingEntries`, and refuse while the library is populating. Hold a failure until the confirmation closes rather than swapping it in.

### Smaller observations (no test; for triage)

- **Shuffle is sticky and unseen from the Library.** Shuffle on any page turns the saved shuffle setting on; its only switch is in the Now Playing queue header. After one Shuffle, the header’s Play, a double-click and Return all start at the right song and then play at random, so “the page from that song on, in the shown order” (decision 11, PLAY-02) holds only while shuffle is off. Decision 36 puts the pill on albums and playlists too. A product question: should Play turn shuffle off?
- **An all-missing playlist.** Play and Shuffle look enabled and do nothing, with no message. Shuffle on a one-song playlist plays it and leaves shuffle on.
- **Track 0, disc 0, odd numbers.** Track 0 sorts first and shows “0”; a negative number sorts first; a zeroed mp4 `trkn`/`disk` atom and the text `0/12` both store 0, not “none” (read from the extractor, not run). Songs tagged disc 0 play before songs with no disc tag (which count as disc 1). Four-digit numbers in the 34 pt column were not rendered — check live.
- **A compilation’s album page** never names a song’s artist (only the Info popover does). Carried in.
- **A removed cursor row.** After a reload removes the cursor row and every selected row, the ring goes back to the first row. By the kit’s documented rule.
- **Type-to-select.** Case, accents, width, decomposed text and Hangul all match. Letters that are not accents do not: “o” misses “Øye”, “l” misses “Łódź”, “ae” misses “Ægis”. A title that starts with a space, a bracket, “…” or an invisible mark can’t be reached by its first letter.
- **A tab switch** rebuilds the page: scroll place and selection are lost. Songs is the same; only the grids restore their place.
- **A failed playlist delete is silent.** `PlaylistsModel.deletePlaylist` sets `treeState = .failed`, which no view reads. Carried in.
- **A text drag onto a rail playlist.** The drop type is a plain string, so text such as “42” dragged from another app may add library song 42. Not run. Carried in (S10.3).

## What held up

- **Play from a row.** `playFromRow` resolves by id: a row a reload removed plays nothing, the last row starts at the last song (the queue is still the whole page), an empty page plays nothing, and the start index is clamped. No stale-index path exists.
- **Selection kit under reloads.** 3,000 random runs of 40 steps (clicks with ⇧ and ⌘, arrows, Page, Home, End, ⌘A, Esc, Return, and reloads that add, remove and reorder rows): no trap; a move always lands on a shown, selected row; Return never plays a hidden row; the cursor is always a shown row and, when anchored, a selected one. Home and End on an empty list move nothing.
- **Album order is stable.** 400 shuffles of 30 awkward titles (accents, width forms, digits, CJK, empty) gave one order. Duplicate track numbers and equal titles keep the read order.
- **One section per album** when its songs arrive apart; a one-song album and an empty page lay out correctly.
- **Speed (debug build).** 100,000 songs: album layout 0.56 s, artist 0.32 s, genre 0.06 s; a 20,000-song untagged album 0.17 s.
- **Sheet dismissal.** On the replica, once the sheet is dismissed its content does not redraw: no flash of the other dialog and no click lands on it, for a failure alone and for a confirmed Remove.
- **Deleting the open playlist.** `closeDetail` bumps the epoch, so a load in flight can’t bring the rows back; the page shows a spinner for the length of one tree read before the rail returns to the category.
- **Concurrency.** The sprint adds no `didSet` and two task spawns. A superseded page load publishes nothing (`Task.isCancelled` is checked after the read).
- **Decision 12.** A compilation is one album under Various Artists; its 0-song artist entry stays hidden from the Artists grid.

## Not covered

- The live UI, VoiceOver and the look of anything (the coordinator’s pass). Please confirm 8 and 13 on the real app.
- `PlaylistsModel`, `DetailTrackList` and the dialogs have no importable test target, so 8, 9 and 11 to 13 rest on code reading and replicas.

## Run it again

- `swift test --filter BreakItTests` — the eight red tests.
- `swiftc -swift-version 5 break-it-e-evidence/seam-replica.swift -o /tmp/seam && /tmp/seam`
- `swiftc -swift-version 5 break-it-e-evidence/sheet-replica.swift -o /tmp/sheet && /tmp/sheet both` (also `failure`, `confirm`). Both replicas keep their windows invisible and off screen and never take focus.
