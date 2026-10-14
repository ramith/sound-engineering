import json, sys
cls=json.load(open(sys.argv[1]))
excl=sys.argv[2] if len(sys.argv)>2 else "@@"
for i,c in enumerate(cls,1):
    fs=c["files"]
    if all(excl in f for f in fs): continue
    print(f'C{i} files={c["nfiles"]} pairs={c["npairs"]} maxtok={c["max_tokens"]} maxsim={c["max_sim"]} kinds={c["kinds"]} duplines={c["dup_lines"]}')
    for f,iv in list(fs.items())[:8]:
        print("    ",f, ", ".join(f"{a}-{b}" for a,b in iv[:6]), "..." if len(iv)>6 else "")
    if len(fs)>8: print("     ... +",len(fs)-8,"files")
