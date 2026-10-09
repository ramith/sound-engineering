import SwiftUI

// MARK: - suppressesTransportSpace (S10.3 focus-audit — the one-place gate wiring)

/// Binds a text field's focus AND wires the global transport-Space gate in ONE place: applies
/// `.focused`, files the field's own token with `KeyboardTransportFocus` while it holds focus, and
/// withdraws it on teardown. Previously every field hand-wired the `.focused` + `.onChange` +
/// `.onDisappear` trio; a field that forgot either half silently re-broke space-typing (S4 SW1) or
/// left the gate stuck on. As a single modifier the half-wired state is unrepresentable: a field
/// either applies it (atomic + correct) or doesn't. (Focus-audit MAJOR-1.)
private struct TransportSpaceGate: ViewModifier {
    /// The field holds key focus.
    let isFocused: Bool

    @Environment(KeyboardTransportFocus.self) private var gate
    /// This field's token — its own entry in the gate, so another field's focus change never
    /// clears it.
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isFocused) { _, focused in gate.field(token, isFocused: focused) }
            .onDisappear { gate.field(token, isFocused: false) }
    }
}

extension View {
    /// Focus this text field via `focused` AND suppress the global Space play/pause accelerator while
    /// it holds focus (so a typed space inserts a space instead of toggling playback). Replaces the
    /// per-field `.focused` + `.onChange` + `.onDisappear` gate trio. Apply INSTEAD of a separate
    /// `.focused($…)`; additional `.onChange(of:)` (e.g. an inline-rename blur-commit) still compose.
    func suppressesTransportSpace(while focused: FocusState<Bool>.Binding) -> some View {
        self.focused(focused)
            .modifier(TransportSpaceGate(isFocused: focused.wrappedValue))
    }

    /// The same, for a field that is one value of its host's focus (`FilterPill`: `.filter` of a
    /// `CardFocus`): the field holds focus while `focus` equals `value`.
    func suppressesTransportSpace<Value: Hashable>(while focus: FocusState<Value?>.Binding,
                                                   equals value: Value) -> some View {
        focused(focus, equals: value)
            .modifier(TransportSpaceGate(isFocused: focus.wrappedValue == value))
    }
}
