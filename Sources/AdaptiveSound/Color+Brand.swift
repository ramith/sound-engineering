import SwiftUI

// MARK: - Brand Colors

extension Color {
    /// Pink — gradient start, note head
    static let asPink = Color(red: 0.973, green: 0.004, blue: 0.569)

    /// Orange — gradient midpoint
    static let asOrange = Color(red: 1.0, green: 0.392, blue: 0.016)

    /// Gold — gradient end, wave tip
    static let asGold = Color(red: 0.992, green: 0.749, blue: 0.145)

    /// Dark surface background
    static let asDark = Color(red: 0.078, green: 0.047, blue: 0.039)

    /// Text and single-color mark
    static let asInk = Color(red: 0.129, green: 0.082, blue: 0.063)

    /// Light surface background
    static let asPaper = Color(red: 0.998, green: 0.984, blue: 0.973)
}

// MARK: - Brand Gradient

extension LinearGradient {
    /// Sunset gradient: pink → orange → gold (40° angle)
    static let sunset = LinearGradient(
        gradient: Gradient(colors: [.asPink, .asOrange, .asGold]),
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )
}

// MARK: - Typography

enum BrandFont {
    /// Space Grotesk 700 (primary headings)
    static let heading = Font.system(size: 24, weight: .bold)

    /// Space Grotesk 500 (secondary headings)
    static let subheading = Font.system(size: 18, weight: .semibold)

    /// Space Grotesk 400 (body text)
    static let body = Font.system(size: 14, weight: .regular)

    /// Space Grotesk 400 monospaced (labels, code-like text)
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
}
