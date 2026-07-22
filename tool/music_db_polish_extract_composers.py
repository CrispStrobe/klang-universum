import os, glob, json
from collections import Counter
SRC="/mnt/volume1/polish-scores-tmp"
def hdr(path):
    m={}
    try:
        for ln in open(path,encoding="utf-8",errors="replace"):
            if ln.startswith("!!!"):
                kv=ln[3:].split(":",1)
                if len(kv)==2: m.setdefault(kv[0].strip(),kv[1].strip())
            elif not ln.startswith("!") and m: break
    except Exception: pass
    return m
krns=glob.glob(f"{SRC}/**/*.krn",recursive=True)
print("krn files:",len(krns))
comp=Counter(); rows=[]
for k in krns:
    m=hdr(k)
    c=(m.get("COM") or "").strip()
    if "," in c and c.count(",")==1:
        a,b=[s.strip() for s in c.split(",",1)]; c=f"{b} {a}" if a and b else c
    rows.append((k,c,m.get("OTL","")))
    if c: comp[c]+=1
print("unique composers:",len(comp))
print("entries with a composer:",sum(1 for _,c,_ in rows if c),"| without:",sum(1 for _,c,_ in rows if not c))
json.dump({c:n for c,n in comp.items()},open("/tmp/polish_composers.json","w"),ensure_ascii=False)
print("top 25:")
for c,n in comp.most_common(25): print(f"  {n:4} {c}")
