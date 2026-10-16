import Foundation
import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Music Folders section (S9 IA → S10.8 inline rail section)

/// The Library's folder list with a per-root remove (confirmed in the app's themed dialog,
/// `MusicFolderRemoveDialog`). Rendered inline in the Twin Panels navigation rail (`LibrarySidebar`),
/// under the "Music Folders" section header, as plain rows inside the rail card's OWN ScrollView
/// (S10.8 PR-C retired the earlier footer accordion, so a nested scroll here would fight the card's
/// scroll). Adding lives on the section header's "+" — NOT here — kept there for the one-click add
/// UX (§6).
///
/// Each row's one caption line under its path (`MusicFolderStatus`, LibraryBrowseKit): "Scanning…"
/// while a scan walks it, or — for a PAUSED folder, whose last walk was refused so its songs are kept —
/// a short reason, with the folder glyph turned into a question mark and a tooltip (R1.1-A, KI-LIB-02;
/// founder 2026-10-15). `.task`/`.onChange` refresh `model.roots` and that line while the rail is
/// mounted (i.e. while the Library tab is open); a pause shows the moment the library records it.
struct MusicFoldersSection: View {
    @Environment(LibraryBrowseModel.self) private var model
    @Environment(LibraryModel.self) private var library
    @State private var removeTarget: LibraryFolder?

    var body: some View {
        Group {
            if model.roots.isEmpty {
                Text("No folders in your library yet. Use ＋ above to add one.")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Plain VStack (no inner ScrollView): the rows are items in the rail card's own
                // ScrollView now (S10.8 inline folders), so a nested scroll would fight it.
                VStack(spacing: 0) {
                    ForEach(model.roots) { root in
                        rootRow(root)
                        if root.id != model.roots.last?.id {
                            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        // Align with the rail's nav-row content inset (S10.8 inline folders).
        .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .task { await model.loadRoots() }
        // Re-read as scans/adds/removes land: a freshly-added root (and its per-row "Scanning…"
        // hint) appears once its scan starts; libraryRevision covers completion.
        .onChange(of: library.scanProgress?.folderID) { _, _ in Task { await model.loadRoots() } }
        .onChange(of: library.libraryRevision) { _, _ in Task { await model.loadRoots() } }
        // The app's themed dialog, as a sheet (the window's own modality), not the system alert.
        .sheet(item: $removeTarget) { root in
            MusicFolderRemoveDialog(path: abbreviatedPath(root.path), remove: { confirmRemove(root) },
                                    cancel: cancelRemove)
        }
    }

    /// Remove: close the dialog, then let the folder go — its files stay on disk.
    private func confirmRemove(_ root: LibraryFolder) {
        removeTarget = nil
        Task { await model.removeFolder(id: root.id) }
    }

    private func cancelRemove() {
        removeTarget = nil
    }

    private func rootRow(_ root: LibraryFolder) -> some View {
        let status = MusicFolderStatus(isScanning: model.scanningRootID == root.id,
                                       pausedBy: library.reconcileState[root.id]?.pauseReason)
        let isPaused = status?.isPaused == true
        return HStack(spacing: DesignSystem.Spacing.small) {
            // The glyph, the path and the status line are ONE VoiceOver element — "~/Music, Not found
            // — is its drive connected?" — the caption read as part of the row; the glyph is hidden
            // (the caption says it in words). The Remove button stays its own element (below). The glyph
            // sits on the path's line, however many lines the reason wraps to.
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
                Image(systemName: isPaused ? "folder.badge.questionmark" : "folder")
                    .foregroundStyle(isPaused ? DesignSystem.Color.statusWarningText
                        : DesignSystem.Color.labelSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(abbreviatedPath(root.path))
                        .font(DesignSystem.Font.body)
                        .foregroundStyle(DesignSystem.Color.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let status {
                        // Wraps rather than truncates: a cut-off reason would not say why.
                        Text(status.caption)
                            .font(DesignSystem.Font.caption)
                            .foregroundStyle(DesignSystem.Color.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .help(isPaused ? MusicFolderStatus.pausedHelp : "")
            Spacer(minLength: DesignSystem.Spacing.small)
            Button {
                removeTarget = root
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .help("Remove from Library")
            .accessibilityLabel("Remove \(abbreviatedPath(root.path)) from library")
        }
        // A one-line row stays 34 pt; a row with a status line keeps room at both dividers.
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .frame(minHeight: 34)
        // `.contain` (not `.combine`): keep the Remove button a first-class, directly-activatable
        // VoiceOver element rather than demoting it to an Actions-rotor custom action (review S3).
        .accessibilityElement(children: .contain)
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
