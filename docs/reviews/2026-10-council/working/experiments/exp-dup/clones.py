#!/usr/bin/env python3
"""Token-shingle clone detector (Type-1 / Type-2 / near-miss Type-3) for Swift and C/C++/ObjC++.

Method (CPD-style, "ignore identifiers + ignore literals"):
  1. Lex each tracked file (git ls-files) into tokens; drop comments, import/#include/#pragma lines.
  2. Normalise: identifiers -> $id, string literals -> $str, numbers -> $num; keywords and punctuation kept.
  3. Rabin-Karp hash every window of K normalised tokens; bucket equal hashes.
  4. For every left-maximal pair in a bucket, extend forward while normalised tokens agree.
  5. Keep matches >= K tokens and >= MINLINES lines in both copies.
  6. Merge matches between the same two files that are separated by a small gap (<= GAP tokens on both
     sides) into one near-miss (Type-3) clone.
  7. Similarity = share of identifier/literal positions whose RAW text is identical (1.0 = verbatim).
Usage: clones.py REPO --roots Sources [Tests] [--cross Sources Tests] --out PREFIX [-k 40] [--min-lines 6]
"""
import argparse, json, os, re, subprocess, sys
from collections import defaultdict

SWIFT_KW = set("""associatedtype class deinit enum extension fileprivate func import init inout internal let open
operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch
continue default defer do else fallthrough for guard if in repeat return throw switch where while as Any await
false is nil self Self super throws true try async actor some any nonisolated isolated consuming borrowing
convenience dynamic final indirect lazy mutating nonmutating optional override required unowned weak willSet
didSet get set""".split())
C_KW = set("""alignas alignof and asm auto bool break case catch char char8_t char16_t char32_t class co_await
co_return co_yield concept const consteval constexpr constinit const_cast continue decltype default delete do double
dynamic_cast else enum explicit export extern false float for friend goto if inline int long mutable namespace new
noexcept not nullptr operator or private protected public register reinterpret_cast requires return short signed
sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typeid
typename union unsigned using virtual void volatile wchar_t while override final size_t uint32_t int32_t uint64_t
int64_t uint8_t int16_t uint16_t std id self nil YES NO NULL BOOL interface implementation end property
synthesize atomic nonatomic strong weak assign readonly readwrite nullable nonnull instancetype""".split())

OPS = sorted("""... ..< <<= >>= === !== -> :: == != <= >= && || ++ -- += -= *= /= %= &= |= ^= << >> ?? &+ &- &*
""".split(), key=len, reverse=True)

ID_RE = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
NUM_RE = re.compile(r"0[xX][0-9a-fA-F_']+(\.[0-9a-fA-F_']*)?([pP][+-]?\d+)?[a-zA-Z]*|\d[\d_']*(\.\d[\d_']*)?([eE][+-]?\d+)?[a-zA-Z]*|\.\d[\d_']*([eE][+-]?\d+)?[a-zA-Z]*")


def lang_of(path):
    return "swift" if path.endswith(".swift") else "c"


def lex(src, lang):
    """Return list of (kind, text, line). kind in {kw, id, str, num, op}."""
    toks = []
    i, n, line = 0, len(src), 1
    kws = SWIFT_KW if lang == "swift" else C_KW
    at_line_start = True
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1; i += 1; at_line_start = True; continue
        if c in " \t\r\f\v":
            i += 1; continue
        # line-level skips: imports / includes / pragmas
        if at_line_start:
            rest = src[i:i + 40]
            if (lang == "swift" and re.match(r"(@preconcurrency\s+|@testable\s+|@_implementationOnly\s+)?import\s", rest)) or \
               (lang == "c" and re.match(r"#\s*(include|import|pragma)\b", rest)) or \
               (lang == "swift" and re.match(r"#(sourceLocation)", rest)):
                j = src.find("\n", i)
                i = n if j < 0 else j
                continue
        at_line_start = False
        # comments
        if src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j) and lang == "swift":
                    depth += 1; j += 2
                elif src.startswith("*/", j):
                    depth -= 1; j += 2
                else:
                    if src[j] == "\n": line += 1
                    j += 1
            i = j; continue
        # strings
        if lang == "swift" and (c == '"' or (c == "#" and re.match(r'#+"', src[i:i + 8]))):
            start_line = line
            hashes = 0
            j = i
            while j < n and src[j] == "#": hashes += 1; j += 1
            if src.startswith('"""', j):
                close = '"""' + "#" * hashes
                k = src.find(close, j + 3)
                k = n if k < 0 else k + len(close)
                line += src.count("\n", i, k)
                toks.append(("str", src[i:k], start_line)); i = k; continue
            close = '"' + "#" * hashes
            k = j + 1
            while k < n:
                if src[k] == "\\" and hashes == 0:
                    if k + 1 < n and src[k + 1] == "(":
                        depth, k = 1, k + 2
                        while k < n and depth:
                            if src[k] == "(": depth += 1
                            elif src[k] == ")": depth -= 1
                            elif src[k] == '"':
                                k2 = src.find('"', k + 1); k = n if k2 < 0 else k2
                            k += 1
                        continue
                    k += 2; continue
                if src.startswith(close, k): k += len(close); break
                if src[k] == "\n": break
                k += 1
            toks.append(("str", src[i:k], start_line)); i = k; continue
        if lang == "c" and (c == '"' or (c == "@" and i + 1 < n and src[i + 1] == '"') or (c == "R" and i + 1 < n and src[i + 1] == '"') or (c in "uUL" and re.match(r'(u8|u|U|L)R?"', src[i:i + 4]))):
            m = re.match(r'(u8|u|U|L)?R"([^(\s]*)\(', src[i:i + 40])
            start_line = line
            if m:
                delim = ")" + m.group(2) + '"'
                k = src.find(delim, i + m.end())
                k = n if k < 0 else k + len(delim)
                line += src.count("\n", i, k)
                toks.append(("str", src[i:k], start_line)); i = k; continue
            j = src.find('"', i)
            k = j + 1
            while k < n and src[k] != '"':
                if src[k] == "\\": k += 1
                if k < n and src[k] == "\n": line += 1
                k += 1
            k += 1
            toks.append(("str", src[i:k], start_line)); i = k; continue
        if lang == "c" and c == "'":
            k = i + 1
            while k < n and src[k] != "'":
                if src[k] == "\\": k += 1
                k += 1
            k += 1
            toks.append(("str", src[i:k], line)); i = k; continue
        # numbers
        if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit() and (not toks or toks[-1][0] not in ("id", "num"))):
            m = NUM_RE.match(src, i)
            if m and m.end() > i:
                toks.append(("num", m.group(0), line)); i = m.end(); continue
        # identifiers / keywords / attributes / directives
        if c == "`" and lang == "swift":
            k = src.find("`", i + 1)
            if k > 0:
                toks.append(("id", src[i + 1:k], line)); i = k + 1; continue
        if c in "@#" and i + 1 < n and (src[i + 1].isalpha() or src[i + 1] == "_"):
            m = ID_RE.match(src, i + 1)
            word = c + m.group(0)
            toks.append(("kw", word, line)); i = m.end(); continue
        m = ID_RE.match(src, i)
        if m:
            w = m.group(0)
            toks.append(("kw" if w in kws else "id", w, line)); i = m.end(); continue
        # operators
        for op in OPS:
            if src.startswith(op, i):
                toks.append(("op", op, line)); i += len(op); break
        else:
            toks.append(("op", c, line)); i += 1
    return toks


MODE = "weak"


def norm(tok):
    k, t, _ = tok
    if k == "id": return "$id" if MODE == "weak" else t
    if k == "str": return "$str" if MODE in ("weak", "mild") else t
    if k == "num": return "$num" if MODE in ("weak", "mild") else t
    return t


class Corpus:
    def __init__(self):
        self.files, self.raw, self.normi, self.lines, self.group, self.lang = [], [], [], [], [], []
        self.vocab = {}

    def add(self, path, src, group):
        lang = lang_of(path)
        toks = lex(src, lang)
        ids = []
        for t in toks:
            nt = lang + ":" + norm(t)
            v = self.vocab.get(nt)
            if v is None:
                v = self.vocab[nt] = len(self.vocab) + 1
            ids.append(v)
        self.files.append(path); self.raw.append(toks); self.normi.append(ids)
        self.lines.append([t[2] for t in toks]); self.group.append(group); self.lang.append(lang)


def find_clones(cp, K, min_lines, gap, cross=None, bucket_cap=60):
    MOD = (1 << 61) - 1
    B = 1_000_003
    BK = pow(B, K - 1, MOD)
    buckets = defaultdict(list)
    for fi, ids in enumerate(cp.normi):
        if len(ids) < K: continue
        h = 0
        for j in range(K): h = (h * B + ids[j]) % MOD
        buckets[h].append((fi, 0))
        for p in range(1, len(ids) - K + 1):
            h = ((h - ids[p - 1] * BK) * B + ids[p + K - 1]) % MOD
            buckets[h].append((fi, p))
    matches = {}
    capped = 0
    capped_sites = defaultdict(int)
    for h, occ in buckets.items():
        if len(occ) < 2: continue
        if len(occ) > bucket_cap:
            capped += 1
            for fi, p in occ: capped_sites[cp.files[fi]] += 1
            occ = occ[:bucket_cap]
        for x in range(len(occ)):
            fa, a = occ[x]
            A = cp.normi[fa]
            for y in range(x + 1, len(occ)):
                fb, b = occ[y]
                if cross:
                    ga, gb = cp.group[fa], cp.group[fb]
                    if ga == gb: continue
                Bt = cp.normi[fb]
                if fa == fb and abs(a - b) < K: continue
                # left-maximal only
                if a > 0 and b > 0 and A[a - 1] == Bt[b - 1]: continue
                L = 0
                lim = min(len(A) - a, len(Bt) - b)
                if fa == fb: lim = min(lim, abs(b - a))
                while L < lim and A[a + L] == Bt[b + L]: L += 1
                if L < K: continue
                key = (fa, a, fb, b) if (fa, a) <= (fb, b) else (fb, b, fa, a)
                if key not in matches or matches[key] < L: matches[key] = L
    # line filter
    out = []
    for (fa, a, fb, b), L in matches.items():
        la = cp.lines[fa][a + L - 1] - cp.lines[fa][a] + 1
        lb = cp.lines[fb][b + L - 1] - cp.lines[fb][b] + 1
        if la < min_lines or lb < min_lines: continue
        out.append([fa, a, a + L, fb, b, b + L, L])
    # merge overlapping / near-miss (Type-3) fragments between the same two files into one clone
    byp = defaultdict(list)
    for r in out: byp[(r[0], r[3])].append(r)
    merged = []
    for key, lst in byp.items():
        lst.sort(key=lambda r: (r[1], r[4]))
        cur = []
        for r in lst:
            for m in cur:
                if r[1] <= m[2] + gap and m[1] <= r[2] + gap and r[4] <= m[5] + gap and m[4] <= r[5] + gap \
                   and (r[4] - r[1]) - (m[4] - m[1]) in range(-gap, gap + 1):
                    m[1], m[2] = min(m[1], r[1]), max(m[2], r[2])
                    m[4], m[5] = min(m[4], r[4]), max(m[5], r[5])
                    m[6] = max(m[6], r[6]) if (r[1] >= m[1] and r[2] <= m[2]) else m[6] + r[6]
                    break
            else:
                cur.append(list(r))
        merged.extend(cur)
    # score each merged clone: align with difflib on normalised ids, then compare raw identifiers/literals
    import difflib
    res = []
    for fa, a0, a1, fb, b0, b1, _ in merged:
        NA, NB = cp.normi[fa][a0:a1], cp.normi[fb][b0:b1]
        sm = difflib.SequenceMatcher(None, NA, NB, autojunk=False)
        matched = sum(blk.size for blk in sm.get_matching_blocks())
        param = same = 0
        renames = set()
        for blk in sm.get_matching_blocks():
            for off in range(blk.size):
                ta, tb = cp.raw[fa][a0 + blk.a + off], cp.raw[fb][b0 + blk.b + off]
                if ta[0] in ("id", "str", "num"):
                    param += 1
                    if ta[1] == tb[1]: same += 1
                    else: renames.add((ta[1], tb[1]))
        sim = same / param if param else 1.0
        span = max(a1 - a0, b1 - b0)
        cov = matched / span
        overlap = fa == fb and a1 > b0
        kind = "REP" if overlap else ("T1" if sim >= 0.98 and cov >= 0.98 else ("T3" if cov < 0.98 else "T2"))
        res.append(dict(
            a=cp.files[fa], a_lines=[cp.lines[fa][a0], cp.lines[fa][a1 - 1]],
            b=cp.files[fb], b_lines=[cp.lines[fb][b0], cp.lines[fb][b1 - 1]],
            tokens=span, matched=matched, coverage=round(cov, 3),
            ident_sim=round(sim, 3), renames=len(renames), kind=kind,
            lines=max(cp.lines[fa][a1 - 1] - cp.lines[fa][a0], cp.lines[fb][b1 - 1] - cp.lines[fb][b0]) + 1,
        ))
    res.sort(key=lambda d: -d["tokens"])
    return res, capped, capped_sites


def module_of(path):
    parts = path.split("/")
    if parts[0] == "Sources":
        if parts[1] == "AdaptiveSound" and len(parts) > 3:
            return "/".join(parts[:3]) if parts[2] in ("UI", "Debug", "Spectrum", "Monitoring") else "Sources/AdaptiveSound(root)"
        if parts[1] == "AdaptiveSound":
            return "Sources/AdaptiveSound(root)"
        if parts[1] == "AudioDSP" and len(parts) > 3:
            return "/".join(parts[:3])
        return "/".join(parts[:2])
    if parts[0] == "Tests":
        return "/".join(parts[:2]) if len(parts) > 2 else "Tests/(C++ harness)"
    return parts[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("--roots", nargs="+", required=True)
    ap.add_argument("--cross", action="store_true", help="only report pairs whose two files are in different roots")
    ap.add_argument("-k", type=int, default=40)
    ap.add_argument("--min-lines", type=int, default=6)
    ap.add_argument("--gap", type=int, default=12)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", choices=["strict", "mild", "weak"], default="weak")
    ap.add_argument("--min-sim", type=float, default=0.0, help="report only clones with ident_sim >= this")
    args = ap.parse_args()
    global MODE
    MODE = args.mode
    files = subprocess.run(["git", "-C", args.repo, "ls-files", *args.roots], capture_output=True, text=True, check=True).stdout.split()
    files = [f for f in files if re.search(r"\.(swift|cpp|mm|h|c|inc|m|hpp)$", f)]
    cp = Corpus()
    total_lines = defaultdict(int)
    for f in files:
        with open(os.path.join(args.repo, f), encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        root = f.split("/")[0]
        cp.add(f, src, root)
        total_lines[module_of(f)] += src.count("\n")
    res, capped, capped_sites = find_clones(cp, args.k, args.min_lines, args.gap, cross=args.cross)
    raw_count = len(res)
    raw_kinds = {k: sum(1 for r in res if r["kind"] == k) for k in ("T1", "T2", "T3", "REP")}
    res = [r for r in res if r["ident_sim"] >= args.min_sim]
    # duplicated-line accounting per module
    dup_lines = defaultdict(set)
    for r in res:
        for side in ("a", "b"):
            lo, hi = r[side + "_lines"]
            for ln in range(lo, hi + 1): dup_lines[r[side]].add(ln)
    mod_dup = defaultdict(int)
    for f, s in dup_lines.items(): mod_dup[module_of(f)] += len(s)
    summary = dict(files=len(files), tokens=sum(len(x) for x in cp.normi), raw_clones=raw_count, raw_by_kind=raw_kinds, clones=len(res),
                   by_kind={k: sum(1 for r in res if r["kind"] == k) for k in ("T1", "T2", "T3", "REP")},
                   capped_buckets=capped,
                   modules={m: dict(lines=total_lines[m], dup_lines=mod_dup.get(m, 0),
                                    pct=round(100 * mod_dup.get(m, 0) / max(1, total_lines[m]), 1),
                                    pairs=sum(1 for r in res if module_of(r["a"]) == m or module_of(r["b"]) == m))
                            for m in sorted(total_lines)},
                   settings=dict(mode=args.mode, min_sim=args.min_sim, k=args.k, min_lines=args.min_lines, gap=args.gap, roots=args.roots, cross=args.cross))
    with open(args.out + ".json", "w") as fh:
        json.dump(dict(summary=summary, clones=res), fh, indent=1)
    with open(args.out + ".md", "w") as fh:
        fh.write(f"# clones {args.roots} cross={args.cross}\n\n```\n{json.dumps({k: v for k, v in summary.items() if k != 'modules'}, indent=1)}\n```\n\n")
        fh.write("| module | lines | dup lines | % | pairs |\n|---|---|---|---|---|\n")
        for m, d in sorted(summary["modules"].items(), key=lambda kv: -kv[1]["dup_lines"]):
            fh.write(f"| {m} | {d['lines']} | {d['dup_lines']} | {d['pct']} | {d['pairs']} |\n")
        fh.write("\n| # | kind | tokens | lines | sim | A | B |\n|---|---|---|---|---|---|---|\n")
        for i, r in enumerate(res, 1):
            fh.write(f"| {i} | {r['kind']} | {r['tokens']} | {r['lines']} | {r['ident_sim']} | {r['a']}:{r['a_lines'][0]}-{r['a_lines'][1]} | {r['b']}:{r['b_lines'][0]}-{r['b_lines'][1]} |\n")
    print(json.dumps({k: v for k, v in summary.items() if k != "modules"}, indent=1))


if __name__ == "__main__":
    main()
