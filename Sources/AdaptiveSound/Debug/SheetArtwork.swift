#if DEBUG
    import AppKit

    // MARK: - Picture-sheet covers

    /// The picture-sheet fixture's cover art: per artwork key, a two-colour gradient, horizontal or
    /// vertical — the stress library's covers (`scripts/generate-stress-library.py`), drawn here from
    /// raw pixels and seeded by the key, so every render of a key is the same picture. Debug data,
    /// not UI colour: no token stands for "an album's cover".
    enum SheetArtwork {
        /// The covers' side, in pixels — larger than any tile's art at 2×.
        private static let side = 384

        /// One cover per key.
        static func images(for keys: [String]) -> [String: NSImage] {
            Dictionary(keys.compactMap { key in cover(for: key).map { (key, $0) } }) { first, _ in first }
        }

        private static func cover(for key: String) -> NSImage? {
            var random = SplitMix64(seed: fnv1a(key))
            let start = (0 ..< 3).map { _ in Double(random.next() % 256) }
            let end = (0 ..< 3).map { _ in Double(random.next() % 256) }
            let vertical = random.next() % 2 == 0
            var pixels = [UInt8](repeating: 255, count: side * side * 4)
            for row in 0 ..< side {
                for column in 0 ..< side {
                    let fraction = Double(vertical ? row : column) / Double(side - 1)
                    let offset = (row * side + column) * 4
                    for channel in 0 ..< 3 {
                        let value = start[channel] + (end[channel] - start[channel]) * fraction
                        pixels[offset + channel] = UInt8(value.rounded())
                    }
                }
            }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true,
                                      intent: .defaultIntent)
            else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: side, height: side))
        }

        /// FNV-1a over the key's UTF-8: a stable seed (Swift's `hashValue` changes every launch).
        private static func fnv1a(_ key: String) -> UInt64 {
            key.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
    }
#endif
