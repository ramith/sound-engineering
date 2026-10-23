#!/usr/bin/env bash
#
# scripts/toolchain/install.sh — installs every pinned gate tool from toolchain/toolchain.env.
#
# One install script serves the Mac and CI. Nothing here touches global Homebrew or uses sudo, and
# nothing is allowed to fail silently: a failed download, checksum, build or version assertion stops
# the script with the tool's name and the fix.
#
# Layout under ${ADAPTIVESOUND_TOOLCHAIN_CACHE:-$HOME/.cache/adaptivesound-toolchain}:
#   <manifest-hash>/bin/        symlinks to the tools this manifest names, plus bin.sha256 (what they must be)
#   tools/llvm-<sha>/           ONLY clang-tidy, clang-format and their resource headers (shared by checksum)
#   tools/cppcheck-<sha>/       cppcheck built from its pinned source (shared by checksum)
#   tools/semgrep-<reqs-hash>/  the hash-locked semgrep venv (shared by the lock's hash)
#   archives/<sha>              downloaded archives, kept only while needed (LLVM's is deleted once extracted)
# Every manifest hash except the current one and ONE previous (kept as a rollback) is pruned on install.
#
# Usage:
#   scripts/toolchain/install.sh               # install (a verified cache is a no-op: every tool file is re-hashed)
#   scripts/toolchain/install.sh --print-bin   # print the bin dir only (used by the gate runner and the hooks)
#
# Then put the bin dir first on PATH (the gate runner and the git hooks do this for you):
#   export PATH="$(scripts/toolchain/install.sh --print-bin):$PATH"
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
set -a
# shellcheck source=toolchain/toolchain.env
source "$manifest"
set +a

# The manifest hash covers the manifest and the hash-locked semgrep requirements.
manifest_hash="$(cat "$manifest" "$reqs" | shasum -a 256 | cut -c1-16)"
reqs_hash="$(shasum -a 256 "$reqs" | cut -c1-16)"
cache_root="${ADAPTIVESOUND_TOOLCHAIN_CACHE:-$HOME/.cache/adaptivesound-toolchain}"
tool_dir="$cache_root/$manifest_hash"
bin_dir="$tool_dir/bin"
shared="$cache_root/tools"

if [[ "${1:-}" == "--print-bin" ]]; then
    printf '%s\n' "$bin_dir"
    exit 0
fi

# download <url> <sha256> <dest> — the archive is stored once per checksum under archives/<sha>, every use
# re-verifies the digest, and a stored file that no longer matches is discarded.
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
        die "$label installed as '$got', manifest wants '$want' (delete $tool_dir and $shared/* for it, then re-run)"
    fi
    green "  ok  $label $want"
}

# Keep the current manifest's folder and ONE previous one (a rollback); remove the rest.
prune_old() {
    python3 - "$cache_root" "$manifest_hash" <<'PY'
import os, re, shutil, sys
root, cur = sys.argv[1], sys.argv[2]
if not os.path.isdir(root):
    sys.exit(0)
others = [d for d in os.listdir(root) if re.fullmatch(r"[0-9a-f]{16}", d) and d != cur]
others.sort(key=lambda d: os.path.getmtime(os.path.join(root, d)), reverse=True)
for d in others[1:]:
    shutil.rmtree(os.path.join(root, d))
    print("  pruned old toolchain folder %s" % d)
PY
}

# Bring PATH and $GITHUB_PATH to the bin dir, for both the fresh install and the verified fast path.
announce() {
    echo "PATH line: export PATH=\"$bin_dir:\$PATH\""
    if [[ -n "${GITHUB_PATH:-}" ]]; then
        echo "$bin_dir" >> "$GITHUB_PATH"
        echo "GITHUB_PATH updated with $bin_dir"
    fi
}

# ---------------------------------------------------------------- fast path: every tool file still matches
if [[ -f "$tool_dir/.complete" && -f "$tool_dir/bin.sha256" ]]; then
    if shasum -a 256 -c "$tool_dir/bin.sha256" >/dev/null 2>&1; then
        echo "toolchain installed and verified (every tool file re-hashed): $tool_dir"
        prune_old
        announce
        exit 0
    fi
    echo "an installed tool no longer matches its recorded checksum: reinstalling $tool_dir"
    rm -f "$tool_dir/.complete"
fi

mkdir -p "$tool_dir/downloads" "$bin_dir" "$shared"
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

# ---------------------------------------------------------------- LLVM: clang-tidy AND clang-format, nothing else
# The gate needs the two binaries (statically linked) and clang's resource headers, which clang-tidy finds at
# ../lib/clang/<major>/include. The rest of the 1.5 GB archive (about 7.6 GB unpacked) is not kept.
step "LLVM $LLVM_VERSION (clang-tidy + clang-format only)"
llvm_store="$shared/llvm-$LLVM_SHA256"
llvm_prefix="LLVM-${LLVM_VERSION}-macOS-ARM64"
if [[ ! -x "$llvm_store/bin/clang-tidy" || ! -d "$llvm_store/lib/clang/$LLVM_MAJOR/include" ]]; then
    download "$LLVM_URL" "$LLVM_SHA256" "$dl/llvm.tar.xz"
    rm -rf "$llvm_store.partial" && mkdir -p "$llvm_store.partial"
    tar -xJf "$dl/llvm.tar.xz" -C "$llvm_store.partial" --strip-components=1 \
        "$llvm_prefix/bin/clang-tidy" "$llvm_prefix/bin/clang-format" "$llvm_prefix/lib/clang/$LLVM_MAJOR/include" \
        || die "could not extract clang-tidy and clang-format from the LLVM archive (truncated? delete $cache_root/archives/$LLVM_SHA256 and re-run)"
    rm -rf "$llvm_store" && mv "$llvm_store.partial" "$llvm_store"
    rm -f "$cache_root/archives/$LLVM_SHA256"     # the 1.5 GB archive is not needed once its two tools are out
fi
[[ -x "$llvm_store/bin/clang-format" ]] || die "LLVM has no bin/clang-format (the manifest's LLVM_URL is wrong)"
ln -sf "$llvm_store/bin/clang-tidy" "$bin_dir/clang-tidy"
ln -sf "$llvm_store/bin/clang-format" "$bin_dir/clang-format"
assert_version "clang-tidy" "$LLVM_VERSION" "$("$bin_dir/clang-tidy" --version | sed -nE 's/.*version ([0-9.]+).*/\1/p' | head -1)"
assert_version "clang-format" "$LLVM_VERSION" "$("$bin_dir/clang-format" --version | sed -nE 's/.*version ([0-9.]+).*/\1/p' | head -1)"

# ---------------------------------------------------------------- cppcheck (source build, shared by checksum)
step "cppcheck $CPPCHECK_VERSION (source build)"
cpp_prefix="$shared/cppcheck-$CPPCHECK_SHA256"
if [[ ! -x "$cpp_prefix/bin/cppcheck" ]]; then
    download "$CPPCHECK_URL" "$CPPCHECK_SHA256" "$dl/cppcheck.tar.gz"
    cpp_src="$shared/cppcheck-src-$CPPCHECK_SHA256"
    rm -rf "$cpp_src" && mkdir -p "$cpp_src"
    tar -xzf "$dl/cppcheck.tar.gz" -C "$cpp_src" --strip-components=1 \
        || die "could not extract the cppcheck source"
    # FILESDIR must sit inside the prefix (cppcheck's Makefile refuses to install without it).
    make -C "$cpp_src" -j"$(sysctl -n hw.ncpu)" MATCHCOMPILER=yes FILESDIR="$cpp_prefix/share/cppcheck" \
        CXXFLAGS="-O2 -DNDEBUG" >"$tool_dir/cppcheck-build.log" 2>&1 \
        || die "cppcheck build failed; see $tool_dir/cppcheck-build.log"
    make -C "$cpp_src" install PREFIX="$cpp_prefix" FILESDIR="$cpp_prefix/share/cppcheck" >>"$tool_dir/cppcheck-build.log" 2>&1 \
        || die "cppcheck install failed; see $tool_dir/cppcheck-build.log"
    rm -rf "$cpp_src"
fi
ln -sf "$cpp_prefix/bin/cppcheck" "$bin_dir/cppcheck"
assert_version "cppcheck" "$CPPCHECK_VERSION" "$("$bin_dir/cppcheck" --version)"

# ---------------------------------------------------------------- semgrep (pip, hash-locked, venv shared by the lock)
step "semgrep $SEMGREP_VERSION (pip --require-hashes, Python $PYTHON_VERSION)"
PYTHON_BIN="$(command -v "python$PYTHON_VERSION" || true)"
[[ -n "$PYTHON_BIN" ]] || die "python$PYTHON_VERSION is not on PATH. The hash-locked wheels are built for $PYTHON_VERSION. Install Python $PYTHON_VERSION (python.org or the runner's toolcache) and re-run."
venv="$shared/semgrep-$reqs_hash"
if [[ ! -x "$venv/bin/semgrep" ]]; then
    rm -rf "$venv"
    "$PYTHON_BIN" -m venv "$venv" || die "python venv creation failed with $PYTHON_BIN"
    "$venv/bin/pip" install --quiet --require-hashes --disable-pip-version-check -r "$reqs" \
        || die "semgrep install failed: pip refused the hashes or a wheel. The lock is $reqs"
fi
ln -sf "$venv/bin/semgrep" "$bin_dir/semgrep"
# semgrep's CLI re-enters through `pysemgrep` and runs `semgrep-core` by name, both resolved from PATH.
# Homebrew ships its own pysemgrep (1.175.0 here), which would silently run instead of the pinned one.
ln -sf "$venv/bin/pysemgrep" "$bin_dir/pysemgrep"
core="$("$venv/bin/python3" -c 'import os, semgrep; print(os.path.join(os.path.dirname(semgrep.__file__), "bin", "semgrep-core"))')"
[[ -x "$core" ]] || die "semgrep's bundled semgrep-core is missing at $core"
ln -sf "$core" "$bin_dir/semgrep-core"
assert_version "semgrep" "$SEMGREP_VERSION" "$(PATH="$bin_dir:$PATH" "$bin_dir/semgrep" --version 2>/dev/null)"
assert_version "semgrep-core" "$SEMGREP_VERSION" "$(PATH="$bin_dir:$PATH" "$bin_dir/semgrep-core" -version 2>/dev/null | sed -nE 's/.*version: ([0-9.]+).*/\1/p')"

# ---------------------------------------------------------------- actionlint (pinned tarball)
step "actionlint $ACTIONLINT_VERSION"
download "$ACTIONLINT_URL" "$ACTIONLINT_SHA256" "$dl/actionlint.tar.gz"
tar -xzf "$dl/actionlint.tar.gz" -C "$bin_dir" actionlint || die "could not extract actionlint"
chmod +x "$bin_dir/actionlint"
assert_version "actionlint" "$ACTIONLINT_VERSION" "$("$bin_dir/actionlint" -version | head -1)"

# ---------------------------------------------------------------- shellcheck (pinned release archive)
step "shellcheck $SHELLCHECK_VERSION"
download "$SHELLCHECK_URL" "$SHELLCHECK_SHA256" "$dl/shellcheck.tar.gz"
tar -xzf "$dl/shellcheck.tar.gz" -C "$bin_dir" --strip-components=1 "shellcheck-v$SHELLCHECK_VERSION/shellcheck" \
    || die "could not extract shellcheck from its archive"
chmod +x "$bin_dir/shellcheck"
assert_version "shellcheck" "$SHELLCHECK_VERSION" "$("$bin_dir/shellcheck" --version | sed -nE 's/^version: //p')"

# ---------------------------------------------------------------- done: record what every tool file must hash to
rm -rf "$dl"
for f in "$bin_dir"/*; do shasum -a 256 "$f"; done > "$tool_dir/bin.sha256"
date -u +%Y-%m-%dT%H:%M:%SZ > "$tool_dir/.complete"
prune_old
step "installed"
green "toolchain ready: $tool_dir"
announce
