import SwiftUI

// MARK: - Queue panel mode + session-History list (S10.2 3a)

/// Which list the queue panel shows: the live queue (Up Next) or this session's plays (History).
enum QueuePanelMode: String, CaseIterable, Identifiable {
    case upNext
    case history

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .upNext: "Up Next"
        case .history: "History"
        }
    }
}

/// The session play-History list, newest first. Tapping a row plays that track NOW
/// (`playFromHistory` → `playTrackNextNow`), keeping the rest of the queue intact. History is
/// session-scoped + in-memory: never persisted, and Clear Queue leaves it untouched (founder §3a).
struct QueueHistoryList: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        if viewModel.sessionHistory.isEmpty {
            emptyHistory
        } else {
            List {
                // Newest first: reverse the append-ordered log. `rank` is the recency position
                // (0 → "1" = most recent) shown in the row's number column. Keyed on the stable
                // `HistoryItem.id` so replaying a track (a duplicate entry) stays distinct.
                ForEach(Array(viewModel.sessionHistory.reversed().enumerated()), id: \.element.id) { rank, item in
                    PlaylistItemRow(file: item.file, index: rank, isSelected: false, isNowPlaying: false)
                        // Same tap pattern as PlaylistItemList — `simultaneousGesture` so the
                        // recognizer doesn't claim exclusive priority (proven on macOS lists here).
                        .simultaneousGesture(
                            TapGesture().onEnded { viewModel.playFromHistory(item) }
                        )
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyHistory: some View {
        ContentUnavailableView {
            Label("Nothing Played Yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Tracks you play this session will appear here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
