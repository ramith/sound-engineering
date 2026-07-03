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
    /// Wired once the window appears (see AdaptiveSound.swift). Weak because the view model is
    /// owned by the App's `@State` for the whole process lifetime — it is still alive at quit.
    weak var audioViewModel: AudioViewModel?

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    /// Defer termination until the engine teardown COMPLETES. `shutdown()` is async (the ordered
    /// stop → engine.shutdown P2-C sequence); doing it fire-and-forget (as `ContentView.onDisappear`
    /// used to) means the process can be killed mid-teardown at quit → use-after-free of the C
    /// audio handles. `.terminateLater` + `reply(toApplicationShouldTerminate:)` blocks the quit
    /// until teardown finishes, guaranteeing the ordering. Reached on ⌘Q AND on last-window-close
    /// (which routes here via `applicationShouldTerminateAfterLastWindowClosed`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let audioViewModel else { return .terminateNow }
        Task { @MainActor in
            await audioViewModel.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
