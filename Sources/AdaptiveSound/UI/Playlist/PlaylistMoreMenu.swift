import SwiftUI

// MARK: - Playlist ⋯ menu (S10.8 E4 — the playlist header's third pill)

/// The playlist header's ⋯: Play Next and Add to Queue for the whole playlist, and, while some of its
/// files are missing, Remove Missing… (the page confirms it; off during a scan, when files flicker
/// "missing"). Its label is a header pill (`HeaderPillFace`), drawn as a real view (`pillMenuStyle`),
/// with the app's keyboard ring; VoiceOver reads it as "More".
struct PlaylistMoreMenu: View {
    /// Asks to remove the entries whose files are missing.
    let removeMissing: () -> Void

    @Environment(PlaylistsModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button("Play Next", action: playNext)
            Button("Add to Queue", action: addToQueue)
            if model.missingEntryCount > 0 {
                Divider()
                Button("Remove \(model.missingEntryCount.formatted(.number)) Missing…", role: .destructive,
                       action: removeMissing)
                    .disabled(model.isLibraryPopulating)
            }
        } label: {
            HeaderPillFace(content: Label("More", systemImage: "ellipsis").labelStyle(.iconOnly), tone: .neutral,
                           isHovered: isHovered, isPressed: false)
        }
        .pillMenuStyle()
        .controlFocusRing(around: Capsule(style: .circular))
        .onHover { isHovered = $0 }
        .help("More")
        // Outermost, so VoiceOver reads no hint — not the tooltip a second time (the `IconChip` rule).
        .accessibilityHint("")
    }

    private func playNext() {
        model.playPlaylistNext()
    }

    private func addToQueue() {
        model.appendPlaylist()
    }
}
