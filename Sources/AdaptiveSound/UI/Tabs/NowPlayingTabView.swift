import SwiftUI

// MARK: - Now Playing Tab View

struct NowPlayingTabView: View {
    @State private var masterGain: Double = 58.0

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                // LEFT: Album Art & Playback Info (50%)
                AlbumArtAndPlaybackSection()
                    .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)
                    .padding(16)

                // RIGHT: DSP Dashboard (50%)
                DSPDashboardSection(masterGain: $masterGain)
                    .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)
                    .padding(16)
                    .background(Color.asCard)
                    .borderOrDivider()
            }
            .background(Color.asWindow)
        }
    }
}

// MARK: - Album Art & Playback Section

struct AlbumArtAndPlaybackSection: View {
    var body: some View {
        VStack(spacing: 16) {
            // Album Art Placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.asCard)
                    .aspectRatio(1, contentMode: .fit)

                Image(systemName: "music.note")
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(.asLabelSecond)
            }
            .frame(maxWidth: 400)

            // Song Info
            VStack(spacing: 8) {
                Text("Untitled Track")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.asLabel)
                    .lineLimit(1)

                Text("Unknown Artist")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.asLabelSecond)
                    .lineLimit(1)

                Text("Unknown Album")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.asLabelTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Progress Bar
            VStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.asAccent)
                        .frame(maxWidth: .infinity * 0.35, alignment: .leading)
                        .frame(height: 4)
                }

                HStack {
                    Text("1:23")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.asLabelSecond)

                    Spacer()

                    Text("3:45")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.asLabelSecond)
                }
            }
            .frame(maxWidth: .infinity)

            // Spectrum Analyzer (Visual Stub - 15 Bars)
            SpectrumAnalyzerView()

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Spectrum Analyzer Stub

struct SpectrumAnalyzerView: View {
    @State private var barHeights: [Double] = (0 ..< 15).map { _ in Double.random(in: 0.2 ... 1.0) }

    var body: some View {
        VStack(spacing: 8) {
            Text("Spectrum")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.asLabelTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0 ..< 15, id: \.self) { index in
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.asAccent,
                                        Color.asAccent.opacity(0.6),
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: CGFloat(barHeights[index]) * 60)
                    }
                    .frame(maxHeight: 60, alignment: .bottom)
                }
            }
            .frame(height: 70)
            .padding(.vertical, 8)
        }
        .padding(12)
        .background(Color.asInset)
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
    }
}

// MARK: - DSP Dashboard Section

struct DSPDashboardSection: View {
    @Binding var masterGain: Double

    var body: some View {
        VStack(spacing: 16) {
            // Active Modules Section
            VStack(spacing: 12) {
                Text("ACTIVE MODULES")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.asLabelTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    ModuleStatusRow(name: "EQ", status: "Flat", isActive: true)
                    ModuleStatusRow(name: "Clarity", status: "Off", isActive: false)
                    ModuleStatusRow(name: "BRIR", status: "Off", isActive: false)
                    ModuleStatusRow(name: "Loudness", status: "Off", isActive: false)
                    ModuleStatusRow(name: "Limiter", status: "Active", isActive: true)
                }
            }

            Divider()
                .background(Color.asHairline)

            // Master Gain Slider
            VStack(spacing: 10) {
                HStack {
                    Text("Master Gain")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.asLabel)

                    Spacer()

                    Text("\(Int(masterGain))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.asAccent)
                        .monospacedDigit()
                }

                Slider(value: $masterGain, in: 0 ... 100, step: 1)
                    .accessibilityLabel("Master Gain")
                    .accessibilityValue("\(Int(masterGain))%")
            }

            Divider()
                .background(Color.asHairline)

            // Output Device Info
            VStack(spacing: 8) {
                Text("OUTPUT DEVICE")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.asLabelTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built-in")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.asLabel)

                        Text("48 kHz")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.asLabelSecond)
                    }
                    Spacer()
                }
            }

            Divider()
                .background(Color.asHairline)

            // Intensity Knob (Disabled, Phase 1.5)
            VStack(spacing: 10) {
                HStack {
                    Text("Intensity")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.asLabel)

                    Spacer()

                    Text("Phase 1.5")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.asLabelTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.asInset)
                        .cornerRadius(4)
                }

                ZStack {
                    Circle()
                        .stroke(Color.asHairline, lineWidth: 2)
                        .frame(height: 60)

                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.asLabelTertiary)

                        Text("Disabled")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.asLabelTertiary)
                    }
                }
                .frame(height: 80)
                .opacity(0.5)
                .accessibilityLabel("Intensity knob")
                .accessibilityValue("Disabled - Phase 1.5")
                .accessibilityAddTraits(.isStaticText)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Module Status Row

struct ModuleStatusRow: View {
    let name: String
    let status: String
    let isActive: Bool

    var body: some View {
        HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive ? .asAccent : .asLabelTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.asLabel)
            }

            Spacer()

            Text(status)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.asLabelSecond)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.asInset.opacity(0.5))
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(status)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Helper Extensions

extension View {
    func borderOrDivider() -> some View {
        overlay(
            VStack {
                Rectangle()
                    .fill(Color.asHairline)
                    .frame(width: 0.5)
            },
            alignment: .leading
        )
    }
}
