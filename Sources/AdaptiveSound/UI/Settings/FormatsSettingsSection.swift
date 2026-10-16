import DesignTokenKit
import LibraryScan
import SwiftUI

/// The Formats card (R1.1-A, founder decision FD-3): FFmpeg as an opt-in, off by default. Apple's own
/// decoder reads every format the library scans; FFmpeg only adds a reader for a file it can't — its
/// tags, and its sound in Pure Mode — at the cost of running a third-party parser inside the app on
/// files from anywhere. Under the switch, one line says where FFmpeg stands once it is on (read when the
/// card draws: it loads the first time a file needs it).
struct FormatsSettingsSection: View {
    @Bindable var audioViewModel: AudioViewModel

    var body: some View {
        SettingsCard(title: "Formats") {
            SettingsSwitchRow(title: "Use FFmpeg for other formats",
                              detail: "Lets FFmpeg read a file macOS can’t: its tags, and its sound in Pure Mode. "
                                  + "FFmpeg runs inside the app on files from anywhere, so leave this off unless you "
                                  + "need it. Install FFmpeg with Homebrew.",
                              isOn: $audioViewModel.useFFmpeg)
            if audioViewModel.useFFmpeg, let note = Self.note(FFmpegOptIn.state) {
                Text(note)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Where FFmpeg stands, in plain words — nil when there is nothing to say.
    static func note(_ state: FFmpegOptIn.State) -> String? {
        switch state {
        case .off: nil
        case .standby: "FFmpeg loads the first time a file needs it."
        case .loaded: "FFmpeg is loaded."
        case .notFound: "FFmpeg isn’t installed where the app looks (Homebrew). Install it, then reopen the app."
        case .refused:
            "FFmpeg wasn’t loaded: another user could change its files. Reinstall it with Homebrew as yourself."
        case .wrongVersion: "FFmpeg wasn’t loaded: this build needs a different FFmpeg version."
        }
    }
}
