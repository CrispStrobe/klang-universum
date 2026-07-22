"""Ingest the PD-verified subset of humdrum-polish-scores. Ships composers with
life+70 status PD or NO_AUTHOR (anonymous); HOLDS unknown-composer works; drops
RECENT/ALIVE. CC BY 4.0 (attribution)."""
import os, glob, json, shutil, re
SRC="/mnt/volume1/polish-scores-tmp"; ROOT="/mnt/volume1/music-db"
SHIP=f"{ROOT}/nifc/ship/polish"; os.makedirs(SHIP,exist_ok=True)
cls=json.load(open("/tmp/polish_classify.json"))
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
def normc(c):
    c=(c or "").strip()
    if "," in c and c.count(",")==1:
        a,b=[s.strip() for s in c.split(",",1)]
        if a and b: c=f"{b} {a}"
    return c
items=[]; held=[]; excl=0; SHIP_ST={"PD","NO_AUTHOR"}
for i,k in enumerate(sorted(glob.glob(f"{SRC}/**/*.krn",recursive=True))):
    m=hdr(k); comp=normc(m.get("COM"))
    st=cls.get(comp,{}).get("status","UNKNOWN")
    title=(m.get("OTL") or os.path.basename(k)).strip().rstrip(".") or os.path.basename(k)
    if st not in SHIP_ST:
        (held if st=="UNKNOWN" else None)
        if st=="UNKNOWN": held.append({"composer":comp,"title":title,"file":os.path.relpath(k,SRC)})
        else: excl+=1
        continue
    rel=os.path.relpath(k,SRC).replace("/","_")
    fn=f"{i:05d}_{os.path.basename(k)}"
    shutil.copyfile(k,f"{SHIP}/{fn}")
    anon=(st=="NO_AUTHOR")
    items.append({"id":f"nifc_polish_{i:05d}","title":title[:180],
        "author":None if anon else comp,"author_full":None if anon else comp,
        "poet":None,"year":None,"transcribed":None,
        "instrument":m.get("AIN","") or "","instruments":[],"editor":"score",
        "ensemble":False,"licence":"Creative Commons Attribution 4.0",
        "source":"NIFC Polish Scores","source_url":"https://github.com/pl-wnifc/humdrum-polish-scores",
        "attribution":"NIFC / pl-wnifc (CC BY 4.0)","format":"krn","tier":"ship",
        "rights_status":"NO_AUTHOR" if anon else "PD",
        "rights_method":("anonymous — no life+70 clock" if anon else
                         f"composer life+70 verified PD (Wikidata: {cls.get(comp,{}).get('death')})"),
        "verified_from":"krn !!!COM + Wikidata life+70",
        "path":f"nifc/ship/polish/{fn}"})
json.dump(items,open(f"{ROOT}/polish-manifest.json","w"),indent=1,ensure_ascii=False)
json.dump(held,open(f"{ROOT}/polish_held.json","w"),indent=1,ensure_ascii=False)
from collections import Counter
print(f"SHIPPED {len(items)}  HELD(unknown) {len(held)}  EXCLUDED(recent/alive) {excl}")
print("shipped rights:",dict(Counter(x['rights_status'] for x in items)))
print("held unique composers:",len(set(h['composer'] for h in held)))
