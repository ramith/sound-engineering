#if DEBUG

    // MARK: - Picture-sheet EQ graph states

    /// The EQ graph states the picture-sheet renderer draws (the `eq-*` worlds): a drag under way, and the
    /// keyboard cursor holding focus. An offscreen window gets no pointer and never becomes key, so the
    /// graph seeds these itself on appear; the fixture runs the matching stroke on the view model.
    struct SheetEQGraph {
        var drag: EQGraphDrag?
        /// The keyboard cursor's band, with the graph holding focus; nil leaves it unfocused.
        var cursorBand: Int?
    }
#endif
