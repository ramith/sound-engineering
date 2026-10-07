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
    /// The header row's Dynamic-Type-scaled minimum height (32pt at default size).
    @ScaledMetric(relativeTo: .body) private var headerHeight = DesignSystem.QueueHeader.height
    /// The filter pill's scaled height (28pt at default size).
    @ScaledMetric(relativeTo: .callout) private var filterHeight = DesignSystem.QueueHeader.filterHeight

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
        // A filter must not OUTLIVE the queue it narrowed (break-it finding: clear queue →
        // pill unmounts with its text retained → the NEXT queue arrives pre-narrowed to a
        // possibly-empty match set, with reorder silently disabled). Emptying the queue
        // resets the filter; a mode round-trip keeps it (the visible pill carries it).
        .onChange(of: viewModel.queue.isEmpty) { _, isEmpty in
            if isEmpty {
                filterText = ""
            }
        }
    }

    // MARK: Header (S10.8 PR C — the realigned SINGLE 32pt row, `png/03`)

    /// Title + count + icon chips + the Up Next/Recent capsule pair + the compact filter
    /// pill, replacing the stacked header block / segmented picker / full-width filter bar.
    /// Width-deficit policy at the 880pt minimum (break-it finding 2): the title is
    /// protected, the switcher/chips are rigid (`fixedSize` — a control label must never
    /// truncate), the filter compresses to its minimum first, and the COUNT subtitle is
    /// the designated truncation victim. Height is a scaled MINIMUM (finding 3) so larger
    /// text sizes grow the row instead of clipping.
    private var headerRow: some View {
        HStack(spacing: 12) {
            Text(panelMode == .history ? "Recently Played" : "Queue")
                .font(.system(.body, weight: .heavy))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.asLabel)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)

            Text(headerSubtitle)
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(Color.asLabelTertiary)
                .lineLimit(1)

            PlaylistControlsView(onJumpToNowPlaying: jumpToNowPlaying, panelMode: $panelMode)
                .fixedSize()

            QueueModeSwitcher(panelMode: $panelMode)
                .fixedSize()

            Spacer(minLength: DesignSystem.Spacing.small)

            // The filter narrows Up Next only (a Recently-Played filter would be new
            // function, out of this styling wave) — hidden with the mode, not disabled.
            if panelMode == .upNext, !viewModel.queue.isEmpty {
                filterField
            }
        }
        .frame(minHeight: headerHeight)
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
        .frame(height: filterHeight)
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
                .buttonStyle(.pill)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
