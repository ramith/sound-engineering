import DesignTokenKit
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
///
/// OPT-IN behaviours (EQ3t's Tone sliders turn them on; with the defaults the inspector's
/// Intensity and Master Gain sliders behave and look exactly as shipped):
/// - `origin`: a CENTRE-ZERO slider (±12 dB around 0) — the fill grows from that value toward the
///   knob, with a mark in the groove at it;
/// - `stepsWithVerticalArrows`: ↑/↓ step the value too (NSSlider parity);
/// - `usesAppFocusRing`: the app's keyboard-only ring (`controlFocusRing`) in place of the system
///   focus effect, so a click never leaves a ring behind;
/// - `onEditingChanged`: brackets a DRAG, as `Slider`'s does — `true` at mouse-down, before the
///   first value; `false` at mouse-up. A key or VoiceOver step is one change with no bracket.
struct CarvedSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0 ... 1
    var step: Float = 0.01
    /// The value the fill grows from; `nil` is the range's lower bound.
    var origin: Float?
    var stepsWithVerticalArrows = false
    var usesAppFocusRing = false
    let accessibilityLabel: String
    /// Spoken/read value, e.g. "4.0 decibels" — derived by the caller from the same binding.
    var accessibilityValueText: String
    var onEditingChanged: ((Bool) -> Void)?

    /// A drag is in progress (between its `onEditingChanged` brackets).
    @State private var isDragging = false
    /// The pointer is down on the track. Unlike `onEnded`, its reset comes for a drag the system
    /// cancels too, so every drag that began ends (`onEditingChanged(false)`).
    @GestureState private var isPressing = false

    var body: some View {
        GeometryReader { geo in
            CarvedTrack(fraction: fraction(of: value), origin: fraction(of: origin ?? range.lowerBound))
                // Fill the GeometryReader (it top-aligns by default) so the contentShape —
                // and therefore the drag — covers the FULL 20pt hit target, not just the
                // track's own 14pt band.
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressing) { _, pressing, _ in pressing = true }
                        .onChanged { drag in
                            beginDragIfNeeded()
                            // Map the pointer onto the KNOB'S travel ([knob/2, width−knob/2]
                            // — the same inset `CarvedTrack` renders with), not the raw
                            // width: this is a LIVE-commit audio control, so mouse-down on
                            // the knob at either extreme must be value-neutral, never a jump.
                            let knob = CGFloat(GlassDecor.sliderKnobSize)
                            set(fraction: (drag.location.x - knob / 2) / max(geo.size.width - knob, 1))
                        }
                        .onEnded { _ in endDrag() }
                )
                .onChange(of: isPressing) { _, pressing in
                    if !pressing {
                        endDrag()
                    }
                }
        }
        .frame(height: 20) // hit target taller than the visual track
        .focusable()
        .modifier(CarvedSliderFocusLook(usesAppFocusRing: usesAppFocusRing))
        // A focused slider OWNS its arrows (NSSlider parity): consume the key even at the
        // bounds — a bubbled ← at min must not reach whatever the enclosing context binds
        // arrows to (PR 6 puts a CarvedTrack scrubber next to the footer transport). ↑/↓ are
        // the slider's only when `stepsWithVerticalArrows`; otherwise they pass on, as shipped. A
        // shortcut (⌘ ⌥ ⌃) always passes, so ⌘← / ⌘→ skip tracks from a focused slider too.
        .onKeyPress(keys: [.leftArrow, .rightArrow, .downArrow, .upArrow], action: handleArrow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(step)
            case .decrement: nudge(-step)
            @unknown default: break
            }
        }
    }

    private func fraction(of value: Float) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return Double((value - range.lowerBound) / span)
    }

    private func beginDragIfNeeded() {
        guard !isDragging else { return }
        isDragging = true
        onEditingChanged?(true)
    }

    private func endDrag() {
        guard isDragging else { return }
        isDragging = false
        onEditingChanged?(false)
    }

    private func set(fraction raw: Double) {
        let clamped = Float(min(max(raw, 0), 1))
        let stepped = (range.lowerBound + clamped * (range.upperBound - range.lowerBound)) / step
        value = min(max(stepped.rounded() * step, range.lowerBound), range.upperBound)
    }

    private func nudge(_ delta: Float) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }

    /// An arrow key on the focused slider: ← / → always, ↑ / ↓ when opted in; never a shortcut.
    private func handleArrow(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut else { return .ignored }
        let isVertical = press.key == .upArrow || press.key == .downArrow
        guard !isVertical || stepsWithVerticalArrows else { return .ignored }
        nudge(press.key == .rightArrow || press.key == .upArrow ? step : -step)
        return .handled
    }
}
