import EQEditKit
import SwiftUI

// MARK: - EQ graph (Sprint EQ, EQ3 — the graph IS the editor)

/// The 31 points over ±12 dB on the analyzer lens, with the curve the EQ PLAYS (EQ1a's designer, via
/// `EQViewModel.played`). Drag a point and its neighbours follow (`EQStroke`, through the view model's
/// stroke API); the keyboard cursor follows the click. One Tab stop: ←/→ move the cursor, Home/End jump,
/// ↑/↓ adjust by 0.5 dB (⇧ 3 dB), ⌫ returns the band to its preset, Esc cancels a drag. Its ring shows
/// only while navigating by keyboard. VoiceOver gets 31 adjustable points (`+Accessibility`).
///
/// The layers: the analyzer silhouette (redrawing at 20 Hz on its own), one Canvas pass
/// (`EQGraphPainter`), the active point's handle, and the strip across the top.
struct EQGraph: View {
    @Environment(EQViewModel.self) var eq
    @Environment(AudioViewModel.self) var audio
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    #if DEBUG
        @Environment(\.sheetEQGraph) private var sheetSeed
    #endif

    /// The lens's size, for the plot map the handle and the hit-test place by.
    @State private var size: CGSize = .zero
    /// The drag under way, once its stroke began; nil at rest and once Esc cancelled it. Internal for
    /// the `+Input` extension (an extension of this type is this type).
    @State var drag: EQGraphDrag?
    /// The drag under way has begun its stroke (its first sample did); cleared when the drag ends.
    @State var strokeBegan = false
    /// VoiceOver has heard "held at the ceiling" in this stroke (once per stroke).
    @State var announcedCeiling = false
    /// The band the keyboard acts on. A click or drag moves it to that band (the cursor follows the click).
    @State var keyboardBand = 15
    @FocusState var focused: Bool
    /// Resets even on a drag the system cancels (which never reaches `onEnded`).
    @GestureState var isDragging = false

    var body: some View {
        let reading = EQGraphReading(eq) // the curve, resolved once per redraw
        let audible = eq.audible
        ZStack(alignment: .topLeading) {
            plot(reading, audible: audible)
            EQGraphStrip(audible: audible, keyboardReadout: keyboardReadout(reading),
                         toneReadout: eq.toneReadout, isDragging: drag != nil,
                         isHeldAtCeiling: drag?.isPastCeiling ?? false) {
                audio.selectedTab = .settings
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onDisappear { endStroke() }
        #if DEBUG
            .onAppear(perform: seedSheetState)
        #endif
    }

    private func plot(_ reading: EQGraphReading, audible: EQAudibleState) -> some View {
        // Everything the painter draws is read HERE, in the body — which is what observes the view
        // model and this view's state — and handed to the Canvas as values.
        let active = activeBand
        let region = eq.highlightedRegion
        let dragged = drag
        let tag = dragged.map { reading.tag(band: $0.band) }
        let points = reading.points
        let played = reading.played
        let plot = ZStack(alignment: .topLeading) {
            EQGraphSilhouette()
            Canvas { context, canvasSize in
                EQGraphPainter(map: .eqGraph(in: canvasSize), points: points, played: played, audible: audible,
                               highlightedRegion: region, activeBand: active, drag: dragged, tag: tag)
                    .draw(in: &context)
            }
            if let active, size.width > 0 {
                let map = EQPlotMap.eqGraph(in: size)
                EQPointHandle(diameter: EQGraphPainter.handleRadius * 2)
                    .keyboardFocusRing(ringVisible && drag == nil, around: Circle())
                    .position(x: map.x(forFreq: EQBands.nominalHz[active]),
                              y: map.y(forGain: Double(points[active])))
            }
        }
        .contentShape(Rectangle())
        return editable(plot, reading: reading)
    }

    // MARK: Derived

    /// The keyboard ring shows only while the graph holds focus in keyboard mode (Sprint A rule).
    private var ringVisible: Bool {
        focused && showsKeyboardFocus
    }

    /// The band with the handle and the column: the dragged one, else the keyboard cursor's while its
    /// ring shows.
    private var activeBand: Int? {
        drag?.band ?? (ringVisible ? keyboardBand : nil)
    }

    /// The plot map for the lens as last measured (the drag's hit-test uses it).
    var plotMap: EQPlotMap {
        .eqGraph(in: size)
    }

    private func keyboardReadout(_ reading: EQGraphReading) -> String? {
        guard ringVisible, drag == nil else { return nil }
        return reading.tag(band: keyboardBand)
    }

    #if DEBUG
        /// Picture sheets: the drag, the keyboard cursor and its focus the fixture asks for (an offscreen
        /// window gets no pointer and never becomes key).
        private func seedSheetState() {
            drag = sheetSeed.drag
            strokeBegan = sheetSeed.drag != nil
            if let band = sheetSeed.cursorBand {
                keyboardBand = band
                focused = true
            }
        }
    #endif
}
