import AppKit
import DesignTokenKit
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
        /// not dark-lock). S10.7 extends the candidate set with the two high-contrast
        /// appearance names, so a token can opt into Increase-Contrast variants (they
        /// default to the base values — existing call sites are unchanged). STRUCTURAL
        /// increase-contrast responses (thicker hairlines/borders) belong to the
        /// `.glassPanel` modifier, not to color tokens.
        static func dynamic(light: SwiftUI.Color, dark: SwiftUI.Color,
                            lightHighContrast: SwiftUI.Color? = nil,
                            darkHighContrast: SwiftUI.Color? = nil) -> SwiftUI.Color {
            let lightNS = NSColor(light)
            let darkNS = NSColor(dark)
            let lightHCNS = NSColor(lightHighContrast ?? light)
            let darkHCNS = NSColor(darkHighContrast ?? dark)
            return SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ]) {
                case .accessibilityHighContrastDarkAqua: darkHCNS
                case .accessibilityHighContrastAqua: lightHCNS
                case .darkAqua: darkNS
                default: lightNS
                }
            })
        }

        // S10.7 single-source invariant (design §3.2): every VALUE below lives in
        // `DesignTokenKit.Palette` (plain RGBA data — headlessly contrast-audited and
        // invariant-tested); this enum keeps the API and re-exports via `from(_:)`
        // (DesignSystemGlass.swift). No RGBA literal may exist on this side — the former
        // inline literals moved to the Kit byte-identically (PR 1a, zero visual change).

        // Accent — appearance-independent (the teal reads on both light + dark). #29B6A4/#148979.
        static let accent = from(Palette.accent)
        static let accentDeep = from(Palette.accentDeep)
        /// Foreground drawn ON the accent (e.g. a play glyph over the teal fill). Appearance-
        /// independent like `accent` itself — white reads on the teal in both light + dark.
        static let onAccent = from(Palette.onAccent)

        /// Alternates (swap into accent to change feel). #0A84FF.
        static let blue = from(Palette.blue)

        /// Surfaces (elevation stack) — dark = pre-S9-T (#1E1E1E window, pre-D10); light =
        /// first pass (gray base, white raised cards, darker inset).
        static let window = from(Palette.window)
        static let card = from(Palette.card)
        static let panel = from(Palette.panel)
        static let hairline = from(Palette.hairline)

        // Labels — secondary + tertiary lifted so BOTH clear WCAG AA (≥4.5:1) on the
        // stricter card/panel surface (not just the window), AND the secondary→tertiary
        // hierarchy stays perceptible (dark 0.92 > 0.55 > 0.48; light 0.90 > 0.62 > 0.55).
        // `labelDisabled` is WCAG-exempt (disabled text). That audit is now a PERMANENT
        // test: DesignTokenKitTests/ContrastAuditTests (R4).
        static let label = from(Palette.label)
        static let labelSecondary = from(Palette.labelSecondary)
        static let labelTertiary = from(Palette.labelTertiary)
        static let labelDisabled = from(Palette.labelDisabled)

        /// Status. `statusWarning` #FF9F0A (system-vibrant orange). `statusError` is NEW in
        /// S10.7 (PR 1a): the clipping/over-level red the loudness meters previously
        /// hand-painted as `Color.red` — the macOS-26 palette-red values (#FF383C/#FF4245),
        /// so the swap is pixel-invisible (its AA shortfalls are pre-existing; PR-6 restyle).
        static let statusWarning = from(Palette.statusWarning)
        static let statusError = from(Palette.statusError)

        /// Row-fill tints for a selectable list row (queue / History): the now-playing row reads
        /// stronger than a merely-selected one. Accent-derived (the derivation is asserted by
        /// TOK-04), so appearance-independent like `accent`.
        static let rowNowPlaying = from(Palette.rowNowPlaying)
        static let rowSelected = from(Palette.rowSelected)
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
        /// The Now Playing hero title (8a: 28/800). Dynamic-Type-mapped `.largeTitle`
        /// (~26pt macOS default) at heavy weight — a fixed 28pt would break text scaling
        /// and is banned (S10.7 §3.2). Pair with `.heroTitle()` for the dark-only halo.
        static let heroTitle = SwiftUI.Font.system(.largeTitle, weight: .heavy)
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
        /// App-mark squircle / play-button fill (subtle teal). Stops from the Kit palette
        /// (#3FD0BA → #1FA893 → accentDeep) — no RGBA literals on the app side (§3.2).
        static let iconFill = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [
                Color.from(Palette.iconFillTop),
                Color.from(Palette.iconFillMid),
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
    /// Band/window metrics FORWARD the Kit's `NowPlayingLayout` values (single-source
    /// invariant): the §7.1 layout-arithmetic tests derive the min-window budget from the
    /// Kit, so the shell must lay out from the same numbers — a local copy here would let
    /// the tests keep passing against stale values.
    enum ShellMetrics {
        static let chromeHeight = CGFloat(NowPlayingLayout.chromeHeight)
        static let footerHeight = CGFloat(NowPlayingLayout.footerHeight)
        static let windowMinWidth = CGFloat(NowPlayingLayout.windowMinWidth)
        static let windowMinHeight = CGFloat(NowPlayingLayout.windowMinHeight)
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
        /// Re-exported from the Kit so SlotFitTests can assert "88:88" fits headlessly (§7.1).
        static let timeLabelWidth: CGFloat = .init(SlotWidths.footerTimeLabel)
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
