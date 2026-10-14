import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

func makeJPEG(w: Int, h: Int, path: String) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
}
var bad: [(Int, Int, Int, Int)] = []
var total = 0
var g = SystemRandomNumberGenerator()
let requests = [56, 64, 100, 112, 128, 160, 200, 224, 256, 320, 336, 480, 512, 640]
for i in 0..<150 {
    let long = Int.random(in: 200...1600, using: &g)
    let short = Int.random(in: max(1, long / 3)...long, using: &g)
    let (w, h) = i % 2 == 0 ? (long, short) : (short, long)
    let p = "/private/tmp/claude-501/-Users-ramith-code-sound-engineering/737ceb91-aaa1-4ae6-bf56-9f296592de83/scratchpad/council/exp-p5b/thumb/img.jpg"
    makeJPEG(w: w, h: h, path: p)
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    for m in requests where m < long {
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: m, kCGImageSourceCreateThumbnailWithTransform: true]
        let t = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)!
        total += 1
        let side = max(t.width, t.height)
        if side < m { bad.append((w, h, m, side)) }
    }
}
print("decodes where source long side > request: \(total); decoded long side < request: \(bad.count)")
for b in bad.prefix(15) { print("  source \(b.0)x\(b.1) request \(b.2) → long side \(b.3)") }
