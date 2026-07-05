import Foundation

// MARK: - Library drill-down routes (S9.4)

/// A data-driven destination pushed onto the Library detail `NavigationStack`. Kept
/// `Hashable` so `navigationDestination(for:)` is registered ONCE at the stack root and
/// pushes are `NavigationLink(value:)` (never `NavigationLink(destination:)`). Album
/// detail ships in S9.4; artist/genre/year details fill in over S9.5/S9.6.
enum LibraryRoute: Hashable {
    case album(Int64)
    case artist(Int64)
    case genre(Int64)
    case year(Int)
}
