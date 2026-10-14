"""Group clone pairs into clone classes (connected components over overlapping regions)."""
import json, sys, collections
src, out = sys.argv[1], sys.argv[2]
minsim = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
d = json.load(open(src))
cl = [c for c in d["clones"] if c["ident_sim"] >= minsim]
parent = {}
def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]; x = parent[x]
    return x
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb: parent[ra] = rb
regions = []
for i, c in enumerate(cl):
    for s in "ab":
        r = (c[s], c[s + "_lines"][0], c[s + "_lines"][1], i)
        parent[r] = r; regions.append(r)
for i, c in enumerate(cl):
    union((c["a"], *c["a_lines"], i), (c["b"], *c["b_lines"], i))
byfile = collections.defaultdict(list)
for r in regions: byfile[r[0]].append(r)
for f, rs in byfile.items():
    rs.sort(key=lambda r: r[1])
    cur_end, cur = -1, None
    for r in rs:
        if cur is not None and r[1] <= cur_end:
            union(r, cur)
            if r[2] > cur_end: cur_end, cur = r[2], r
        else:
            cur_end, cur = r[2], r
comp = collections.defaultdict(list)
for r in regions: comp[find(r)].append(r)
classes = []
for k, rs in comp.items():
    files = collections.defaultdict(list)
    for f, lo, hi, _ in rs: files[f].append((lo, hi))
    spans = {}
    for f, iv in files.items():
        iv.sort(); m = []
        for lo, hi in iv:
            if m and lo <= m[-1][1] + 1: m[-1][1] = max(m[-1][1], hi)
            else: m.append([lo, hi])
        spans[f] = m
    pairs = sorted({r[3] for r in rs})
    cs = [cl[i] for i in pairs]
    classes.append(dict(files=spans, nfiles=len(spans), npairs=len(pairs),
                        max_tokens=max(c["tokens"] for c in cs), max_sim=max(c["ident_sim"] for c in cs),
                        kinds=sorted({c["kind"] for c in cs}),
                        dup_lines=sum(hi - lo + 1 for iv in spans.values() for lo, hi in iv)))
classes.sort(key=lambda c: -c["max_tokens"])
json.dump(classes, open(out, "w"), indent=1)
print("pairs", len(cl), "classes", len(classes))
