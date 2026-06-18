import SwiftUI

// MARK: - Transport Scrubber

/// Full-width interactive playhead scrubber.
/// Placed in `LeftPanelView` between `SpectrumAnalyzerView` and `PlayControlsView`.
/// Reads `AudioViewModel` from the environment; seek is committed on drag release only.
struct TransportScrubberView: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDragging = false
    @State private var dragFraction: Double = 0
    @State private var isHovered = false

    // MARK: Layout constants

    private enum Layout {
        /// Rendered height of the track capsule.
        static let trackHeight: CGFloat = 3
        /// Full-height invisible hit rectangle for a comfortable drag target.
        static let hitAreaHeight: CGFloat = 20
        /// Diameter of the thumb circle.
        static let thumbSize: CGFloat = 12
        /// Scale factor applied to the thumb while hovered or dragging.
        static let thumbHoverScale: CGFloat = 1.17
        /// Half-width of the tooltip capsule used for clamping and centering (≈ 44 pt wide).
        static let tooltipHalfWidth: CGFloat = 22
        /// Vertical offset of the tooltip above the track centre.
        static let tooltipYOffset: CGFloat = -22
    }

    // MARK: Derived state

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

    // MARK: Body

    var body: some View {
        HStack(spacing: 8) {
            timeLabel(formatDuration(displayPosition), prominent: isDragging)
                .accessibilityHidden(true)

            track
                .frame(height: Layout.hitAreaHeight)

            timeLabel(viewModel.duration > 0 ? formatDuration(viewModel.duration) : "--:--", prominent: false)
                .accessibilityHidden(true)
        }
        // Accessibility: treat as a single adjustable element
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard viewModel.duration > 0 else { return }
            let step = max(viewModel.duration * 0.02, 5)
            let newPos: Double
            switch direction {
            case .increment: newPos = min(viewModel.playbackPosition + step, viewModel.duration)
            case .decrement: newPos = max(viewModel.playbackPosition - step, 0)
            @unknown default: return
            }
            viewModel.seek(to: newPos)
        }
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width

            ZStack(alignment: .leading) {
                // Background capsule
                Capsule()
                    .fill(Color.asCard)
                    .frame(height: Layout.trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                // Filled portion
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(trackWidth * CGFloat(fraction), 0), height: Layout.trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                // Thumb — hidden when duration is unknown
                if viewModel.duration > 0 {
                    thumbView
                        .offset(x: max(thumbOffset(trackWidth: trackWidth) - Layout.thumbSize / 2, 0))
                        .frame(maxHeight: .infinity, alignment: .center)
                }

                // Tooltip shown only while dragging
                if isDragging && viewModel.duration > 0 {
                    tooltipView(trackWidth: trackWidth)
                }
            }
            // Full-height invisible hit rectangle for a comfortable 20pt drag target
            .contentShape(Rectangle())
            .onHover { hovering in isHovered = hovering }
            .gesture(viewModel.duration > 0 ? dragGesture(trackWidth: trackWidth) : nil)
        }
    }

    // MARK: Thumb

    private var thumbView: some View {
        Circle()
            .fill(Color.asLabel)
            .frame(width: Layout.thumbSize, height: Layout.thumbSize)
            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
            .scaleEffect(isHovered || isDragging ? Layout.thumbHoverScale : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered || isDragging)
    }

    // MARK: Tooltip

    private func tooltipView(trackWidth: CGFloat) -> some View {
        let offset = thumbOffset(trackWidth: trackWidth)
        // Clamp so the tooltip capsule doesn't clip out of bounds at the track edges.
        let clampedX = min(max(offset, Layout.tooltipHalfWidth), trackWidth - Layout.tooltipHalfWidth)

        return Text(formatDuration(dragFraction * viewModel.duration))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color.asLabel)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.asCard)
                    .overlay(Capsule().stroke(Color.asHairline, lineWidth: 0.5))
            )
            .offset(x: clampedX - Layout.tooltipHalfWidth, y: Layout.tooltipYOffset)
            .frame(maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }

    // MARK: Gesture

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

    // MARK: Helpers

    private func thumbOffset(trackWidth: CGFloat) -> CGFloat {
        CGFloat(fraction) * trackWidth
    }

    private func timeLabel(_ text: String, prominent: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(prominent ? Color.asLabelSecond : Color.asLabelTertiary)
    }

    private var fillColor: Color {
        if isInterrupted {
            return Color.asLabelTertiary
        }
        if viewModel.isPlaying {
            return Color.asAccent
        }
        return Color.asAccent.opacity(0.5)
    }

    private var accessibilityValue: String {
        guard viewModel.duration > 0 else { return "Duration unknown" }
        var value = "\(formatDuration(displayPosition)) of \(formatDuration(viewModel.duration))"
        if isInterrupted {
            value += " — playback paused, device disconnected"
        }
        return value
    }
}
