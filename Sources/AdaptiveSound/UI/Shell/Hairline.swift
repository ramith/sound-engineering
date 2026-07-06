import SwiftUI

/// A 0.5pt hairline separator.
///
/// A *filled* `Rectangle` (not `Divider`) painted in `DesignSystem.Color.hairline`:
/// `Divider` ignores `foregroundStyle` on macOS, so the shell uses this wherever a
/// header / footer / card edge needs a crisp, appearance-reactive rule.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Color.hairline)
            .frame(height: DesignSystem.ShellMetrics.hairline)
    }
}
