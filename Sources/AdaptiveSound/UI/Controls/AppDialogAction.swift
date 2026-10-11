// MARK: - App dialog action (S10.8 EQ fix — the founder's "match the UI theme")

/// A dialog's primary action (`AppDialog`): its title, its tone and whether it can act now. Cancel is
/// the dialog's own, always present.
struct AppDialogAction {
    enum Tone {
        /// The teal pill: Save, Rename.
        case accent
        /// The destructive pill — the error family's tint and text: Delete.
        case destructive
    }

    let title: String
    var tone: Tone = .accent
    /// False while the action can't act (Save with a name that won't do): the pill shows disabled and
    /// Return does nothing.
    var isEnabled = true
    let perform: () -> Void
}
