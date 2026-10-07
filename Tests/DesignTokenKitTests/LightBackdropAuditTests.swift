// The candidate LIGHT backdrops (S10.8 B2b): their data, the resolver's use of their window,
// and the R4 light pairs on every candidate window. The base suites audit `Palette.window` —
// backdrops A and B — so the replay is what covers C's tinted base. TEMPORARY like the switch:
// deleted with the losing backdrops (if C wins, its window becomes `Palette.window` and the
// base suites carry it).

import DesignTokenKit
import Testing

@Suite("Light backdrops — the B2b candidates")
struct LightBackdropAuditTests {
    @Test("LB-01: the backdrop is a light-only choice — every candidate's dark window is today's")
    func darkIsUntouched() {
        for backdrop in LightBackdrop.allCases {
            for increasedContrast in [false, true] {
                #expect(backdrop.window.value(for: .dark, increasedContrast: increasedContrast)
                    == Palette.window.value(for: .dark, increasedContrast: increasedContrast), "\(backdrop)")
            }
        }
    }

    @Test("LB-02: B is the designed default; A and B paint today's grey, C the teal-grey base")
    func candidates() {
        #expect(LightBackdrop.designed == .paleGlow)
        #expect(LightBackdrop.noGlow.window == Palette.window)
        #expect(LightBackdrop.paleGlow.window == Palette.window)
        #expect(LightBackdrop.tintedBase.window.light
            == RGBAColor(red: 227.0 / 255.0, green: 238.0 / 255.0, blue: 236.0 / 255.0))
        #expect(LightBackdrop.allCases.filter(\.glowsInLight) == [.paleGlow])
        // The glow composite folds over `Palette.window` (GlowFieldSpec.compositeBackdrop), so
        // a backdrop that glows in light must paint exactly that window.
        for backdrop in LightBackdrop.allCases where backdrop.glowsInLight {
            #expect(backdrop.window == Palette.window, "\(backdrop)")
        }
    }

    @Test("RES-07: the RT/IC opaque fill composites over the backdrop's own window")
    func opaqueFillsSitOnTheBackdrop() {
        let fillRoles: [(role: SurfaceRole, pair: AppearancePair)] = [
            (.lens, Palette.lensFill), (.badge, Palette.badgeFill), (.panel, Palette.panelFill),
        ]
        for backdrop in LightBackdrop.allCases {
            for (role, pair) in fillRoles {
                for appearance in TokenAppearance.allCases {
                    for increasedContrast in [false, true] {
                        let resolved = resolveSurface(role: role, appearance: appearance,
                                                      reduceTransparency: true,
                                                      increasedContrast: increasedContrast,
                                                      backdrop: backdrop)
                        let window = backdrop.window.value(for: appearance, increasedContrast: increasedContrast)
                        let fill = pair.value(for: appearance, increasedContrast: increasedContrast)
                        #expect(resolved == .fill(fill.over(window)), "\(backdrop) \(role) \(appearance)")
                    }
                }
            }
        }
    }

    @Test("R4-LB-01: every light R4 pair clears its threshold on every candidate window")
    func lightPairsOnEveryWindow() {
        for backdrop in LightBackdrop.allCases {
            LightPairs.expectAll(on: backdrop.window.light, "\(backdrop) window")
        }
    }
}
