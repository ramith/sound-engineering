import SwiftUI

// MARK: - Carved Slider (S10.7 PR 5 — the shared 8a slider primitive)

/// The interaction half of the 8a carved slider: LIVE-commit dragging (the value binding
/// updates continuously — gain must be audible while dragging), click-to-set, and FULL
/// keyboard/VoiceOver parity (§5 acceptance: reachable-but-inoperable is a PR failure):
/// focusable with the system focus ring, ←/→ step the value, VoiceOver reads the label +
/// value and supports adjustable increments. Visuals come from `CarvedTrack` (the sanctioned
/// appearance file); native `Slider` cannot render the carved look (`.tint` only), which is
/// what justifies this control existing at all. The footer scrubber (deferred-commit
/// semantics) adopts `CarvedTrack` in PR 6 with its own interaction wrapper.
struct CarvedSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0 ... 1
    var step: Float = 0.01
    let accessibilityLabel: String
    /// Spoken/read value, e.g. "4.0 decibels" — derived by the caller from the same binding.
    var accessibilityValueText: String

    @FocusState private var focused: Bool

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return Double((value - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { geo in
            CarvedTrack(fraction: fraction)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            set(fraction: drag.location.x / max(geo.size.width, 1))
                        }
                )
        }
        .frame(height: 20) // hit target taller than the visual track
        .focusable()
        .focused($focused)
        .onKeyPress(.leftArrow) { nudge(-step) }
        .onKeyPress(.rightArrow) { nudge(step) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = nudge(step)
            case .decrement: _ = nudge(-step)
            @unknown default: break
            }
        }
    }

    private func set(fraction raw: Double) {
        let clamped = Float(min(max(raw, 0), 1))
        let stepped = (range.lowerBound + clamped * (range.upperBound - range.lowerBound)) / step
        value = min(max(stepped.rounded() * step, range.lowerBound), range.upperBound)
    }

    private func nudge(_ delta: Float) -> KeyPress.Result {
        let next = min(max(value + delta, range.lowerBound), range.upperBound)
        guard next != value else { return .ignored }
        value = next
        return .handled
    }
}
