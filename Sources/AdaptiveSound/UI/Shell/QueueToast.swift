import SwiftUI

// MARK: - Queue Toast

/// The queue-add confirmation (S9.5 §10.4) on the shell's toast host (`ShellToastHost`). Reads
/// `LibraryBrowseModel.queueToast`, hidden on the Now Playing tab (whose right panel already IS the
/// queue). Tapping opens Now Playing.
struct QueueToast: View {
    @Environment(LibraryBrowseModel.self) private var library
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        ShellToastHost(
            toast: viewModel.selectedTab == .nowPlaying ? nil : library.queueToast.toast,
            systemImage: "text.badge.plus",
            hint: "Opens Now Playing"
        ) {
            viewModel.selectedTab = .nowPlaying
            library.queueToast.dismiss() // clear now; don't rely on the render gate (review swiftui #2)
        }
        // Clear on entering Now Playing by ANY route (tap or manual tab switch) so a stale toast
        // can't reappear on return to a gated tab within the ~2 s window (review swiftui #2).
        .onChange(of: viewModel.selectedTab) { _, tab in
            if tab == .nowPlaying {
                library.queueToast.dismiss()
            }
        }
    }
}
