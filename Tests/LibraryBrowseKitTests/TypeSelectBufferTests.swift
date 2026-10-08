import LibraryBrowseKit
import Testing

// MARK: - TypeSelectBuffer (S10.8 decision 20 — type-to-select on the browse grids)

@Suite("TypeSelectBuffer — the typed prefix and its first match")
struct TypeSelectBufferTests {
    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    // MARK: The prefix

    @Test("letters typed in quick succession build one prefix")
    func prefixGrows() {
        var buffer = TypeSelectBuffer()
        #expect(buffer.append("j", at: at(0)) == "j")
        #expect(buffer.append("a", at: at(0.3)) == "ja")
        #expect(buffer.append("z", at: at(1.2)) == "jaz") // 0.9 s after the last key, not the first
    }

    @Test("a pause longer than a second starts a new prefix")
    func pauseRestarts() {
        var buffer = TypeSelectBuffer()
        _ = buffer.append("j", at: at(0))
        #expect(buffer.append("k", at: at(1.5)) == "k")
    }

    @Test("a pause of exactly a second still continues the prefix")
    func timeoutBoundary() {
        var buffer = TypeSelectBuffer()
        _ = buffer.append("j", at: at(0))
        #expect(buffer.append("a", at: at(1)) == "ja")
    }

    // MARK: The match

    private let titles = ["Abbey Road", "Jazz at the Pawnshop", "Jazz", "Beyoncé", "Ｊａｐａｎ"]

    private func match(_ prefix: String) -> String? {
        TypeSelectBuffer.firstMatch(for: prefix, in: titles) { $0 }
    }

    @Test("the first title in display order that starts with the prefix")
    func firstInDisplayOrder() {
        #expect(match("jazz") == "Jazz at the Pawnshop")
        #expect(match("a") == "Abbey Road")
    }

    @Test("case, accents and width are ignored")
    func insensitive() {
        #expect(match("JAZZ") == "Jazz at the Pawnshop")
        #expect(match("beyonce") == "Beyoncé")
        #expect(match("japan") == "Ｊａｐａｎ")
    }

    @Test("only prefixes match — never a word inside the title")
    func prefixOnly() {
        #expect(match("road") == nil)
        #expect(match("azz") == nil)
    }

    @Test("an empty prefix or no match selects nothing")
    func noMatch() {
        #expect(match("") == nil)
        #expect(match("zz") == nil)
        #expect(TypeSelectBuffer.firstMatch(for: "a", in: [String]()) { $0 } == nil)
    }
}
