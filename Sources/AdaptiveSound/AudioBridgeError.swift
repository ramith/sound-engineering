import AudioToolbox
import Foundation
import LibraryScan

// MARK: - AudioBridgeError

enum AudioBridgeError: Error, Equatable {
    case engineNotInitialized
    /// A file type the app doesn't play: its extension is none the library admits
    /// (`LibraryScanner.supportedExtensions`, the one list).
    case unsupportedFormat(String)
    /// A file of a type the app plays whose contents Apple's decoder can't read: damaged, empty, cut off before its
    /// first frame, or not audio at all (its extension): break-it LOW-3 — it used to be called an unsupported type.
    case unreadableFile(String)
    /// A file of a type the app plays in a variant macOS can't decode — a codec or a channel layout Apple's decoder
    /// refuses: 5.1 Opus (KI-LIB-12), a FLAC with blocks under 192 samples (KI-PB-22).
    case undecodableFormat(String)
    /// A seek did not happen: its target was not a number, the file no longer opens (Enhanced), or
    /// the decoder could not reposition / the output would not go quiet for it (Pure). Playback
    /// carries on where it was.
    case seekFailed

    /// Why `url` can't play, from the status Apple's decoder refused it with (`nil`: it gave none). A type the app
    /// doesn't play is said so whatever the status; for one it plays, 'fmt?' — the data format is not one the
    /// decoder takes — is a variant macOS can't decode, and anything else a file it can't read.
    static func refusing(_ url: URL, status: OSStatus?) -> AudioBridgeError {
        let ext = url.pathExtension.lowercased()
        guard LibraryScanner.supportedExtensions.contains(ext) else { return .unsupportedFormat(ext) }
        return status == kAudioFileUnsupportedDataFormatError ? .undecodableFormat(ext) : .unreadableFile(ext)
    }
}

/// Founder-facing copy (break-it): without this, the error banner rendered the raw bridged
/// enum — "The operation couldn't be completed. (AdaptiveSound.AudioBridgeError error 0.)".
extension AudioBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            "The audio engine isn't ready yet — try again in a moment."
        case let .unsupportedFormat(ext):
            "This file type isn't supported\(Self.naming(ext))."
        case let .unreadableFile(ext):
            "This file can't be read — it may be damaged\(Self.naming(ext))."
        case let .undecodableFormat(ext):
            "macOS can't decode this kind of file\(Self.naming(ext))."
        case .seekFailed:
            "Couldn't jump to that point in the song — it keeps playing from where it was."
        }
    }

    /// " (.flac)": the file's extension, as the copy names it; nothing for a file that has none.
    private static func naming(_ ext: String) -> String {
        ext.isEmpty ? "" : " (.\(ext))"
    }
}
