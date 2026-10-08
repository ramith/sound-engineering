import AppKit
import SwiftUI

// MARK: - Keyboard focus visibility (S10.8 A-review)

/// Whether keyboard focus should be DRAWN right now — the `:focus-visible` rule for the custom
/// lists' cursor ring (`keyboardCursorRing`, A3). The lists still take key focus at once
/// (`.defaultFocus`, a row click) so the arrows work without a Tab first; only the ring waits
/// until the user actually drives the window from the keyboard.
///
/// One app-wide LOCAL event monitor (the App owns this object, so there is one per app): a
/// focus-navigation key — Tab / ⇧Tab, an arrow, Home / End, Page Up / Down, without ⌘ (so the
/// ⌘← / ⌘→ track skips don't count) — switches to keyboard mode; any mouse-down switches back.
/// The lists read the result as the plain `showsKeyboardFocus` environment Bool, published at
/// the window root by `publishesKeyboardFocusVisibility(_:)`.
///
/// System "Keyboard navigation" (Full Keyboard Access) is deliberately NOT an input: it governs
/// what Tab can reach, not whether focus is drawn — the browser `:focus-visible` precedent. It
/// used to force the ring on permanently, so with FKA on a clicking user always saw a ring on a
/// row they never chose (and Delete acted on it — A break-it). An FKA user who navigates by
/// Tab or the arrows switches to keyboard mode like anyone else, and sees the ring then.
@MainActor
@Observable
final class KeyboardFocusVisibility {
    /// Draw keyboard focus: the last input that could move focus was a navigation key, not a
    /// click.
    private(set) var showsFocus = false

    @ObservationIgnored private var monitor: Any?

    /// Installs the monitor. Idempotent — every window root calls it, one monitor results.
    func start() {
        guard monitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitor = NSEvent.addLocalMonitorForEvents(matching: events) { @Sendable [weak self] event in
            let keyboardDriven = Self.inputMode(after: event)
            // Local monitors run on the main thread (inside `NSApplication.sendEvent`).
            MainActor.assumeIsolated { self?.record(keyboardDriven: keyboardDriven) }
            return event // observe only — never consume
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    isolated deinit {
        stop()
    }

    /// `true` for a focus-navigation key, `false` for a mouse-down, `nil` for anything else (a
    /// typed character, a ⌘ shortcut) — which leaves the mode unchanged.
    private nonisolated static func inputMode(after event: NSEvent) -> Bool? {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return false
        case .keyDown:
            guard !event.modifierFlags.contains(.command), let key = event.specialKey else { return nil }
            let navigationKeys: [NSEvent.SpecialKey] = [
                .tab, .backTab, .upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end, .pageUp, .pageDown,
            ]
            return navigationKeys.contains(key) ? true : nil
        default:
            return nil
        }
    }

    /// Writes only on a change — an `@Observable` write invalidates its readers even when equal.
    private func record(keyboardDriven: Bool?) {
        if let keyboardDriven, keyboardDriven != showsFocus {
            showsFocus = keyboardDriven
        }
    }
}

extension EnvironmentValues {
    /// Draw keyboard focus (see `KeyboardFocusVisibility`). Read by the custom-list and grid
    /// containers (Songs, the queue, the playlist detail, the Library rail, the browse grids),
    /// which pass their rows a plain `isKeyboardCursor` Bool — rows stay environment-free — and
    /// by the controls that hold focus themselves (`IconChip`). Defaults to
    /// `false`, which is what the debug picture-sheet renderer draws.
    @Entry var showsKeyboardFocus = false
}
