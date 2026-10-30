import SwiftUI

// MARK: - Library nav-rail components (S10.8 Library PR-C — `png/01`)

/// One row in the Twin Panels navigation rail: an SF-symbol + label with the realigned selection
/// treatment. Idle = the primary label color on a transparent row (hover reveals the
/// `controlHover` wash); active = the `rowSelected` tint + a hairline accent ring + the bright
/// `accentText` label (semibold). Optional trailing content (a playlist count, a folder remove
/// control) is supplied by the caller and keeps its OWN color/behaviour, so it isn't recolored by
/// the row's active state.
///
/// Visual only: the caller wraps it in the Button / gesture / drop machinery, owns the selection
/// binding, and attaches the row's accessibility (element + `.isSelected`). The row height scales
/// with Dynamic Type (`@ScaledMetric`, matching HeroBand/FormatBadge) so the `.body` label never
/// clips at large text sizes; the icon–label gap and inset match the mock.
///
/// The leading mark is the Library's SF symbol (`NavRowSymbol`) by default; the EQ rail passes its
/// preset's curve glyph and a denser row height (Sprint EQ, EQ3) — one row, two rails.
struct NavRow<Leading: View, Trailing: View>: View {
    let label: String
    let active: Bool
    /// The rail holds key focus and this is the row the arrow keys act on (A3).
    let isKeyboardCursor: Bool
    /// Where a label too long for the row gives way: its tail (the Library rail), or its middle for
    /// names told apart by their endings (the EQ's My Presets).
    let truncation: Text.TruncationMode
    let leading: Leading
    let trailing: Trailing

    /// Scales with the text size, relative to `.body` (set in `init`).
    @ScaledMetric private var rowHeight: CGFloat
    @State private var hover = false
    /// A disabled row (the EQ's presets while Pure plays) never washes under the pointer.
    @Environment(\.isEnabled) private var isEnabled

    /// A row `rowHeight` tall at the default text size (the Library rail's 38 unless given).
    init(label: String, active: Bool = false, isKeyboardCursor: Bool = false, rowHeight: CGFloat = 38,
         truncation: Text.TruncationMode = .tail,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.active = active
        self.isKeyboardCursor = isKeyboardCursor
        self.truncation = truncation
        self.leading = leading()
        self.trailing = trailing()
        _rowHeight = ScaledMetric(wrappedValue: rowHeight, relativeTo: .body)
    }

    var body: some View {
        HStack(spacing: 11) {
            leading
                .accessibilityHidden(true) // decorative; the row's combined label carries the name
            Text(label)
                .font(DesignSystem.Font.body.weight(active ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(truncation)
            Spacer(minLength: 0)
            trailing
        }
        // Idle rows sit recessed (mock png/01, ~72% via the dedicated `labelNav` tier) so the
        // active teal row leads. Disabled, light draws the row's own look (tertiary); dark dims it.
        .controlLabelStyle(active ? DesignSystem.Color.accentText : DesignSystem.Color.labelNav)
        .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
        .frame(height: rowHeight)
        .background(rowFill, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.container,
                                                  style: .continuous))
        .overlay {
            if active {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.container, style: .continuous)
                    .strokeBorder(DesignSystem.Color.accent.opacity(0.30), lineWidth: 1)
            }
        }
        .keyboardCursorRing(isKeyboardCursor, cornerRadius: DesignSystem.Radius.container)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private var rowFill: Color {
        if active {
            DesignSystem.Color.rowSelected
        } else if hover, isEnabled {
            DesignSystem.Color.controlHover
        } else {
            .clear
        }
    }
}

/// The Library rail's rows: an SF symbol leading.
extension NavRow where Leading == NavRowSymbol {
    init(icon: String, label: String, active: Bool = false, isKeyboardCursor: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(label: label, active: active, isKeyboardCursor: isKeyboardCursor) {
            NavRowSymbol(name: icon)
        } trailing: {
            trailing()
        }
    }
}

/// Trailing-free convenience for the plain category rows.
extension NavRow where Leading == NavRowSymbol, Trailing == EmptyView {
    init(icon: String, label: String, active: Bool = false, isKeyboardCursor: Bool = false) {
        self.init(icon: icon, label: label, active: active, isKeyboardCursor: isKeyboardCursor) {
            EmptyView()
        }
    }
}

// MARK: - Section header

/// A rail section header (`png/01`): a heavy, letter-spaced tertiary caption + a trailing
/// `accentText` "+" add button, optionally led by a glyph (Music Folders' folder icon). Shares
/// the rail row inset so the caption lines up with the nav rows below it. A section with nothing to
/// add (the EQ's built-in Presets) has no "+".
struct NavSectionHeader: View {
    /// The "+" button: its help (also its VoiceOver label), whether it is disabled, and its action.
    private struct AddButton {
        let help: String
        let disabled: Bool
        let action: () -> Void
    }

    let title: String
    let icon: String?
    private let addButton: AddButton?

    init(title: String, icon: String? = nil, addHelp: String, addDisabled: Bool,
         add: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        addButton = AddButton(help: addHelp, disabled: addDisabled, action: add)
    }

    /// A header with no "+".
    init(title: String) {
        self.title = title
        icon = nil
        addButton = nil
    }

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(DesignSystem.Font.micro)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(DesignSystem.Font.micro)
                .fontWeight(.heavy)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
            Spacer(minLength: 0)
            if let addButton {
                Button(action: addButton.action) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignSystem.Color.accentText)
                .disabled(addButton.disabled)
                .help(addButton.help)
                .accessibilityLabel(addButton.help)
            }
        }
        .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
        .padding(.top, DesignSystem.Spacing.small)
        .padding(.bottom, 2)
    }
}
