// FFmpegOptIn — "Use FFmpeg for other formats" (R1.1-A, founder decision FD-3, council C-99).
//
// FFmpeg is an in-process C parser for files from anywhere, so it is an opt-in, OFF BY DEFAULT: while it
// is off nothing loads it, the metadata scan reads through Apple only (`MetadataExtractor`), and Pure's
// decode fallback opens nothing (`FileDecodeSource`). When it is on, FFmpeg loads the first time a file
// Apple can't read needs it — from fixed absolute paths only, and only a library no other user can
// change (`FFmpegLoader.h`). This is the ONE switch for the whole process: a thin face over the AudioDSP
// C bridge (`FFmpegBridge.h`), whose reads and writes are an atomic each — no load, no I/O — so any
// thread may use it. The app sets it from the listener's setting (`ListeningSettings.useFFmpeg`) before
// any library work.

import AudioDSP

public enum FFmpegOptIn {
    /// Whether FFmpeg may be used. Off when the process starts.
    public static var isOn: Bool {
        get { ffmpegIsEnabled() != 0 }
        set { ffmpegSetEnabled(newValue ? 1 : 0) }
    }

    /// Where FFmpeg stands — never loads anything to answer.
    public static var state: State {
        State(rawValue: ffmpegState()) ?? .notFound
    }

    /// Where FFmpeg stands: `ffmpegState()`'s codes, in `FFmpegBridge.h`'s order.
    public enum State: UInt8, Sendable {
        /// The setting is off: FFmpeg is never loaded or used.
        case off
        /// On; it loads the first time a file needs it.
        case standby
        /// On, and loaded.
        case loaded
        /// On, but not installed where the app looks (Homebrew's `lib` folder).
        case notFound
        /// On, but a library file, or its folder, can be changed by another user: not loaded.
        case refused
        /// On, but not the FFmpeg version this build uses.
        case wrongVersion
    }
}
