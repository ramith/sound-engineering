import SwiftUI

// MARK: - Pill menus (a `Menu` whose label is a real SwiftUI view)

extension View {
    /// Make a `Menu` draw its label as a REAL SwiftUI view: rendered in full, re-rendered live
    /// when observed state changes, and clickable across the label's whole shape. Apply it to the
    /// `Menu`, and build the entire pill (padding, fill, ring, every text) INSIDE the label.
    ///
    /// Why this exists — `.menuStyle(.borderlessButton)` hands the label to an AppKit pop-up
    /// button, which keeps ONE image and ONE text and throws the rest away (a second `Text`,
    /// padding, capsule fill, ring), and does not re-render when observed state changes. That
    /// silently broke three pills (founder screenshots, 2026-10-06):
    ///
    ///   - the Songs **Sort** pill drew a bare "⌄ Sort:" — no value, no capsule;
    ///   - the Songs **Columns** pill lost its teal capsule;
    ///   - the chrome **device** pill needed its rate readout moved OUTSIDE the label to update
    ///     at all (S10.7 PR 6), which left a dead, unclickable half and let AppKit's own bezel
    ///     insets truncate the device name.
    ///
    /// An offscreen render on macOS 26.6 confirmed both halves: the borderless style reproduces
    /// the broken pill exactly and never updates, while `.buttonStyle(.plain)` renders the label
    /// pixel-identical to the same view outside a `Menu` and follows state changes. A view-level
    /// hit-test of the borderless style also shows its AppKit control covers only the text, not
    /// the surrounding padding — the "highlights but does not click" chip.
    ///
    /// `.menuIndicator(.hidden)`: the pill draws its own chevron where the design wants it.
    /// `.fixedSize()`: a pill hugs its label instead of stretching to the proposed width.
    func pillMenuStyle() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}
