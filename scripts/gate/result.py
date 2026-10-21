#!/usr/bin/env python3
"""Result records for scripts/gate/run.sh and scripts/gate/report.sh (stdlib only).

  result.py write <json-path> <id> <job> <blocking> <status> <exit> <seconds> <timeout> \
                  <reason> <log-path> <coverage>
      Writes one step's record. The failing head (first 50 matching lines, or the last 50
      lines when nothing matches) is read from the log, so the record is self-contained.

  result.py render <results-dir>
      Prints a markdown table of every step record under <results-dir> (recursive), plus a
      verdict line. Exit 0 only when every BLOCKING record passed. Missing or unreadable
      records are reported as failures, never ignored.
"""
import glob
import json
import os
import re
import sys

# Failure lines: compiler and linter diagnostics, test-framework failures, the runner's own markers.
# Case-sensitive on purpose: a file named AudioBridgeError.swift is not a failure.
FAIL_PAT = re.compile(
    r": (error|warning): |\bERROR\b|\bFAILED\b|\bfailed\b|timed out|Fatal error|Symbol not found|"
    r"Failed to open|Expectation failed|recorded an issue|\[HANG\]|NAMED HANG|✘|❌|GATE_COVERED 0|Terminated",
)
HEAD = 50


def failing_head(log_path):
    try:
        with open(log_path, encoding="utf-8", errors="replace") as fh:
            lines = [ln.rstrip("\n") for ln in fh]
    except OSError:
        return ["<log missing: %s>" % log_path]
    hits = [ln for ln in lines if FAIL_PAT.search(ln)]
    chosen = hits[:HEAD] if hits else lines[-HEAD:]
    return chosen


def covered(log_path):
    """The last `GATE_COVERED <n> ...` line's count, or None when absent."""
    n = None
    try:
        with open(log_path, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                m = re.match(r"GATE_COVERED (\d+)", ln)
                if m:
                    n = int(m.group(1))
    except OSError:
        return None
    return n


def cmd_write(a):
    path, sid, job, blocking, status, rc, secs, timeout, reason, log, cov = a
    if status == "pass":
        head = []
    elif status == "skipped":
        head = [reason]              # a skip has no log; its reason is the head
    else:
        head = failing_head(log)
    rec = {
        "id": sid,
        "job": job,
        "blocking": blocking == "yes",
        "status": status,            # pass | fail | timeout | skipped
        "exit_code": int(rc),
        "duration_s": int(float(secs)),
        "timeout": timeout,
        "reason": reason,
        "coverage_rule": cov,
        "covered": covered(log) if cov != "-" and status != "skipped" else None,
        "log": log,
        "failing_lines": head,
    }
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(rec, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def cmd_render(results_dir):
    recs = []
    bad_files = []
    for p in sorted(glob.glob(os.path.join(results_dir, "**", "*.json"), recursive=True)):
        if os.path.basename(p) == "run.json":
            continue
        try:
            with open(p, encoding="utf-8") as fh:
                recs.append(json.load(fh))
        except (OSError, ValueError) as exc:
            bad_files.append("%s (%s)" % (p, exc))
    recs.sort(key=lambda r: (r.get("job", ""), r.get("id", "")))
    ok = not bad_files
    print("| job | step | verdict | time | reason |")
    print("|---|---|---|---|---|")
    for r in recs:
        verdict = r["status"].upper()
        if r["blocking"] and r["status"] != "pass":
            ok = False
        if not r["blocking"] and r["status"] != "pass":
            verdict += " (advisory)"
        reason = r.get("reason", "") or ""
        print("| %s | %s | %s | %ss | %s |" % (r["job"], r["id"], verdict, r.get("duration_s", "?"), reason))
    for b in bad_files:
        print("| ? | ? | UNREADABLE | - | %s |" % b)
    print()
    print("VERDICT: %s" % ("PASS" if ok and recs else "FAIL"))
    if not recs:
        print("(no step records found under %s: nothing ran)" % results_dir)
    return 0 if ok and recs else 1


def cmd_head(path):
    with open(path, encoding="utf-8") as fh:
        rec = json.load(fh)
    for ln in rec.get("failing_lines", [])[:HEAD]:
        print("    | " + ln)
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "write" and len(argv) == 13:
        cmd_write(argv[2:])
        return 0
    if len(argv) == 3 and argv[1] == "render":
        return cmd_render(argv[2])
    if len(argv) == 3 and argv[1] == "head":
        return cmd_head(argv[2])
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
