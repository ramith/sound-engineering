import Foundation

// MARK: - AudioBridgeError

enum AudioBridgeError: Error {
    case engineNotInitialized
    case auInitializationFailed
    case parameterSetFailed
    case unsupportedFormat(String)

    var localizedDescription: String {
        switch self {
        case .engineNotInitialized:
            return "Audio engine not initialized"
        case .auInitializationFailed:
            return "Audio unit initialization failed"
        case .parameterSetFailed:
            return "Parameter setting failed"
        case let .unsupportedFormat(ext):
            return "Unsupported file format: .\(ext). Supported: MP3, WAV, AAC, M4A, FLAC, AIFF, OGG"
        }
    }
}
