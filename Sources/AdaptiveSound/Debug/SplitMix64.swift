#if DEBUG

    // MARK: - SplitMix64

    /// A tiny seedable random generator (Steele, Lea & Flood's SplitMix64), so the picture-sheet
    /// fixture draws the same cover for a key on every run (`SheetArtwork`).
    struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }
#endif
