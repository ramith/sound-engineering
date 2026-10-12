import DesignTokenKit
import SwiftUI

// MARK: - Output device pill (the chrome's device picker — S10.8 F2: shared with Settings)

/// The output device as a pill that opens the device menu: the device's icon and name, a chevron, and
/// its live sample rate while one is known. The chrome's top bar shows it beside the logo; Settings'
/// Output Device card reuses it, so both pick a device the same way.
///
/// - **The menu:** one item per output device, the current one CHECKED — the menu's native state,
///   which VoiceOver reads as "checked" (a checkmark image beside the name read as nothing). Choosing
///   an item selects that device. The check follows the device actually in use: a failed switch
///   leaves it where it was.
/// - **Size:** the pill hugs its content up to `DevicePillMetrics.maxWidth`, then the name truncates,
///   so an aggregate device's long name can't blow out the bar.
/// - **Keyboard:** a Tab stop under Full Keyboard Access with the app's keyboard ring, like the
///   Library's Sort and Columns pills.
struct OutputDevicePill: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The device's live output rate (0 when idle → the readout slot stays empty). Enhanced
    /// now publishes this too (PR 6), so it's populated on both paths while playing.
    private var achievedRate: Double {
        viewModel.signalPath.achievedSampleRate
    }

    var body: some View {
        Menu {
            ForEach(viewModel.availableDevices) { device in
                Toggle(device.displayName, isOn: isCurrent(device))
            }
        } label: {
            pillLabel
        }
        // The WHOLE pill is the menu's label (`pillMenuStyle`). Under the old borderless style
        // only the icon + name were, drawn by AppKit: the rate had to sit beside the menu to
        // update at all, which left the pill's trailing half unclickable, and AppKit's own bezel
        // insets truncated "MacBook Pro Speak…" with empty space right next to it (founder
        // screenshot, 2026-10-06).
        .pillMenuStyle()
        .controlFocusRing(around: Capsule())
        .accessibilityLabel("Audio output device")
        .accessibilityValue(deviceAccessibilityValue)
        .accessibilityHint("Click to choose from available audio output devices")
    }

    private var pillLabel: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.selectedDevice?.systemIcon ?? "speaker.wave.2")
                Text(viewModel.selectedDevice?.name ?? "No Device")
                    .lineLimit(1)
                    .truncationMode(.tail)
                // Realigned (png/01): an explicit dropdown chevron after the name.
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.asLabelTertiary)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.asLabel)

            // D5: the device's live sample rate, digits rolling (`numericText`) when it changes.
            // Present only while a rate is known — an idle pill is just the device, with no
            // blank reserved slot. While shown it keeps a FIXED slot, so a rate change
            // (44.1 → 176.4 kHz) rolls the digits without resizing the pill.
            if achievedRate > 0 {
                Text(SignalPathInfo.rateString(achievedRate))
                    .font(DesignSystem.Font.monoSmall)
                    .foregroundStyle(Color.asLabelSecond)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    // The slot fits every rate at default size (SLOT-02); a 9-char hi-res rate
                    // ("176.4 kHz") at the clamped .xLarge max shrinks to fit rather than
                    // truncating away the "kHz" unit.
                    .minimumScaleFactor(0.7)
                    .frame(width: CGFloat(SlotWidths.chromeSampleRate), alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: CGFloat(DevicePillMetrics.minHeight))
        .frame(maxWidth: CGFloat(DevicePillMetrics.maxWidth), alignment: .leading)
        // The 8a glass "small-control" fill (the .badge role — same white-8% recipe the
        // mock's device pill uses).
        .glassPanel(.badge, in: Capsule())
        .contentShape(Capsule())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: achievedRate)
    }

    /// A device's menu item: on while it is the device in use. Choosing it selects that device — every
    /// choice goes to `selectDevice`, which commits only on success, as the old item buttons did.
    private func isCurrent(_ device: AudioDeviceModel) -> Binding<Bool> {
        Binding(get: { viewModel.selectedDevice?.id == device.id },
                set: { _ in viewModel.selectDevice(device) })
    }

    private var deviceAccessibilityValue: String {
        let name = viewModel.selectedDevice?.displayName ?? "No device selected"
        guard achievedRate > 0 else { return name }
        return "\(name), \(SignalPathInfo.rateString(achievedRate).replacing(" kHz", with: " kilohertz"))"
    }
}
