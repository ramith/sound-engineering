import SwiftUI

// MARK: - Right Panel

/// The right side of the Now Playing tab: the play queue (header, queue controls, and the
/// scrolling track list) or an empty-queue state.
struct RightPanelView: View {
    var body: some View {
        PlaylistView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
