@testable import DesignTokenKit
import Foundation
import Testing

// P5b council panel — adversarial checks of the design-token math (uncommitted, panel worktree only).
// Every expected value here comes from the SPEC (WCAG 2.2, W3C Compositing Level 1), not the Kit.

@Suite("P5b tokens — WCAG / compositing / glow audit holes / sampled glow")
struct P5bTokenBreakTests {
    // MARK: Independent oracles (WCAG 2.2 §relative-luminance, 0.04045 threshold)

    static func lin2022(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func lum2022(_ c: RGBAColor) -> Double {
        0.2126 * lin2022(c.red) + 0.7152 * lin2022(c.green) + 0.0722 * lin2022(c.blue)
    }

    static func hex(_ v: Int) -> RGBAColor {
        RGBAColor(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    @Test("N116 known-value vectors (WCAG / WebAIM published ratios)")
    func knownVectors() {
        // Black / white = 21:1 exactly (WCAG definition: (1 + 0.05) / (0 + 0.05)).
        #expect(abs(RGBAColor.contrastRatio(.gray(0), .gray(1)) - 21) < 1e-12)
        #expect(RGBAColor.contrastRatio(.gray(1), .gray(1)) == 1)
        // #767676 on white = 4.54:1 (the smallest gray that passes AA), #777777 = 4.48:1.
        let r767676 = RGBAColor.contrastRatio(Self.hex(0x767676), .gray(1))
        let r777777 = RGBAColor.contrastRatio(Self.hex(0x777777), .gray(1))
        #expect((r767676 * 100).rounded() / 100 == 4.54, "\(r767676)")
        #expect((r777777 * 100).rounded() / 100 == 4.48, "\(r777777)")
        // Pure primaries' luminance = the Rec.709 weights.
        #expect(abs(Self.hex(0xFF0000).relativeLuminance - 0.2126) < 1e-12)
        #expect(abs(Self.hex(0x00FF00).relativeLuminance - 0.7152) < 1e-12)
        #expect(abs(Self.hex(0x0000FF).relativeLuminance - 0.0722) < 1e-12)
    }

    @Test("N116 the 0.03928 (WCAG 2.0/2.1) vs 0.04045 (WCAG 2.2 / IEC 61966-2-1) threshold: worst difference")
    func thresholdDifference() {
        var worst = 0.0
        var worstRatio = 0.0
        for step in 0 ... 255 {
            let c = Double(step) / 255
            worst = max(worst, abs(RGBAColor.linearChannel(c) - Self.lin2022(c)))
        }
        // Over every 8-bit gray pair, the contrast ratio under both thresholds.
        for a in 0 ... 255 {
            for b in 0 ... 255 {
                let ca = RGBAColor.gray(Double(a) / 255), cb = RGBAColor.gray(Double(b) / 255)
                let kit = RGBAColor.contrastRatio(ca, cb)
                let la = Self.lum2022(ca), lb = Self.lum2022(cb)
                let spec = (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
                worstRatio = max(worstRatio, abs(kit - spec))
            }
        }
        print("P5b N116: worst |linear| diff over 8-bit = \(worst); worst |ratio| diff over all gray pairs = \(worstRatio)")
        // 8-bit values never fall between the thresholds except 10/255 = 0.0392...: tiny.
        #expect(worst < 1e-6)
        #expect(worstRatio < 1e-4)
    }

    @Test("N116 linear/encoded round trip and monotonicity across the threshold")
    func roundTripMonotone() {
        var previous = -1.0
        var worstRoundTrip = 0.0
        for step in 0 ... 100_000 {
            let c = Double(step) / 100_000
            let l = RGBAColor.linearChannel(c)
            #expect(l >= previous, "non-monotone at \(c)")
            previous = l
            worstRoundTrip = max(worstRoundTrip, abs(RGBAColor.encodedChannel(l) - c))
        }
        print("P5b N116: worst encoded(linear(c)) - c = \(worstRoundTrip)")
        #expect(worstRoundTrip < 1e-6)
    }

    // MARK: N115 compositing (W3C Compositing and Blending Level 1 §5.1, straight alpha)

    @Test("N115 source-over vs the W3C premultiplied formula, random colors, incl. translucent backdrops")
    func sourceOverOracle() {
        var rng = SplitMix(seed: 115)
        for _ in 0 ..< 20000 {
            let s = RGBAColor(red: rng.unit(), green: rng.unit(), blue: rng.unit(), alpha: rng.unit())
            let b = RGBAColor(red: rng.unit(), green: rng.unit(), blue: rng.unit(), alpha: rng.unit())
            // premultiplied: co = cs·αs + cb·αb·(1 − αs); αo = αs + αb·(1 − αs); Co = co / αo
            let ao = s.alpha + b.alpha * (1 - s.alpha)
            let out = s.over(b)
            #expect(abs(out.alpha - ao) < 1e-12)
            if ao > 1e-9 {
                let co = (s.red * s.alpha + b.red * b.alpha * (1 - s.alpha)) / ao
                #expect(abs(out.red - co) < 1e-9)
            }
            // Associativity (a over (b over c)) == ((a over b) over c) — a property of source-over.
            let c = RGBAColor(red: rng.unit(), green: rng.unit(), blue: rng.unit(), alpha: 1)
            let left = s.over(b.over(c)), right = s.over(b).over(c)
            #expect(abs(left.red - right.red) < 1e-9 && abs(left.alpha - right.alpha) < 1e-9)
        }
        // Degenerate: both fully transparent → transparent black, no NaN.
        let z = RGBAColor.gray(0.5, alpha: 0).over(.gray(0.7, alpha: 0))
        #expect(z.alpha == 0 && !z.red.isNaN)
    }

    // MARK: N119/N116 — can the R4 grid miss the worst point of the glow field?

    /// The audit's own sampled minimum vs a dense sampling of the same continuous field.
    private static func minRatio(points: [(x: Double, y: Double)], geometry: (width: Double, height: Double),
                                 glows: [GlowFieldSpec.Glow], appearance: TokenAppearance,
                                 domain: (Double, Double) -> Bool = { _, _ in true },
                                 surface: (RGBAColor) -> RGBAColor = { $0 },
                                 label: AppearancePair) -> (ratio: Double, x: Double, y: Double) {
        var best = (ratio: Double.infinity, x: 0.0, y: 0.0)
        for point in points where domain(point.x, point.y) {
            let backdrop = GlowFieldSpec.compositeBackdrop(unitX: point.x, unitY: point.y,
                                                           containerWidth: geometry.width,
                                                           containerHeight: geometry.height,
                                                           appearance: appearance, glows: glows)
            let ratio = ContrastAuditTests.ratio(label: label, on: surface(backdrop), appearance)
            if ratio < best.ratio {
                best = (ratio, point.x, point.y)
            }
        }
        return best
    }

    private static func densePoints(_ columns: Int, _ rows: Int) -> [(x: Double, y: Double)] {
        (0 ... rows).flatMap { row in (0 ... columns).map { (Double($0) / Double(columns), Double(row) / Double(rows)) } }
    }

    @Test("N116/N119 audit grid vs dense field: R4-GLOW-01/02/04 and R4-GLOW-APP-01/02 worst points")
    func auditGridVsDense() {
        let dense = Self.densePoints(560, 400) + GlowFieldSpec.glows.map { ($0.unitCenterX, $0.unitCenterY) }
            + GlowFieldSpec.appGlows.map { ($0.unitCenterX, $0.unitCenterY) }
        let grid = ContrastAuditTests.gridPoints()
        for geometry in ContrastAuditTests.glowGeometries {
            let outsideCore: (Double, Double) -> Bool = { x, y in
                GlowFieldSpec.tealDistance(unitX: x, unitY: y, containerWidth: geometry.width,
                                           containerHeight: geometry.height) > GlowFieldSpec.falloffMidStop
            }
            let cases: [(String, [GlowFieldSpec.Glow], TokenAppearance, (Double, Double) -> Bool,
                         (RGBAColor) -> RGBAColor, AppearancePair)] = [
                ("R4-GLOW-01 labelSecondary", GlowFieldSpec.glows, .dark, { _, _ in true }, { $0 }, Palette.labelSecondary),
                ("R4-GLOW-04 labelTertiary outside core", GlowFieldSpec.glows, .dark, outsideCore, { $0 }, Palette.labelTertiary),
                ("R4-GLOW-02 label on rowSelected", GlowFieldSpec.glows, .dark, { _, _ in true },
                 { Palette.rowSelected.value(for: .dark).over($0) }, Palette.label),
                ("R4-GLOW-APP-01 labelSecondary", GlowFieldSpec.appGlows, .dark, { _, _ in true }, { $0 }, Palette.labelSecondary),
                ("R4-GLOW-APP-02 labelTertiary on card (dark)", GlowFieldSpec.appGlows, .dark, { _, _ in true },
                 { Palette.panelFill.value(for: .dark).over($0) }, Palette.labelTertiary),
                ("R4-GLOW-APP-02 labelTertiary on card (light)", GlowFieldSpec.appGlows, .light, { _, _ in true },
                 { Palette.panelFill.value(for: .light).over($0) }, Palette.labelTertiary),
            ]
            for (name, glows, appearance, domain, surface, label) in cases {
                let onGrid = Self.minRatio(points: grid, geometry: geometry, glows: glows, appearance: appearance,
                                           domain: domain, surface: surface, label: label)
                let onDense = Self.minRatio(points: dense, geometry: geometry, glows: glows, appearance: appearance,
                                            domain: domain, surface: surface, label: label)
                print(String(format: "P5b AUDIT %@ @%.0fpt: grid min %.4f @(%.3f,%.3f)  dense min %.4f @(%.4f,%.4f)  gap %.4f",
                             name, geometry.width, onGrid.ratio, onGrid.x, onGrid.y,
                             onDense.ratio, onDense.x, onDense.y, onGrid.ratio - onDense.ratio))
                #expect(onDense.ratio >= ContrastAuditTests.textAA, "\(name) dense min \(onDense.ratio) < 4.5")
            }
        }
    }

    // MARK: N120/N121 — the clamp and the light lift over the whole RGB cube

    @Test("N120/N121 clamp + light pair: in-box, hue-preserving, idempotent, light ≥ pastel luminance, channels in [0,1]")
    func clampProperties() {
        var rng = SplitMix(seed: 120)
        var accepted = 0
        var worstLightChannel = (low: 1.0, high: 0.0)
        for index in 0 ..< 60000 {
            let sample: RGBAColor = index < 4096
                ? RGBAColor(red: Double(index & 15) / 15, green: Double((index >> 4) & 15) / 15, blue: Double(index >> 8) / 15)
                : RGBAColor(red: rng.unit(), green: rng.unit(), blue: rng.unit())
            for slot in GlowFieldSpec.glows.indices {
                guard let dark = SampledGlow.clampedSampledColor(sample, slot: slot) else { continue }
                accepted += 1
                let ceiling = SampledGlow.channelMax[slot]
                #expect(max(dark.red, dark.green, dark.blue) <= ceiling + 1e-12)
                #expect(dark.alpha == GlowFieldSpec.glows[slot].color.dark.alpha)
                // Hue preserved: proportional scale (cross ratios equal).
                #expect(abs(dark.red * sample.green - dark.green * sample.red) < 1e-12)
                #expect(abs(dark.green * sample.blue - dark.blue * sample.green) < 1e-12)
                // Idempotent.
                #expect(SampledGlow.clampedSampledColor(dark, slot: slot) == dark)
                guard let pair = SampledGlow.clampedSampledPair(sample, slot: slot) else {
                    Issue.record("pair nil where dark clamp accepted")
                    continue
                }
                let light = pair.light
                for channel in [light.red, light.green, light.blue] {
                    worstLightChannel = (min(worstLightChannel.low, channel), max(worstLightChannel.high, channel))
                    #expect(channel >= -1e-9 && channel <= 1 + 1e-9, "light channel \(channel) for \(sample) slot \(slot)")
                }
                let target = GlowFieldSpec.glows[slot].color.light.relativeLuminance
                #expect(light.relativeLuminance >= target - 1e-9, "light pastel darker than brand pastel: \(sample) slot \(slot)")
                // GLOW-01 in light: the light pair composited at ANY partial alpha never darkens the window.
                let window = Palette.window.value(for: .light)
                for fraction in [0.05, 0.25, 0.5, 1.0] {
                    let composite = light.opacity(light.alpha * fraction).over(window)
                    #expect(composite.relativeLuminance >= window.relativeLuminance - 1e-9,
                            "light glow darkens the window: \(sample) slot \(slot) fraction \(fraction)")
                }
            }
        }
        print("P5b N121: accepted \(accepted); light channel range \(worstLightChannel)")
    }

    @Test("N122 dominant colours: degenerate covers (empty, transparent, gray, single pixel, single colour)")
    func dominantDegenerate() {
        #expect(SampledGlow.dominantColors(samples: []).isEmpty)
        // A fully transparent cover premultiplies to black → no votes.
        #expect(SampledGlow.dominantColors(samples: Array(repeating: .fromPixel(red: 0, green: 0, blue: 0), count: 1024)).isEmpty)
        // Pure grays / white never vote.
        #expect(SampledGlow.dominantColors(samples: (0 ... 255).map { .fromPixel(red: UInt8($0), green: UInt8($0), blue: UInt8($0)) }).isEmpty)
        // One vivid pixel → exactly that colour.
        let one = SampledGlow.dominantColors(samples: [.fromPixel(red: 200, green: 30, blue: 90)])
        #expect(one.count == 1 && abs(one[0].red - 200.0 / 255) < 1e-12)
        // A single-colour cover → one colour, itself.
        let flat = SampledGlow.dominantColors(samples: Array(repeating: .fromPixel(red: 20, green: 120, blue: 220), count: 4096))
        #expect(flat.count == 1 && abs(flat[0].blue - 220.0 / 255) < 1e-12)
        // Every 8-bit RGB lattice point (step 5): no crash, ≤ 3 colours, each a convex mix of its voters (in the cube).
        var lattice: [RGBAColor] = []
        for r in stride(from: 0, through: 255, by: 5) {
            for g in stride(from: 0, through: 255, by: 5) {
                for b in stride(from: 0, through: 255, by: 5) {
                    lattice.append(.fromPixel(red: UInt8(r), green: UInt8(g), blue: UInt8(b)))
                }
            }
        }
        let all = SampledGlow.dominantColors(samples: lattice)
        #expect(all.count == 3)
        #expect(all.allSatisfy { [$0.red, $0.green, $0.blue].allSatisfy { $0 >= 0 && $0 <= 1 } })
    }

    @Test("N122 hue-bucket wrap: a red cover jittering across 0° splits its vote and loses to a smaller blue field")
    func dominantRedWrapSplit() {
        // 60 % of the cover is ONE red that jitters ±8° around 0° (half at 352–359°, half at 0–7°);
        // 40 % is one flat blue. A perceptual "dominant colour" is the red.
        var samples: [RGBAColor] = []
        for index in 0 ..< 600 {
            let hue = index.isMultiple(of: 2) ? 352.0 + Double(index % 8) : Double(index % 8)
            samples.append(Self.hsv(hue, 0.85, 0.85))
        }
        samples += Array(repeating: Self.hsv(220, 0.85, 0.85), count: 400)
        let top = SampledGlow.dominantColors(samples: samples)
        let firstIsBlue = top.first.map { $0.blue > $0.red } ?? false
        print("P5b N122: red 60% (split 0°/360°) vs blue 40% → top = \(top.map { String(format: "(%.2f,%.2f,%.2f)", $0.red, $0.green, $0.blue) })")
        #expect(!firstIsBlue, "the 40 % blue out-votes the 60 % red because 0° is a bucket edge")
    }

    static func hsv(_ hue: Double, _ saturation: Double, _ value: Double) -> RGBAColor {
        let chroma = value * saturation
        let sector = hue / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base = value - chroma
        let (r, g, b): (Double, Double, Double) = switch Int(sector) % 6 {
        case 0: (chroma, second, 0)
        case 1: (second, chroma, 0)
        case 2: (0, chroma, second)
        case 3: (0, second, chroma)
        case 4: (second, 0, chroma)
        default: (chroma, 0, second)
        }
        return RGBAColor(red: r + base, green: g + base, blue: b + base)
    }

    @Test("N119 falloff: continuous, monotone non-increasing, 1 at 0, 0 at ≥1, NaN-safe")
    func falloffShape() {
        var previous = 1.0
        for step in 0 ... 100_000 {
            let t = Double(step) / 80_000
            let f = GlowFieldSpec.falloffFraction(at: t)
            #expect(f <= previous + 1e-12)
            #expect(abs(f - previous) < 1e-4 || step == 0, "jump at \(t)")
            previous = f
        }
        #expect(GlowFieldSpec.falloffFraction(at: 0) == 1 && GlowFieldSpec.falloffFraction(at: 1) == 0)
        let nanBackdrop = GlowFieldSpec.compositeBackdrop(unitX: .nan, unitY: 0.5, containerWidth: 100,
                                                          containerHeight: 100, appearance: .dark)
        #expect(!nanBackdrop.red.isNaN)
        let zeroSize = GlowFieldSpec.compositeBackdrop(unitX: 0.2, unitY: 0.1, containerWidth: 0,
                                                       containerHeight: 0, appearance: .dark)
        #expect(!zeroSize.red.isNaN)
    }

    @Test("N117/N118 AppearancePair + resolveSurface: the full flag cube, opaque whenever RT or IC")
    func resolverCube() {
        for role in [SurfaceRole.lens, .badge, .panel, .overlay(.bar), .overlay(.ultraThin)] {
            for appearance in TokenAppearance.allCases {
                for rt in [false, true] {
                    for ic in [false, true] {
                        let resolved = resolveSurface(role: role, appearance: appearance,
                                                      reduceTransparency: rt, increasedContrast: ic)
                        switch (role, resolved) {
                        case (.overlay, .systemMaterial): break
                        case let (_, .fill(color)):
                            #expect((rt || ic) ? color.alpha == 1 : true, "\(role) \(appearance) rt=\(rt) ic=\(ic)")
                        default: Issue.record("\(role) resolved to \(resolved)")
                        }
                    }
                }
            }
        }
        #expect(glowFieldIsVisible(reduceTransparency: false, increasedContrast: false))
        #expect(!glowFieldIsVisible(reduceTransparency: false, increasedContrast: true))
        #expect(!glowFieldIsVisible(reduceTransparency: true, increasedContrast: false))
    }

    @Test("N123 R4-GLOW-D8 lattice on a dense field: the {corner, brand} folds at their true worst points")
    func d8LatticeDense() {
        let corner = SampledGlow.auditCornerPalette
        let geometry = ContrastAuditTests.glowGeometries[0]
        let points = Self.densePoints(280, 200) + GlowFieldSpec.glows.map { ($0.unitCenterX, $0.unitCenterY) }
        var overall = (ratio: Double.infinity, what: "")
        for mask in 0 ..< 8 {
            let palette: [RGBAColor?] = (0 ..< 3).map { (mask & (1 << $0)) == 0 ? corner[$0] : nil }
            var gridMin = Double.infinity, denseMin = (ratio: Double.infinity, what: "")
            for (set, isGrid) in [(ContrastAuditTests.gridPoints(), true), (points, false)] {
                for point in set {
                    let backdrop = GlowFieldSpec.compositeBackdrop(unitX: point.x, unitY: point.y,
                                                                   containerWidth: geometry.width,
                                                                   containerHeight: geometry.height,
                                                                   appearance: .dark, overrideColors: palette)
                    var pairs: [(String, Double)] = [
                        ("labelSecondary", ContrastAuditTests.ratio(label: Palette.labelSecondary, on: backdrop, .dark)),
                        ("statusWarningText on badge", ContrastAuditTests.ratio(label: Palette.statusWarningText,
                                                                                on: Palette.badgeFill.dark.over(backdrop), .dark)),
                        ("labelSecondary on lens", ContrastAuditTests.ratio(label: Palette.labelSecondary,
                                                                            on: Palette.lensFill.dark.over(backdrop), .dark)),
                    ]
                    if GlowFieldSpec.tealDistance(unitX: point.x, unitY: point.y, containerWidth: geometry.width,
                                                  containerHeight: geometry.height) > GlowFieldSpec.falloffMidStop {
                        pairs.append(("labelTertiary", ContrastAuditTests.ratio(label: Palette.labelTertiary, on: backdrop, .dark)))
                    }
                    for (name, ratio) in pairs {
                        if isGrid {
                            gridMin = min(gridMin, ratio)
                        } else if ratio < denseMin.ratio {
                            denseMin = (ratio, String(format: "%@ mask %d @(%.4f,%.4f)", name, mask, point.x, point.y))
                        }
                    }
                }
            }
            print(String(format: "P5b D8 mask %d: grid min %.4f, dense min %.4f (%@)", mask, gridMin, denseMin.ratio, denseMin.what))
            if denseMin.ratio < overall.ratio {
                overall = denseMin
            }
        }
        #expect(overall.ratio >= ContrastAuditTests.textAA, "\(overall.what) = \(overall.ratio)")
    }
}

/// A tiny deterministic generator (SplitMix64) so every run is reproducible.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
