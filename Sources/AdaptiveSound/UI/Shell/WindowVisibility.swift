import AppKit
import SwiftUI

// MARK: - Whether any of the window can be seen (council C-52)

extension EnvironmentValues {
    /// Whether any of this view's window can be seen: `false` while it is minimised, hidden, fully
    /// covered or on another Space (`NSWindow.occlusionState`). Live visuals stop drawing then
    /// (`LiveTimeline`). Set once at the window's root (`readsWindowVisibility()`); `true` where no
    /// window says otherwise.
    @Entry var windowIsVisible = true
}

extension View {
    /// Tell the views in this window whether any of it can be seen (`windowIsVisible`). Apple, on the
    /// occlusion notification: "use this notification to increase responsiveness and save power, by
    /// halting any expensive calculations that the user can not see". Apply once, at the root.
    func readsWindowVisibility() -> some View {
        modifier(WindowVisibilityModifier())
    }
}

private struct WindowVisibilityModifier: ViewModifier {
    @State private var isVisible = true

    func body(content: Content) -> some View {
        content
            .environment(\.windowIsVisible, isVisible)
            .background(WindowVisibilityReader(isVisible: $isVisible))
    }
}

/// A zero-size, non-drawing view that follows its window's occlusion state.
private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context _: Context) -> NSView {
        OcclusionView { visible in
            if isVisible != visible {
                isVisible = visible
            }
        }
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class OcclusionView: NSView {
        private let report: (Bool) -> Void
        private var observer: NSObjectProtocol?

        init(report: @escaping (Bool) -> Void) {
            self.report = report
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        isolated deinit {
            observer.map(NotificationCenter.default.removeObserver)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportVisibility() }
            }
            // After this update pass: SwiftUI state must not change while it lays the window out.
            DispatchQueue.main.async { [weak self] in self?.reportVisibility() }
        }

        private func reportVisibility() {
            guard let window else { return }
            report(window.occlusionState.contains(.visible))
        }
    }
}
