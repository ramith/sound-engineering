import AppKit
import SwiftUI

/// The macOS menu-bar (status-bar) presence, rendered as a `.menu`-style `MenuBarExtra` in
/// `AdaptiveSound`. Mirrors the footer transport so playback is controllable without focusing
/// (or even showing) the app window: current track + play/pause/next/previous, then raise-window
/// and quit. Shares the single `AudioViewModel` with the window, so it drives the same engine.
struct MenuBarView: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    private var currentTrack: AudioFile? {
        guard let index = viewModel.selectedTrackIndex, index < viewModel.playlist.count else {
            return nil
        }
        return viewModel.playlist[index]
    }

    var body: some View {
        if let track = currentTrack {
            Text(track.name)
            Button(viewModel.isPlaying ? "Pause" : "Play") {
                if viewModel.isPlaying { viewModel.pause() } else { viewModel.play() }
            }
            Button("Next Track") { viewModel.nextTrack() }
            Button("Previous Track") { viewModel.previousTrack() }
        } else {
            Text("Nothing playing")
        }

        Divider()

        Button("Open AdaptiveSound") {
            // Restore the normal Dock-visible app and reopen the window if we retreated to the
            // menu bar; if a window is already showing, just bring it forward (avoid a duplicate).
            NSApp.setActivationPolicy(.regular)
            let hasContentWindow = NSApp.windows.contains {
                $0.styleMask.contains(.titled) && $0.canBecomeMain && $0.isVisible
            }
            if !hasContentWindow { openWindow(id: "main") }
            NSApp.activate()
        }
        Button("Quit AdaptiveSound") { NSApp.terminate(nil) }
    }
}
