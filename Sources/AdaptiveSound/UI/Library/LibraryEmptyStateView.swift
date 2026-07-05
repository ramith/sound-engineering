import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library empty / first-run / scanning / failed states (S9.4)

/// The Library grid's non-content states. First-run offers a folder-add CTA (reusing the
/// existing scan seam); scanning shows progress while the library fills in; failed surfaces
/// the error. (Two-phase determinate scan/metadata progress is an S9.6 polish item.)
struct LibraryEmptyStateView: View {
    enum Kind: Equatable {
        case firstRun
        case scanning
        case emptyLibrary // roots exist, scan finished, no playable audio found (review S1)
        case failed(String)
    }

    let kind: Kind
    @Environment(LibraryBrowseModel.self) private var model
    @State private var showFolderPicker = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                // The ONE shared add path (scan-only, never touches the queue) — same as the
                // sidebar footer + Music Folders popover, so behavior can't drift between them.
                if case let .success(url) = result { model.addFolder(url) }
            }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .firstRun:
            ContentUnavailableView {
                Label("No Music Yet", systemImage: "music.note.house")
            } description: {
                Text("Add a folder of music to start browsing your library.")
            } actions: {
                Button("Add Folder…") { showFolderPicker = true }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Color.accent)
            }
        case .scanning:
            VStack(spacing: DesignSystem.Spacing.medium) {
                ProgressView()
                Text("Scanning your library…")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
            }
        case .emptyLibrary:
            ContentUnavailableView {
                Label("No Music Found", systemImage: "music.note.list")
            } description: {
                Text("No playable audio was found in your library folders.")
            } actions: {
                Button("Add Folder…") { showFolderPicker = true }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Color.accent)
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't Load Library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        }
    }
}
