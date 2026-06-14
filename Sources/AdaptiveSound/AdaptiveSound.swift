import Foundation
import SwiftUI

@main
struct AdaptiveSound: App {
    @StateObject private var viewModel = AudioViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var viewModel: AudioViewModel

    var body: some View {
        VStack(spacing: 20) {
            HeaderView()
            StatusCardView()
            DeviceInfoView()
            DevicePickerView()
            if viewModel.errorMessage != nil {
                ErrorBannerView()
            }
            Spacer()
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            viewModel.initializeEngine()
        }
        .onDisappear {
            viewModel.shutdown()
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(LinearGradient.asIconFill)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)

            Text("Adaptive Sound")
                .font(BrandFont.heading)
                .foregroundColor(.asLabel)

            Text("Audio Enhancement Engine")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.asLabelSecond)
        }
        .padding()
    }
}

// MARK: - Status Card

struct StatusCardView: View {
    @EnvironmentObject var viewModel: AudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine Status")
                .font(BrandFont.sectionLabel)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundColor(.asLabelTertiary)

            HStack {
                Image(
                    systemName: viewModel.isEngineReady
                        ? "circle.fill"
                        : "circle"
                )
                .foregroundColor(
                    viewModel.isEngineReady
                        ? .asGreen
                        : .orange
                )
                Text(
                    viewModel.isEngineReady
                        ? "Audio Engine Ready"
                        : "Initializing..."
                )
                .font(BrandFont.mono)
                .foregroundColor(.asLabel)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.asCard)
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
        }
        .padding()
    }
}

// MARK: - Device Info

struct DeviceInfoView: View {
    @EnvironmentObject var viewModel: AudioViewModel

    var body: some View {
        if let device = viewModel.selectedDevice {
            VStack(alignment: .leading, spacing: 8) {
                Text("Output Device")
                    .font(BrandFont.sectionLabel)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundColor(.asLabelTertiary)
                Text(device.displayName)
                    .font(.body)
                    .foregroundColor(.asLabel)
                HStack(spacing: 12) {
                    Text("\(device.sampleRate) Hz")
                        .font(.caption)
                        .foregroundColor(.asLabelSecond)
                    Text("\(device.bufferFrameSize) frames")
                        .font(.caption)
                        .foregroundColor(.asLabelSecond)
                }
            }
            .padding(12)
            .background(Color.asCard)
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
            .padding(.horizontal)
        }
    }
}

// MARK: - Device Picker

struct DevicePickerView: View {
    @EnvironmentObject var viewModel: AudioViewModel

    var body: some View {
        if !viewModel.availableDevices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Available Devices")
                    .font(BrandFont.sectionLabel)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundColor(.asLabelTertiary)
                    .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.availableDevices, id: \.id) { device in
                            DeviceRowView(device: device)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color.asInset)
                .cornerRadius(11)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Device Row

struct DeviceRowView: View {
    @EnvironmentObject var viewModel: AudioViewModel
    let device: AudioDeviceModel

    var body: some View {
        Button(action: { viewModel.selectDevice(device) }) {
            HStack {
                Image(systemName: device.systemIcon)
                    .frame(width: 20)
                    .foregroundStyle(
                        device.id == viewModel.selectedDevice?.id
                            ? Color.asAccent
                            : Color.asLabelSecond
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body)
                        .foregroundColor(.asLabel)
                    Text("\(device.sampleRate) Hz")
                        .font(.caption)
                        .foregroundColor(.asLabelSecond)
                }
                Spacer()
                if device.id == viewModel.selectedDevice?.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.asAccent)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                device.id == viewModel.selectedDevice?.id
                    ? Color.asSelection
                    : Color.clear
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Device: \(device.displayName)")
        .accessibilityAddTraits(
            device.id == viewModel.selectedDevice?.id
                ? .isSelected
                : []
        )
    }
}

// MARK: - Error Banner

struct ErrorBannerView: View {
    @EnvironmentObject var viewModel: AudioViewModel

    var body: some View {
        if let error = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.asAccent)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.asLabel)
                    Spacer()
                }
                Button(action: { viewModel.retryInitialization() }) {
                    Text("Retry")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.asAccent)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(Color.asAccent.opacity(0.10))
            .cornerRadius(8)
            .padding()
            .accessibilityElement(children: .combine)
        }
    }
}
