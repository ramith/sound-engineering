// MARK: - ThumbnailUpgrade (S10.8 D fix round — the cover cache never stays soft)

/// The cover-thumbnail cache's size rule, UPGRADE-ONLY: an entry remembers the largest request it
/// serves; a bigger request re-decodes and replaces it, a smaller one is served from it, and a decode
/// never replaces a bigger entry. So a cover first decoded small (a Recently Played row at 56 px, a
/// mosaic quarter) can't leave a 160-pt grid tile showing it blurry for the whole session. Pure, so
/// the rule is tested without images.
public enum ThumbnailUpgrade {
    /// The largest request a decode serves: the side it came out at — or unbounded when it came out
    /// smaller than requested, because then it is the whole source image and no bigger decode exists.
    public static func servesUpTo(decodedSide: Int, requested maxPixel: Int) -> Int {
        decodedSide < maxPixel ? Int.max : decodedSide
    }

    /// An entry serving up to `servesUpTo` is good enough for a `maxPixel` request when it is within
    /// 10% of it: a re-decode for a few pixels shows no difference and would cost a decode per scroll.
    public static func serves(_ servesUpTo: Int, request maxPixel: Int) -> Bool {
        Double(servesUpTo) >= 0.9 * Double(maxPixel)
    }

    /// A new decode serving up to `decoded` replaces the cached entry (nil = none) only when bigger.
    public static func replaces(cached: Int?, with decoded: Int) -> Bool {
        cached.map { decoded > $0 } ?? true
    }
}
