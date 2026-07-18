import Foundation

// MARK: - AudioBridgeError

enum AudioBridgeError: Error {
    case engineNotInitialized
    case unsupportedFormat(String)
}

/// Founder-facing copy (break-it): without this, the error banner rendered the raw bridged
/// enum — "The operation couldn't be completed. (AdaptiveSound.AudioBridgeError error 0.)".
extension AudioBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            "The audio engine isn't ready yet — try again in a moment."
        case let .unsupportedFormat(ext):
            "This file type isn't supported (.\(ext))."
        }
    }
}
