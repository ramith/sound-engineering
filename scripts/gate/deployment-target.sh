#!/usr/bin/env bash
#
# Deployment-target guard (cheap, no symbol scan): every built executable and test bundle must declare
# a minimum macOS (LC_BUILD_VERSION minos) no newer than the package's .macOS(.v26) target.
#
# Why: CI runs macOS 27 (the xcode-27 image), and the product targets macOS 26. A binary built against
# Xcode 27's SDK can reference a symbol that exists only on macOS 27, and then it fails to load on
# macOS 26 while passing on the 27 runner. Measured: _LIBCPP_DISABLE_AVAILABILITY-free builds now report
# minos 26.0; a regression shows up here as minos 27.x.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

target="$(sed -nE 's/.*\.macOS\(\.v([0-9]+)\).*/\1/p' Package.swift | head -1)"
[[ -n "$target" ]] || fail "could not read the macOS deployment target from Package.swift"
bin="$(swift build --show-bin-path -c debug)" || fail "swift build --show-bin-path failed"

files=()
while IFS= read -r f; do files+=("$f"); done < <(
    find "$bin" -maxdepth 1 -type f -perm -u+x 2>/dev/null
    find "$bin" -path '*.xctest/Contents/MacOS/*' -type f 2>/dev/null
)
# Keep only Mach-O files (the executables above are not all binaries; a shell script would not be).
macho=()
for f in "${files[@]}"; do
    file -b "$f" 2>/dev/null | grep -q 'Mach-O' && macho+=("$f")
done
((${#macho[@]})) || fail "found 0 Mach-O products under $bin: nothing to check is not a pass"

bad=0
for f in "${macho[@]}"; do
    # minos for each architecture; the highest one is what must stay within the target.
    while read -r minos; do
        major="${minos%%.*}"
        if ((major > target)); then
            echo "ERROR: $f declares minos $minos, newer than the deployment target $target.0" >&2
            bad=1
        fi
    done < <(vtool -show-build "$f" 2>/dev/null | awk '/minos/ {print $2}')
done
((bad == 0)) || fail "a built product needs a newer macOS than the target ($target): a symbol from the newer SDK leaked in"
covered "${#macho[@]}" products-within-macOS-$target
