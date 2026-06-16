import SwiftUI

// MARK: - Brand Colors (compatibility aliases → DesignSystem)

// These `asXxx` tokens are the legacy names used across the existing views. They
// now delegate to `DesignSystem.Color` (the canonical palette, see DesignSystem.swift)
// so there is a single source of truth. New code should reference `DesignSystem.*`
// directly; these aliases are migrated out incrementally with visual verification.

extension Color {
    /// Primary accent — icon, selection, checkmark (teal)
    static let asAccent = DesignSystem.Color.accent
    static let asAccentDeep = DesignSystem.Color.accentDeep

    /// Alternate accents (swap into asAccent to change feel)
    static let asBlue = DesignSystem.Color.blue
    static let asGraphite = DesignSystem.Color.graphite

    /// System green status dot
    static let asGreen = DesignSystem.Color.statusOK

    /// Neutral surfaces (no warm tint)
    static let asWindow = DesignSystem.Color.window
    static let asInset = DesignSystem.Color.inset
    static let asCard = DesignSystem.Color.card
    static let asHairline = DesignSystem.Color.hairline

    /// Labels (system semantics, dark mode)
    static let asLabel = DesignSystem.Color.label
    static let asLabelSecond = DesignSystem.Color.labelSecondary
    static let asLabelTertiary = DesignSystem.Color.labelTertiary

    /// Teal-tinted row background for the selected device
    static let asSelection = DesignSystem.Color.accentSubtle
}

// MARK: - Icon gradient (app mark squircle)

extension LinearGradient {
    static let asIconFill = DesignSystem.Gradient.iconFill
}
