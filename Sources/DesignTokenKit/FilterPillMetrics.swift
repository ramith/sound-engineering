// FilterPillMetrics — the filter pill's horizontal geometry as data (S10.8 D2), in the Kit so the
// placeholder-fit test (SLOT-06) can measure the pill headlessly, exactly as the app draws it.

import Foundation

/// The filter pill's horizontal geometry: `FilterPill` lays out with these and SLOT-06
/// (DesignTokenKitTests/SlotFitTests) measures with them, so the test cannot drift from the render.
/// The narrowest each host lets the pill get is a slot (`SlotWidths.queueFilter`, `.libraryFilter`).
public enum FilterPillMetrics {
    /// The inset from each round end of the capsule to its content.
    public static let horizontalInset: Double = 12
    /// The gap between the magnifier, the text and the clear button.
    public static let itemSpacing: Double = 7
}
