@testable import AdaptiveSound
import AppKit
import RigKit
import SwiftUI
import Testing

// MARK: - An inert carved slider looks inert in light (R1.1-B fix round, F4: review-ui M4)

//
// While Pure plays, the Tone sliders are disabled. Dark dims a disabled row 50% (`disabledDim`); light never dims —
// a control shows its own disabled look there (the grammar GlassSwitchStyle follows). The carved slider read no
// `isEnabled`, so in light an inert Tone slider drew pixel for pixel like a live one: the teal fill, the white knob
// with its edge and shade. A click did nothing — the "looks broken" US-R1F-20 exists to remove. Rendered offscreen in
// each appearance, as the picture sheets render it, a Tone slider at +6 dB (its fill showing).

/// A Tone slider at +6 dB, enabled or not.
private struct ToneSlider: View {
    let isEnabled: Bool
    @State private var value: Float = 6

    var body: some View {
        CarvedSlider(value: $value, range: -12 ... 12, step: 0.5, origin: 0, usesAppFocusRing: true,
                     accessibilityLabel: "Bass tone", accessibilityValueText: "plus 6 decibels")
            .disabled(!isEnabled)
            .frame(width: 200)
            .padding(10)
    }
}

@MainActor
@Suite("An inert carved slider looks inert in light (M4)", .serialized, .timeLimit(.minutes(1)))
struct CarvedSliderLookTests {
    /// The slider's pixels in `appearance`, once it has drawn.
    private static func drawn(enabled: Bool, in appearance: NSAppearance.Name) async throws -> [UInt8] {
        let host = OffscreenHost(ToneSlider(isEnabled: enabled), size: NSSize(width: 220, height: 40),
                                 appearance: appearance)
        defer { host.close() }
        try await untilOnMainRunLoop("the slider to draw") { host.pixels().contains { $0 != 0 } }
        return host.pixels()
    }

    @Test("SLIDER-LOOK-01: in light, a disabled carved slider doesn't draw as an enabled one")
    func lightDisabledLooksInert() async throws {
        let live = try await Self.drawn(enabled: true, in: .aqua)
        let inert = try await Self.drawn(enabled: false, in: .aqua)
        #expect(!live.isEmpty && live.count == inert.count)
        #expect(live != inert, "an inert slider in light draws exactly as a live one")
    }

    @Test("SLIDER-LOOK-02: in dark it draws as it always has — the row's 50% dim is its disabled look, not twice")
    func darkKeepsItsLook() async throws {
        let live = try await Self.drawn(enabled: true, in: .darkAqua)
        let inert = try await Self.drawn(enabled: false, in: .darkAqua)
        #expect(!live.isEmpty && live == inert)
    }
}
