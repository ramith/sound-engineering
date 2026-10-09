import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Songs header (S10.8 Library PR-D — `png/03`)

/// The Songs card header (`LibraryCardHeader`, the one header of the four categories): title,
/// count line, the Filter pill, then Songs' own Sort and Columns pills. The Sort pill drives the
/// SAME `model.sortOrder` / `applySortOrder` machinery the old Table header-clicks used (one source
/// of truth). Kept a separate view (reads only the model's count/searchQuery/sortOrder, never the
/// list's selection) so a selection change never re-sums.
///
/// The count line is "379 songs · 41 hrs" on ONE line, never wrapped (D6): where it doesn't fit —
/// the 880×640 minimum window, beside the three pills — the count alone ("379 songs") stands in.
/// VoiceOver reads the full line either way.
///
/// Sort and Columns stay labelled pills, not icon chips (S10.8 D3): Sort carries its value
/// ("Sort: Artist ↑") and the Library guide's addendum specifies Columns as icon + "Columns". They
/// take the chip's grammar where it fits a labelled pill — the app's keyboard ring
/// (`controlFocusRing`) in place of the system focus effect, a height and glyphs that scale with
/// the text size like the Filter pill and the chips — and Columns fills with the chip's accent
/// token (`controlActiveFill`, the same teal 16%).
struct SongsHeader: View {
    /// The Songs card's one focus value (`SongsView` owns it): the Filter pill is `.filter`.
    let focus: FocusState<CardFocus?>.Binding

    @Environment(LibraryBrowseModel.self) private var model
    /// The shared column config (SAME `@AppStorage` key as `SongsListView`): this pill toggles
    /// show/hide, the list renders + click-sorts. Drag-a-header reorder lands in the next sub-step.
    @AppStorage("songs.columns.v2") private var columnConfig = SongColumnConfig.default
    @ScaledMetric(relativeTo: .body) private var pillHeight = ControlMetrics.pillHeight
    @ScaledMetric(relativeTo: .callout) private var chevronSize: CGFloat = 9
    @ScaledMetric(relativeTo: .callout) private var columnsSymbolSize: CGFloat = 11

    var body: some View {
        @Bindable var model = model
        LibraryCardHeader(title: "Songs", count: model.songsCountLine, compactCount: model.songsCount,
                          filter: $model.searchQuery, filterPrompt: "Filter Songs", focus: focus) {
            sortPill
            columnsPill
        }
    }

    // MARK: Sort pill

    /// A sort field + its comparator factory (both directions from one `SortOrder` arg — a
    /// `KeyPathComparator` can't be rebuilt from a `PartialKeyPath`, so the concrete keypath is
    /// captured in the closure). Genre is display-only (no comparator), so it's absent.
    private struct SortOption: Identifiable {
        let id: String
        let label: String
        let defaultOrder: SortOrder
        let make: (SortOrder) -> KeyPathComparator<LibraryTrackDisplay>
    }

    private var sortOptions: [SortOption] {
        [
            SortOption(id: "title", label: "Title", defaultOrder: .forward) {
                KeyPathComparator(\.title, order: $0)
            },
            SortOption(id: "artist", label: "Artist", defaultOrder: .forward) {
                KeyPathComparator(\.artistName, order: $0)
            },
            SortOption(id: "album", label: "Album", defaultOrder: .forward) {
                KeyPathComparator(\.albumName, order: $0)
            },
            SortOption(id: "dateAdded", label: "Date Added", defaultOrder: .reverse) {
                KeyPathComparator(\.dateAdded, order: $0)
            },
            SortOption(id: "duration", label: "Duration", defaultOrder: .forward) {
                KeyPathComparator(\.durationMs, order: $0)
            },
            SortOption(id: "year", label: "Year", defaultOrder: .forward) {
                KeyPathComparator(\.year, order: $0)
            },
        ]
    }

    private var sortPill: some View {
        Menu {
            ForEach(sortOptions) { option in
                Button {
                    applySort(option)
                } label: {
                    if isCurrentField(option) {
                        Label(option.label,
                              systemImage: currentAscending ? "arrow.up" : "arrow.down")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("Sort: ").foregroundStyle(DesignSystem.Color.labelSecondary)
                    Text(currentSortText).foregroundStyle(DesignSystem.Color.accentText)
                        .fontWeight(.semibold)
                }
                .font(DesignSystem.Font.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: chevronSize, weight: .semibold))
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: pillHeight)
            .background(DesignSystem.Color.card, in: Capsule())
            .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: 0.5))
            .contentShape(Capsule()) // the whole pill opens the menu, not just its text
        }
        // `pillMenuStyle`, not `.borderlessButton`: the borderless style drew a bare "⌄ Sort:"
        // (it keeps one image + one text and drops the value, the capsule and the ring) and
        // never updated when the sort changed.
        .pillMenuStyle()
        .controlFocusRing(around: Capsule())
        .help("Sort")
        .accessibilityLabel("Sort")
        .accessibilityValue(currentSortText)
    }

    private var currentAscending: Bool {
        model.sortOrder.first?.order == .forward
    }

    /// The pill's current field label + direction arrow, derived from `model.sortOrder`.
    private var currentSortText: String {
        guard let current = model.sortOrder.first,
              let option = sortOptions.first(where: { $0.make(.forward).keyPath == current.keyPath })
        else { return sortOptions.first?.label ?? "Title" }
        return option.label + (current.order == .forward ? " ↑" : " ↓")
    }

    private func isCurrentField(_ option: SortOption) -> Bool {
        model.sortOrder.first?.keyPath == option.make(.forward).keyPath
    }

    /// Apply a sort field: toggle the direction if it's already the active field, else use the
    /// field's first-click default. Writes `model.sortOrder` (the pill/triangle source of truth)
    /// and re-reads via `applySortOrder` (the same path the old Table header-click used).
    private func applySort(_ option: SortOption) {
        let order: SortOrder
        if isCurrentField(option) {
            order = currentAscending ? .reverse : .forward
        } else {
            order = option.defaultOrder
        }
        let comparators = [option.make(order)]
        model.sortOrder = comparators
        model.applySortOrder(comparators)
        if let text = SongsAccessibility.sortAnnouncement(for: comparators) {
            AccessibilityNotification.Announcement(text).post()
        }
    }

    // MARK: Columns pill

    /// The teal Columns pill (`png/07`): opens the show/hide menu (+ Reset to Default). The list
    /// reveals the glass column-header row once the visible set differs from the default.
    private var columnsPill: some View {
        Menu {
            ForEach(toggleableColumns) { column in
                Toggle(column.label, isOn: visibilityBinding(for: column))
            }
            Divider()
            Button("Reset to Default") { columnConfig = .default }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: columnsSymbolSize, weight: .semibold))
                Text("Columns").font(DesignSystem.Font.caption)
            }
            .foregroundStyle(DesignSystem.Color.accentText)
            .padding(.horizontal, 12)
            .frame(height: pillHeight)
            .background(DesignSystem.Color.controlActiveFill, in: Capsule())
            .overlay(Capsule().strokeBorder(DesignSystem.Color.accent.opacity(0.30), lineWidth: 1))
            .contentShape(Capsule())
        }
        .pillMenuStyle() // keeps the teal capsule the borderless style discarded
        .controlFocusRing(around: Capsule())
        .help("Columns")
        .accessibilityLabel("Columns")
    }

    /// The non-frozen (toggleable) columns, in the config's current order.
    private var toggleableColumns: [SongColumn] {
        columnConfig.entries.map(\.column).filter { !$0.isFrozen }
    }

    private func visibilityBinding(for column: SongColumn) -> Binding<Bool> {
        Binding(
            get: { columnConfig.entries.first { $0.column == column }?.visible ?? false },
            set: { newValue in
                var config = columnConfig
                if let index = config.entries.firstIndex(where: { $0.column == column }) {
                    config.entries[index].visible = newValue
                    columnConfig = config
                }
            }
        )
    }
}
