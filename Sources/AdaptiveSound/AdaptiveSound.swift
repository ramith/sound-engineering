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
    }
}
