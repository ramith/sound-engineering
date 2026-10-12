import SwiftUI

// MARK: - Hairline (S10.8 F — the one rule between a card's sections)

/// A 1 pt horizontal rule in `DesignSystem.Color.hairline`, between a card's sections or under a
/// header: Settings' cards, the inspector, the Library card and page headers, the rail. A filled
/// `Rectangle`, not `Divider`, which ignores `foregroundStyle` on macOS. It takes the width it is
/// offered; any inset is the call site's.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Color.hairline)
            .frame(height: 1)
    }
}
