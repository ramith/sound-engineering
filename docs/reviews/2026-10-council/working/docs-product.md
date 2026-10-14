# Product docs reconciled to the code — council report (docs-product)

**Scope:** `docs/product/PRD.md`, `requirements.md`, `user-journeys.md`, `backlog.md`, `known-issues.md`.
**Ground truth:** `main` at a206107 (R1 = v1.0.0-alpha; release PR #87 merged, tag pending a green CI — wording aligned with
the sprint plan on `docs/council-recon-arch`).
**Branch / worktree:** `docs/council-recon-product` in `.claude/worktrees/docs-recon-product` (not pushed).
**Method:** every requirement, journey, story and known issue checked against the source with grep and reads (file:line in
the docs). The ~45 logged post-R1 items were re-verified item by item (three read-only verifier agents plus my own spot
checks of every cited line). The arch agent's two findings (multichannel truncation, Opus not scanned) were verified
before being added.

## Commits (oldest → newest)

| Hash | What |
|---|---|
| 50b6f5a | known-issues: the open post-R1 list (severity, file:line, forward link), closed items, limitations, SEQ-1 / ENH-001 corrections |
| 3f60204 | backlog: status + back-link / forward link on every story; Post-R1 fix pool; US-QA-07, US-REL-01/02; stale anchors fixed |
| bdb32c0 | requirements: §3.0 status matrix for all FR / NFR; as-built notes on deviations; OQ-07 / OQ-17 resolved; ASM / DEP / CON fixed |
| a7ca2a4 | user journeys: statuses re-verified; Journeys 2.8 (library), 2.9 (playlists), 2.10 (Pure Mode) added |
| d1e91b8 | requirements: journey table lists 2.8–2.10 |
| 0382a3e | requirements: §3.0 short, stable heading |
| 5791c5a | PRD: as-built column on the Phase 0 / 1 feature tables; as-built notes on LD-9 / 16 / 19, §1, §3b, §5, §6, R-10, Decision 3 |
| 5294c79 | backlog + known-issues: the S9 IA change named with its PR (#23) |
| cb471f2 | known-issues: KI-MC-01 (multichannel on a stereo output) + the lossy-gapless limitation narrowed |
| 1a50f7e | backlog: US-R1F-08 (KI-MC-01 decision) + US-PLAY-07 narrowed by the code |
| 31d4c16 | requirements + PRD: KI-MC-01 on FR-SPAT-07; "R1 release in progress" wording |
| 03f2448 | US-R1F-08 / KI-MC-01: the S4 design's own fold named as the first interim option |

No Co-Authored-By trailer; no `--no-verify` (the hook passed on every commit; it does not lint markdown). All relative links in
the five files resolve (checked after every commit).

---

## 1. Per document

### known-issues.md — MATCHES 2 · STALE 1 · WRONG 2 (+ ~42 open issues that were missing)

- MATCHES: DUR-1 (closed), ENH-002 (still L/R-only, `AudioEngineBridge+Graph.swift:170-173`).
- STALE: SEQ-1 Gate 1 — the filter now counts **user** playlists only (PR #85, ff0e0da; `LibraryStore+DAO.swift:365-366`). Annotated.
- WRONG: the header's promise that each entry is guarded by `withKnownIssue` (zero uses in `Tests/`); ENH-001's "guarded by
  `VM-AA-RTR-1` withKnownIssue" (dropped in c63ba7f). Both corrected with strike-through.
- **Notable change:** the page is now the open list the R1 release notes link to. **44 open entries** (2 HIGH-by-council +
  1 HIGH logged + 18 MEDIUM + 19 LOW + 4 internal), an at-a-glance table, each with file:line, source and forward link;
  a **Known limitations** table (not notarized, Pure on Bluetooth, no single-file open, copy-then-delete moves, FFmpeg-fallback
  gapless trim, DSD); a **Closed** section (the 13 Sprint G blockers, the freeze, and 6 logged items found already fixed:
  G-LIB-03 ad2ee3c, the Pure alive-listener leak a4c5bc1, audit S1-E cc976dc, `withExtendedLifetime` 69b94aa/cc976dc, the R10
  stall test a861cc6, Pure resume intro 92c1801).
- Of the logged post-R1 items: library 13/14 still open, playback / shell 9 open + 1 partly fixed / 11, ledger + freeze +
  evidence 15 open + 1 partly fixed + 4 fixed + 2 not judgeable from code / 22.

### backlog.md (114 stories + spikes) — MATCHES 69 · STALE 40 · WRONG 5

- WRONG: **US-PLAY-01** ("Opus replaced OGG on the shipped list" — the scan admits `ogg` and not `opus`); **US-QA-02** (proven-by
  "`VerifyAUGraph` FR sweep" — it is `Tests/EqFrequencyResponseSweepTests.inc`); **US-TON-06** (`EQPresetPickerView` doesn't
  exist); **US-RMG-01** (`NowPlayingWidget` doesn't exist); **US-LIB-02** (AC: the single-file path "must keep working exactly as
  it does today" — it was removed in PR #23 and never replaced).
- STALE (shipped or changed, not marked): US-ENG-01/02/03/04/06 (shipped), US-ENG-05/08/09 (Sprint EQ decisions 29/25/26/33),
  US-PLAY-02/03/04/10 (shipped), US-PLAY-05 (partly), US-PLAY-07 (narrowed: AAC/MP3 already trimmed by Apple), US-TON-01
  (Sprint EQ rebuild), US-DEVICE-01 (shipped), -02/-03 (partly), -07 (OQ-17 resolved), -09 (Sprint G rework), US-UI-01/02/04/05,
  US-PRIV-02 (superseded: Developer-ID, S8.1 D5), US-LIB-01/03/04/05/06 (shipped), US-LIB-07 (superseded: S10.5 cut),
  US-PLIST-01/04/07/08 (shipped), -03/-06 (partly), -05 (Apple-style "New Playlist" naming), US-PROF-02 (partly: hold-Compare),
  SPIKE-LIBBS2B (resolved by QW1 §2); the "none are Done" note on the library section.
- **Notable changes:** a dated status line on every story (71 lines); an epic-status table; the status rule amended to carry PR
  back-links and a "Partly shipped" value; reversed decisions struck through, not deleted; open-items table updated (OQ-07,
  OQ-17 resolved; hearing-safety spike re-scoped — those clamps are design-only; new licence row).

### requirements.md (85 FR / NFR + LD / ASM / CON / DEP / OQ registers)

- FR / NFR — MATCHES 74 · STALE 11 · WRONG 0. STALE (a founder decision changed the target): FR-PLAY-01 (formats / scan),
  FR-SPAT-03, FR-TONAL-01/06/07, FR-ADAPT-03, FR-REIMAGINE-02, NFR-QUAL-03 (decision 25), FR-UI-01 (20 Hz, no decision),
  NFR-PRIV-05 (superseded), NFR-INSTALL-04 (App Support data stays).
- Registers — STALE 6 (LD-16, LD-19, OQ-07, OQ-17, DEP-16, CON-12) · WRONG 3 (ASM-01 "macOS 14" → macOS 26; DEP-09 TPCircularBuffer
  not used; DEP-11 "libebur128 replaces bespoke LUFS" → the runtime meter is in-house, libebur128 is test-only) · the rest MATCH.
- **Notable change:** **§3.0 Requirement status matrix** — every FR / NFR: Delivered / Delivered† / Partial / Not built / Won't /
  Superseded / N/A, the code location + PR back-link, and the S11–S18 or backlog forward link. As-built notes in place on the
  deviating requirements; v0.8 change note.

### user-journeys.md (7 journeys + header) — MATCHES 6 · STALE 2 · WRONG 1

- WRONG: header "four-tab window" (it is five, with the Library).
- STALE: 2.3 (what the relaunch restores; chain), 2.4 (stale file names; Step 4's toast is built; device loss now pauses).
- MATCHES: 2.1, 2.5, 2.6 (still unbuilt — forward links added), 2.2 / 2.7 (withdrawn), cross-references.
- **Notable change:** Journeys **2.8** (add music and play from the library), **2.9** (curate a playlist), **2.10** (Pure Mode) —
  the flows R1 is built around, which no journey covered; each with gaps linked to KIs / stories.

### PRD.md (19 LDs, 28 Phase 0/1 feature rows, ~12 narrative claims) — MATCHES ~47 · STALE 9 · WRONG 1

- WRONG: §6's premise ("the licence only needs to be in place before the repository is made public") — the repo is public, R1
  is being released, and there is no LICENSE file (see finding F6).
- STALE: LD-16 + §3b (decision 25), LD-19 (menu-bar extra is transport only), §1 (what R1 ships), the competitive table's
  Adaptive Sound column (target, not shipped), §5 KPIs (no telemetry → unmeasurable), Decision 3 (R1 distribution), R-10
  (actual dependencies), the phasing appendix.
- **Notable change:** an **As-built (2026-10-13)** column on the Phase 0 and Phase 1 feature tables (shipped / partial / not
  built, PR back-links, S11–S18 forward links); the vision text is untouched.

---

## 2. CODE-LOOKS-LIKE-A-BUG findings (described in the docs, raised here)

New in this reconciliation (not in any earlier list):

1. **F1 — HIGH (needs a live check on a USB DAC): Pure ignores a changed next track while another is armed.** Pure's gapless deck
   refuses a second arm — `pureModeEngineArmOpenedNextTrack` returns an error (`AudioDSP/PureModeBridge.cpp:357-362`;
   `GaplessSource::armNext`, `GaplessSource.cpp:124-129`). The VM's re-arm (`armOnDeck`, `AudioViewModel+Queue.swift:195-201`)
   pushes the new URL without clearing; `setPureNextTrack` clears only for `nil` (`AudioEngineBridge+Gapless.swift:94-100`). So a
   mid-song Repeat / Shuffle change (the PR #85 B6 fix) or a queue edit on Pure leaves the old next track armed; at the seam Pure
   plays it while the VM names `pendingNextIndex`. Violates FR-PLAY-03. → KI-PB-01, US-R1F-01.
2. **F2 — HIGH: a 5.1 / 7.1 file on a stereo output plays only front L / R** (also the arch agent's F1, verified here). M =
   min(N, device) (`AudioFormatKit/MultichannelFormat.swift:89-104`); for M < N `routeBinauralStub` copies the first M channels
   and discards the rest (`AudioDSP/Spatial/SpatialRenderKernel.cpp:59-89`); the MPEG 5.1 order is L R C LFE Ls Rs
   (`MultichannelFormat.swift:53`) — so the centre / vocal is gone. The release notes advertise "up to 7.1". → KI-MC-01,
   US-R1F-08 (founder decision: pull the S4 design's `AVAudioEnvironmentNode` fold forward, an interim BS.775 fold, or warn),
   final fix S18. (I rate it HIGH on the user-severity scale; the arch report calls it SIGNIFICANT on the code-review scale.)
3. **F3 — MEDIUM: crossfeed is unavailable on wired headphones in the Mac's own jack.** "Headphones" = USB or wireless transport
   (`AudioViewModel.swift:159-171`); the type is transport-only (`AudioDSP/CoreAudioDevice.cpp:321-354`); the built-in jack
   reports the built-in transport, so crossfeed is disabled with "Connect headphones". AirPlay speakers count as headphones.
   Violates FR-SPAT-03 / FR-DEVICE-03. → KI-DEV-01, US-R1F-06.
4. **F4 — MEDIUM (requirement not delivered; a doc claims it is): no way to play a single file, or add a non-library file to a
   playlist.** The store supports it (`LibraryStore+DAO.swift:226` `addLooseFile`; `LibraryStore+Playlists.swift:422`
   `addLooseFileToPlaylist`) but nothing in the app calls them: no Finder drop target, no Open…, no `CFBundleDocumentTypes` /
   `application(_:open:)`; the only `.fileImporter` on a playlist is Locate… (`PlaylistDetailView.swift:55`); the queue mirror
   comments that "there is no loose-file queue entry point in the UI today" (`AudioViewModel+QueueMirror.swift:40-44`). The old
   folder-chooser entry was removed in PR #23 (7058667) without a replacement. US-LIB-02 / US-PLIST-02 are Must stories, and
   `sprint-plan.md`'s S10.3 row says "add a single non-library file" shipped. → backlog statuses + known limitation.
5. **F5 — LOW (spec ↔ code, no recorded decision): the analyzer updates at 20 Hz**, the shared main-thread tick
   (`AudioViewModel+SpectrumTimer.swift:35`), where FR-UI-01 / architecture §14 say ≥ 30 fps. Either record it as a decision or
   raise the rate.
6. **F6 — process / legal (not code): the public repository has no licence.** `gh repo view` → `visibility: PUBLIC`,
   `licenseInfo: null`, no LICENSE file; PRD §6 required one before going public; R1 is being released from it. → US-REL-02.
7. **F7 — doc fact: ENH-001's guard test is not a guard.** `VM-AA-RTR-1` (`Tests/AudioViewModelTests/AutoAdvanceReconfigureGapTests.swift:88`)
   lost `withKnownIssue` in c63ba7f; nothing fails when the seamless fix lands. Corrected in known-issues.

Already logged (Sprint G break-it / freeze lists), re-verified still present, and requirement-relevant — the most serious:
KI-LIB-01 (HIGH, "Remove Missing…" deletes entries of an unplugged drive, `PlaylistsModel+DeadFiles.swift:33-34`), KI-SET-02
(MEDIUM, a Master Gain cut doesn't carry into Pure — hearing-safety adjacent), KI-PB-03 (shuffle + repeat off never ends,
`QueueAdvance.swift:38-45`), KI-GAP-01 (48 kHz seam gap), KI-SET-01 (settings reset every launch). Full list with evidence in
`docs/product/known-issues.md`.

---

## 3. New backlog items added

All in `backlog.md` → "Post-R1 fix pool *(new — 2026-10-13)*", Planned and unscheduled (scheduling is the re-plan's call):

| ID | Covers |
|---|---|
| US-R1F-01 | Transport and queue correctness — KI-PB-01, -03, -04, -05, -06, -07, -08, -09, -10, -14 |
| US-R1F-02 | Seamless seams — KI-GAP-01..03, KI-PB-02, ENH-001 (candidate for S11) |
| US-R1F-03 | Library honesty and safety — KI-LIB-01..03 |
| US-R1F-04 | Library and playlist polish — KI-PB-11..13, -15, KI-LIB-04, -06..10 |
| US-R1F-05 | Keep the listening settings; one honest level — KI-SET-01..03 |
| US-R1F-06 | EQ and output-device fixes — KI-DEV-01/02, KI-EQ-01..03 |
| US-R1F-07 | Engine and test-harness hygiene — KI-ENG-01..04, KI-UI-01, ENH-002 (links the parked concurrency cleanup) |
| US-R1F-08 | Multichannel on a narrower output until S18 — KI-MC-01 (with the founder decision) |
| US-QA-07 | THD+N oracle — the one S7 oracle never built (NFR-QUAL-01), candidate for R2 |
| US-REL-01 | Developer ID signing + notarization (decision 13), with the FFmpeg `dlopen` entitlement |
| US-REL-02 | Choose and add the OSS licence (F6) |

Existing stories that are not delivered and have **no** S11–S18 sprint (left Planned, marked "unscheduled" / post-R1 pool):
US-LIB-02, US-PLIST-02, US-LIB-08, US-PLIST-06's "save queue as playlist", US-TON-04, US-TON-05, US-ADAPT-01/02, US-DEVICE-06
(speaker side), US-DEVICE-08, US-HT-01, US-AMB-01, US-UI-03, US-UI-06, US-PRIV-01, US-PRIV-03. Also: **CUE has no backlog story**
though S11 owns it (the arch agent's note; not added here — it is S11 planning).

---

## 4. Links I couldn't resolve

- **None broken** in the five files (relative links and the anchors I added checked against GitHub slug rules).
- Non-link references that live **off main**: the Sprint G red tests / VM harness (`Tests/BreakItG/…`, `LibraryGenreNamesGTests`)
  exist only on the reference branches `breakit/s10-8-g-playback-shell` / `breakit/s10-8-g-library`; the docs say so.
- The `v1.0.0-alpha` tag / GitHub release does not exist yet (`gh release list` is empty); the release-notes file link resolves.
- `UX-guidelines.md` and `Test-and-qa-strategy.md` (user-journeys cross-references) were never written; annotated, pointing to
  the docs that exist.

## 5. Consistency with the arch branch

Read `docs/council-recon-arch`'s sprint-plan / roadmap diff. Aligned: "R1 = v1.0.0-alpha — release in progress (tag pending)";
S11's code fact on AAC/MP3 trim (US-PLAY-07 narrowed to match); S13's "auto-load by identified output delivered early" (matches
US-DEVICE-02's partial status); S18 "replaces the M < N truncation" (KI-MC-01 forward link); "Logged after R1 … not yet scheduled"
(= the Post-R1 fix pool). The arch branch references backlog IDs only (no anchors), all of which still exist. One divergence to
reconcile at merge: sprint-plan's S10.3 row still says "add a single non-library file" and S10.1 "`untitled-N` naming" — the code
has neither (F4; "New Playlist" naming).
