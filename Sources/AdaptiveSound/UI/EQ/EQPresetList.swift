import DesignTokenKit
import EQEditKit
import LibraryBrowseKit
import SwiftUI

// MARK: - EQ presets list (Sprint EQ, EQ3 — ui-plan §5.2)

/// The Equalizer card's list: "Presets" (the built-ins) and "My Presets" (+ saves the current curve).
/// One Tab stop, and the screen's first focus (as the Library rail): ↑/↓ choose a preset and it plays at
/// once — "Bring back edits" covers anything left behind. Its keyboard cursor is `ListKeyboardCursor`'s,
/// its ring drawn only in keyboard mode. Longer than the card allows, it scrolls inside the card with a
/// fade at the bottom while more lies below, keeping the playing preset in view.
struct EQPresetList: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    let save: () -> Void
    /// The list's natural height, which the card hugs.
    @Binding var contentHeight: CGFloat

    @FocusState private var focused: Bool
    /// More rows lie below the visible ones: the fade shows.
    @State private var moreBelow = false

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
            .focusable()
            .focused($focused)
            .defaultFocus($focused, true)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                step(press, from: cursor, through: rows, proxy: proxy)
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
                           setAside: eq.bringBack?.edits.preset.displayName,
                           choose: { choose(preset) }, bringBack: eq.bringBackEdits)
            .id(preset) // the arrow keys' and the playing preset's `scrollTo` target
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
