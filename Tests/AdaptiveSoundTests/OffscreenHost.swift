@testable import AdaptiveSound
import AppKit
import SwiftUI

// MARK: - A SwiftUI view hosted offscreen, for what only a live view tree shows

/// `view` in an `NSHostingView` inside a borderless window that is never ordered on screen — the picture
/// sheets' host (`SheetRenderer`). For what only SwiftUI itself decides: whether a view keeps its identity (its
/// `@State`) across an update, which environment its content sees, what it draws in an appearance. The test drives
/// the run loop with RigKit's `untilOnMainRunLoop`, waiting for the state it wants. (Pointer events sent to such a
/// window never reach a SwiftUI gesture, and it never becomes key, so a drag and key focus are out of its reach.)
@MainActor
final class OffscreenHost<Content: View> {
    private let window: NSWindow
    private let host: NSHostingView<Content>

    /// - Parameter appearance: the window's appearance (`.aqua`, `.darkAqua`), which the view's color scheme follows.
    init(_ view: Content, size: NSSize = NSSize(width: 320, height: 120), appearance: NSAppearance.Name? = nil) {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.appearance = appearance.flatMap(NSAppearance.init(named:))
        host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    /// What the view draws now, as RGBA bytes at 1x (the hosting view's own drawing, as the sheets take it).
    func pixels() -> [UInt8] {
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.bitmapData else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh))
    }

    /// Take the view down (its `onDisappear`s run), so nothing outlives the test.
    func close() {
        window.contentView = nil
    }
}
