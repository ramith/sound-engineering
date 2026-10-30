@testable import AdaptiveSound
import Foundation
import RigKit
import SettingsKit
import SwiftUI
import Testing

// MARK: - The shared row gate keeps the control it gates (R1.1-B fix round, F4: review-ui M1, review-sound N13)

//
// When the path in use flips — a song starts in Pure after the listener switched it on, a device move, the next
// start after Leave Pure — the gated control must stay the SAME view: a Tone drag in flight has to end through the
// slider's own cancel path, and VoiceOver's cursor and the keyboard focus stay on it. A gate that swaps its content
// between two branches rebuilds the control instead: its `@State` (the slider's drag) is gone, and the drag's
// stroke is left open. The real view model drives the flip, through the transport tick, as the engine reports it.

/// Each appearance of the gated control: its identity (a token its `@State` holds) and whether it was enabled.
@MainActor
private final class Sightings {
    var seen: [(token: UUID, enabled: Bool)] = []
}

/// A control stand-in: reports its identity and its enabled state whenever either is (re)made or changes.
private struct IdentityProbe: View {
    let sightings: Sightings
    @State private var token = UUID()
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onAppear { sightings.seen.append((token, isEnabled)) }
            .onChange(of: isEnabled) { _, enabled in sightings.seen.append((token, enabled)) }
    }
}

/// The probe under the shared gate, as a DSP row wears it, reading the real view model.
private struct GatedProbe: View {
    @Environment(AudioViewModel.self) private var audio
    let sightings: Sightings

    var body: some View {
        IdentityProbe(sightings: sightings)
            .bitPerfectGate(.tone, audio.dspRowAvailability)
    }
}

@MainActor
@Suite("The shared row gate keeps its control when the path flips (M1, N13)", .serialized, .timeLimit(.minutes(2)),
       .attachingLogTail)
struct BitPerfectGateTests {
    @Test("GATE-01: Enhanced → Pure → Enhanced at a song start: the gated control is the same view throughout")
    func gateKeepsTheControlAcrossAPathFlip() async throws {
        let player = try await FakePlayer.launched(tracks: 1)
        try await player.play(at: 0)
        let sightings = Sightings()
        let host = OffscreenHost(GatedProbe(sightings: sightings).environment(player.vm))
        defer { host.close() }
        try await untilOnMainRunLoop("the gated control to appear, live") { sightings.seen.last?.enabled == true }

        player.engine.state.withLock { $0.signalPath.path = .pure }
        try player.tick()
        #expect(!player.vm.dspRowAvailability.isLive, "Pure plays: the row is inert")
        try await untilOnMainRunLoop("the gated control to read disabled") { sightings.seen.last?.enabled == false }

        player.engine.state.withLock { $0.signalPath.path = .enhanced }
        try player.tick()
        try await untilOnMainRunLoop("the gated control to read enabled again") {
            sightings.seen.last?.enabled == true
        }
        let identities = Set(sightings.seen.map(\.token))
        #expect(identities.count == 1, "the control was rebuilt \(identities.count - 1) time(s): \(sightings.seen)")
    }
}
