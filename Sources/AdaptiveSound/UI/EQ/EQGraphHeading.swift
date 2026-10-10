import SwiftUI

// MARK: - EQ graph card heading (Sprint EQ, EQ4)

/// The header's leading block: the preset and its state (`EQGraphTitle`) over the "Used on <output>"
/// pin (`EQOutputPinButton`), which shows while the output can be pinned. Both fit the header's height
/// (`EQScreenLayout.headerHeight`), so the pin coming and going never moves the graph.
struct EQGraphHeading: View {
    @Environment(EQViewModel.self) private var eq

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EQGraphTitle()
            if let pin = eq.outputPin {
                EQOutputPinButton(pin: pin, toggle: eq.togglePin)
            }
        }
    }
}
