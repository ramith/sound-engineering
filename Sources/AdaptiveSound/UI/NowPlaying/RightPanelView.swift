import SwiftUI

// MARK: - Right Panel

/// The right side of the Now Playing tab: the full playlist (header, controls,
/// Choose Folder, and the scrolling track list).
struct RightPanelView: View {
    var body: some View {
        PlaylistView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
