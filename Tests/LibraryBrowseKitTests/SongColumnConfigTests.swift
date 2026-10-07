// The Songs column config's equality decides whether the glass column-header row shows
// (`isCustomized`). It is the standard library's `RawRepresentable` `==`, comparing JSON strings —
// and the JSON's key order was not stable, so an untouched config read as customized at random
// (S10.8 B2a: the Songs picture sheet grew a header row in about one render in four). The stored
// string is canonical now; these tests hold it there.

import LibraryBrowseKit
import Testing

@Suite("Songs column config — equality and persistence")
struct SongColumnConfigTests {
    @Test("The default config equals itself and is not customized, on every evaluation")
    func defaultIsStable() {
        // Repeated: the unsorted JSON differed between encodes, not only between processes.
        for _ in 0 ..< 200 {
            #expect(SongColumnConfig.default == SongColumnConfig.default)
            #expect(!SongColumnConfig.default.isCustomized)
        }
    }

    @Test("The stored string is canonical and round-trips to an equal config")
    func rawValueRoundTrips() {
        let config = SongColumnConfig.default
        #expect(config.rawValue == config.rawValue)
        #expect(SongColumnConfig(rawValue: config.rawValue) == config)
    }

    @Test("Showing a hidden column (or hiding a default one) customizes the config")
    func visibilityChangeCustomizes() {
        var shown = SongColumnConfig.default
        if let album = shown.entries.firstIndex(where: { $0.column == .album }) {
            shown.entries[album].visible = true
        }
        #expect(shown.isCustomized)
        #expect(shown.scrollingColumns.contains(.album))
    }

    @Test("A blob that doesn't cover the column catalog falls back (nil)")
    func structurallyInvalidBlobIsRejected() {
        #expect(SongColumnConfig(rawValue: #"[{"column":"title","visible":true}]"#) == nil)
        #expect(SongColumnConfig(rawValue: "not json") == nil)
    }
}
