import AVFoundation
import SwiftUI

// MARK: - Track Info Card

/// Popover card showing metadata for a single `AudioFile`. Async fields (sample rate,
/// channels, bit depth, file size) are loaded off the main actor in a `.task` and
/// populated without layout shift — a pending/unavailable field renders an em-dash at
/// the same font as a loaded value.
struct TrackInfoCard: View {
    let file: AudioFile

    // MARK: Async state

    @State private var duration: MetaValue = .loading
    @State private var sampleRate: MetaValue = .loading
    @State private var channels: MetaValue = .loading
    @State private var bitDepth: MetaValue = .loading
    @State private var fileSize: MetaValue = .loading

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleBlock
            divider
            metadataGroup
            pathBlock
        }
        .padding(16)
        .frame(width: 340)
        // Every field (title, metadata values, path) is selectable + ⌘C-copyable — this
        // propagates to all descendant Text, so the per-field modifier isn't repeated.
        .textSelection(.enabled)
        .task { await loadMetadata() }
    }

    // MARK: - Title block

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundStyle(Color.asAccent)
                .frame(width: 40, height: 40)
                .background(Color.asWindow)
                .clipShape(.rect(cornerRadius: 8))

            Text(file.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.asLabel)
                .lineLimit(nil) // show the FULL title — wrap to as many lines as needed, never truncate
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            FormatBadgeView(format: file.format)
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.asHairline)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    // MARK: - Metadata group

    private var metadataGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow(key: "Duration", value: durationValue)
            metaRow(key: "Sample Rate", value: metaValueText(sampleRate))
            metaRow(key: "Channels", value: metaValueText(channels))
            // Bit Depth only appears once a real value is known — compressed formats
            // (MP3/AAC) report 0, resolving to `.unavailable`, so the row stays hidden.
            if case let .value(depth) = bitDepth {
                metaRow(key: "Bit Depth", value: Text(depth).foregroundStyle(Color.asLabel))
            }
            metaRow(key: "File Size", value: metaValueText(fileSize))
        }
    }

    // MARK: - Path block

    private var pathBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PATH")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.asLabelSecond)

            Text(file.absoluteURL.path)
                .textSelection(.enabled)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.asLabelTertiary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.asWindow)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: - Helpers

    /// A single key/value metadata row. The value's font is applied here (one place);
    /// the value view supplies its own foreground colour (primary vs. tertiary placeholder).
    private func metaRow(key: String, value: some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(key)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.asLabelSecond)
                .frame(width: 96, alignment: .leading)

            value
                .font(.system(size: 12, weight: .regular, design: .monospaced))
        }
    }

    /// Duration: the pre-scanned `file.durationSeconds` when available (shown instantly),
    /// otherwise the value computed from the opened `AVAudioFile` (the playlist scan leaves
    /// `durationSeconds` at 0 today, so the card relies on the async fallback).
    @ViewBuilder
    private var durationValue: some View {
        if file.durationSeconds > 0 {
            Text(formatDuration(file.durationSeconds)).foregroundStyle(Color.asLabel)
        } else {
            metaValueText(duration)
        }
    }

    /// Renders a `MetaValue`: an em-dash placeholder (tertiary) while loading or when
    /// unavailable, the loaded string (primary) once resolved. Same font in both cases
    /// (applied by `metaRow`), so there is no layout shift when the value arrives.
    @ViewBuilder
    private func metaValueText(_ value: MetaValue) -> some View {
        switch value {
        case .loading, .unavailable:
            Text("—").foregroundStyle(Color.asLabelTertiary)
        case let .value(string):
            Text(string).foregroundStyle(Color.asLabel)
        }
    }

    // MARK: - Async metadata loading

    @MainActor
    private func loadMetadata() async {
        let url = file.absoluteURL
        let result = await Task.detached(priority: .userInitiated) {
            TrackMetadata(url: url)
        }.value
        // The card can be dismissed (and the .task cancelled) before the detached work
        // returns; don't write stale values onto a view that's going away.
        guard !Task.isCancelled else { return }
        duration = result.duration
        sampleRate = result.sampleRate
        channels = result.channels
        bitDepth = result.bitDepth
        fileSize = result.fileSize
    }
}

// MARK: - MetaValue

/// Tri-state for an async metadata field: `loading` → resolved as `value` or `unavailable`.
/// Replaces an ambiguous `String?` (where nil/"" meant different things per field).
private enum MetaValue {
    case loading
    case unavailable
    case value(String)
}

// MARK: - TrackMetadata (gathered off the main actor)

/// All async metadata fields gathered off the main actor in one detached task.
private struct TrackMetadata {
    let duration: MetaValue
    let sampleRate: MetaValue
    let channels: MetaValue
    let bitDepth: MetaValue
    let fileSize: MetaValue

    init(url: URL) {
        // Hold the security scope for BOTH the filesystem stat AND the AVAudioFile open:
        // for a sandboxed build, a bookmark-derived URL needs the scope active for either.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        // --- File size ---
        if let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 {
            // Matches SongsTable's `fileSize.formatted(.byteCount(style: .file))` (S4 SW5).
            fileSize = .value(bytes.formatted(.byteCount(style: .file)))
        } else {
            fileSize = .unavailable
        }

        // --- AVAudioFile on-disk (native) format ---
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            duration = .unavailable
            sampleRate = .unavailable
            channels = .unavailable
            bitDepth = .unavailable
            return
        }
        let nativeFormat = audioFile.fileFormat

        // Duration — frames / sample rate of the decoded (processing) format.
        let procRate = audioFile.processingFormat.sampleRate
        duration = procRate > 0
            ? .value(formatDuration(Double(audioFile.length) / procRate))
            : .unavailable

        // Sample rate — integer kHz when the fractional part is negligible, else 1 dp.
        let rateHz = nativeFormat.sampleRate
        if rateHz >= 1000 {
            let kHz = rateHz / 1000
            if kHz.truncatingRemainder(dividingBy: 1) < 0.001 {
                sampleRate = .value("\(Int(kHz)) kHz")
            } else {
                // Swift-native formatting, not C `String(format:)` (S4 SW5 / swift.md).
                sampleRate = .value("\(kHz.formatted(.number.precision(.fractionLength(1)))) kHz")
            }
        } else {
            sampleRate = .value("\(Int(rateHz)) Hz")
        }

        // Channel count
        let channelCount = nativeFormat.channelCount
        switch channelCount {
        case 1: channels = .value("Mono")
        case 2: channels = .value("Stereo")
        default: channels = .value("\(channelCount) ch")
        }

        // Bit depth — 0 for compressed formats (AAC, MP3, …) → unavailable (row hidden).
        let bits = nativeFormat.streamDescription.pointee.mBitsPerChannel
        bitDepth = bits > 0 ? .value("\(bits)-bit") : .unavailable
    }
}
