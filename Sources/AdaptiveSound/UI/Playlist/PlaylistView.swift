import LibraryBrowseKit
import SwiftUI

// MARK: - Queue View (the current playback queue — S9 IA change)

/// The Now Playing queue: ONLY the current play queue, built by the Library's Play / Play Next /
/// Add to Queue verbs. Folder-loading moved to the Library section (design §4/§5), so there is no
/// folder chooser or "~/…" chip here anymore, and choosing a folder never rewrites this list.
///
/// S10.7 PR 5 (founder decision D7): a VIEW-LOCAL filter field — narrows the visible rows by
/// TITLE (reusing `FacetTextFilter`, the S9.6 primitive; path was a dead candidate — see
/// `filteredIndices`), never mutates the queue or playback, suppresses the transport Space
/// accelerator while focused, Escape clears, and Jump-to-Now-Playing clears it first rather
/// than silently failing (§5).
struct PlaylistView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Environment(LibraryBrowseModel.self) var library
    /// Observed by the list to scroll the current track into view (UI-2). A monotonic
    /// request-ID (not a Bool) so repeated presses re-fire even when the value would
    /// otherwise be unchanged. Bumped ONLY via `jumpToNowPlaying()` so an active filter is
    /// cleared before the list is asked to scroll.
    @State private var jumpToCurrentRequestID = 0
    /// Up Next (the live queue) vs. History (this session's plays). Local view state — the panel
    /// simply switches which list it shows (S10.2 3a).
    @State private var panelMode: QueuePanelMode = .upNext
    /// The D7 filter — view-local; empty means "filter off".
    @State private var filterText = ""
    @FocusState private var filterFocused: Bool
    /// Key-command focus for the queue list — owned HERE (not by the list) so the filter
    /// field's Escape can hand focus back to the queue (§5: ↑/↓ must work immediately).
    @FocusState private var queueFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            headerRow

            switch panelMode {
            case .upNext:
                if viewModel.queue.isEmpty {
                    emptyQueue
                } else if filteredIndices.isEmpty {
                    noMatches
                } else {
                    PlaylistItemList(jumpToCurrentRequestID: jumpToCurrentRequestID,
                                     visibleIndices: filteredIndices,
                                     reorderEnabled: !filterActive,
                                     queueFocused: $queueFocused)
                }
            case .history:
                QueueHistoryList()
            }
        }
    }

    // MARK: Header (S10.8 PR C — the realigned SINGLE 32pt row, `png/03`)

    /// Title + count + icon chips + the Up Next/Recent capsule pair + the compact filter
    /// pill, replacing the stacked header block / segmented picker / full-width filter bar.
    private var headerRow: some View {
        HStack(spacing: 12) {
            Text(panelMode == .history ? "Recently Played" : "Queue")
                .font(.system(.body, weight: .heavy))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.asLabel)
                .lineLimit(1)
                .layoutPriority(1)

            Text(headerSubtitle)
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(Color.asLabelTertiary)
                .lineLimit(1)

            PlaylistControlsView(onJumpToNowPlaying: jumpToNowPlaying, panelMode: $panelMode)

            QueueModeSwitcher(panelMode: $panelMode)

            Spacer(minLength: DesignSystem.Spacing.small)

            // The filter narrows Up Next only (a Recently-Played filter would be new
            // function, out of this styling wave) — hidden with the mode, not disabled.
            if panelMode == .upNext, !viewModel.queue.isEmpty {
                filterField
            }
        }
        .frame(height: DesignSystem.QueueHeader.height)
    }

    /// Mode-aware count: the queue's track count, or the number of recently-played tracks.
    private var headerSubtitle: String {
        let count = panelMode == .history ? library.history.count : viewModel.queue.count
        return "\(count) \(count == 1 ? "track" : "tracks")"
    }

    /// Jump-to-now-playing IGNORES an active filter (§5) — sequenced, not simultaneous:
    /// clear the filter in THIS transaction (the full list mounts, every row id registered),
    /// then bump the request-ID on the NEXT main-actor turn so the list's `onChange` +
    /// `scrollTo` run against the full list. Bumping in the same transaction targeted the
    /// FILTERED tree — a filtered-out (or No-Matches-unmounted) target row never scrolled,
    /// and a matching row centered against the wrong (still-narrowed) layout.
    private func jumpToNowPlaying() {
        filterText = ""
        Task { @MainActor in
            jumpToCurrentRequestID += 1
        }
    }

    /// Escape's landing (§5): clear, dismiss the field, and hand key focus to the queue so
    /// ↑/↓/Return work immediately — focus must never strand on a defocused field.
    private func clearFilterAndFocusQueue() {
        filterText = ""
        filterFocused = false
        queueFocused = true
    }

    private var filterActive: Bool {
        !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The visible queue positions under the filter (REAL indices — play/remove/menu actions
    /// keep operating on the true queue positions). Matches on the display TITLE only:
    /// `relativePath` is empty for library-queued tracks (the queue adapter never fills it —
    /// break-it MINOR-5), so it was a dead candidate; artist isn't carried by `AudioFile`.
    private var filteredIndices: [Int] {
        guard filterActive else { return Array(viewModel.queue.indices) }
        return viewModel.queue.indices.filter { index in
            FacetTextFilter.matches(viewModel.queue[index].file.name, query: filterText)
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.asLabelTertiary)
            TextField("Filter queue", text: $filterText)
                .textFieldStyle(.plain)
                .font(DesignSystem.Font.caption)
                .suppressesTransportSpace(while: $filterFocused)
                // `.onExitCommand` is the documented macOS cancel hook — the field editor's
                // `cancelOperation` can consume Escape before `.onKeyPress` ever sees it.
                // The key-press handler stays as belt-and-braces for paths where it does
                // fire (it only fires focused, so no guard).
                .onExitCommand(perform: clearFilterAndFocusQueue)
                .onKeyPress(.escape) {
                    clearFilterAndFocusQueue()
                    return .handled
                }
            if filterActive {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    filterText = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.asLabelTertiary)
                .help("Clear the filter")
            }
        }
        .padding(.horizontal, 10)
        // Realigned (`png/03`): a compact right-aligned pill — 190pt ideal, compressing to
        // its minimum before the header row's fixed neighbours would overflow (LAY-01).
        .frame(minWidth: DesignSystem.QueueHeader.filterMinWidth,
               idealWidth: DesignSystem.QueueHeader.filterIdealWidth,
               maxWidth: DesignSystem.QueueHeader.filterIdealWidth)
        .frame(height: DesignSystem.QueueHeader.filterHeight)
        .glassPanel(.badge, in: Capsule())
        .accessibilityLabel("Filter queue")
    }

    private var noMatches: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "magnifyingglass")
        } description: {
            Text("No queued track matches “\(filterText)”.")
        } actions: {
            Button("Clear Filter") { filterText = "" }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown whenever the queue is empty (fresh launch, or after Clear Queue). The queue is now
    /// filled from the Library, so the primary action is a doorway to it (design §4).
    private var emptyQueue: some View {
        ContentUnavailableView {
            Label("Queue is Empty", systemImage: "play.square.stack")
        } description: {
            Text("Browse your Library and press Play to start listening.")
        } actions: {
            Button("Browse Library") { viewModel.selectedTab = .library }
                .buttonStyle(.borderedProminent)
                .tint(Color.asAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Queue Controls (S10.8 PR C — 28pt icon chips, realigned `png/03`)

private struct PlaylistControlsView: View {
    @Environment(AudioViewModel.self) var viewModel
    let onJumpToNowPlaying: () -> Void
    @Binding var panelMode: QueuePanelMode

    var body: some View {
        HStack(spacing: 4) {
            // Clear Queue — Up Next only, and only when there's something to clear. Immediate
            // (no confirm, founder §3): the queue is cheap to rebuild and History is left intact.
            if panelMode == .upNext, !viewModel.queue.isEmpty {
                QueueIconButton(title: "Clear Queue", systemImage: "trash",
                                action: viewModel.clearPlaylist)
                    .help("Clear the queue (keeps History)")
            }

            QueueIconButton(title: "Shuffle", systemImage: "shuffle",
                            isOn: viewModel.shuffleEnabled,
                            action: viewModel.toggleShuffle)
                .accessibilityLabel("Shuffle: \(viewModel.shuffleEnabled ? "on" : "off")")
                .help("Shuffle: \(viewModel.shuffleEnabled ? "On" : "Off")")

            QueueIconButton(title: "Repeat",
                            systemImage: viewModel.repeatMode == 2 ? "repeat.1" : "repeat",
                            isOn: viewModel.repeatMode > 0,
                            action: viewModel.cycleRepeatMode)
                .accessibilityLabel("Repeat mode: \(["off", "all", "one"][viewModel.repeatMode])")
                .help(["Off", "All", "One"][viewModel.repeatMode])

            // Jump to now-playing — the owner's sequenced action (clear filter, THEN bump
            // the request-ID that triggers the list's scroll onChange).
            if viewModel.selectedTrackIndex != nil {
                QueueIconButton(title: "Jump to Now Playing", systemImage: "play.circle",
                                accented: true,
                                action: onJumpToNowPlaying)
                    .help("Jump to now playing")
            }
        }
    }
}

/// One 28×28 header chip: resting badge wash → hover lift → toggled-on accent tint with a
/// ring and an `accentText` glyph (all token'd, audited by R4-CHIP-01).
private struct QueueIconButton: View {
    let title: String
    let systemImage: String
    var isOn: Bool = false
    /// An always-teal ACTION glyph (jump-to-now-playing) — accent identity without the
    /// toggled-on chip treatment.
    var accented: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: DesignSystem.QueueHeader.iconSymbol, weight: .medium))
            .foregroundStyle(isOn || accented ? DesignSystem.Color.accentText : Color.asLabelSecond)
            .frame(width: DesignSystem.QueueHeader.iconButton,
                   height: DesignSystem.QueueHeader.iconButton)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                    .fill(isOn ? DesignSystem.Color.controlActiveFill
                        : hovering ? DesignSystem.Color.controlHover : DesignSystem.Color.hoverWash)
            }
            .overlay {
                if isOn {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                        .strokeBorder(DesignSystem.Color.accent.opacity(0.3), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.control,
                                           style: .continuous))
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Queue mode switcher (Up Next / Recent — the mini capsule pair)

/// The realigned segmented pair: a small `tabTrack` capsule with a `segmentSelected` lift —
/// the tab strip's grammar at header scale. Replaces `.pickerStyle(.segmented)`.
private struct QueueModeSwitcher: View {
    @Binding var panelMode: QueuePanelMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(QueuePanelMode.allCases) { mode in
                let selected = mode == panelMode
                Button {
                    panelMode = mode
                } label: {
                    Text(mode.pickerLabel)
                        .font(.callout.weight(selected ? .bold : .semibold))
                        .foregroundStyle(selected ? Color.asLabel : Color.asLabelSecond)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: DesignSystem.QueueHeader.segmentHeight)
                        .background {
                            if selected {
                                Capsule().fill(DesignSystem.Color.segmentSelected)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(DesignSystem.QueueHeader.segmentPadding)
        .background(TabTrackCapsule())
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: panelMode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Queue view")
        .accessibilityValue(panelMode.pickerLabel)
    }
}

// MARK: - Playlist Item List

private struct PlaylistItemList: View {
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

    /// Non-nil while the "Info" popover is showing; identifies which row's card is open by its
    /// stable `QueueItem.id` (dups-safe — keying on the URL popped the card on every duplicate row).
    /// Only one row presents at a time — the per-row `Binding<Bool>` is derived from this.
    @State private var infoTarget: QueueItem?

    /// The row a reorder drag is currently hovering over (drives the drop-target border). Nil when
    /// no drag is in progress.
    @State private var dropTargetIndex: Int?

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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleRows) { row in
                        queueRow(index: row.index, item: row.item)
                    }
                }
            }
            // The queue moved off `List` because a List row's `.dropDestination` never fires (an
            // Apple limitation, forum 730367) — so grip drag-and-drop reorder works here.
            // `.focusable` + `.focused` + `.defaultFocus` restore the key-command target that
            // `List` provided for free (a row tap also sets it); `.focusEffectDisabled` suppresses
            // the focus ring on the scroll area (the selection tint is the cue).
            .focusable()
            .focused(queueFocused)
            .defaultFocus(queueFocused, true)
            .focusEffectDisabled()
            .frame(maxHeight: .infinity)
            // Dismiss any open Info popover when the queue changes (remove / clear / reorder)
            // so a stale target can't match — and re-present on — a different row.
            .onChange(of: viewModel.queue.map(\.id)) { _, _ in
                infoTarget = nil
            }
            .onKeyPress(.upArrow) { moveSelection(by: -1) }
            .onKeyPress(.downArrow) { moveSelection(by: 1) }
            .onKeyPress(.return) { togglePlayIfSelected() }
            // No `.onKeyPress(.space)`: the Controls-menu Space key-equivalent is matched first
            // (disabled only while a text field is focused), so this handler was dead — Return
            // already covers keyboard toggle here (focus-audit nit).
            .onKeyPress(.delete) {
                guard let index = viewModel.selectedTrackIndex else { return .ignored }
                // Never remove a row the filter is HIDING (break-it MINOR-2): Delete on an
                // invisible selection silently removed — and could stop — the playing track
                // with no visible target. Visible rows only.
                guard visibleIndices.contains(index) else { return .ignored }
                viewModel.removeTrack(at: index)
                return .handled
            }
            // Scroll the current track into view when the header's "Jump to Now Playing" fires (UI-2).
            // Target the row's stable id (matches `.id(item.id)`), not a positional index.
            .onChange(of: jumpToCurrentRequestID) { _, _ in
                guard let index = viewModel.selectedTrackIndex, index < viewModel.queue.count else { return }
                withAnimation { proxy.scrollTo(viewModel.queue[index].id, anchor: .center) }
            }
        } // ScrollViewReader
    }

    private func queueRow(index: Int, item: QueueItem) -> some View {
        PlaylistItemRow(
            file: item.file,
            index: index,
            isSelected: viewModel.selectedTrackIndex == index,
            isNowPlaying: viewModel.isPlaying && viewModel.selectedTrackIndex == index,
            numberColumnWidth: numberColumnWidth,
            // Nil payload while the filter narrows the list = NO grip (the row API's own
            // non-reorderable state, built in S10.3): the affordance disappears with the
            // capability instead of offering a dead-end drag. The drop guard below stays
            // as belt-and-braces.
            dragPayload: reorderEnabled ? QueueDragItem(id: item.id) : nil,
            isDropTarget: dropTargetIndex == index
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
                // A click on a row focuses the queue for the keyboard shortcuts.
                queueFocused.wrappedValue = true
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
                set: { if !$0 { infoTarget = nil } }
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

    /// Move the selection by `delta` rows, clamped to the queue (keyboard ↑/↓). `.ignored` when
    /// there's no selection or the move would leave the queue, so the event can bubble.
    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard let current = viewModel.selectedTrackIndex else { return .ignored }
        let next = current + delta
        guard next >= 0, next < viewModel.queue.count else { return .ignored }
        viewModel.selectedTrackIndex = next
        return .handled
    }

    /// Toggle play/pause for the selected row (keyboard Return/Space). `.ignored` when nothing is
    /// selected so the key can do its default thing.
    private func togglePlayIfSelected() -> KeyPress.Result {
        guard viewModel.selectedTrackIndex != nil else { return .ignored }
        viewModel.togglePlayPause()
        return .handled
    }
}
