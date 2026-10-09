# S10.8 part 2 plan — the glass sweep: every remaining screen onto the shipped glass

> Status lives in [sprint-plan.md §Status](sprint-plan.md#status), not here. This doc carries
> the sweep's scope, decisions, sprint breakdown, exit criteria and acceptance checks. Per-sprint
> evidence, the filled acceptance matrix and the mini-retros live in the sweep ledger
> (`s10-8-sweep-ledger.md`, opened with Sprint A).
> **Design sources of truth:** the shipped Now Playing and Library › Songs screens, and their
> founder packages — [now-playing-realigned/](../design/now-playing-realigned/README.md) and
> [library-twin-panels/](../design/library-twin-panels/README.md). Both packages are
> dark-only. No founder mock exists for any screen this plan covers; the glass grammar is
> [s10-7-liquid-glass-design.md](s10-7-liquid-glass-design.md) §3.
> **Review provenance (2026-10-06):** drafted from three parallel reviews — product-manager,
> ui-designer, swiftui-pro. **Gap review** by a second, non-authoring panel — architect-reviewer,
> qa-expert, accessibility-tester, the-fool pre-mortem. **Final gate:** architect-reviewer
> **APPROVED WITH AMENDMENTS**, the-fool **PASS WITH AMENDMENTS** — every required amendment
> folded in (dispositions in §J). Claims marked *verified* were re-checked in source.

## A. The plan in one paragraph

Two screens are glass today, and only in dark mode. This plan brings every other screen —
Albums, Artists, Genres and their detail pages, playlists, EQ, Monitoring, Settings — onto the
shipped glass pieces, **and** gives the whole app a designed light mode as polished as dark,
which nothing yet defines. It runs as **seven small sprints (A–G, 4–9 points each, ~45 in all)**
so each one is small enough to get right: A fixes two shipped bugs and builds the picture-sheet
renderer; B designs light mode once on the shipped screens and freezes it; C fixes album
artists; D–G restyle the remaining screens. Every sprint ends with a break-it QA pass, agent
picture sheets, a founder check of under ten minutes, and a short retro that adjusts the next
sprint before it starts. R1 ships the day Sprint G passes (no soak), on the founder's own Mac.

## B. Decisions (founder)

> **DECIDED (founder, 2026-10-06):** 1–5 = as recommended. **6 = light mode as polished as
> dark before R1.** **7 = R1 as soon as every screen passes — no soak.** Album "Unknown Artist"
> fix before R1, as its own item.
> **DECIDED (founder, after the gap review):** **9 = yes**, agent-made picture sheets. **10 =
> delay R1 until light is right.** **11 = keep today's double-click behaviour.** **12 = one
> album under "Various Artists".** **13 = not for R1** — R1 is the founder's own Mac.
> **DECIDED (founder, after the final gate):** **14 = founder check under ten minutes per
> sprint.** **15 = Now Playing accepted as it is** — "I like the current screen, let's close
> it": the 14 recorded part-1 deviations are accepted and S10.8 part 1 closes (dark); its light
> cells move to Sprint B.

1. **No mocks** — derive every screen from the shipped look.
2. **Glow on EQ, Monitoring, Settings:** one calm teal pool, mounted once behind every tab
   except Now Playing (not Now Playing's art-sampled field).
3. **EQ controls** stay under the graph; the graph grows to fill the height.
4. **Monitoring:** Before = neutral grey, After = the analyzer's teal→lime (light variant from
   Sprint B — lime is ~1.2:1 on the light lens today).
5. **Playlist rows:** the queue's 36pt card rows.
6. **Light mode** as polished as dark before R1 — designed in Sprint B.
7. **R1** as soon as every screen passes; no soak. The soak's job moves to the per-sprint
   break-it passes and the Sprint G whole-app pass.
8. *(Superseded by 9.)*
9. **Agent picture sheets** for every PR: dark / light / Reduce Transparency / Increase Contrast
   renders of each new surface and control, pre-checked by agents before the founder looks.
10. **If light mode has not come together after two Sprint B rounds:** delay R1. Any further
    round is an explicit founder decision per item (§G), never the default.
11. **Double-click** on album, artist and genre pages keeps playing the page from that song on;
    on Songs it keeps playing just that song.
12. **Mixed-artist albums with no album-artist tag** group as one album under "Various Artists".
13. **Signing and notarization** are not part of R1 (`make release` stays unsigned, *verified*);
    they become the first item of any release beyond the founder's Mac.
14. **Founder check under ten minutes:** the final look in dark and light, plus the few actions
    named for that sprint. Agents and tests fill the rest of the matrix (§G). The keyboard and
    VoiceOver walk happens once, in Sprint G.
15. **Now Playing (part 1) closed** as it is; only its light-mode pass remains, in Sprint B.
16. **Light backdrop = B, the pale glow** (picked live in the app, 2026-10-07, from A no glow /
    B pale glow / C tinted base): plain grey window, with a pale glow that brightens and never
    darkens. A and C are deleted; the light design is now frozen (§E Sprint B freeze rule).
17. **Two faint dark texts fixed** (2026-10-07, "fix both"; an exception to "dark untouched"):
    the headphones hint is no longer dimmed, and tertiary text on a selected row promotes to
    secondary. The dark selection tint itself is unchanged.
18. **Lighter routine, behaviour first** (2026-10-07, after Sprint B's "never-ending loop"
    review). Sprints C–G run the lighter routine in §D, and the behaviour the founder noticed
    in use comes before the glass looks: album artists, keyboard selection, the grid keeping
    its scroll position, moving playlist items (run order in §E). No scope added or cut.
19. **Genres becomes a tile grid** (2026-10-08, founder test-library feedback; a recorded exception
    to "no new arrangements"): Albums, Artists and Genres share ONE browse tile, a genre's art is a
    2×2 mosaic of its top album covers (a small new library read), and no Sort pill on the grids for
    R1. Design: [s10-8-browse-grid-design.md](s10-8-browse-grid-design.md). Sprint D grows by ~1–2.
20. **Arrow keys on the tile grids** (Albums, Artists, Genres) come with the keyboard work in the
    behaviour pull-forward, not after R1 (2026-10-08). About +2.
21. **The EQ is redesigned in full before R1** (2026-10-09; founder ask + market research + a DSP
    check that found today's EQ plays a fraction of what it shows). A recorded exception to "no new
    arrangements" and to decision 3. Built as **Sprint EQ** (§E); design and evidence in
    [docs/design/eq-lens/](../design/eq-lens/README.md).
22. **EQ editor: "The Lens" look, 31 draggable points only** — no five-point mode. The engine
    becomes an accurate 31-band graphic EQ so what is drawn is what plays.
23. **EQ safety: automatic headroom + a visible +12 dB ceiling;** the summed-dB clamp is retired
    (it shrank presets ~10× yet let a single +12 dB band through).

## C. Scope

*Restyle* keeps every element in its place and may **resize, fill space, or swap a control for
its glass equivalent in the same position**. A *new arrangement* — moving, adding or removing
elements — is post-R1 (sprint-plan S10.8: *no layout redesigns*). One recorded exception: the
playlist **Move Up / Down / to Top** menu items are added, because without them playlists can
only be reordered by dragging (an accessibility requirement, not a design change).

| Item | R1 | Why |
|---|---|---|
| Albums, Artists, Genres | **Must** | Founder decision: one glass card for every Library category. |
| Album / artist / genre detail pages | **Must** | Same decision. |
| Playlist, empty playlist, Recents | **Must** | The hard edge against the glow reads as a fault. |
| Library first-run, scanning, empty and no-results states | **Must** | Library guide PR-F: never a blank card. First-run is a new user's first screen. |
| Settings, EQ, Monitoring | **Must** | System blue and flat cards; up to two-thirds of each screen empty. |
| **Light mode at full parity — every screen, incl. the shipped Now Playing, Songs, nav rail and both bands** | **Must** | Decision 6. Every founder screenshot so far is dark. |
| **Keyboard: select all, ⇧-arrow, type-to-select, Home/End, Page Up/Down, scroll-into-view, a visible focus cue** | **Must** | The detail pages get these free from the system list today; reusing the Songs rows would remove them (*verified*). |
| Playlist Move Up / Down / to Top | **Must** | The recorded exception above. |
| System-drawn surfaces — sheets, alerts, popovers, the menu-bar menu, drag previews | **Must (bounded)** | Kept native (design §3.1 Regime A); only our content inside them is restyled. |
| Album-artist data fix | **Must** | Founder decision (Sprint C). |
| Release engineering (signing, notarization, a clean-Mac smoke test) | Not now | Decision 13. |
| Gold lossless tag; drag to reorder columns | Could | Deferred in the library ledger. |
| Pinned title column; column resize; new arrangements of EQ, Monitoring, Settings | Not now | Fragile, dropped, or post-R1. |

## D. How every sprint runs (the loop that keeps each chunk accurate)

**From Sprint C on: the lighter routine (decision 18).** It replaces the six-step loop below,
which ran Sprints A and B (A: 10 feature commits, 22 fix commits).

1. **Plan check:** short, by the coordinator or one agent; the founder is asked only when a
   decision changes.
2. **Build:** one agent per piece of work, in parallel worktrees when independent; each runs
   `swift build && swift test` and the linters. The coordinator merges and runs ONE
   `make strict-gate` on the merged branch, exit code read directly. Code review for logic,
   data and store changes; colour-only changes rest on the R4 audits and the sheets.
3. **Sheets:** only the screens the sprint changed; dark pixel-compared to the sprint's base.
4. **Break-it:** only for keyboard / focus, data-changing or store work — plus the whole-app
   pass in Sprint G.
5. **Founder check:** a few minutes on the changed spots (close-ups are fine).
6. **Mini-retro:** five lines in the sweep ledger.

**Fix what a person can notice:** a contrast number is an R1 item only when it is a real
readability miss (text under AA, a control or its state under 3:1) — not a hair under a target
no eye can see.

*The original loop (Sprints A–B):*

1. **Plan check (start):** before code, an agent re-reads the sprint's PRs against the current
   code and the previous sprint's retro, and corrects the scope. The founder is asked only if a
   decision changes.
2. **Build, one PR at a time:** each PR has its own todo list, is implemented by a specialist,
   reviewed by code-reviewer plus the domain expert (swiftui-pro for UI, architect for the
   store), passes `make strict-gate` with its exit code read directly, and is committed.
3. **Picture sheets:** agents render the sprint's screens and controls in every appearance and
   check them against the audits and the previous sheets.
4. **Break-it pass:** qa-expert + the-fool try to break the sprint (edge cases, interruptions,
   long names, empty states, appearance flips); findings are fixed and re-broken.
5. **Founder check (under ten minutes):** the screens in dark and light, plus the actions named
   in the sprint's "Founder checks". Every finding is tagged with the §G triage rule.
6. **Mini-retro (five lines, in the sweep ledger):** what slipped, what the next sprint changes.
   The next sprint's plan check (step 1) reads it.

## E. The seven sprints

Sizes: S = 1 point, M = 2, L = 3 (the sprint model's scale). Each PR can be reverted on its own
and ships every new piece with a consumer in the same PR (hostile Periphery).

**Run order from Sprint C (decision 18: behaviour first).** A ✅ → B ✅ → **C** (album artists,
test library) → **behaviour pull-forward**: E1 (selection kit + the full keyboard set), D6
(the grid keeps its scroll position; the Songs count line), E4's Move Up / Down / to Top
with shortcuts, and **arrow keys on the tile grids** (decision 20; its plan check decides whether
D5's `BrowseGridRoot` scaffold moves forward so the keys are wired once) → **D** (D1–D5, the Library glass) → **E** (E2, E3, E4's header and insets) →
**Sprint EQ** (decisions 21–23) → **F** → **G**. The PR tables below keep their letters; only the
order changes.

### Sprint A — foundation (7 points)

| PR | Scope | Size | Tests / audits |
|---|---|---|---|
| A1 | Card shadow on the background shape only, **set per surface role** — today's chips, device pill and queue badge get most of their visible shadow from their text (*verified*) | S | RES-06 (shadow per role) |
| A2 | **Accent tokens:** new light/dark pairs whose **dark value is today's teal** (no shipped dark look changes) and whose light value is the deeper teal (fills, tints) or the text teal (text, glyphs). The root tint and every per-site tint route through them. The teal **pill button style** (dark-on-teal text) replaces the 6 white-on-teal system buttons (*verified*) — its first consumers | M | R4-TINT-01; semgrep: no `.borderedProminent`, no `accent` in `foregroundStyle` (text and glyphs only — decorative strokes keep `accent`); the migrated sites are listed in the PR |
| A3 | Focus-ring token (≥ 3:1 against row and card, both appearances and Increase Contrast) on the four lists that switch the system focus effect off; arrow keys scroll the selected row into view (none do today, *verified*) | M | R4-FOCUS-01 |
| A4 | **Picture-sheet renderer** (debug-only, decision 9). Acceptance: whole Now Playing and Songs renders in light. If whole screens will not render, fall back to a debug flag that forces the live app's appearance. Materials (banners, toasts) and system surfaces cannot be rendered — those rows stay founder-only | M | the renderer's own smoke test |

**Founder checks:** Now Playing, Songs, the analyzer, hero chips, device pill and queue badge
look the same in dark, minus the text halos; no button has white text on teal.

### Sprint B — light mode, designed once (6 points)

| PR | Scope | Size | Tests / audits |
|---|---|---|---|
| B1 | Two or three light options rendered for the founder: no glow, depth from shadow; a pale glow that brightens the window; a tinted window base | S | — |
| B2 | The chosen light values: card separation from the window; the analyzer ramp moved into the token kit as a light/dark pair; light slider knob and track (the white knob is ~1.06:1 on the light card, *verified* by the accessibility review); Reduce Transparency and Increase Contrast looks. If a glow is chosen: the glow resolver's light rule (RES-04) and a light clamp for the album-art glow | L | R4 light rows; R4-SPEC-01 (every analyzer stop ≥ 3:1 on the lens, both modes, incl. the idle dim); R4-SLIDER-01; CARD-SEP-01 |
| B3 | Light pass on Now Playing, Songs, the nav rail and both bands — fixing what the sheets show | M | the light picture sheets |

**Bar:** the §3.2 light grammar fully applied. The effects that stay dark-only are named:
the title halo, the slider glow, the band sheen, the play-button gloss glow and the inspector
card's teal glow (grammar rule 6; the card glow shares the glow field's gate, so it carries its
own dark check — the pale light glow opens that gate in light).
How the *background glow* looks in light is exactly what B1 decides.
**Freeze rule:** after B, a light token changes only with founder sign-off **and** a re-render
of every earlier sprint's picture sheets; later sprints derive new values from the frozen ones.
**Founder checks:** pick one option (B1); approve Now Playing and Songs in light (B3).

### Sprint C — album artists, and the test library (5 points)

| PR | Scope | Size | Tests / audits |
|---|---|---|---|
| C1 | **Isolated test library:** a debug launch argument that switches the library folder, the settings store and the single-instance key together (today the database path is fixed and a second copy is blocked, *verified*), plus a generated stress library: 10k tracks, art and no art, very long / CJK / RTL / emoji names, a mixed-artist compilation, 6- and 8-channel files | M | — |
| C2 | **Album artist.** Read the compilation tag (not read today, *verified*). Albums with no album-artist tag are grouped by title + year + **folder**, then given an artist: the compilation flag or mixed artists → "Various Artists" (decision 12); otherwise the songs' shared artist. This runs as a pass after the metadata scan and again for affected albums on incremental scans. Re-processing means **re-reading tags**, so a one-time full re-read is triggered by a derived-data version bump that keeps playlists, play counts and loved flags. Amends the locked S8 album-identity decision — recorded in the S8 design doc | L | VerifyLibraryStore ALB-01 (fallback), ALB-02 (a compilation does not split), ALB-03 (user data survives the re-read), ALB-04 (one missing-artist string everywhere), ALB-05 (same-title albums in different folders do not merge) |

**Founder checks:** Albums show real artists; a known compilation shows once, as "Various Artists".

### Sprint D — Library browse (8 points)

| PR | Scope | Size | Tests / audits |
|---|---|---|---|
| D1 | The glass card mounted once for the whole Library right pane (Songs' own card removed, so it does not get two); the playlist view's opaque background deleted — **the hard edge** (*verified*) | S | R4 tertiary text on the card over the glow peak |
| D2 | Shared filter pill → Songs, queue, playlist picker | M | SLOT fit for the placeholder; semgrep: no raw text field outside the shared pill, the rename field and the Save sheet |
| D3 | Icon chip and capsule switch (required accessibility label; selection cue not by fill alone) → queue header, Songs | M | R4-SEG-02 (selected segment ≥ 3:1) |
| D4 | Card header → Songs, Albums, Artists, Genres | S | — |
| D5 | ~~Genres rows (system list replaced)~~ → **one shared browse grid** for Albums, Artists and Genres (decision 19, [design](s10-8-browse-grid-design.md)): `BrowseTile` / `BrowseArt` / `BrowseGridRoot`, fill-width columns, one-line names, the placeholder, hover plate + the A3 ring; Genres on the tile with a 2×2 cover mosaic (a new genre-cover read); first-run, scanning, empty, no-results states on the pill style | L (+1–2) | the genre-cover read: a VerifyLibraryStore check incl. its query plan + a break-it pass (store work); a 300-genre stress case; one sheet variant per grid |
| D6 | Returning from an album / artist / genre page restores the grid's scroll position (founder, Sprint A check); the Songs count line no longer wraps at 880×640 (Sprint A break-it) | M | — |

**Founder checks:** Songs → Albums → Artists → Genres, the card never moves; each has the
filter pill; the Now Playing queue header still works (D2 and D3 change it).

### Sprint E — detail pages and playlists (9 points)

| PR | Scope | Size | Tests / audits |
|---|---|---|---|
| E1 | Selection kit: the Songs rows, selection and spacing — **not** its column settings or sort — plus the full keyboard set; no visual change | L | SEL-01…08; COL-01 (detail pages ignore Songs' columns) |
| E2 | Album detail on the kit, keeping its fields, play behaviour (decision 11) and drag-to-playlist | M | PLAY-01 rows for album |
| E3 | Artist and genre detail on the kit, keeping the artist page's album grouping | M | PLAY-01 rows for artist and genre; PLAY-02 (artist queue order = shown order) |
| E4 | Playlist header, insets, Move Up / Down / to Top with shortcuts | M | — |

*SEL-01…08 as built (behaviour pull-forward, `ListSelection` in LibraryBrowseKit):* **01** click /
⇧-click / ⌘-click results unchanged; **02** ↑/↓ move the cursor and a single selection; **03** ⇧↑/⇧↓
extend from the anchor; **04** ⌘A selects exactly the filtered rows; **05** Home / End and Page Up /
Down (⇧ extends); **06** type-to-select on the displayed title (case- and accent-blind, 1 s reset; ⌘/⌃
and Space left alone); **07** Esc clears (the ring stays), Return plays the cursor row; **08** the
selection survives filtering and re-sorting, by id. **COL-01:** the kit sees only row ids and a title —
semgrep `selection-kit-no-columns` keeps Songs' columns and sort out of it.

Play contexts are added to the kit only by the PR that uses them (hostile Periphery).
**Founder checks:** a detail page opens inside the card; double-click plays from that song;
⌘A and ⇧↓ select; dragging a song into a playlist still works.

### Sprint F — Settings and EQ (6 points)

| PR | Scope | Size | Tests / audits |
|---|---|---|---|
| F1 | The glow mounted once behind every tab except Now Playing (renamed from "library" glow); the shared screen container's and Monitoring's opaque backgrounds deleted (*verified*) | S | R4 glow audit renamed for all tabs |
| F2 | Settings: readable-width glass cards (scroll clipping off so card shadows are not cut); the chrome's device pill reused, its current device reading "checked" to VoiceOver; both switches on the accent tokens | M | SLOT fit for the status column |
| F3 | EQ graph on the lens, growing to fill the height without clipping the controls at the minimum window with large text; its own extra fill and border removed | M | R4-EQ-02 (curve, dots, 0 dB line ≥ 3:1 both modes, incl. the lens's bottom band); LAY-EQ-01 |
| F4 | EQ controls: the capsule switch (a recorded deviation from design §3.1's native-control rule), Preset and Save as pills | S | — |

*F3 and F4 are superseded by Sprint EQ (decision 21); Sprint F keeps F1 and F2.*

**Founder checks:** no blue on any surface the app draws; dragging an EQ point, a preset, Save,
and switching output device all still work.

### Sprint EQ — "The Lens", 31 points (decisions 21–23; ~20 points)

Design, evidence and scope: [docs/design/eq-lens/](../design/eq-lens/README.md).

| PR | Scope | Size | Tests / audits |
|---|---|---|---|
| EQ1 | Engine: an accurate 31-band graphic EQ (Välimäki & Liski), sections 10 → ≥ 31 | L+ | C++ gate: per-band and per-preset played response vs target; null / bypass bit-exact; RT-alloc soak; CPU at 7.1 |
| EQ2 | Automatic headroom (the summed-dB clamp deleted; preamp via `masterGainLinear`) + the played-curve read-back | M+M | no frequency above the source; preset loudness before/after |
| EQ3 | The Lens: 31 draggable points over ±12 dB, the played curve, readout, headroom + ceiling, On/Off, Compare, Reset; keyboard + VoiceOver | L+ | R4 for the curve, points and ceiling, both modes; the live keyboard pass |
| EQ4 | Presets: My Presets in the menu (rename / delete), per-output memory written ("Use on <output> ✓"), the presets re-voiced | M | the founder's listening check |

**Founder checks:** a 10-minute listening check of the presets and of dragging; On/Off and Compare
feel level-fair; a saved preset comes back; switching output recalls its EQ.

### Sprint G — Monitoring, then close-out (4 points)

| PR | Scope | Size | Tests / audits |
|---|---|---|---|
| G1 | Each channel on a lens (scroll clipping off); Before / After per decision 4, **each tag over its own half**; rows share the height, more channels scroll | M | R4 bars and tags both modes; LAY-MON-01 (1 / 2 / 6 / 8 channels) |
| G2 | Close-out: Instruments scroll pass on the Albums grid (stress library, with art) and Monitoring with an 8-channel file; a whole-app break-it pass; the full matrix on all five tabs; the macOS accent set to purple to catch leftover tint on surfaces the app draws | M | — |

**Founder checks:** the one keyboard and VoiceOver walk (§H, about ten minutes); then R1.

## F. Rules every PR follows

- `swiftlint --strict` caps type bodies at 250 lines and files at 500. The glass definition file
  is at 431 lines and is the only file allowed appearance checks; new controls are built from
  dynamic tokens instead of splitting it.
- Hover washes, hit areas and focus are built inside the Button label; controls stay ≥ 4pt
  inside a card edge; any new fixed row height gets a Dynamic Type clamp.
- Reduce Motion means "no easing; live meters stay live".
- **No app-wide tint** (Sprint A finding: an inherited `.tint` recolours every plain button in
  dark). Every system control a sprint restyles gets its tint per site, from the accent tokens.
- Debug-only code (the renderer, the test-library switch) must still have a consumer in the
  debug build, or hostile Periphery fails the gate.
- **System-drawn surfaces** (Save Preset sheet, playlist picker sheet, Track Info popover,
  alerts and confirmation dialogs, the menu-bar menu, drag previews) stay native; each gets one
  line in the sprint that touches its parent: what stays native, what we restyle inside.

## G. Exit criteria, triage, and the acceptance matrix

**A sprint is done when:** `make strict-gate` exits 0; the break-it pass has run and its
findings are closed; the matrix is filled for every screen in the sprint (in the sweep ledger);
the founder check is done and every finding tagged; the mini-retro is written.

**Triage rule.** Every finding is tagged **R1 blocker** — a broken function, a failed contrast
audit, system blue on a surface the app draws, a visible defect, an obviously empty screen, *or
a light-mode defect of any of those kinds* — or **post-R1** (taste and tuning, in either
appearance). Light taste is post-R1 exactly like dark taste. A third round is for blockers only;
a fourth round on the same sprint, or a third Sprint B round, makes every open item an explicit
founder decision — fix now, accept as a ledger deviation, or move post-R1 — and decision 10 is
re-asked with the picture sheets in hand. **R1 = zero blockers.**
**Not blockers:** native focus rings, text selection and menu highlights follow the user's
macOS accent (Regime A); the purple test (G2) targets surfaces the app draws.

**Matrix template** (filled per sprint in the sweep ledger):

| Screen / state | Dark | Light | Reduce Transparency | Increase Contrast | Reduce Motion | 880×640, default and largest text | States* | Regression (NP, Songs, bands) | Live appearance flip | Keyboard + VoiceOver | Final look | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| *filled by* | agent sheets | agent sheets | agent sheets | agent sheets | agent | agent sheets | agent (test library) | agent sheets | founder | founder (Sprint G) | founder | measured values |

\*empty, loading, failed, no results, long names, no art, stress library. A skipped cell is
logged with a reason and an expiry no later than the R1 gate; a silent skip is a fail.

## H. The founder's checks

**Every sprint (under ten minutes):** open the sprint's screens in dark, then light; try the
actions listed under that sprint's "Founder checks"; say what looks wrong.

**Once, in Sprint G (about ten minutes):**
1. **Keyboard:** turn on keyboard navigation; Tab through each tab. Every stop shows a clear
   ring; ↑/↓ keeps the row in view; ⇧↓ and ⌘A select; Return plays or presses the focused
   pill (Space stays the app-wide play / pause key, by design).
2. **VoiceOver (⌘F5):** the capsule switch reads its label and "selected"; the current item in
   an open pill menu reads "checked"; a row reads title, artist and "Now playing".
3. **Appearance:** flip dark ↔ light while a song plays.
4. **Grayscale** (Accessibility › Display › Colour filters): the selected tab, the playing row,
   an "on" switch, and Before vs After still stand apart.

## I. Not glass problems: product and data issues

| Seen | Issue | R1 |
|---|---|---|
| Albums | Every album reads "Unknown Artist" — no fallback from the album-artist tag (*verified*). | **Yes** (C2) |
| Songs vs Albums vs footer | A missing artist is blank in one place and "Unknown Artist" in others. | **Yes** (C2, ALB-04) |
| Artists | "A. R. Rahman" and "A.R. Rahman" are separate artists. | No |
| Genres | Genre counts total 265 of 379 songs: 114 songs unreachable from Genres. | No |
| Playlists | Rows show no artist or album. | No |
| Albums, Artists | Most covers missing; whether folder images are read is unchecked. | No |
| Settings | "Output Device" is both heading and label; developer wording in details. | Fixed in F2 |

## J. Review dispositions

| Finding (reviewer) | Disposition |
|---|---|
| Light mode has no design, PR or owner (all four) | Sprint B; frozen before Sprint D. |
| Analyzer, accent, knob fail in light (all four) | Sprint A (accent tokens) and B (analyzer, knob) with audits. |
| Stopping rule vs "release when all pass"; light taste could loop forever (the-fool, architect) | §G triage: light taste = post-R1 like dark; round 4 = explicit founder decision. |
| "No re-layout" contradicts the plan's own changes (the-fool) | Restyle redefined (§C). |
| Focus cue off and faint; no scroll into view (accessibility) | A3. |
| Detail pages would lose keyboard access, play and drag behaviour (accessibility, QA, architect) | E1–E3; keyboard set is Must; decision 11. |
| Root tint / white-on-teal; system surfaces unreachable (accessibility, QA, architect) | A2 accent tokens; §F system surfaces; §G "not blockers". |
| Light fixes would recolour approved dark looks (architect gate) | A2 tokens keep dark = today's teal; semgrep limited to text and glyphs. |
| Shadow change alters chips, pill, badge (architect) | A1 per-role shadow; added to Sprint A checks. |
| Opaque backgrounds on Monitoring and the screen container; clipped card shadows (QA, architect) | F1; scroll clipping off in F2 and G1. |
| No matrix, break-it pass, owner, performance check (QA, architect) | §D loop, §G matrix with "filled by", G2 Instruments. |
| Unreachable states; no test-library isolation (QA, architect gate) | C1. |
| Album fix untested, splits compilations, same-title merge, no re-read path (QA, architect, the-fool) | C2 with ALB-01…05; decision 12. |
| Renderer may not draw whole screens; tooling stalls progress (the-fool gate) | A4 renderer only, with a fallback; the test library moved to C1. |
| Founder load (all reviewers) | Decisions 9 and 14; seven small sprints; one keyboard / VoiceOver walk. |
| Sizes hidden; cost to S11–S14 invisible (the-fool gate) | Sizes per PR; sprint-plan S10.8 row restated. |
| No release engineering (the-fool) | Decision 13: not for R1. |
| Playlist reorder drag-only (accessibility) | E4; §C exception. |
| Before / After by colour only (accessibility) | G1. |
| Screen recordings measured by frame (QA) | Not adopted: picture sheets cover it with less tooling. |

## K. Risks and non-goals

**Risks:**
- **Light mode may not converge.** Decision 10 and the round-4 rule are the stop.
- **The album fix changes Albums and Artists.** It lands in C, before those screens are judged.
- **System surfaces stay partly native.** They will never look fully glass.
- **Keyboard and VoiceOver are founder-checked once, at the end** (decision 14). Code review,
  the accessibility audits and the SEL tests carry them until then.

**Non-goals:**
- New arrangements of any screen.
- Retuning shipped dark values. Card fill, radius, glow position and the analyzer's band are
  founder decisions.
- Album-coloured glow outside Now Playing.
- Real blur behind cards.
- S12 features.
- The §I items marked "No".
