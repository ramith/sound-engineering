import SwiftUI

// MARK: - Device detail row (Settings › Output Device)

/// The device in use, in detail: its icon, its name with its kind ("MacBook Pro Speakers (Built-in)"),
/// and a line with its sample rate ("44.1 kHz").
struct DeviceDetailRow: View {
    let device: AudioDeviceModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.systemIcon)
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.accentForeground)
                .frame(width: 24)
                .accessibilityHidden(true) // the name says what it is

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.label)
                Text(device.displayKHz)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
        }
        // One element, read with "kilohertz", not "k-H-z".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.displayName), \(device.spokenKHz)")
    }
}
