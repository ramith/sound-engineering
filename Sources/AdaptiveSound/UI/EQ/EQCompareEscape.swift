import AppKit
import SwiftUI

// MARK: - Esc releases a held Compare, wherever key focus is (Sprint EQ, EQ3; review fix round)

extension View {
    /// While Compare is held, Esc anywhere in the app lets go — with key focus on the pill, the graph,
    /// the rail, the chrome or nowhere at all, which a key handler on the tab could never all reach.
    /// A local event monitor (as `KeyboardFocusVisibility`), installed only while Compare is held and
    /// removed when it is released or the screen goes away; it consumes the Esc that released Compare
    /// and passes every other key on.
    func releasesCompareOnEscape(_ eq: EQViewModel) -> some View {
        modifier(CompareEscapeRelease(eq: eq))
    }
}

/// `releasesCompareOnEscape(_:)`: the monitor, held while Compare is.
private struct CompareEscapeRelease: ViewModifier {
    let eq: EQViewModel

    /// The installed monitor's token, while Compare is held.
    @State private var monitor: Any?

    /// The character Esc types.
    private nonisolated static let escape = "\u{1B}"

    func body(content: Content) -> some View {
        content
            .onChange(of: eq.isComparing, initial: true) { _, comparing in
                if comparing {
                    install()
                } else {
                    remove()
                }
            }
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @Sendable [weak eq] event in
            guard event.charactersIgnoringModifiers == Self.escape else { return event }
            // Local monitors run on the main thread (inside `NSApplication.sendEvent`).
            let released = MainActor.assumeIsolated {
                guard let eq, eq.isComparing else { return false }
                eq.endCompare()
                return true
            }
            return released ? nil : event
        }
    }

    private func remove() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
