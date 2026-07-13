# S10.2 — Queue UX (design)

**Document ID:** S10.2-DESIGN-001
**Status:** DESIGN — team-vetted (BA · swift-expert · swiftui-pro) + **architect + the-fool gate: GO-WITH-CHANGES** (7 must-fixes folded in). **Pending founder brainstorm BEFORE implementation** (§0). Then implement → QA break-it pass → founder manual test → retro.
**Sprint:** S10.2, second of the S10 series — see [s10-queue-playlists-macos-plan.md](s10-queue-playlists-macos-plan.md). **Depends on S10.1** (playlist store spine + the built-in "current" playlist).
**Authored by:** AdaptiveSound team — business-analyst, swift-expert, swiftui-pro, architect-reviewer + the-fool (gate), synthesized by the orchestrator.

---

## 0. Decisions needing the founder (brainstorm before code)

**The crux:** S9 made the queue **ephemeral**; S10.1's "current" playlist is **persistent** and you decided "queue = the current playlist." S10.2 wires them together. Calls:

1. **⭐ Does the queue persist across quit/relaunch?** — **Recommend YES.** *(This reverses S9's ephemeral-queue AC — a deliberate, founder-approved change.)*
2. **⭐ Restore behavior on relaunch** — **Recommend restore-PAUSED** at the saved track + offset (Music.app-like; never auto-blasts audio). Alternatives: (b) auto-resume playing; (c) content persists but launch stopped at the top.
3. **⭐ Allow the same track more than once in the queue?** — **Recommend YES** (the point of the entry-id model; matches Music.app). Behavior change to note: "Add to Queue" of an already-queued track now adds a **second copy** (today it's a silent no-op); the toast becomes a truthful "Added 1."
4. **⭐ History — session-only vs all-time, and does "Clear Queue" also clear history?** — **Recommend session-only, via a separate history log, and Clear Queue leaves history intact** (offer a separate "Clear History"). *(Gate correction: history is NOT the played prefix of the queue — that breaks under shuffle (cursor jumps) and repeat-all (cursor wraps). It's a separate append-on-completion log.)* All-time history deferred (US-PLAY-10).
5. **⭐ Acknowledge: DUR-1 now reaches the queue.** Once the queue is durable, it rides the same self-erasing DB (`eraseOnSchemaChange` still true, DUR-1): a **pre-R1 schema change will wipe saved queues**, and a naive future migration could id-churn so restore-paused resumes the *wrong song*. Accepted pre-R1 consequence — not silent. Reinforces that **DUR-1 must be solved before R1**.
6. **File deleted on disk while queued** → **Recommend tolerate** (skip-on-play-fail + advance; the stale row lingers visibly until played). Live-reconcile deferred.

*Mechanism (team decision, not founder): the queue mirrors to the "current" playlist via a **debounced full-snapshot resync** (§2); the now-playing cursor lives in UserDefaults (no schema change).*

---

## 1. Scope

| In S10.2 | Deferred |
|---|---|
| `playlist:[AudioFile]` → `queue:[QueueItem]`; **debounced full-snapshot mirror** to the "current" playlist | Save-queue-as-named-playlist, drag into *other* playlists, non-library-file add UI, M3U → **S10.3** |
| Re-platform reorder / play-next / play-this-now / add / **clear** onto the mirror | A–Z rail, folder-browse → **S10.5** |
| **History** (separate session append-log) + Up Next｜History UI | Media keys / Now-Playing/Control Center → **S10.4** |
| **Drag-to-queue from the library** (deferred S9 carry-over) | All-time history (US-PLAY-10); live reconcile of a queued file deleted on disk |
| Relaunch hydration (restore-paused); allow duplicates | — |

**Reverses a prior decision:** S9's ephemeral-queue IA ([s9-library-ia-queue-design.md](s9-library-ia-queue-design.md)) → persistent (annotate that doc as superseded by §0.1).

## 2. Model — hybrid queue with a debounced full-snapshot mirror

The **in-memory array + `Int` cursors stay authoritative for playback** (PlaybackQueueKit's index math untouched → gapless/advance byte-for-byte S9). The **"current" playlist is a durable mirror**, treated as a **rebuildable cache that always re-derives from the authoritative in-memory queue**:

- On any *edit*, mutate the array synchronously on `@MainActor`, then (debounced) issue **one** `replaceCurrentQueue(trackIDs: queue.map(\.trackID))` — a full snapshot. No per-entry deltas, no `entryID` round-trip, no serial patch-back chain.
- On any mirror error: **log it and re-issue the snapshot** (the recovery path *is* the normal path). Never `try?`-swallow.

```swift
struct QueueItem: Identifiable, Sendable {
    let id: UUID          // STABLE SwiftUI identity (allows duplicate files; survives across edits)
    let file: AudioFile   // what the engine plays (URL-keyed; unchanged)
    var trackID: Int64?   // durable tracks.id — snapshot payload + play-count + delete-reconciliation
}
```
`AudioViewModel.playlist:[AudioFile]` → `queue:[QueueItem]`; `selectedTrackIndex`/`pendingNextIndex` stay `Int` (PlaybackQueueKit unchanged). **`entryID` dropped** (the snapshot doesn't need stable slot ids; the cursor keys on the persisted *position*).

*Why snapshot over per-op deltas (gate rec #3): the delta model bought stable entryIDs that nothing at runtime consumes, at the cost of a provisional-id window, a serial mirror chain, patch-back, and a reorder-before-append-acks ordering hazard — all of which vanish with a debounced snapshot. At the "low hundreds" target a clear+append burst off-main is negligible.*

## 3. Op mapping
Every verb: mutate the in-memory array synchronously (PlaybackQueueKit logic unchanged), then schedule the debounced snapshot.

| Verb | In-memory (unchanged) | Persistence |
|---|---|---|
| Play Now / replace · Play Next · Play-This-Now · Add · Reorder (by `QueueItem.id`) · Remove | existing `AudioViewModel+Queue`/`+Playlist` logic, over `queue[i].file` | → schedule debounced snapshot |
| Clear | `queue.removeAll(); stop` | `clearEntries(playlistID:)` (explicit, immediate) |
| Advance (auto/gapless) | cursor `±1` only | **nothing** — rows don't change |
| History | append `queue[cursor]` to a separate `history:[…]` log at natural-completion (cap ~100) | own persistence (UserDefaults/JSON) or session-only; **not** the queue prefix |

## 4. DAO additions (`LibraryStore+Playlists.swift`, additive)
- `replaceCurrentQueue(trackIDs:) async throws` — clear "current" + append all, one txn (the snapshot primitive; entryIDs no longer returned/needed).
- `clearEntries(playlistID:) async throws` — one `DELETE … WHERE playlist_id=?` (explicit Clear).
- `incrementPlayCount(trackID:)` overload — closes the S9.5 url→id play-count seam (optional polish; url path already works).

No schema change (v3 suffices). `insertEntries`/entryID-patch from the earlier draft are **dropped** (snapshot mirror doesn't need them).

## 5. UI (extend the Now-Playing List, don't rebuild)
Keep **`List` (not `Table`** — no `.onMove`/scroll-to-row on macOS 26). Add an **Up Next｜History** segmented picker; a header **⋯ menu** (Clear Queue [destructive]; Save-as-Playlist → S10.3 stub); a reverse-chron **history** list (the separate append-log) whose rows requeue via context menu. Row menu mirrors browse verbs. **Drag-to-queue from library:** browse cells `.draggable` a `Codable` payload of durable `tracks.id`/`album.id`; the always-visible footer **`NowPlayingBar` is the drop target** (append + reuse `QueueToast`). **A11y:** ⌥↑/↓ + "Move Up/Down" actions (native drag is invisible to VoiceOver); Reduce-Motion-gate the jump-scroll; keep the no-`List(selection:)` single-click-plays model.

**Dup-identity surface sweep (must-fix #6 — all move off URL):** the `ForEach` id (`PlaylistView.swift:145`), the S9 `dedupedAgainstQueue` guard (`AudioViewModel+Queue.swift:143-146`, delete it), `movePlaylistItems` re-anchor (`+Playlist.swift:9-15`), the **Info popover binding** (`PlaylistView.swift:182`, else it pops on all duplicate rows), and **`.onChange(of: …map(\.id))`** (`:226`) → all key on `QueueItem.id`, not `AudioFile.id`/URL.

## 6. Auto-advance / gapless — unchanged
Advance mutates **only the cursor**; no store call on the 20 Hz seam. Persistence rides the *edit* path + *launch* only.

## 7. Concurrency
Mutate in-memory synchronously on `@MainActor`; the mirror is a **single debounced Task that cancels its predecessor** and snapshots the current authoritative array (no chain, no patch-back). The store serializes writes on its `DatabaseWriter`. On error → log (`logUX`) + mark dirty + re-snapshot.

## 8. Relaunch + quit
- **Hydrate (must-fix #5 guard):** on store-ready, load `currentPlaylistID` → `entries` → resolve to `QueueItem`s; set the cursor from the saved UserDefaults `{entryID/position, offset}`; **leave `isPlaying=false`**. A `pending/hydrated/superseded` state ensures a user edit that lands before store-ready **cancels** the hydrate (never clobbers a just-started album). Stale saved cursor → fall back to top, offset 0.
- **Quit (must-fix #4):** there is **no `applicationWillTerminate`** — `shutdown()` (already awaited by `applicationShouldTerminate`, `AppDelegate.swift:46-56`) must **await the mirror tail / issue a final snapshot and persist the cursor** before returning, so the last edit isn't lost on ⌘Q.

## 9. Risks
1. **Dup-identity flip is mandatory + wider than one site** — §5 sweep (ForEach, dedup guard, movePlaylistItems, Info popover, onChange). Miss one → duplicate-row crash or cursor mis-point.
2. **Silent mirror drift** — killed by §7 (log + snapshot resync; never `try?`).
3. **File deleted while queued** → skip-on-play-fail + advance (§0.6); live-reconcile deferred.
4. **Scan-folder removed while queued** — safe (Gate-1 keeps the track loose).
5. **DUR-1 reaches the queue** (§0.5) — durable queue on a self-erasing DB; must be solved before R1.

## 10. Definition of Done
`VerifyLibraryStore` checks for the new DAO ops (`replaceCurrentQueue`/`clearEntries` + `incrementPlayCount(trackID:)`); VM-level queue tests (incl. append-then-immediate-reorder persisted-order, and quit-flush); **QA break-it pass** (qa-expert + the-fool) after implementation; `make gate` + `make strict-gate` green; **founder manual testing** (reorder/add/play-next/clear/history/drag-to-queue + quit→relaunch restore-paused — the first S10 sprint with a UI to drive). Retro.
