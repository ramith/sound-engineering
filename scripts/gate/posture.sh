#!/usr/bin/env bash
#
# scripts/gate/posture.sh <migrator|playlist|layers> — the file-level posture guards, moved
# verbatim in logic from scripts/strict-gate.sh (one registry row each).
#
#   migrator  user data must never be erased on a schema change (S10.3 one-store posture)
#   playlist  a playlist add/drop path must never move or copy a file (US-PLIST-04)
#   layers    Kits stay headless (no SwiftUI/AppKit import); fixed bands keep their Dynamic Type clamp
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

check_migrator() {
    local src="Sources/LibraryStore/LibraryStore.swift"
    [[ -f "$src" ]] || { red "ERROR: $src is missing, so the migrator guard has nothing to read"; return 1; }
    if grep -nE 'eraseDatabaseOnSchemaChange[[:space:]]*=[[:space:]]*true' "$src"; then
        red "ERROR: eraseDatabaseOnSchemaChange = true in $src: this WIPES all user data on a schema change."
        red "       Forbidden (S10.3 one-store posture holds playlists + track user-state)."
        return 1
    fi
    if ! grep -qE 'eraseDatabaseOnSchemaChange[[:space:]]*=[[:space:]]*false' "$src"; then
        red "ERROR: '$src' must explicitly pin 'eraseDatabaseOnSchemaChange = false' (S10.3)."
        return 1
    fi
    green "migrator posture ok (eraseDatabaseOnSchemaChange pinned false; never-erase)."
    echo "GATE_COVERED 1 guarded-file"
}

check_playlist() {
    local paths=(
        "Sources/AdaptiveSound/UI/Library/LibrarySidebar.swift"
        "Sources/AdaptiveSound/UI/Playlist/AddToPlaylistMenu.swift"
        "Sources/AdaptiveSound/PlaylistsModel.swift"
        "Sources/AdaptiveSound/PlaylistsModel+Add.swift"
        "Sources/AdaptiveSound/UI/Library/FileOrRowDrop.swift"
        "Sources/LibraryBrowseKit/PlaylistDropRouter.swift"
        "Sources/LibraryStore/LibraryStore+Playlists.swift"
    )
    local f
    for f in "${paths[@]}"; do
        [[ -f "$f" ]] || { red "ERROR: $f is missing: the playlist guard would check nothing"; return 1; }
    done
    if grep -nE '\.(moveItem|copyItem)\(' "${paths[@]}"; then
        red "ERROR: a playlist add/drop path references moveItem/copyItem. Playlist membership is a"
        red "       reference-add by track id and must NEVER move or copy a file on disk (US-PLIST-04)."
        return 1
    fi
    green "playlist add/drop path ok (no moveItem/copyItem: reference-add only)."
    echo "GATE_COVERED ${#paths[@]} guarded-files"
}

check_layers() {
    local kits=(Sources/DesignTokenKit Sources/EQEditKit Sources/OutputDeviceKit Sources/SettingsKit)
    local d
    for d in "${kits[@]}"; do
        [[ -d "$d" ]] || { red "ERROR: $d is missing: the Kit purity guard would check nothing"; return 1; }
    done
    if grep -rnE '^import(\s+(struct|class|enum|protocol|func|typealias|var|let))?\s+(SwiftUI|AppKit)' "${kits[@]}"; then
        red "ERROR: a pure Kit imports a UI framework. Kits stay headless (s10-7 design §3.2)."
        return 1
    fi
    local bands=(
        "Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift"
        "Sources/AdaptiveSound/UI/Shell/ChromeBar.swift"
    )
    local f
    for f in "${bands[@]}"; do
        if ! grep -q '\.dynamicTypeSize(' "$f"; then
            red "ERROR: $f lost its .dynamicTypeSize clamp: a fixed band overflows at accessibility text sizes."
            return 1
        fi
    done
    green "layer-policy guards ok (Kits headless; fixed-band clamps present)."
    echo "GATE_COVERED $(( ${#kits[@]} + ${#bands[@]} )) guarded-paths"
}

case "${1:-}" in
    migrator) check_migrator ;;
    playlist) check_playlist ;;
    layers)   check_layers ;;
    *) red "usage: posture.sh <migrator|playlist|layers>"; exit 2 ;;
esac
