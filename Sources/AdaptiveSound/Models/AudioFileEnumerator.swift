import Foundation

// MARK: - Audio File Enumerator

/// Stateless namespace for recursive audio-file enumeration.
///
/// Runs on a background executor (via `Task.detached` in the call site).
/// Returns results sorted locale-aware ascending by name.
enum AudioFileEnumerator {
    /// Supported audio file extensions (lowercased).
    /// These are the formats that AVAudioFile natively supports on macOS.
    static let supportedExtensions: Set<String> = [
        "flac", "mp3", "wav", "aac", "m4a", "alac", "aiff", "ogg",
    ]

    /// Recursively enumerate all audio files under `folderURL`.
    ///
    /// - Parameter folderURL: The directory to scan.
    /// - Returns: Sorted array of `AudioFile` values.
    static func enumerate(folderURL: URL) -> [AudioFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [AudioFile] = []

        for case let fileURL as URL in enumerator {
            guard
                let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)),
                resourceValues.isRegularFile == true
            else {
                continue
            }

            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            let name = fileURL.deletingPathExtension().lastPathComponent
            let format = fileURL.pathExtension.uppercased()

            // Relative path is the folder portion relative to the chosen root,
            // e.g. for root=/Music and file=/Music/Indie/2024/Song.flac → "Indie/2024/"
            let relativeURL = fileURL.deletingLastPathComponent()
            let relativePath: String
            if let rel = relativeURL.path.dropFirst(folderURL.path.count)
                .trimmingCharacters(in: .init(charactersIn: "/")) as String?,
                !rel.isEmpty
            {
                relativePath = rel + "/"
            } else {
                relativePath = ""
            }

            results.append(
                AudioFile(
                    name: name,
                    relativePath: relativePath,
                    absoluteURL: fileURL,
                    format: format,
                    durationSeconds: 0
                )
            )
        }

        return results.sorted()
    }
}
