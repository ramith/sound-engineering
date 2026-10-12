// DevicePillMetrics — the output-device pill's size as data (S10.8 F2), in the Kit so the Settings
// title-row test (LAY-SET-01b) budgets the pill the app draws, as `FilterPillMetrics` does for the
// filter pill.

import Foundation

/// The output-device pill's size (`OutputDevicePill` — the chrome's, and Settings' Output Device
/// card's). Its live-rate readout is a slot of its own, `SlotWidths.chromeSampleRate`.
public enum DevicePillMetrics {
    /// The pill's widest: it HUGS its content up to this, then the device name truncates, so an
    /// aggregate device's long name can't blow out the bar. (It was a fixed 302 pt slot while the tab
    /// strip sat directly to its right, so a device change could not slide the tabs; the tabs moved to
    /// the chrome's right edge in S10.8 founder round 1, so only the pill's own trailing edge moves now.)
    public static let maxWidth: Double = 302
    /// The pill's least height. Settings' title rows take it too (`SettingsLayout.titleRowMinHeight`),
    /// so every card's title sits at one height, pill or not.
    public static let minHeight: Double = 32
}
