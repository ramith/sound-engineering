# Area review: SwiftUI views and the design system

Reviewer: SwiftUI Pro (council Stage 2). Repo @ main (7d7c2cd), read-only.

**Scope read:**
- In full:
  - root views and the design system: `ContentView`, `TabContentView`, `DesignSystem.swift`, `DesignSystemGlass.swift`, `Color+Brand.swift`;
  - all of `UI/Controls` and `UI/Shell`;
  - the Library lists, grids, rail and pages, and the Playlist/queue lists;
  - Now Playing, the spectrum and meter views, `EQGraph(+Input)`, `EQPresetList`, `EQToneRow`, Monitoring;
  - `DesignTokenKit/{Palette,SurfaceResolver,*Layout,QueueHeaderWidths}`;
  - `.semgrep.yml` (the UI rules);
  - `Debug/{SheetRenderer,SheetFixture,SheetEngine,SheetFocusSeed}`.
- Sampled: the remaining EQ cards, Settings, `TrackInfoCard`, `HeroBand`, `MenuBarView`.

**Experiment:** `scratchpad/council/exp-ui/bench/main.swift`, built standalone with `swiftc -O`, offscreen `NSHostingView`. It touches no repo code, plays no audio and launches no app.

**Sources opened (Apple DocC JSON, fetched with `exp-ui/fetchdoc.py`):**
- API docs: `Canvas`, `TimelineView`, `TimelineSchedule.animation(minimumInterval:paused:)`, `AccessibilityTraits.updatesFrequently`, `FocusedValue`, `focusedSceneValue`, `Commands`, `EnvironmentValues.undoManager`, `Layout.makeCache`, `ScrollPosition`.
- HIG: "The menu bar" and "Undo and redo".
- Technology overview: "Adopting Liquid Glass".

**Coordination with the other area reviews:**
- `area-viewmodels.md` owns the *source* side of the 20 Hz problem: VM-3 (polling), VM-4 (observation granularity, the scrubber's 20 Hz body), VM-1 (`selectedTab` in the audio VM) and VM-11 (the current-file copies). Here I give only the *render and accessibility* side and reference those findings instead of repeating them.
- `area-build-test.md` BT-2 covers the sheet renderer as a non-test, and BT-5 covers semgrep as structure.
- `area-library.md` LIB-01 covers the reload wiring the views trigger.

## Summary counts

- STRUCTURAL 2: UI-1, UI-3.
- SIGNIFICANT 7: UI-2, UI-4, UI-5, UI-6, UI-8, UI-9, UI-10.
- LOCAL 4: UI-7, UI-11, UI-12, UI-13.

**The thread running through them.** The design system's colour and surface layer is mature: data in a Kit, pure resolvers, WCAG audits, and one sanctioned appearance reader. Two layers are less mature:
- **The interaction layer.** Lists, commands, undo and transient messages are rebuilt per screen. Every macOS SwiftUI limitation (List drops, gesture races, Menu labels) was worked around where it bit. The *decision logic* was extracted into kits; the SwiftUI containers that apply it were not.
- **The real-time render path.** It has no single primitive.

---

### UI-1 The List replacement was rebuilt per screen: six hand-rolled list scaffolds, three interaction models, STRUCTURAL. Criteria: 1, 2, 3, 5

**Evidence.** Each list is a `ScrollView { LazyVStack }` with its own keyboard, selection, focus and drop wiring:

| List | Selection model | Click | Keys | Reveal | Files |
|---|---|---|---|---|---|
| Songs, album / artist / genre pages | `ListSelection` (multi, ⇧ / ⌘) | Button: click selects, double-click plays | `ListSelectionKeyboard`: ↑↓ Home End PgUp/Dn, ⌘A, Esc, type-select, ↩ ⌘↩ ⇧⌘↩ ⌘I | arithmetic `FixedRowReveal` | `SongsListView.swift:102-106,296-309`, `DetailTrackList.swift:79-84,204-215`, `SongRowInteraction.swift:28-47` |
| Queue | single `cursorID` | `TapGesture`: **single click plays** | its own `onKeyPress` ↑↓↩ + `onDeleteCommand` | `ScrollViewReader.scrollTo(id)` | `PlaylistItemList.swift:43,100-110,165-176,265` |
| Playlist page | single `selectedEntryID` | `TapGesture`: single click plays | its own ↑↓↩, ⌥⌘ moves, `onDeleteCommand` | `scrollTo(id)` | `PlaylistDetailView.swift:26,125-130,136,171,241-245` |
| Recently Played | none | `TapGesture` plays | **none** (no focus stop, no keys, no context menu) | none | `QueueHistoryList.swift:41-46` |
| Library rail | selection = navigation | Button + double-click renames | its own ↑↓↩ + `onDeleteCommand` | `scrollTo(id)` | `LibrarySidebar.swift:80-101,208,305-313` |
| EQ presets | selection = the playing preset | Button | its own ↑↓↩⌫ | `scrollTo(id)` | `EQPresetList.swift:50-60,158-168` |

The SwiftUI glue is copied rather than shared:
- `showsRing`, 5 copies: `PlaylistItemList:242`, `PlaylistDetailView:155`, `LibrarySidebar:292`, `SongsListView:323`, `DetailTrackList:173`.
- The drop-target `isTargeted` toggle, 3 copies of the same shape: `PlaylistItemList:163`, `PlaylistDetailView:239`, `LibrarySidebar:203-204`.
- `numberColumnWidth = digits * 8 + 6`, 2 copies: `PlaylistItemList:47-50`, `PlaylistDetailView:41-44`.
- The `.focusable / .focused / .defaultFocus / .focusEffectDisabled` quartet, 6 copies.
- `PlaylistDetailView.swift:12` says so itself: "the same scaffold the queue's `PlaylistItemList` uses".

The divergence is user-visible:
- **Click semantics differ by list.** In Songs a click selects and a double-click plays (the HIG convention). In the queue, playlist and history lists a single click plays. The logged post-R1 item "a queue-row double-click logs two plays" (sweep ledger, Sprint G) is this model, not a separate bug: both taps pass the `isPlaying` guard (`PlaylistItemList:173`) before the async start flips it.
- **Multi-selection exists only in Songs and the pages.** The queue, the most-used list, can't remove, move or add-to-playlist several rows.
- **The S10.8 End-key-hang fix was applied to Songs and the pages only.**
  - `SongsListView.swift:296-299` records that `scrollTo(id)` "made the lazy stack build every row up to it, and keep them".
  - The queue's Jump-to-Now-Playing still does exactly that (`proxy.scrollTo(id, anchor: .center)`, `PlaylistItemList:115`), and so does every queue and playlist arrow key (`:265`, `PlaylistDetailView:171`).
  - `make songs-perf` gates Songs alone, yet a 10k-entry queue or playlist is reachable (⌘A on Songs, then Add to Queue).
- **Keyboard reorder is uneven.** The playlist page has ⌥⌘↑/↓ (`PlaylistDetailView+Moves.swift:16-18`). The queue has menu moves only. Recently Played has no keyboard support at all.

**Root cause.** Each macOS `List` limitation (drop never fires, the row gesture races selection, no reorder; see FB7367473 and forum 730367 in memory) was solved at the screen that hit it.
- What was extracted is the pure *decision* logic: `ListSelection`, `ListKeyboardCursor`, `GridKeyboardCursor`, `FixedRowReveal`. That part is good and tested.
- The *container* that applies the logic was not extracted. `ListSelectionKeyboard` is a partial container, used by 2 of the 6 lists.

**Why it matters:**
- Every list fix lands once and must be rediscovered for the other five; the End-key fix is the proof.
- The most-used list has the weakest model.
- R2 surfaces (smart playlists, stems lists, a second history) would become copy number seven.

**Structural remedy.** One generic container, `SelectableRows<ID, Row>` (or a `selectableList(...)` modifier family), that owns:
- the focus-stop quartet and the ring rule;
- selection as `ListSelection`, with a policy (`.multiple` / `.single` / `.navigation`);
- an activation policy: `.doubleClick` by default, with single-click-plays only as a deliberate, named per-list policy;
- the keys, including moves, and Delete via `onDeleteCommand`;
- reveal by `FixedRowReveal` (the fixed row pitch is already a design invariant, `LibraryRowSize`) or `ScrollPosition.scrollTo(y:)`, never `scrollTo(id)` on a lazy stack;
- grip drag-and-drop reorder with the drop-target state;
- the published commands of UI-3.

Rows stay environment-free values: keep the `SongRow` / `RowPass` discipline, which works. Extend `make songs-perf` into a per-list perf check of the container. A custom container stays justified on macOS 26, because `List` still can't host these drops. The point is to have exactly one.

**Effort:** L (M for queue + playlist first). **Risk:** med. **Depends on:** UI-3 (commands); founder question 2 (click model).

---

### UI-2 Real-time visuals: no single primitive; the Now Playing analyzer is 88 animated views re-diffed at 20 Hz, SIGNIFICANT. Criteria: 1, 3, 5

The *source* side (observable `[Float]` arrays, timers that never idle) is VM-3 / VM-4. This finding is the render side, with a measurement.

**Evidence:**
- **Three render strategies for the same kind of picture:**
  - `SpectrumAnalyzerView.swift:50-84`: `ForEach` over 88 bars. Each bar is a `ZStack` + `RoundedRectangle` + an optional cap, with two per-bar `.animation(.easeOut(duration: 0.08), value:)` (176 animations in all). Each cap also carries an environment-reading modifier (`.spectrumCapOpacity()`, `DesignSystemGlass.swift:90-110`). The whole body re-evaluates on every 20 Hz write, and the 80 ms ease outlasts the 50 ms tick, so animations are always in flight.
  - `EQGraphSilhouette.swift:21` and `SpectrumMiniView.swift:36` draw the same kind of data in a `Canvas`.
  - `MiniEqualizer.swift:30-50` runs **three** `TimelineView(.animation)` instances per playing row, with no `minimumInterval`, so they run at display rate (120 Hz on ProMotion). The playing row is mounted in the queue *and* in Songs or a page at the same time.
- **Three timing sources for one rate:** the VM's spectrum `Timer`, `MonitoringViewModel`'s `Task.sleep(50 ms)` loop, and the `TimelineView`s. VM-3 lists the first two.
- **Measurement** (`exp-ui/bench/main.swift`): a replica of the analyzer vs the same picture in one `Canvas`, in an offscreen `NSHostingView`, 300 frames of random bars, built with `-O`, two interleaved runs.

  | | update median / p95 (set model → run-loop turn → layout → flush) | process CPU per frame (incl. animation ticks between frames) |
  |---|---|---|
  | 88 views (the app's shape) | **6.3–6.4 ms / 8.2 ms** | **15.7 ms** |
  | one `Canvas` | 0.35–0.40 ms / 1.9–2.2 ms | 0.53 ms |

  - At 20 Hz the views version costs roughly 13 % (update only) to 30 % (with in-flight animations) of a core for one decorative view; the `Canvas` version costs about 1 %.
  - Caveats: this is a replica, not the app; it runs offscreen; and the app's real gradients and lens aren't in it.
  - The robust number is the ratio: about 18× on update and 30× on CPU. Confirm it on the real app with the Instruments SwiftUI template.
- **Apple's `Canvas` doc (opened):** "a canvas … might provide better performance for a complex drawing that involves dynamic data. Use a canvas to improve performance for a drawing that doesn't primarily involve text or require interactive elements." The analyzer is already `accessibilityHidden(true)` (`:45`), so moving it to `Canvas` loses nothing.

**Root cause.** There is no "live visual" primitive. Each visualization chose its own drawing and its own clock. The analyzer predates the app's `Canvas` adoption (EQ, Monitoring).

**Why it matters:**
- Now Playing is the default landing tab, and its analyzer is the single largest render cost in the app while music plays.
- It adds to the VoiceOver load (UI-4) and to power use while the app sits in the menu bar.

**Structural remedy:** one `LiveSpectrum` primitive.
- It is `TimelineView(.animation(minimumInterval: 1/30, paused: !isPlaying))` + `Canvas`, reading the non-observable spectrum source that VM-4 #2 proposes at draw time.
- A timeline doesn't tick off-screen, so visibility gating comes free.
- Peak-hold is fed by `context.date`; `PeakHoldTracker` is already time-fed (`DesignTokenKit/PeakHoldTracker.swift:42`).
- One component serves Now Playing, the EQ silhouette and each Monitoring half; bar colours are already per-index arrays (`SpectrumColorPalette`, `MonitorColors`).
- `MiniEqualizer` becomes one `TimelineView(.animation(minimumInterval: 1/30, paused:))` drawing three bars, or a `Canvas`.
- Docs opened: `TimelineView`, `TimelineSchedule.animation(minimumInterval:paused:)`.

**Effort:** M. **Risk:** low (visual parity is checkable with `make sheets`). **Depends on:** VM-4 #2 for the source; the render swap alone can land first.

---

### UI-3 No command layer: user verbs are wired per surface, so the menu bar, ⌘Z and consistent feedback cannot exist, STRUCTURAL. Criteria: 1, 2, 3, 5

**Evidence:**
- **The menu bar carries transport only.** There is one `CommandMenu("Controls")` (`AdaptiveSound.swift:149-194`). A grep finds **zero** `FocusedValue` / `focusedValue` / `focusedSceneValue` in the app, so no menu item can act on a list's selection.
- **Each surface re-implements the verbs, with its own set:**
  - Library song rows: Play, Play Next, Add to Queue, Add to Playlist…, Info (`LibrarySongMenu.swift:27-33`). The same verbs are repeated as VoiceOver named actions (`SongRowInteraction.swift:43-47`) and again as `onKeyPress` keys (`ListSelectionKeyboard.swift:65-74`, ⌘↩ ⇧⌘↩ ⌘I).
  - Playlist rows: Play, Play Next, the moves, Remove; **no** Add to Queue, Info or Add to Playlist (`PlaylistDetailView.swift:249-258`).
  - Queue rows: the moves, Info, Remove, Clear; **no** Add to Playlist (`PlaylistItemList.swift:197-225`).
  - Recently Played: tap only (`QueueHistoryList.swift:41-46`).
- **Feedback is composed in different layers.** The "added to queue" toast is raised by the model for Library pages (`LibraryBrowseModel+Play.swift:36,41`) but by the **views** for playlists (`PlaylistMoreMenu.swift:27-40`, `PlaylistDetailView+Actions.swift:41`).
- **Undo is bespoke and partial.** A grep finds no `UndoManager` / `undoManager` anywhere.
  - A queue replace keeps a one-level `queueRestorePoint` and shows a 6-second toast (`LibraryBrowseModel.swift:145`, `+Play.swift:28-31`, `QueueRestoreToast.swift`). There is no ⌘Z and no Edit ▸ Undo.
  - The toast is **not announced** to VoiceOver: `QueueRestoreToast` posts no `AccessibilityNotification`, unlike `ShellToast.swift:105`, `ErrorBanner.swift:53` and `EQBringBackMessage.swift:72`.
  - It does **not pause** on hover or focus, unlike `EQBringBackMessage.swift:41-43`.
  - So the one undo for a destructive action expires unannounced, which fails WCAG 2.2.1 (Timing Adjustable).
  - EQ "Bring back edits" is a second, separate undo mechanism.
  - Remove from Queue, Clear Queue and Remove from Playlist have no undo at all.
- **HIG, "The menu bar" (opened):** "Provide app-specific menus for custom commands … Even when commands are available elsewhere in your app, it's important to list them in the menu bar … makes them more accessible to people using Full Keyboard Access."
- **HIG, "Undo and redo" (opened), macOS:** "Place undo and redo commands in the Edit menu and support the standard keyboard shortcuts."

**Root cause.** Actions are closures handed to views. No value *names* a command (e.g. `PlayNext(targets)`) together with its availability, its feedback and its undo.

**Why it matters:**
- None of the library verbs can be found in the menu bar.
- Full Keyboard Access and VoiceOver parity is maintained by hand, three times per verb.
- Undo can't be offered consistently.
- Each new surface (for example R2's adaptive panels) re-invents the verb set, and the sets have already drifted (see the evidence above).

**Structural remedy:** the app's own house pattern. The EQ already works this way: `EQSession.perform(verb) -> outcome`.
1. Introduce a `LibraryCommand` / `QueueCommand` enum. One main-actor runner turns each command into an outcome: queue toast, announcement, and `UndoManager` registration (queue replace, remove, clear, playlist remove).
2. Lists publish their targets with `focusedSceneValue(\.trackTargets, selection.actionTargets(...))`.
3. A `Commands` "Song" menu reads them: Play, Play Next ⌘↩, Add to Queue ⇧⌘↩, Add to Playlist…, Get Info ⌘I, Remove ⌫. Edit ▸ Undo reads the same targets.
4. Context menus, VoiceOver actions and keys all render from the same command list, so the verb set has one definition.
5. `KeyboardTransportFocus` (`UI/Shell/KeyboardTransportFocus.swift`) becomes `@FocusedValue(\.isTextEntry)`, read by the Play/Pause command. That is the native mechanism for "a command depends on what has focus", and it replaces the hand-kept UUID token set.

Docs opened: `FocusedValue`, `focusedSceneValue`, `Commands`, `EnvironmentValues.undoManager`.

**Effort:** M-L. **Risk:** med. **Depends on:** VM-11 (`QueueCommands` narrow protocol); founder question 3 (undo).

---

### UI-4 Live readouts have no accessibility pattern: readings in labels, rewritten every tick, never marked `.updatesFrequently`, SIGNIFICANT. Criteria: 1, 5, 6

VM-4 covers the scrubber's 20 Hz body from the observation side. This finding is the accessibility-architecture side, plus a second, larger source that VM-4 doesn't list.

**Evidence:**
- **The readings sit in the label.** In `LoudnessMetersView.swift:108-109`, each of the three meter rows is `.accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(valueText)\(spokenSuffix)")`.
  - The *reading* is in the **label** (the element's name), at 0.1 precision (`:54,66`).
  - So the element's name changes every tick the loudness moves: up to 20 Hz, on 3 rows.
- **The same readout shape repeats:** the footer scrubber, whose value changes every second (`NowPlayingBar.swift:356-363`); the footer signal slot (`:445-453`); the device pill's rate (`OutputDevicePill.swift:99-103`); the hero badge row (`HeroBand.swift:124`).
- **`.updatesFrequently` is used once in the app**, on the scan strip (`LibrarySidebar.swift:242`). Apple's doc (opened): "Use this trait when you want an assistive technology to poll for changes when it needs updated information. For example, … the readout of a stopwatch."
- **The symptom is listed but untracked.** `docs/releases/v1.0.0-alpha.md:43` lists "VoiceOver keeps the app fairly busy while a song plays", but `docs/product/known-issues.md` doesn't carry it (grep: no match), and no analysis exists anywhere in `docs/`.

**Root cause.** Accessibility is authored per view, carefully but case by case. No shared "live readout" primitive encodes the label/value split, the speech quantisation and the trait.

**Why it matters:**
- It is the most plausible view-side contributor to the alpha's VoiceOver load: several elements change their *name*, not just their value, several times a second.
- It is also a semantics bug: VoiceOver users hear the reading as the element's name.

**Structural remedy:** one `liveReadout(label:value:)` modifier.
- The label is static.
- The value is quantised for speech: LUFS and dBTP to 1 dB, the playhead to the second, the rate unchanged.
- It applies `.accessibilityAddTraits(.updatesFrequently)` and `children: .ignore`.
- Apply it to the meters, the scrubber, the signal slot, the hero badges and the device pill.
- Then verify with Time Profiler under VoiceOver during the founder's walk.
- It pairs with VM-4 #1 (a quantised elapsed value in the model).

**Effort:** S. **Risk:** low. **Depends on:** none.

---

### UI-5 View state lives and dies with the tab switch; retention is patched per screen, SIGNIFICANT. Criteria: 1, 3

**Evidence:**
- **A tab switch destroys the whole subtree.** `TabContentView.swift:16-27` is a `switch selectedTab`, so each tab change throws away the tab's subtree. `LibraryTabView.swift:7-9` documents it: "the enclosing tab `switch` destroys this view on every tab change".
- **Only the browse grids get their place back.** They restore it through a `BrowsePlace` held by the model (`BrowsePlace.swift`, `BrowseNavigator.swift:94-131`, `BrowseKeyboard.swift:115-133`).
- **Everything else resets on return:**
  - Songs' selection and scroll (`@State selection` and `rowScroll`, `SongsListView.swift:32,37`);
  - a detail page's selection and scroll (`DetailTrackList.swift:37,41`);
  - the queue cursor (`PlaylistItemList.swift:43`);
  - the playlist page's selection (`PlaylistDetailView.swift:26`);
  - the EQ graph's keyboard band (`EQGraph.swift:32`).
- The selected tab itself lives in the audio VM (VM-1).

**Root cause.** The custom tab container (UI-9) discards view state, and retention is re-implemented per screen. So far that has been done only for the grids.

**Why it matters.**
- A user who selects 30 songs, glances at Now Playing and comes back has lost the selection and the scroll position.
- Each new screen has to decide again whether, and how, to remember its place.

**Structural remedy:** decide once, between two options.
- **(a) Keep tabs alive.** Put all tabs in a `ZStack`, gated by opacity, hit-testing and `accessibilityHidden`. This is only safe once UI-2 / VM-4 stop hidden tabs redrawing at 20 Hz.
- **(b) One place store.** Generalise `BrowsePlace` into a `ViewPlace` keyed by route (`ScrollPosition` + selected ids + cursor), held on the navigation model (VM-1 #7). Every container from UI-1 saves and restores through it.

Recommendation: (b), built into the UI-1 container, so there is one implementation for every list.

**Effort:** M. **Risk:** low-med. **Depends on:** UI-1, VM-1 #7.

---

### UI-6 Design-system maturity: colour tokens are values, not roles; the contrast audit proves the palette, not its use; type and metric tokens stop at primitives, SIGNIFICANT. Criteria: 1, 3, 6

BT-5 calls the `ui-*` semgrep rules legitimate style lint. The new point here: two contrast-critical rules live in regexes and naming, and the audit can't see call sites.

**Evidence:**
- **Text-vs-fill is enforced by naming and a regex, not by types.** Every colour is one `AppearancePair` (`DesignTokenKit/Palette.swift`).
  - "Text vs fill" exists only as name pairs: `accentForeground` / `accentFill`, `statusWarningText` / `statusWarning`, `meterHotText` / `meterHot`.
  - It is enforced by a one-line regex, `ui-no-accent-as-text` in `.semgrep.yml`, which says of itself: "it sees one foregroundStyle( call per line only".
- **The audit checks a hand-listed set of pairs** (e.g. `ContrastAuditTests.swift:20-27` lists the surfaces). Nothing ties those pairs to the pairs the views actually draw.
  - The selected-row rule is a function that callers must remember to use: `DesignSystem.Color.labelTertiary(onSelectedRow:)` (`DesignSystem.swift:120-122`).
  - `PlaylistItemRow.swift:45,77` paints `Color.asLabelTertiary` on a row whose fill is `rowSelected`, bypassing it.
- **Type tokens are fonts, not text roles.** The section-label recipe (font + `.tracking` + `.textCase(.uppercase)` + colour) is copied by hand nine times, with three different fonts:
  - `.caption.weight(.semibold)`: `InspectorColumn.swift:91,147`, `MasterGainSliderView.swift:19`, `LoudnessMetersView.swift:24`, `TrackInfoCard.swift:82`;
  - `DesignSystem.Font.micro`: `NavRow.swift:149`, `MonitorStageView.swift:22`, `EQToneHeader.swift:27-37`;
  - `.system(.body, weight: .heavy)`: `PlaylistView.swift:78`.

  The token's own doc says "pair with `.tracking(0.5).textCase(.uppercase)`" (`DesignSystem.swift:179`), which keeps a recipe in a comment.
- **Two names per base colour.** The legacy aliases `Color.asLabel*` / `asWindow` / `asHairline` are still used **36 times in 11 files**, while `Color+Brand.swift:5-8` says they are "migrated out incrementally".
- **Metric tokens have two homes and no bridge:**
  - 113 call sites convert with `CGFloat(Kit.value)`.
  - The "Twin Panels insets" triple is applied by hand in four tabs. Library uses **literals** (`LibraryTabView.swift:27,40-42`: 20 / 22 / 22 / 18); EQ, Settings and Monitoring use `EQScreenLayout.inset*`.
  - The `Screen` primitive's own insets are dead: both callers pass `edgeToEdge: true` (`MonitoringTabView.swift:77`, `SettingsTabView.swift:16`). So `LayoutMetrics.screenInsetV` is used by nobody, and `screenInsetH` is used as a card's inner padding instead (`LibraryCardHeader.swift:60`).

**Root cause.** The Kit models colour as data, which is excellent, but not the *surface a colour sits on*. Typography and metrics stop at primitives, so composites (the section label, the tab scaffold) are reassembled in each view.

**Why it matters:**
- A new view can put any ink on any surface and still pass every gate; the R4 audit is only as good as its hand-kept pair list.
- The legacy aliases double the vocabulary.
- One designer change, such as the section label or the tab inset, becomes a hunt across many files.

**Structural remedy:**
1. **`Ink` × `Surface`.** `Ink` (label / secondary / tertiary / accent / warning / error) × `Surface` (window / card / panel / badge / rowSelected / rowNowPlaying / lens) → `ink.on(surface)` returns the audited colour, used as `.foregroundStyle(.ink(.tertiary, on: .rowSelected))`. The R4 audit iterates the **cartesian product of the two enums**, so its coverage is complete by construction. The selected-row rule and the text-vs-fill rule become types instead of a regex.
2. **Text roles** for composites: `.textRole(.sectionLabel / .rowTitle / .readout)`.
3. **One tab scaffold.** A `TabScaffold` (the existing `Screen`, fixed) owns the Twin Panels insets.
4. **The `as*` aliases** are finished or deleted in one PR.
5. **Kit metrics** are exposed as `CGFloat` in the app layer through one extension, not converted per call.

All five are zero-visual-change refactors that the picture sheets can prove.

**Effort:** M. **Risk:** low. **Depends on:** none.

---

### UI-7 Transient messages: four capsule implementations, three lifetimes, two announce policies, LOCAL. Criteria: 3, 5

**Evidence:**
- **One good shared host.** `ShellToastSlot` + `ShellToastHost` (`ShellToast.swift`), used by the queue-add and EQ-output toasts.
- **Three others re-implement parts of it:**
  - `QueueRestoreToast` (`QueueRestoreToast.swift:17-34`): its own view and `.overlay(.bar)`, a literal 0.5 hairline, no announcement, no pause.
  - `EQBringBackMessage` (`EQBringBackMessage.swift:41-90`): its own countdown with a hover/focus pause, and its own announcement.
  - `ErrorBanner` (`ErrorBanner.swift:30-95`): its own announcement and animation.
- **The hairline is added by hand** after `.glassPanel(.overlay…)` in all four: `ShellToast:123`, `QueueRestoreToast:31`, `EQBringBackMessage:60`, `ErrorBanner:89-92`.

**Remedy.**
- One `TransientMessage` host takes a policy value: lifetime, pause on hover/focus (as `EQBringBackMessage` already does), announce, and an optional action.
- The `.overlay` surface role draws its own hairline.
- This also fixes UI-3's unannounced, unpausable restore offer.

**Effort:** S. **Risk:** low.

---

### UI-8 Presentation logic is re-derived in views: signal-path wording, sample-rate text, the current track, file facts, SIGNIFICANT. Criteria: 3, 4, 6

VM-11 already lists the current-file copies. This finding adds their per-body cost and the other duplications.

**Evidence:**
- **Signal path → presentation, four mappings with two spoken forms:**
  - the footer (`NowPlayingBar.swift:387-453`), with its own `dotColor` and spoken text ("Pure mode, …");
  - the hero (`HeroBand.swift:82-170` plus `SignalPathAccessibility.value`, `:225-247`), with a *different* spoken form;
  - Settings (`SignalPathStatus.swift:21-93`);
  - the inspector (`InspectorColumn.swift:60-72`).
- **Sample-rate text, four formatters with different rules:**
  - `SignalPathInfo.swift:103-117` uses `String(format: "%.1f kHz")`, spoken by string-replacing `" kHz"` → `" kilohertz"`;
  - `TrackInfoCard.swift:215-224` has its own;
  - `SongsColumnModel.swift:62` uses 0…1 fraction digits;
  - `Helpers/QualityFormatter.swift:11-13` uses `String(format:)`.
- **Current track, four derivations in views.** `NowPlayingBar.swift:19-24`, `HeroBand.swift:27-31`, `NowPlayingTabView.swift:54-58` and `MenuBarView.swift:12-17` each call `viewModel.playlist` (which is `queue.map(\.file)`, `AudioViewModel.swift:208-210`) **twice**. That is two O(n) array builds per body pass, in views mounted on every tab.
- **File I/O inside a view.** `TrackInfoCard` opens `AVAudioFile` and stats the file in a `Task.detached` launched from the view, then interprets the format there (`TrackInfoCard.swift:143-157,180-238`). It is untestable, and it is a fourth reader of facts the store already holds for library tracks.

**Root cause.** There is no presentation-model layer between kit/VM state and the views, and formatting helpers are added per need as free functions.

**Why it matters:**
- The same state reads differently on screen and to VoiceOver, depending on where it is shown.
- The O(n) shim runs in views that are always mounted.
- None of these mappings is tested.

**Remedy:** pure, tested presenters in a kit.
- `SignalPathPresentation(info) -> (tone, title, chips, spoken)`, used by all four sites.
- `SampleRateFormatStyle: FormatStyle` with a `.spoken` variant.
- `queue.current` (VM-7) in place of the per-view derivations.
- A `TrackFacts` loader service (off-main, cached), shared by the Info card and `NowPlayingController`.

**Effort:** S-M. **Risk:** low. **Depends on:** VM-7 for `queue.current`.

---

### UI-9 The custom window chrome is the root of a family of workarounds; Liquid Glass is banned while the release notes claim it, SIGNIFICANT. Criteria: 1, 5

**Evidence:**
- **The chrome lives inside the content area.** `AppShell.swift:27-50` puts a 60 pt chrome band and a 64 pt footer inside the content area, under a native titlebar (`AdaptiveSound.swift:139-145`).
- **Workarounds that follow from that choice:**
  - `WindowMinSize`, an `NSViewRepresentable` (`WindowMinSize.swift:4-13`), because `.windowResizability(.contentMinSize)` "did NOT reliably clamp".
  - `NavigationSplitView` and `NavigationStack` are avoided (`LibraryTabView.swift:11-18`, `LibraryRoute.swift:5-10`), so the Library has a hand-rolled path stack.
  - A hand-built tab strip with manual `.isSelected` traits (`ChromeBar.swift:68-124`).
  - The tab container that loses view state (UI-5).
  - Semgrep `swift-no-navigation-title` (`.semgrep.yml:43-50`), whose message points at a non-existent `UI/Shell/ScreenHeader.swift` (doc drift).
  - Semgrep `no-liquid-glass-api`, marked "FROZEN for S10.7" (`.semgrep.yml:196-207`).
  - Hand-painted "styled glass" fill strata that imitate materials (`DesignSystemGlass.swift:211-261`).
- **The release notes promise "a Liquid Glass look"** (`docs/releases/v1.0.0-alpha.md:35`).
- **Apple, "Adopting Liquid Glass" (opened):**
  - "If your app uses standard components … your interface picks up the latest look and feel";
  - "Reduce your use of custom backgrounds in controls and navigation elements";
  - "Consider using split views to build sidebar layouts with an inspector panel."

**Root cause.** In July 2026 the app chose to own its chrome (the window buttons overlapped it) and to keep material off surfaces with nothing scrolling beneath. That was reasonable for S10.7, but the cost is now spread across many sites, and each new SwiftUI limitation adds another workaround.

**Why it matters.** The app forgoes what the system chrome gives for free, and every new screen pays the workarounds again. What it gives up:
- toolbar integration and the scroll-edge effect;
- full-screen toolbar behaviour;
- native tab and sidebar accessibility semantics;
- future OS look updates.

**Remedy:** no rewrite now. A post-R1 **spike (S)**:
- move `ChromeBar` into `.toolbar` (principal: the tab picker; navigation: the logo and the device pill) with `windowToolbarStyle(.unified)`;
- make the footer a `.safeAreaInset(edge: .bottom)` bar;
- count which workarounds disappear (`WindowMinSize`, the Library path stack, the tab-state loss).

The founder then decides on Liquid Glass adoption. (Memory records that "the entire GUI will eventually redesign around Liquid Glass".)

**Effort:** S for the spike, L for adoption. **Risk:** high (visual identity). **Depends on:** founder question 1.

---

### UI-10 Picture-sheet hooks live inside production views; the visual tool is a side channel, SIGNIFICANT. Criteria: 6, 1

BT-2 covers the renderer being a non-test and recommends a smoke test. This finding is about how it couples into production views, and its root cause.

**Evidence:**
- **12 production views read DEBUG-only hooks.** They use 7 DEBUG-only environment keys (`Debug/EnvironmentValues+Sheet*.swift`) and/or `sheetFocusSeed`:
  - Songs and detail lists: `SongsListView.swift:42-47,113-126`, `DetailTrackList.swift:44-47,105-110`;
  - browse grids: `BrowseGrid.swift:31-34,66-77`, `BrowseTile.swift:27-30,53-59`, `BrowseNavigator.swift:99-104`;
  - artwork: `ArtworkThumbnail.swift:43-46,87-91`;
  - EQ: `EQGraph.swift:18-20,52-54,120-131`, `EQToneCard.swift:28`, `EQPresetList.swift:69`;
  - pages, rail and queue: `LibraryDetailPage.swift:37-40,74-79`, `LibrarySidebar.swift:102-105`, `PlaylistItemList.swift:117-123`.
- **Production code paths branch on the hooks.** `LibraryDetailPage.load()` returns the fixture instead of reading the store (`:74-79`). `ArtworkThumbnail.load()` serves fixture images (`:87-91`).
- **The fixture writes VM state directly** (`SheetFixture.swift:155-168`); this is VM-1's evidence.

**Root cause.** Interaction state (selection, hover, drag, focus, cursor) is private `@State` in leaf views, so the only way to render "row 3 selected and focused" is a DEBUG back door. And because the app target is untestable (BT-1, process.md), the sheets can't become assertions.

**Why it matters:**
- Every new state the founder wants to see needs a new environment key and a hook in a production view.
- The sheets verify nothing automatically, so visual regressions are only found by eye.

**Remedy:**
1. Give stateful leaf views an explicit initial-state input, e.g. `SongsListView(initialSelection:)`, `EQGraph(seed:)`. Alternatively, lift the state into small view-state objects owned by the container (`BrowseNavigator` is already this shape). Either way the fixture *constructs* the state instead of reaching in.
2. Once the views live in a library target (BT-1), render the sheets from swift-testing with `ImageRenderer` / `NSHostingView` and compare against golden images with a tolerance. The sheets then become a gate.
3. Delete the environment keys.

**Effort:** M. **Risk:** low. **Depends on:** BT-1.

---

### UI-11 Songs sort: three representations and a Table-era round trip, LOCAL. Criteria: 1, 3

**Evidence:**
- **A Table-era type with no Table.** `LibraryBrowseModel.sortOrder: [KeyPathComparator]` is still documented as "The Songs `Table`'s active-column comparator" (`LibraryBrowseModel.swift:80-88`). The `Table` is gone (`SongsListView.swift:6-12`).
- **Three representations, with a round trip.** The sort fields are listed in `SongsHeader.sortOptions` (`SongsHeader.swift:55-76`) and again in `SongColumn.comparator` (`SongsColumnModel.swift:15-40`). The Kit's `SongSortMapping` then maps the keypath *back* to `TrackSort`.
- **`applySort` exists twice** (`SongsHeader.swift:136-149`, `SongsListView.swift:262-276`). Each copy does the two-step `model.sortOrder = x; model.applySortOrder(x)` plus an announcement.

**Remedy.**
- Add `SongSort { field, ascending }` in `LibraryBrowseKit`, mapping directly to `TrackSort`.
- Add one `model.toggleSort(field)` that writes, reloads and announces; the column header and the pill both call it.
- `KeyPathComparator` then leaves the app.

**Effort:** S. **Risk:** low.

---

### UI-12 Dynamic Type machinery that does nothing on macOS 26, enforced by the gate, LOCAL. Criteria: 6

This is a known open item: the memory note `reference-macos-dynamic-type-clamps` says "the strict-gate clamp guard may be guarding a no-op — revisit". The new insight is that the code now contradicts itself:
- `DesignSystem.swift:160-165` says the Dynamic-Type text styles are "what makes the `.dynamicTypeSize(.small ... .xxLarge)` clamps … actually bound anything".
- `QueueHeaderLayout.swift:19-22` and `EQScreenLayout.swift:7-8` say the clamps bound nothing.

The machinery in question:
- 16 `@ScaledMetric`;
- 4 clamps: `NowPlayingBar.swift:41`, `ChromeBar.swift:45`, `SongsListView.swift:99`, `DetailTrackList.swift:74`;
- a gate stage that asserts the clamps are present (`scripts/strict-gate.sh:150-171`);
- a 1.4× headroom budget (`NowPlayingLayout.maxTypeHeadroom`).

**Remedy:**
1. Run a short spike on what macOS 26's Text Size setting actually does to a SwiftUI app.
2. Delete the dead idioms and the gate stage, and fix the comments.
3. Keep structural reflow (`QueueHeaderWidths`) as *the* pattern.

**Effort:** S. **Risk:** low.

---

### UI-13 Small items, LOCAL. Criteria: 5

- **O(n) work on hot body passes:**
  - `ForEach(Array(model.visibleSongs.enumerated()), id: \.element.id)` (`SongsListView.swift:79`, `PlaylistDetailView.swift:108`) allocates an O(n) array per body pass, and Songs' body re-runs on every selection change. In Swift 6.2 `enumerated()` is a `Collection` (SE-0459), so pass it directly.
  - The queue's `visibleRows` (`PlaylistItemList.swift:63-68`), `.onChange(of: viewModel.queue.map(\.id))` (`:94`), `PlaylistView.filteredIndices` (`:150-155`) and `PlaylistDetailView.swift:133` each map the whole list per body pass.
- **Optional-driven presentation through a hand-built `Binding(get:set:)`:** a per-row popover (`PlaylistItemList.swift:181-190`), a `fileImporter` (`PlaylistDetailView.swift:55-62`) and a sheet (`EQPresetList.swift:62,138-144`). Prefer the `item:` forms.
- **A day-long sleep standing in for disappear.** `MonitoringTabView.swift:40-52` keeps a `.task` alive with `Task.sleep(for: .seconds(86400))` and a cancellation handler that hops to stop polling. It disappears with UI-2's `TimelineView`; meanwhile `onAppear` / `onDisappear` say it plainly.

**Effort:** S each.

---

## What is GOOD (keep and copy)

- **`.glassPanel(role:)` plus a pure `resolveSurface`** (`DesignTokenKit/SurfaceResolver.swift`):
  - Reduce Transparency and Increase Contrast fallbacks are decided in the Kit and tested.
  - Views declare *what* a surface is.
  - `DesignSystemGlass.swift` is the one sanctioned appearance reader, and semgrep holds that rule.
- **`DesignTokenKit` as data.** Every colour is an audited `AppearancePair`, and layout arithmetic is tested headlessly (`EQScreenLayout`, `MonitorLayout`, `SettingsLayout`, `NowPlayingLayout`).
- **`QueueHeaderLayout` + `QueueHeaderWidths`:** a custom `Layout` whose policy is a pure, unit-tested Kit value that reflows rather than clamps. It is the model for any width-deficit problem. It has no cache, which matches Apple's `makeCache` guidance ("only implement a cache if profiling shows that it improves performance").
- **`pillMenuStyle()`.** The macOS Menu-label-flattening limitation is isolated in **one** modifier, together with its evidence and the VoiceOver `combine` fix. This is how a workaround should look.
- **Custom controls that keep native semantics:**
  - `CapsuleSwitch` exposes `accessibilityRepresentation { Picker }`;
  - `GlassSwitchStyle` is a `ToggleStyle`;
  - an `IconChip` can't be built without a label;
  - `CarvedSlider` has an adjustable action and keyboard parity.
- **`KeyboardFocusVisibility`:** a `:focus-visible` rule driven by one app-wide event monitor, with `keyboardCursorRing` / `controlFocusRing` as the only ring primitives.
- **Songs list performance design:**
  - environment-free rows and a per-pass `RowPass`;
  - `ListVisibleSpan`, a non-observed reference, so scrolling never re-renders the list;
  - `FixedRowReveal` instead of `scrollTo(id)`;
  - the `make songs-perf` gate at 20k songs.

  UI-1 should copy all of it to the other lists.
- **`SongRowInteraction`:** one row behaviour, including the VoiceOver named actions, shared by Songs and the pages.
- **`EQGraph`:** a `Canvas` painter, a stroke API on the VM, 31 adjustable VoiceOver points and full keyboard support. It is the template for interactive visualizations.
- **`ShellToastSlot`** (a monotonic token and a single cancellable task) and **`AppDialog`** (one themed dialog, with Esc and Return designed in).
- **`TransportSpaceGate`:** the Space-vs-text-field workaround in one modifier with per-field tokens. UI-3 proposes its native successor.

## Duplicated capability (for the duplication pass)

1. **List scaffolds, 6 copies (UI-1):** `showsRing` 5 copies, the drop-target toggle 3, `numberColumnWidth` 2, the focus quartet 6, keyboard handlers 6.
2. **Row interaction models, 3:** Button + double-click; `TapGesture` single-click-plays; none at all (Recently Played).
3. **Real-time rendering (UI-2, VM-3):** 3 render paths (views, `Canvas`, `TimelineView`) and 3 timing sources.
4. **Commands (UI-3):**
   - verb sets defined per surface (context menu, VoiceOver actions, keys);
   - queue-toast composition split between models and views;
   - 2 bespoke undo mechanisms (queue restore, EQ bring-back).
5. **Transient message capsules, 4 copies (UI-7).**
6. **Presentation mappings (UI-8, VM-11):** signal-path presentation in 4 places with two spoken forms; sample-rate formatters, 4; current-track derivation in views, 4.
7. **Design-system composites (UI-6):** the section-label recipe in 9 places with three fonts; the Twin Panels inset triple in 4 places (one with literals); two colour vocabularies (`DesignSystem.Color.*` and `Color.as*`).
8. **Songs sort (UI-11):** 3 sort definitions and 2 `applySort` copies.
9. **Dialog hosting, 3 patterns:**
   - a model-owned host, one per tab (`PlaylistDialogSheet`);
   - a local `sheet(item:)` (`MusicFoldersSection`, `EQTabView`);
   - a local hand-built `Binding` (`EQPresetList`).
10. **Place restoration (UI-5):** grids only (`BrowsePlace`); nothing elsewhere.

## Algorithms that need a correctness panel (map row IDs)

- **D53–D56 (spectrum FFT, band mapping, ballistics, handoff buffer):** zero test coverage. They feed all three visualizations, and Monitoring's BEFORE/AFTER comparison only means something if the band mapping is right. Oracle: a known sine must land in the expected band at the expected dB.
- **N116 (WCAG luminance / contrast):** every R4 audit rests on it, and it has no pinned known-value vector. Add white/black = 21.0, the sRGB mid-grey reference, and the 0.03928 vs 0.04045 threshold case. It is cheap, and it stops the whole audit suite from being its own oracle.
- **N87 (`FixedRowReveal` / `ScrollPlacement`):** tested in the Kit, but applied only to Songs and the pages. When UI-1 moves the queue and playlists onto it, the panel should cover a filtered list and the queue's Up Next / History switch.
- **N85 / N86 and `QueueHeaderWidths`:** tested and fine; no panel needed.

## Open questions for the founder (recommendation first)

1. **Window chrome and Liquid Glass (UI-9).**
   - Recommended: run the post-R1 toolbar spike (S) before any further chrome work. Then decide on Liquid Glass, using the spike's list of the workarounds that disappear.
   - Alternative: keep the custom chrome, and correct the release-notes claim of a "Liquid Glass look".
2. **The click model for lists (UI-1).**
   - Recommended: **single click selects, double-click or Return plays, everywhere.** This is the macOS convention, matches Songs today, and removes the queue's double play.
   - Alternative: keep single-click-plays in the queue and playlist pages as a named, documented exception inside the shared container.
3. **Undo (UI-3).**
   - Recommended: **yes**, through `UndoManager` with Edit ▸ Undo / ⌘Z, for queue replace, remove, clear and playlist remove. The restore toast stays as a visible hint, made pausable and announced.
   - Alternative: keep the one-level toast but make it pausable and announced (UI-7). That is S effort, but still gives no ⌘Z.
4. **Remembering places across tab switches (UI-5).** Recommended: **yes, for every list** (selection, scroll and cursor), through one place store.
5. **Text size on macOS (UI-12).** Recommended: accept that "layouts hold at any size by structure", and delete the clamps, the `@ScaledMetric`s and the gate stage once a one-hour spike confirms that the system Text Size setting doesn't reach SwiftUI text styles.

## Suggested ordering (feeds the wave plan)

1. **Quick and low-risk:**
   - UI-4, the live-readout modifier (S);
   - UI-2's render half: the analyzer to `Canvas` and `MiniEqualizer` to one throttled timeline (M);
   - UI-7, the transient host (S);
   - UI-13 and UI-11 (S each).

   Together with VM-4's quick wins, these directly attack the alpha note "VoiceOver keeps the app fairly busy".
2. **Design system:** UI-6, role tokens and the tab scaffold (M, zero visual change, verified by the sheets).
3. **Interaction core:** UI-3, the command layer, then the UI-1 container (queue and playlist first), with UI-5's place store inside it.
4. **Testability:** UI-10, after BT-1 lands.
5. **Strategic:** the UI-9 spike, then the founder's decision.
