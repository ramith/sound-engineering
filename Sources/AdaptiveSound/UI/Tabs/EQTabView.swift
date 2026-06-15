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
            VStack(spacing: 16) {
                // Preset Buttons
                HStack(spacing: 12) {
                    PresetButton(
                        label: "Flat",
                        preset: .flat,
                        isSelected: currentPreset == .flat && !isCustomized,
                        action: {
                            currentPreset = .flat
                            isCustomized = false
                            bandGains = Array(repeating: 0.0, count: 31)
                        }
                    )

                    PresetButton(
                        label: "Presence",
                        preset: .presence,
                        isSelected: currentPreset == .presence && !isCustomized,
                        action: {
                            currentPreset = .presence
                            isCustomized = false
                            bandGains = getPresenceGains()
                        }
                    )

                    PresetButton(
                        label: "Clarity",
                        preset: .clarity,
                        isSelected: currentPreset == .clarity && !isCustomized,
                        action: {
                            currentPreset = .clarity
                            isCustomized = false
                            bandGains = getClarityGains()
                        }
                    )

                    PresetButton(
                        label: "Warm",
                        preset: .warm,
                        isSelected: currentPreset == .warm && !isCustomized,
                        action: {
                            currentPreset = .warm
                            isCustomized = false
                            bandGains = getWarmGains()
                        }
                    )

                    Spacer()
                }

                // Current Preset Dropdown and Reset Row
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Preset")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.asLabelTertiary)
                            .textCase(.uppercase)
                            .tracking(0.6)

                        HStack(spacing: 4) {
                            Text(isCustomized ? "Custom" : currentPreset.displayName)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.asLabel)
                            Image(systemName: "triangle.fill")
                                .font(.system(size: 4))
                                .foregroundColor(.asLabelSecond)
                        }
                    }
                    .padding(12)
                    .background(Color.asCard)
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Current Preset: \(isCustomized ? "Custom" : currentPreset.displayName)")

                    Button(action: {
                        currentPreset = .flat
                        isCustomized = false
                        bandGains = Array(repeating: 0.0, count: 31)
                    }) {
                        Text("Reset to Flat")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.asLabel)
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 8)
                            .background(Color.asCard)
                            .cornerRadius(9)
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset to Flat")
                    .accessibilityHint("Returns the EQ curve to flat response")
                }

                // Blending Toggle Buttons
                HStack(spacing: 8) {
                    BlendingToggleButton(
                        label: "Smooth Curve",
                        isActive: !isUsingDiscreteSteps,
                        action: {
                            isUsingDiscreteSteps = false
                            print("Switched to smooth curve")
                        }
                    )

                    BlendingToggleButton(
                        label: "Discrete Steps",
                        isActive: isUsingDiscreteSteps,
                        action: {
                            isUsingDiscreteSteps = true
                            print("Switched to discrete steps")
                        }
                    )

                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .background(Color.asWindow)
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
                .foregroundColor(
                    isSelected ? .white : .asLabel
                )
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 8)
                .background(
                    isSelected
                        ? Color.asAccent
                        : Color.asCard
                )
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            isSelected ? Color.asAccent : Color.asHairline,
                            lineWidth: isSelected ? 2 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preset: \(label)")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select")
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
                .foregroundColor(
                    isActive ? .white : .asLabel
                )
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 8)
                .background(
                    isActive
                        ? Color.asAccent
                        : Color.asCard
                )
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            isActive ? Color.asAccent : Color.asHairline,
                            lineWidth: isActive ? 2 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Blending mode: \(label)")
        .accessibilityHint(isActive ? "Currently active" : "Tap to activate")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Frequency Response Canvas

struct FrequencyResponseCanvas: View {
    let currentPreset: EQPreset
    @Binding var bandGains: [Double]
    @Binding var isCustomized: Bool
    let isUsingDiscreteSteps: Bool

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            // Draw background
            var bgPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
            context.fill(
                bgPath,
                with: .color(Color.asCard)
            )

            // Draw border
            let borderPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9)
            context.stroke(
                borderPath,
                with: .color(Color.asHairline),
                lineWidth: 0.5
            )

            // Define plot area with margins
            let plotLeft: CGFloat = 50
            let plotRight: CGFloat = width - 20
            let plotTop: CGFloat = 20
            let plotBottom: CGFloat = height - 40

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

            // Draw frequency response curve (diagonal from -20dB @ 20Hz to +20dB @ 20kHz)
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
        .background(Color.asCard)
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    updateEQFromClick(value.location)
                }
        )
        .accessibilityLabel("Frequency Response Curve")
        .accessibilityValue(
            "EQ Preset: \(isCustomized ? "Custom" : currentPreset.displayName), "
                + "Blending: \(isUsingDiscreteSteps ? "Discrete Steps" : "Smooth Curve")"
        )
        .accessibilityHint("Interactive frequency response visualization with 31 ISO 1/3-octave bands from 20Hz to 20kHz. Click or drag to adjust.")
    }

    private func updateEQFromClick(_ location: CGPoint) {
        let plotLeft: CGFloat = 50
        let plotRight: CGFloat = 350 // Approximate based on typical canvas width
        let plotBottom: CGFloat = 300 // Approximate based on typical canvas height
        let plotTop: CGFloat = 20

        let plotWidth = plotRight - plotLeft
        let plotHeight = plotBottom - plotTop

        // Convert pixel position to frequency
        let relativeX = max(0, min(1, (location.x - plotLeft) / plotWidth))
        let freqIndex = Int(relativeX * 30)
        guard freqIndex >= 0, freqIndex < 31 else { return }

        // Convert pixel position to dB gain
        let relativeY = max(-1, min(1, (plotBottom - location.y) / plotHeight))
        let gainValue = relativeY * 40 - 20 // Map to -20 to +20 dB range
        let clampedGain = max(-20, min(20, gainValue))

        // Update the band gain
        bandGains[freqIndex] = clampedGain
        isCustomized = true
    }

    private func getISO31Frequencies() -> [Double] {
        [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
         630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
         10000, 12500, 16000, 20000]
    }

    private func getPresenceGains() -> [Double] {
        let freqs = getISO31Frequencies()
        return freqs.map { gainForPresence($0) }
    }

    private func getClarityGains() -> [Double] {
        let freqs = getISO31Frequencies()
        return freqs.map { gainForClarity($0) }
    }

    private func getWarmGains() -> [Double] {
        let freqs = getISO31Frequencies()
        return freqs.map { gainForWarm($0) }
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

            // Draw dB labels on the left side
            let labelText = Text("\(Int(dbLevel))")
                .font(.system(size: 10, weight: .regular))
            let resolvedLabel = context.resolve(labelText)
            context.draw(
                resolvedLabel,
                at: CGPoint(x: plotLeft - 15, y: yPos),
                anchor: .trailing
            )
        }

        // Draw vertical grid lines for frequency decades (logarithmic: 20Hz, 200Hz, 2kHz, 20kHz)
        let freqLabels = [(20, "20Hz"), (200, "200Hz"), (2000, "2kHz"), (20000, "20kHz")]
        for (freq, label) in freqLabels {
            let logFreq = log10(Double(freq))
            let xPos = plotLeft + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * plotWidth

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: xPos, y: plotTop))
            gridLine.addLine(to: CGPoint(x: xPos, y: plotBottom))

            context.stroke(gridLine, with: .color(Color.asHairline), lineWidth: 0.5)

            // Draw frequency labels at the bottom
            let labelText = Text(label)
                .font(.system(size: 10, weight: .regular))
            let resolvedLabel = context.resolve(labelText)
            context.draw(
                resolvedLabel,
                at: CGPoint(x: xPos, y: plotBottom + 12),
                anchor: .top
            )
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

        context.stroke(
            curvePath,
            with: .color(Color.asAccent),
            lineWidth: 2.5
        )
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
        let dotRadius: CGFloat = 4.0 // 8pt diameter = 4pt radius

        for (freq, gain) in eqValues {
            let logFreq = log10(freq)
            let xPos = plotLeft + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * plotWidth
            let yPos = plotBottom - ((gain + 20.0) / 40.0) * plotHeight

            var dotPath = Path(ellipseIn: CGRect(
                x: xPos - dotRadius,
                y: yPos - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))

            context.fill(
                dotPath,
                with: .color(Color.asAccent)
            )
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
