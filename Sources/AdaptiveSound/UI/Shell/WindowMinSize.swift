import AppKit
import SwiftUI

/// Pins the host window's HARD minimum size at the AppKit layer.
///
/// `.windowResizability(.contentMinSize)` + a root `.frame(minHeight:)` did NOT reliably clamp
/// the flexible `AppShell` content — the window could still be dragged smaller than the shell,
/// clipping the pinned chrome (founder make-run, L2). Setting `NSWindow.minSize` directly is the
/// reliable macOS fix. `viewDidMoveToWindow` fires exactly when the backing view attaches to its
/// window, so the min is applied with correct timing (and re-applied on `updateNSView`).
struct WindowMinSize: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context _: Context) -> NSView {
        MinSizeView(minSize: NSSize(width: width, height: height))
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        let size = NSSize(width: width, height: height)
        (nsView as? MinSizeView)?.minSize = size
        nsView.window?.minSize = size
    }

    /// A zero-size, non-drawing NSView whose only job is to reach its window and set `minSize`.
    private final class MinSizeView: NSView {
        var minSize: NSSize {
            didSet { window?.minSize = minSize }
        }

        init(minSize: NSSize) {
            self.minSize = minSize
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.minSize = minSize
        }
    }
}
