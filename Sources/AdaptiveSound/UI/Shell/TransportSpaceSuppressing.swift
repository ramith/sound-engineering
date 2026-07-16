import SwiftUI

// MARK: - suppressesTransportSpace (S10.3 focus-audit — the one-place gate wiring)

/// Binds a text field's `@FocusState` AND wires the global transport-Space gate in ONE place:
/// applies `.focused`, mirrors focus into `KeyboardTransportFocus.isTextEntryFocused`, and clears
/// it on teardown. Previously every field hand-wired the `.focused` + `.onChange` + `.onDisappear`
/// trio; a field that forgot either half silently re-broke space-typing (S4 SW1) or left the gate
/// stuck on. As a single modifier the half-wired state is unrepresentable: a field either applies
/// it (atomic + correct) or doesn't. (Focus-audit MAJOR-1; the fix the sidebar comment promised.)
private struct TransportSpaceSuppressing: ViewModifier {
    @FocusState.Binding var focused: Bool
    @Environment(KeyboardTransportFocus.self) private var gate

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, isFocused in gate.isTextEntryFocused = isFocused }
            .onDisappear { gate.isTextEntryFocused = false }
    }
}

extension View {
    /// Focus this text field via `focused` AND suppress the global Space play/pause accelerator while
    /// it holds focus (so a typed space inserts a space instead of toggling playback). Replaces the
    /// per-field `.focused` + `.onChange` + `.onDisappear` gate trio. Apply INSTEAD of a separate
    /// `.focused($…)`; additional `.onChange(of:)` (e.g. an inline-rename blur-commit) still compose.
    func suppressesTransportSpace(while focused: FocusState<Bool>.Binding) -> some View {
        modifier(TransportSpaceSuppressing(focused: focused))
    }
}
