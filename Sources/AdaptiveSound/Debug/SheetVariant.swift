#if DEBUG
    import AppKit

    // MARK: - Picture-sheet variants

    /// One fixture world of the picture-sheet run. `standard` is the full matrix; the others are
    /// cheap extras — dark and light at the default window size only, on the tabs they change —
    /// so a reviewer is not blind to the keyboard ring or the empty states. File names carry the
    /// slug: `<tab>-<appearance>-<slug>-1000x720.png` (`standard` adds none).
    enum SheetVariant: CaseIterable {
        case standard
        /// Keyboard focus drawn: the queue (Now Playing) and the Songs list (Library) hold focus
        /// with a cursor row — the ring a keyboard user sees.
        case ring
        /// The same, with the Library RAIL holding focus — one window has one focused list.
        case ringRail
        /// An empty library (first run, no folders) and an empty queue.
        case empty

        /// The scene's default window size (`AdaptiveSound.body`'s `.defaultSize`).
        private static let defaultSize = NSSize(width: 1000, height: 720)

        /// The file-name slug, or nil for `standard`.
        var slug: String? {
            switch self {
            case .standard: nil
            case .ring: "ring"
            case .ringRail: "ring-rail"
            case .empty: "empty"
            }
        }

        /// The default window size and the hard minimum for `standard`; the default size only for
        /// the extras.
        var sizes: [NSSize] {
            switch self {
            case .standard:
                [Self.defaultSize,
                 NSSize(width: DesignSystem.ShellMetrics.windowMinWidth,
                        height: DesignSystem.ShellMetrics.windowMinHeight)]
            case .ring, .ringRail, .empty:
                [Self.defaultSize]
            }
        }

        /// The lists that take keyboard focus (and so draw the ring) in this world.
        var focusedLists: Set<SheetFocusedList> {
            switch self {
            case .standard, .empty: []
            case .ring: [.queue, .songs]
            case .ringRail: [.rail]
            }
        }

        /// The requested tabs this variant renders.
        func tabs(of request: SheetRequest) -> [TabSelection] {
            switch self {
            case .standard: request.tabs
            case .ring, .empty: request.tabs.filter { $0 == .nowPlaying || $0 == .library }
            case .ringRail: request.tabs.filter { $0 == .library }
            }
        }

        /// The requested appearances this variant renders.
        func appearances(of request: SheetRequest) -> [SheetAppearance] {
            switch self {
            case .standard: request.appearances
            case .ring, .ringRail, .empty: request.appearances.filter { $0 == .dark || $0 == .light }
            }
        }

        /// How many sheets this variant renders for `request` (a light appearance once per backdrop).
        func sheetCount(for request: SheetRequest) -> Int {
            let looks = appearances(of: request).reduce(0) { $0 + request.backdrops(for: $1).count }
            return tabs(of: request).count * looks * sizes.count
        }
    }
#endif
