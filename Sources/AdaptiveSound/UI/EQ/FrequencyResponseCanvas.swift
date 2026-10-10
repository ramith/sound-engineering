import EQEditKit
import SwiftUI

// MARK: - Frequency Response Canvas

struct FrequencyResponseCanvas: View {
    let eqViewModel: EQViewModel

    // Plot-margin constants — single source of truth for drawing and gesture handler.
    // The right inset is wide (was 20): the 20 kHz band sits at `plotRight`, and the whole
    // right inset maps to that last band, so a roomier inset both un-crowds the dot from the
    // window edge and enlarges its drag/hit zone (the far-right point was easy to miss). The
    // left inset already doubles as the dB-label gutter.
    private let plotLeftInset: CGFloat = 50
    private let plotRightInset: CGFloat = 44
    private let plotTopInset: CGFloat = 20
    private let plotBottomInset: CGFloat = 40

    /// Captured layout size for gesture coordinate mapping.
    @State private var canvasSize: CGSize = .zero

    /// Whether the drag under way has begun its stroke (its first sample did); cleared when it ends.
    /// `isDragging` resets even on a drag the system cancels (which never reaches `onEnded`).
    @State private var strokeBegan = false
    @GestureState private var isDragging = false

    /// The band the keyboard arrow keys currently target, and whether the canvas holds keyboard
    /// focus (A-H1). A click moves it to the clicked band and focuses the graph (UI plan §5.3), which
    /// is also what lets Esc reach a drag. A vertical column marks this band in keyboard mode only.
    @State private var keyboardBand = 15
    @FocusState private var canvasFocused: Bool
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus

    /// Per-keystroke / per-VoiceOver-swipe gain increment (dB).
    private let gainStep: Float = 1.0

    var body: some View {
        Canvas { context, size in
            let bgPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
            context.fill(bgPath, with: .color(Color.asCard))

            let borderPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
            context.stroke(borderPath, with: .color(Color.asHairline), lineWidth: 0.5)

            let map = plotMap(for: size)

            drawGridAndLabels(context: &context, map: map)

            let eqValues: [(freq: Double, gain: Double)] = zip(EQBands.nominalHz, eqViewModel.points)
                .map { freq, gain in (freq, Double(gain)) }

            drawFrequencyResponseCurve(context: &context, eqValues: eqValues, map: map)
            drawISOOctaveDots(context: &context, eqValues: eqValues, map: map)

            // Keyboard-editing cursor (A-H1): a vertical "selected frequency column" highlight on the
            // targeted band, drawn while the canvas holds focus in keyboard mode, so an arrow-key user
            // can see which band they're adjusting (the band's own dot sits within the column).
            if canvasFocused && showsKeyboardFocus {
                drawKeyboardCursor(context: &context, map: map, bandIndex: keyboardBand)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($isDragging) { _, dragging, _ in dragging = true }
                .onChanged { value in strokeSample(at: value.location) }
                .onEnded { _ in endStroke() }
        )
        // A stroke never outlives its drag: a cancelled drag resets `isDragging`, and a tab switch
        // mid-drag takes the graph away.
        .onChange(of: isDragging) { _, dragging in
            if !dragging {
                endStroke()
            }
        }
        .onDisappear { endStroke() }
        .background(Color.asCard)
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5)
        }
        // Keyboard editing (A-H1): Tab focuses the canvas, ← / → move the band cursor, ↑ / ↓ adjust
        // the targeted band's gain by ±`gainStep` dB. Esc cancels a drag (else it bubbles).
        .focusable()
        .focused($canvasFocused)
        // The app's keyboard ring in place of the system focus effect (S10.8 D3): a click focuses the
        // graph without leaving a ring behind; keyboard mode shows it, inside the surface's clip.
        .focusEffectDisabled()
        .keyboardFocusRing(canvasFocused && showsKeyboardFocus,
                           around: RoundedRectangle(cornerRadius: 9).inset(by: ControlMetrics.focusRingOutset))
        .onKeyPress(.leftArrow) { moveKeyboardCursor(-1); return .handled }
        .onKeyPress(.rightArrow) { moveKeyboardCursor(1); return .handled }
        .onKeyPress(.upArrow) { eqViewModel.nudge(band: keyboardBand, by: gainStep); return .handled }
        .onKeyPress(.downArrow) { eqViewModel.nudge(band: keyboardBand, by: -gainStep); return .handled }
        .onKeyPress(.escape) { eqViewModel.cancelStroke() ? .handled : .ignored }
        .accessibilityElement()
        .accessibilityLabel("Frequency Response Curve")
        .accessibilityValue("EQ Preset: \(eqViewModel.summary)")
        .accessibilityHint("Adjust each band from the elements inside, or drag the curve with a pointer.")
        // VoiceOver editing (A-H1): synthetic, a11y-only children — NOT rendered and NOT hit-tested,
        // so they can't intercept the mouse `DragGesture`. Each is an adjustable element: VoiceOver
        // focuses a band and swipes up/down to change its gain ("1 kilohertz, +3 decibels").
        .accessibilityChildren {
            ForEach(EQBands.nominalHz.indices, id: \.self) { index in
                Rectangle()
                    .accessibilityLabel(Text(bandFrequencyLabel(index)))
                    .accessibilityValue(Text(bandGainLabel(index)))
                    .accessibilityAdjustableAction { direction in
                        eqViewModel.nudge(band: index, by: direction == .increment ? gainStep : -gainStep)
                    }
            }
        }
    }

    // MARK: - Accessible / keyboard band editing (A-H1)

    /// Move the keyboard-cursor band, clamped to 0…30.
    private func moveKeyboardCursor(_ delta: Int) {
        keyboardBand = max(0, min(EQBands.nominalHz.count - 1, keyboardBand + delta))
    }

    /// VoiceOver-spoken band frequency ("1 kilohertz" / "3150 hertz") — words, not "kHz"/"Hz",
    /// which VoiceOver would spell out letter by letter.
    private func bandFrequencyLabel(_ index: Int) -> String {
        let hz = EQBands.nominalHz[index]
        if hz >= 1000 {
            let kHz = hz / 1000
            let value = kHz.truncatingRemainder(dividingBy: 1) < 0.001
                ? "\(Int(kHz))"
                : kHz.formatted(.number.precision(.fractionLength(1)))
            return "\(value) kilohertz"
        }
        return "\(Int(hz)) hertz"
    }

    /// VoiceOver-spoken band gain ("+3 decibels" / "-4.5 decibels" / "0 decibels").
    private func bandGainLabel(_ index: Int) -> String {
        let gain = (eqViewModel.points[index] * 10).rounded() / 10
        let sign = gain > 0 ? "+" : ""
        return "\(sign)\(gain.formatted(.number.precision(.fractionLength(1)))) decibels"
    }

    // MARK: - Plot map

    /// The plot's coordinate map for the given canvas size (same insets the `Canvas` uses). Built
    /// here too so the drag hit-test picks bands with the SAME math the dots are drawn with.
    private func plotMap(for size: CGSize) -> EQPlotMap {
        EQPlotMap(
            left: plotLeftInset,
            right: size.width - plotRightInset,
            top: plotTopInset,
            bottom: size.height - plotBottomInset
        )
    }

    // MARK: - Gesture Handler

    /// One pointer sample of a drag, at the dot nearest the pointer and the pointer's level (the kit
    /// holds it in ±12). The first sample begins the stroke: the keyboard cursor follows the click
    /// and the graph takes focus. The view model shapes the curve (`EQStroke`) and sends it.
    private func strokeSample(at location: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let map = plotMap(for: canvasSize)
        guard map.width > 0, map.height > 0 else { return }
        let band = map.nearestBand(toX: location.x)
        if !strokeBegan {
            strokeBegan = true
            keyboardBand = band
            canvasFocused = true
            eqViewModel.beginStroke()
        }
        eqViewModel.updateStroke(band: band, db: Float(map.gain(forY: location.y)))
    }

    /// The drag is over — released, cancelled, or the graph went away: the stroke is kept (the view
    /// model persists and logs it once; a second call is a no-op).
    private func endStroke() {
        strokeBegan = false
        eqViewModel.endStroke()
    }
}
