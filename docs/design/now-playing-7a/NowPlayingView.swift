//
//  NowPlayingView.swift
//  AdaptiveSound — "Now Playing" screen, design variant 5a ("Glass Inspector")
//
//  Reference SwiftUI implementation of the handoff design.
//  Wire the sample state to your real audio engine / DSP core.
//  Requires macOS 13+.
//

import SwiftUI

// MARK: - Design tokens

enum DS {
    // Teal accent set
    static let teal = Color(hex: 0x29B6A4)
    static let tealLight = Color(hex: 0x3FD0BA)
    static let tealLighter = Color(hex: 0x4FD2C0)
    static let tealText = Color(hex: 0x6FE0D0)
    static let tealBright = Color(hex: 0x8AF0E0)
    static let tealDeep = Color(hex: 0x1FA893)
    static let tealDarkest = Color(hex: 0x14897A)
    static let onTeal = Color(hex: 0x0C1413)
    static let amber = Color(hex: 0xFFB347)

    static let windowBG = Color(hex: 0x17181B)

    /// Spectrum palette: teal → lime, mapped to horizontal position (low → high freq)
    static let spectrumStops: [(t: Double, color: NSColor)] = [
        (0.0, NSColor(hex: 0x1F9D8B)), (0.2, NSColor(hex: 0x36C1AB)),
        (0.4, NSColor(hex: 0x4FD2C0)), (0.6, NSColor(hex: 0x7FE3A8)),
        (0.8, NSColor(hex: 0xA8EC84)), (1.0, NSColor(hex: 0xC8F06A)),
    ]

    static func spectrumColor(at t: Double) -> Color {
        let stops = spectrumStops
        var i = 0
        while i < stops.count - 2 && t > stops[i + 1].t {
            i += 1
        }
        let (t0, c0) = stops[i], (t1, c1) = stops[i + 1]
        let k = (t - t0) / (t1 - t0)
        return Color(nsColor: c0.lerp(to: c1, k: k))
    }
}

// MARK: - Model

struct Track: Identifiable {
    let id = UUID()
    let title: String
    let duration: String
    let format: String
    let absolutePath: String
}

final class PlayerModel: ObservableObject {
    @Published var tracks: [Track] = Track.samples
    @Published var currentIndex = 1
    @Published var isPlaying = true
    @Published var elapsed: Double = 114 // seconds
    @Published var duration: Double = 278
    @Published var masterGainDB: Double = 4.0 // −12…+12
    @Published var intensity: Double = 0.20 // 0…1
    @Published var integratedLUFS: Double = -15.1
    @Published var shortTermLUFS: Double = -14.2
    @Published var truePeakDBTP: Double = -0.8
    @Published var crossfeedEnabled = false
    @Published var headphonesConnected = false
    /// Log-bucketed FFT magnitudes 0…1, low → high frequency. Feed from the audio engine.
    @Published var spectrum: [Double] = (0 ..< 72).map { _ in .random(in: 0.15 ... 0.95) }

    var currentTrack: Track {
        tracks[currentIndex]
    }

    func togglePlay() {
        isPlaying.toggle()
    }

    func previous() {
        currentIndex = (currentIndex - 1 + tracks.count) % tracks.count; isPlaying = true
    }

    func next() {
        currentIndex = (currentIndex + 1) % tracks.count; isPlaying = true
    }

    func play(_ track: Track) {
        if let i = tracks.firstIndex(where: { $0.id == track.id }) { currentIndex = i; isPlaying = true }
    }
}

// MARK: - Root view

struct NowPlayingView: View {
    @StateObject private var model = PlayerModel()

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
            HeroBand(model: model)
            HStack(spacing: 0) {
                QueueColumn(model: model)
                InspectorPanel(model: model)
                    .frame(width: 260)
                    .padding(.trailing, 14)
                    .padding(.vertical, 12)
            }
            .frame(maxHeight: .infinity)
        }
        .background(DS.windowBG)
        .frame(minWidth: 1120, minHeight: 720)
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    @State private var selectedTab = "Now Playing"
    private let tabs = ["Now Playing", "Library", "EQ", "Monitoring", "Settings"]

    var body: some View {
        HStack(spacing: 14) {
            // App mark
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [DS.tealLight, DS.tealDarkest],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "waveform").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))

            // Output device capsule (single source of device selection)
            Menu {
                Button("MacBook Pro Speakers") {}
                Button("External Headphones") {}
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2").font(.system(size: 11)).foregroundStyle(DS.tealLighter)
                    Text("MacBook Pro Speakers").font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.5)
                }
                .padding(.horizontal, 13).frame(height: 32)
                .background(.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            // Tab capsule segmented control
            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? DS.onTeal : .white.opacity(0.65))
                            .padding(.horizontal, 13).frame(height: 26)
                            .background(selectedTab == tab ? DS.teal.opacity(0.92) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.black.opacity(0.35), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, 16).frame(height: 52)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }
}

// MARK: - Hero band

struct HeroBand: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.currentTrack.title)
                        .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                        .foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 8) {
                        Text("Nirvana").font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        BadgeView(text: "ENHANCED \(Int(model.intensity * 100))%", tint: .teal)
                        BadgeView(text: "\(model.currentTrack.format) · 44.1 kHz", tint: .gray)
                    }
                }
                TransportRow(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SpectrumAnalyzer(model: model)
                .frame(width: 400, height: 122)
        }
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22))
        .background(LinearGradient(colors: [DS.teal.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }
}

struct BadgeView: View {
    enum Tint { case teal, gray }
    let text: String
    let tint: Tint

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold)).kerning(0.5)
            .foregroundStyle(tint == .teal ? DS.tealText : .white.opacity(0.6))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint == .teal ? DS.teal.opacity(0.18) : .white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 7))
    }
}

struct TransportRow: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        HStack(spacing: 14) {
            // Glass transport pill
            HStack(spacing: 4) {
                TransportButton(system: "backward.fill", size: 38) { model.previous() }
                Button(action: model.togglePlay) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(colors: [DS.tealLight, DS.tealDeep, DS.tealDarkest],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle()
                        )
                        .shadow(color: DS.tealDeep.opacity(0.8), radius: 10, y: 6)
                }
                .buttonStyle(.plain)
                TransportButton(system: "forward.fill", size: 38) { model.next() }
            }
            .padding(5)
            .background(.white.opacity(0.06), in: Capsule())

            Text(timeString(model.elapsed)).monoTime()
            ScrubberSlider(value: Binding(
                get: { model.elapsed / model.duration },
                set: { model.elapsed = $0 * model.duration }
            ))
            Text(timeString(model.duration)).monoTime()
        }
    }

    private func timeString(_ s: Double) -> String {
        "\(Int(s) / 60):" + String(format: "%02d", Int(s) % 60)
    }
}

struct TransportButton: View {
    let system: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                .frame(width: size, height: size)
                .background(hovering ? .white.opacity(0.08) : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 4px slim slider with a 13px white knob — used by scrubber, gain, intensity.
struct ScrubberSlider: View {
    @Binding var value: Double // 0…1
    var fillColor: Color = DS.tealLight

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 4)
                Capsule()
                    .fill(LinearGradient(colors: [DS.tealDeep, fillColor], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, w * value), height: 4)
                Circle().fill(.white).frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    .offset(x: w * value - 6.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(1, max(0, g.location.x / w))
            })
        }
        .frame(height: 14)
    }
}

extension Text {
    func monoTime() -> some View {
        font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Spectrum analyzer (teal → lime, boxed panel)

struct SpectrumAnalyzer: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.34))

            // Bars — replace the animation with real FFT updates from the engine.
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(model.spectrum.indices, id: \.self) { i in
                    let t = Double(i) / Double(model.spectrum.count - 1)
                    let base = DS.spectrumColor(at: t)
                    UnevenRoundedRectangle(topLeadingRadius: 1.5, topTrailingRadius: 1.5)
                        .fill(LinearGradient(colors: [base, base.darkened(0.18)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(maxWidth: .infinity)
                        .frame(height: nil)
                        .scaleEffect(y: model.isPlaying ? model.spectrum[i] : model.spectrum[i] * 0.4,
                                     anchor: .bottom)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 16, trailing: 12))
            .opacity(model.isPlaying ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: model.spectrum)

            // Frequency scale
            HStack {
                Text("20 Hz"); Spacer(); Text("200"); Spacer(); Text("2 k"); Spacer(); Text("20 kHz")
            }
            .font(.system(size: 8.5, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 12).padding(.bottom, 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.05)))
    }
}

// MARK: - Queue

struct QueueColumn: View {
    @ObservedObject var model: PlayerModel
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Queue").font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.94))
                Text("\(model.tracks.count) tracks · 12:07:44")
                    .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.38))
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10))
                    TextField("Filter queue", text: $filter)
                        .textFieldStyle(.plain).font(.system(size: 11.5)).frame(width: 90)
                }
                .foregroundStyle(.white.opacity(0.42))
                .padding(.horizontal, 12).frame(height: 28)
                .background(.white.opacity(0.07), in: Capsule())
            }
            .padding(EdgeInsets(top: 14, leading: 22, bottom: 10, trailing: 16))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.tracks.enumerated()), id: \.element.id) { i, track in
                        QueueRow(track: track, index: i,
                                 isActive: i == model.currentIndex,
                                 isPlaying: model.isPlaying) { model.play(track) }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 12, trailing: 8))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct QueueRow: View {
    let track: Track
    let index: Int
    let isActive: Bool
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Group {
                    if isActive {
                        MiniEqualizer(animating: isPlaying)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.32))
                    }
                }
                .frame(width: 18, alignment: .trailing)

                Text(track.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? DS.tealBright : .white.opacity(0.82))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(track.format)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(isActive ? DS.tealText : .white.opacity(0.45))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(isActive ? DS.teal.opacity(0.18) : .white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 4))

                Text(track.duration)
                    .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isActive ? DS.teal.opacity(0.16) : hovering ? .white.opacity(0.05) : .clear)
            )
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isActive ? DS.teal.opacity(0.4) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(track.absolutePath) // tooltip: full file path
    }
}

struct MiniEqualizer: View {
    let animating: Bool
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< 3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.tealLighter)
                    .frame(width: 2.5, height: phase ? 12 : 5)
                    .animation(.easeInOut(duration: 0.6 + Double(i) * 0.18)
                        .repeatForever(autoreverses: true).delay(Double(i) * 0.12),
                        value: phase)
            }
        }
        .frame(height: 12)
        .onAppear { phase = animating }
        .onChange(of: animating) { phase = $0 }
    }
}

// MARK: - Inspector (floating glass, in flow)

struct InspectorPanel: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Master gain
            VStack(alignment: .leading, spacing: 8) {
                InspectorLabel(title: "Master Gain", value: String(format: "%+.1f dB", model.masterGainDB))
                ScrubberSlider(value: Binding(
                    get: { (model.masterGainDB + 12) / 24 },
                    set: { model.masterGainDB = $0 * 24 - 12 }
                ))
            }
            // Intensity
            VStack(alignment: .leading, spacing: 8) {
                InspectorLabel(title: "Intensity", value: "\(Int(model.intensity * 100)) %")
                ScrubberSlider(value: $model.intensity)
            }
            Divider().overlay(.white.opacity(0.09))

            // Loudness meters
            VStack(alignment: .leading, spacing: 9) {
                Text("Loudness").inspectorTitle()
                LoudnessMeter(label: "Integrated", value: model.integratedLUFS, range: -30 ... 0)
                LoudnessMeter(label: "Short-term", value: model.shortTermLUFS, range: -30 ... 0)
                LoudnessMeter(label: "True peak", value: model.truePeakDBTP, range: -12 ... 0, hot: model.truePeakDBTP > -1)
            }
            Divider().overlay(.white.opacity(0.09))

            // Crossfeed
            HStack {
                Text("Crossfeed").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.78))
                Spacer()
                Toggle("", isOn: $model.crossfeedEnabled)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .disabled(!model.headphonesConnected)
            }
            if !model.headphonesConnected {
                Text("Connect headphones to enable.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .background(Color(hex: 0x1A1C20).opacity(0.66), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.05)))
        .shadow(color: .black.opacity(0.65), radius: 20, y: 8)
    }
}

struct InspectorLabel: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).inspectorTitle()
            Spacer()
            Text(value)
                .font(.system(size: 11.5, design: .monospaced)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

extension Text {
    func inspectorTitle() -> some View {
        font(.system(size: 11, weight: .bold)).kerning(0.4)
            .textCase(.uppercase).foregroundStyle(.white.opacity(0.6))
    }
}

struct LoudnessMeter: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var hot = false

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.72))
                .frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(
                            colors: hot ? [DS.tealDeep, DS.tealLighter, DS.amber] : [DS.tealDeep, DS.tealLighter],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * max(0, min(1, fraction)))
                }
            }
            .frame(height: 6)
            Text(String(format: "%.1f", value))
                .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                .foregroundStyle(hot ? DS.amber : .white.opacity(0.85))
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - Sample data & helpers

extension Track {
    static let samples: [Track] = [
        .init(title: "Bruno Mars, Adele, Ed Sheeran, Maroon 5, Dua Lipa — Billboard Top 50 This Week", duration: "174:12", format: "MP3", absolutePath: "~/Music/Library/Playlists/Billboard Top 50.mp3"),
        .init(title: "Nirvana — Smells Like Teen Spirit (Official Music Video)", duration: "4:38", format: "MP3", absolutePath: "~/Music/Library/Rock/Nirvana/Smells Like Teen Spirit.mp3"),
        .init(title: "Premasiri Kemadasa — Master Songs Collection", duration: "37:31", format: "MP3", absolutePath: "~/Music/Library/Classical/Kemadasa/Master Songs.mp3"),
        .init(title: "Muse — Starlight (Official Music Video)", duration: "4:04", format: "MP3", absolutePath: "~/Music/Library/Rock/Muse/Starlight.mp3"),
        .init(title: "Green Day — Boulevard Of Broken Dreams [4K Upgrade]", duration: "4:47", format: "MP3", absolutePath: "~/Music/Library/Rock/Green Day/Boulevard.mp3"),
        .init(title: "Gotye — Somebody That I Used To Know (feat. Kimbra)", duration: "4:03", format: "MP3", absolutePath: "~/Music/Library/Pop/Gotye/Somebody.mp3"),
        .init(title: "PSY — Gangnam Style (M/V)", duration: "4:12", format: "MP3", absolutePath: "~/Music/Library/Pop/PSY/Gangnam Style.mp3"),
        .init(title: "Ed Sheeran, Rihanna, Selena Gomez — Billboard Hot 100", duration: "203:16", format: "MP3", absolutePath: "~/Music/Library/Playlists/Billboard Hot 100.mp3"),
        .init(title: "LMFAO — Sexy and I Know It", duration: "3:23", format: "MP3", absolutePath: "~/Music/Library/Pop/LMFAO/Sexy and I Know It.mp3"),
        .init(title: "Beautiful South — Perfect 10", duration: "3:35", format: "MP3", absolutePath: "~/Music/Library/Pop/Beautiful South/Perfect 10.mp3"),
        .init(title: "Ed Sheeran — You Need Me, I Don't Need You", duration: "4:01", format: "MP3", absolutePath: "~/Music/Library/Pop/Ed Sheeran/You Need Me.mp3"),
        .init(title: "Kasabian — Where Did All the Love Go (Video)", duration: "4:10", format: "MP3", absolutePath: "~/Music/Library/Rock/Kasabian/Where Did All the Love Go.mp3"),
        .init(title: "Vanessa Carlton — A Thousand Miles", duration: "4:26", format: "MP3", absolutePath: "~/Music/Library/Pop/Vanessa Carlton/A Thousand Miles.mp3"),
        .init(title: "Nickelback — Rockstar", duration: "4:15", format: "MP3", absolutePath: "~/Music/Library/Rock/Nickelback/Rockstar.mp3"),
        .init(title: "Red Hot Chili Peppers — Scar Tissue [HD Upgrade]", duration: "3:41", format: "MP3", absolutePath: "~/Music/Library/Rock/RHCP/Scar Tissue.mp3"),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Darken by multiplying RGB (matches the prototype's 18% darkening).
    func darkened(_ amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return Color(red: ns.redComponent * (1 - amount),
                     green: ns.greenComponent * (1 - amount),
                     blue: ns.blueComponent * (1 - amount))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    func lerp(to other: NSColor, k: CGFloat) -> NSColor {
        let a = usingColorSpace(.sRGB)!, b = other.usingColorSpace(.sRGB)!
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * k,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * k,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * k,
                       alpha: 1)
    }
}

#Preview {
    NowPlayingView()
}
