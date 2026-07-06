import Foundation
import SwiftUI

@main
struct AdaptiveSound: App {
    // Quit on last-window close (single-window player; the engine lifecycle is window-bound —
    // see AppDelegate). Without this, closing the window leaves a windowless process behind.
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var audioViewModel: AudioViewModel
    @State private var eqViewModel: EQViewModel
    @State private var libraryModel: LibraryBrowseModel

    init() {
        // Build the single AudioViewModel once and share it with EQViewModel + LibraryBrowseModel.
        let audio = AudioViewModel()
        _audioViewModel = State(initialValue: audio)
        _eqViewModel = State(initialValue: EQViewModel(audioViewModel: audio))
        // S9.4: the browse model is owned HERE (above the tab switch) and injected, so Library
        // nav/selection/loaded state survives tab changes (LibraryTabView is switch-destroyed).
        _libraryModel = State(initialValue: LibraryBrowseModel(audio: audio))
    }

    var body: some Scene {
        WindowGroup {
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
        // App-owned chrome (L2): hide the native titlebar (traffic lights stay), let the
        // chrome band drag the window natively (no AppKit NSView), keep the content-driven
        // window minimum that AppShell now supplies.
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentMinSize)
        .commands {
            // No document model — drop the default New/Open items.
            CommandGroup(replacing: .newItem) {}

            // Escape hatch for the Library sidebar: its toolbar toggle is removed (L2), so
            // View ▸ Toggle Sidebar is the accessible way to re-show a divider-collapsed sidebar.
            SidebarCommands()

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
