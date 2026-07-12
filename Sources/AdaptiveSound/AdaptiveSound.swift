import Foundation
import SwiftUI

@main
struct AdaptiveSound: App {
    // Resident menu-bar app: closing the window retreats to the menu bar (Dock icon hidden) and
    // does NOT quit — see AppDelegate. `initializeEngine()` is idempotent so window reopen is safe.
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var audioViewModel: AudioViewModel
    @State private var eqViewModel: EQViewModel
    @State private var library: LibraryModel
    @State private var libraryModel: LibraryBrowseModel
    /// Suppresses the global Space play/pause accelerator while a text field is focused (S4 SW1).
    @State private var keyboardFocus = KeyboardTransportFocus()

    init() {
        // Single instance only: if another copy already holds the lock, raise it and exit before
        // building any @State or touching the audio engine (no two engines fighting one device).
        guard SingleInstanceGuard.acquire() else { exit(0) }

        // Build the model peers once and wire the two edges between the audio VM and the library
        // subsystem (S3 F5 — the God-object split). `library` owns the store + scan/reconcile;
        // `audio` owns playback/engine. They are peers, NOT nested.
        let audio = AudioViewModel()
        let lib = LibraryModel()
        // Edge 1 (audio → library): the play-count write-back reaches the store through this
        // non-owning reference (see `AudioViewModel.countPlayCompletion`).
        audio.library = lib
        // Edge 2 (library → shell, via the composition root): surface library failures in the same
        // shell error banner the audio VM uses, WITHOUT giving LibraryModel a back-reference to the
        // audio VM (it stays testable in isolation). Mirrors the `onEngineReady` hook pattern.
        lib.onError = { [weak audio] message in audio?.errorMessage = message }
        _audioViewModel = State(initialValue: audio)
        _library = State(initialValue: lib)
        _eqViewModel = State(initialValue: EQViewModel(audioViewModel: audio))
        // S9.4: the browse model is owned HERE (above the tab switch) and injected, so Library
        // nav/selection/loaded state survives tab changes (LibraryTabView is switch-destroyed). It
        // composes BOTH peers — library reads + audio play verbs.
        _libraryModel = State(initialValue: LibraryBrowseModel(audio: audio, library: lib))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(audioViewModel)
                .environment(eqViewModel)
                .environment(library)
                .environment(libraryModel)
                .environment(keyboardFocus)
                .onAppear {
                    // Engine lifecycle belongs to the app/scene, NOT a child view's
                    // `.task`/`.onDisappear` (the latter is an unreliable teardown signal and
                    // was the fire-and-forget shutdown that couldn't complete at quit). Wire the
                    // terminate-time teardown owners (both peers — the library tears down BEFORE
                    // the engine, see AppDelegate) and start the engine here (single-window app, so
                    // this runs once); teardown runs in `AppDelegate.applicationShouldTerminate`.
                    appDelegate.audioViewModel = audioViewModel
                    appDelegate.libraryModel = library
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
                    audioViewModel.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                // A modifier-less menu key-equivalent is matched BEFORE the focused field editor,
                // so disable it while a text field is being edited — otherwise a space typed into a
                // Library filter (or the Save-Preset field) toggles playback instead of inserting a
                // space, breaking multi-word filtering (S4 SW1). Disabling lets the key fall through.
                .disabled(audioViewModel.selectedTrackIndex == nil || keyboardFocus.isTextEntryFocused)

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
