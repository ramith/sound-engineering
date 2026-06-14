import SwiftUI

// MARK: - Response Label Computation Helper

func computeResponseLabel(bandGains: [Float]) -> String {
    let average = bandGains.reduce(0, +) / Float(bandGains.count)
    let lowBands = bandGains[0 ..< 10].reduce(0, +) / 10.0
    let highBands = bandGains[20 ..< 31].reduce(0, +) / 11.0

    if bandGains.allSatisfy({ abs($0) < 0.1 }) {
        return "flat"
    } else if lowBands > highBands + 1.0 {
        return "warm"
    } else if highBands > lowBands + 1.0 {
        return "bright"
    } else if average > 2.0 {
        return "boosted"
    } else if average < -2.0 {
        return "cut"
    } else {
        return "balanced"
    }
}

// MARK: - Frequency Response Graph View

struct FrequencyResponseGraphView: View {
    let bandGains: [Float]
    let isoDates: [String] = [
        "20", "25", "31.5", "40", "50", "63", "80", "100", "125", "160",
        "200", "250", "315", "400", "500", "630", "800", "1k", "1.25k", "1.6k",
        "2k", "2.5k", "3.15k", "4k", "5k", "6.3k", "8k", "10k", "12.5k", "16k", "20k",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frequency Response")
                .font(BrandFont.sectionLabel)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundColor(.asLabelTertiary)

            ZStack(alignment: .topLeading) {
                // Background
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.asCard)

                // Graph drawing
                Canvas { context, size in
                    let width = size.width
                    let height = size.height
                    let graphInsetX = 40.0
                    let graphInsetY = 20.0
                    let graphWidth = width - graphInsetX * 2
                    let graphHeight = height - graphInsetY * 2

                    // Draw grid lines (log frequency scale)
                    var gridPath = Path()
                    for i in 0 ..< bandGains.count {
                        let xPos = graphInsetX + (Double(i) / Double(bandGains.count - 1)) * graphWidth
                        gridPath.move(to: CGPoint(x: xPos, y: graphInsetY))
                        gridPath.addLine(to: CGPoint(x: xPos, y: graphInsetY + graphHeight))
                    }

                    // Horizontal center line (0 dB)
                    let centerY = graphInsetY + graphHeight / 2.0
                    gridPath.move(to: CGPoint(x: graphInsetX, y: centerY))
                    gridPath.addLine(to: CGPoint(x: graphInsetX + graphWidth, y: centerY))

                    context.stroke(
                        gridPath,
                        with: .color(.asHairline),
                        lineWidth: 0.5
                    )

                    // Draw curve
                    var curvePath = Path()
                    for i in 0 ..< bandGains.count {
                        let xPos = graphInsetX + (Double(i) / Double(bandGains.count - 1)) * graphWidth
                        // Map dB value (-20 to +12) to vertical position
                        let gainNormalized = Double(bandGains[i]) / 16.0 // Use 16 as mid-range
                        let yPos = centerY - gainNormalized * (graphHeight / 2.0)

                        if i == 0 {
                            curvePath.move(to: CGPoint(x: xPos, y: yPos))
                        } else {
                            curvePath.addLine(to: CGPoint(x: xPos, y: yPos))
                        }
                    }

                    context.stroke(
                        curvePath,
                        with: .color(.asAccent),
                        lineWidth: 2.0
                    )

                    // Draw circle indicators
                    let circleRadius = 2.0
                    var circlePath = Path()
                    for i in 0 ..< bandGains.count {
                        let xPos = graphInsetX + (Double(i) / Double(bandGains.count - 1)) * graphWidth
                        let gainNormalized = Double(bandGains[i]) / 16.0
                        let yPos = centerY - gainNormalized * (graphHeight / 2.0)
                        circlePath.addEllipse(in: CGRect(x: xPos - circleRadius / 2.0, y: yPos - circleRadius / 2.0, width: circleRadius, height: circleRadius))
                    }
                    context.fill(circlePath, with: .color(.asAccent))
                }

                // Axis labels overlay
                VStack(alignment: .leading, spacing: 0) {
                    Text("+20 dB")
                        .font(.caption2)
                        .foregroundColor(.asLabelTertiary)
                        .frame(height: 20)

                    Spacer()

                    Text("0 dB")
                        .font(.caption2)
                        .foregroundColor(.asLabelTertiary)
                        .frame(height: 20)

                    Spacer()

                    Text("-20 dB")
                        .font(.caption2)
                        .foregroundColor(.asLabelTertiary)
                        .frame(height: 20)
                }
                .padding(.leading, 4)
                .padding(.vertical, 20)

                // X-axis labels
                HStack(spacing: 0) {
                    let labelFreqs = [0, 5, 10, 15, 20, 25, 30]
                    ForEach(labelFreqs, id: \.self) { idx in
                        if idx < isoDates.count {
                            Text(isoDates[idx])
                                .font(.caption2)
                                .foregroundColor(.asLabelTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .padding(.bottom, 4)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 200)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
        }
        .padding()
    }
}

// MARK: - Preset Selector

struct PresetSelectorView: View {
    @ObservedObject var eqViewModel: EQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preset")
                .font(BrandFont.sectionLabel)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundColor(.asLabelTertiary)

            HStack(spacing: 8) {
                Menu {
                    ForEach(eqViewModel.availablePresets, id: \.self) { presetName in
                        Button(action: {
                            eqViewModel.selectPreset(presetName)
                        }) {
                            HStack {
                                Text(presetName)
                                if presetName == eqViewModel.selectedPreset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundColor(.asAccent)
                        Text(eqViewModel.selectedPreset)
                            .font(BrandFont.body)
                            .foregroundColor(.asLabel)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.asLabelSecond)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.asCard)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Text(presetDescription(eqViewModel.selectedPreset))
                    .font(.caption)
                    .foregroundColor(.asLabelSecond)
                    .lineLimit(1)
            }
        }
        .padding()
    }

    private func presetDescription(_ presetName: String) -> String {
        switch presetName {
        case "Flat":
            return "No EQ applied"
        case "Presence":
            return "Clarity and presence boost"
        case "Clarity":
            return "Detail and articulation"
        case "Warm":
            return "Bass-heavy, smooth tone"
        case "Custom":
            return "User-defined settings"
        default:
            return ""
        }
    }
}

// MARK: - Band Slider

struct BandSliderView: View {
    @Binding var gain: Float
    let frequency: String
    let index: Int

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(frequency)
                    .font(.caption2)
                    .foregroundColor(.asLabelTertiary)
                    .frame(width: 40, alignment: .leading)

                Slider(value: $gain, in: -12 ... 12, step: 0.1)
                    .tint(.asAccent)

                Text(String(format: "%+.1f", gain))
                    .font(BrandFont.mono)
                    .foregroundColor(.asLabel)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.asCard)
            .cornerRadius(6)
        }
    }
}

// MARK: - Band Sliders Grid

struct BandSlidersView: View {
    @ObservedObject var eqViewModel: EQViewModel

    let isoDates: [String] = [
        "20", "25", "31.5", "40", "50", "63", "80", "100", "125", "160",
        "200", "250", "315", "400", "500", "630", "800", "1k", "1.25k", "1.6k",
        "2k", "2.5k", "3.15k", "4k", "5k", "6.3k", "8k", "10k", "12.5k", "16k", "20k",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("31-Band EQ")
                .font(BrandFont.sectionLabel)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundColor(.asLabelTertiary)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(0 ..< eqViewModel.bandGains.count, id: \.self) { index in
                        BandSliderCardView(
                            frequency: isoDates[index],
                            index: index,
                            eqViewModel: eqViewModel
                        )
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 400)
            .background(Color.asInset)
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
        }
        .padding()
    }
}

// MARK: - Band Slider Card (adjusted to use eqViewModel)

struct BandSliderCardView: View {
    let frequency: String
    let index: Int
    @ObservedObject var eqViewModel: EQViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(frequency)
                    .font(.caption2)
                    .foregroundColor(.asLabelTertiary)
                    .frame(width: 40, alignment: .leading)

                Slider(value: Binding(
                    get: { eqViewModel.bandGains[index] },
                    set: { newValue in eqViewModel.applyBandGain(index, newValue) }
                ), in: -20 ... 12, step: 0.1)
                    .tint(.asAccent)

                Text(String(format: "%+.1f", eqViewModel.bandGains[index]))
                    .font(BrandFont.mono)
                    .foregroundColor(.asLabel)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.asCard)
            .cornerRadius(6)
        }
    }
}

// MARK: - Response Label View

struct ResponseLabelView: View {
    let label: String

    var labelColor: Color {
        switch label {
        case "bright":
            return Color(red: 0.039, green: 0.518, blue: 1.0) // Blue
        case "warm":
            return Color(red: 1.0, green: 0.584, blue: 0.0) // Orange
        case "flat":
            return Color.asGreen
        default:
            return Color.asAccent
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .foregroundColor(labelColor)

            Text("Frequency Response: \(label.capitalized)")
                .font(BrandFont.body)
                .foregroundColor(.asLabel)

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(labelColor.opacity(0.12))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(labelColor.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Main EQ View

struct EQView: View {
    @EnvironmentObject var audioViewModel: AudioViewModel
    @StateObject private var eqViewModel: EQViewModel

    init() {
        // Initialize EQViewModel with a dummy AudioViewModel for preview
        // In real app, this will be set via environment
        let dummyAudioViewModel = AudioViewModel()
        _eqViewModel = StateObject(wrappedValue: EQViewModel(audioViewModel: dummyAudioViewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Response label indicator
                    ResponseLabelView(label: computeResponseLabel(bandGains: eqViewModel.bandGains))
                        .padding()

                    // Frequency response graph
                    FrequencyResponseGraphView(bandGains: eqViewModel.bandGains)

                    // Preset selector
                    PresetSelectorView(eqViewModel: eqViewModel)

                    // Band sliders
                    BandSlidersView(eqViewModel: eqViewModel)
                }
            }
        }
    }
}

// MARK: - Preview

// Preview disabled in CLI environment
// Uncomment in Xcode for live preview
// #Preview {
//     EQView()
//         .environmentObject(AudioViewModel())
//         .frame(minWidth: 600, minHeight: 800)
//         .background(Color.asWindow)
// }
