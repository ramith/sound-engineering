#!/usr/bin/env python3
"""Gate records, the run stamp, and the CI summary (stdlib only).

  result.py write <json-path> <id> <job> <blocking> <status> <exit> <seconds> <timeout> \
                  <reason> <log-path> <coverage>
      One step's record. Stamped with this run's identity (see stamp()). The failing head is read
      from the log so the record is self-contained.

  result.py runjson <run-dir> <mode> <selector> <exit-code>
      run.json: the job's verdict and its stamp. A job's artifact must hold exactly one of these.

  result.py summary <artifact-root> [--registry FILE] [--stamp S]
      The `strict-gate` summary. Reads, per registry job, ONLY <root>/gate-<job>/**/run.json (exactly one,
      stamped with this run) and <root>/gate-<job>/**/results/*.json (step records). Anything else is a
      named RED row, never a crash:
        - a job with no run.json, or several, or one from another run (stale);
        - a record that does not parse, lacks fields, names another job, or another run;
        - a registry step with no record;
        - a record for a step the registry does not have;
        - a blocking step that did not pass.
      Advisory rows are shown and never turn it red. Exit 0 only when nothing is red.

  result.py render is gone: it globbed every JSON, including the semgrep and GoogleTest files.
  result.py head <record.json>: the failing head of one record.
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
RECORD_KEYS = ("id", "job", "blocking", "status", "run")


def stamp():
    """This run's identity. CI: run id, attempt and commit, so a record from any other run is visible.
    Local: 'local'. Every job of one CI attempt shares the same stamp."""
    rid = os.environ.get("GITHUB_RUN_ID")
    if rid:
        return "%s.%s.%s" % (rid, os.environ.get("GITHUB_RUN_ATTEMPT", "1"), os.environ.get("GITHUB_SHA", "nosha"))
    return "local"


def failing_head(log_path):
    try:
        with open(log_path, encoding="utf-8", errors="replace") as fh:
            lines = [ln.rstrip("\n") for ln in fh]
    except OSError:
        return ["<log missing: %s>" % log_path]
    hits = [ln for ln in lines if FAIL_PAT.search(ln)]
    return hits[:HEAD] if hits else lines[-HEAD:]


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
        head = [reason]
    else:
        head = failing_head(log)
    rec = {
        "id": sid,
        "job": job,
        "run": stamp(),
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


def cmd_runjson(run_dir, mode, selector, rc):
    os.makedirs(run_dir, exist_ok=True)
    with open(os.path.join(run_dir, "run.json"), "w", encoding="utf-8") as fh:
        json.dump({"mode": mode, "selector": selector, "exit_code": int(rc), "stamp": stamp()}, fh, indent=2)
        fh.write("\n")
    return 0


def registry_rows(path):
    """(id, job, blocking) for every step row, in registry order."""
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if not line.strip() or line.startswith("#") or line.startswith("id\t"):
                continue
            cols = line.rstrip("\n").split("\t")
            rows.append((cols[0], cols[1], cols[3] == "yes"))
    return rows


def summary(root, reg_path, expect_stamp):
    rows = registry_rows(reg_path)
    jobs = []
    for _, job, _ in rows:
        if job not in jobs:
            jobs.append(job)
    red = []          # named problems, each one a red row
    table = []        # (job, id, verdict, secs, reason)
    for job in jobs:
        art = os.path.join(root, "gate-" + job)
        expected = {sid: blocking for sid, j, blocking in rows if j == job}
        # A job's own records sit at the top of its artifact: run.json and results/ at the root, or one
        # level down (a run directory uploaded from its parent). Anything deeper is NOT this job's —
        # e.g. the summary self-test's fixture trees, which once sat inside the static job's run directory
        # and made every CI summary red ("expected exactly one run.json … found 36", PR #95).
        runs = sorted(glob.glob(os.path.join(art, "run.json")) + glob.glob(os.path.join(art, "*", "run.json")))
        if len(runs) != 1:
            red.append((job, "-", "job %s: expected exactly one run.json in its artifact, found %d "
                                  "(missing: cancelled, timed out or crashed; duplicate: a re-upload)" % (job, len(runs))))
        else:
            try:
                meta = json.load(open(runs[0], encoding="utf-8"))
                if meta.get("stamp") != expect_stamp:
                    red.append((job, "-", "job %s: run.json is from another run (stamp %s, this run %s): stale"
                                % (job, meta.get("stamp"), expect_stamp)))
                if meta.get("mode") != "job" or meta.get("selector") != job:
                    red.append((job, "-", "job %s: run.json says it ran %s %s, not this job" % (
                        job, meta.get("mode"), meta.get("selector"))))
            except (OSError, ValueError, AttributeError) as exc:
                red.append((job, "-", "job %s: unreadable run.json (%s)" % (job, exc)))
        seen = set()
        for p in sorted(glob.glob(os.path.join(art, "results", "*.json"))
                        + glob.glob(os.path.join(art, "*", "results", "*.json"))):
            try:
                rec = json.load(open(p, encoding="utf-8"))
            except (OSError, ValueError) as exc:
                red.append((job, os.path.basename(p), "unreadable record %s (%s)" % (p, exc)))
                continue
            if not isinstance(rec, dict) or any(k not in rec for k in RECORD_KEYS):
                red.append((job, os.path.basename(p), "malformed record %s (fields missing)" % p))
                continue
            sid = rec["id"]
            if rec["run"] != expect_stamp:
                red.append((job, sid, "record from another run (stamp %s, this run %s): ignored, and red"
                            % (rec["run"], expect_stamp)))
                continue
            if rec["job"] != job:
                red.append((job, sid, "record says job %s but sits in %s" % (rec["job"], job)))
                continue
            if sid not in expected:
                red.append((job, sid, "step %s is not a %s row in the registry" % (sid, job)))
                continue
            if sid in seen:
                red.append((job, sid, "duplicate record for step %s" % sid))
                continue
            seen.add(sid)
            verdict = rec.get("status", "?").upper()
            if rec.get("blocking") and rec.get("status") != "pass":
                red.append((job, sid, "blocking step %s: %s" % (sid, rec.get("reason", ""))))
            if not rec.get("blocking") and rec.get("status") != "pass":
                verdict += " (advisory)"
            table.append((job, sid, verdict, rec.get("duration_s", "?"), rec.get("reason", "") or ""))
        for sid, blocking in expected.items():
            if sid not in seen:
                red.append((job, sid, "step %s has no result record (lost in the run)" % sid))
    table.sort()
    out = []
    out.append("| job | step | verdict | time | reason |")
    out.append("|---|---|---|---|---|")
    for job, sid, verdict, secs, reason in table:
        out.append("| %s | %s | %s | %ss | %s |" % (job, sid, verdict, secs, reason))
    for job, sid, text in red:
        out.append("| %s | %s | RED | - | %s |" % (job, sid, text))
    out.append("")
    ok = not red and bool(table)
    out.append("VERDICT: %s" % ("PASS" if ok else "FAIL"))
    if not table:
        out.append("(no step records found under %s: nothing ran)" % root)
    return ok, "\n".join(out) + "\n"


def cmd_summary(argv):
    root = argv[0]
    reg = os.path.join(os.path.dirname(os.path.abspath(__file__)), "steps.tsv")
    expect = stamp()
    rest = argv[1:]
    while rest:
        if rest[0] == "--registry":
            reg = rest[1]
        elif rest[0] == "--stamp":
            expect = rest[1]
        else:
            raise SystemExit("unknown option %s" % rest[0])
        rest = rest[2:]
    try:
        ok, text = summary(root, reg, expect)
    except Exception as exc:  # the check itself crashed: red, with the reason, never green
        sys.stdout.write("VERDICT: FAIL\nreport check crashed: %s: %s\n" % (type(exc).__name__, exc))
        return 1
    sys.stdout.write(text)
    return 0 if ok else 1


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
    if len(argv) == 6 and argv[1] == "runjson":
        return cmd_runjson(argv[2], argv[3], argv[4], argv[5])
    if len(argv) >= 3 and argv[1] == "summary":
        return cmd_summary(argv[2:])
    if len(argv) == 3 and argv[1] == "head":
        return cmd_head(argv[2])
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
