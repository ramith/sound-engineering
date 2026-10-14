import json, sys
repo="/Users/ramith/code/sound-engineering"
d=json.load(open(sys.argv[1]))
excl=sys.argv[2].split(",") if len(sys.argv)>2 and sys.argv[2] else []
minsim=float(sys.argv[3]) if len(sys.argv)>3 else 0
mintok=int(sys.argv[4]) if len(sys.argv)>4 else 0
show=int(sys.argv[5]) if len(sys.argv)>5 else 0
cache={}
def lines(f):
    if f not in cache: cache[f]=open(repo+"/"+f,errors="replace").read().split("\n")
    return cache[f]
i=0
for c in d["clones"]:
    if any(e in c["a"]+c["b"] for e in excl): continue
    if c["ident_sim"]<minsim or c["tokens"]<mintok: continue
    i+=1
    print(f'#{i} {c["kind"]} tok={c["tokens"]} lines={c["lines"]} cov={c["coverage"]} sim={c["ident_sim"]} ren={c["renames"]}  {c["a"]}:{c["a_lines"][0]}-{c["a_lines"][1]}  <->  {c["b"]}:{c["b_lines"][0]}-{c["b_lines"][1]}')
    if show:
        for side in "ab":
            lo,hi=c[side+"_lines"]
            for ln in lines(c[side])[lo-1:min(hi,lo-1+show)]: print("   ",side,"|",ln[:150])
print("count",i)
