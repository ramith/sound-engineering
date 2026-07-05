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
    @Environment(AudioViewModel.self) private var audio
    @State private var showFolderPicker = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case let .success(url) = result {
                    audio.scanFolderIntoLibrary(url) // non-sandboxed (Developer-ID): no scoped-access dance
                }
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
                Button("Add Music Folder…") { showFolderPicker = true }
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
                Button("Add Another Folder…") { showFolderPicker = true }
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
