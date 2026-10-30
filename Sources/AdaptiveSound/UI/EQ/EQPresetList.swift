import DesignTokenKit
import EQEditKit
import LibraryBrowseKit
import SwiftUI

// MARK: - EQ presets list (Sprint EQ, EQ3 — ui-plan §5.2)

/// The Equalizer card's list: "Presets" (the built-ins) and "My Presets" (+ saves the current curve).
/// One Tab stop, and the screen's first focus (as the Library rail): ↑/↓ choose a preset and it plays at
/// once — "Bring back edits" covers anything left behind. On one of My Presets, Return renames it and ⌫
/// deletes it, after a confirmation (EQ4; its menu offers both too). Its keyboard cursor is
/// `ListKeyboardCursor`'s, its ring drawn only in keyboard mode. Longer than the card allows, it scrolls
/// inside the card with a fade at the bottom while more lies below, keeping the playing preset in view.
/// Inert while Pure plays, with the rest of the EQ's editing (`bitPerfectGate`).
struct EQPresetList: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(AudioViewModel.self) private var audio
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    let save: () -> Void
    /// Opens the Rename sheet for one of My Presets.
    let rename: (String) -> Void
    /// The list's natural height, which the card hugs.
    @Binding var contentHeight: CGFloat

    @FocusState private var focused: Bool
    /// More rows lie below the visible ones: the fade shows.
    @State private var moreBelow = false
    /// The My Preset whose deletion waits on the confirmation.
    @State private var deleting: String?

    var body: some View {
        let rows = eq.presetRows
        let cursor = ListKeyboardCursor.resolve(rows: rows, anchor: eq.current.preset)
        let ringRow = focused && showsKeyboardFocus ? cursor?.id : nil
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(NavSectionHeader(title: "Presets"))
                    ForEach(EQBuiltInPreset.allCases) { preset in
                        row(.builtIn(preset), ringRow: ringRow)
                    }
                    header(NavSectionHeader(title: "My Presets", addHelp: "Save Current as Preset…",
                                            addDisabled: !eq.isEdited, add: save))
                    myPresets(ringRow: ringRow)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
            } action: { _, more in
                moreBelow = more
            }
            .mask { fade }
            // While Pure plays no preset can be chosen, saved or brought back — the EQ's one rule (founder,
            // 2026-10-30); the switch's note above says so.
            .bitPerfectGate(.equalizer, audio.dspRowAvailability)
            .focusable()
            .focused($focused)
            .defaultFocus($focused, true)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                step(press, from: cursor, through: rows, proxy: proxy)
            }
            .onKeyPress(.return, action: renameCurrent)
            .onDeleteCommand(perform: currentMine.map { name in { deleting = name } })
            // The app's themed dialog, as a sheet (the window's own modality), not the system alert.
            .sheet(isPresented: isConfirmingDelete) {
                if let deleting {
                    EQDeletePresetDialog(name: deleting, delete: { confirmDelete(deleting) }, cancel: cancelDelete)
                }
            }
            .onChange(of: eq.current.preset, initial: true) { _, preset in proxy.scrollTo(preset) }
            #if DEBUG
                .sheetFocusSeed(.eqPresets) { focused = true }
            #endif
        }
    }

    /// A section header at the layout's fixed height (`EQScreenLayout` budgets it).
    private func header(_ header: NavSectionHeader) -> some View {
        header.frame(height: CGFloat(EQScreenLayout.sectionHeaderHeight))
    }

    @ViewBuilder
    private func myPresets(ringRow: EQPresetRef?) -> some View {
        let names = eq.myPresetNames
        if names.isEmpty {
            Text("None yet")
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
                .frame(height: CGFloat(EQScreenLayout.presetRowHeight))
        } else {
            ForEach(names, id: \.self) { name in
                row(.mine(name), ringRow: ringRow)
            }
        }
    }

    private func row(_ preset: EQPresetRef, ringRow: EQPresetRef?) -> some View {
        let isCurrent = eq.current.preset == preset
        return EQPresetRow(preset: preset, glyph: eq.glyphPoints(for: preset), isCurrent: isCurrent,
                           isEdited: eq.isEdited, isKeyboardCursor: ringRow == preset,
                           menu: menu(for: preset, isCurrent: isCurrent)) { choose(preset) }
            .id(preset) // the arrow keys' and the playing preset's `scrollTo` target
    }

    /// A row's menu: Bring back while edits are set aside; the pin on the row playing now; Rename and
    /// Delete on My Presets.
    private func menu(for preset: EQPresetRef, isCurrent: Bool) -> EQPresetRowMenu {
        let mine = preset.myPresetName
        return EQPresetRowMenu(
            bringBack: audio.dspRowAvailability.isLive
                ? eq.bringBack.map { ($0.edits.preset.displayName, eq.bringBackEdits) } : nil,
            pin: isCurrent ? eq.outputPin : nil,
            togglePin: eq.togglePin,
            rename: mine.map { name in { rename(name) } },
            delete: mine.map { name in { deleting = name } }
        )
    }

    /// The preset playing, when it is one of My Presets: what Return renames and ⌫ deletes.
    private var currentMine: String? {
        eq.current.preset.myPresetName
    }

    /// Return on one of My Presets opens its Rename sheet; on a built-in it passes on.
    private func renameCurrent() -> KeyPress.Result {
        guard let currentMine else { return .ignored }
        rename(currentMine)
        return .handled
    }

    private func confirmDelete(_ name: String) {
        deleting = nil
        eq.deleteMyPreset(name)
    }

    private func cancelDelete() {
        deleting = nil
    }

    /// The delete confirmation is up while a deletion waits on it; dismissing it cancels.
    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { shown in
            if !shown {
                deleting = nil
            }
        })
    }

    /// The bottom fade while more rows lie below (macOS hides the scroller until you scroll).
    private var fade: some View {
        LinearGradient(stops: [.init(color: .black, location: 0),
                               .init(color: .black, location: moreBelow ? 0.86 : 1),
                               .init(color: moreBelow ? .clear : .black, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    private func choose(_ preset: EQPresetRef) {
        eq.choose(preset)
        focused = true
    }

    /// ↑/↓: the preset a row away plays at once. `.ignored` past either end (so the key bubbles) and for
    /// shortcuts.
    private func step(_ press: KeyPress, from cursor: ListKeyboardCursor<EQPresetRef>?, through rows: [EQPresetRef],
                      proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !press.isShortcut,
              let target = cursor?.step(by: press.key == .upArrow ? -1 : 1, in: rows) else { return .ignored }
        eq.choose(target)
        proxy.scrollTo(target)
        return .handled
    }
}
