#if DEBUG
    import SwiftUI

    extension EnvironmentValues {
        /// `SongsPerfRun` only: the Songs list's performance hook (`SongsListProbe`). Nil in a normal
        /// run and in the picture sheets.
        @Entry var songsListProbe: SongsListProbe?
    }
#endif
