// RES — resolver contract tests (design §7 R2). PR 1a scope: the `.overlay` role. The fill
// roles' RT-swap cases (RES-01/02 for translucent fills) land with their roles in PRs 2–6.

import DesignTokenKit
import Testing

@Suite("SurfaceResolver — overlay (RES)")
struct SurfaceResolverOverlayTests {
    /// One point of the appearance × RT × IC flag cube.
    private struct FlagCase {
        let appearance: TokenAppearance
        let reduceTransparency: Bool
        let increasedContrast: Bool
    }

    /// Every (appearance × RT × IC) combination — the full flag cube, derived not enumerated
    /// by hand, so a new flag dimension can't silently escape coverage.
    private static let cube: [FlagCase] = TokenAppearance.allCases.flatMap { appearance in
        [false, true].flatMap { reduceTransparency in
            [false, true].map { increasedContrast in
                FlagCase(appearance: appearance,
                         reduceTransparency: reduceTransparency,
                         increasedContrast: increasedContrast)
            }
        }
    }

    /// Native adaptation ownership: the resolver never substitutes a fill for an overlay.
    @Test("RES-OV-01: overlay resolves to its system material for the entire flag cube")
    func overlayIsAlwaysSystemMaterial() {
        for substrate in OverlaySubstrate.allCases {
            for point in Self.cube {
                let resolved = resolveSurface(role: .overlay(substrate),
                                              appearance: point.appearance,
                                              reduceTransparency: point.reduceTransparency,
                                              increasedContrast: point.increasedContrast)
                #expect(resolved == .systemMaterial(substrate),
                        "overlay(\(substrate)) substituted under \(point)")
            }
        }
    }
}
