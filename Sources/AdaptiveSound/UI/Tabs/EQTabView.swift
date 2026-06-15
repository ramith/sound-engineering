import SwiftUI

// MARK: - EQ Tab View

struct EQTabView: View {
    @State private var currentPreset: EQPreset = .flat
    @State private var isCustomized = false
    @State private var isUsingDiscreteSteps = false
    @State private var bandGains: [Double] = Array(repeating: 0.0, count: 31)

    /// Passed down to FrequencyResponseCanvas so gesture bounds match drawing bounds.
    @State private var canvasSize: CGSize = .zero
    /// Tracks the last touched band within a drag stroke for gap-fill interpolation.
    @State private var lastBandIndex: Int? = nil

    var body: some View {
        VStack(spacing: 20) {
            // Frequency Response Canvas (Interactive)
            FrequencyResponseCanvas(
                currentPreset: currentPreset,
                bandGains: $bandGains,
                isCustomized: $isCustomized,
                isUsingDiscreteSteps: isUsingDiscreteSteps,
                canvasSize: $canvasSize,
                lastBandIndex: $lastBandIndex
            )
            .frame(height: 400, alignment: .center)
            .frame(minWidth: 400)
            .padding(.top, 20)
            .padding(.horizontal)

            // Control Section
            VStack(spacing: 10) {
                // Preset selection — native segmented control bound to currentPreset
                Picker("Preset", selection: $currentPreset) {
                    ForEach(EQPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("EQ Preset")
                .onChange(of: currentPreset) { _, newPreset in
                    applyPreset(newPreset)
                }

                // Interpolation mode — native segmented 2-way switch
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
                    .onChange(of: isUsingDiscreteSteps) { _, newValue in
                        print("Switched to \(newValue ? "discrete steps" : "smooth curve")")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Color.asWindow)
    }

    // MARK: - Preset Actions

    private func applyPreset(_ preset: EQPreset) {
        isCustomized = false
        switch preset {
        case .flat:
            bandGains = Array(repeating: 0.0, count: 31)
        case .presence:
            bandGains = getPresenceGains()
        case .clarity:
            bandGains = getClarityGains()
        case .warm:
            bandGains = getWarmGains()
        }
    }

    // MARK: - EQ Gain Helpers

    private func getISO31Frequencies() -> [Double] {
        [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
         630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
         10000, 12500, 16000, 20000]
    }

    private func getPresenceGains() -> [Double] {
        getISO31Frequencies().map { gainForPresence($0) }
    }

    private func getClarityGains() -> [Double] {
        getISO31Frequencies().map { gainForClarity($0) }
    }

    private func getWarmGains() -> [Double] {
        getISO31Frequencies().map { gainForWarm($0) }
    }

    private func gainForPresence(_ freq: Double) -> Double {
        if freq >= 1000 && freq <= 4000 {
            return 8.0 * sin((log10(freq) - log10(1000)) / (log10(4000) - log10(1000)) * .pi)
        } else if freq > 4000 && freq <= 8000 {
            return 4.0 * sin((log10(8000) - log10(freq)) / (log10(8000) - log10(4000)) * .pi / 2)
        } else {
            return 0.0
        }
    }

    private func gainForClarity(_ freq: Double) -> Double {
        if freq >= 1000 && freq <= 8000 {
            return 6.0 * sin((log10(freq) - log10(1000)) / (log10(8000) - log10(1000)) * .pi / 2)
        } else if freq > 8000 && freq <= 16000 {
            return 4.0 * sin((log10(16000) - log10(freq)) / (log10(16000) - log10(8000)) * .pi / 2)
        } else {
            return 0.0
        }
    }

    private func gainForWarm(_ freq: Double) -> Double {
        if freq >= 20 && freq <= 500 {
            return 12.0 * (1.0 - exp(-log10(freq) / 1.5))
        } else if freq > 500 && freq <= 2000 {
            return 8.0 * exp(-(freq - 500) / 1500)
        } else {
            return 0.0
        }
    }
}

// MARK: - Frequency Response Canvas

struct FrequencyResponseCanvas: View {
    let currentPreset: EQPreset
    @Binding var bandGains: [Double]
    @Binding var isCustomized: Bool
    let isUsingDiscreteSteps: Bool

    /// Captured layout size — must match drawing bounds exactly.
    @Binding var canvasSize: CGSize
    /// Tracks the last touched band within a single drag stroke for gap-fill.
    @Binding var lastBandIndex: Int?

    // Plot-margin constants — single source of truth for drawing and gesture handler.
    private let plotLeftInset: CGFloat = 50
    private let plotRightInset: CGFloat = 20
    private let plotTopInset: CGFloat = 20
    private let plotBottomInset: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height

                // Draw background
                let bgPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
                context.fill(bgPath, with: .color(Color.asCard))

                // Draw border
                let borderPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
                context.stroke(borderPath, with: .color(Color.asHairline), lineWidth: 0.5)

                // Define plot area with margins
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

                let isoFreqs = getISO31Frequencies()
                let eqValues = isCustomized
                    ? zip(isoFreqs, bandGains).map { ($0, $1) }
                    : getEQValuesForPreset(currentPreset)

                drawFrequencyResponseCurve(
                    context: &context,
                    eqValues: eqValues,
                    plotLeft: plotLeft,
                    plotRight: plotRight,
                    plotTop: plotTop,
                    plotBottom: plotBottom,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight
                )

                drawISOOctaveDots(
                    context: &context,
                    eqValues: eqValues,
                    plotLeft: plotLeft,
                    plotRight: plotRight,
                    plotTop: plotTop,
                    plotBottom: plotBottom,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight
                )
            }
            // Keep canvasSize in sync with the GeometryReader's reported frame.
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in canvasSize = newSize }
            // coordinateSpace: .local matches the local frame GeometryReader measures.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        updateEQFromDrag(location: value.location)
                    }
                    .onEnded { _ in
                        lastBandIndex = nil
                    }
            )
        }
        .background(Color.asCard)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5)
        }
        .accessibilityLabel("Frequency Response Curve")
        .accessibilityValue(
            "EQ Preset: \(isCustomized ? "Custom" : currentPreset.displayName), "
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
        let plotTop = plotTopInset
        let plotBottom = canvasSize.height - plotBottomInset
        let plotWidth = plotRight - plotLeft
        let plotHeight = plotBottom - plotTop
        guard plotWidth > 0, plotHeight > 0 else { return }

        // Map x → band index (0…30); rounded() avoids left-bias from truncation.
        let relativeX = max(0.0, min(1.0, (location.x - plotLeft) / plotWidth))
        let bandIndex = max(0, min(30, Int((relativeX * 30.0).rounded())))

        // Map y → dB gain (-20…+20 dB); y increases downward so invert.
        let relativeY = max(0.0, min(1.0, (plotBottom - location.y) / plotHeight))
        let cursorGain = max(-20.0, min(20.0, relativeY * 40.0 - 20.0))

        if let previousIndex = lastBandIndex, abs(bandIndex - previousIndex) > 1 {
            // Gap-fill: interpolate across skipped bands so fast drags leave no holes.
            fillGapBetweenBands(
                from: previousIndex,
                to: bandIndex,
                startGain: bandGains[previousIndex],
                endGain: cursorGain
            )
        } else {
            bandGains[bandIndex] = cursorGain
        }

        // Smooth shoulder only in smooth-curve mode; discrete leaves sharp edits.
        if !isUsingDiscreteSteps {
            applySmoothShoulder(centerIndex: bandIndex, targetGain: cursorGain)
        }

        lastBandIndex = bandIndex
        isCustomized = true
    }

    /// Linearly interpolates gain between `from` and `to` band indices, inclusive
    /// of `to` and exclusive of `from`, so fast drags leave no unedited gaps.
    private func fillGapBetweenBands(from startIndex: Int, to endIndex: Int,
                                     startGain: Double, endGain: Double)
    {
        let steps = abs(endIndex - startIndex)
        let direction = endIndex > startIndex ? 1 : -1
        for step in 1 ... steps {
            let progress = Double(step) / Double(steps)
            let interpolatedGain = startGain + (endGain - startGain) * progress
            let targetIndex = startIndex + step * direction
            bandGains[targetIndex] = max(-20.0, min(20.0, interpolatedGain))
        }
    }

    /// Blends the ±1 and ±2 neighbors of `centerIndex` toward `targetGain` with
    /// raised-cosine weights (d=1 → 0.75, d=2 → 0.25), composing well across
    /// repeated drag samples without overshooting.
    private func applySmoothShoulder(centerIndex: Int, targetGain: Double) {
        let neighborWeights: [(offset: Int, weight: Double)] = [(1, 0.75), (2, 0.25)]
        for (offset, weight) in neighborWeights {
            for sign in [-1, 1] {
                let neighborIndex = centerIndex + offset * sign
                guard neighborIndex >= 0, neighborIndex <= 30 else { continue }
                let existing = bandGains[neighborIndex]
                bandGains[neighborIndex] = existing + (targetGain - existing) * weight
            }
        }
    }

    // MARK: - Drawing Helpers

    private func getISO31Frequencies() -> [Double] {
        [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
         630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
         10000, 12500, 16000, 20000]
    }

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
        plotRight _: CGFloat,
        plotTop _: CGFloat,
        plotBottom: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) {
        // Interpolate gains at finer frequency intervals for smooth visual curve
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
        plotRight _: CGFloat,
        plotTop _: CGFloat,
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

    /// Generate smooth curve with interpolated points at ~1/6 octave intervals (~60 points)
    /// Apply 3-tap smoothing for subtle processing smoothing (avoids harsh peaks)
    private func interpolateFrequencyResponse(
        _ isoPoints: [(freq: Double, gain: Double)]
    ) -> [(freq: Double, gain: Double)] {
        guard !isoPoints.isEmpty else { return isoPoints }

        // Generate finer frequency grid: every ~1/6 octave (6 points per octave)
        var interpolatedFreqs: [Double] = []
        let logFreqMin = log10(20.0)
        let logFreqMax = log10(20000.0)
        let numSteps = 120 // ~6 points per octave across 20Hz-20kHz

        for i in 0 ... numSteps {
            let t = Double(i) / Double(numSteps)
            let logFreq = logFreqMin + t * (logFreqMax - logFreqMin)
            interpolatedFreqs.append(pow(10.0, logFreq))
        }

        // Interpolate gains at these finer frequencies (log-linear)
        var interpolatedGains: [Double] = interpolatedFreqs.map { freq in
            gainAtFrequency(freq, from: isoPoints)
        }

        // Apply 3-tap moving average smoothing (subtle, prevents harsh peaks)
        interpolatedGains = smoothGains(interpolatedGains, tapCount: 3)

        return zip(interpolatedFreqs, interpolatedGains).map { ($0, $1) }
    }

    /// Linear interpolation on log frequency scale for smooth curve
    private func gainAtFrequency(
        _ freq: Double,
        from isoPoints: [(freq: Double, gain: Double)]
    ) -> Double {
        guard freq >= 20 && freq <= 20000 else { return 0 }

        let logFreq = log10(freq)

        // Find bounding ISO points
        var lower = isoPoints[0]
        var upper = isoPoints.last ?? isoPoints[0]

        for i in 0 ..< (isoPoints.count - 1) {
            if logFreq >= log10(isoPoints[i].freq) && logFreq <= log10(isoPoints[i + 1].freq) {
                lower = isoPoints[i]
                upper = isoPoints[i + 1]
                break
            }
        }

        // Linear interpolation on log-frequency scale
        let logLower = log10(lower.freq)
        let logUpper = log10(upper.freq)
        let t = (logFreq - logLower) / (logUpper - logLower)
        let clampedT = max(0, min(1, t))

        return lower.gain + clampedT * (upper.gain - lower.gain)
    }

    /// Apply N-tap moving average smoothing to prevent harsh peaks
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

    private func getEQValuesForPreset(_ preset: EQPreset) -> [(freq: Double, gain: Double)] {
        let iso31Frequencies: [Double] = [
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
            630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
            10000, 12500, 16000, 20000,
        ]

        switch preset {
        case .flat:
            return iso31Frequencies.map { ($0, 0.0) }
        case .presence:
            return iso31Frequencies.map { freq in (freq, gainForPresence(freq)) }
        case .clarity:
            return iso31Frequencies.map { freq in (freq, gainForClarity(freq)) }
        case .warm:
            return iso31Frequencies.map { freq in (freq, gainForWarm(freq)) }
        }
    }

    private func gainForPresence(_ freq: Double) -> Double {
        if freq >= 1000 && freq <= 4000 {
            return 8.0 * sin((log10(freq) - log10(1000)) / (log10(4000) - log10(1000)) * .pi)
        } else if freq > 4000 && freq <= 8000 {
            return 4.0 * sin((log10(8000) - log10(freq)) / (log10(8000) - log10(4000)) * .pi / 2)
        } else {
            return 0.0
        }
    }

    private func gainForClarity(_ freq: Double) -> Double {
        if freq >= 1000 && freq <= 8000 {
            return 6.0 * sin((log10(freq) - log10(1000)) / (log10(8000) - log10(1000)) * .pi / 2)
        } else if freq > 8000 && freq <= 16000 {
            return 4.0 * sin((log10(16000) - log10(freq)) / (log10(16000) - log10(8000)) * .pi / 2)
        } else {
            return 0.0
        }
    }

    private func gainForWarm(_ freq: Double) -> Double {
        if freq >= 20 && freq <= 500 {
            return 12.0 * (1.0 - exp(-log10(freq) / 1.5))
        } else if freq > 500 && freq <= 2000 {
            return 8.0 * exp(-(freq - 500) / 1500)
        } else {
            return 0.0
        }
    }
}

// MARK: - EQ Preset Enum

enum EQPreset: String, CaseIterable {
    case flat
    case presence
    case clarity
    case warm

    var displayName: String {
        switch self {
        case .flat:
            return "Flat"
        case .presence:
            return "Presence"
        case .clarity:
            return "Clarity"
        case .warm:
            return "Warm"
        }
    }
}
