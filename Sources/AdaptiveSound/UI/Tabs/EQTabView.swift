import SwiftUI

// MARK: - EQ Tab View

struct EQTabView: View {
    @Environment(EQViewModel.self) private var eqViewModel
    @State private var isUsingDiscreteSteps = false

    var body: some View {
        VStack(spacing: 20) {
            FrequencyResponseCanvas(
                eqViewModel: eqViewModel,
                isUsingDiscreteSteps: isUsingDiscreteSteps
            )
            .frame(height: 400, alignment: .center)
            .frame(minWidth: 400)
            .padding(.top, 20)
            .padding(.horizontal)

            ControlsSection(
                eqViewModel: eqViewModel,
                isUsingDiscreteSteps: $isUsingDiscreteSteps
            )
        }
        .background(Color.asWindow)
    }
}

// MARK: - Controls Section

private struct ControlsSection: View {
    let eqViewModel: EQViewModel
    @Binding var isUsingDiscreteSteps: Bool

    var body: some View {
        VStack(spacing: 10) {
            PresetPickerView(eqViewModel: eqViewModel)

            InterpolationPickerView(isUsingDiscreteSteps: $isUsingDiscreteSteps)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}

// MARK: - Preset Picker

private struct PresetPickerView: View {
    let eqViewModel: EQViewModel

    var body: some View {
        // Using @Bindable inline because EQViewModel is passed as a let constant.
        // We need a Bindable wrapper to create a binding from an @Observable class.
        let bindable = Bindable(eqViewModel)

        Picker("Preset", selection: bindable.selectedPreset) {
            ForEach(EQPreset.allCases) { preset in
                Text(preset.displayName).tag(EQPreset?.some(preset))
            }
            Text("Custom").tag(EQPreset?.none)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("EQ Preset")
        .accessibilityValue(eqViewModel.selectedPresetName)
        .onChange(of: eqViewModel.selectedPreset) { _, newPreset in
            if let preset = newPreset {
                eqViewModel.selectPreset(preset)
            }
        }
    }
}

// MARK: - Interpolation Picker

private struct InterpolationPickerView: View {
    @Binding var isUsingDiscreteSteps: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Interpolation")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.asLabelTertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            Picker("Interpolation", selection: $isUsingDiscreteSteps) {
                Text("Smooth Curve").tag(false)
                Text("Discrete Steps").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Interpolation mode")
        }
    }
}

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
    /// GeometryReader is intentionally used here: we need the exact rendered
    /// CGSize inside the Canvas draw pass and for gesture hit-testing. There
    /// is no containerRelativeFrame equivalent that surfaces a CGSize at draw
    /// time, so GeometryReader is the correct tool for this specific case.
    @State private var canvasSize: CGSize = .zero

    /// Tracks the last touched band within a drag stroke for gap-fill interpolation.
    @State private var lastBandIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height

                let bgPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
                context.fill(bgPath, with: .color(Color.asCard))

                let borderPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
                context.stroke(borderPath, with: .color(Color.asHairline), lineWidth: 0.5)

                let plotLeft: CGFloat = plotLeftInset
                let plotRight: CGFloat = width - plotRightInset
                let plotTop: CGFloat = plotTopInset
                let plotBottom: CGFloat = height - plotBottomInset
                let plotWidth = plotRight - plotLeft
                let plotHeight = plotBottom - plotTop

                drawGridAndLabels(
                    context: &context,
                    plotLeft: plotLeft,
                    plotRight: plotRight,
                    plotTop: plotTop,
                    plotBottom: plotBottom,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight
                )

                let eqValues: [(freq: Double, gain: Double)] = EQPreset.isoFrequencies
                    .enumerated()
                    .map { index, freq in (freq, Double(eqViewModel.bandGains[index])) }

                drawFrequencyResponseCurve(
                    context: &context,
                    eqValues: eqValues,
                    plotLeft: plotLeft,
                    plotBottom: plotBottom,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight
                )

                drawISOOctaveDots(
                    context: &context,
                    eqValues: eqValues,
                    plotLeft: plotLeft,
                    plotBottom: plotBottom,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight
                )
            }
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in canvasSize = newSize }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in updateEQFromDrag(location: value.location) }
                    .onEnded { _ in lastBandIndex = nil }
            )
        }
        .background(Color.asCard)
        .clipShape(RoundedRectangle(cornerRadius: 9))
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
        let cursorGain = Float(max(-20.0, min(20.0, relativeY * 40.0 - 20.0)))

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

        // Mark selectedPreset as nil (custom) and dispatch all 31 bands to the
        // DSP kernel. This is intentionally called once per drag sample —
        // the kernel requires a full band update, not a partial one.
        eqViewModel.selectedPreset = nil
        eqViewModel.dispatchAllBands()
    }

    /// Linearly interpolates gain between `from` and `to` band indices.
    private func fillGapBetweenBands(from startIndex: Int, to endIndex: Int,
                                     startGain: Float, endGain: Float)
    {
        let steps = abs(endIndex - startIndex)
        let direction = endIndex > startIndex ? 1 : -1
        for step in 1 ... steps {
            let progress = Float(step) / Float(steps)
            let interpolatedGain = startGain + (endGain - startGain) * progress
            let targetIndex = startIndex + step * direction
            eqViewModel.bandGains[targetIndex] = max(-20.0, min(20.0, interpolatedGain))
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
                eqViewModel.bandGains[neighborIndex] = existing + (targetGain - existing) * weight
            }
        }
    }

    // MARK: - Drawing Helpers

    private func drawGridAndLabels(
        context: inout GraphicsContext,
        plotLeft: CGFloat,
        plotRight: CGFloat,
        plotTop: CGFloat,
        plotBottom: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) {
        let dbLevels = [-20.0, -10.0, 0.0, 10.0, 20.0]
        for dbLevel in dbLevels {
            let yPos = plotBottom - ((dbLevel + 20.0) / 40.0) * plotHeight

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: plotLeft, y: yPos))
            gridLine.addLine(to: CGPoint(x: plotRight, y: yPos))

            let strokeColor = dbLevel == 0.0 ? Color.asAccent.opacity(0.3) : Color.asHairline
            let lineWidth: CGFloat = dbLevel == 0.0 ? 1 : 0.5
            context.stroke(gridLine, with: .color(strokeColor), lineWidth: lineWidth)

            let labelText = Text("\(Int(dbLevel))").font(.caption2)
            let resolvedLabel = context.resolve(labelText)
            context.draw(resolvedLabel, at: CGPoint(x: plotLeft - 15, y: yPos), anchor: .trailing)
        }

        let freqLabels = [(20, "20Hz"), (200, "200Hz"), (2000, "2kHz"), (20000, "20kHz")]
        for (freq, freqLabel) in freqLabels {
            let logFreq = log10(Double(freq))
            let xPos = plotLeft + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * plotWidth

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: xPos, y: plotTop))
            gridLine.addLine(to: CGPoint(x: xPos, y: plotBottom))
            context.stroke(gridLine, with: .color(Color.asHairline), lineWidth: 0.5)

            let labelText = Text(freqLabel).font(.caption2)
            let resolvedLabel = context.resolve(labelText)
            context.draw(resolvedLabel, at: CGPoint(x: xPos, y: plotBottom + 12), anchor: .top)
        }
    }

    private func drawFrequencyResponseCurve(
        context: inout GraphicsContext,
        eqValues: [(freq: Double, gain: Double)],
        plotLeft: CGFloat,
        plotBottom: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) {
        let interpolatedPoints = interpolateFrequencyResponse(eqValues)

        var curvePath = Path()
        var isFirstPoint = true

        for (freq, gain) in interpolatedPoints {
            let logFreq = log10(freq)
            let xPos = plotLeft + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * plotWidth
            let yPos = plotBottom - ((gain + 20.0) / 40.0) * plotHeight

            if isFirstPoint {
                curvePath.move(to: CGPoint(x: xPos, y: yPos))
                isFirstPoint = false
            } else {
                curvePath.addLine(to: CGPoint(x: xPos, y: yPos))
            }
        }

        context.stroke(curvePath, with: .color(Color.asAccent), lineWidth: 2.5)
    }

    private func drawISOOctaveDots(
        context: inout GraphicsContext,
        eqValues: [(freq: Double, gain: Double)],
        plotLeft: CGFloat,
        plotBottom: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) {
        let dotRadius: CGFloat = 4.0

        for (freq, gain) in eqValues {
            let logFreq = log10(freq)
            let xPos = plotLeft + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * plotWidth
            let yPos = plotBottom - ((gain + 20.0) / 40.0) * plotHeight

            let dotPath = Path(ellipseIn: CGRect(
                x: xPos - dotRadius,
                y: yPos - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
            context.fill(dotPath, with: .color(Color.asAccent))
        }
    }

    // MARK: - Interpolation & Smoothing

    private func interpolateFrequencyResponse(
        _ isoPoints: [(freq: Double, gain: Double)]
    ) -> [(freq: Double, gain: Double)] {
        guard !isoPoints.isEmpty else { return isoPoints }

        var interpolatedFreqs: [Double] = []
        let logFreqMin = log10(20.0)
        let logFreqMax = log10(20000.0)
        let numSteps = 120

        for i in 0 ... numSteps {
            let t = Double(i) / Double(numSteps)
            let logFreq = logFreqMin + t * (logFreqMax - logFreqMin)
            interpolatedFreqs.append(pow(10.0, logFreq))
        }

        var interpolatedGains: [Double] = interpolatedFreqs.map { freq in
            gainAtFrequency(freq, from: isoPoints)
        }

        interpolatedGains = smoothGains(interpolatedGains, tapCount: 3)

        return zip(interpolatedFreqs, interpolatedGains).map { ($0, $1) }
    }

    private func gainAtFrequency(
        _ freq: Double,
        from isoPoints: [(freq: Double, gain: Double)]
    ) -> Double {
        guard freq >= 20 && freq <= 20000 else { return 0 }

        let logFreq = log10(freq)
        var lower = isoPoints[0]
        var upper = isoPoints.last ?? isoPoints[0]

        for i in 0 ..< (isoPoints.count - 1) {
            if logFreq >= log10(isoPoints[i].freq) && logFreq <= log10(isoPoints[i + 1].freq) {
                lower = isoPoints[i]
                upper = isoPoints[i + 1]
                break
            }
        }

        let logLower = log10(lower.freq)
        let logUpper = log10(upper.freq)
        let t = (logFreq - logLower) / (logUpper - logLower)
        let clampedT = max(0, min(1, t))

        return lower.gain + clampedT * (upper.gain - lower.gain)
    }

    private func smoothGains(_ gains: [Double], tapCount: Int) -> [Double] {
        guard gains.count >= tapCount else { return gains }

        let halfTap = tapCount / 2
        var smoothed = gains

        for i in 0 ..< gains.count {
            var sum = 0.0
            var count = 0

            for j in max(0, i - halfTap) ... min(gains.count - 1, i + halfTap) {
                sum += gains[j]
                count += 1
            }

            smoothed[i] = sum / Double(count)
        }

        return smoothed
    }
}
