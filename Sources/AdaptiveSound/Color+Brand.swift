import SwiftUI

// MARK: - Brand Colors (native macOS theme)

// Pink/orange/gold "sunset" palette retired in favor of neutral system
// surfaces + a single restrained accent. Swap `accent`/`accentStrong`
// for .asTeal / .asGraphite below to change the feel.

extension Color {
    /// Primary accent — icon, selection, checkmark (teal)
    static let asAccent = Color(red: 0.161, green: 0.714, blue: 0.643) // #29B6A4
    static let asAccentDeep = Color(red: 0.078, green: 0.537, blue: 0.478) // #148979

    /// Alternate accents (swap into asAccent to change feel)
    static let asBlue = Color(red: 0.039, green: 0.518, blue: 1.0) // #0A84FF
    static let asGraphite = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93

    /// System green status dot
    static let asGreen = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158

    /// Neutral surfaces (no warm tint)
    static let asWindow = Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
    static let asInset = Color.black.opacity(0.28) // device-list well
    static let asCard = Color.white.opacity(0.045) // translucent card fill
    static let asHairline = Color.white.opacity(0.08) // 0.5px borders

    /// Labels (system semantics, dark mode)
    static let asLabel = Color.white.opacity(0.92)
    static let asLabelSecond = Color.white.opacity(0.50)
    static let asLabelTertiary = Color.white.opacity(0.42)
}

// MARK: - Selection

extension Color {
    /// Teal-tinted row background for the selected device
    static let asSelection = Color.asAccent.opacity(0.16)
}

// MARK: - Icon gradient (app mark squircle)

extension LinearGradient {
    /// Replaces `.sunset`. Subtle teal gradient for the icon tile.
    static let asIconFill = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.247, green: 0.816, blue: 0.729), // #3FD0BA
            Color(red: 0.122, green: 0.659, blue: 0.576), // #1FA893
            .asAccentDeep,
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography (unchanged — SF Pro / system)

enum BrandFont {
    static let heading = Font.system(size: 30, weight: .bold)
    static let subheading = Font.system(size: 18, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    /// Uppercase section headers (Engine Status / Output Device / Available Devices)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
}
