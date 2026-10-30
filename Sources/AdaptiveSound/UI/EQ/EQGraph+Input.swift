import EQEditKit
import SettingsKit
import SwiftUI

// MARK: - EQ graph: the drag and the keyboard

/// The views never write the curve: pointer samples and key presses go to the view model, whose stroke
/// API shapes them (`EQStroke`) and sends every sample at once.
extension EQGraph {
    /// One ↑/↓ press or VoiceOver swipe (dB); ⇧ takes `bigStepDb`.
    static let stepDb: Float = 0.5
    static let bigStepDb: Float = 3

    /// The plot's editing — the stroke, the keys, ⌫, VoiceOver's 31 points — and its gate: while Pure plays,
    /// nothing on the EQ screen can be edited (founder, 2026-10-30: nothing you can't hear can be changed, and the
    /// switch never flips by itself). The not-playing curve is the graph's own disabled look, so no dim on top; a
    /// stroke under way when Pure starts ends here, kept.
    func editable(_ plot: some View, reading: EQGraphReading) -> some View {
        let availability = audio.dspRowAvailability
        return plot
            .gesture(strokeGesture)
            .onChange(of: isDragging) { _, dragging in
                if !dragging {
                    endStroke()
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end], action: handleKey)
            .onKeyPress(.escape, action: cancelStroke)
            .onDeleteCommand { eq.resetBand(keyboardBand) }
            .graphAccessibility(eq: eq, reading: reading, map: plotMap, availability: availability)
            .bitPerfectGate(.equalizer, availability, ownDisabledLook: true)
            .onChange(of: availability.isLive) { _, live in
                if !live {
                    endStroke()
                }
            }
    }

    /// One stroke per press: every pointer sample, wherever the pointer goes, until it is released.
    var strokeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in strokeSample(at: value.location) }
            .onEnded { _ in endStroke() }
    }

    /// A pointer sample: the band nearest the pointer, at the pointer's level (the stroke holds it in
    /// ±12 dB; past +12 the graph ghosts what was asked). The first sample begins the stroke — the
    /// keyboard cursor follows the click and the graph takes focus, so Esc reaches the drag. Once the
    /// stroke is over early — Esc cancelled it, or a discrete edit (a preset choice, a key step) ended
    /// it mid-drag — the rest of the drag is ignored and its readout goes.
    func strokeSample(at location: CGPoint) {
        let map = plotMap
        guard map.width > 0, map.height > 0 else { return }
        let sample = EQGraphDrag(band: map.nearestBand(toX: location.x), requestedDb: map.gain(forY: location.y))
        if !strokeBegan {
            strokeBegan = true
            announcedCeiling = false
            keyboardBand = sample.band
            focused = true
            eq.beginStroke()
        }
        guard eq.isStroking else {
            drag = nil
            return
        }
        drag = sample
        eq.updateStroke(band: sample.band, db: Float(sample.requestedDb))
        if sample.isPastCeiling, !announcedCeiling {
            announcedCeiling = true
            AccessibilityNotification.Announcement("Held at plus 12 decibels, the EQ's ceiling").post()
        }
    }

    /// The drag is over — released, cancelled by the system, or the graph went away: the stroke stays
    /// (the view model persists and logs it once; a second call is a no-op).
    func endStroke() {
        strokeBegan = false
        drag = nil
        eq.endStroke()
    }

    /// Esc: cancels a stroke under way, putting back the curve from before it; otherwise it bubbles (the
    /// EQ tab releases a held Compare on it).
    func cancelStroke() -> KeyPress.Result {
        guard eq.cancelStroke() else { return .ignored }
        drag = nil
        return .handled
    }

    /// ←/→ move the cursor (held at the ends, so focus never leaves on an arrow), Home/End jump to the
    /// ends, ↑/↓ adjust the cursor's band by 0.5 dB (⇧ 3 dB). Shortcuts (⌘ ⌥ ⌃) pass, so ⌘← / ⌘→ still
    /// skip tracks.
    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut else { return .ignored }
        let step = press.modifiers.contains(.shift) ? Self.bigStepDb : Self.stepDb
        switch press.key {
        case .leftArrow: keyboardBand = max(keyboardBand - 1, 0)
        case .rightArrow: keyboardBand = min(keyboardBand + 1, EQBands.count - 1)
        case .home: keyboardBand = 0
        case .end: keyboardBand = EQBands.count - 1
        case .upArrow: eq.nudge(band: keyboardBand, by: step)
        case .downArrow: eq.nudge(band: keyboardBand, by: -step)
        default: return .ignored
        }
        return .handled
    }
}
