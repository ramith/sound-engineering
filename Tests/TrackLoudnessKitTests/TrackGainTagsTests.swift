// TAGREAD — the ReplayGain 2.0 / R128 tag reader (R1.1-B W5, lane 3-A; US-R1F-10 item 4): FLAC and Ogg Vorbis
// comments (AVFoundation's `vorb/…`), ID3 `TXXX` user frames (as MP3s carry them; here in a WAV's `id3 ` chunk,
// which AVFoundation reads the same way), and MP4 freeform `----:com.apple.iTunes:…` atoms (its `itlk/…`). Names
// match in any case. The fixtures are made at run time (Apple's encoders, then the tags written in), under
// test-data/.

import AVFoundation
import Foundation
import Testing
@testable import TrackLoudnessKit

@Suite("TrackGainTags — ReplayGain 2.0 and R128 from FLAC, ID3 and MP4", .timeLimit(.minutes(2)))
struct TrackGainTagsTests {
    @Test("TAGREAD-01: FLAC Vorbis comments, in lower case, with an R128 album gain")
    func flac() async throws {
        let url = try await TagFixtures.flac(named: "tags-flac", comments: [
            "replaygain_track_gain=-7.53 dB", "replaygain_track_peak=0.988", "R128_ALBUM_GAIN=-1280",
        ])
        let tags = await TrackGainTags.read(from: url)
        #expect(tags == TrackGainTags(replayGainTrack: -7.53, replayGainTrackPeak: 0.988, r128Album: -1280))
    }

    @Test("TAGREAD-02: ID3 TXXX frames named by their description, '+' signs and 'dB' read")
    func id3() async throws {
        let url = try TagFixtures.wavWithID3(named: "tags-id3", frames: [
            ("REPLAYGAIN_TRACK_GAIN", "+2.50 dB"), ("REPLAYGAIN_TRACK_PEAK", "0.311896"),
            ("replaygain_album_gain", "+3.40 dB"), ("replaygain_album_peak", "0.589856"), ("COMMENT", "-9 dB"),
        ])
        let tags = await TrackGainTags.read(from: url)
        #expect(tags == TrackGainTags(replayGainTrack: 2.5, replayGainTrackPeak: 0.311896, replayGainAlbum: 3.4,
                                      replayGainAlbumPeak: 0.589856))
    }

    @Test("TAGREAD-03: MP4 freeform atoms (com.apple.iTunes:replaygain_…)")
    func mp4() async throws {
        let url = try await TagFixtures.m4a(named: "tags-m4a", items: [
            ("replaygain_track_gain", "-1.00 dB"), ("replaygain_album_gain", "-3.00 dB"),
            ("replaygain_album_peak", "1.012"),
        ])
        let tags = await TrackGainTags.read(from: url)
        #expect(tags == TrackGainTags(replayGainTrack: -1, replayGainAlbum: -3, replayGainAlbumPeak: 1.012))
    }

    @Test("TAGREAD-04: no tags, unreadable values and a file that will not open read as empty")
    func empty() async throws {
        let plain = try await TagFixtures.flac(named: "tags-none", comments: ["TITLE=plain"])
        #expect(await TrackGainTags.read(from: plain).isEmpty)
        let garbled = try await TagFixtures.flac(named: "tags-garbled", comments: [
            "REPLAYGAIN_TRACK_GAIN=loud", "R128_TRACK_GAIN=-12.5",
        ])
        #expect(await TrackGainTags.read(from: garbled).isEmpty)
        let missing = Fixtures.directory.appending(path: "tags-not-there.flac")
        #expect(await TrackGainTags.read(from: missing).isEmpty)
    }
}

/// Tagged fixtures made at run time: a short tone written by Apple's encoder, then the tags put in.
enum TagFixtures {
    /// A FLAC file whose Vorbis comment block holds `comments` ("NAME=value").
    static func flac(named name: String, comments: [String]) async throws -> URL {
        let url = try tone(named: name, extension: "flac", settings: [AVFormatIDKey: kAudioFormatFLAC])
        var bytes = try [UInt8](Data(contentsOf: url))
        try #require(bytes.starts(with: Array("fLaC".utf8)))
        var blocks: [(type: UInt8, body: [UInt8])] = []
        var position = 4
        var last = false
        while !last {
            last = bytes[position] & 0x80 != 0
            let length = Int(bytes[position + 1]) << 16 | Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            blocks.append((bytes[position] & 0x7F, Array(bytes[position + 4 ..< position + 4 + length])))
            position += 4 + length
        }
        let audio = bytes[position...]
        var comment = littleEndian(4) + Array("test".utf8) + littleEndian(comments.count)
        for entry in comments {
            comment += littleEndian(entry.utf8.count) + Array(entry.utf8)
        }
        blocks = blocks.filter { $0.type != 4 } + [(4, comment)] // 4: VORBIS_COMMENT
        bytes = Array("fLaC".utf8)
        for (index, block) in blocks.enumerated() {
            let flag: UInt8 = index == blocks.count - 1 ? 0x80 : 0
            bytes += [block.type | flag] + Array(bigEndian(block.body.count).dropFirst()) + block.body
        }
        try Data(bytes + audio).write(to: url)
        return url
    }

    /// A WAV file with an `id3 ` chunk holding one ID3v2.3 `TXXX` frame per (description, value).
    static func wavWithID3(named name: String, frames: [(String, String)]) throws -> URL {
        let url = try tone(named: name, extension: "wav", settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        var body: [UInt8] = []
        for (description, value) in frames {
            let content: [UInt8] = [0] + Array(description.utf8) + [0] + Array(value.utf8) // ISO-8859-1
            body += Array("TXXX".utf8) + bigEndian(content.count) + [0, 0] + content
        }
        let size = body.count
        let synchsafe = [21, 14, 7, 0].map { UInt8((size >> $0) & 0x7F) }
        let tag = Array("ID3".utf8) + [3, 0, 0] + synchsafe + body
        var bytes = try [UInt8](Data(contentsOf: url)) + Array("id3 ".utf8) + littleEndian(tag.count) + tag
        if tag.count % 2 == 1 {
            bytes.append(0)
        }
        bytes.replaceSubrange(4 ..< 8, with: littleEndian(bytes.count - 8)) // the RIFF size
        try Data(bytes).write(to: url)
        return url
    }

    /// An AAC .m4a file with iTunes long-form (freeform) items, one per (name, value).
    static func m4a(named name: String, items: [(String, String)]) async throws -> URL {
        let source = try tone(named: name + "-source", extension: "m4a",
                              settings: [AVFormatIDKey: kAudioFormatMPEG4AAC])
        let url = Fixtures.directory.appending(path: name + ".m4a")
        try? FileManager.default.removeItem(at: url)
        let session = try #require(AVAssetExportSession(asset: AVURLAsset(url: source),
                                                        presetName: AVAssetExportPresetPassthrough))
        session.metadata = items.map { name, value in
            let item = AVMutableMetadataItem()
            item.identifier = AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.\(name)")
            item.value = value as NSString
            return item
        }
        try await session.export(to: url, as: .m4a)
        return url
    }

    /// 0.1 s of a quiet stereo tone at 48 kHz in `settings`' format.
    private static func tone(named name: String, extension suffix: String, settings: [String: Any]) throws -> URL {
        try FileManager.default.createDirectory(at: Fixtures.directory, withIntermediateDirectories: true)
        let url = Fixtures.directory.appending(path: "\(name).\(suffix)")
        try? FileManager.default.removeItem(at: url)
        let format = settings.merging([AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2]) { $1 }
        let file = try AVAudioFile(forWriting: url, settings: format, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let frames: AVAudioFrameCount = 4800
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0 ..< 2 {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0 ..< Int(frames) {
                samples[frame] = 0.1 * Float(sin(Double(frame) * 0.13))
            }
        }
        try file.write(from: buffer)
        return url
    }

    private static func littleEndian(_ value: Int) -> [UInt8] {
        [0, 8, 16, 24].map { UInt8((value >> $0) & 0xFF) }
    }

    private static func bigEndian(_ value: Int) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
    }
}
