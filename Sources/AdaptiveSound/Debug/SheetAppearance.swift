#if DEBUG
    import AppKit
    import ObjectiveC

    // MARK: - Picture-sheet appearances

    /// One appearance column of the picture-sheet matrix (S10.8 plan §G): the offscreen window's AppKit
    /// appearance plus the SwiftUI accessibility environment a Mac in that mode would supply
    /// (`SheetFixture.root(for:)`). The raw value is the slug used in file names and on the command line.
    enum SheetAppearance: String, CaseIterable {
        case dark
        case light
        /// Increase Contrast — the high-contrast appearance AND `colorSchemeContrast == .increased`.
        case darkIC
        case lightIC
        /// Reduce Transparency — the base appearance with `accessibilityReduceTransparency` set, which is
        /// what the glass recipe reads (`DesignSystemGlass.swift`).
        case darkRT
        case lightRT

        var isDark: Bool {
            switch self {
            case .dark, .darkIC, .darkRT: true
            case .light, .lightIC, .lightRT: false
            }
        }

        var increasedContrast: Bool {
            self == .darkIC || self == .lightIC
        }

        var reduceTransparency: Bool {
            self == .darkRT || self == .lightRT
        }

        /// The window appearance, or `nil` when this macOS can't build it truthfully — the renderer then
        /// reports the sheets as failed rather than drawing a plain-contrast picture under an IC name.
        func makeAppearance() -> NSAppearance? {
            guard increasedContrast else { return NSAppearance(named: isDark ? .darkAqua : .aqua) }
            let appearance = Self.accessibilityAppearance(dark: isDark)
            let expected: NSAppearance.Name = isDark
                ? .accessibilityHighContrastDarkAqua
                : .accessibilityHighContrastAqua
            let candidates: [NSAppearance.Name] = [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]
            // The same match `DesignSystem.Color.dynamic` makes, so the IC token variants really resolve.
            return appearance?.bestMatch(from: candidates) == expected ? appearance : nil
        }

        /// The system's high-contrast appearance, as AppKit builds it when Increase Contrast is on.
        ///
        /// No public API returns one while the setting is off: `NSAppearance(named:)` silently drops the
        /// high-contrast names back to plain Aqua/Dark Aqua, and `init(appearanceNamed:bundle:)` gets the
        /// name right but resolves system colors (labels, separators, controls) from a generic light
        /// catalog. AppKit's own factory is the only source that is right on both counts (verified with
        /// `bestMatch` and resolved `labelColor`). Debug-only, looked up at runtime, and checked by the
        /// caller — a missing or changed factory fails the IC sheets loudly instead of faking them.
        private static func accessibilityAppearance(dark: Bool) -> NSAppearance? {
            typealias Factory = @convention(c) (AnyClass, Selector, Bool) -> NSAppearance?
            let selector = NSSelectorFromString(
                dark ? "_darkAquaAppearanceWithAccessibility:" : "_aquaAppearanceWithAccessibility:"
            )
            guard let method = class_getClassMethod(NSAppearance.self, selector) else { return nil }
            let factory = unsafeBitCast(method_getImplementation(method), to: Factory.self)
            return factory(NSAppearance.self, selector, true)
        }
    }
#endif
