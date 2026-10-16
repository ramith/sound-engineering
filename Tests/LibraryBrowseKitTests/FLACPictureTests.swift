import Foundation
@testable import LibraryScan
import Testing

// MARK: - The cover a FLAC carries, without FFmpeg (R1.1-A, FD-3)

/// AVFoundation reads a FLAC's Vorbis comments but not its PICTURE block, so with FFmpeg off by default
/// every FLAC album would lose its cover. `FLACPicture` reads the block in Swift — bounds-checked, the
/// metadata blocks only — and the same structure where Ogg Vorbis / Opus keep it (base64, in a
/// METADATA_BLOCK_PICTURE comment).
@Suite("FLAC PICTURE — the cover, read in Swift")
struct FLACPictureTests {
    /// A PICTURE block body (FLAC format, METADATA_BLOCK_PICTURE): big-endian fields.
    static func pictureBody(type: UInt32, mime: String, data: Data, description: String = "") -> Data {
        var body = Data()
        func u32(_ value: UInt32) {
            body.append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
                                     UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
        }
        u32(type)
        u32(UInt32(mime.utf8.count))
        body.append(contentsOf: Array(mime.utf8))
        u32(UInt32(description.utf8.count))
        body.append(contentsOf: Array(description.utf8))
        for _ in 0 ..< 4 {
            u32(64) // width, height, depth, colours: not read
        }
        u32(UInt32(data.count))
        body.append(data)
        return body
    }

    /// One metadata block: the last-block flag and type, a 24-bit length, the body.
    static func block(type: UInt8, last: Bool, body: Data) -> Data {
        let length = body.count
        return Data([(last ? 0x80 : 0) | type, UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF),
                     UInt8(length & 0xFF)]) + body
    }

    /// A FLAC file's head: an optional ID3v2 tag, "fLaC", STREAMINFO, then `blocks`, then a frame byte.
    static func flacFile(id3: Bool, blocks: [(type: UInt8, body: Data)]) -> Data {
        var file = Data()
        if id3 {
            // "ID3" v2.4, no flags, a syncsafe size of 20, then 20 bytes of tag.
            file.append(contentsOf: Array("ID3".utf8) + [4, 0, 0, 0, 0, 0, 20])
            file.append(Data(repeating: 0x41, count: 20))
        }
        file.append(contentsOf: Array("fLaC".utf8))
        file.append(block(type: 0, last: blocks.isEmpty, body: Data(repeating: 0, count: 34)))
        for (index, entry) in blocks.enumerated() {
            file.append(block(type: entry.type, last: index == blocks.count - 1, body: entry.body))
        }
        file.append(contentsOf: [0xFF, 0xF8]) // the first audio frame's sync
        return file
    }

    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 9, 9])

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flac-picture-\(UUID().uuidString).flac")
        try data.write(to: url)
        return url
    }

    @Test("a PICTURE block parses to its type, MIME and bytes; a truncated or overlong one reads as none")
    func parsesOneBlock() {
        let body = Self.pictureBody(type: 3, mime: "image/png", data: Self.png, description: "cover")
        #expect(FLACPicture.parse(body) == FLACPicture(type: 3, mime: "image/png", data: Self.png))
        #expect(FLACPicture.parse(body.dropLast()) == nil)
        var overlong = body
        overlong[4] = 0xFF // a MIME length far past the block
        #expect(FLACPicture.parse(overlong) == nil)
        #expect(FLACPicture.parse(Data()) == nil)
    }

    @Test("the front cover wins over another picture; an ID3 tag in front of the FLAC is skipped",
          arguments: [false, true])
    func readsTheFrontCover(id3: Bool) throws {
        let url = try write(Self.flacFile(id3: id3, blocks: [
            (type: 4, body: Data(repeating: 0, count: 8)), // VORBIS_COMMENT, skipped
            (type: 6, body: Self.pictureBody(type: 0, mime: "image/jpeg", data: Self.jpeg)),
            (type: 6, body: Self.pictureBody(type: 3, mime: "image/png", data: Self.png)),
        ]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FLACPicture.cover(inFileAt: url) == FLACPicture(type: 3, mime: "image/png", data: Self.png))
    }

    @Test("a file that is not a FLAC, or has no PICTURE, has no cover")
    func noCover() throws {
        let plain = try write(Self.flacFile(id3: false, blocks: [(type: 4, body: Data(count: 8))]))
        let notFLAC = try write(Data("OggS and more".utf8))
        defer {
            try? FileManager.default.removeItem(at: plain)
            try? FileManager.default.removeItem(at: notFLAC)
        }
        #expect(FLACPicture.cover(inFileAt: plain) == nil)
        #expect(FLACPicture.cover(inFileAt: notFLAC) == nil)
    }

    @Test("an Ogg METADATA_BLOCK_PICTURE comment is the same block, base64")
    func parsesTheOggComment() {
        let body = Self.pictureBody(type: 3, mime: "image/jpeg", data: Self.jpeg)
        #expect(FLACPicture(base64Comment: body.base64EncodedString())
            == FLACPicture(type: 3, mime: "image/jpeg", data: Self.jpeg))
        #expect(FLACPicture(base64Comment: "not base64 at all!") == nil)
    }
}
