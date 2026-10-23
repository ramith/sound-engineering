#!/usr/bin/env bash
#
# availability-ban.sh — no build flag may switch off availability checking (review H1, founder decision).
#
# The incident this guards: -D_LIBCPP_DISABLE_AVAILABILITY made Xcode 27's libc++ emit a macOS 27-only symbol,
# so the app failed to load on macOS 26 while passing on the macOS 27 CI runner. The same family of switch
# (-disable-availability-checking, -Wno-unguarded-availability...) would hide the same class of bug.
#
# Scope: Package.swift, scripts/, Makefile and .github/. A COMMENT that names a flag is fine (the docs must
# say what is banned); a non-comment line that uses one fails. Self-tested: a planted use must be caught.
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

banned='_LIBCPP_DISABLE_AVAILABILITY|-disable-availability-checking|-Wno-unguarded-availability|-Wno-availability'

# scan <root-or-file...>: prints "file:line: text" for every banned use in a non-comment line.
scan() {
    grep -rnE "$banned" "$@" 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)' \
        | grep -v 'scripts/gate/availability-ban.sh:' || true
}

hits="$(scan Package.swift scripts Makefile .github)"
if [[ -n "$hits" ]]; then
    while IFS= read -r line; do echo "RED $line"; done <<< "$hits"
    echo "ERROR: a build flag switches off availability checking. Remove it; the macOS 26 job catches what it hid." >&2
    exit 1
fi
files=$(git ls-files -- Package.swift scripts Makefile .github | wc -l | tr -d ' ')
((files >= 1)) || { echo "ERROR: found no files to scan" >&2; exit 1; }
echo "no availability-disabling flag in $files tracked file(s) under Package.swift, scripts/, Makefile, .github/."

# Planted: a real use in a code line must be caught (proves the ban can fail).
planted="${GATE_RUN_DIR:-$repo_root/.build/gate}/availability-planted"
rm -rf "$planted"; mkdir -p "$planted"
printf 'swiftSettings: [.unsafeFlags(["-D_LIBCPP_DISABLE_AVAILABILITY"])]\n' > "$planted/Package.swift"
printf '# a comment naming -D_LIBCPP_DISABLE_AVAILABILITY is allowed\n' > "$planted/comment.sh"
caught="$(scan "$planted")"
if [[ "$caught" != *"Package.swift"* || "$caught" == *"comment.sh"* ]]; then
    echo "ERROR: the planted use was not caught as expected (or a comment was flagged): $caught" >&2
    exit 1
fi
echo "planted use caught; a comment naming the flag is not (as required)."
echo "GATE_COVERED $files files"
