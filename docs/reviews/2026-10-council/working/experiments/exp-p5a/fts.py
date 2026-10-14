import sqlite3, unicodedata
print("sqlite", sqlite3.sqlite_version)
titles = ["මිල","මාල","මුල","මල","අමරදේව ගීත","ගීතය", unicodedata.normalize("NFD","Café del Mar"), "Björk", unicodedata.normalize("NFD","노래"), "東京事変"]
for tok in ["unicode61 remove_diacritics 2", "unicode61 remove_diacritics 2 categories 'L* N* Co M*'", "unicode61 remove_diacritics 2 categories 'L* N* Co Mn Mc'", "trigram remove_diacritics 1"]:
    db = sqlite3.connect(":memory:")
    db.execute(f"create virtual table f using fts5(title, tokenize=\"{tok}\")")
    for i,t in enumerate(titles): db.execute("insert into f(rowid,title) values(?,?)",(i,t))
    out=[]
    for q in ["මාල","මිල","ගීත","අමරදේව","cafe","café","bjork","björk","노래","事変"]:
        mq = '"%s"*' % q if not tok.startswith("trigram") else '"%s"' % q
        try:
            r=[titles[x[0]] for x in db.execute("select rowid from f where f match ?", (mq,))]
        except Exception as e: r=["ERR "+str(e)]
        out.append(f"{q}→{r}")
    print("\n["+tok+"]\n  "+"\n  ".join(out))
