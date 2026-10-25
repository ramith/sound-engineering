import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - A Search page row and section header (R1.1-B, US-R1F-14)

/// One row of ⌘F's results — a song, an album, an artist, a genre or a playlist — on the Library rows'
/// card (`libraryRowChrome`, Songs' size): its cover (or its kind's glyph), its name, a line saying what
/// it is, and a song's length. A song selects on a click and plays on a double-click (as on Songs); any
/// other row opens on a click. One VoiceOver element: "Halo, song, Beyoncé — I Am... Sasha Fierce".
struct LibrarySearchRow: View {
    let item: LibrarySearchItem
    let results: LibrarySearchResults
    let isSelected: Bool
    let isKeyboardCursor: Bool
    let select: () -> Void
    let activate: () -> Void

    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        let content = Self.content(of: item, in: results)
        HStack(spacing: DesignSystem.Spacing.small) {
            art(content)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.label)
                    .lineLimit(1)
                Text(content.subtitle)
                    .font(DesignSystem.Font.trackSubtitle)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DesignSystem.Spacing.small)
            if let trailing = content.trailing {
                Text(trailing)
                    .font(DesignSystem.Font.monoSmall)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
        }
        .libraryRowChrome(isNowPlaying: false, isSelected: isSelected, isKeyboardCursor: isKeyboardCursor)
        .gesture(TapGesture(count: 2).onEnded(activate).exclusively(before: TapGesture().onEnded(tap)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(content.title), \(content.kind), \(content.subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate() }
    }

    /// A song selects on a single click (a double-click plays it); anything else opens.
    private func tap() {
        if case .song = item {
            select()
        } else {
            activate()
        }
    }

    private func art(_ content: Content) -> some View {
        let side = DesignSystem.SongsList.artwork
        return ArtworkThumbnail(key: content.artworkKey, pixelSide: side, model: model) {
            ZStack {
                DesignSystem.Color.card
                Image(systemName: content.symbol)
                    .font(.system(size: max(12, side * 0.42)))
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                .strokeBorder(DesignSystem.Color.hairline, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    // MARK: What a row shows

    /// A row's words and art.
    struct Content: Equatable {
        let title: String
        let subtitle: String
        let kind: String
        let trailing: String?
        let artworkKey: String?
        let symbol: String
    }

    /// What `item` shows, read from the results it came from.
    static func content(of item: LibrarySearchItem, in results: LibrarySearchResults) -> Content {
        switch item {
        case let .song(id):
            let song = results.songs.first { $0.id == id }
            let byLine = [song?.artistName, song?.albumName].compactMap { $0?.isEmpty == false ? $0 : nil }
            return Content(title: song?.title ?? "", subtitle: byLine.joined(separator: " — "), kind: "song",
                           trailing: song.map { formatDuration($0.durationSeconds) }, artworkKey: song?.artworkKey,
                           symbol: "music.note")
        case let .album(id):
            let album = results.albums.first { $0.id == id }
            return Content(title: album?.title ?? "", subtitle: "Album · \(album?.albumArtist ?? "")", kind: "album",
                           trailing: nil, artworkKey: album?.artworkKey, symbol: "square.stack")
        case let .artist(id):
            let artist = results.artists.first { $0.id == id }
            return Content(title: artist?.name ?? "",
                           subtitle: "Artist · \(FacetCountLabel.songs(count: artist?.trackCount ?? 0))",
                           kind: "artist", trailing: nil, artworkKey: artist?.artworkKey, symbol: "music.mic")
        case let .genre(id):
            let genre = results.genres.first { $0.id == id }
            return Content(title: genre?.name ?? "",
                           subtitle: "Genre · \(FacetCountLabel.songs(count: genre?.trackCount ?? 0))",
                           kind: "genre", trailing: nil, artworkKey: nil, symbol: "guitars")
        case let .playlist(id):
            let playlist = results.playlists.first { $0.id == id }
            return Content(title: playlist?.name ?? "",
                           subtitle: "Playlist · \(FacetCountLabel.songs(count: playlist?.entryCount ?? 0))",
                           kind: "playlist", trailing: nil, artworkKey: nil, symbol: "music.note.list")
        }
    }
}

/// A section's header on the Search page: its name and how many it found, and "Show All" — the tab,
/// filtered by the query — when the section shows only its first few.
struct LibrarySearchSectionHeader: View {
    let section: LibrarySearchSection
    let count: Int
    let showsAll: Bool
    let showAll: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xSmall) {
            Text(Self.title(section))
                .font(DesignSystem.Font.sectionTitle)
                .foregroundStyle(DesignSystem.Color.label)
                .accessibilityAddTraits(.isHeader)
            Text(count.formatted(.number))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .accessibilityLabel("\(count) found")
            Spacer(minLength: 0)
            if showsAll {
                Button("Show All", action: showAll)
                    .buttonStyle(.plain)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.accentText)
                    .accessibilityLabel("Show all \(count) \(Self.title(section).lowercased())")
            }
        }
        .padding(.horizontal, LibraryRowMetrics.horizontalPadding)
        .padding(.top, DesignSystem.Spacing.medium)
        .padding(.bottom, 6)
    }

    static func title(_ section: LibrarySearchSection) -> String {
        switch section {
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .genres: "Genres"
        case .playlists: "Playlists"
        }
    }
}
