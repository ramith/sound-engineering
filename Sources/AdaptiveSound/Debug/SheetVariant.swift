#if DEBUG
    import AppKit

    // MARK: - Picture-sheet variants

    /// One fixture world of the picture-sheet run. `standard` is the full matrix; the others are
    /// extras on the tabs they change, so a reviewer is not blind to the keyboard ring, the empty
    /// states, a browse grid or an EQ state. File names carry the raw value as a slug:
    /// `<tab>-<appearance>-<slug>-1000x720.png` (`standard` adds none).
    enum SheetVariant: String, CaseIterable {
        case standard = ""
        /// Keyboard focus drawn: the queue (Now Playing), the Songs list (Library) and the EQ graph
        /// hold focus with their cursor — the ring a keyboard user sees. On the EQ graph the cursor
        /// sits on a point the Tone layer holds at the ceiling, so its readout ends "limited".
        case ring
        /// The same, with the RAIL holding focus — the Library's, and the EQ's presets list: one
        /// window has one focused list.
        case ringRail = "ring-rail"
        /// An empty library (first run, no folders) and an empty queue.
        case empty
        /// A browse grid (S10.8 D5) — the Library tab only, in every appearance at both sizes.
        case albums
        case artists
        case genres
        /// The Genres grid with one tile hovered and the keyboard ring on another (D5's states).
        case gridStates = "grid-states"
        /// The EQ worlds (Sprint EQ, EQ3) — the EQ tab only: a drag under way (the readout, the
        /// neighbours following); a stroke past the +12 dB ceiling; 12 My Presets at 880×640 (the
        /// Equalizer card scrolls); Off; Compare held; Pure Mode; and the engine not running.
        case eqDrag = "drag"
        case eqCeiling = "ceiling"
        case eqMany = "many"
        case eqOff = "off"
        case eqCompare = "compare"
        case eqPure = "pure"
        case eqEngine = "engine"
        /// The Tone worlds (EQ3t): a Tone row hovered on a Flat base, so the curve is the Tone alone —
        /// its region shaded and the readout in the strip; and the Tone card folded to its one line at
        /// 880×640, where every preset then fits without a scroll.
        case eqTone = "tone"
        case eqFolded = "folded"
        /// The My Presets and pin worlds (EQ4): the output pinned ("Used on MacBook Pro Speakers"
        /// under the preset's name), and the app's themed dialogs open — Save, Rename on a My Preset,
        /// and its Delete confirmation (drawn in the window: a real sheet is a window of its own, out of
        /// an offscreen render's reach).
        case eqPinned = "pinned"
        case eqSave = "save"
        case eqRename = "rename"
        case eqDelete = "delete"

        /// The scene's default window size (`AdaptiveSound.body`'s `.defaultSize`).
        private static let defaultSize = NSSize(width: 1000, height: 720)
        /// The hard window minimum.
        private static let minimumSize = NSSize(width: DesignSystem.ShellMetrics.windowMinWidth,
                                                height: DesignSystem.ShellMetrics.windowMinHeight)

        /// The file-name slug, or nil for `standard`.
        var slug: String? {
            self == .standard ? nil : rawValue
        }

        /// The Library category the world opens on.
        var category: LibraryCategory {
            switch self {
            case .albums: .albums
            case .artists: .artists
            case .genres, .gridStates: .genres
            default: .songs
            }
        }

        /// A browse-grid world: its fixture shows its grid on the Library tab alone.
        private var isGrid: Bool {
            category != .songs
        }

        /// The default window size and the hard minimum for `standard` and the grids; the minimum
        /// alone for the long presets list (where the card scrolls) and the folded Tone card; the
        /// default size for the rest.
        var sizes: [NSSize] {
            switch self {
            case .standard, .albums, .artists, .genres: [Self.defaultSize, Self.minimumSize]
            case .eqMany, .eqFolded: [Self.minimumSize]
            default: [Self.defaultSize]
            }
        }

        /// The lists that take keyboard focus (and so draw the ring) in this world. (The EQ graph's
        /// cursor is `SheetFixture.eqGraphSeed`.)
        var focusedLists: Set<SheetFocusedList> {
            switch self {
            case .ring: [.queue, .songs]
            case .ringRail: [.rail, .eqPresets]
            case .gridStates: [.grid]
            default: []
            }
        }

        /// The requested tabs this variant renders.
        func tabs(of request: SheetRequest) -> [TabSelection] {
            let wanted: Set<TabSelection>? = switch self {
            case .standard: nil
            case .ring: [.nowPlaying, .library, .eq]
            case .empty: [.nowPlaying, .library]
            case .ringRail: [.library, .eq]
            case .albums, .artists, .genres, .gridStates: [.library]
            case .eqDrag, .eqCeiling, .eqMany, .eqOff, .eqCompare, .eqPure, .eqEngine, .eqTone, .eqFolded,
                 .eqPinned, .eqSave, .eqRename, .eqDelete: [.eq]
            }
            return request.tabs.filter { wanted?.contains($0) ?? true }
        }

        /// The requested appearances this variant renders: all of them for `standard` and the grids,
        /// dark and light for the other extras.
        func appearances(of request: SheetRequest) -> [SheetAppearance] {
            self == .standard || (isGrid && self != .gridStates)
                ? request.appearances
                : request.appearances.filter { $0 == .dark || $0 == .light }
        }

        /// How many sheets this variant renders for `request`.
        func sheetCount(for request: SheetRequest) -> Int {
            tabs(of: request).count * appearances(of: request).count * sizes.count
        }
    }
#endif
