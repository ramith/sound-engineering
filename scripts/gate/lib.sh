# shellcheck shell=bash
#
# scripts/gate/lib.sh — helpers shared by the step scripts. SOURCED, never executed.
#   fail <msg...>          print to stderr and exit 1
#   tracked <pathspec...>  print the git-tracked files under the given paths (one per line)
#   covered <n> <unit>     the coverage line the runner requires (n must be >= 1)
#
# Step scripts lint and analyse TRACKED files, never a directory walk: an agent worktree's
# parent-checkout configs and untracked scratch must not decide a verdict.

fail() {
    printf '\033[31mERROR: %s\033[0m\n' "$*" >&2
    exit 1
}

tracked() {
    git ls-files -- "$@"
}

covered() {
    printf 'GATE_COVERED %s %s\n' "$1" "$2"
}
