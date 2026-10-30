@testable import AdaptiveSound
import AppKit
import SwiftUI

// MARK: - A SwiftUI view hosted offscreen, for what only a live view tree shows

/// `view` in an `NSHostingView` inside a borderless window that is never ordered on screen — the picture
/// sheets' host (`SheetRenderer`), without the picture. For what only SwiftUI itself decides: whether a view
/// keeps its identity (its `@State`) across an update, which environment its content sees. The test drives
/// the run loop with RigKit's `untilOnMainRunLoop`, waiting for the state it wants. (Pointer events sent to
/// such a window never reach a SwiftUI gesture, so a drag is out of its reach.)
@MainActor
final class OffscreenHost<Content: View> {
    private let window: NSWindow

    init(_ view: Content, size: NSSize = NSSize(width: 320, height: 120)) {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    /// Take the view down (its `onDisappear`s run), so nothing outlives the test.
    func close() {
        window.contentView = nil
    }
}
