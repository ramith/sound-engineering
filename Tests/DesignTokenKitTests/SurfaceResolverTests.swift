// RES — resolver contract tests (design §7 R2). PR 1a scope: the `.overlay` role. The fill
// roles' RT-swap cases (RES-01/02 for translucent fills) land with their roles in PRs 2–6.

import DesignTokenKit
import Testing

@Suite("SurfaceResolver — overlay (RES)")
struct SurfaceResolverOverlayTests {
    /// Every (appearance × RT × IC) combination — the full flag cube, derived not enumerated
    /// by hand, so a new flag dimension can't silently escape coverage.
    private static let cube: [(TokenAppearance, AccessibilityFlags)] = TokenAppearance.allCases
        .flatMap { appearance in
            [false, true].flatMap { reduceTransparency in
                [false, true].map { increasedContrast in
                    (appearance, AccessibilityFlags(reduceTransparency: reduceTransparency,
                                                    increasedContrast: increasedContrast))
                }
            }
        }

    /// Native adaptation ownership: the resolver never substitutes a fill for an overlay.
    @Test("RES-OV-01: overlay resolves to its system material for the entire flag cube")
    func overlayIsAlwaysSystemMaterial() {
        for substrate in OverlaySubstrate.allCases {
            for (appearance, flags) in Self.cube {
                let resolved = resolveSurface(role: .overlay(substrate),
                                              appearance: appearance,
                                              flags: flags)
                #expect(resolved == .systemMaterial(substrate),
                        "overlay(\(substrate)) substituted under \(appearance)/\(flags)")
            }
        }
    }
}
