#if DEBUG

    // MARK: - Picture-sheet keyboard focus

    /// A custom list the picture-sheet renderer can put keyboard focus in (`SheetVariant.ring` /
    /// `.ringRail` / `.gridStates`). An offscreen window never becomes key, so `.defaultFocus` never
    /// lands; the list takes focus itself on appear (`sheetFocusSeed(_:perform:)`), as a key press
    /// would make it.
    enum SheetFocusedList {
        /// The Now Playing queue — its cursor seeded one ↓ below the playing row.
        case queue
        /// The Songs list — its cursor on the fixture's selected (anchored) row.
        case songs
        /// The Library rail — its cursor on the selected category.
        case rail
        /// A browse grid — its cursor on the fixture's tile (`SheetGridStates.cursor`).
        case grid
        /// The EQ presets list — its cursor on the preset playing. (The EQ graph's cursor is seeded by
        /// `SheetEQGraph`.)
        case eqPresets
    }
#endif
