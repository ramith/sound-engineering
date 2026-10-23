#!/usr/bin/env bash
#
# scripts/gate/run.sh — the gate runner. Every local tier, every `make` gate target and every CI
# job calls this, so local and CI run the SAME steps from the SAME registry (scripts/gate/steps.tsv).
#
#   scripts/gate/run.sh --tier ci              # everything (T4); CI runs it as parallel jobs
#   scripts/gate/run.sh --tier check           # T2: the lane's "done" bar
#   scripts/gate/run.sh --job cpp              # one CI job's steps
#   scripts/gate/run.sh --step null-asan --step store-asan
#   scripts/gate/run.sh --list                 # the registry as a table
#
# Rules this runner enforces:
#   - COLLECT-ALL. A failing step never stops the run. Every selected step runs to completion.
#     Only a real dependency is skipped, and a skip is recorded as "skipped: <why>", never green.
#   - PARITY FIRST. toolchain-parity runs before anything else, every time. If it fails, every
#     other step is skipped with that reason: a verdict from the wrong tools means nothing.
#   - EVERY STEP HAS A CEILING. Each step runs in its OWN process group under a bash watchdog
#     (macOS has no `timeout`). On expiry the group gets TERM, then KILL, and the step is named
#     "timed out after <limit>". An EXIT/INT/TERM trap kills whatever is still running.
#   - ZERO IS A FAILURE. A step whose registry row has coverage files|tests must print
#     `GATE_COVERED <n> <unit>` with n >= 1, or it fails. `swift test` running 0 tests fails.
#   - THE EXIT CODE IS THE VERDICT. 0 only if every BLOCKING step passed. Advisory steps are
#     reported (and marked "(advisory)") but never turn the run red.
#   - EVERY RUN REPORTS EVERYTHING. results/<id>.json per step (status, time, the failing head,
#     the log path), full logs in logs/<id>.log, summary.md, run.json for the report job.
#
# Output: .build/gate/<label>-<UTC stamp>/ (gitignored). Override with GATE_RUN_DIR.
# Bash 3.2 compatible (macOS /bin/bash): no associative arrays, no mapfile, no ${x,,}.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# GATE_REGISTRY overrides the registry for planted-failure proofs only (never set in CI).
registry="${GATE_REGISTRY:-$repo_root/scripts/gate/steps.tsv}"
result_py="$repo_root/scripts/gate/result.py"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
die()    { red "ERROR: $*" >&2; exit 2; }

usage() {
    sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

# ----------------------------------------------------------------- arguments
mode=""
selector=""
steps_req=()
list_only=0
while (($#)); do
    case "$1" in
        --tier) mode=tier; selector="${2:-}"; [[ -n "$selector" ]] || die "--tier needs a value"; shift 2 ;;
        --job)  mode=job;  selector="${2:-}"; [[ -n "$selector" ]] || die "--job needs a value"; shift 2 ;;
        --step) mode=step; [[ -n "${2:-}" ]] || die "--step needs a value"; steps_req+=("$2"); shift 2 ;;
        --list) list_only=1; shift ;;
        -h|--help) usage ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

[[ -f "$registry" ]] || die "registry missing: $registry"

# Read the registry: header and # comments skipped, registry order kept.
all_rows=()
while IFS= read -r line; do
    case "$line" in ''|'#'*|'id	'*) continue ;; esac
    all_rows+=("$line")
done < "$registry"
((${#all_rows[@]})) || die "the registry has no steps: $registry"

if ((list_only)); then
    printf '%-22s %-7s %-30s %-9s %-7s %-9s %s\n' ID JOB TIERS BLOCKING TIMEOUT COVERAGE COMMAND
    for row in "${all_rows[@]}"; do
        IFS=$'\t' read -r id job tiers blocking timeout coverage needs command <<< "$row"
        printf '%-22s %-7s %-30s %-9s %-7s %-9s %s\n' "$id" "$job" "$tiers" "$blocking" "$timeout" "$coverage" "$command"
    done
    exit 0
fi

[[ -n "$mode" ]] || { red "pick one of --tier, --job, --step (or --list)"; usage; }

# A misspelt --step is a FAILURE, never a silent no-op.
if [[ "$mode" == "step" ]]; then
    for want in "${steps_req[@]}"; do
        found=0
        for row in "${all_rows[@]}"; do
            IFS=$'\t' read -r id _rest <<< "$row"
            [[ "$id" == "$want" ]] && found=1
        done
        ((found)) || die "no step named '$want' in $registry (see --list)"
    done
fi

selected=()
for row in "${all_rows[@]}"; do
    IFS=$'\t' read -r id job tiers blocking timeout coverage needs command <<< "$row"
    take=0
    case "$mode" in
        tier) case ",$tiers," in *",$selector,"*) take=1 ;; esac ;;
        job)  [[ "$job" == "$selector" ]] && take=1 ;;
        step) for want in "${steps_req[@]}"; do [[ "$want" == "$id" ]] && take=1; done ;;
    esac
    ((take)) && selected+=("$row")
done
((${#selected[@]})) || die "the selection matched no steps ($mode=${selector:-${steps_req[*]}})"

# Parity always runs first, whatever was selected.
parity_row=""
for row in "${all_rows[@]}"; do
    IFS=$'\t' read -r id _rest <<< "$row"
    [[ "$id" == "toolchain-parity" ]] && parity_row="$row"
done
[[ -n "$parity_row" ]] || die "the registry has no toolchain-parity row"
ordered=("$parity_row")
for row in "${selected[@]}"; do
    IFS=$'\t' read -r id _rest <<< "$row"
    [[ "$id" == "toolchain-parity" ]] || ordered+=("$row")
done

# ----------------------------------------------------------------- run directory
if [[ "$mode" == "step" ]]; then
    label="step-${steps_req[0]}"
    ((${#steps_req[@]} > 1)) && label="step-multi"
else
    label="$mode-$selector"
fi
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="${GATE_RUN_DIR:-$repo_root/.build/gate/$label-$stamp}"
mkdir -p "$run_dir/results" "$run_dir/logs" || die "cannot create $run_dir"
export GATE_RUN_DIR="$run_dir" GATE_MODE="$mode" GATE_SELECTOR="${selector:-${steps_req[*]}}"

# The installed toolchain goes first on PATH, exactly as CI and the parity check see it.
tool_bin="$(env -u TOOLCHAIN_ENV "$repo_root/scripts/toolchain/install.sh" --print-bin)"
[[ -n "$tool_bin" ]] || die "install.sh printed no tool directory: the toolchain cannot be located"
export PATH="$tool_bin:$PATH"

# ----------------------------------------------------------------- process control
# `set -m`: every background job gets its own process group (pgid == leader pid), so a step's
# whole tree is signalled as one unit and the watchdog can be killed without touching the step.
set -m
current_pgid=""
# The signal handler is inline: the running step's whole process group gets TERM, then KILL after 2 s, the
# null-test lock is released, and the run says it was interrupted. (A named handler here was only ever called
# from the trap, which shellcheck cannot see as a call.)
trap 'if [[ -n "$current_pgid" ]]; then kill -TERM -- "-$current_pgid" 2>/dev/null; sleep 2; kill -KILL -- "-$current_pgid" 2>/dev/null; fi; release_null_lock; red "gate interrupted: running step killed; partial results are in $run_dir"; exit 130' INT TERM

# timeout_seconds <spec>: 90s | 5m | 1h -> seconds
timeout_seconds() {
    local spec="$1" n unit
    n="${spec%[smh]}"
    unit="${spec##*[0-9]}"
    case "$unit" in
        s|"") echo "$n" ;;
        m) echo $((n * 60)) ;;
        h) echo $((n * 3600)) ;;
        *) die "bad timeout '$spec' in the registry" ;;
    esac
}

# run_step <id> <timeout> <coverage> <command>
# Sets STEP_STATUS (pass|fail|timeout), STEP_REASON, STEP_RC, STEP_SECS, STEP_LOG.
# One checkout must never run two null-test processes at once: their fixtures share test-data/ paths.
# The runner runs steps one after another, so this guards a SECOND gate run started in the same checkout
# (a `make check` beside a `make ci`). A lock held by a dead pid is stale and is taken over.
null_lock="$repo_root/.build/gate/null-test.lock"
acquire_null_lock() {
    local waited=0 cap=14400
    mkdir -p "$(dirname "$null_lock")"
    until mkdir "$null_lock" 2>/dev/null; do
        local holder
        holder="$(cat "$null_lock/pid" 2>/dev/null || true)"
        if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
            rm -rf "$null_lock"; continue
        fi
        if ((waited % 60 == 0)); then echo "    waiting: another null-test run holds $null_lock (pid ${holder:-?})"; fi
        if ((waited >= cap)); then
            red "null-test lock still held by pid ${holder:-?} after $((cap / 60)) min: a stuck run. Stop it and re-run."
            exit 1
        fi
        sleep 5; waited=$((waited + 5))
    done
    echo $$ > "$null_lock/pid"
}
release_null_lock() {
    [[ "$(cat "$null_lock/pid" 2>/dev/null)" == "$$" ]] && rm -rf "$null_lock"
    return 0
}

run_step() {
    local sid="$1" limit="$2" coverage="$3" command="$4"
    local locked=0
    export GATE_STEP_ID="$sid"
    if [[ "$command" == *build-null-test.sh* || "$command" == *null-run.sh* ]]; then
        acquire_null_lock; locked=1
    fi
    local log="$run_dir/logs/$sid.log" flag="$run_dir/logs/.$sid.timedout"
    local secs start end rc pid pgid wd covered
    secs="$(timeout_seconds "$limit")"
    rm -f "$flag"
    start=$(date +%s)
    (cd "$repo_root" && exec bash -c "$command") >"$log" 2>&1 &
    pid=$!
    pgid="$pid"
    current_pgid="$pgid"
    # Watchdog in its own group: it names the timeout and kills the step's whole group. Its stderr
    # is closed: when the step ends first the watchdog is killed mid-`sleep`, and bash would print
    # "Terminated: 15 sleep" into the gate's console for every step.
    (
        exec 2>/dev/null
        sleep "$secs"
        if kill -0 -- "-$pgid" 2>/dev/null; then
            : > "$flag"
            kill -TERM -- "-$pgid" 2>/dev/null
            sleep 5
            kill -KILL -- "-$pgid" 2>/dev/null
        fi
    ) &
    wd=$!
    # The step's exit code is read from `wait`; its stderr is closed so a step killed by its watchdog
    # does not also print the shell's job notice ("[1]- Terminated: 15 ...") — the result row names it.
    wait "$pid" 2>/dev/null
    rc=$?
    kill -TERM -- "-$wd" 2>/dev/null
    wait "$wd" 2>/dev/null
    current_pgid=""
    end=$(date +%s)
    STEP_SECS=$((end - start))
    STEP_RC=$rc
    STEP_LOG="$log"
    if [[ -f "$flag" ]]; then
        STEP_STATUS=timeout
        STEP_REASON="timed out after $limit (watchdog killed the step)"
    elif grep -q '^\[HANG\]' "$log"; then
        # The null test's watchdog named the test that ran past its ceiling. Classified by that line,
        # never by the exit code: 134 also means a plain abort, such as an ASan report.
        STEP_STATUS=timeout
        STEP_REASON="named hang: $(grep -m1 '^\[HANG\]' "$log" | cut -c1-160)"
    elif ((rc != 0)); then
        STEP_STATUS=fail
        STEP_REASON="exit $rc"
    elif [[ "$coverage" != "-" ]]; then
        covered="$(grep -E '^GATE_COVERED [0-9]+' "$log" | tail -1 | awk '{print $2}')"
        if [[ -z "$covered" ]]; then
            STEP_STATUS=fail
            STEP_REASON="exit 0 but no 'GATE_COVERED <n>' line: a $coverage step must report what it covered"
        elif ((covered < 1)); then
            STEP_STATUS=fail
            STEP_REASON="covered 0 $coverage: a check that checks nothing is not a pass"
        else
            STEP_STATUS=pass
            STEP_REASON="covered $covered $coverage"
        fi
    else
        STEP_STATUS=pass
        STEP_REASON=""
    fi
    rm -f "$flag"
    ((locked)) && release_null_lock
    return 0
}

# record <id> <job> <blocking> <timeout> <coverage> <status> <rc> <secs> <reason> <log>
record() {
    python3 "$result_py" write "$run_dir/results/$1.json" "$1" "$2" "$3" "$6" "$7" "$8" "$4" "$9" "${10}" "$5" \
        || red "could not write the result record for $1"
}

# ----------------------------------------------------------------- the loop (collect-all)
total=${#ordered[@]}
n=0
parity_failed=0
ids=(); jobs=(); blockings=(); statuses=(); secs_list=(); reasons=()

echo "gate: $mode ${selector:-${steps_req[*]}}  ($total steps)"
echo "run dir: $run_dir"
echo "toolchain first on PATH: $tool_bin"
echo

for row in "${ordered[@]}"; do
    IFS=$'\t' read -r sid job tiers blocking limit coverage needs command <<< "$row"
    n=$((n + 1))
    printf '[%2d/%d] %-22s ' "$n" "$total" "$sid"

    skip_reason=""
    if [[ "$sid" != "toolchain-parity" ]] && ((parity_failed)); then
        skip_reason="toolchain-parity failed: the tools are not the pinned ones"
    elif [[ "$needs" != "-" ]]; then
        dep_status="not run"
        for i in "${!ids[@]}"; do
            [[ "${ids[$i]}" == "$needs" ]] && dep_status="${statuses[$i]}"
        done
        if [[ "$dep_status" != "pass" ]]; then
            skip_reason="needs $needs, which is $dep_status"
        fi
    fi

    if [[ -n "$skip_reason" ]]; then
        STEP_STATUS=skipped
        STEP_REASON="skipped: $skip_reason"
        STEP_SECS=0
        STEP_RC=0
        STEP_LOG="-"
        yellow "SKIPPED ($skip_reason)"
    else
        run_step "$sid" "$limit" "$coverage" "$command"
        if [[ "$STEP_STATUS" == fail || "$STEP_STATUS" == timeout ]] && [[ "${GITHUB_ACTIONS:-}" == true ]]; then
            echo "::error title=$sid::$STEP_STATUS: $STEP_REASON"
        fi
        case "$STEP_STATUS" in
            pass)    green "PASS    ${STEP_SECS}s${STEP_REASON:+  ($STEP_REASON)}" ;;
            timeout) red   "TIMEOUT ${STEP_SECS}s  $STEP_REASON" ;;
            fail)
                if [[ "$blocking" == yes ]]; then
                    red "FAIL    ${STEP_SECS}s  $STEP_REASON"
                else
                    yellow "FAIL    ${STEP_SECS}s  $STEP_REASON (advisory: not blocking)"
                fi ;;
        esac
    fi

    if [[ "$sid" == "toolchain-parity" && "$STEP_STATUS" != pass ]]; then
        parity_failed=1
        red "toolchain-parity failed: every other step in this run is skipped. Fix the tools (see its table) and re-run."
    fi

    record "$sid" "$job" "$blocking" "$limit" "$coverage" "$STEP_STATUS" "$STEP_RC" "$STEP_SECS" "$STEP_REASON" "$STEP_LOG"

    ids+=("$sid"); jobs+=("$job"); blockings+=("$blocking")
    statuses+=("$STEP_STATUS"); secs_list+=("$STEP_SECS"); reasons+=("$STEP_REASON")

    if [[ "$STEP_STATUS" == fail || "$STEP_STATUS" == timeout ]]; then
        echo "    --- head of $sid (full log: $STEP_LOG) ---"
        python3 "$result_py" head "$run_dir/results/$sid.json"
        echo "    ---"
    fi
done

# ----------------------------------------------------------------- verdict
blocking_bad=0
for i in "${!ids[@]}"; do
    if [[ "${blockings[$i]}" == yes && "${statuses[$i]}" != pass ]]; then
        blocking_bad=$((blocking_bad + 1))
    fi
done

summary="$run_dir/summary.md"
{
    echo "## Gate: $mode ${selector:-${steps_req[*]}}"
    echo
    echo "| job | step | verdict | time | reason |"
    echo "|---|---|---|---|---|"
    for i in "${!ids[@]}"; do
        v="${statuses[$i]}"
        [[ "${statuses[$i]}" != pass && "${blockings[$i]}" != yes ]] && v="$v (advisory)"
        echo "| ${jobs[$i]} | ${ids[$i]} | $v | ${secs_list[$i]}s | ${reasons[$i]} |"
    done
    echo
} > "$summary"
cat "$summary"

if ((blocking_bad)); then
    rc=1
    red "GATE FAILED: $blocking_bad blocking step(s) did not pass. Each failure's head is printed above; full logs are in $run_dir/logs."
else
    rc=0
    green "GATE PASSED: every blocking step passed ($total steps, $mode ${selector:-${steps_req[*]}})."
fi
python3 "$result_py" runjson "$run_dir" "$mode" "${selector:-${steps_req[*]}}" "$rc"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then cat "$summary" >> "$GITHUB_STEP_SUMMARY"; fi
echo "exit: $rc  (this code is the verdict)"
exit "$rc"
