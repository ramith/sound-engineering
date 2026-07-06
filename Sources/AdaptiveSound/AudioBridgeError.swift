import Foundation

// MARK: - AudioBridgeError

enum AudioBridgeError: Error {
    case engineNotInitialized
    case unsupportedFormat(String)
}
