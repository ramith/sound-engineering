#!/usr/bin/env bash
#
# strict-gate.sh — the full pre-merge gate. A thin wrapper over the step registry.
#
# The steps live in scripts/gate/steps.tsv and run through scripts/gate/run.sh. This file no longer
# holds a step list, so local `make strict-gate`, `make ci`, the pre-push tiers and every CI job
# cannot diverge. It runs EVERY step to completion (collect-all), prints each failure's head, and its
# exit code is the verdict. Mapping from the old inline steps to registry ids: scripts/gate/README.md.
#
# Equivalent to:  scripts/gate/run.sh --tier ci
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$repo_root/scripts/gate/run.sh" --tier ci "$@"
