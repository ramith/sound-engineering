import SwiftUI

// MARK: - EQ Tab View

struct EQTabView: View {
    @Environment(EQViewModel.self) private var eqViewModel
    @Environment(AudioViewModel.self) private var audioViewModel

    @State private var isUsingDiscreteSteps = false
    @State private var bannerVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 20) {
                FrequencyResponseCanvas(
                    eqViewModel: eqViewModel,
                    isUsingDiscreteSteps: isUsingDiscreteSteps
                )
                .frame(height: 400, alignment: .center)
                .frame(minWidth: 400)
                .padding(.top, 20)
                .padding(.horizontal)

                EQControlsSection(
                    eqViewModel: eqViewModel,
                    isUsingDiscreteSteps: $isUsingDiscreteSteps
                )
            }

            // Non-modal auto-recall banner (F3).
            if bannerVisible, let message = eqViewModel.recallBannerMessage {
                EQRecallBanner(message: message)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.asWindow)
        .animation(.easeInOut(duration: 0.3), value: bannerVisible)
        .onChange(of: isUsingDiscreteSteps) { _, newValue in
            eqViewModel.logInterpolationModeChange(newValue)
        }
        // F3: per-output recall wired here in the view — NOT via a cross-VM callback.
        .onChange(of: audioViewModel.selectedDevice) { _, newDevice in
            guard let device = newDevice else { return }
            eqViewModel.recallPresetForDevice(device)
        }
        .onChange(of: eqViewModel.recallBannerMessage) { _, message in
            guard message != nil else { return }
            bannerVisible = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                bannerVisible = false
                eqViewModel.recallBannerMessage = nil
            }
        }
    }
}

// MARK: - EQ Recall Banner

/// Transient non-modal banner shown when a preset is auto-recalled for a device.
private struct EQRecallBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.asAccent)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.asLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().stroke(Color.asHairline, lineWidth: 0.5))
    }
}
