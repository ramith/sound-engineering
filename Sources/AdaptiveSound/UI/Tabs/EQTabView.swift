import DesignTokenKit
import SwiftUI

// MARK: - EQ Tab View (Sprint EQ, EQ3 — the V1b screen, decision 24)

/// The EQ tab: the rail (Equalizer card, then EQ3t's Tone card) beside the graph card, on the Library's
/// Twin Panels insets over the app glow the shell mounts behind every tab but Now Playing
/// (`TabContentView`, S10.8 F1). Per-output memory isn't here: the composition root's Edge 5 switches the
/// slot with any tab (or no window) showing, and the shell's `EQOutputToast` says so.
///
/// The screen lets go of a held Compare on Esc (anywhere in the app: `releasesCompareOnEscape`), on the
/// window losing key or the app going to the background, and on a tab change (this view goes away); the
/// app delegate lets go when the window closes.
struct EQTabView: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(\.appearsActive) private var appearsActive
    /// The Save or Rename sheet, while one is open.
    @State private var presetSheet: EQPresetSheet?

    var body: some View {
        // Two focus sections, so Tab finishes the rail (switch, presets, Tone) before the graph card.
        HStack(alignment: .top, spacing: CGFloat(EQScreenLayout.columnGap)) {
            EQRail(save: beginSave, rename: beginRename) { EQToneCard() }
                .focusSection()
            EQGraphCard(save: beginSave)
                .focusSection()
        }
        .padding(.horizontal, CGFloat(EQScreenLayout.insetHorizontal))
        .padding(.top, CGFloat(EQScreenLayout.insetTop))
        .padding(.bottom, CGFloat(EQScreenLayout.insetBottom))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $presetSheet) { sheet in
            SaveCustomPresetView(sheet: sheet, eqViewModel: eq)
        }
        .releasesCompareOnEscape(eq)
        .onChange(of: appearsActive) { _, active in
            if !active {
                eq.endCompare()
            }
        }
        .onDisappear(perform: eq.endCompare)
    }

    /// Save takes what plays now, and the slot it plays in, as the sheet opens (break-it C1).
    private func beginSave() {
        presetSheet = .save(eq.saveSource())
    }

    private func beginRename(_ name: String) {
        presetSheet = .rename(name)
    }
}
