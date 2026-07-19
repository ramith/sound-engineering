// NowPlayingLayout — the PR-5 restructure's layout data (design §5), in the Kit so the
// §7.1 layout-arithmetic test can ASSERT the width/height budget headlessly instead of
// trusting prose. The app-side views consume these; the test derives from them.

import Foundation

public enum NowPlayingLayout {
    /// The fixed trailing inspector column (founder decision D2 — 8a). S10.8 PR E: 260 →
    /// 320 per the Realigned Target's floating card (`png/05`); LAY-01 still clears the
    /// 320pt queue minimum at the 880pt window (848 − 20 − 320 = 508).
    public static let inspectorWidth: Double = 320
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
    /// The shell's fixed bands. `DesignSystem.ShellMetrics` FORWARDS these (single-source
    /// invariant, PR 1a pattern): the shell lays out from the same values the §5 arithmetic
    /// test derives from, so neither can drift behind the other.
    public static let windowMinWidth: Double = 880
    public static let windowMinHeight: Double = 640
    public static let chromeHeight: Double = 60
    public static let footerHeight: Double = 64
    /// The §7.1 headroom factor absorbing Dynamic-Type growth of the hero block in the
    /// vertical budget (macOS max text size ≈ 1.4× default — documented approximation; the
    /// hero deliberately scales, the assertion is that scaling never starves the queue).
    public static let maxTypeHeadroom: Double = 1.4
}
