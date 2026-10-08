#if DEBUG
    import AppKit

    // MARK: - Picture-sheet variants

    /// One fixture world of the picture-sheet run. `standard` is the full matrix; the others are
    /// extras on the tabs they change, so a reviewer is not blind to the keyboard ring, the empty
    /// states or a browse grid. File names carry the raw value as a slug:
    /// `<tab>-<appearance>-<slug>-1000x720.png` (`standard` adds none).
    enum SheetVariant: String, CaseIterable {
        case standard = ""
        /// Keyboard focus drawn: the queue (Now Playing) and the Songs list (Library) hold focus
        /// with a cursor row — the ring a keyboard user sees.
        case ring
        /// The same, with the Library RAIL holding focus — one window has one focused list.
        case ringRail = "ring-rail"
        /// An empty library (first run, no folders) and an empty queue.
        case empty
        /// A browse grid (S10.8 D5) — the Library tab only, in every appearance at both sizes.
        case albums
        case artists
        case genres
        /// The Genres grid with one tile hovered and the keyboard ring on another (D5's states).
        case gridStates = "grid-states"

        /// The scene's default window size (`AdaptiveSound.body`'s `.defaultSize`).
        private static let defaultSize = NSSize(width: 1000, height: 720)

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
            case .standard, .ring, .ringRail, .empty: .songs
            }
        }

        /// A browse-grid world: its fixture shows its grid on the Library tab alone.
        private var isGrid: Bool {
            category != .songs
        }

        /// The default window size and the hard minimum for `standard` and the grids; the default
        /// size only for the other extras.
        var sizes: [NSSize] {
            switch self {
            case .standard, .albums, .artists, .genres:
                [Self.defaultSize,
                 NSSize(width: DesignSystem.ShellMetrics.windowMinWidth,
                        height: DesignSystem.ShellMetrics.windowMinHeight)]
            case .ring, .ringRail, .empty, .gridStates:
                [Self.defaultSize]
            }
        }

        /// The lists that take keyboard focus (and so draw the ring) in this world.
        var focusedLists: Set<SheetFocusedList> {
            switch self {
            case .standard, .empty, .albums, .artists, .genres: []
            case .ring: [.queue, .songs]
            case .ringRail: [.rail]
            case .gridStates: [.grid]
            }
        }

        /// The requested tabs this variant renders.
        func tabs(of request: SheetRequest) -> [TabSelection] {
            switch self {
            case .standard: request.tabs
            case .ring, .empty: request.tabs.filter { $0 == .nowPlaying || $0 == .library }
            case .ringRail, .albums, .artists, .genres, .gridStates: request.tabs.filter { $0 == .library }
            }
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
