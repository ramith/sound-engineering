#!/usr/bin/env bash
#
# scripts/toolchain/install.sh — installs every pinned gate tool from toolchain/toolchain.env.
#
# One install script serves the Mac and CI. It installs into a USER cache directory keyed by the
# manifest hash, verifies every download's sha256 before use, and never touches global Homebrew
# or uses sudo. Nothing here is allowed to fail silently: a failed download, checksum, build or
# version assertion stops the script with the tool's name and the fix.
#
# Usage:
#   scripts/toolchain/install.sh            # install (idempotent: a complete cache is a no-op)
#   scripts/toolchain/install.sh --print-bin   # print the bin dir only (used by the gate runner)
#
# Then put the bin dir first on PATH:
#   export PATH="$(scripts/toolchain/install.sh --print-bin):$PATH"
#   (the gate runner does this for itself; you only need it for by-hand tool calls)
#
# Cache: ${ADAPTIVESOUND_TOOLCHAIN_CACHE:-$HOME/.cache/adaptivesound-toolchain}/<manifest-hash>/
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="${TOOLCHAIN_ENV:-$repo_root/toolchain/toolchain.env}"
reqs="$repo_root/scripts/toolchain/semgrep-requirements.txt"

red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
die()    { red "ERROR: $*"; exit 1; }

[[ -f "$manifest" ]] || die "manifest not found: $manifest"
[[ -f "$reqs" ]]     || die "semgrep requirements not found: $reqs"
# shellcheck source=toolchain/toolchain.env
set -a; source "$manifest"; set +a

# The hash covers everything that defines the installed tools: the manifest and the hash-locked
# semgrep requirements. A bump changes the hash, so the new tools land in a NEW directory.
manifest_hash="$(cat "$manifest" "$reqs" | shasum -a 256 | cut -c1-16)"
cache_root="${ADAPTIVESOUND_TOOLCHAIN_CACHE:-$HOME/.cache/adaptivesound-toolchain}"
tool_dir="$cache_root/$manifest_hash"
bin_dir="$tool_dir/bin"

if [[ "${1:-}" == "--print-bin" ]]; then
    printf '%s\n' "$bin_dir"
    exit 0
fi

# download <url> <sha256> <dest> — the archive is stored ONCE per checksum under archives/<sha256>, so a
# manifest bump that leaves a tool's pin unchanged reuses the verified bytes instead of re-downloading
# (LLVM is 1.5 GB). Every use re-verifies the digest; a stored file that no longer matches is discarded.
download() {
    local url="$1" want="$2" dest="$3" got tmp store
    store="$cache_root/archives/$want"
    mkdir -p "$cache_root/archives"
    if [[ -f "$store" ]] && [[ "$(shasum -a 256 "$store" | awk '{print $1}')" == "$want" ]]; then
        echo "  reuse $(basename "$dest") (archive $want, verified)"
    else
        rm -f "$store"
        tmp="$store.part"
        echo "  fetch $(basename "$dest")"
        curl -fSL --retry 8 --retry-delay 5 --retry-all-errors -C - -o "$tmp" "$url" \
            || die "download failed: $url (retry, or check the network; the manifest URL is unchanged)"
        got="$(shasum -a 256 "$tmp" | awk '{print $1}')"
        if [[ "$got" != "$want" ]]; then
            rm -f "$tmp"
            die "checksum mismatch for $url
       want $want
       got  $got
       The archive does not match the manifest. Do NOT edit the checksum to match: find out why the bytes changed."
        fi
        mv "$tmp" "$store"
    fi
    ln -sfn "$store" "$dest"
}

# assert_version <label> <expected-substring> <actual> — fails hard on mismatch.
assert_version() {
    local label="$1" want="$2" got="$3"
    if [[ "$got" != *"$want"* ]]; then
        die "$label installed as '$got', manifest wants '$want' (the cache is corrupt or the manifest moved on; delete $tool_dir and re-run)"
    fi
    green "  ok  $label $want"
}

if [[ -f "$tool_dir/.complete" ]]; then
    echo "toolchain already installed: $tool_dir"
    echo "PATH line: export PATH=\"$bin_dir:\$PATH\""
    exit 0
fi

mkdir -p "$tool_dir/downloads" "$bin_dir"
dl="$tool_dir/downloads"

# ---------------------------------------------------------------- SwiftFormat / SwiftLint / Periphery
step "Swift style and dead-code tools"
download "$SWIFTFORMAT_URL" "$SWIFTFORMAT_SHA256" "$dl/swiftformat.zip"
unzip -o -q "$dl/swiftformat.zip" swiftformat -d "$bin_dir"
chmod +x "$bin_dir/swiftformat"
assert_version "swiftformat" "$SWIFTFORMAT_VERSION" "$("$bin_dir/swiftformat" --version)"

download "$SWIFTLINT_URL" "$SWIFTLINT_SHA256" "$dl/swiftlint.zip"
unzip -o -q "$dl/swiftlint.zip" swiftlint -d "$bin_dir"
chmod +x "$bin_dir/swiftlint"
assert_version "swiftlint" "$SWIFTLINT_VERSION" "$("$bin_dir/swiftlint" --version)"

download "$PERIPHERY_URL" "$PERIPHERY_SHA256" "$dl/periphery.zip"
unzip -o -q "$dl/periphery.zip" periphery -d "$bin_dir"
chmod +x "$bin_dir/periphery"
assert_version "periphery" "$PERIPHERY_VERSION" "$("$bin_dir/periphery" version)"

# ---------------------------------------------------------------- LLVM: clang-tidy AND clang-format
step "LLVM $LLVM_VERSION (clang-tidy + clang-format from one tarball)"
download "$LLVM_URL" "$LLVM_SHA256" "$dl/llvm.tar.xz"
llvm_dir="$tool_dir/llvm"
rm -rf "$llvm_dir" && mkdir -p "$llvm_dir"
tar -xJf "$dl/llvm.tar.xz" -C "$llvm_dir" --strip-components=1 \
    || die "could not extract the LLVM archive (it may be truncated: delete $dl/llvm.tar.xz and re-run)"
for tool in clang-tidy clang-format; do
    [[ -x "$llvm_dir/bin/$tool" ]] || die "LLVM archive has no bin/$tool (the manifest's LLVM_URL is wrong)"
    ln -sf "$llvm_dir/bin/$tool" "$bin_dir/$tool"
done
assert_version "clang-tidy" "$LLVM_VERSION" "$("$bin_dir/clang-tidy" --version | sed -nE 's/.*version ([0-9.]+).*/\1/p' | head -1)"
assert_version "clang-format" "$LLVM_VERSION" "$("$bin_dir/clang-format" --version | sed -nE 's/.*version ([0-9.]+).*/\1/p' | head -1)"

# ---------------------------------------------------------------- cppcheck (built from source, once)
step "cppcheck $CPPCHECK_VERSION (source build)"
download "$CPPCHECK_URL" "$CPPCHECK_SHA256" "$dl/cppcheck.tar.gz"
cpp_src="$tool_dir/cppcheck-src"
rm -rf "$cpp_src" && mkdir -p "$cpp_src"
tar -xzf "$dl/cppcheck.tar.gz" -C "$cpp_src" --strip-components=1 \
    || die "could not extract the cppcheck source"
cpp_prefix="$tool_dir/cppcheck"
# FILESDIR must sit inside the prefix (cppcheck's Makefile refuses to install without it).
make -C "$cpp_src" -j"$(sysctl -n hw.ncpu)" MATCHCOMPILER=yes FILESDIR="$cpp_prefix/share/cppcheck" \
    CXXFLAGS="-O2 -DNDEBUG" >"$tool_dir/cppcheck-build.log" 2>&1 \
    || die "cppcheck build failed; see $tool_dir/cppcheck-build.log"
make -C "$cpp_src" install PREFIX="$cpp_prefix" FILESDIR="$cpp_prefix/share/cppcheck" >>"$tool_dir/cppcheck-build.log" 2>&1 \
    || die "cppcheck install failed; see $tool_dir/cppcheck-build.log"
ln -sf "$cpp_prefix/bin/cppcheck" "$bin_dir/cppcheck"
assert_version "cppcheck" "$CPPCHECK_VERSION" "$("$bin_dir/cppcheck" --version)"

# ---------------------------------------------------------------- semgrep (pip, hash-locked, private venv)
step "semgrep $SEMGREP_VERSION (pip --require-hashes)"
venv="$tool_dir/semgrep-venv"
python3 -m venv "$venv" || die "python3 -m venv failed (need python3 3.12 to match the hash-locked wheels)"
"$venv/bin/pip" install --quiet --require-hashes --disable-pip-version-check -r "$reqs" \
    || die "semgrep install failed: pip refused the hashes or a wheel. The lock is $reqs"
ln -sf "$venv/bin/semgrep" "$bin_dir/semgrep"
# semgrep's CLI re-enters through `pysemgrep` and runs `semgrep-core` by name, both resolved from PATH.
# Homebrew ships its own pysemgrep (1.175.0 here), which would silently run instead of the pinned one.
# So the pinned pysemgrep and the wheel's bundled semgrep-core are linked into the same bin dir.
ln -sf "$venv/bin/pysemgrep" "$bin_dir/pysemgrep"
core="$("$venv/bin/python3" -c 'import os, semgrep; print(os.path.join(os.path.dirname(semgrep.__file__), "bin", "semgrep-core"))')"
[[ -x "$core" ]] || die "semgrep's bundled semgrep-core is missing at $core"
ln -sf "$core" "$bin_dir/semgrep-core"
# Assert with the pinned directory FIRST on PATH: that is how the gate runs it.
assert_version "semgrep" "$SEMGREP_VERSION" "$(PATH="$bin_dir:$PATH" "$bin_dir/semgrep" --version 2>/dev/null)"
assert_version "semgrep-core" "$SEMGREP_VERSION" "$(PATH="$bin_dir:$PATH" "$bin_dir/semgrep-core" -version 2>/dev/null | sed -nE 's/.*version: ([0-9.]+).*/\1/p')"

# ---------------------------------------------------------------- actionlint (pinned tarball)
step "actionlint $ACTIONLINT_VERSION"
download "$ACTIONLINT_URL" "$ACTIONLINT_SHA256" "$dl/actionlint.tar.gz"
tar -xzf "$dl/actionlint.tar.gz" -C "$bin_dir" actionlint \
    || die "could not extract actionlint"
chmod +x "$bin_dir/actionlint"
assert_version "actionlint" "$ACTIONLINT_VERSION" "$("$bin_dir/actionlint" -version | head -1)"

# ---------------------------------------------------------------- done
rm -rf "$cpp_src" "$dl"
date -u +%Y-%m-%dT%H:%M:%SZ > "$tool_dir/.complete"
step "installed"
green "toolchain ready: $tool_dir"
echo "PATH line: export PATH=\"$bin_dir:\$PATH\""
if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$bin_dir" >> "$GITHUB_PATH"
    echo "GITHUB_PATH updated with $bin_dir"
fi
