#if DEBUG

    // MARK: - Picture-sheet browse-tile states

    /// The browse-tile states the picture-sheet renderer draws (`SheetVariant.gridStates`): one tile
    /// hovered (its plate and Play) and one wearing the keyboard ring. An offscreen window gets no
    /// mouse and never becomes key, so the tile and the grid seed these themselves on appear.
    struct SheetGridStates {
        var hovered: LibraryBrowseModel.FacetRef?
        var cursor: LibraryBrowseModel.FacetRef?
    }
#endif
