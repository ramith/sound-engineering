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

    /// The fill roles and their token pairs — one table drives RES-01/02 (new fill roles
    /// join here, and only here).
    private static let fillRoles: [(role: SurfaceRole, pair: AppearancePair)] = [
        (.lens, Palette.lensFill),
        (.badge, Palette.badgeFill),
        (.panel, Palette.panelFill),
    ]

    @Test("RES-01: fill roles resolve to their translucent token when transparency is allowed")
    func fillTranslucent() {
        for (role, pair) in Self.fillRoles {
            for appearance in TokenAppearance.allCases {
                let resolved = resolveSurface(role: role, appearance: appearance,
                                              reduceTransparency: false, increasedContrast: false)
                #expect(resolved == .fill(pair.value(for: appearance)), "\(role)")
            }
        }
    }

    @Test("RES-02: fill roles go OPAQUE (fill⊕window) under RT — and under IC even without RT")
    func fillOpaqueFallback() {
        for (role, pair) in Self.fillRoles {
            for point in Self.cube where point.reduceTransparency || point.increasedContrast {
                let resolved = resolveSurface(role: role,
                                              appearance: point.appearance,
                                              reduceTransparency: point.reduceTransparency,
                                              increasedContrast: point.increasedContrast)
                let fill = pair.value(for: point.appearance,
                                      increasedContrast: point.increasedContrast)
                let window = Palette.window.value(for: point.appearance,
                                                  increasedContrast: point.increasedContrast)
                #expect(resolved == .fill(fill.over(window)), "\(role) stayed translucent under \(point)")
                if case let .fill(color) = resolved {
                    #expect(color.alpha == 1.0, "\(role) RT/IC fallback must be fully opaque")
                }
            }
        }
    }

    @Test("PG-01..04: the pulse animates ONLY while playing with Reduce Motion off — full table")
    func pulseGate() {
        #expect(pulseIsActive(isPlaying: true, reduceMotion: false))
        #expect(!pulseIsActive(isPlaying: true, reduceMotion: true))
        #expect(!pulseIsActive(isPlaying: false, reduceMotion: false))
        #expect(!pulseIsActive(isPlaying: false, reduceMotion: true))
    }
}
