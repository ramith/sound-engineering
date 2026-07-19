import Foundation

// MARK: - Tab Selection

enum TabSelection: String, CaseIterable {
    case nowPlaying = "Now Playing"
    case library = "Library"
    case eq = "EQ"
    case monitoring = "Monitoring"
    case settings = "Settings"

    var id: String {
        rawValue
    }
    // No `icon`: the realigned tab strip (S10.8 PR B) is text-only capsules — the old
    // per-tab SF Symbols were for the retired segmented Picker. Re-add with a consumer if
    // a future surface (e.g. a menu) needs tab glyphs.
}
