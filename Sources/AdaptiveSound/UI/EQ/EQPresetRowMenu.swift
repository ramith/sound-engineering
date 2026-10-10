import EQEditKit
import SwiftUI

// MARK: - EQ preset row menu (Sprint EQ, EQ3 + EQ4)

/// What a preset row offers beyond choosing it — in its context menu, and as VoiceOver actions:
/// - **Bring back edits** a switch set aside (decision 27), with no time limit (WCAG 2.2.1);
/// - on the row playing now, **"Use on <output>"** — the header's pin, as a checked item (decision 28);
/// - on one of My Presets, **Rename…** and **Delete…** (Return and ⌫ in the list do the same).
struct EQPresetRowMenu: View {
    /// The preset whose edits were set aside, and bringing them back.
    var bringBack: (preset: String, action: () -> Void)?
    /// The current output and its pin (on the row playing now), and pressing the pin.
    var pin: EQOutputPin?
    var togglePin: () -> Void = {}
    var rename: (() -> Void)?
    var delete: (() -> Void)?
    /// As VoiceOver actions: the pin is a button named for what it does (an action has no checkmark).
    var forVoiceOver = false

    var body: some View {
        if let bringBack {
            Button("Bring Back Edits to \(bringBack.preset)", action: bringBack.action)
        }
        if let pin {
            let output = pin.output.name
            if forVoiceOver {
                Button(pin.isPinned ? "Unpin from \(output)" : "Use on \(output)", action: togglePin)
            } else {
                Toggle("Use on \(output)", isOn: pinBinding)
            }
        }
        if let rename {
            Button("Rename…", action: rename)
        }
        if let delete {
            Button("Delete…", role: .destructive, action: delete)
        }
    }

    /// The same items as VoiceOver actions.
    var voiceOverActions: EQPresetRowMenu {
        var actions = self
        actions.forVoiceOver = true
        return actions
    }

    /// The pin as a checked menu item: on while the output plays a pin; choosing it presses the pin.
    private var pinBinding: Binding<Bool> {
        Binding(get: { pin?.isPinned ?? false }, set: { _ in togglePin() })
    }
}
