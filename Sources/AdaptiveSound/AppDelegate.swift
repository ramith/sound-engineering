import AppKit

// MARK: - App lifecycle delegate

/// Resident menu-bar behavior + clean engine teardown.
///
/// Closing the LAST window does NOT quit (the "minimize to the menu bar" model): the app drops
/// its Dock icon (`.accessory`) and lives on in the `MenuBarExtra`, playback continuing. A real
/// quit — ⌘Q or the menu-bar "Quit" — routes through `applicationShouldTerminate` (NOT through
/// `applicationShouldTerminateAfterLastWindowClosed`), which awaits the ordered engine teardown
/// before the process exits. Reopening from the menu-bar "Open" item restores the `.regular` app.
///
/// This reverses the earlier quit-on-last-window-close policy. That policy existed to avoid a
/// zombie re-initializing the engine on reopen; the real fix is `initializeEngine()` idempotency
/// (it now guards `!isEngineReady`), which lets the app safely outlive its window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Wired once the window appears (see AdaptiveSound.swift). Weak because the view model is
    /// owned by the App's `@State` for the whole process lifetime — it is still alive at quit.
    weak var audioViewModel: AudioViewModel?

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // Last window closed (the red traffic-light button): retreat to the menu bar — hide the
        // Dock icon and DO NOT quit. This delegate hook fires ONLY on last-window-close, never on
        // ⌘Q / the menu-bar Quit (those go straight to applicationShouldTerminate).
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Relaunch / Dock reopen: restore the normal Dock-visible app and let AppKit re-open a
        // window if none is visible. In `.accessory` there is no Dock icon, so the primary reopen
        // path is the menu-bar "Open" item (which uses `openWindow`); this covers the relaunch case.
        NSApp.setActivationPolicy(.regular)
        return !hasVisibleWindows
    }

    /// Defer termination until the engine teardown COMPLETES. `shutdown()` is async (the ordered
    /// stop → engine.shutdown P2-C sequence); doing it fire-and-forget means the process can be
    /// killed mid-teardown at quit → use-after-free of the C audio handles. `.terminateLater` +
    /// `reply(toApplicationShouldTerminate:)` blocks the quit until teardown finishes. Reached on
    /// ⌘Q AND the menu-bar Quit (both call `NSApp.terminate`); NOT on window-close (which retreats
    /// to the menu bar instead).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let audioViewModel else { return .terminateNow }
        Task { @MainActor in
            await audioViewModel.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
