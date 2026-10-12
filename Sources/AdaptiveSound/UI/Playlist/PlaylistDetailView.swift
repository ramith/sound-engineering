import LibraryBrowseKit
import LibraryStore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Playlist detail (S10.3 — the open-playlist content pane)

/// The detail shown when a playlist is selected in the sidebar. Loads through `PlaylistsModel`
/// (entries in position order, each resolved to its library track) and reuses `PlaylistItemRow`
/// (with a `PlaylistEntryDragItem` grip). Chunk C: the three play verbs (Play replaces the queue
/// with a one-level restore-queue undo; Play Next / Add to Queue), tap-to-play-from-row, grip-drag
/// reorder, remove, and ↑/↓/Return/⌫ keys — the same scaffold the queue's `PlaylistItemList` uses.
/// S10.8 E4 adds Move to Top / Up / Down / to Bottom (`+Moves`): row menu, ⌥⌘-arrow keys, VoiceOver;
/// then the Library card's header (`PlaylistDetailHeader`: Play / Shuffle / ⋯) and row area. Its
/// confirmation and failures show in the Library tab's one dialog (`PlaylistDialogSheet`).
/// Chunk F renders the unavailable state for an entry whose file moved/was deleted. Several members
/// are `internal` (not `private`) so the same-type `PlaylistDetailView+Actions` extension (split out
/// for type-body length) can reach them.
struct PlaylistDetailView: View {
    let playlistID: Int64
    @Environment(PlaylistsModel.self) var model
    /// The queue toast's owner (a row's Play Next confirms there, as on the other pages).
    @Environment(LibraryBrowseModel.self) var library

    /// Keyboard-selected row (a ScrollView/LazyVStack doesn't own key focus like a `List`).
    @State var selectedEntryID: Int64?
    /// The entry a Move command just moved: scrolled into view once the rows re-sequence (E4).
    @State var revealEntryID: Int64?
    /// The entry a reorder drag is hovering over (drop-target border). Nil when no drag is active.
    @State private var dropTargetEntryID: Int64?
    /// The list holds key focus. `internal` so a Move from the menu or VoiceOver (`+Moves`) can take
    /// it — the next ⌥⌘-arrow then lands on this list.
    @FocusState var listFocused: Bool
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    /// Transient "Restore previous queue" affordance after a Play-replace; the token re-triggers the
    /// auto-dismiss even on a repeated Play.
    @State var restoreToastToken: Int?
    @State var restoreDismissTask: Task<Void, Never>?
    /// The entry being re-pointed via Locate… (drives the file importer); nil when closed (F).
    /// `internal` so the `+Actions` extension's `missingRowActions` can set it.
    @State var locatingEntryID: Int64?

    /// Track-number column sized to the widest index, so a 3-digit position never wraps (queue idiom).
    private var numberColumnWidth: CGFloat {
        let digits = max(2, String(model.detail.count).count)
        return CGFloat(digits) * 8 + 6
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaylistDetailHeader(play: { playNow() }, shuffle: shuffleNow)
            content
        }
        // No background of its own: it sits on the Library card (S10.8 D1 — the opaque window fill
        // it painted was the hard edge against the glow).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { restoreToast }
        // Locate… (F): pick the moved file → re-point the track (id preserved) → it resolves.
        .fileImporter(
            isPresented: Binding(get: { locatingEntryID != nil },
                                 set: {
                                     if !$0 {
                                         locatingEntryID = nil
                                     }
                                 }),
            allowedContentTypes: [.audio]
        ) { result in
            if case let .success(url) = result, let id = locatingEntryID {
                Task { await model.relocateEntry(id, to: url) }
            }
            locatingEntryID = nil
        }
        // Reload whenever the selected playlist changes (a new sidebar selection reuses this view).
        .task(id: playlistID) { await model.loadDetail(id: playlistID) }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.detailState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t Load Playlist", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView {
                Label("No Tracks Yet", systemImage: "music.note.list")
            } description: {
                Text("Add songs from your Library to build this playlist.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            trackList
        }
    }
}

// MARK: - Track list (rows + keyboard cursor)

/// Same-file extension (type-body length): reaches the view's private focus/drop state.
private extension PlaylistDetailView {
    var trackList: some View {
        ScrollViewReader { proxy in
            let cursorID = ringCursorEntryID
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.detail.enumerated()), id: \.element.id) { index, row in
                        detailRow(index: index, row: row, isKeyboardCursor: row.id == cursorID)
                            .id(row.id) // the arrow keys' `scrollTo` target (A3)
                    }
                }
                // The card's row area, as Songs and the grids (E4): a row's card never touches the
                // card's edge.
                .padding(.vertical, DesignSystem.LayoutMetrics.cardRowAreaInsetV)
                .padding(.horizontal, DesignSystem.LayoutMetrics.cardRowAreaInsetH)
            }
            // All-unavailable (missing-file) rows = no cursor row = no focus stop.
            .focusable(keyboardCursor != nil)
            .focused($listFocused)
            .defaultFocus($listFocused, true)
            // The system effect would outline the whole list; the cursor row's ring replaces it (A3).
            .focusEffectDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onKeyPress(keys: [.upArrow, .downArrow]) { arrowKey($0, proxy: proxy) }
            // Key-down only: a held Return must not replace the queue again on every repeat.
            .onKeyPress(.return, phases: .down) { _ in playCursorRow() }
            // The system Delete command (⌫, ⌦, Edit ▸ Delete): macOS delivers ⌫ as U+007F, which
            // a key-press match on `KeyEquivalent.delete` (U+0008) never sees — see the queue.
            .onDeleteCommand(perform: removeCommand)
            // A moved row stays in view (E4). After the re-sequence, not in the move itself: the
            // row's new place exists only once the rows have re-rendered.
            .onChange(of: model.detail.map(\.id)) {
                guard let id = revealEntryID else { return }
                revealEntryID = nil
                proxy.scrollTo(id)
            }
        }
    }

    /// The rows the cursor walks: the AVAILABLE (playable) entries only — a missing-file row is
    /// non-interactive except via its badge/context menu (Locate / Remove), so the keys skip it (F).
    var playableEntryIDs: some BidirectionalCollection<Int64> {
        model.detail.lazy.filter(\.isAvailable).map(\.id)
    }

    /// The ONE keyboard cursor (A3, A-review) — the ring row, the row ↑/↓ move from, and the row
    /// Return plays from and Delete removes: the selected entry, or the first playable row while
    /// nothing is selected.
    var keyboardCursor: ListKeyboardCursor<Int64>? {
        ListKeyboardCursor.resolve(rows: playableEntryIDs, anchor: selectedEntryID)
    }

    /// The ring is drawn while the list holds key focus AND the user navigates by keyboard.
    var showsRing: Bool {
        listFocused && showsKeyboardFocus
    }

    /// The row wearing the focus ring, or nil (no ring).
    var ringCursorEntryID: Int64? {
        showsRing ? keyboardCursor?.id : nil
    }

    /// ↑/↓ from the cursor through the playable rows; with nothing selected the first press
    /// (either arrow) selects the first playable row, where the ring already sits. Keeps the new
    /// selection on screen the queue's way: `scrollTo` with no anchor scrolls only as far as
    /// needed, instantly.
    func moveSelection(by delta: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let target = keyboardCursor?.step(by: delta, in: playableEntryIDs) else { return .ignored }
        selectedEntryID = target
        proxy.scrollTo(target)
        return .handled
    }

    /// ↑/↓ walk the cursor; the Move chords (⌥⌘↑ / ⌥⌘↓, with ⇧ to the top / bottom) MOVE an entry
    /// instead (E4) — one handler, so a chord can never also walk the cursor. A move acts where
    /// Return does: on the selected row, or on the ring row while the ring is drawn (a move removes
    /// nothing, so the ring alone is mark enough — unlike Delete). A chord is always consumed, even
    /// with nothing to move or at the edge, so it never falls through to another action.
    func arrowKey(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let move = ListMove(press) else {
            return moveSelection(by: press.key == .upArrow ? -1 : 1, proxy: proxy)
        }
        if let id = keyboardCursor?.activationTarget(ringVisible: showsRing) {
            perform(move, on: id)
        }
        return .handled
    }

    /// Return: play the playlist from the cursor row (selecting it).
    func playCursorRow() -> KeyPress.Result {
        guard let id = keyboardCursor?.activationTarget(ringVisible: showsRing) else { return .ignored }
        selectedEntryID = id
        playNow(startingAt: id)
        return .handled
    }

    /// The Delete command's action, or nil while Delete has nothing to act on — which disables
    /// Edit ▸ Delete and lets ⌫ bubble.
    var removeCommand: (() -> Void)? {
        guard keyboardCursor?.deleteAction(ringVisible: showsRing) != nil else { return nil }
        return { removeCursorRow() }
    }

    /// Delete: remove the SELECTED row — permanently, so the ring alone never licenses it (A
    /// break-it): on the seeded first row it only selects. Pre-selects the playable neighbour
    /// (next, else previous) so the selection lands there — not back at the top — once the async
    /// remove + reload lands.
    func removeCursorRow() {
        switch keyboardCursor?.deleteAction(ringVisible: showsRing) {
        case let .remove(id):
            selectedEntryID = ListKeyboardCursor.anchor(afterRemoving: id, from: playableEntryIDs)
            Task { await model.removeEntry(id) }
        case let .claim(id):
            selectedEntryID = id
        case nil:
            break
        }
    }

    @ViewBuilder
    func detailRow(index: Int, row: PlaylistDetailEntry, isKeyboardCursor: Bool) -> some View {
        if row.isAvailable, let display = row.display {
            PlaylistItemRow(
                file: AudioFile(display),
                index: index,
                isSelected: selectedEntryID == row.id,
                isNowPlaying: false, // "now playing" in a playlist context is deferred (architect #4)
                numberColumnWidth: numberColumnWidth,
                dragPayload: PlaylistEntryDragItem(entryID: row.id),
                isDropTarget: dropTargetEntryID == row.id,
                isKeyboardCursor: isKeyboardCursor
            )
            .dropDestination(for: PlaylistEntryDragItem.self) { payloads, _ in
                dropTargetEntryID = nil
                guard let fromID = payloads.first?.entryID else { return false }
                return moveEntry(fromID: fromID, toEntryID: row.id)
            } isTargeted: { targeted in
                dropTargetEntryID = targeted ? row.id : (dropTargetEntryID == row.id ? nil : dropTargetEntryID)
            }
            .simultaneousGesture(TapGesture().onEnded {
                listFocused = true
                selectedEntryID = row.id
                playNow(startingAt: row.id)
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { playNow(startingAt: row.id) }
            .accessibilityActions { moveAccessibilityActions(for: row.id, at: index) }
            .contextMenu {
                Button("Play") { playNow(startingAt: row.id) }
                Button("Play Next") { playEntryNext(row.id) } // this track, not the whole list
                Divider()
                moveMenuItems(for: row.id, at: index)
                Divider()
                Button("Remove from Playlist", role: .destructive) {
                    Task { await model.removeEntry(row.id) }
                }
            }
        } else {
            unavailableRow(index: index, row: row)
        }
    }

    /// A missing-file entry (F): its metadata dimmed, with a trailing warning-badge MENU (Locate /
    /// Remove) — a visible, click-and-keyboard-reachable affordance, not just right-click (review).
    /// Not tappable-to-play (skipped on play). VoiceOver reads it as one element + the same actions.
    /// On the playable rows' card (E4): the grip's slot, so its number and title line up with theirs,
    /// and one line at their 36pt pitch (decision 5), the artist after the title.
    func unavailableRow(index: Int, row: PlaylistDetailEntry) -> some View {
        HStack(spacing: 12) {
            // A missing entry has no grip (it can't be dragged); the slot stays.
            Color.clear.frame(width: DesignSystem.QueueRow.gripHitWidth, height: 0)
            Text(index + 1, format: .number.grouping(.never))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .frame(width: numberColumnWidth, alignment: .trailing)
            unavailableTitle(row)
                .lineLimit(1)
            Spacer()
            Menu {
                missingRowActions(row)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignSystem.Color.statusWarningText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DesignSystem.Color.labelTertiary)
                }
                .contentShape(Rectangle())
            }
            // `pillMenuStyle`, not `.borderlessButton`: the borderless style redraws the label
            // as a template image and DROPS its color — the warning triangle rendered grey, so
            // the amber token never showed. The explicit chevron keeps the "this opens a menu"
            // cue the borderless indicator used to give.
            .pillMenuStyle()
            .help("File missing — moved or deleted. Locate… to re-point it, or remove it.")
        }
        // `PlaylistItemRow`'s card metrics: its padding, its 34pt card and the 2pt seam between cards.
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .padding(.horizontal, DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, minHeight: DesignSystem.QueueRow.cardMinHeight, alignment: .leading)
        .padding(.vertical, DesignSystem.QueueRow.cardSeam / 2)
        .contentShape(Rectangle())
        .contextMenu { missingRowActions(row) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.display?.title ?? "Unknown Track"), unavailable — file missing")
        .accessibilityActions { missingRowActions(row) }
    }

    /// "Title · Artist", dimmed: the title secondary, the artist (when tagged) tertiary and smaller.
    func unavailableTitle(_ row: PlaylistDetailEntry) -> Text {
        let title = Text(row.display?.title ?? "Unknown Track")
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
        guard let artist = row.display?.artistName, !artist.isEmpty else { return title }
        let byline = Text(" · \(artist)")
            .font(DesignSystem.Font.caption)
            .foregroundStyle(DesignSystem.Color.labelTertiary)
        return Text("\(title)\(byline)")
    }
}

// MARK: - Restore-queue undo toast

private extension PlaylistDetailView {
    @ViewBuilder var restoreToast: some View {
        if restoreToastToken != nil, model.canRestorePreviousQueue {
            HStack(spacing: DesignSystem.Spacing.medium) {
                Text("Queue replaced")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.label)
                Button("Restore previous queue") {
                    model.restorePreviousQueue()
                    dismissRestoreToast()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Color.accentForeground)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            // Regime A/`.overlay` (S10.7 §3.1): a restore-toast floating over the list. The
            // `.bar` substrate preserves this pill's shipped look exactly (PR 1a is
            // zero-visual-change); S10.8 may unify it onto `.ultraThin`.
            .glassPanel(.overlay(.bar), in: Capsule())
            .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: 0.5))
            .padding(.bottom, DesignSystem.Spacing.large)
            .transition(.opacity)
        }
    }
}
