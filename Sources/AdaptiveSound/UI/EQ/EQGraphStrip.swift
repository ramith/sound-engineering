import EQEditKit
import SwiftUI

// MARK: - EQ graph strip (Sprint EQ, EQ3 — ui-plan §4)

/// The line across the top of the EQ graph's lens: what the graph is showing, in words. While the EQ
/// plays, the legend ("— plays · ● your setting") and the drag hint — or, with the graph under the
/// keyboard, the cursor's readout and its keys. Otherwise the state's own copy: Off, a held Compare,
/// Pure Mode (with Open Settings) or no engine yet. A stroke past +12 dB adds the ceiling's note.
/// No Headroom figure (decision 26).
///
/// EQ3t's seam: while a Tone row is hovered or dragged, its readout ("Tone · Presence 2–6 kHz +3.0 dB ·
/// 3 points held at +12") takes the hint's place in `playing`.
struct EQGraphStrip: View {
    let audible: EQAudibleState
    /// The keyboard cursor's readout, while the graph holds key focus in keyboard mode.
    let keyboardReadout: String?
    let isDragging: Bool
    /// A stroke is asking past +12 dB, and the ceiling holds the point.
    let isHeldAtCeiling: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            message
            Spacer(minLength: 8)
            if isHeldAtCeiling {
                Label("Held at +12 dB — the EQ's ceiling", systemImage: "arrow.up.to.line")
                    .foregroundStyle(DesignSystem.Color.meterHotText)
                    .fixedSize()
            }
        }
        .font(DesignSystem.Font.caption)
        .lineLimit(1)
    }

    @ViewBuilder private var message: some View {
        switch audible {
        case .playing:
            if let keyboardReadout {
                EQKeyboardReadout(text: keyboardReadout)
            } else {
                EQGraphLegend(showsHint: !isDragging)
            }
        case .engineNotReady:
            stateCopy("The audio engine isn't running yet — the EQ plays as set once it starts.",
                      short: "Audio engine not running yet")
        case .off:
            stateCopy("Equalizer off · the song plays without it, at matched loudness",
                      short: "Equalizer off · matched loudness")
        case .comparing:
            stateCopy("Without the EQ · matched loudness · release to return",
                      short: "Without the EQ · release to return")
        case .pureMode:
            stateCopy("Pure Mode is on — the EQ doesn't play. Switch to Enhanced to hear it.",
                      short: "Pure Mode is on — the EQ doesn't play.")
            Button("Open Settings", action: openSettings)
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Color.accentForeground)
                .pointerStyle(.link)
                .fixedSize()
        }
    }

    /// A state's line, giving way to its short form where the lens is too narrow.
    private func stateCopy(_ full: String, short: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(full)
            Text(short)
        }
        .foregroundStyle(DesignSystem.Color.labelSecondary)
        .accessibilityLabel(full)
    }
}
