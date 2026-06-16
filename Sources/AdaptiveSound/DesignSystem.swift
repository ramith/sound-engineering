import SwiftUI

// MARK: - Design System (canonical visual tokens)

/// Single source of truth for visual design tokens — color, type, spacing, radius,
/// gradient. `Color+Brand.swift` (`Color.asXxx`) delegates here so there is one
/// canonical palette; new code should reference `DesignSystem.*` directly.
///
/// Introduced per docs/sprints/08-gui-design-review.md (the GUI review found 11
/// ad-hoc font sizes / 11 spacing values / mixed radii with no governing scale).
/// Existing call sites are migrated to these tokens incrementally (with visual
/// verification), so the legacy `asXxx` aliases remain valid in the meantime.
enum DesignSystem {
    // MARK: Color

    enum Color {
        // Accent
        static let accent = SwiftUI.Color(red: 0.161, green: 0.714, blue: 0.643) // #29B6A4
        static let accentDeep = SwiftUI.Color(red: 0.078, green: 0.537, blue: 0.478) // #148979
        static let accentSubtle = accent.opacity(0.16) // selected-row fill
        static let accentMid = accent.opacity(0.25) // now-playing-row fill

        // Alternates (swap into accent to change feel)
        static let blue = SwiftUI.Color(red: 0.039, green: 0.518, blue: 1.0) // #0A84FF
        static let graphite = SwiftUI.Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93

        // Surfaces (elevation stack)
        static let window = SwiftUI.Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
        static let inset = SwiftUI.Color.black.opacity(0.28)
        static let card = SwiftUI.Color.white.opacity(0.045)
        static let panel = SwiftUI.Color.white.opacity(0.06) // NEW — panel vs card elevation
        static let hairline = SwiftUI.Color.white.opacity(0.08)

        // Labels
        static let label = SwiftUI.Color.white.opacity(0.92)
        static let labelSecondary = SwiftUI.Color.white.opacity(0.50)
        static let labelTertiary = SwiftUI.Color.white.opacity(0.42)
        static let labelDisabled = SwiftUI.Color.white.opacity(0.25) // NEW

        // Status (NEW — warning/error had no semantic token)
        static let statusOK = SwiftUI.Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
        static let statusWarning = SwiftUI.Color(red: 1.0, green: 0.623, blue: 0.039) // #FF9F0A
        static let statusError = SwiftUI.Color(red: 1.0, green: 0.271, blue: 0.227) // #FF453A
    }

    // MARK: Typography (5-rung scale; replaces scattered Font.system(size:) calls)

    enum Font {
        static let displayTitle = SwiftUI.Font.system(size: 22, weight: .bold)
        static let sectionTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 14, weight: .regular)
        static let bodyMedium = SwiftUI.Font.system(size: 14, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular)
        /// Uppercase section labels — pair with `.tracking(0.5).textCase(.uppercase)`.
        static let micro = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let mono = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(size: 11, weight: .regular, design: .monospaced)
    }

    // MARK: Spacing (single rhythm scale)

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }

    // MARK: Corner radius

    enum Radius {
        static let chip: CGFloat = 4 // badges / tags
        static let control: CGFloat = 8 // buttons / pills / small cards
        static let container: CGFloat = 10 // canvas / large cards / panels
    }

    // MARK: Gradient

    enum Gradient {
        /// App-mark squircle / play-button fill (subtle teal).
        static let iconFill = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [
                SwiftUI.Color(red: 0.247, green: 0.816, blue: 0.729), // #3FD0BA
                SwiftUI.Color(red: 0.122, green: 0.659, blue: 0.576), // #1FA893
                Color.accentDeep,
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
