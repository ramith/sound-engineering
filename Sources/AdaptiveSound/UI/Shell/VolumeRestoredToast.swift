import SwiftUI

// MARK: - "Volume restored" (R1.1-B, US-R1F-20 item 4)

/// The toast Master Gain's loan raises when Pure hands the device's volume back at a level it was not at — a stop
/// that ends playback, Enhanced starting, the output moving — so the listener knows why the Mac got louder (or
/// unmuted): "Volume restored", on every tab, non-blocking. Tapping opens Now Playing, where Master Gain is — and on
/// Now Playing, where it already is, the tap only dismisses it (no chevron, no promise to go anywhere).
/// Raised by `AudioViewModel.pureVolumeRestored()`; with the window closed nothing shows (the host's stale rule).
struct VolumeRestoredToast: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        let opens = Self.opensNowPlaying(from: viewModel.selectedTab)
        ShellToastHost(toast: viewModel.volumeRestoredToast.toast, systemImage: "speaker.wave.2",
                       hint: Self.hint(opening: opens), opens: opens) {
            if opens {
                viewModel.selectedTab = .nowPlaying
            }
            viewModel.volumeRestoredToast.dismiss()
        }
    }

    /// Whether the tap takes the listener to Now Playing: from every tab but Now Playing itself.
    static func opensNowPlaying(from tab: TabSelection) -> Bool {
        tab != .nowPlaying
    }

    /// VoiceOver's hint for the tap.
    static func hint(opening: Bool) -> String {
        opening ? "Opens Now Playing" : "Dismisses"
    }
}
