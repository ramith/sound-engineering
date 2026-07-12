import SwiftUI

// MARK: - Frequency Response Canvas

struct FrequencyResponseCanvas: View {
    let eqViewModel: EQViewModel
    let isUsingDiscreteSteps: Bool

    // Plot-margin constants — single source of truth for drawing and gesture handler.
    private let plotLeftInset: CGFloat = 50
    private let plotRightInset: CGFloat = 20
    private let plotTopInset: CGFloat = 20
    private let plotBottomInset: CGFloat = 40

    /// Captured layout size for gesture coordinate mapping.
    @State private var canvasSize: CGSize = .zero

    /// Tracks the last touched band within a drag stroke for gap-fill interpolation.
    @State private var lastBandIndex: Int?

    /// The band the keyboard arrow keys currently target, and whether the canvas holds keyboard
    /// focus (A-H1). The mouse drag and VoiceOver each edit independently of this cursor — it exists
    /// purely so a sighted keyboard-only user can see and move the band they're about to adjust. A
    /// highlight ring is drawn on this band only while `canvasFocused`.
    @State private var keyboardBand = 15
    @FocusState private var canvasFocused: Bool

    /// Per-keystroke / per-VoiceOver-swipe gain increment (dB).
    private let gainStep: Float = 1.0

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            let bgPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
            context.fill(bgPath, with: .color(Color.asCard))

            let borderPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
            context.stroke(borderPath, with: .color(Color.asHairline), lineWidth: 0.5)

            let geometry = PlotGeometry(
                left: plotLeftInset,
                right: width - plotRightInset,
                top: plotTopInset,
                bottom: height - plotBottomInset
            )

            drawGridAndLabels(context: &context, geometry: geometry)

            let eqValues: [(freq: Double, gain: Double)] = EQPreset.isoFrequencies
                .enumerated()
                .map { index, freq in (freq, Double(eqViewModel.bandGains[index])) }

            drawFrequencyResponseCurve(context: &context, eqValues: eqValues, geometry: geometry)
            drawISOOctaveDots(context: &context, eqValues: eqValues, geometry: geometry)

            // Keyboard-editing cursor (A-H1): a vertical guide + ring on the targeted band, drawn
            // only while the canvas holds keyboard focus, so an arrow-key user can see which band
            // they're adjusting. Reuses the same log-x / linear-y mapping as `drawISOOctaveDots`.
            if canvasFocused {
                drawKeyboardCursor(context: &context, geometry: geometry, bandIndex: keyboardBand)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in updateEQFromDrag(location: value.location) }
                .onEnded { _ in
                    lastBandIndex = nil
                    // Persist once at drag-end (not per-sample — see commitCustomBandEdits).
                    eqViewModel.persistLiveState()
                }
        )
        .background(Color.asCard)
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5)
        }
        // Keyboard editing (A-H1): Tab focuses the canvas, ← / → move the band cursor, ↑ / ↓ adjust
        // the targeted band's gain by ±`gainStep` dB. Coexists with the mouse `DragGesture` above.
        .focusable()
        .focused($canvasFocused)
        .onKeyPress(.leftArrow) { moveKeyboardCursor(-1); return .handled }
        .onKeyPress(.rightArrow) { moveKeyboardCursor(1); return .handled }
        .onKeyPress(.upArrow) { adjustBand(keyboardBand, by: gainStep); return .handled }
        .onKeyPress(.downArrow) { adjustBand(keyboardBand, by: -gainStep); return .handled }
        .accessibilityElement()
        .accessibilityLabel("Frequency Response Curve")
        .accessibilityValue(
            "EQ Preset: \(eqViewModel.selectedPresetName), "
                + "Blending: \(isUsingDiscreteSteps ? "Discrete Steps" : "Smooth Curve")"
        )
        .accessibilityHint("Adjust each band from the elements inside, or drag the curve with a pointer.")
        // VoiceOver editing (A-H1): synthetic, a11y-only children — NOT rendered and NOT hit-tested,
        // so they can't intercept the mouse `DragGesture`. Each is an adjustable element: VoiceOver
        // focuses a band and swipes up/down to change its gain ("1 kilohertz, +3 decibels"). Before
        // this, the curve was a single read-only element editable only by dragging — unreachable by
        // VoiceOver (grep-verified: no other per-band input path exists).
        .accessibilityChildren {
            ForEach(EQPreset.isoFrequencies.indices, id: \.self) { index in
                Rectangle()
                    .accessibilityLabel(Text(bandFrequencyLabel(index)))
                    .accessibilityValue(Text(bandGainLabel(index)))
                    .accessibilityAdjustableAction { direction in
                        adjustBand(index, by: direction == .increment ? gainStep : -gainStep)
                    }
            }
        }
    }

    // MARK: - Accessible / keyboard band editing (A-H1)

    /// Move the keyboard-cursor band, clamped to 0…30.
    private func moveKeyboardCursor(_ delta: Int) {
        keyboardBand = max(0, min(EQPreset.isoFrequencies.count - 1, keyboardBand + delta))
    }

    /// Nudge one band's gain (keyboard ↑/↓ or a VoiceOver increment/decrement) and commit. Unlike
    /// the drag path — which persists once at `.onEnded` — each discrete step both dispatches to the
    /// DSP (`commitCustomBandEdits` clamps + marks custom) and persists, since there is no stroke end.
    private func adjustBand(_ index: Int, by delta: Float) {
        guard eqViewModel.bandGains.indices.contains(index) else { return }
        eqViewModel.bandGains[index] = max(-12.0, min(12.0, eqViewModel.bandGains[index] + delta))
        eqViewModel.commitCustomBandEdits()
        eqViewModel.persistLiveState()
    }

    /// VoiceOver-spoken band frequency ("1 kilohertz" / "3150 hertz") — words, not "kHz"/"Hz",
    /// which VoiceOver would spell out letter by letter.
    private func bandFrequencyLabel(_ index: Int) -> String {
        let hz = EQPreset.isoFrequencies[index]
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
        let gain = (eqViewModel.bandGains[index] * 10).rounded() / 10
        let sign = gain > 0 ? "+" : ""
        return "\(sign)\(gain.formatted(.number.precision(.fractionLength(1)))) decibels"
    }

    // MARK: - Gesture Handler

    private func updateEQFromDrag(location: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        let plotLeft = plotLeftInset
        let plotRight = canvasSize.width - plotRightInset
        let plotBottom = canvasSize.height - plotBottomInset
        let plotWidth = plotRight - plotLeft
        let plotHeight = plotBottom - plotTopInset
        guard plotWidth > 0, plotHeight > 0 else { return }

        let relativeX = max(0.0, min(1.0, (location.x - plotLeft) / plotWidth))
        let bandIndex = max(0, min(30, Int((relativeX * 30.0).rounded())))

        let relativeY = max(0.0, min(1.0, (plotBottom - location.y) / plotHeight))
        // Clamp to the DSP range [-12, +12] dB (the kernel's hard limit), not the
        // ±20 visual span — the canvas must never write out-of-range gains.
        let cursorGain = Float(max(-12.0, min(12.0, relativeY * 40.0 - 20.0)))

        if let previousIndex = lastBandIndex, abs(bandIndex - previousIndex) > 1 {
            fillGapBetweenBands(
                from: previousIndex,
                to: bandIndex,
                startGain: eqViewModel.bandGains[previousIndex],
                endGain: cursorGain
            )
        } else {
            eqViewModel.bandGains[bandIndex] = cursorGain
        }

        if !isUsingDiscreteSteps {
            applySmoothShoulder(centerIndex: bandIndex, targetGain: cursorGain)
        }

        lastBandIndex = bandIndex

        // Clamp every band to the DSP range, mark custom, and dispatch once.
        // Called once per drag sample — the kernel requires a full band update.
        eqViewModel.commitCustomBandEdits()
    }

    /// Linearly interpolates gain between `from` and `to` band indices.
    private func fillGapBetweenBands(
        from startIndex: Int,
        to endIndex: Int,
        startGain: Float,
        endGain: Float
    ) {
        let steps = abs(endIndex - startIndex)
        let direction = endIndex > startIndex ? 1 : -1
        for step in 1 ... steps {
            let progress = Float(step) / Float(steps)
            let interpolatedGain = startGain + (endGain - startGain) * progress
            let targetIndex = startIndex + step * direction
            eqViewModel.bandGains[targetIndex] = max(-12.0, min(12.0, interpolatedGain))
        }
    }

    /// Blends ±1 and ±2 neighbours of `centerIndex` toward `targetGain`.
    private func applySmoothShoulder(centerIndex: Int, targetGain: Float) {
        let neighborWeights: [(offset: Int, weight: Float)] = [(1, 0.75), (2, 0.25)]
        for (offset, weight) in neighborWeights {
            for sign in [-1, 1] {
                let neighborIndex = centerIndex + offset * sign
                guard neighborIndex >= 0, neighborIndex <= 30 else { continue }
                let existing = eqViewModel.bandGains[neighborIndex]
                let blended = existing + (targetGain - existing) * weight
                eqViewModel.bandGains[neighborIndex] = max(-12.0, min(12.0, blended))
            }
        }
    }
}
