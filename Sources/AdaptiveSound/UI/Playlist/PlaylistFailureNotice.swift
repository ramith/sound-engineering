import SwiftUI

// MARK: - A playlist action's failure (S10.8 E4 — the app's themed dialog)

/// "Couldn’t Complete That" — a playlist action that failed (Locate, Remove Missing, saving a new order),
/// as a notice in the app's themed dialog (`AppDialog`): the reason, and one OK that Return and Esc both
/// press. A transient notice, never the page's load-error state (F review).
struct PlaylistFailureNotice: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        AppDialog(notice: "Couldn’t Complete That", message: message, dismiss: dismiss)
    }
}
