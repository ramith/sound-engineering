import LibraryBrowseKit
import SwiftUI

// MARK: - Playlist Item List

struct PlaylistItemList: View {
    @Environment(AudioViewModel.self) var viewModel
    /// Read-only scroll request (the OWNER sequences filter-clear before bumping it);
    /// observed via `onChange` to scroll the current track into view.
    let jumpToCurrentRequestID: Int
    /// The REAL queue positions to render (the D7 filter narrows this; actions keep true
    /// indices). Unfiltered = all indices.
    let visibleIndices: [Int]
    /// Reorder (grip drag + drop) is disabled while the filter narrows the list — moving a
    /// row relative to HIDDEN neighbours is incoherent; the context-menu moves stay.
    let reorderEnabled: Bool
    /// Keyboard-command focus for the scroll area. `List` owned key focus for free; a
    /// ScrollView/LazyVStack does not, so the ↑/↓/Return/Delete shortcuts are bound to this
    /// (`.focused` + default + set-on-tap). OWNED by `PlaylistView` so the filter field's
    /// Escape can hand focus back here.
    var queueFocused: FocusState<Bool>.Binding
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus

    /// Non-nil while the "Info" popover is showing; identifies which row's card is open by its
    /// stable `QueueItem.id` (dups-safe — keying on the URL popped the card on every duplicate row).
    /// Only one row presents at a time — the per-row `Binding<Bool>` is derived from this.
    @State private var infoTarget: QueueItem?

    /// The row a reorder drag is currently hovering over (drives the drop-target border). Nil when
    /// no drag is in progress.
    @State private var dropTargetIndex: Int?

    /// The keyboard-navigation cursor (a REAL queue index), DISTINCT from the now-playing
    /// pointer `viewModel.selectedTrackIndex`. Arrow keys move THIS — never the now-playing
    /// pointer — so navigating the queue no longer changes the hero / footer / Now Playing
    /// (which all read `selectedTrackIndex`); only Return/click actually plays a row and
    /// moves that pointer. The anchor of `keyboardCursor`; nil = none yet. Drives the
    /// `rowSelected` focus tint; the playing row keeps its own now-playing card independently.
    @State private var cursorIndex: Int?

    /// Track-number column width sized to the widest index in the list (~8 pt per monospaced
    /// digit + slack), so a 190-track list reserves room for 3 digits and never wraps "191".
    private var numberColumnWidth: CGFloat {
        let digits = max(2, String(viewModel.queue.count).count)
        return CGFloat(digits) * 8 + 6
    }

    /// ForEach rows keyed by the STABLE `QueueItem.id` — a positional-Int key re-identifies
    /// every row on reorder (moves render as content swaps, row-local state resets) — while
    /// still carrying the REAL queue index the row's actions need.
    private struct VisibleRow: Identifiable {
        let index: Int
        let item: QueueItem
        var id: QueueItem.ID {
            item.id
        }
    }

    private var visibleRows: [VisibleRow] {
        visibleIndices.compactMap { index in
            guard index < viewModel.queue.count else { return nil }
            return VisibleRow(index: index, item: viewModel.queue[index])
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            let ringIndex = ringCursorIndex
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleRows) { row in
                        queueRow(index: row.index, item: row.item, isKeyboardCursor: row.index == ringIndex)
                    }
                }
            }
            // The queue moved off `List` because a List row's `.dropDestination` never fires (an
            // Apple limitation, forum 730367) — so grip drag-and-drop reorder works here.
            // `.focusable` + `.focused` + `.defaultFocus` restore the key-command target that
            // `List` provided for free (a row tap also sets it); `.focusEffectDisabled` suppresses
            // the system ring around the whole scroll area — the cursor row's own `focusRing`
            // is the cue (A3). No visible row = no cursor = no focus stop.
            .focusable(!visibleIndices.isEmpty)
            .focused(queueFocused)
            .defaultFocus(queueFocused, true)
            .focusEffectDisabled()
            .frame(maxHeight: .infinity)
            // Dismiss any open Info popover when the queue changes (remove / clear / reorder)
            // so a stale target can't match — and re-present on — a different row. Also drop
            // a now-out-of-range cursor (the queue shrank).
            .onChange(of: viewModel.queue.map(\.id)) { _, _ in
                infoTarget = nil
                if let cursor = cursorIndex, cursor >= viewModel.queue.count {
                    cursorIndex = nil
                }
            }
            .onKeyPress(.upArrow) { moveCursor(by: -1, proxy: proxy) }
            .onKeyPress(.downArrow) { moveCursor(by: 1, proxy: proxy) }
            .onKeyPress(.return) { activateCursor() }
            // No `.onKeyPress(.space)`: the Controls-menu Space key-equivalent is matched first
            // (disabled only while a text field is focused), so this handler was dead — Return
            // already covers keyboard play/toggle here (focus-audit nit).
            .onKeyPress(.delete) { deleteCursorRow() }
            // Scroll the current track into view when the header's "Jump to Now Playing" fires (UI-2).
            // Target the row's stable id (matches `.id(item.id)`), not a positional index.
            .onChange(of: jumpToCurrentRequestID) { _, _ in
                guard let index = viewModel.selectedTrackIndex, index < viewModel.queue.count else { return }
                withAnimation { proxy.scrollTo(viewModel.queue[index].id, anchor: .center) }
            }
        } // ScrollViewReader
    }

    private func queueRow(index: Int, item: QueueItem, isKeyboardCursor: Bool) -> some View {
        PlaylistItemRow(
            file: item.file,
            index: index,
            // `isSelected` follows the KEYBOARD CURSOR (the focus tint), not the now-playing
            // pointer — so arrowing the queue highlights the focused row without disturbing
            // the hero. The now-playing card is a separate cue below.
            isSelected: cursorIndex == index,
            // PR D: the CURRENT row keeps its card while paused (prominence is no longer
            // tied to play state); `isPlaybackActive` gates only the equalizer motion.
            isNowPlaying: viewModel.selectedTrackIndex == index,
            isPlaybackActive: viewModel.isPlaying,
            numberColumnWidth: numberColumnWidth,
            // Nil payload while the filter narrows the list = NO grip (the row API's own
            // non-reorderable state, built in S10.3): the affordance disappears with the
            // capability instead of offering a dead-end drag. The drop guard below stays
            // as belt-and-braces.
            dragPayload: reorderEnabled ? QueueDragItem(id: item.id) : nil,
            isDropTarget: dropTargetIndex == index,
            isKeyboardCursor: isKeyboardCursor
        )
        // Identity is the stable `QueueItem.id` (matches the `ForEach` key via `VisibleRow`)
        // so reorders re-render the RIGHT rows — a positional key re-identifies every row
        // after a move. `scrollTo` targets this id too.
        .id(item.id)
        // Reorder: the grip is the `.draggable` source, each row a `.dropDestination` that lands
        // the dragged item at its position. This is why the queue is a LazyVStack, not a List.
        .dropDestination(for: QueueDragItem.self) { payloads, _ in
            dropTargetIndex = nil
            guard reorderEnabled, let fromID = payloads.first?.id else { return false }
            return viewModel.moveByDrop(fromID: fromID, toIndex: index)
        } isTargeted: { targeted in
            // No reorderEnabled guard here (break-it NIT-1): typing a filter mid-drag flips
            // reorder OFF, and a guard would swallow the un-target event — latching the
            // highlight on a row until the next drag. Tracking the hover is always safe;
            // only the DROP is gated (above).
            dropTargetIndex = targeted ? index : (dropTargetIndex == index ? nil : dropTargetIndex)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                // A click on a row focuses the queue for the keyboard shortcuts and lands the
                // cursor here (so subsequent arrows continue from where you clicked).
                queueFocused.wrappedValue = true
                cursorIndex = index
                // Single-click plays the row, so the now-playing card always matches the audio (no
                // select-without-play state). Re-clicking the playing track is a no-op (no restart).
                guard !(viewModel.isPlaying && viewModel.selectedTrackIndex == index) else { return }
                viewModel.playTrack(at: index)
            }
        )
        .accessibilityAddTraits(.isButton)
        // VoiceOver "activate" — the tap is a gesture VO can't trigger, so bind the play action.
        .accessibilityAction { viewModel.playTrack(at: index) }
        .contextMenu { queueRowMenu(index: index, item: item) }
        .popover(
            isPresented: Binding(
                get: { infoTarget?.id == item.id },
                set: {
                    if !$0 {
                        infoTarget = nil
                    }
                }
            ),
            arrowEdge: .trailing
        ) {
            TrackInfoCard(file: item.file)
        }
    }

    @ViewBuilder
    private func queueRowMenu(index: Int, item: QueueItem) -> some View {
        Button("Move to Top", systemImage: "arrow.up.to.line") {
            viewModel.moveTrackToTop(index)
        }
        .disabled(index == 0)
        Button("Move Up", systemImage: "arrow.up") {
            viewModel.moveTrackUp(index)
        }
        .disabled(index == 0)
        Button("Move Down", systemImage: "arrow.down") {
            viewModel.moveTrackDown(index)
        }
        .disabled(index >= viewModel.queue.count - 1)
        Button("Move to Bottom", systemImage: "arrow.down.to.line") {
            viewModel.moveTrackToBottom(index)
        }
        .disabled(index >= viewModel.queue.count - 1)
        Divider()
        Button("Info", systemImage: "info.circle") {
            infoTarget = item
        }
        Divider()
        Button("Remove from Queue", systemImage: "trash") {
            viewModel.removeTrack(at: index)
        }
        Button("Clear Queue", systemImage: "clear") {
            viewModel.clearPlaylist()
        }
    }

    /// The ONE keyboard cursor (A3, A-review) — the ring row, the row ↑/↓ move from, and the row
    /// Return plays and Delete removes: the cursor index when visible, else the playing row when
    /// visible, else the first visible row. Visible-only, so a filter-hidden row (possibly the
    /// playing track) is never acted on with no visible target (break-it MINOR-2).
    private var keyboardCursor: ListKeyboardCursor<Int>? {
        ListKeyboardCursor.resolve(rows: visibleIndices, anchor: cursorIndex,
                                   fallback: viewModel.selectedTrackIndex)
    }

    /// The ring is drawn while the queue holds key focus AND the user navigates by keyboard.
    private var showsRing: Bool {
        queueFocused.wrappedValue && showsKeyboardFocus
    }

    /// The row wearing the focus ring, or nil (no ring).
    private var ringCursorIndex: Int? {
        showsRing ? keyboardCursor?.id : nil
    }

    /// Return/Delete target: the cursor row when something on screen marks it (see
    /// `ListKeyboardCursor.actionTarget`), as a still-valid REAL queue index.
    private var actionIndex: Int? {
        guard let index = keyboardCursor?.actionTarget(ringVisible: showsRing),
              index < viewModel.queue.count else { return nil }
        return index
    }

    /// Move the keyboard CURSOR by `delta` VISIBLE rows — never `selectedTrackIndex`, so the
    /// hero/footer/Now Playing (which read that pointer) don't move while you navigate
    /// (founder bug). Navigates the visible (filter-narrowed) set, so the cursor can't land
    /// on a hidden row. With no cursor yet, the first press (either arrow) claims the ring row
    /// — the playing row when visible, else the first; scrolls the cursor into view.
    /// `.ignored` when the move would leave the list, so the event can bubble.
    private func moveCursor(by delta: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let target = keyboardCursor?.step(by: delta, in: visibleIndices),
              target < viewModel.queue.count else { return .ignored }
        cursorIndex = target
        // Keep the cursor on screen (nil anchor = scroll the minimum needed, no jump).
        proxy.scrollTo(viewModel.queue[target].id)
        return .handled
    }

    /// Return: play the cursor row, or toggle play/pause when it is already the playing track
    /// (mirrors the row's tap semantics), claiming it as the cursor. `.ignored` with no target
    /// so the key can bubble.
    private func activateCursor() -> KeyPress.Result {
        guard let index = actionIndex else { return .ignored }
        cursorIndex = index
        if viewModel.selectedTrackIndex == index {
            viewModel.togglePlayPause()
        } else {
            viewModel.playTrack(at: index)
        }
        return .handled
    }

    /// Delete: remove the cursor row. The cursor stays at that position, so the next row
    /// slides under it.
    private func deleteCursorRow() -> KeyPress.Result {
        guard let index = actionIndex else { return .ignored }
        cursorIndex = index
        viewModel.removeTrack(at: index)
        return .handled
    }
}
