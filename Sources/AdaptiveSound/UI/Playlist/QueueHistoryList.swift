import Foundation
import SwiftUI

// MARK: - Queue panel mode + Recently Played list (S10.6)

/// Which list the queue panel shows: the live queue (Up Next) or the Recently-Played digest.
enum QueuePanelMode: String, CaseIterable, Identifiable {
    case upNext
    case history // internal name kept stable; the tab is LABELED "Recently Played" (S10.6)

    var id: String {
        rawValue
    }

    /// Compact label for the segmented picker (so "Up Next ｜ Recently Played" doesn't truncate).
    /// The full header title is set by `PlaylistHeaderView` ("Queue" / "Recently Played").
    var pickerLabel: String {
        switch self {
        case .upNext: "Up Next"
        case .history: "Recent"
        }
    }
}

/// The Recently-Played (frecency) list: each track ONCE, ranked by recency-weighted play frequency
/// (S10.6). Bound to `LibraryBrowseModel.history` — a persistent frecency store read — NOT the old
/// in-memory session log, so re-playing a track never adds a duplicate row. Tapping plays it now
/// (`playTrackNextNow`, non-destructive). Loads on appear and refreshes when a play crosses the
/// ≥60% threshold; empty until something has been heard through.
struct QueueHistoryList: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(LibraryBrowseModel.self) private var library

    var body: some View {
        Group {
            if library.history.isEmpty {
                emptyHistory
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(library.history) { track in
                            RecentlyPlayedRow(track: track, isNowPlaying: track.id == currentTrackID)
                                .accessibilityAction { library.playTrackNextNow(track) }
                                .simultaneousGesture(
                                    TapGesture().onEnded { library.playTrackNextNow(track) }
                                )
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .task { await library.loadHistory() }
        // A play crossing ≥60% bumps `playCountRevision` AFTER the store write commits, so the list
        // reorders without a manual revisit. This view exists only while the tab is on screen, so
        // the reload can't thrash during background album playback.
        .onChange(of: viewModel.playCountRevision) { _, _ in
            Task { await library.loadHistory() }
        }
    }

    /// The durable id of the track currently playing (drives the ▶ / accent cue), or nil.
    private var currentTrackID: Int64? {
        guard viewModel.isPlaying, let index = viewModel.selectedTrackIndex,
              index < viewModel.queue.count else { return nil }
        return viewModel.queue[index].file.trackID
    }

    private var emptyHistory: some View {
        ContentUnavailableView {
            Label("Nothing Played Yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Tracks you finish will appear here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
