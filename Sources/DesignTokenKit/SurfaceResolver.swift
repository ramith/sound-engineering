// SurfaceResolver — the pure RT/IC resolution contract for glass-look surfaces (S10.7 R0).
//
// The app-side `.glassPanel(_:in:)` modifier is a thin shim: it reads the accessibility
// environment, calls `resolveSurface`, and paints the result. ALL resolution logic lives
// here so it is unit-testable headlessly (design §7 R2: RES-01..04). Roles land STAGED with
// their first consumer (design §3.2): PR 1a ships `.overlay` only; the fill roles (panel /
// lens / control / badge) arrive with PRs 2–6 and will extend `ResolvedSurface` with the
// translucent-fill → opaque-fill Reduce-Transparency swap.

import Foundation

// MARK: - Roles

/// What a surface IS (never how it looks). The app-wide role charter is in the design doc;
/// cases appear here only once a consumer exists (hostile-Periphery staging rule).
public enum SurfaceRole: Equatable, Sendable {
    /// A transient floating surface with variable content genuinely beneath it — the ONE
    /// Material-backed role (design §3.1: banner / toast / EQ recall / selection pill).
    /// The substrate is token-governed but per-site (the S10.3 pill shipped on `.bar`);
    /// the shape is a call-site parameter on the app-side modifier.
    case overlay(OverlaySubstrate)
    /// The analyzer lens — the first Regime-B FILL role (PR 3): a token'd translucent fill
    /// + edge decoration; NEVER backdrop-sampling (design §3.1).
    case lens
    /// Hero badge capsules (PR 4): the 8a small-control fill, same RT/IC contract as lens.
    case badge
    /// The inspector column (PR 5): the 8a panel fill, same RT/IC contract.
    case panel
}

/// The animation-gate predicate (design §3.4/§7 R2 PG-01..04): the pulsing dot and the
/// active-row equalizer animate ONLY while playing AND only when Reduce Motion is off.
public func pulseIsActive(isPlaying: Bool, reduceMotion: Bool) -> Bool {
    isPlaying && !reduceMotion
}

/// The blessed system-material substrates for `.overlay`. `.bar` exists solely for the
/// pre-glass selection pill's shipped look; PR 5 / S10.8 restyles may unify onto `.ultraThin`.
public enum OverlaySubstrate: Equatable, Sendable, CaseIterable {
    case ultraThin
    case bar
}

// MARK: - Resolution result

/// What the modifier paints. `.systemMaterial` = the system owns the fallback behavior
/// (Reduce Transparency / Increase Contrast adaptation is NATIVE to Material — the resolver
/// deliberately passes it through untouched, design §3.2 `.overlay` spec). `.fill` = a
/// Regime-B token fill, already RT/IC-resolved (translucent normally; the OPAQUE
/// fill-over-window composite when transparency is reduced — derived, never hand-kept).
public enum ResolvedSurface: Equatable, Sendable {
    case systemMaterial(OverlaySubstrate)
    case fill(RGBAColor)
}

// MARK: - Resolver

/// Pure resolution: role × appearance × accessibility flags → what to paint. Deterministic,
/// total. Contract notes the fill roles will honor (asserted then by RES-01/02): a
/// translucent fill goes opaque when `reduceTransparency` is true, AND when
/// `increasedContrast` is true even with `reduceTransparency` false — macOS couples IC→RT at
/// the OS level, but the resolver must never depend on the OS doing it (design §7 RES-02).
public func resolveSurface(role: SurfaceRole,
                           appearance: TokenAppearance,
                           reduceTransparency: Bool,
                           increasedContrast: Bool) -> ResolvedSurface {
    switch role {
    case let .overlay(substrate):
        // Native-adaptation ownership: Material self-adapts to RT/IC/appearance, so the
        // resolver returns the substrate unconditionally — asserted for the full flag
        // cube in RES tests.
        return .systemMaterial(substrate)
    // Every fill role names its pair EXPLICITLY (no `default:`) so a future role cannot
    // silently inherit panelFill — it fails to compile until someone binds its token here.
    case .lens:
        return resolvedFill(Palette.lensFill, appearance: appearance,
                            reduceTransparency: reduceTransparency,
                            increasedContrast: increasedContrast)
    case .badge:
        return resolvedFill(Palette.badgeFill, appearance: appearance,
                            reduceTransparency: reduceTransparency,
                            increasedContrast: increasedContrast)
    case .panel:
        return resolvedFill(Palette.panelFill, appearance: appearance,
                            reduceTransparency: reduceTransparency,
                            increasedContrast: increasedContrast)
    }
}

/// RES-01/02 for every fill role: translucent normally; opaque (fill composited over the
/// window) when transparency is reduced — and under Increase Contrast EVEN IF the RT flag
/// is false (never depend on the OS coupling IC→RT).
private func resolvedFill(_ pair: AppearancePair,
                          appearance: TokenAppearance,
                          reduceTransparency: Bool,
                          increasedContrast: Bool) -> ResolvedSurface {
    let fill = pair.value(for: appearance, increasedContrast: increasedContrast)
    if reduceTransparency || increasedContrast {
        let window = Palette.window.value(for: appearance, increasedContrast: increasedContrast)
        return .fill(fill.over(window))
    }
    return .fill(fill)
}
