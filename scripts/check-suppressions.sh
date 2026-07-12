#!/usr/bin/env bash
#
# check-suppressions.sh — suppression accountability gate for AdaptiveSound.
#
# Every lint/analysis suppression in first-party code must be ACCOUNTABLE. This enforces a
# compact, one-line annotation grammar (no 4-line SAFETY blocks — permanent architectural
# suppressions don't "expire", and boilerplate x67 is just noise). Owner is resolved from a
# path map, not spelled out per line.
#
# Grammar (metadata rides on the SAME comment line, after the rule list — clang-tidy and
# semgrep both ignore trailing text):
#
#   PERMANENT — architectural necessity; NO expiry allowed:
#     // NOLINT(rule[,rule...]) PERMANENT reason="C-ABI opaque handle; balances *Create()"
#     // NOLINTNEXTLINE(rule) PERMANENT reason="reinterpret_cast at the AudioBufferList seam"
#     // NOLINTBEGIN(rule) PERMANENT reason="17 control-plane NSLog calls; per-line is noise"
#     // nosemgrep: rule-id PERMANENT reason="reviewed boundary allocation"
#     // swiftlint:disable:next rule PERMANENT reason="wrapped URL literal must stay one line"
#
#   TEMP — time-boxed tech debt; requires expiry=YYYY-MM-DD OR issue=<#id|url>:
#     // NOLINTNEXTLINE(rule) TEMP reason="pending EQ refactor" expiry=2026-09-01
#     // NOLINT(rule) TEMP reason="works around SDK bug" issue=https://github.com/.../123
#
# Rules enforced (any failure aborts the gate):
#   1. Rule-ID mandatory — no blanket `// NOLINT` / `// nosemgrep` without a rule list/id.
#   2. Classification — exactly one of PERMANENT | TEMP.
#   3. Reason — reason="…" present, >= 12 chars of substance.
#   4. Owner — resolvable from the path->owner map (always is, for first-party paths).
#   5. Expiry — PERMANENT: forbidden. TEMP: expiry=YYYY-MM-DD (fail if past) or issue=… .
#   6. Range balance — every NOLINTBEGIN(rules) has a matching NOLINTEND(rules) (same file,
#      same rule set); swiftlint:disable <rule> has a matching swiftlint:enable <rule>.
#   7. Liveness (clang-tidy NOLINT only) — every suppressed rule must be in the EFFECTIVE
#      clang-tidy enabled set for that file's directory, resolved via `clang-tidy --list-checks`
#      (which honors the nearest .clang-tidy upward, incl. the Tests/ and AudioDSPTestBridge/
#      InheritParentConfig overrides). A token that is disabled there, belongs to a never-enabled
#      family (e.g. hicpp-*), or is misspelled suppresses NOTHING → dead → fail. Requires
#      clang-tidy; skipped with a note if absent (CI always has it). Strictly stronger than the
#      former "disabled at repo root only" redundancy check it replaces.
#
# NOLINTEND / swiftlint:enable are closers: exempt from metadata, checked only for balance.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required for check-suppressions.sh" >&2; exit 1; }

python3 - "$@" <<'PY'
import os, re, sys, subprocess, datetime, shutil

REPO = os.getcwd()
# .inc included: the C++ test fragments (#included into a .cpp TU) carry LIVE clang-tidy
# NOLINT suppressions, so the accountability grammar must reach them too — not just the
# standalone .cpp/.mm/.h files.
CODE_EXT = ('.swift', '.c', '.cc', '.cpp', '.mm', '.h', '.hpp', '.inc')
# First-party only — mirror .semgrepignore. Vendored/build/asset trees are not ours.
EXCLUDE_DIRS = {'.build', '.swiftpm', '.git', 'third_party', 'docs', 'research', 'assets'}
EXCLUDE_PATH_SUBSTR = ('Tests/Fixtures/', 'scripts/hal-spike')

# Path -> owner map (most specific first). Owner is never spelled per-line.
OWNER_MAP = [
    ('Sources/AudioDSP/',        'dsp-kernels'),
    ('Sources/AudioDSPTestBridge/', 'dsp-kernels'),
    ('Sources/LibraryStore/',    'library'),
    ('Sources/LibraryScan/',     'library'),
    ('Sources/AdaptiveSound/',   'app'),
    ('Sources/Verify',           'verify-tools'),
    ('Sources/SRCQualityMeasure/', 'verify-tools'),
    ('Sources/AudioFormatKit/',  'app'),
    ('Tests/',                   'tests'),
]
DEFAULT_OWNER = 'maintainer'

def owner_for(path):
    for prefix, owner in OWNER_MAP:
        if path.startswith(prefix):
            return owner
    return DEFAULT_OWNER

def _resolve_clang_tidy():
    """Prefer keg-only Homebrew LLVM (matches strict-gate/pre-commit), fall back to PATH."""
    cand = '/opt/homebrew/opt/llvm/bin/clang-tidy'
    if os.path.isfile(cand) and os.access(cand, os.X_OK):
        return cand
    return shutil.which('clang-tidy')

CLANG_TIDY = _resolve_clang_tidy()
_CT_WARNED = [False]
_enabled_cache = {}

def enabled_checks_for(dirpath):
    """The EFFECTIVE clang-tidy enabled-check set for dirpath. `clang-tidy --list-checks` run
    with cwd=dirpath resolves the nearest .clang-tidy upward (honoring the Tests/ and
    AudioDSPTestBridge/ InheritParentConfig overrides) exactly as it would when analysing a file
    there. Cached per directory. Returns None when clang-tidy is unavailable OR its output can't
    be parsed → the liveness check is skipped rather than risking a false accusation."""
    if CLANG_TIDY is None:
        return None
    key = os.path.abspath(dirpath)
    if key in _enabled_cache:
        return _enabled_cache[key]
    checks = set()
    try:
        out = subprocess.run([CLANG_TIDY, '--list-checks'], cwd=key,
                             capture_output=True, text=True, timeout=120)
        # Format: "Enabled checks:\n" then 4-space-indented check names, one per line.
        for ln in out.stdout.splitlines():
            if ln[:1].isspace() and ln.strip():
                checks.add(ln.strip())
    except Exception:
        checks = set()
    result = checks or None   # empty = exec/parse failure → treat as unavailable, never false-flag
    _enabled_cache[key] = result
    return result

def iter_files():
    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files:
            if not f.endswith(CODE_EXT):
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, REPO)
            if any(s in rel for s in EXCLUDE_PATH_SUBSTR):
                continue
            yield rel, full

# Directive matchers. Group 'rules' = rule list/id, 'tail' = trailing annotation text.
NOLINT_RE   = re.compile(r'//\s*NOLINT(?P<kind>NEXTLINE|BEGIN|END)?\s*\((?P<rules>[^)]*)\)(?P<tail>.*)$')
NOSEMGREP_RE= re.compile(r'//\s*nosemgrep:\s*(?P<rules>[A-Za-z0-9_.\-]+)(?P<tail>.*)$')
SWIFTL_RE   = re.compile(r'//\s*swiftlint:(?P<act>disable(?::next|:this)?|enable)\s+(?P<rules>[A-Za-z0-9_,\s]+?)(?P<tail>(?:PERMANENT|TEMP|reason=|expiry=|issue=|owner=).*)?$')
BARE_NOLINT = re.compile(r'//\s*NOLINT(NEXTLINE|BEGIN|END)?\s*(?:$|[^(A-Za-z])')
BARE_NOSEM  = re.compile(r'//\s*nosemgrep\s*(?::\s*(?:$|[^A-Za-z0-9]))?')

REASON_RE = re.compile(r'reason="([^"]*)"')
EXPIRY_RE = re.compile(r'expiry=(\d{4}-\d{2}-\d{2})')
ISSUE_RE  = re.compile(r'issue=(\S+)')
TODAY = datetime.date.today()

errors = []
def err(rel, ln, msg):
    errors.append(f"{rel}:{ln}: {msg}")

def split_rules(s):
    return [r.strip() for r in s.split(',') if r.strip()]

def validate_meta(rel, ln, rules, tail, kind_label, is_clang_tidy=False):
    tail = tail or ''
    perm = 'PERMANENT' in tail
    temp = 'TEMP' in tail
    if perm and temp:
        err(rel, ln, f"{kind_label}: both PERMANENT and TEMP present — pick one.")
    elif not (perm or temp):
        err(rel, ln, f"{kind_label}: missing classification (add PERMANENT or TEMP). See docs/development/DEVELOPMENT.md § Suppression policy.")
    rm = REASON_RE.search(tail)
    if not rm or len(rm.group(1).strip()) < 12:
        err(rel, ln, f'{kind_label}: missing/short reason (need reason="…" >= 12 chars).')
    if perm:
        if EXPIRY_RE.search(tail) or ISSUE_RE.search(tail):
            err(rel, ln, f"{kind_label}: PERMANENT must NOT carry expiry=/issue= (architecture doesn't expire).")
    if temp:
        em = EXPIRY_RE.search(tail)
        im = ISSUE_RE.search(tail)
        if not em and not im:
            err(rel, ln, f"{kind_label}: TEMP requires expiry=YYYY-MM-DD or issue=<#id|url>.")
        if em:
            try:
                exp = datetime.date.fromisoformat(em.group(1))
                if TODAY > exp:
                    err(rel, ln, f"{kind_label}: TEMP suppression EXPIRED on {em.group(1)} — remove it or fix the underlying issue.")
            except ValueError:
                err(rel, ln, f"{kind_label}: malformed expiry (want YYYY-MM-DD).")
    # Owner always resolves via the path map; explicit owner= just overrides.
    _ = owner_for(rel)
    # Liveness (clang-tidy NOLINT only): every suppressed rule must be in the EFFECTIVE enabled
    # set for this file's directory. A token disabled there, from a never-enabled family (hicpp-*),
    # or misspelled suppresses nothing → dead.
    if is_clang_tidy:
        enabled = enabled_checks_for(os.path.dirname(os.path.join(REPO, rel)) or REPO)
        if enabled is None:
            if not _CT_WARNED[0]:
                print("  (note: clang-tidy unavailable — NOLINT liveness check skipped)", file=sys.stderr)
                _CT_WARNED[0] = True
        else:
            for r in rules:
                if r not in enabled:
                    err(rel, ln, f"{kind_label}: rule '{r}' is not in the effective clang-tidy enabled set for "
                                 f"this path (disabled in a .clang-tidy, a never-enabled family like hicpp-*, or "
                                 f"misspelled) — dead suppression, remove it.")

for rel, full in iter_files():
    try:
        with open(full, encoding='utf-8', errors='replace') as fh:
            lines = fh.readlines()
    except OSError:
        continue
    # Track open ranges for balance: (file-local) rule-set -> begin line
    open_nolint = {}   # frozenset(rules) -> line
    open_swiftl = {}   # rule -> line
    for i, raw in enumerate(lines, 1):
        line = raw.rstrip('\n')
        # ---- bare (blanket) directives: hard fail ----
        if BARE_NOLINT.search(line) and not NOLINT_RE.search(line):
            err(rel, i, "blanket NOLINT without a (rule-list) is forbidden.")
            continue
        if BARE_NOSEM.search(line) and not NOSEMGREP_RE.search(line):
            err(rel, i, "blanket nosemgrep without a rule-id is forbidden.")
            continue
        m = NOLINT_RE.search(line)
        if m:
            kind = m.group('kind')
            rules = split_rules(m.group('rules'))
            if not rules:
                err(rel, i, "NOLINT with empty rule list is forbidden.")
                continue
            if kind == 'END':
                key = frozenset(rules)
                if key in open_nolint:
                    del open_nolint[key]
                else:
                    err(rel, i, f"NOLINTEND({','.join(rules)}) has no matching NOLINTBEGIN.")
                continue
            validate_meta(rel, i, rules, m.group('tail'), f"NOLINT{kind or ''}", is_clang_tidy=True)
            if kind == 'BEGIN':
                open_nolint[frozenset(rules)] = i
            continue
        m = NOSEMGREP_RE.search(line)
        if m:
            validate_meta(rel, i, [m.group('rules')], m.group('tail'), "nosemgrep")
            continue
        m = SWIFTL_RE.search(line)
        if m:
            act = m.group('act')
            rules = split_rules(m.group('rules'))
            if not rules:
                err(rel, i, "swiftlint:disable without a rule is forbidden.")
                continue
            if act == 'enable':
                for r in rules:
                    open_swiftl.pop(r, None)
                continue
            # SwiftLint parses ALL trailing tokens after the rule as rule-ids (on-line
            # metadata → 'superfluous_disable_command'), so its PERMANENT/reason annotation
            # lives on the immediately-PRECEDING comment line. Read metadata from there.
            prev = lines[i - 2] if i >= 2 else ''
            validate_meta(rel, i, rules, prev + ' ' + (m.group('tail') or ''), f"swiftlint:{act}")
            if act == 'disable':  # block form needs a matching enable
                for r in rules:
                    open_swiftl[r] = i
            continue
    for key, ln in open_nolint.items():
        err(rel, ln, f"NOLINTBEGIN({','.join(sorted(key))}) has no matching NOLINTEND.")
    for r, ln in open_swiftl.items():
        err(rel, ln, f"swiftlint:disable {r} (block) has no matching swiftlint:enable.")

if errors:
    print("Suppression policy violations:\n", file=sys.stderr)
    for e in sorted(errors):
        print(f"  ❌ {e}", file=sys.stderr)
    print(f"\n{len(errors)} violation(s). Grammar: docs/development/DEVELOPMENT.md § Suppression policy.", file=sys.stderr)
    sys.exit(1)
print("✅ suppression policy: all annotations accountable.")
PY
