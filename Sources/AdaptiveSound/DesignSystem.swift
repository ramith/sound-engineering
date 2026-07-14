import AppKit
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
        /// An appearance-reactive color (S9-T): `dark` is served under `.darkAqua`, `light`
        /// otherwise, via an `NSColor` dynamic provider — so surfaces/labels follow the
        /// system appearance with NO per-view `colorScheme` checks (D2: build light+dark,
        /// not dark-lock). `dark` values are the pre-S9-T look, unchanged; `light` values
        /// are a first pass to tune during the founder `make run` in Light Appearance.
        static func dynamic(light: SwiftUI.Color, dark: SwiftUI.Color) -> SwiftUI.Color {
            let lightNS = NSColor(light)
            let darkNS = NSColor(dark)
            return SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkNS : lightNS
            })
        }

        // Accent — appearance-independent (the teal reads on both light + dark).
        static let accent = SwiftUI.Color(red: 0.161, green: 0.714, blue: 0.643) // #29B6A4
        static let accentDeep = SwiftUI.Color(red: 0.078, green: 0.537, blue: 0.478) // #148979
        /// Foreground drawn ON the accent (e.g. a play glyph over the teal fill). Appearance-
        /// independent like `accent` itself — white reads on the teal in both light + dark.
        static let onAccent = SwiftUI.Color.white

        /// Alternates (swap into accent to change feel)
        static let blue = SwiftUI.Color(red: 0.039, green: 0.518, blue: 1.0) // #0A84FF

        /// Surfaces (elevation stack) — dark = pre-S9-T; light = first pass (gray base,
        /// white raised cards, darker inset).
        static let window = dynamic(light: SwiftUI.Color(white: 0.93),
                                    dark: SwiftUI.Color(red: 0.118, green: 0.118, blue: 0.118)) // #1E1E1E
        static let card = dynamic(light: SwiftUI.Color.white, dark: SwiftUI.Color.white.opacity(0.045))
        static let panel = dynamic(light: SwiftUI.Color.white, dark: SwiftUI.Color.white.opacity(0.06))
        static let hairline = dynamic(light: SwiftUI.Color.black.opacity(0.12),
                                      dark: SwiftUI.Color.white.opacity(0.08))

        // Labels — secondary + tertiary lifted so BOTH clear WCAG AA (≥4.5:1) on the
        // stricter card/panel surface (not just the window), AND the secondary→tertiary
        // hierarchy stays perceptible (dark 0.92 > 0.55 > 0.48; light 0.90 > 0.62 > 0.55).
        // `labelDisabled` is WCAG-exempt (disabled text). Light values still tune-in-make-run.
        static let label = dynamic(light: SwiftUI.Color.black.opacity(0.90), dark: SwiftUI.Color.white.opacity(0.92))
        static let labelSecondary = dynamic(light: SwiftUI.Color.black.opacity(0.62),
                                            dark: SwiftUI.Color.white.opacity(0.55))
        static let labelTertiary = dynamic(light: SwiftUI.Color.black.opacity(0.55),
                                           dark: SwiftUI.Color.white.opacity(0.48))
        static let labelDisabled = dynamic(light: SwiftUI.Color.black.opacity(0.28),
                                           dark: SwiftUI.Color.white.opacity(0.25))

        /// Status (NEW — warning had no semantic token). System-vibrant; read on both.
        static let statusWarning = SwiftUI.Color(red: 1.0, green: 0.623, blue: 0.039) // #FF9F0A

        /// Row-fill tints for a selectable list row (queue / History): the now-playing row reads
        /// stronger than a merely-selected one. Accent-derived, so appearance-independent like
        /// `accent`. (Formerly inline `accent.opacity(0.25 / 0.12)` literals at the row.)
        static let rowNowPlaying = accent.opacity(0.25)
        static let rowSelected = accent.opacity(0.12)
    }

    // MARK: Typography (semantic scale mapped to Dynamic Type text styles)

    ///
    /// Each rung maps to a `Font.TextStyle` (not a fixed `.system(size:)`) so ALL text built from
    /// these tokens scales with the macOS Accessibility → Display → Text size setting (A-M2). This
    /// is also what makes the `.dynamicTypeSize(.small ... .xxLarge)` clamps on the fixed-row-height
    /// surfaces (Songs table, footer) actually bound anything. The `// ~N` sizes are each style's
    /// macOS default at the standard content size — close to the previous fixed sizes, except `body`
    /// /`bodyMedium` shift 14 → 13 (macOS `.body`). `trackTitle`/`.headline` and `displayTitle`/
    /// `.title` carry the style's own weight. (Ad-hoc `Font.system(size:)` call sites elsewhere are a
    /// separate migration — some are SF Symbols / proportional glyph sizes, not text.)
    enum Font {
        static let displayTitle = SwiftUI.Font.system(.title, weight: .bold) // ~22
        static let sectionTitle = SwiftUI.Font.system(.title3, weight: .semibold) // ~15
        static let body = SwiftUI.Font.system(.body) // ~13
        static let bodyMedium = SwiftUI.Font.system(.body, weight: .medium) // ~13
        static let caption = SwiftUI.Font.system(.callout) // ~12
        /// Uppercase section labels — pair with `.tracking(0.5).textCase(.uppercase)`.
        static let micro = SwiftUI.Font.system(.subheadline, weight: .semibold) // ~11
        static let monoSmall = SwiftUI.Font.system(.subheadline, design: .monospaced) // ~11 mono
        /// Compact now-playing pairing (footer transport / mini-player): title over subtitle.
        static let trackTitle = SwiftUI.Font.system(.headline) // ~13 semibold
        static let trackSubtitle = SwiftUI.Font.system(.subheadline) // ~11
    }

    // MARK: Spacing (single rhythm scale)

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    // MARK: Corner radius

    enum Radius {
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

    // MARK: Shell metrics (app-owned window chrome bands)

    /// Fixed heights for the app-owned chrome (header / footer bands) and the window minimum.
    /// Reconciled to the shipping look in the layout plan (§5): chrome stays 60 (today's
    /// `ToolbarView`), window min bumps to 880×640 for the footer transport + two Now Playing
    /// panes. No traffic-light inset — the native titlebar carries the window buttons in their
    /// own strip, so the chrome shares the content's left margin.
    enum ShellMetrics {
        static let chromeHeight: CGFloat = 60
        static let footerHeight: CGFloat = 64
        static let windowMinWidth: CGFloat = 880
        static let windowMinHeight: CGFloat = 640
        static let hairline: CGFloat = 0.5
    }

    // MARK: Layout metrics (screen insets + pane / sidebar sizing)

    /// Screen-level layout metrics: content insets, the readable-width cap for form-like
    /// screens, and split-view sizing. Named `LayoutMetrics` (NOT `Layout`) to avoid
    /// colliding with the SwiftUI `Layout` protocol.
    enum LayoutMetrics {
        static let screenInsetH: CGFloat = 20
        static let screenInsetV: CGFloat = 16
        static let sectionGap: CGFloat = 20
        static let readableMaxWidth: CGFloat = 720
        static let sidebarIdeal: CGFloat = 200
    }

    // MARK: Visualizer surfaces (drawing-surface sizing)

    /// Sizing for drawing surfaces (EQ response graph, spectrum, channel rows). The Canvas
    /// draws to whatever size the slot gives it; these tokens size the slot — replacing the
    /// former magic pixel heights.
    enum Visualizer {
        static let responseGraphMinHeight: CGFloat = 220
        static let responseGraphIdealHeight: CGFloat = 360
        static let responseGraphMaxHeight: CGFloat = 460
    }

    // MARK: Artwork sizes

    /// Square artwork edge length for the list / footer thumbnail. (The album grid-cell and
    /// detail-hero sizes are literals at their own call sites; add a token here only when a
    /// second consumer needs the same value.)
    enum Artwork {
        static let thumb: CGFloat = 44
    }

    // MARK: Footer transport metrics (L3)

    /// Sizing for the persistent footer transport bar (`NowPlayingBar`). Keeps the four-region
    /// layout free of magic numbers; the band height itself stays `ShellMetrics.footerHeight`.
    enum Footer {
        static let hInset: CGFloat = 16 // matches the chrome header inset
        static let infoMinWidth: CGFloat = 174
        static let infoIdealWidth: CGFloat = 240
        static let artGap: CGFloat = 10
        static let controlSpacing: CGFloat = 18
        static let playButton: CGFloat = 34
        static let playSymbol: CGFloat = 14
        static let skipButton: CGFloat = 30 // hit target
        static let skipSymbol: CGFloat = 15
        static let scrubberTrackMinWidth: CGFloat = 120
        static let scrubberTrackHeight: CGFloat = 3
        static let scrubberHitHeight: CGFloat = 20
        static let thumbSize: CGFloat = 10
        static let timeLabelWidth: CGFloat = 46
        static let signalSlotWidth: CGFloat = 120
        static let regionGapInfoToControls: CGFloat = 20
        static let regionGap: CGFloat = 16 // controls→scrubber, scrubber→signal
        static let tooltipHalfWidth: CGFloat = 22 // half the drag tooltip width, for edge clamping
        static let tooltipYOffset: CGFloat = -20 // tooltip rises above the track while dragging
    }

    // MARK: Songs list metrics (S9.5)

    /// Sizing for the Songs table (S9.5), a peer of `Footer`/`LayoutMetrics`. Only the tokens
    /// THIS slice consumes are declared; artwork thumb / A–Z-rail widths are added in the slices
    /// that consume them (§10.8) so there are no unused tokens for periphery to flag.
    enum SongsList {
        static let rowHeight: CGFloat = 36 // uniform; dense but legible; aids virtualization
        static let headerHeight: CGFloat = 44 // SongsHeader band (count + filter field)
        static let searchFieldMinWidth: CGFloat = 180 // filter field, trailing in the header (§10.2)
        static let searchFieldIdealWidth: CGFloat = 240
        static let artwork: CGFloat = 28 // leading row thumbnail (§10.1; denser than the 44pt footer)
    }

    // MARK: Queue / playlist row metrics (S10.2)

    /// Sizing for the queue (Up Next) + History rows and the drag-reorder grip handle. The queue
    /// is a `ScrollView`/`LazyVStack` (a List row's `.dropDestination` never fires), so the row
    /// owns its own insets via these tokens rather than `List`'s `.listRow*`.
    enum QueueRow {
        static let durationWidth: CGFloat = 42 // trailing mm:ss column
        static let gripSymbol: CGFloat = 13 // drag-handle glyph point size
        static let gripHitWidth: CGFloat = 22 // grip hover/drag hit target
        static let gripHitHeight: CGFloat = 26
    }
}
