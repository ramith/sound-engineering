import LibraryBrowseKit
import Testing

// MARK: - CoverArrangement (S10.8 D5 — what a browse tile's art shows)

@Suite("CoverArrangement — mosaic, single cover or placeholder")
struct CoverArrangementTests {
    @Test("four or more keys: a 2×2 mosaic of the first four, in order")
    func mosaic() {
        #expect(CoverArrangement(keys: ["a", "b", "c", "d"]) == .mosaic(["a", "b", "c", "d"]))
        #expect(CoverArrangement(keys: ["a", "b", "c", "d", "e", "f"]) == .mosaic(["a", "b", "c", "d"]))
    }

    @Test("one to three keys: the first cover, full size — never a partial mosaic")
    func single() {
        #expect(CoverArrangement(keys: ["a"]) == .single("a"))
        #expect(CoverArrangement(keys: ["a", "b"]) == .single("a"))
        #expect(CoverArrangement(keys: ["a", "b", "c"]) == .single("a"))
    }

    @Test("no keys: the section's placeholder")
    func placeholder() {
        #expect(CoverArrangement(keys: []) == .placeholder)
    }
}
