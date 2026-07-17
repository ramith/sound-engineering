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
}

/// The blessed system-material substrates for `.overlay`. `.bar` exists solely for the
/// pre-glass selection pill's shipped look; PR 5 / S10.8 restyles may unify onto `.ultraThin`.
public enum OverlaySubstrate: Equatable, Sendable, CaseIterable {
    case ultraThin
    case bar
}

// MARK: - Accessibility flags

/// The environment flags surface resolution answers to. `increasedContrast` implies the
/// opaque path even if `reduceTransparency` is false (macOS couples IC→RT at the OS level,
/// but the resolver must not depend on the OS doing it — design §7 RES-02).
public struct AccessibilityFlags: Equatable, Sendable {
    public let reduceTransparency: Bool
    public let increasedContrast: Bool

    public init(reduceTransparency: Bool, increasedContrast: Bool) {
        self.reduceTransparency = reduceTransparency
        self.increasedContrast = increasedContrast
    }
}

// MARK: - Resolution result

/// What the modifier paints. `.systemMaterial` = the system owns the fallback behavior
/// (Reduce Transparency / Increase Contrast adaptation is NATIVE to Material — the resolver
/// deliberately passes it through untouched, design §3.2 `.overlay` spec). Fill-based cases
/// join with the fill roles.
public enum ResolvedSurface: Equatable, Sendable {
    case systemMaterial(OverlaySubstrate)
}

// MARK: - Resolver

/// Pure resolution: role × appearance × flags → what to paint. Deterministic, total.
public func resolveSurface(role: SurfaceRole,
                           appearance: TokenAppearance,
                           flags: AccessibilityFlags) -> ResolvedSurface {
    switch role {
    case let .overlay(substrate):
        // Native-adaptation ownership: Material self-adapts to RT/IC/appearance, so the
        // resolver returns the substrate unconditionally — asserted for the full flag
        // cube in RES tests. (`appearance` participates for the fill roles to come.)
        _ = appearance
        _ = flags
        return .systemMaterial(substrate)
    }
}
