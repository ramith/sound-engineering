// P5b N88 probe: the app's pipeline — an embedded cover → stored thumb at ≤512 (ArtworkCache) →
// a view request min(512, ceil(pt × scale)) decoded with ArtworkThumbnailStore's exact options.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()
func makeJPEG(_ w: Int, _ h: Int, _ path: String) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
}
func thumb(_ path: String, _ m: Int) -> CGImage {
    let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: m, kCGImageSourceCreateThumbnailWithTransform: true]
    return CGImageSourceCreateThumbnailAtIndex(s, 0, o as CFDictionary)!
}
var g = SystemRandomNumberGenerator(); var decodes = 0, stuck = 0
for _ in 0 ..< 400 {
    let (w, h) = (Int.random(in: 150 ... 560, using: &g), Int.random(in: 150 ... 560, using: &g))
    makeJPEG(w, h, dir + "/cover.jpg")
    let stored = thumb(dir + "/cover.jpg", 512)
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir + "/stored.jpg") as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, stored, nil); CGImageDestinationFinalize(d)
    for m in [56, 64, 80, 88, 96, 112, 128, 160, 176, 192, 240, 320, 336, 352, 400, 480] where m < max(stored.width, stored.height) {
        decodes += 1
        let t = thumb(dir + "/stored.jpg", m)
        if max(t.width, t.height) < m { stuck += 1 } // ThumbnailUpgrade.servesUpTo → Int.max
    }
}
print("decodes from a larger stored thumb: \(decodes); marked 'whole image' (served for every later size): \(stuck)")
