import SwiftUI

// MARK: - Capsule switch (S10.8 D3 — the app's one 2–3 segment switch)

/// A small segmented switch: a carved `tabTrack` capsule holding 2–3 segments, the selected one
/// raised (`segmentSelected`) — the tab strip's grammar at control scale. The queue's Up Next /
/// Recent today; the EQ's interpolation switch in Sprint F.
///
/// - **Selection is not shown by fill alone.** The raised segment is ≈ 1.3:1 (dark) and ≈ 2:1
///   (light) against the track — too faint to carry the selection — so it also gets a 1pt
///   `accentForeground` ring that clears 3:1 against the track and the segment in both
///   appearances (R4-SEG-02), and a bold, full-strength title (the others are semibold secondary).
/// - **VoiceOver:** a group named by `label`, valued by the selected title; each segment is a
///   button, the selected one carrying the Selected trait.
/// - **Keyboard:** ONE Tab stop under Full Keyboard Access (the segments are not stops of their
///   own); ← / → select the neighbouring segment (mirrored right-to-left), like a native segmented
///   control; a shortcut (⌘, ⌥ or ⌃ held) passes through. The app's keyboard ring is drawn around
///   the track. A click selects without taking key focus (the `.activate` interaction).
/// - Segment heights scale with Dynamic Type; a caller that `fixedSize()`s the switch never
///   truncates a title.
struct CapsuleSwitch<Value: Hashable>: View {
    private let label: String
    @Binding private var selection: Value
    private let options: [Value]
    private let title: (Value) -> String

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - label: the switch's VoiceOver name ("Queue view") — required, like the chip's.
    ///   - options: the segments, in order (2–3).
    ///   - title: a segment's visible title, which is also its VoiceOver label.
    init(_ label: String, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
        assert(!label.isEmpty, "a capsule switch needs its accessibility label")
        assert((2 ... 3).contains(options.count), "a capsule switch has 2–3 segments")
        self.label = label
        _selection = selection
        self.options = options
        self.title = title
    }

    var body: some View {
        HStack(spacing: ControlMetrics.segmentSpacing) {
            ForEach(options, id: \.self) { option in
                Segment(title: title(option), isSelected: option == selection) {
                    selection = option
                }
            }
        }
        .padding(ControlMetrics.switchTrackPadding)
        .background(TabTrackCapsule())
        .focusable(interactions: .activate)
        .controlFocusRing(around: Capsule(style: .circular))
        .onKeyPress(keys: [.leftArrow, .rightArrow], action: step)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(title(selection))
    }

    /// ← / → select the visually previous / next segment. At either end the key is still the
    /// switch's: a focused control owns its arrows, so nothing behind it moves instead.
    private func step(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut, let index = options.firstIndex(of: selection) else { return .ignored }
        let forward = (press.key == .rightArrow) == (layoutDirection == .leftToRight)
        let target = forward ? index + 1 : index - 1
        if options.indices.contains(target) {
            selection = options[target]
        }
        return .handled
    }
}

extension CapsuleSwitch {
    /// One segment: a plain button with its capsule built inside the label (the hit shape) —
    /// raised and ringed when selected, washed on hover. Not a focus stop: the switch is.
    private struct Segment: View {
        let title: String
        let isSelected: Bool
        let select: () -> Void

        @State private var isHovered = false
        @ScaledMetric(relativeTo: .callout) private var height = ControlMetrics.segmentHeight

        var body: some View {
            // Circular ends: a continuous capsule's 1pt `strokeBorder` draws a straight,
            // pixel-snapped tick at each end (seen on the picture sheets); a round end has none.
            let shape = Capsule(style: .circular)
            Button(action: select) {
                Text(title)
                    .font(.callout.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected || isHovered ? DesignSystem.Color.label
                        : DesignSystem.Color.labelSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, ControlMetrics.segmentTitleInset)
                    .frame(height: height)
                    .background {
                        if isSelected {
                            shape
                                .fill(DesignSystem.Color.segmentSelected)
                                .overlay {
                                    shape.strokeBorder(DesignSystem.Color.accentForeground,
                                                       lineWidth: ControlMetrics.stateRingWidth)
                                }
                        } else if isHovered {
                            shape.fill(DesignSystem.Color.hoverWash)
                        }
                    }
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
