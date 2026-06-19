import Foundation
import SwiftUI

@main
struct AdaptiveSound: App {
    @State private var audioViewModel: AudioViewModel
    @State private var eqViewModel: EQViewModel

    init() {
        // Build the single AudioViewModel once and share it with EQViewModel.
        let audio = AudioViewModel()
        _audioViewModel = State(initialValue: audio)
        _eqViewModel = State(initialValue: EQViewModel(audioViewModel: audio))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioViewModel)
                .environment(eqViewModel)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // No document model — drop the default New/Open items.
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Controls") {
                Button(audioViewModel.isPlaying ? "Pause" : "Play") {
                    if audioViewModel.isPlaying {
                        audioViewModel.stopPlayback()
                    } else {
                        audioViewModel.startPlayback()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(audioViewModel.selectedTrackIndex == nil)

                Divider()

                Button("Next Track") {
                    if let index = audioViewModel.selectedTrackIndex,
                       index + 1 < audioViewModel.playlist.count {
                        audioViewModel.playTrack(at: index + 1)
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(audioViewModel.selectedTrackIndex == nil)

                Button("Previous Track") {
                    if let index = audioViewModel.selectedTrackIndex, index > 0 {
                        audioViewModel.playTrack(at: index - 1)
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(audioViewModel.selectedTrackIndex == nil)
            }
        }
    }
}
