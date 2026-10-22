#!/usr/bin/env bash
#
# nightly-issue.sh <title> <body-file> — a failing nightly opens or updates ONE GitHub issue with this title
# (founder decision H5). It comments with the run and never blocks a merge. Needs GH_TOKEN with issues: write.
set -uo pipefail
title="${1:-}"
body="${2:-}"
[[ -n "$title" && -s "$body" ]] || { echo "usage: nightly-issue.sh <title> <body-file>" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "nightly-issue: gh is not installed; the failure is NOT reported as an issue" >&2; exit 0; }

number="$(gh issue list --state open --search "in:title \"$title\"" --json number,title \
    --jq ".[] | select(.title == \"$title\") | .number" 2>/dev/null | head -1)"
if [[ -n "$number" ]]; then
    gh issue edit "$number" --body-file "$body" >/dev/null && \
        gh issue comment "$number" --body "Still failing: run ${GITHUB_RUN_ID:-local} (${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-})." >/dev/null
    echo "nightly-issue: updated #$number"
else
    gh issue create --title "$title" --body-file "$body" >/dev/null && echo "nightly-issue: opened a new issue"
fi
exit 0
