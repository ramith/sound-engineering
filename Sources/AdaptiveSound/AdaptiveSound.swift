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
        VStack {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Adaptive Sound")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Audio Enhancement Engine")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
                .font(.headline)

            HStack {
                Image(
                    systemName: viewModel.isEngineReady
                        ? "circle.fill"
                        : "circle"
                )
                .foregroundColor(
                    viewModel.isEngineReady
                        ? .green
                        : .orange
                )
                Text(
                    viewModel.isEngineReady
                        ? "Audio Engine Ready"
                        : "Initializing..."
                )
                .font(.system(.body, design: .monospaced))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
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
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(device.displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                HStack(spacing: 12) {
                    Text("\(device.sampleRate) Hz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(device.bufferFrameSize) frames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
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
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text("\(device.sampleRate) Hz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if device.id == viewModel.selectedDevice?.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                device.id == viewModel.selectedDevice?.id
                    ? Color.blue.opacity(0.15)
                    : Color(nsColor: .controlBackgroundColor)
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
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.body)
                    Spacer()
                }
                Button(action: { viewModel.retryInitialization() }) {
                    Text("Retry")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .padding()
            .accessibilityElement(children: .combine)
        }
    }
}
