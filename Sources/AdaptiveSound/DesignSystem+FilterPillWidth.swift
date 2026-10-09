import DesignTokenKit
import SwiftUI

// MARK: - Filter pill widths (S10.8 D2 — one token group for every host)

extension DesignSystem {
    /// The filter pill's width in each host that sizes it, in one group (it was split across
    /// `SongsList`, `LibraryCardHeader` literals and `QueueHeader`). The narrowest a host lets it get
    /// holds the whole placeholder (`SlotWidths`, SLOT-06); it grows to its ideal and no wider. The
    /// playlist picker gives it the sheet's full width, so it is not here.
    enum FilterPillWidth {
        /// The Library card header — Songs, Albums, Artists, Genres.
        case library
        /// The Now Playing queue header (`png/03`: 190 pt ideal).
        case queue

        var minimum: CGFloat {
            switch self {
            case .library: CGFloat(SlotWidths.libraryFilter)
            case .queue: CGFloat(SlotWidths.queueFilter)
            }
        }

        var ideal: CGFloat {
            switch self {
            case .library: 230
            case .queue: 190
            }
        }

        var maximum: CGFloat {
            switch self {
            case .library: 260
            case .queue: 190
            }
        }
    }
}

extension View {
    /// Size a filter pill for its host (`DesignSystem.FilterPillWidth`).
    func filterPillWidth(_ width: DesignSystem.FilterPillWidth) -> some View {
        frame(minWidth: width.minimum, idealWidth: width.ideal, maxWidth: width.maximum)
    }
}
