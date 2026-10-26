import Foundation
import LibraryBrowseKit
import Testing
import UniformTypeIdentifiers

// MARK: - R1.1-B break-it, Open With: what the app says it opens vs what it plays (BI-P)

//
// A red test written against the combined sprint branch (f52de075): the shipped Info.plist's
// `CFBundleDocumentTypes` (read from the source tree — SwiftPM does not bundle it, scripts/bundle-app.py
// does) against `LooseFiles.isPlayable`, the one list an open is judged by.

@Suite("R1.1-B break-it — Open With (BI-P)")
struct BreakItOpenWithTests {
    /// The app's Info.plist, from this file's place in the repo.
    private static let infoPlist = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/AdaptiveSound/Info.plist")

    @Test("BI-P10: Finder offers the app only for files it plays — every extension of a claimed type is playable")
    func everyClaimedExtensionPlays() throws {
        let data = try Data(contentsOf: Self.infoPlist)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let documentTypes = plist?["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        let claimed = documentTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        try #require(!claimed.isEmpty, "precondition: the app declares the audio types it opens")
        var refused: [String] = []
        for identifier in claimed {
            for ext in UTType(identifier)?.tags[.filenameExtension] ?? []
                where !LooseFiles.isPlayable(URL(fileURLWithPath: "/Music/song.\(ext)")) {
                refused.append(".\(ext) (\(identifier))")
            }
        }
        #expect(refused.isEmpty,
                Comment(rawValue: "Open With lists the app for these files, then it says “Can’t play … it isn’t an "
                    + "audio file this app plays”: \(refused.joined(separator: ", "))"))
    }
}
