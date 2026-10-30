import AudioFormatKit
import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

// MARK: - The bridge's own reader: a track read by Apple's decoder, its place counted (KI-PB-22)

/// A track as Apple's decoder reads it, for every read and seek the bridge makes itself: the streaming reader's
/// (`EnhancedResampleSession`) and the probe at open (`openForPlayback`). It is `ExtAudioFile` — the decoder
/// `AVAudioFile` wraps — set to the opened file's processing format, so it reads the very samples `AVAudioFile`
/// does, bit for bit, on every channel (measured on the corpus: 1–8 channels; PCM, FLAC, ALAC, AAC, AC-3, E-AC-3,
/// MP3, Vorbis, Opus; 8–96 kHz), and a seek lands where `AVAudioFile`'s does.
///
/// Its place is **counted** (`position`), never asked of the file, and every failure is a thrown status:
/// `AVAudioFile.framePosition` — its getter and its setter — raises an Objective-C exception nothing catches, fatal
/// to the process, on a file whose decoder refuses it (a FLAC with blocks under 192 samples, KI-PB-22). So the app
/// never asks an `AVAudioFile` its place nor sets it; the Semgrep rule `app-no-avaudiofile-position` holds that.
///
/// Its end is where the decoder stops delivering (`ended`), which can come before `length`: E-AC-3, AC-3,
/// ffmpeg-made MP3 and Vorbis deliver up to a few hundred frames fewer than `AVAudioFile.length` states, and a file
/// cut short stops at its cut. `ExtAudioFile` then answers an empty read, where `AVAudioFile` throws.
///
/// Not thread-safe: one queue owns it (the resampler's, or the opener's for the probe).
final class TrackFileReader {
    /// A status Apple's decoder refused a step with.
    struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus

        var description: String {
            "\(step) failed (\(status))"
        }
    }

    /// The format the reads fill: the opened `AVAudioFile`'s processing format (float, one buffer per channel, the
    /// file's rate and channel layout).
    let processingFormat: AVAudioFormat
    /// The frames the file states (`AVAudioFile.length`). The decoder may deliver fewer (`ended`).
    let length: AVAudioFramePosition
    /// Where the next read begins: counted from the top, or from the last seek's place.
    private(set) var position: AVAudioFramePosition = 0
    /// The decoder has delivered its last frame: a read came back short (its real end), or `length` is reached.
    private(set) var ended = false

    private let file: ExtAudioFileRef

    /// Read `opened`'s file in its processing format, from the top. Throws when Apple's decoder can't be set up for
    /// it — the tiny-block FLAC opens, then refuses its decoder here ('fmt?').
    init(reading opened: AVAudioFile) throws(Failure) {
        processingFormat = opened.processingFormat
        length = opened.length
        var opening: ExtAudioFileRef?
        let status = ExtAudioFileOpenURL(opened.url as CFURL, &opening)
        guard status == noErr, let opening else { throw Failure(step: "open", status: status) }
        var client = processingFormat.streamDescription.pointee
        let formatStatus = ExtAudioFileSetProperty(opening, kExtAudioFileProperty_ClientDataFormat,
                                                   UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
        guard formatStatus == noErr else {
            ExtAudioFileDispose(opening)
            throw Failure(step: "decode setup", status: formatStatus)
        }
        file = opening
    }

    deinit {
        ExtAudioFileDispose(file)
    }

    /// Place the next read at `frame` (clamped to `0 ... length`), as `AVAudioFile`'s seek places it. On a failure
    /// nothing moved.
    func seek(to frame: AVAudioFramePosition) throws(Failure) {
        let place = max(0, min(frame, length))
        let status = ExtAudioFileSeek(file, place)
        guard status == noErr else { throw Failure(step: "seek", status: status) }
        position = place
        ended = place >= length
    }

    /// Read up to `frameCount` frames (at most `buffer`'s capacity, never past `length`) into `buffer`; its
    /// `frameLength` is what came. Fewer than asked is the decoder's real end (`ended`), and once ended a read
    /// delivers nothing. A failed read delivers nothing and throws.
    func read(into buffer: AVAudioPCMBuffer, frameCount: AVAudioFrameCount) throws(Failure) {
        let asked = AVAudioFrameCount(clamping: min(Int64(min(frameCount, buffer.frameCapacity)),
                                                    max(0, length - position)))
        guard !ended, asked > 0 else {
            buffer.frameLength = 0
            ended = true
            return
        }
        buffer.frameLength = asked // the buffer list's sizes: room for what is asked
        var frames = asked
        let status = ExtAudioFileRead(file, &frames, buffer.mutableAudioBufferList)
        guard status == noErr else {
            buffer.frameLength = 0
            throw Failure(step: "read", status: status)
        }
        buffer.frameLength = frames
        position += AVAudioFramePosition(frames)
        ended = frames < asked || position >= length
    }
}

// MARK: - Opening a track to play it

extension AudioEngineBridge {
    /// Frames the probe at open reads: enough for Apple's decoder to decode its first packet of any codec.
    private static let probeFrames: AVAudioFrameCount = 4096

    /// Open `url` to play it: its `AVAudioFile`, once Apple's decoder has read its first frames on a reader of its
    /// own (`TrackFileReader`; the returned file is untouched, at its top). Some files open and then fail every
    /// read — the tiny-block FLAC (KI-PB-22) — and nothing must commit to one: the caller is refused with why
    /// (`AudioBridgeError.refusing`), the playing song carries on, and the view model says so. A file that states
    /// frames and delivers none is refused too. The caller holds the file's security scope.
    static func openForPlayback(_ url: URL) throws(AudioBridgeError) -> AVAudioFile {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw .refusing(url, status: OSStatus(truncatingIfNeeded: (error as NSError).code))
        }
        do throws(TrackFileReader.Failure) {
            let reader = try TrackFileReader(reading: file)
            guard let probe = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: probeFrames) else {
                throw TrackFileReader.Failure(step: "probe buffer", status: kAudio_MemFullError)
            }
            try reader.read(into: probe, frameCount: probeFrames)
            guard probe.frameLength > 0 || file.length == 0 else {
                throw TrackFileReader.Failure(step: "first read (no frames)", status: kAudioFileEndOfFileError)
            }
        } catch {
            logUX("open: '\(url.lastPathComponent)' refused — Apple's decoder: \(error)")
            throw .refusing(url, status: error.status)
        }
        return file
    }

    /// Whether `file` plays straight through to the player at `graphRate` — `AVAudioPlayerNode` reading the file
    /// itself (`scheduleSegment` / `scheduleFile`) — rather than through the bridge's own reader
    /// (`EnhancedResampleSession`).
    ///
    /// Only a file at the graph's rate whose decoder delivers exactly `length` frames: linear PCM, FLAC and ALAC,
    /// which state their sample count. A lossy codec's `length` is the decoder's estimate from its packets, and
    /// E-AC-3, AC-3, ffmpeg-made MP3 and Vorbis deliver up to a few hundred frames fewer, then fail the read; the
    /// player completes such a schedule when its read-ahead meets that failure, about a second before the last
    /// frame is heard (break-it MEDIUM-3: the end of the queue cut the last second, a seam came a second early).
    /// The reader ends on the frames the decoder delivered, and passes a file already at the graph's rate on as it
    /// is: nothing is resampled.
    static func playsStraightThrough(_ file: AVAudioFile, graphRate: Double) -> Bool {
        guard file.processingFormat.sampleRate == graphRate else { return false }
        return [kAudioFormatLinearPCM, kAudioFormatFLAC, kAudioFormatAppleLossless]
            .contains(file.fileFormat.streamDescription.pointee.mFormatID)
    }
}
