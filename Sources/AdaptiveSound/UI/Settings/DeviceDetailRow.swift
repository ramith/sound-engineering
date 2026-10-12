import SwiftUI

// MARK: - Device detail row (Settings › Output Device)

/// The device in use, in detail: its icon, its name with its kind ("MacBook Pro Speakers (Built-in)"),
/// and a line with its Core Audio ID, its rate and its buffer size.
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
                Text("ID \(device.id)  •  \(device.displayKHz)  •  \(device.bufferFrameSize) frames")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
        }
        // One element, read without the bullets and with "kilohertz", not "k-H-z".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.displayName), device ID \(device.id), \(device.spokenKHz), "
            + "\(device.bufferFrameSize) frames")
    }
}
