# S10 — Queue + playlists + macOS control (sub-sprints S10.1–S10.6)

**Document ID:** S10-PLAN-001
**Status:** S10.1 ✅ + S10.2 ✅ shipped & merged; **S10.6 (Recently Played) in design → then S10.4**; S10.3 still open. S10 runs as **individual done-done sub-sprints** (S10.1–S10.6), each via the **usual development process** (vetted design → multi-SME review panel → architect + the-fool gate → build-enforced gate + commit). *(Authoritative project status: [sprint-plan.md §Status](sprint-plan.md). Deprioritized 2026-07-14: drag-from-Library-into-queue + M3U/M3U8 import-export.)*
**Relates to:** [sprint-plan.md](sprint-plan.md) — the S10.x sprint series, the last work before **Release R1**.
**Depends on:** S8 (library spine, GRDB store) ✅, S9 (browse/search) ✅.

> **Why five sprints (founder decision):** the founder-locked playlist stories alone (EP-PLAYLIST, US-PLIST-01…08 in [backlog.md](../product/backlog.md)) total **~26 SP**, before queue UX, M3U, media keys, and browse polish — far past one 5–10 SP sprint. So the original single "S10" is split into the five individual sprints below (~31 SP total), each independently done-done. Sub-numbered `S10.x` deliberately, to avoid renumbering S11–S18 and the R1/R2/R3 anchors. **R1 gates on S10.1–S10.4** (S10.5 is polish).

---

## The sub-sprints

| Sprint | SP | Scope (line item) | Key stories | Depends on |
|---|---|---|---|---|
| **S10.1** ✅ | 8 | **Playlist/queue persistence spine** — `playlists` + `playlist_entries` tables (GRDB, delete-rebuild migration; keyed on `tracks.id` with a `position` + own entry id so a track can repeat); DAO for create/rename/delete + ordered add/remove/reorder + loose-file add; the built-in non-deletable **"current"** playlist; `untitled-N` lowest-unused naming; **closes Gate 1** (`unreferencedTrackIDs` gains `AND id NOT IN (SELECT track_id FROM playlist_entries)`). Gated by `VerifyLibraryStore`. | US-PLIST-01, -05, -06 (store), -07; known-issues **SEQ-1 Gate 1** | S8.1 store |
| **S10.2** ✅ | 6 | **Queue UX** — persistent play queue (the "current" playlist; survives quit/relaunch, restore-paused); Up Next｜History + session history; Clear Queue; reorder (grip-drag + context-menu + keyboard); wires to `PlaybackQueueKit`. *(drag-from-Library-into-queue deprioritized 2026-07-14 — Play Next / Add to Queue verbs cover add.)* | US-PLIST-06 (UI), US-PLAY reorder/history | S10.1 |
| **S10.3** | 6 | **Playlists UX** — playlist browse/sidebar (create/edit/rename/delete, scales to hundreds); add songs → playlist as a **reference-add, never a file move** (separate handler from folder-move); add a single non-library file. *(M3U/M3U8 import-export deprioritized 2026-07-14.)* | US-PLIST-02, -03, -04; + the US-PLIST-08 cross-seam test | S10.1 (+ S8.4 ✅ for -08) |
| **S10.4** | 5 | **macOS system control** — media keys + Now-Playing / Control Center (`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`); app-wide keyboard shortcuts. Independent of the persistence spine. | (new — trace to sprint-plan S10.4) | S9 |
| **S10.5** | 3 | **Browse polish** — folder-browse mode; the **deferred A–Z jump rail** from S9. *(Polish — not an R1 gate.)* | (S9 carry-overs) | S9 |
| **S10.6** | 5 | **Recently Played (frecency)** — rework the S10.2 History tab into an all-time, per-track, **frecency-ranked** "Recently Played": persisted play count (a play = **≥60% heard, ~4-min cap**, cumulative), decayed-score accumulator column (`frecency_score`, schema v4, 7-day half-life), dedicated read + `RecentlyPlayedRow`. Design: [recently-played-frecency-design.md](recently-played-frecency-design.md). *(Added 2026-07-14; enhancement, not an R1 gate.)* | US-PLAY-10 | S10.2 |

---

## Per-sprint notes

- **S10.1 is the enabler and comes first.** Everything else depends on the playlist/queue tables, and it's also the only thing that **closes the open hard-gate** (SEQ-1 Gate 1) — until `playlist_entries` exists, removing a scan-root can delete playlist-referenced tracks. So S10.1 is both the data spine and a data-integrity fix.
- **S10.2 and S10.3** both build on S10.1 and can run back-to-back (or parallel if capacity allows). The **drag distinction** is load-bearing: dropping into a **playlist** is a reference-add (S10.3), dropping into a **scan folder** is a potential real move (already handled by S8.4) — the UI must make the two drop targets visually unambiguous, and the code paths stay separate (US-PLIST-04).
- **US-PLIST-08** (playlist membership survives a folder→folder move) is the **cross-seam integration test** tying S8.4's move-detection to S10.1's membership model. S8.4 already shipped, so it's verifiable once S10.1 + S10.3 land; flag it in planning as "not in Definition of Done until both sides exist."
- **S10.4** is independent — it can be built any time (doesn't touch the store), so it's a good parallel/fill-in sprint.

## Founder decisions to lock during S10.1/S10.3 design
- **Duplicate playlist name** handling (US-PLIST-05): auto-suffix vs. reject-with-inline-message — pick one (some collision handling is required; the choice is a UI decision, not yet pinned).
- **`untitled-N`** numbering: lowest-unused vs. monotonic counter (open in US-PLIST-05).

## Definition of done (per sprint)
Each sprint: design vetted → SME review panel → architect + the-fool gate → implemented → `make gate` green (C++ null-test + `VerifyAUGraph` + `VerifyLibraryStore`) + `make strict-gate` → founder by-ear/by-hand where applicable → commit. **Release R1** ships after S10.1–S10.4 are done-done.
