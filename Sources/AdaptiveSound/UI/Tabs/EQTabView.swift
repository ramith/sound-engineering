import DesignTokenKit
import SwiftUI

// MARK: - EQ Tab View (Sprint EQ, EQ3 — the V1b screen, decision 24)

/// The EQ tab: the rail (Equalizer card, then EQ3t's Tone card) beside the graph card, on the Library's
/// Twin Panels insets over the same glow (mounted here, as Library does, until F1 mounts one for every
/// tab). Per-output memory isn't here: the composition root's Edge 5 switches the slot with any tab
/// (or no window) showing, and the shell's `EQOutputToast` says so.
///
/// The screen lets go of a held Compare on Esc (bubbling from whatever holds focus), on the window
/// losing key or the app going to the background, and on a tab change (this view goes away).
struct EQTabView: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(\.appearsActive) private var appearsActive
    @State private var isSaving = false

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(EQScreenLayout.columnGap)) {
            EQRail(save: beginSave) { EQToneCard() }
            EQGraphCard(save: beginSave)
        }
        .padding(.horizontal, CGFloat(EQScreenLayout.insetHorizontal))
        .padding(.top, CGFloat(EQScreenLayout.insetTop))
        .padding(.bottom, CGFloat(EQScreenLayout.insetBottom))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { GlowField(glows: GlowFieldSpec.libraryGlows) }
        .sheet(isPresented: $isSaving) {
            SaveCustomPresetView(eqViewModel: eq, isPresented: $isSaving)
        }
        .onKeyPress(.escape, action: releaseCompare)
        .onChange(of: appearsActive) { _, active in
            if !active {
                eq.endCompare()
            }
        }
        .onDisappear(perform: eq.endCompare)
    }

    private func beginSave() {
        isSaving = true
    }

    private func releaseCompare() -> KeyPress.Result {
        guard eq.isComparing else { return .ignored }
        eq.endCompare()
        return .handled
    }
}
