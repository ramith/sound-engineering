# shellcheck shell=bash
#
# scripts/toolchain/use-pinned.sh — SOURCED by the git hooks (pre-commit, pre-push). It puts the PINNED
# toolchain first on PATH, so a hook formats and analyses with exactly the tools the gate verifies.
#
# Installed (the install script wrote its .complete marker): the cache bin dir goes first on PATH and
# ADAPTIVESOUND_TOOL_BIN names it. Not installed: say so plainly, and the hook keeps today's behaviour,
# which is the tools already on PATH. Nothing here installs anything.
_pinned_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_pinned_bin="$(env -u TOOLCHAIN_ENV "$_pinned_root/scripts/toolchain/install.sh" --print-bin 2>/dev/null)"
if [[ -n "$_pinned_bin" && -f "$(dirname "$_pinned_bin")/.complete" ]]; then
    export PATH="$_pinned_bin:$PATH"
    export ADAPTIVESOUND_TOOL_BIN="$_pinned_bin"
else
    export ADAPTIVESOUND_TOOL_BIN=""
    printf '\033[33mNOTE: the pinned toolchain is not installed (run "make toolchain"). This hook uses the tools on PATH, which may not be the gate'"'"'s versions.\033[0m\n' >&2
fi
unset _pinned_root _pinned_bin
