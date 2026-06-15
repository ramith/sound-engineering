import SwiftUI

// MARK: - EQ Tab View

struct EQTabView: View {
    @State private var currentPreset: EQPreset = .flat
    @State private var isCustomized = false
    @State private var isUsingDiscreteSteps = false
    @State private var bandGains: [Double] = Array(repeating: 0.0, count: 31)

    var body: some View {
        VStack(spacing: 20) {
            // Frequency Response Canvas (Interactive)
            FrequencyResponseCanvas(
                currentPreset: currentPreset,
                bandGains: $bandGains,
                isCustomized: $isCustomized,
                isUsingDiscreteSteps: isUsingDiscreteSteps
            )
            .frame(height: 400, alignment: .center)
            .frame(minWidth: 400)
            .padding(.top, 20)
            .padding(.horizontal)

            // Control Section
            VStack(spacing: 10) {
                // Preset Buttons Row
                HStack(spacing: 8) {
                    PresetButton(
                        label: "Flat",
                        preset: .flat,
                        isSelected: currentPreset == .flat && !isCustomized,
                        action: applyFlatPreset
                    )

                    PresetButton(
                        label: "Presence",
                        preset: .presence,
                        isSelected: currentPreset == .presence && !isCustomized,
                        action: applyPresencePreset
                    )

                    PresetButton(
                        label: "Clarity",
                        preset: .clarity,
                        isSelected: currentPreset == .clarity && !isCustomized,
                        action: applyClarityPreset
                    )

                    PresetButton(
                        label: "Warm",
                        preset: .warm,
                        isSelected: currentPreset == .warm && !isCustomized,
                        action: applyWarmPreset
                    )

                    Spacer()
                }

                // Interpolation Mode Row
                HStack(spacing: 8) {
                    Text("Interpolation")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.asLabelTertiary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    BlendingToggleButton(
                        label: "Smooth Curve",
                        isActive: !isUsingDiscreteSteps,
                        action: activateSmoothCurve
                    )

                    BlendingToggleButton(
                        label: "Discrete Steps",
                        isActive: isUsingDiscreteSteps,
                        action: activateDiscreteSteps
                    )

                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Color.asWindow)
    }

    // MARK: - Preset Actions

    private func applyFlatPreset() {
        currentPreset = .flat
        isCustomized = false
        bandGains = Array(repeating: 0.0, count: 31)
    }

    private func applyPresencePreset() {
        currentPreset = .presence
        isCustomized = false
        bandGains = getPresenceGains()
    }

    private func applyClarityPreset() {
        currentPreset = .clarity
        isCustomized = false
        bandGains = getClarityGains()
    }

    private func applyWarmPreset() {
        currentPreset = .warm
        isCustomized = false
        bandGains = getWarmGains()
    }

    // MARK: - Blending Actions

    private func activateSmoothCurve() {
        isUsingDiscreteSteps = false
        print("Switched to smooth curve")
    }

    private func activateDiscreteSteps() {
        isUsingDiscreteSteps = true
        print("Switched to discrete steps")
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

// MARK: - Preset Button

struct PresetButton: View {
    let label: String
    let preset: EQPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.asLabel)
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
                .background(isSelected ? Color.asAccent : Color.asCard)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            isSelected ? Color.asAccent : Color.asHairline,
                            lineWidth: isSelected ? 2 : 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preset: \(label)")
        .accessibilityHint(isSelected ? "Currently selected" : "Click to select")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Blending Toggle Button

struct BlendingToggleButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.white : Color.asLabel)
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
                .background(isActive ? Color.asAccent : Color.asCard)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            isActive ? Color.asAccent : Color.asHairline,
                            lineWidth: isActive ? 2 : 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Blending mode: \(label)")
        .accessibilityHint(isActive ? "Currently active" : "Click to activate")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Frequency Response Canvas

struct FrequencyResponseCanvas: View {
    let currentPreset: EQPreset
    @Binding var bandGains: [Double]
    @Binding var isCustomized: Bool
    let isUsingDiscreteSteps: Bool

    /// Tracks the actual rendered canvas size so the gesture handler uses
    /// identical plot bounds to the drawing code.
    @State private var canvasSize: CGSize = .zero
    /// Tracks which band index was last touched within a single drag stroke,
    /// so gap-fill can interpolate over skipped bands on fast drags.
    @State private var lastBandIndex: Int? = nil

    // Plot-margin constants — single source of truth shared by drawing and gesture.
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

                // Draw grid lines and labels
                drawGridAndLabels(
                    context: &context,
                    plotLeft: plotLeft,
                    plotRight: plotRight,
                    plotTop: plotTop,
                    plotBottom: plotBottom,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight
                )

                // Get EQ values: use custom gains if customized, otherwise use preset
                let isoFreqs = getISO31Frequencies()
                let eqValues = isCustomized
                    ? zip(isoFreqs, bandGains).map { ($0, $1) }
                    : getEQValuesForPreset(currentPreset)

                // Draw frequency response curve
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

                // Plot 31 dots at ISO 1/3-octave center frequencies
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
            // Capture the rendered size so the gesture handler stays in sync.
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in canvasSize = newSize }
            // coordinateSpace: .local ensures DragGesture reports locations in the
            // same local frame that GeometryReader measures, matching canvasSize exactly.
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

        // Mirror the exact plot bounds used by the drawing code.
        let plotLeft = plotLeftInset
        let plotRight = canvasSize.width - plotRightInset
        let plotTop = plotTopInset
        let plotBottom = canvasSize.height - plotBottomInset
        let plotWidth = plotRight - plotLeft
        let plotHeight = plotBottom - plotTop
        guard plotWidth > 0, plotHeight > 0 else { return }

        // Map x → band index (0…30), using rounded() to avoid left-bias.
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
            // Single-band paint (also handles the first sample of each stroke).
            paintBand(index: bandIndex, gain: cursorGain)
        }

        // Apply smooth shoulder to the landed band after all writes are done.
        if !isUsingDiscreteSteps {
            applySmoothShoulder(centerIndex: bandIndex, targetGain: cursorGain)
        }

        lastBandIndex = bandIndex
        isCustomized = true
    }

    /// Sets a single band to the given gain (discrete-accurate, no spreading).
    private func paintBand(index: Int, gain: Double) {
        bandGains[index] = gain
    }

    /// Linearly interpolates gain across the integer band indices between `from`
    /// and `to` (exclusive of `from`, inclusive of `to`), so fast drags fill gaps.
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

    /// Pulls the ±2 neighbors of `centerIndex` toward `targetGain` using a
    /// raised-cosine falloff (weights: d=1 → 0.75, d=2 → 0.25). Blends rather
    /// than overwrites, so repeated drag samples compose smoothly.
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

    private func drawGridAndLabels(
        context: inout GraphicsContext,
        plotLeft: CGFloat,
        plotRight: CGFloat,
        plotTop: CGFloat,
        plotBottom: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) {
        // Draw horizontal grid lines for dB levels (-20, -10, 0, 10, 20)
        let dbLevels = [-20.0, -10.0, 0.0, 10.0, 20.0]
        for dbLevel in dbLevels {
            let yPos = plotBottom - ((dbLevel + 20.0) / 40.0) * plotHeight

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: plotLeft, y: yPos))
            gridLine.addLine(to: CGPoint(x: plotRight, y: yPos))

            let strokeColor = dbLevel == 0.0 ? Color.asAccent.opacity(0.3) : Color.asHairline
            let lineWidth: CGFloat = dbLevel == 0.0 ? 1 : 0.5
            context.stroke(gridLine, with: .color(strokeColor), lineWidth: lineWidth)

            let labelText = Text("\(Int(dbLevel))")
                .font(.system(size: 10, weight: .regular))
            let resolvedLabel = context.resolve(labelText)
            context.draw(resolvedLabel, at: CGPoint(x: plotLeft - 15, y: yPos), anchor: .trailing)
        }

        // Draw vertical grid lines for frequency decades (logarithmic: 20Hz, 200Hz, 2kHz, 20kHz)
        let freqLabels = [(20, "20Hz"), (200, "200Hz"), (2000, "2kHz"), (20000, "20kHz")]
        for (freq, freqLabel) in freqLabels {
            let logFreq = log10(Double(freq))
            let xPos = plotLeft + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * plotWidth

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: xPos, y: plotTop))
            gridLine.addLine(to: CGPoint(x: xPos, y: plotBottom))
            context.stroke(gridLine, with: .color(Color.asHairline), lineWidth: 0.5)

            let labelText = Text(freqLabel)
                .font(.system(size: 10, weight: .regular))
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
        var curvePath = Path()
        var isFirstPoint = true

        for (freq, gain) in eqValues {
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
