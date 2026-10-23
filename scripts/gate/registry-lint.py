#!/usr/bin/env python3
"""registry-lint.py [--registry FILE] [--root DIR] — the registry and CI must agree (review M5).

Red when:
  - a row does not have 8 tab-separated columns, or its blocking / timeout / needs field is malformed;
  - a row's job is not a job in .github/workflows/strict-ci.yml (the step would never run in CI);
  - a row's tiers lack `ci` (make strict-gate / --tier ci would never run it);
  - a row's `needs` names no step;
  - a macOS runs-on in any workflow is not the manifest's RUNNER_LABEL (or the macos-26 compatibility runner);
  - a CI job's timeout-minutes is below the sum of its steps' caps plus 20 minutes of setup (L1).
Prints one RED line per problem, and "registry-lint: OK" with GATE_COVERED <rows> otherwise.
"""
import glob
import os
import re
import sys

args = sys.argv[1:]
root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
reg = os.path.join(root, "scripts", "gate", "steps.tsv")
while args:
    if args[0] == "--registry":
        reg = args[1]
    elif args[0] == "--root":
        root = os.path.abspath(args[1])
    else:
        sys.exit("unknown option " + args[0])
    args = args[2:]

red = []
rows = []
for n, line in enumerate(open(reg, encoding="utf-8"), 1):
    if not line.strip() or line.startswith("#") or line.startswith("id\t"):
        continue
    cols = line.rstrip("\n").split("\t")
    if len(cols) != 8:
        red.append("%s:%d: row has %d columns, wants 8" % (reg, n, len(cols)))
        continue
    rows.append((n, cols))
ids = {c[0] for _, c in rows}

env = {}
manifest = os.path.join(root, "toolchain", "toolchain.env")
if os.path.exists(manifest):
    for line in open(manifest, encoding="utf-8"):
        m = re.match(r"^([A-Z_]+)=(.*)$", line.strip())
        if m:
            env[m.group(1)] = m.group(2)
label = env.get("RUNNER_LABEL", "")
if not label:
    red.append("toolchain/toolchain.env has no RUNNER_LABEL: the macOS runner is then unchecked")

ci_path = os.path.join(root, ".github", "workflows", "strict-ci.yml")
ci_jobs = {}
ci_text = open(ci_path, encoding="utf-8").read()
for m in re.finditer(r"^  ([a-z0-9_-]+):\n((?:    .*\n|\n)*)", ci_text, re.M):
    t = re.search(r"timeout-minutes: (\d+)", m.group(2))
    if t:
        ci_jobs[m.group(1)] = int(t.group(1))

def minutes(spec):
    m = re.fullmatch(r"(\d+)([smh])", spec)
    if not m:
        return None
    n, u = int(m.group(1)), m.group(2)
    return n / 60 if u == "s" else (n if u == "m" else n * 60)

caps = {}
for n, c in rows:
    sid, job, tiers, blocking, timeout, coverage, needs, command = c
    if blocking not in ("yes", "no"):
        red.append("%s:%d: %s: blocking must be yes or no, not '%s'" % (reg, n, sid, blocking))
    if minutes(timeout) is None:
        red.append("%s:%d: %s: timeout '%s' is not like 90s, 5m or 1h" % (reg, n, sid, timeout))
    if job not in ci_jobs:
        red.append("%s:%d: %s: job '%s' is not a job in strict-ci.yml: the step would never run in CI" % (reg, n, sid, job))
    if "ci" not in tiers.split(","):
        red.append("%s:%d: %s: tiers '%s' lack ci: make strict-gate would never run it" % (reg, n, sid, tiers))
    if needs != "-" and needs not in ids:
        red.append("%s:%d: %s: needs '%s', which is no step in the registry" % (reg, n, sid, needs))
    if minutes(timeout) is not None:
        caps[job] = caps.get(job, 0) + minutes(timeout)

for job, cap in sorted(caps.items()):
    if job in ci_jobs and ci_jobs[job] < cap + 20:
        red.append("strict-ci.yml: job %s has timeout-minutes %d, below its steps' caps (%g) plus 20 min setup: "
                   "the job timeout would fire before the step watchdogs" % (job, ci_jobs[job], cap))

allowed = {label, "macos-26", "ubuntu-latest"} - {""}
for wf in sorted(glob.glob(os.path.join(root, ".github", "workflows", "*.yml"))):
    for n, line in enumerate(open(wf, encoding="utf-8"), 1):
        m = re.match(r"^\s*runs-on:\s*(\S+)\s*$", line)
        if m and m.group(1) not in allowed and m.group(1).startswith(("macos", "xcode")):
            red.append("%s:%d: runs-on %s is not the manifest's RUNNER_LABEL (%s) or the macos-26 compatibility runner"
                       % (os.path.relpath(wf, root), n, m.group(1), label))

for r in red:
    print("RED " + r)
if red:
    print("registry-lint: %d problem(s)" % len(red))
    sys.exit(1)
print("registry-lint: OK (%d rows, %d CI jobs, runner %s)" % (len(rows), len(ci_jobs), label))
print("GATE_COVERED %d rows" % len(rows))
