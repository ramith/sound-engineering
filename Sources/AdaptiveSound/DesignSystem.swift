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
        /// Foreground drawn ON the accent (a play glyph on a teal disc, the active tab's and the
        /// pill's label). Appearance-independent like `accent` itself: the near-black teal
        /// #0C1413 — S10.8 PR B retired white, whose ≈ 2.5:1 on the teal failed AA. Gated by
        /// R4-TAB-01 (on the teal gloss) and R4-TINT-04 (on `accentFill`).
        static let onAccent = from(Palette.onAccent)
        /// S10.8 A2 accent ROLES — dark is exactly `accent` (no dark look changes); light is
        /// the deeper teal, because the bare `accent` fails contrast on the light window.
        /// `accentFill`: tints + fills (switches, the root tint, a glyph's fill layer), ≥ 3:1
        /// (R4-TINT-01). `accentForeground`: teal TEXT and GLYPHS, ≥ 4.5:1 (R4-TINT-02).
        /// Decorative strokes/washes keep `accent`; semgrep `ui-no-accent-as-text` holds it.
        ///
        /// `accentFill` is applied PER SITE (each switch), never as an inherited root `.tint`:
        /// on macOS 26 an inherited tint also re-styles NEUTRAL controls — automatic/bordered
        /// buttons turn teal-text-on-teal-wash, default-action buttons white-on-teal (≈ 2.5:1)
        /// — which would change shipped dark looks (probed with ImageRenderer, S10.8 A2).
        static let accentFill = from(Palette.accentFill)
        static let accentForeground = from(Palette.accentForeground)

        /// Alternates (swap into accent to change feel). #0A84FF.
        static let blue = from(Palette.blue)

        /// Surfaces (elevation stack) — dark = pre-S9-T (#1E1E1E window, pre-D10); light =
        /// first pass (gray base, white raised cards, darker inset). (`panel` had one
        /// consumer, the footer band background, which S10.8 PR G replaced with the
        /// styled-glass strata; the Kit `Palette.panel` token stays for the R4 audit.)
        /// `window` is a `ShapeStyle`, not a `Color`, while the light backdrop is switchable
        /// (S10.8 B2b — `WindowBaseStyle` reads the live pick from the environment).
        static let window = WindowBaseStyle()
        static let card = from(Palette.card)
        static let hairline = from(Palette.hairline)

        // Labels — secondary + tertiary lifted so BOTH clear WCAG AA (≥4.5:1) on the
        // stricter card/panel surface (not just the window), AND the secondary→tertiary
        // hierarchy stays perceptible (dark 0.92 > 0.55 > 0.48; light 0.90 > 0.62 > 0.55).
        // `labelDisabled` is WCAG-exempt (disabled text). That audit is now a PERMANENT
        // test: DesignTokenKitTests/ContrastAuditTests (R4).
        static let label = from(Palette.label)
        static let labelSecondary = from(Palette.labelSecondary)
        static let labelTertiary = from(Palette.labelTertiary)
        static let labelNav = from(Palette.labelNav)
        static let labelDisabled = from(Palette.labelDisabled)

        /// Status FILL/indicator color (non-text 3:1): `statusWarning` #FF9F0A vibrant orange
        /// (the Pure-fallback / interrupted dots). PR 6 (founder "split text vs fill"):
        /// TEXT/glyph sites use the darker AA-legible variants below. (The `statusError` red
        /// FILL lost its consumer when S10.8 PR E replaced the sample-peak CLIP bar with the
        /// true-peak amber meter — `statusErrorText` still carries error TEXT in the sidebar;
        /// the Kit `Palette.statusError` stays for the R4 audit.)
        static let statusWarning = from(Palette.statusWarning)
        /// Status TEXT/glyph variants (AA 4.5:1). Differ from the fill values only in LIGHT
        /// (on the deep dark base the vivid values already clear text AA).
        static let statusWarningText = from(Palette.statusWarningText)
        static let statusErrorText = from(Palette.statusErrorText)

        /// Row-fill tints for a selectable list row (queue / History): the now-playing row reads
        /// stronger than a merely-selected one. Accent-derived (the derivation is asserted by
        /// TOK-04); the selected tint deepens in light (S10.8 B2a).
        static let rowNowPlaying = from(Palette.rowNowPlaying)
        static let rowSelected = from(Palette.rowSelected)
        private static let labelTertiaryOnSelection = from(Palette.labelTertiaryOnSelection)

        /// The selected-row text rule (S10.8 B2a) — its ONE home: tertiary text on a row that is
        /// selected promotes to `labelTertiaryOnSelection` (secondary, AA on `rowSelected` in both
        /// appearances; dark since the founder's S10.8 B decision). Every selectable row's tertiary text reads through
        /// here: Songs rows, queue / playlist rows, the rail's playlist counts.
        static func labelTertiary(onSelectedRow isSelected: Bool) -> SwiftUI.Color {
            isSelected ? labelTertiaryOnSelection : labelTertiary
        }

        /// The small-control hover wash (S10.8 PR B): re-exports the badge fill — the same
        /// white-8%/dark-6% wash the realigned mock uses for hovered chrome controls, so
        /// hover states never mint a second near-identical value.
        static let hoverWash = from(Palette.badgeFill)

        // S10.8 PR C — queue-header control chips (realigned `png/03`); audited R4-CHIP-01.
        static let accentText = from(Palette.accentText)
        static let controlHover = from(Palette.controlHover)
        static let controlActiveFill = from(Palette.controlActiveFill)
        static let segmentSelected = from(Palette.segmentSelected)

        /// S10.8 A3 — the keyboard focus ring for the custom lists (Songs, queue, playlist
        /// detail, Library rail); ≥ 3:1 against row fills and cards, audited R4-FOCUS-01/02.
        /// Drawn only through `keyboardCursorRing(_:cornerRadius:)`.
        static let focusRing = from(Palette.focusRing)

        /// S10.8 PR D — the playing row (realigned `png/04`); audited R4-ROW-01.
        static let accentTitle = from(Palette.accentTitle)
        /// The mini equalizer's bar teal — the iconFill gradient's bright stop, re-exported
        /// (never a second #3FD0BA).
        static let accentBright = from(Palette.iconFillTop)

        /// S10.8 PR E — the true-peak hot VALUE text (realigned `png/05`); audited
        /// R4-METER-01. The hot FILL is `Gradient.meterHotFill` (which composes the Kit
        /// `Palette.meterHot` stop inline), so there is no solid `meterHot` re-export.
        static let meterHotText = from(Palette.meterHotText)
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
        /// Micro mono captions (8a slider end-labels) — Dynamic-Type-mapped, never a fixed 9.5.
        static let monoMicro = SwiftUI.Font.system(.caption2, design: .monospaced) // ~10 mono
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

        /// The realigned horizontal teal fill (S10.8 PR E — `asTealMeter`): leading → trailing,
        /// the iconFill mid stop into `meterFillTrail` (dark: bright, as shipped; light: the deep
        /// teal, so the value end clears 3:1 — S10.8 B2a). Shared by the loudness meters, the
        /// carved sliders, and the footer scrubber's playing state.
        static let meterFill = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [
                Color.from(Palette.iconFillMid),
                Color.from(Palette.meterFillTrail),
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )

        /// The true-peak meter's HOT fill (> −1 dBTP): teal running into the amber tail
        /// (realigned `png/05`). Stops: the bright teal → `meterHot`.
        static let meterHotFill = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [
                Color.from(Palette.iconFillTop),
                Color.from(Palette.meterHot),
            ]),
            startPoint: .leading,
            endPoint: .trailing
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
        static let sidebarIdeal: CGFloat = 234 // Twin Panels rail-card width (S10.8 PR-C; was 200)
        /// Horizontal content inset shared by the Twin Panels rail's nav rows, section headers,
        /// and inline folder rows so every item lines up on one edge (S10.8 PR-C).
        static let railRowInset: CGFloat = 12
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
        static let scrubberHitHeight: CGFloat = 20
        /// The scrubber's carved groove uses GlassDecor.carvedTrackHeight (5pt, shared with the
        /// inspector sliders); the thumb is a 14pt CarvedKnob (PR 6). No local track-height.
        static let thumbSize: CGFloat = 14
        /// Re-exported from the Kit so SlotFitTests can assert "88:88" fits headlessly (§7.1).
        static let timeLabelWidth: CGFloat = .init(SlotWidths.footerTimeLabel)
        /// Re-exported from the Kit (SLOT-03 asserts "Enhanced · 176.4 kHz" + dot fits).
        static let signalSlotWidth: CGFloat = .init(SlotWidths.footerSignalSlot)
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
        /// Hover-revealed grip opacity (S10.8 PR C — realigned: no handles at rest).
        static let gripHoverOpacity: Double = 0.45
        /// The row CARD's height (realigned `png/04`: 34pt) and the seam between two cards
        /// (2pt → the mock's 36pt row pitch, `png/00`).
        static let cardMinHeight: CGFloat = 34
        static let cardSeam: CGFloat = 2
    }

    // MARK: Loudness meter mapping (S10.8 PR E — the realigned meter rows, `png/05`)

    /// Display mapping for the inspector's loudness meter bars. Floors reproduce the mock's
    /// fractions exactly: −15.9 LUFS → 62%, −24.3 → 41% (floor −42); −0.8 dBTP → 93%,
    /// −3.2 → 74% (floor −12). The hot threshold equals the limiter's default −1 dBTP
    /// ceiling — the meter warns exactly where the safety layer clamps.
    enum Meters {
        static let lufsFloor: Double = -42
        static let truePeakFloorDb: Double = -12
        static let hotThresholdDbtp: Double = -1.0
        /// "The true-peak row has a live measurement" — the bridge's −120 dB sentinel, with
        /// margin. Independent of the LUFS `hasSignal` gate (a start-of-track transient
        /// must never wait 400 ms of gated blocks to warn).
        static let peakMeterFloorDb: Double = -110
        static let labelColumnWidth: CGFloat = 82
    }

    // MARK: Queue header metrics (S10.8 PR C — the realigned single-row header, `png/03`)

    /// Everything above the queue list collapses into ONE row of this height: title + count +
    /// icon chips + the Up Next/Recent capsule pair + the right-aligned compact filter pill.
    enum QueueHeader {
        static let height: CGFloat = 32
        static let iconButton: CGFloat = 28 // square chip, Radius.control corners
        static let iconSymbol: CGFloat = 12
        static let segmentHeight: CGFloat = 20 // + 2×segmentPadding = the 24pt pair
        static let segmentPadding: CGFloat = 2
        /// The filter pill: 190pt ideal (the mock), compressing to min so the header row
        /// survives the LAY-01 minimum queue width (90: leaves the count subtitle ~50pt at
        /// the 880pt window's worst case — the subtitle is the designated truncation victim).
        static let filterIdealWidth: CGFloat = 190
        static let filterMinWidth: CGFloat = 90
        static let filterHeight: CGFloat = 28
    }
}
