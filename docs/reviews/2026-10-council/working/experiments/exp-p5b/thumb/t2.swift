import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers
func makeJPEG(w: Int, h: Int, path: String) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
}
func thumb(_ p: String, _ m: Int) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: m, kCGImageSourceCreateThumbnailWithTransform: true]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)!
}
// The app's pipeline: an embedded cover (any size) → stored thumb at ≤512 (ArtworkCache) → a view
// request min(512, ceil(pt × scale)). The stored thumb is the decode source.
let dir = "/private/tmp/claude-501/-Users-ramith-code-sound-engineering/737ceb91-aaa1-4ae6-bf56-9f296592de83/scratchpad/council/exp-p5b/thumb/"
let viewRequests = [56, 64, 80, 88, 96, 112, 128, 160, 176, 192, 240, 320, 336, 352, 400, 480]
var stuck = 0, decodes = 0, examples: [String] = []
var g = SystemRandomNumberGenerator()
for _ in 0..<400 {
    let w = Int.random(in: 150...560, using: &g), h = Int.random(in: 150...560, using: &g)
    makeJPEG(w: w, h: h, path: dir + "cover.jpg")
    let stored = thumb(dir + "cover.jpg", 512)
    let sp = dir + "stored.jpg"
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: sp) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, stored, nil); CGImageDestinationFinalize(dest)
    let storedLong = max(stored.width, stored.height)
    for m in viewRequests where m < storedLong {
        decodes += 1
        let t = thumb(sp, m)
        let side = max(t.width, t.height)
        // ThumbnailUpgrade.servesUpTo(decodedSide:requested:)
        let servesUpTo = side < m ? Int.max : side
        if servesUpTo == Int.max {
            stuck += 1
            if examples.count < 8 { examples.append("cover \(w)x\(h) → stored \(stored.width)x\(stored.height) → request \(m) → \(t.width)x\(t.height): servesUpTo = Int.max, so a later 480-px request is served this \(side)-px image") }
        }
    }
}
print("view decodes from a larger stored thumb: \(decodes); entries wrongly marked 'whole source' (serves any size): \(stuck)")
examples.forEach { print("  " + $0) }
