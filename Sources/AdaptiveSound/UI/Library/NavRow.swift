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
struct NavRow<Trailing: View>: View {
    let icon: String
    let label: String
    let active: Bool
    /// The rail holds key focus and this is the row the arrow keys act on (A3).
    let isKeyboardCursor: Bool
    let trailing: Trailing

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 38
    @State private var hover = false

    init(icon: String, label: String, active: Bool = false, isKeyboardCursor: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.label = label
        self.active = active
        self.isKeyboardCursor = isKeyboardCursor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(DesignSystem.Font.body)
                .frame(width: 18)
                .accessibilityHidden(true) // decorative; the row's combined label carries the name
            Text(label)
                .font(DesignSystem.Font.body.weight(active ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            trailing
        }
        // Idle rows sit recessed (mock png/01, ~72% via the dedicated `labelNav` tier) so the
        // active teal row leads.
        .foregroundStyle(active ? DesignSystem.Color.accentText : DesignSystem.Color.labelNav)
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
        } else if hover {
            DesignSystem.Color.controlHover
        } else {
            .clear
        }
    }
}

/// Trailing-free convenience for the plain category rows.
extension NavRow where Trailing == EmptyView {
    init(icon: String, label: String, active: Bool = false, isKeyboardCursor: Bool = false) {
        self.init(icon: icon, label: label, active: active, isKeyboardCursor: isKeyboardCursor) {
            EmptyView()
        }
    }
}

// MARK: - Section header

/// A rail section header (`png/01`): a heavy, letter-spaced tertiary caption + a trailing
/// `accentText` "+" add button, optionally led by a glyph (Music Folders' folder icon). Shares
/// the rail row inset so the caption lines up with the nav rows below it.
struct NavSectionHeader: View {
    let title: String
    let icon: String?
    let addHelp: String
    let addDisabled: Bool
    let add: () -> Void

    init(title: String, icon: String? = nil, addHelp: String, addDisabled: Bool,
         add: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.addHelp = addHelp
        self.addDisabled = addDisabled
        self.add = add
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
            Button(action: add) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignSystem.Color.accentText)
            .disabled(addDisabled)
            .help(addHelp)
            .accessibilityLabel(addHelp)
        }
        .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
        .padding(.top, DesignSystem.Spacing.small)
        .padding(.bottom, 2)
    }
}
