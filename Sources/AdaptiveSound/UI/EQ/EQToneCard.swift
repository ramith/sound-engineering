import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - Tone card (EQ3t — decision 24, the V1b rail's second card)

/// Tone: five region macros over the 31 points — Bass, Body, Mids, Presence, Air — one centre-zero
/// ±12 dB slider each (`EQToneRow`), under a header with the fold chip and Reset Tone
/// (`EQToneHeader`). Tone is not a second mode: a slider moves the points its region reaches, the
/// graph shows them move, and the one 31-band engine plays them.
///
/// - **The fold** is the user's choice, remembered (`eq.toneFolded.v1`, read through the injected
///   defaults — `.defaultAppStorage`, never a `store:` of its own); the card never folds by itself.
///   Folded, it is one line: "TONE all at 0 dB" and the reset glyph.
/// - **The link to the graph:** the region the user is on — a row hovered, a slider dragged, or a
///   slider holding key focus while the window is keyboard-driven — tints its row and is
///   `EQViewModel.highlightedRegion`, which the graph shades with its readout. A drag holds it even
///   when the pointer strays off the row.
/// - **Keyboard:** the fold chip, Reset Tone, then the five sliders, in that Tab order; ←/→ or ↑/↓
///   step a focused slider by 0.5 dB.
///
/// Its height is exact (`EQScreenLayout.toneCardHeight`), so the rail's budget (LAY-EQ-01) holds — plus, while
/// Pure plays, the shared "Not in bit-perfect mode" note under the header, measured (R1.1-B, US-R1F-20): the
/// sliders and Reset Tone are inert then (`bitPerfectGate`), and the EQ's own card scrolls to make room.
struct EQToneCard: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(AudioViewModel.self) private var audio
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
        @Environment(\.sheetEQGraph) private var sheetSeed
    #endif

    /// Where the fold is remembered: the user's choice, through the injected defaults.
    static let foldedKey = "eq.toneFolded.v1"

    @AppStorage(foldedKey) private var isFolded = false
    @State private var hovered: EQToneRegion?
    @State private var dragged: EQToneRegion?
    @FocusState private var focused: EQToneRegion?
    /// The Pure note's measured height (0 while the Tone works).
    @State private var noteHeight: CGFloat = 0

    var body: some View {
        let availability = audio.dspRowAvailability
        VStack(alignment: .leading, spacing: CGFloat(EQScreenLayout.toneHeaderGap)) {
            EQToneHeader(isFolded: isFolded, availability: availability, toggleFold: toggleFold)
            if !availability.isLive {
                BitPerfectRowNote(row: .tone, availability: availability, leavePure: audio.leavePure)
                    .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { noteHeight = $0 }
            }
            if !isFolded {
                VStack(spacing: 0) {
                    ForEach(EQToneRegion.allCases) { region in
                        EQToneRow(region: region, isHighlighted: region == highlighted, focus: $focused) { dragging in
                            dragChanged(region, dragging: dragging)
                        }
                        .onHover { hovering in hoverChanged(region, hovering: hovering) }
                        .bitPerfectGate(.tone, availability)
                    }
                }
            }
        }
        .padding(CGFloat(EQScreenLayout.railCardPadding))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height + (availability.isLive ? 0 : noteHeight + CGFloat(EQScreenLayout.toneHeaderGap)),
               alignment: .top)
        .glassPanel(.panel, in: shape(isOneLine: isFolded && availability.isLive))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tone")
        .onChange(of: highlighted, initial: true) { _, region in
            eq.highlightedRegion = region
        }
        // Inert, the rows take no pointer: whatever one was hovered or dragged lets go of the graph's shading (the
        // slider ends its own drag, and with it the stroke).
        .onChange(of: availability.isLive) { _, live in
            if !live {
                hovered = nil
                dragged = nil
            }
        }
        .onDisappear(perform: clearHighlight)
        #if DEBUG
            .onAppear(perform: seedSheetState)
        #endif
    }

    /// The card's exact height (`EQScreenLayout.toneCardHeight`): the header alone folded, every row open.
    private var height: CGFloat {
        CGFloat(EQScreenLayout.toneCardHeight(rows: isFolded ? 0 : EQToneRegion.allCases.count))
    }

    /// Open, the rail cards' continuous corner. Folded to its one line, the card is too short for it — a
    /// continuous corner needs about one and a half radii of straight edge, or the panel's strokes overrun the
    /// card's ends as a sliver — so its ends round fully, circular.
    private func shape(isOneLine: Bool) -> RoundedRectangle {
        isOneLine
            ? RoundedRectangle(cornerRadius: height / 2, style: .circular)
            : RoundedRectangle(cornerRadius: CGFloat(GlassDecor.panelRadius), style: .continuous)
    }

    /// The region the user is on: a drag wins, then the pointer, then keyboard focus — shown only
    /// while the window is keyboard-driven, like the ring. None while folded.
    private var highlighted: EQToneRegion? {
        guard !isFolded else { return nil }
        return dragged ?? hovered ?? (showsKeyboardFocus ? focused : nil)
    }

    /// Folding drops the rows, so whatever the pointer was on goes with them.
    private func toggleFold() {
        hovered = nil
        dragged = nil
        withAnimation(reduceMotion ? nil : .snappy) {
            isFolded.toggle()
        }
    }

    private func hoverChanged(_ region: EQToneRegion, hovering: Bool) {
        if hovering {
            hovered = region
        } else if hovered == region {
            hovered = nil
        }
    }

    private func dragChanged(_ region: EQToneRegion, dragging: Bool) {
        if dragging {
            dragged = region
        } else if dragged == region {
            dragged = nil
        }
    }

    #if DEBUG
        /// Picture sheets: the Tone row the fixture hovers (an offscreen window gets no pointer).
        private func seedSheetState() {
            hovered = sheetSeed.toneRegion
        }
    #endif

    /// Leaving (the tab, the window) takes the shading with it: a hover's exit never comes then.
    private func clearHighlight() {
        hovered = nil
        dragged = nil
        eq.highlightedRegion = nil
    }
}
