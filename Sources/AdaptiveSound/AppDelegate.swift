import AppKit

// MARK: - App lifecycle delegate

/// Quits the app when its last (and only) window closes.
///
/// A SwiftUI `WindowGroup` app keeps running after its last window closes by default (the
/// Safari/Xcode model). AdaptiveSound is a single-window player AND binds the engine lifecycle
/// to the window (`ContentView` starts the engine in `.task`, tears it down in `.onDisappear`),
/// so "keep running windowless" left a zombie process that re-initialized the engine on reopen.
/// Terminating on last-window-close gives exactly one clean shutdown and matches user
/// expectation (the close button quits). `applicationShouldTerminateAfterLastWindowClosed` is
/// the supported hook for this; returning true then routes through the normal terminate path.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
