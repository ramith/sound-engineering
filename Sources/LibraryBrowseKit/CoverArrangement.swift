// MARK: - CoverArrangement (S10.8 D5 — what a browse tile's art shows)

/// What a browse tile's art shows for its cover keys — one rule for Albums, Artists and Genres:
/// four or more → a 2×2 mosaic of the first four (a genre: the covers of its biggest albums, the way
/// Music.app builds playlist art); one to three → the first cover, full size (a partial mosaic reads
/// as broken); none → the section's placeholder.
public enum CoverArrangement: Equatable, Sendable {
    /// Exactly `mosaicCount` keys, in reading order.
    case mosaic([String])
    case single(String)
    case placeholder

    /// The covers a mosaic shows — and so the most a tile ever needs.
    public static let mosaicCount = 4

    public init(keys: [String]) {
        if keys.count >= Self.mosaicCount {
            self = .mosaic(Array(keys.prefix(Self.mosaicCount)))
        } else if let first = keys.first {
            self = .single(first)
        } else {
            self = .placeholder
        }
    }
}
