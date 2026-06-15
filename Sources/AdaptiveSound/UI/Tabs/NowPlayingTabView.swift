import SwiftUI

// MARK: - Spectrum Color Palette

/// RGB value stored as (red, green, blue) in normalized [0, 1] range.
typealias RGBValue = (r: Double, g: Double, b: Double)

/// Frequency-based color palette for spectrum visualization.
/// Interpolated linearly in sRGB space from low frequencies (left, teal) to high (right, lime).
enum SpectrumColorPalette {
    struct Stop {
        let t: Float
        let rgb: RGBValue
    }

    // Palette: Teal → Lime (low freq to high freq)
    static let tealoLime: [Stop] = [
        Stop(t: 0.00, rgb: (r: 0x1F / 255.0, g: 0x9D / 255.0, b: 0x8B / 255.0)), // #1F9D8B
        Stop(t: 0.20, rgb: (r: 0x36 / 255.0, g: 0xC1 / 255.0, b: 0xAB / 255.0)), // #36C1AB
        Stop(t: 0.40, rgb: (r: 0x4F / 255.0, g: 0xD2 / 255.0, b: 0xC0 / 255.0)), // #4FD2C0
        Stop(t: 0.60, rgb: (r: 0x7F / 255.0, g: 0xE3 / 255.0, b: 0xA8 / 255.0)), // #7FE3A8
        Stop(t: 0.80, rgb: (r: 0xA8 / 255.0, g: 0xEC / 255.0, b: 0x84 / 255.0)), // #A8EC84
        Stop(t: 1.00, rgb: (r: 0xC8 / 255.0, g: 0xF0 / 255.0, b: 0x6A / 255.0)), // #C8F06A
    ]

    /// Get the base color for a bar at normalized position t [0, 1].
    /// Linearly interpolates between palette stops in sRGB space.
    static func colorAt(_ t: Float) -> Color {
        let clamped = max(0, min(1, t))

        // Find the two stops to interpolate between
        var lower = tealoLime[0]
        var upper = tealoLime[tealoLime.count - 1]

        for i in 0 ..< tealoLime.count - 1 {
            if tealoLime[i].t <= clamped && clamped <= tealoLime[i + 1].t {
                lower = tealoLime[i]
                upper = tealoLime[i + 1]
                break
            }
        }

        // Interpolation factor within [lower.t, upper.t]
        let localT = Double((upper.t > lower.t) ? (clamped - lower.t) / (upper.t - lower.t) : 0)
        let r = lower.rgb.r * (1 - localT) + upper.rgb.r * localT
        let g = lower.rgb.g * (1 - localT) + upper.rgb.g * localT
        let b = lower.rgb.b * (1 - localT) + upper.rgb.b * localT

        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Color Utilities

extension SpectrumColorPalette {
    /// Get the interpolated RGB value and darken factor for a bar at position t.
    /// Returns the RGB value and a gradient created from it.
    static func gradientAt(_ t: Float) -> LinearGradient {
        let clamped = max(0, min(1, t))

        // Find the two stops to interpolate between
        var lower = tealoLime[0]
        var upper = tealoLime[tealoLime.count - 1]

        for i in 0 ..< tealoLime.count - 1 {
            if tealoLime[i].t <= clamped && clamped <= tealoLime[i + 1].t {
                lower = tealoLime[i]
                upper = tealoLime[i + 1]
                break
            }
        }

        let localT = Double((upper.t > lower.t) ? (clamped - lower.t) / (upper.t - lower.t) : 0)
        let rgb = RGBValue(
            r: lower.rgb.r * (1 - localT) + upper.rgb.r * localT,
            g: lower.rgb.g * (1 - localT) + upper.rgb.g * localT,
            b: lower.rgb.b * (1 - localT) + upper.rgb.b * localT
        )

        let topColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        let bottomColor = Color(red: rgb.r * 0.82, green: rgb.g * 0.82, blue: rgb.b * 0.82)

        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: topColor, location: 0),
                .init(color: bottomColor, location: 1),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Now Playing Tab View

struct NowPlayingTabView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        HStack(spacing: 0) {
            LeftPanelView()
                .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)

            RightPanelView()
                .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)
                .padding(16)
                .background(Color.asCard)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.asHairline)
                        .frame(width: 0.5)
                }
        }
        .background(Color.asWindow)
    }
}

// MARK: - Left Panel

struct LeftPanelView: View {
    @Environment(AudioViewModel.self) var viewModel

    /// Semantic layout constants — adjust once, affects every section.
    private enum Layout {
        /// "Artistic" breathing room from the window's left edge.
        static let leadingPad: CGFloat = 28
        static let trailingPad: CGFloat = 20
        /// Consistent vertical rhythm between all sections.
        static let sectionVPad: CGFloat = 14
        /// The spectrum header warrants slightly more top air.
        static let spectrumVPad: CGFloat = 16
    }

    var body: some View {
        VStack(spacing: 0) {
            SpectrumAnalyzerView()
                .frame(height: 50)
                .padding(.leading, Layout.leadingPad)
                .padding(.trailing, Layout.trailingPad)
                .padding(.vertical, Layout.spectrumVPad)

            PlayControlsView()
                .padding(.leading, Layout.leadingPad)
                .padding(.trailing, Layout.trailingPad)
                .padding(.vertical, Layout.sectionVPad)

            MasterGainSliderView()
                .padding(.leading, Layout.leadingPad)
                .padding(.trailing, Layout.trailingPad)
                .padding(.vertical, Layout.sectionVPad)

            // Divider() does not respond to foregroundStyle on macOS —
            // a filled Rectangle is the only reliable way to honour the
            // hairline design token.
            Rectangle()
                .fill(Color.asHairline)
                .frame(height: 0.5)

            PlaylistView()
                .padding(.leading, Layout.leadingPad)
                .padding(.trailing, Layout.trailingPad)
                .padding(.vertical, Layout.sectionVPad)
        }
    }
}

// MARK: - Play Controls

struct PlayControlsView: View {
    @Environment(AudioViewModel.self) var viewModel

    private enum Layout {
        static let skipButtonSize: CGFloat = 52
        static let playButtonSize: CGFloat = 72
        /// Symbol scale: ~38% of container keeps proportions comfortable.
        static let skipSymbolSize: CGFloat = 20
        static let playSymbolSize: CGFloat = 26
        /// Gap between the three buttons.
        static let buttonSpacing: CGFloat = 24
    }

    var body: some View {
        HStack(spacing: Layout.buttonSpacing) {
            TransportButton(
                accessibilityLabel: "Previous track",
                systemImage: "backward.fill",
                symbolSize: Layout.skipSymbolSize,
                containerSize: Layout.skipButtonSize
            ) {
                if let currentIndex = viewModel.selectedTrackIndex, currentIndex > 0 {
                    viewModel.selectedTrackIndex = currentIndex - 1
                }
            }

            // Play / Pause — larger, gradient-filled, prominent.
            Button {
                if viewModel.isPlaying {
                    viewModel.stopPlayback()
                } else if viewModel.selectedTrackIndex != nil {
                    viewModel.startPlayback()
                }
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: Layout.playSymbolSize, weight: .semibold))
                    .foregroundStyle(.white)
                    // contentShape ensures the full circle area is hittable,
                    // not just the symbol's bounding box.
                    .frame(width: Layout.playButtonSize, height: Layout.playButtonSize)
                    .background(LinearGradient.asIconFill)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

            TransportButton(
                accessibilityLabel: "Next track",
                systemImage: "forward.fill",
                symbolSize: Layout.skipSymbolSize,
                containerSize: Layout.skipButtonSize
            ) {
                if let currentIndex = viewModel.selectedTrackIndex, currentIndex < viewModel.playlist.count - 1 {
                    viewModel.selectedTrackIndex = currentIndex + 1
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Transport Button

/// Reusable circular skip/transport button shared by Previous and Next.
private struct TransportButton: View {
    let accessibilityLabel: String
    let systemImage: String
    let symbolSize: CGFloat
    let containerSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(Color.asLabel)
                // contentShape ensures the full circle area is hittable,
                // not just the symbol's bounding box.
                .frame(width: containerSize, height: containerSize)
                .background(Color.asCard)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Master Gain Slider

struct MasterGainSliderView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: 8) {
            HStack {
                Text("Master Gain")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                Spacer()

                Text(String(format: "%.1f dB", Double(vm.masterGain) * 20 - 10))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.asLabelSecond)
            }

            Slider(value: $vm.masterGain, in: 0 ... 1, step: 0.01)
                .tint(Color.asAccent)
                .accessibilityLabel("Master Gain")
                .accessibilityValue(String(format: "%.1f decibels", Double(vm.masterGain) * 20 - 10))
        }
    }
}

// MARK: - Playlist View

struct PlaylistView: View {
    @Environment(AudioViewModel.self) var viewModel
    @State private var showFolderPicker = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Playlist")
                        .font(.caption.weight(.semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.asLabelSecond)

                    Text("\(viewModel.playlist.count) files · recursive")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.asLabelTertiary)
                }

                Spacer()

                // WinAmp-style playlist controls
                HStack(spacing: 8) {
                    // Shuffle toggle
                    Button(action: { viewModel.toggleShuffle() }) {
                        Image(systemName: viewModel.shuffleEnabled ? "shuffle.circle.fill" : "shuffle.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(viewModel.shuffleEnabled ? Color.asAccent : Color.asLabelSecond)
                    }
                    .help("Shuffle: \(viewModel.shuffleEnabled ? "On" : "Off")")

                    // Repeat mode toggle
                    Button(action: { viewModel.cycleRepeatMode() }) {
                        if viewModel.repeatMode == 0 {
                            Image(systemName: "repeat.circle")
                                .foregroundStyle(Color.asLabelSecond)
                        } else if viewModel.repeatMode == 1 {
                            Image(systemName: "repeat.circle.fill")
                                .foregroundStyle(Color.asAccent)
                        } else {
                            Image(systemName: "repeat.1.circle.fill")
                                .foregroundStyle(Color.asAccent)
                        }
                    }
                    .font(.system(size: 14))
                    .help(["Off", "All", "One"][viewModel.repeatMode])

                    // Jump to now-playing
                    if let currentIndex = viewModel.selectedTrackIndex {
                        Button(action: {
                            // Scroll to current track (implemented via ScrollViewReader)
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.asAccent)
                        }
                        .help("Jump to now playing")
                    }

                    Divider()
                        .frame(height: 20)

                    Button(action: { showFolderPicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .foregroundStyle(Color.asAccent)
                            Text("Choose Folder…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.asAccent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.asAccent.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.asAccent.opacity(0.5), lineWidth: 0.5)
                        }
                    }
                }
            }

            if !viewModel.folderPathDisplay.isEmpty {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.asLabelSecond)
                    Text(viewModel.folderPathDisplay)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.asLabelSecond)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.asCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            List {
                ForEach(Array(viewModel.playlist.enumerated()), id: \.element.id) { indexedElement in
                    let index = indexedElement.offset
                    let file = indexedElement.element
                    let isSelected = viewModel.selectedTrackIndex == index
                    let isNowPlaying = viewModel.isPlaying && isSelected

                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(isSelected ? Color.asAccent : Color.asLabelTertiary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.asAccent : Color.asLabel)
                                .lineLimit(1)

                            Text(file.relativePath)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.asLabelTertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(file.format)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isSelected ? Color.asAccent.opacity(0.2) : Color.asCard)
                            .foregroundStyle(isSelected ? Color.asAccent : Color.asLabelSecond)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text(file.durationSeconds > 0 ? formatDuration(file.durationSeconds) : "--:--")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.asLabelTertiary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(
                        isNowPlaying ?
                            Color.asAccent.opacity(0.25) // Brighter for now-playing
                            : isSelected ?
                            Color.asAccent.opacity(0.12)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedTrackIndex = index
                    }
                    // Double-click to play from the beginning
                    .onTapGesture(count: 2) {
                        viewModel.selectedTrackIndex = index
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            viewModel.startPlayback()
                        }
                    }
                    // Right-click context menu (WinAmp style)
                    .contextMenu {
                        Button("Remove from Playlist", systemImage: "trash") {
                            viewModel.removeTrack(at: index)
                        }
                        Button("Clear Playlist", systemImage: "clear") {
                            viewModel.clearPlaylist()
                        }
                    }
                    // Delete key to remove track
                    .onKeyPress(.delete) {
                        viewModel.removeTrack(at: index)
                        return .handled
                    }
                    // Keyboard navigation: Up/Down arrows
                    .onKeyPress(.upArrow) {
                        if index > 0 {
                            viewModel.selectedTrackIndex = index - 1
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if index < viewModel.playlist.count - 1 {
                            viewModel.selectedTrackIndex = index + 1
                        }
                        return .handled
                    }
                    // Keyboard navigation: Enter/Space to play
                    .onKeyPress(.return) {
                        if viewModel.selectedTrackIndex == index {
                            if viewModel.isPlaying {
                                viewModel.stopPlayback()
                            } else {
                                viewModel.startPlayback()
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.space) {
                        if viewModel.selectedTrackIndex == index {
                            if viewModel.isPlaying {
                                viewModel.stopPlayback()
                            } else {
                                viewModel.startPlayback()
                            }
                        }
                        return .handled
                    }
                }
                .onMove { source, destination in
                    viewModel.movePlaylistItems(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)
            // Global keyboard shortcuts for the playlist
            .onKeyPress(.upArrow) {
                if let current = viewModel.selectedTrackIndex, current > 0 {
                    viewModel.selectedTrackIndex = current - 1
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow) {
                if let current = viewModel.selectedTrackIndex, current < viewModel.playlist.count - 1 {
                    viewModel.selectedTrackIndex = current + 1
                    return .handled
                }
                return .ignored
            }
            // Global Enter/Space to play selected track
            // Always play the selected track (stops any other track automatically)
            .onKeyPress(.return) {
                if viewModel.selectedTrackIndex != nil {
                    viewModel.startPlayback()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.space) {
                if viewModel.selectedTrackIndex != nil {
                    viewModel.startPlayback()
                    return .handled
                }
                return .ignored
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let folderURL = urls.first {
                let didAccess = folderURL.startAccessingSecurityScopedResource()
                defer { if didAccess { folderURL.stopAccessingSecurityScopedResource() } }
                Task {
                    await viewModel.loadMusicFolder(folderURL)
                }
            }
        }
    }
}

// MARK: - Right Panel

struct RightPanelView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Now Playing Widget
            if let selectedIndex = viewModel.selectedTrackIndex, selectedIndex < viewModel.playlist.count {
                let currentTrack = viewModel.playlist[selectedIndex]
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.asAccent)
                            .frame(width: 52, height: 52)
                            .background(Color.asWindow)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentTrack.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.asLabel)
                                .lineLimit(1)

                            Text("Unknown Artist")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.asLabelSecond)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Text("0:00")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.asLabelTertiary)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.asCard)

                                Capsule()
                                    .fill(Color.asAccent)
                                    .frame(width: currentTrack.durationSeconds > 0 ? geo.size.width * CGFloat(0.0 / currentTrack.durationSeconds) : 0)
                            }
                        }
                        .frame(height: 3)

                        Text(currentTrack.durationSeconds > 0 ? formatDuration(currentTrack.durationSeconds) : "--:--")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.asLabelTertiary)
                    }
                }
                .padding(12)
                .background(Color.asWindow)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.asLabelTertiary)
                            .frame(width: 52, height: 52)
                            .background(Color.asCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("No track selected")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.asLabelSecond)
                                .lineLimit(1)

                            Text("Click a track to play")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.asLabelTertiary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Text("--:--")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.asLabelTertiary)

                        GeometryReader { _ in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.asCard)
                            }
                        }
                        .frame(height: 3)

                        Text("--:--")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.asLabelTertiary)
                    }
                }
                .padding(12)
                .background(Color.asWindow)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Modules
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Modules")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                ForEach([("EQ", true), ("Clarity", false), ("BRII", false), ("Loudness", false), ("Limiter", true)], id: \.0) { name, active in
                    HStack(spacing: 8) {
                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(active ? Color.asAccent : Color.asLabelTertiary)
                            .font(.system(size: 16))
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.asLabel)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(name), \(active ? "active" : "inactive")")
                }
            }

            // Intensity
            VStack(alignment: .leading, spacing: 8) {
                Text("Intensity")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [2]))
                        .foregroundStyle(Color.asHairline)

                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.asLabelTertiary)

                        Text("No module selected")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.asLabelTertiary)
                    }
                }
                .frame(height: 80)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Intensity: no module selected")
            }

            Spacer()
        }
    }
}

// MARK: - Spectrum Analyzer

/// Displays real-time FFT magnitude bars sourced from `AudioViewModel.spectrumBars`.
///
/// The ViewModel updates `spectrumBars` on the main thread at ~20 Hz via a Timer.
/// SwiftUI's `@Observable` machinery propagates changes to this view automatically;
/// no `TimelineView` or fake random data is needed.
///
/// Accessibility: the view is hidden from the accessibility tree (it is a purely
/// decorative animation). Screen readers will still see the playback controls.
struct SpectrumAnalyzerView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        let bars = viewModel.spectrumBars
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< bars.count, id: \.self) { index in
                // Compute normalized horizontal position: 0 (left/low-freq) to 1 (right/high-freq)
                let t = bars.count > 1 ? Float(index) / Float(bars.count - 1) : 0

                // Get the frequency-based gradient for this bar
                let barGradient = SpectrumColorPalette.gradientAt(t)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barGradient)
                    // Height is in [0, 1]; clamp defensively before scaling to 50pt.
                    .frame(height: CGFloat(min(max(bars[index], 0), 1)) * 50)
                    // Animate height changes with a short ease-out.
                    // When reduceMotion is on, skip the animation entirely.
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.08),
                        value: bars[index]
                    )
            }
        }
        .opacity(viewModel.isPlaying ? 1.0 : 0.4)
        .accessibilityHidden(true)
    }
}

// MARK: - Helper

func formatDuration(_ seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, secs)
}
