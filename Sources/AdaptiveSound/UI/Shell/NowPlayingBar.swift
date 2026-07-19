import DesignTokenKit
import SwiftUI

// MARK: - Now Playing Bar (footer transport — L3)

/// The persistent transport footer, shown on every tab. `AppShell` owns the 64pt band height,
/// the `panel` background, and the top hairline — this view paints none of them.
///
/// Four regions L→R: now-playing info (a button that opens the Now Playing tab) · compact
/// transport controls · flexible scrubber · condensed signal-path slot. Idle and loaded states
/// share identical geometry (R1 is fixed-width, R4 is a reserved slot), so nothing reflows
/// horizontally or vertically when playback starts/stops. `AudioViewModel` is `@Observable`, so
/// the 20 Hz playback tick invalidates only the scrubber/signal leaf views — never the other tabs.
struct NowPlayingBar: View {
    @Environment(AudioViewModel.self) private var viewModel

    /// The current track, or nil when idle (mirrors `NowPlayingWidget`'s detection).
    private var currentTrack: AudioFile? {
        guard let index = viewModel.selectedTrackIndex, index < viewModel.playlist.count else {
            return nil
        }
        return viewModel.playlist[index]
    }

    var body: some View {
        let track = currentTrack
        HStack(spacing: 0) {
            NowPlayingInfoRegion(track: track)
            Spacer(minLength: 0).frame(width: DesignSystem.Footer.regionGapInfoToControls)
            FooterTransportControls(isLoaded: track != nil)
            Spacer(minLength: 0).frame(width: DesignSystem.Footer.regionGap)
            FooterScrubber()
            Spacer(minLength: 0).frame(width: DesignSystem.Footer.regionGap)
            FooterSignalSlot(isLoaded: track != nil)
        }
        .padding(.horizontal, DesignSystem.Footer.hInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Fixed 64pt band can't grow — clamp so accessibility sizes don't overflow the chrome
        // (HIG-acceptable for a persistent transport, like the menu-bar clock).
        .dynamicTypeSize(.small ... .xLarge)
    }
}

// MARK: - R1: Now Playing info (opens the Now Playing tab)

private struct NowPlayingInfoRegion: View {
    @Environment(AudioViewModel.self) private var viewModel
    // S10.4 D2: the current track's resolved artist/artwork (nil until resolved / for loose files).
    @Environment(NowPlayingController.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let track: AudioFile?
    @State private var hovering = false

    private var isLoaded: Bool {
        track != nil
    }

    /// The footer subtitle: the resolved artist when known, else the honest "Unknown Artist"
    /// fallback (a loose file or a track with no artist tag), else the idle prompt.
    private var subtitle: String {
        guard isLoaded else { return "Select a track to play" }
        return nowPlaying.currentArtist ?? "Unknown Artist"
    }

    var body: some View {
        Button {
            viewModel.selectedTab = .nowPlaying
        } label: {
            HStack(spacing: DesignSystem.Footer.artGap) {
                artThumb
                VStack(alignment: .leading, spacing: 1) {
                    Text(track?.name ?? "Nothing playing")
                        .font(DesignSystem.Font.trackTitle)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(DesignSystem.Font.trackSubtitle)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLoaded)
        .frame(
            minWidth: DesignSystem.Footer.infoMinWidth,
            idealWidth: DesignSystem.Footer.infoIdealWidth,
            maxWidth: DesignSystem.Footer.infoIdealWidth,
            alignment: .leading
        )
        .layoutPriority(0)
        .background {
            if hovering, isLoaded {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                    .fill(DesignSystem.Color.label.opacity(0.06))
            }
        }
        .pointerStyle(isLoaded ? .link : nil)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isLoaded ? "Opens the Now Playing tab" : "")
    }

    @ViewBuilder private var artThumb: some View {
        let side = DesignSystem.Artwork.thumb
        Group {
            // Real cover when resolved (S10.4 D2); the music.note placeholder otherwise.
            if let artwork = nowPlaying.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .frame(width: side, height: side)
                    .background(DesignSystem.Color.card)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                .strokeBorder(DesignSystem.Color.hairline, lineWidth: 0.5)
        }
    }

    private var titleColor: Color {
        isLoaded ? DesignSystem.Color.label : DesignSystem.Color.labelSecondary
    }

    private var subtitleColor: Color {
        isLoaded ? DesignSystem.Color.labelSecondary : DesignSystem.Color.labelTertiary
    }

    private var accessibilityLabel: String {
        guard let track else { return "Nothing playing" }
        return "Now Playing, \(track.name), \(nowPlaying.currentArtist ?? "Unknown Artist")"
    }
}

// MARK: - R2: Transport controls (compact)

private struct FooterTransportControls: View {
    @Environment(AudioViewModel.self) private var viewModel
    let isLoaded: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Footer.controlSpacing) {
            skipButton(systemImage: "backward.fill", label: "Previous track") { viewModel.previousTrack() }
            playButton
            skipButton(systemImage: "forward.fill", label: "Next track") { viewModel.nextTrack() }
        }
        .fixedSize()
    }

    private func skipButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DesignSystem.Footer.skipSymbol, weight: .medium))
                .foregroundStyle(isLoaded ? DesignSystem.Color.label : DesignSystem.Color.labelDisabled)
                .frame(width: DesignSystem.Footer.skipButton, height: DesignSystem.Footer.skipButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(FooterControlButtonStyle())
        .disabled(!isLoaded)
        .accessibilityLabel(label)
    }

    /// Play/Pause — the glossy teal circle when loaded (S10.8 PR G: the shared `TealGloss`
    /// — inner top highlight + dark-only teal glow, same recipe as the active tab); a flat,
    /// disabled card circle when idle (same 34pt frame, so no reflow between states).
    private var playButton: some View {
        Button {
            viewModel.togglePlayPause()
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: DesignSystem.Footer.playSymbol, weight: .semibold))
                .foregroundStyle(isLoaded ? DesignSystem.Color.onAccent : DesignSystem.Color.labelDisabled)
                .frame(width: DesignSystem.Footer.playButton, height: DesignSystem.Footer.playButton)
                .background {
                    if isLoaded {
                        TealGloss(shape: Circle())
                    } else {
                        Circle().fill(DesignSystem.Color.card)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(FooterControlButtonStyle())
        .disabled(!isLoaded)
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
    }
}

/// Pressed-state feedback for the footer's background-less controls (the label owns its own
/// rest appearance / disabled color). Mirrors the existing `TransportButtonStyle` pattern.
private struct FooterControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - R3: Scrubber + times (the flexible fill)

/// Compact port of `TransportScrubberView` for the footer: the same proven drag/fraction/seek
/// math, with a hover-reveal thumb and footer-scale tokens. This is the app's ONLY scrubber now.
private struct FooterScrubber: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDragging = false
    @State private var dragFraction: Double = 0
    @State private var isHovered = false

    private var displayPosition: Double {
        isDragging ? dragFraction * viewModel.duration : viewModel.playbackPosition
    }

    private var fraction: Double {
        guard viewModel.duration > 0 else { return 0 }
        return min(max(displayPosition / viewModel.duration, 0), 1)
    }

    private var isInterrupted: Bool {
        viewModel.signalPath.interrupted
    }

    var body: some View {
        HStack(spacing: 8) {
            timeLabel(formatDuration(displayPosition), prominent: isDragging, alignment: .trailing)
            track
                .frame(minWidth: DesignSystem.Footer.scrubberTrackMinWidth, maxWidth: .infinity)
                .frame(height: DesignSystem.Footer.scrubberHitHeight)
            timeLabel(
                viewModel.duration > 0 ? formatDuration(viewModel.duration) : "--:--",
                prominent: false,
                alignment: .leading
            )
        }
        // No .layoutPriority: a lone `maxWidth: .infinity` child (the track) already absorbs all
        // surplus against the fixed/capped siblings. An explicit higher priority here risked
        // starving R1's title/artist to its min at every width (architect gate, the-fool #1).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard viewModel.duration > 0 else { return }
            let step = max(viewModel.duration * 0.02, 5)
            switch direction {
            case .increment: viewModel.seek(to: min(viewModel.playbackPosition + step, viewModel.duration))
            case .decrement: viewModel.seek(to: max(viewModel.playbackPosition - step, 0))
            @unknown default: return
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            ZStack(alignment: .leading) {
                // The shared 8a carved groove (PR 6 — same surface as the inspector sliders).
                // Fill follows playback; while playing it carries the realigned teal
                // gradient (S10.8 PR E — shared with sliders/meters), and the dark-only
                // glow shows only then (paused = dim teal, interrupted = grey). The state
                // change swaps erased style TYPES (gradient ↔ solid), which SwiftUI cannot
                // interpolate — the old play↔pause ease is gone by construction, so no
                // animation modifier here (a hard swap either way).
                CarvedGroove(fillFraction: fraction,
                             fillStyle: fillStyle,
                             glow: viewModel.isPlaying && !isInterrupted)

                // Thumb reveals on hover/drag only (cleaner than an always-on thumb).
                if viewModel.duration > 0, isHovered || isDragging {
                    thumbView
                        .offset(x: max(CGFloat(fraction) * trackWidth - DesignSystem.Footer.thumbSize / 2, 0))
                        .frame(maxHeight: .infinity, alignment: .center)
                }

                if isDragging, viewModel.duration > 0 {
                    tooltipView(trackWidth: trackWidth)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .gesture(viewModel.duration > 0 ? dragGesture(trackWidth: trackWidth) : nil)
        }
    }

    /// The hover/drag thumb: the shared carved knob (its bottom-shade cue replaces the old
    /// hand-painted drop shadow — the PR-1 shadow literal is retired by adoption, not tokenised).
    private var thumbView: some View {
        CarvedKnob(size: DesignSystem.Footer.thumbSize)
            .scaleEffect(isHovered || isDragging ? 1.15 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered || isDragging)
    }

    private func tooltipView(trackWidth: CGFloat) -> some View {
        let offset = CGFloat(fraction) * trackWidth
        let half = DesignSystem.Footer.tooltipHalfWidth
        let clampedX = min(max(offset, half), trackWidth - half)
        return Text(formatDuration(dragFraction * viewModel.duration))
            .font(DesignSystem.Font.monoSmall.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.label)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(DesignSystem.Color.card)
                    .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: 0.5))
            )
            .offset(x: clampedX - half, y: DesignSystem.Footer.tooltipYOffset)
            .frame(maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                dragFraction = min(max(value.location.x / trackWidth, 0), 1)
            }
            .onEnded { _ in
                viewModel.seek(to: dragFraction * viewModel.duration)
                isDragging = false
            }
    }

    private func timeLabel(_ text: String, prominent: Bool, alignment: Alignment) -> some View {
        Text(text)
            .font(DesignSystem.Font.monoSmall)
            .monospacedDigit()
            .foregroundStyle(prominent ? DesignSystem.Color.labelSecondary : DesignSystem.Color.labelTertiary)
            .frame(width: DesignSystem.Footer.timeLabelWidth, alignment: alignment)
            .accessibilityHidden(true)
    }

    private var fillStyle: AnyShapeStyle {
        if isInterrupted { return AnyShapeStyle(DesignSystem.Color.labelTertiary) }
        return viewModel.isPlaying
            ? AnyShapeStyle(DesignSystem.Gradient.meterFill)
            : AnyShapeStyle(DesignSystem.Color.accent.opacity(0.5))
    }

    private var accessibilityValue: String {
        guard viewModel.duration > 0 else { return "Duration unknown" }
        var value = "\(formatDuration(displayPosition)) of \(formatDuration(viewModel.duration))"
        if isInterrupted { value += " — playback paused, device disconnected" }
        return value
    }
}

// MARK: - R4: Signal slot (condensed path readout; reserved width even when idle)

private struct FooterSignalSlot: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isLoaded: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isLoaded { content }
        }
        .frame(width: DesignSystem.Footer.signalSlotWidth, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal path")
        .accessibilityValue(accessibilityValue)
        // Idle = empty reserved slot; don't leave a blank "Signal path" element for VoiceOver.
        .accessibilityHidden(!isLoaded)
    }

    @ViewBuilder private var content: some View {
        let info = viewModel.signalPath
        if info.interrupted {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Color.statusWarningText)
            Text("Disconnected")
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
                .lineLimit(1)
        } else {
            // Realigned (S10.8 PR G, `png/06`): the Enhanced dot is the hero chip's teal,
            // pulsing with the same §3.4 gate (playing + Reduce Motion off); "Enhanced"
            // reads in accentText. Pure/fallback keep their established dot colors.
            statusDot(info)
            // Teal "Enhanced" ONLY for the clean enhanced state: under Pure-fallback the
            // dot is the amber warning, and brand-teal text beside it would read as two
            // different states in 12pt of space (break-it finding) — neutral label there.
            (Text(info.path == .pure ? "Pure" : "Enhanced")
                .foregroundStyle(info.path == .enhanced && !info.fellBackToEnhanced
                    ? DesignSystem.Color.accentText : DesignSystem.Color.labelSecondary)
                + Text(" · \(info.formattedRate)")
                .foregroundStyle(DesignSystem.Color.labelSecondary))
                .font(DesignSystem.Font.monoSmall)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder private func statusDot(_ info: SignalPathInfo) -> some View {
        let dot = Circle()
            .fill(dotColor(info))
            .frame(width: 6, height: 6)
        if info.path == .enhanced, !info.fellBackToEnhanced,
           pulseIsActive(isPlaying: viewModel.isPlaying, reduceMotion: reduceMotion) {
            // Conditional phaseAnimator (§3.4) — unmounting IS the deterministic stop.
            dot.phaseAnimator([1.0, GlassDecor.pulseDimOpacity]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: GlassDecor.pulseHalfCycleSeconds)
            }
        } else {
            dot
        }
    }

    private func dotColor(_ info: SignalPathInfo) -> Color {
        if info.fellBackToEnhanced || info.interrupted { return DesignSystem.Color.statusWarning }
        if info.path == .pure { return DesignSystem.Color.accent }
        return DesignSystem.Color.accentBright
    }

    private var accessibilityValue: String {
        let info = viewModel.signalPath
        if info.interrupted { return "Playback paused, output device disconnected" }
        let pathStr = info.path == .pure ? "Pure mode" : "Enhanced mode"
        let rate = info.achievedSampleRate > 0
            ? info.formattedRate.replacing(" kHz", with: " kilohertz")
            : "unknown rate"
        return "\(pathStr), \(rate)"
    }
}
