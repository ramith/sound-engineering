import LibraryStore
import SwiftUI

// MARK: - Header (count line + incremental filter field + Columns menu)

/// The Songs header band: leading "N songs · total duration" (or "N results" when filtered) count,
/// trailing filter field, then the "Columns" menu. Kept a separate view (reads only
/// `model.visibleSongs`/`matchedIDs`, never the table's selection) so a selection change never
/// re-sums the total.
struct SongsHeader: View {
    @Environment(LibraryBrowseModel.self) private var model
    /// Drives ⌘F focus + Escape defocus of the filter field (design §3.2/§8).
    @FocusState private var filterFocused: Bool
    /// The SAME per-column state the table binds (identical `@AppStorage` key → no drift with the
    /// native header context-menu). This side hosts the discoverable "Columns" button + Reset (§5),
    /// which the native menu can't offer.
    @AppStorage("songs.columns.v1")
    private var columnCustomization = TableColumnCustomization<LibraryTrackDisplay>()

    var body: some View {
        // Environment yields no binding; a local `@Bindable` provides `$model.searchQuery` for the
        // TextField (§6 — NOT a hand-rolled `Binding(get:set:)`).
        @Bindable var model = model
        HStack(spacing: DesignSystem.Spacing.small) {
            Text(model.songsCountLine)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
            Spacer(minLength: DesignSystem.Spacing.small)
            filterField(query: $model.searchQuery)
            columnsMenu
        }
        .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
        .frame(height: DesignSystem.SongsList.headerHeight)
        .background {
            // ⌘F focuses the filter field. A `.hidden()` button keeps the shortcut installed
            // regardless of field state — an `if`/`.disabled` would drop the shortcut (§6/§8).
            Button("Find in Songs") { filterFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    /// The trailing filter field (§3.2 / parent §10.2): 28pt `card` pill with a 0.5 `hairline`
    /// stroke, leading `magnifyingglass`, the bound `TextField`, and a trailing clear button when
    /// non-empty. Escape clears-then-defocuses via `.onExitCommand` (the macOS Cancel hook).
    private func filterField(query: Binding<String>) -> some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignSystem.Color.labelTertiary)
            TextField("Filter Songs", text: query)
                .textFieldStyle(.plain)
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.label)
                .focused($filterFocused)
                .onExitCommand {
                    query.wrappedValue = ""
                    filterFocused = false
                }
            if !query.wrappedValue.isEmpty {
                Button {
                    query.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignSystem.Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .frame(height: 28)
        .frame(minWidth: DesignSystem.SongsList.searchFieldMinWidth,
               idealWidth: DesignSystem.SongsList.searchFieldIdealWidth)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                .fill(DesignSystem.Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                .stroke(DesignSystem.Color.hairline, lineWidth: 0.5)
        )
    }

    /// The trailing "Columns" menu (§5 / §11.3): a thin glyph `Menu` over the SAME
    /// `columnCustomization` state as the table — one toggle per hideable column plus Reset to
    /// Default (a fresh `TableColumnCustomization()`), which the native header menu lacks.
    /// Title/Artwork are omitted (locked). It rides with the header, so it's present exactly when
    /// rows are. VoiceOver reads each `Toggle`'s on/off state.
    private var columnsMenu: some View {
        Menu {
            ForEach(SongsColumns.hideable) { column in
                Toggle(column.label, isOn: visibilityBinding(for: column.id))
            }
            Divider()
            Button("Reset to Default") {
                columnCustomization = TableColumnCustomization<LibraryTrackDisplay>()
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(DesignSystem.Color.labelSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Columns")
        .accessibilityLabel("Columns")
    }

    /// A `Visibility`↔`Bool` bridge for a column's show/hide `Toggle`. A `Binding(get:set:)` is
    /// acceptable HERE — this is a COLD menu path, not the hot Table body (§5). The `get` reports
    /// EFFECTIVE visibility (merging the default, §11.2); the `set` writes an EXPLICIT
    /// `.visible`/`.hidden` (never `.automatic`, which would follow a default-hidden column back to
    /// hidden). Writing persists via `@AppStorage`; the table's same-key state observes it → no drift.
    private func visibilityBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { SongsColumns.isVisible(id, in: columnCustomization) },
            set: { columnCustomization[visibility: id] = $0 ? .visible : .hidden }
        )
    }
}
