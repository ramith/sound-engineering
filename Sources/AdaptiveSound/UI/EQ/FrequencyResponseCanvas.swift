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
        .accessibilityLabel("Frequency Response Curve")
        .accessibilityValue(
            "EQ Preset: \(eqViewModel.selectedPresetName), "
                + "Blending: \(isUsingDiscreteSteps ? "Discrete Steps" : "Smooth Curve")"
        )
        .accessibilityHint(
            "Interactive frequency response visualization with 31 ISO 1/3-octave bands "
                + "from 20Hz to 20kHz. Click or drag to adjust."
        )
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
