#if DEBUG
    import EQEditKit

    // MARK: - Picture-sheet EQ graph states

    /// The EQ screen states the picture-sheet renderer draws (the `eq-*` worlds): a drag under way, the
    /// keyboard cursor holding focus, and a Tone row hovered. An offscreen window gets no pointer and
    /// never becomes key, so the graph and the Tone card seed these themselves on appear; the fixture
    /// runs the matching stroke on the view model.
    struct SheetEQGraph {
        var drag: EQGraphDrag?
        /// The keyboard cursor's band, with the graph holding focus; nil leaves it unfocused.
        var cursorBand: Int?
        /// The Tone row under the pointer: its region shades the graph, with the Tone readout.
        var toneRegion: EQToneRegion?
    }
#endif
