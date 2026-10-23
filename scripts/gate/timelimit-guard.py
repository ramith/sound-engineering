#!/usr/bin/env python3
"""timelimit-guard.py <root> — every @Suite in a Swift test file that WAITS must carry .timeLimit.

A file "waits" when it calls one of the wait helpers (until, untilBlocking, waitUntil, settled, quiesce,
untilOnMainRunLoop). testing.md promises the rule; this makes it a gate. A @Suite with no .timeLimit in a
waiting file is a named failure. Exit 0 when the tree is clean, 1 otherwise, with the file:line of each.
Known limit: a file that only calls a helper defined in ANOTHER file is not seen as waiting.
"""
import glob
import os
import re
import sys

WAIT = re.compile(r"\b(until|untilBlocking|waitUntil|settled|quiesce|untilOnMainRunLoop)\s*[({]")
SUITE = re.compile(r"^@Suite\b")


def check(root):
    bad = []
    count = 0
    for p in sorted(glob.glob(os.path.join(root, "**", "*.swift"), recursive=True)):
        text = open(p, encoding="utf-8").read()
        if not WAIT.search(text):
            continue
        lines = text.split("\n")
        for n, line in enumerate(lines, 1):
            if SUITE.match(line):
                # The attribute may span lines (wrapped at 120 columns): read it up to its closing ")" line.
                attr = [line]
                if line.rstrip().endswith("("):
                    for follow in lines[n:]:
                        attr.append(follow)
                        if follow.strip() == ")":
                            break
                count += 1
                if "timeLimit" not in "\n".join(attr):
                    bad.append("%s:%d: a @Suite in a file that waits has no .timeLimit" % (p, n))
    return count, bad


if __name__ == "__main__":
    count, bad = check(sys.argv[1])
    for b in bad:
        print("RED " + b)
    if bad:
        print("timelimit-guard: %d suite(s) without .timeLimit" % len(bad))
        sys.exit(1)
    print("timelimit-guard: %d waiting-file suites, all with .timeLimit" % count)
    print("GATE_COVERED %d suites" % count)
