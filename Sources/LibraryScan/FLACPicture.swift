// FLACPicture — the cover a FLAC file carries in its PICTURE metadata block, read in Swift (R1.1-A,
// founder decision FD-3).
//
// AVFoundation reads a FLAC's Vorbis comments (`vorb/…`) but exposes no PICTURE block, and FFmpeg —
// which did read it — is now an opt-in, off by default. Without this every FLAC album would lose its
// cover. The block is simple and its layout fixed (FLAC format, METADATA_BLOCK_PICTURE: big-endian
// u32 fields — picture type, MIME length + MIME, description length + description, width, height,
// depth, colours, data length + data), so it is read here, in memory-safe Swift, from the file's
// metadata blocks only: an ID3v2 tag some taggers put in front of "fLaC" is skipped, every length is
// checked against what is there, and nothing past `maxBytes` is read. Ogg Vorbis and Opus keep the
// same block, base64, in a METADATA_BLOCK_PICTURE comment, which AVFoundation does expose.

import Foundation

struct FLACPicture: Equatable {
    /// The picture's role (FLAC / ID3 APIC types): 3 is the front cover.
    let type: UInt32
    let mime: String
    let data: Data

    /// The front cover's type.
    static let frontCover: UInt32 = 3

    /// The most this reads from a file's metadata blocks (the art cap plus room for the rest).
    static let maxBytes = MetadataExtractor.maxArtBytes + 1024 * 1024

    /// One PICTURE block body, or nil when a length runs past the block or the picture is empty.
    static func parse(_ body: Data) -> FLACPicture? {
        var reader = BigEndianReader(body)
        guard let type = reader.u32(), let mimeLength = reader.u32(), let mime = reader.bytes(mimeLength),
              let descriptionLength = reader.u32(), reader.skip(descriptionLength),
              reader.skip(16), // width, height, depth, colours
              let dataLength = reader.u32(), dataLength > 0, let data = reader.bytes(dataLength)
        else { return nil }
        return FLACPicture(type: type, mime: String(bytes: mime, encoding: .utf8) ?? "", data: data)
    }

    /// The block from an Ogg METADATA_BLOCK_PICTURE comment (base64), or nil.
    init?(base64Comment: String) {
        guard let body = Data(base64Encoded: base64Comment, options: .ignoreUnknownCharacters),
              let picture = Self.parse(body) else { return nil }
        self = picture
    }

    init(type: UInt32, mime: String, data: Data) {
        self.type = type
        self.mime = mime
        self.data = data
    }

    /// The cover of the FLAC file at `url`: its front cover, else its first picture; nil when it is not a
    /// FLAC (after an optional ID3v2 tag), has no PICTURE block, or can't be read.
    static func cover(inFileAt url: URL) -> FLACPicture? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var file = BoundedFile(handle: handle, limit: maxBytes)
        guard file.skipID3Tag(), file.next(4)?.elementsEqual(Array("fLaC".utf8)) == true else { return nil }
        var pictures: [FLACPicture] = []
        var last = false
        while !last, let header = file.next(4).map([UInt8].init) {
            last = header[0] & 0x80 != 0
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            guard let body = file.next(length) else { break }
            if header[0] & 0x7F == 6, let picture = parse(body) {
                pictures.append(picture)
            }
        }
        return pictures.first { $0.type == frontCover } ?? pictures.first
    }
}

/// A file read from its start in exact pieces, never past `limit` bytes in all.
private struct BoundedFile {
    let handle: FileHandle
    let limit: Int
    private var read = 0

    init(handle: FileHandle, limit: Int) {
        self.handle = handle
        self.limit = limit
    }

    /// The next `count` bytes, or nil at the end, past the limit, or on a read error.
    mutating func next(_ count: Int) -> Data? {
        guard count >= 0, read + count <= limit,
              let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        read += count
        return data
    }

    /// Step over an ID3v2 tag at the start, if there is one: a 10-byte header ("ID3", version, flags,
    /// and a syncsafe size — 7 bits a byte), plus a 10-byte footer when flag 0x10 is set. With no tag
    /// the file is back at its start. False when the tag runs past the file or the file can't be read.
    mutating func skipID3Tag() -> Bool {
        guard let header = next(10).map([UInt8].init) else { return false }
        guard header.starts(with: Array("ID3".utf8)) else {
            guard (try? handle.seek(toOffset: 0)) != nil else { return false }
            read = 0
            return true
        }
        let size = header[6 ... 9].reduce(0) { $0 << 7 | Int($1 & 0x7F) } + (header[5] & 0x10 != 0 ? 10 : 0)
        return next(size) != nil
    }
}

/// Reads big-endian fields from a block, refusing any read past its end.
private struct BigEndianReader {
    private let buffer: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        buffer = [UInt8](data)
    }

    mutating func u32() -> UInt32? {
        take(4).map { $0.reduce(0) { $0 << 8 | UInt32($1) } }
    }

    mutating func bytes(_ count: UInt32) -> Data? {
        take(Int(count)).map { Data($0) }
    }

    mutating func skip(_ count: UInt32) -> Bool {
        take(Int(count)) != nil
    }

    private mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
        guard count <= buffer.count - offset else { return nil }
        defer { offset += count }
        return buffer[offset ..< offset + count]
    }
}
