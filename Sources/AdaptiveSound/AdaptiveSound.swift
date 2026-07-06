import Foundation
import SwiftUI

@main
struct AdaptiveSound: App {
    // Resident menu-bar app: closing the window retreats to the menu bar (Dock icon hidden) and
    // does NOT quit — see AppDelegate. `initializeEngine()` is idempotent so window reopen is safe.
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var audioViewModel: AudioViewModel
    @State private var eqViewModel: EQViewModel
    @State private var libraryModel: LibraryBrowseModel

    init() {
        // Single instance only: if another copy already holds the lock, raise it and exit before
        // building any @State or touching the audio engine (no two engines fighting one device).
        guard SingleInstanceGuard.acquire() else { exit(0) }

        // Build the single AudioViewModel once and share it with EQViewModel + LibraryBrowseModel.
        let audio = AudioViewModel()
        _audioViewModel = State(initialValue: audio)
        _eqViewModel = State(initialValue: EQViewModel(audioViewModel: audio))
        // S9.4: the browse model is owned HERE (above the tab switch) and injected, so Library
        // nav/selection/loaded state survives tab changes (LibraryTabView is switch-destroyed).
        _libraryModel = State(initialValue: LibraryBrowseModel(audio: audio))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(audioViewModel)
                .environment(eqViewModel)
                .environment(libraryModel)
                .onAppear {
                    // Engine lifecycle belongs to the app/scene, NOT a child view's
                    // `.task`/`.onDisappear` (the latter is an unreliable teardown signal and
                    // was the fire-and-forget shutdown that couldn't complete at quit). Wire the
                    // terminate-time teardown owner and start the engine here (single-window app,
                    // so this runs once); teardown runs in `AppDelegate.applicationShouldTerminate`.
                    appDelegate.audioViewModel = audioViewModel
                    audioViewModel.initializeEngine()
                }
        }
        // App-owned chrome: a standard native titlebar carries the window buttons in their OWN
        // strip, so nothing overlaps the content — the app's chrome band and all content share a
        // single left margin (no traffic-light inset). The chrome band can still drag the window
        // natively; AppShell supplies the content-driven window minimum. (An earlier revision used
        // `.windowStyle(.hiddenTitleBar)`, but the buttons then overlapped the top-left and forced
        // an ~80pt indent on the chrome that misaligned it with the content — founder's call.)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 720) // open comfortably above the 880×640 hard minimum
        .commands {
            // No document model — drop the default New/Open items.
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Controls") {
                // Use the SAME transport semantics as the footer bar (L3): position-preserving
                // pause/play (not the old stopPlayback/startPlayback hard-stop that zeroed the
                // playhead), and shuffle/repeat-aware next/previous (not linear playTrack(at:)).
                // A menu key-equivalent wins over the queue's .onKeyPress, so spacebar MUST match
                // the footer's play button — otherwise the two global transports contradict.
                Button(audioViewModel.isPlaying ? "Pause" : "Play") {
                    if audioViewModel.isPlaying {
                        audioViewModel.pause()
                    } else {
                        audioViewModel.play()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(audioViewModel.selectedTrackIndex == nil)

                Divider()

                Button("Next Track") { audioViewModel.nextTrack() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(audioViewModel.selectedTrackIndex == nil)

                Button("Previous Track") { audioViewModel.previousTrack() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(audioViewModel.selectedTrackIndex == nil)
            }
        }

        // macOS menu-bar (top-bar) presence: quick transport + raise/quit, controllable without
        // focusing the window. Shares the single AudioViewModel, so it drives the same engine.
        MenuBarExtra("AdaptiveSound", systemImage: "music.note") {
            MenuBarView()
                .environment(audioViewModel)
        }
    }
}
