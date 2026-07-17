// NowPlayingLayout — the PR-5 restructure's layout data (design §5), in the Kit so the
// §7.1 layout-arithmetic test can ASSERT the width/height budget headlessly instead of
// trusting prose. The app-side views consume these; the test derives from them.

import Foundation

public enum NowPlayingLayout {
    /// The fixed trailing inspector column (founder decision D2 — 8a).
    public static let inspectorWidth: Double = 260
    /// Content inset from the window edges (8a alignment grid).
    public static let contentInset: Double = 16
    /// Gap between the hero text block and the lens, and between the queue and inspector.
    public static let regionGap: Double = 20
    /// The analyzer lens frame (founder decision D6 — 8a hero-right, flexing).
    public static let lensMinWidth: Double = 400
    public static let lensMaxWidth: Double = 560
    public static let lensHeight: Double = 122
    /// Minimum usable widths the arithmetic test asserts at the 880pt window minimum.
    public static let queueMinWidth: Double = 320
    public static let heroTextMinWidth: Double = 300
    /// The shell's fixed bands (mirrors ShellMetrics — asserted equal by the app target's
    /// consumption; duplicated VALUES would drift, so the app reads THESE for the min-window
    /// content-height derivation used in §5's arithmetic).
    public static let windowMinWidth: Double = 880
    public static let windowMinHeight: Double = 640
    public static let chromeHeight: Double = 60
    public static let footerHeight: Double = 64
    /// The §7.1 headroom factor absorbing Dynamic-Type growth of the hero block in the
    /// vertical budget (macOS max text size ≈ 1.4× default — documented approximation; the
    /// hero deliberately scales, the assertion is that scaling never starves the queue).
    public static let maxTypeHeadroom: Double = 1.4
}
