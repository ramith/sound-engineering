import LibraryBrowseKit
import Testing

// MARK: - ThumbnailUpgrade (S10.8 D fix round — the cover cache never stays soft)

@Suite("ThumbnailUpgrade — an upgrade-only cover cache")
struct ThumbnailUpgradeTests {
    @Test("a Recently Played row's 56-px decode does not serve a 324-px grid tile: it re-decodes")
    func smallDecodeIsUpgraded() {
        let row = ThumbnailUpgrade.servesUpTo(decodedSide: 56, requested: 56)
        #expect(!ThumbnailUpgrade.serves(row, request: 324))
        let tile = ThumbnailUpgrade.servesUpTo(decodedSide: 324, requested: 324)
        #expect(ThumbnailUpgrade.replaces(cached: row, with: tile))
    }

    @Test("a bigger entry serves a smaller request; within 10% is close enough")
    func biggerServesSmaller() {
        #expect(ThumbnailUpgrade.serves(512, request: 56))
        #expect(ThumbnailUpgrade.serves(300, request: 324)) // 92.6%
        #expect(!ThumbnailUpgrade.serves(280, request: 324)) // 86.4%
    }

    @Test("a decode smaller than requested is the whole source: it serves every request")
    func wholeSourceServesAll() {
        let whole = ThumbnailUpgrade.servesUpTo(decodedSide: 300, requested: 512)
        #expect(whole == Int.max)
        #expect(ThumbnailUpgrade.serves(whole, request: 512))
        #expect(ThumbnailUpgrade.servesUpTo(decodedSide: 512, requested: 512) == 512)
    }

    @Test("upgrade only: a decode never replaces a bigger or equal entry; anything fills an empty slot")
    func neverDowngrades() {
        #expect(!ThumbnailUpgrade.replaces(cached: 324, with: 56))
        #expect(!ThumbnailUpgrade.replaces(cached: 324, with: 324))
        #expect(!ThumbnailUpgrade.replaces(cached: Int.max, with: 512))
        #expect(ThumbnailUpgrade.replaces(cached: nil, with: 56))
    }
}
