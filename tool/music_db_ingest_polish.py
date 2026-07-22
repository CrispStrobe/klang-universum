"""Authoritative polish-scores ingest. Ships iff (a) parseable by our reader AND
(b) axis-2 clear: composer with !!!CDT latest year <=1955, OR anonymous WITH a
pre-1955 date (publication/source). Holds: unknown-date composers, UNDATED
anonymous (EU: anon = 70y from publication — undated can't be proven PD),
unparseable. Drops: composer/anon dated >1955."""
import os, glob, re, json, shutil
SRC="/mnt/volume1/polish-scores-tmp"; ROOT="/mnt/volume1/music-db"
SHIP=f"{ROOT}/nifc/ship/polish"
shutil.rmtree(SHIP, ignore_errors=True); os.makedirs(SHIP, exist_ok=True)
fails=set(l.split("\t")[0] for l in open("/tmp/polish_parsefail.txt") if l.strip())
ANON={"anonim","anonymous","anon","anon.","traditional","incerti auctoris",""}
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
def maxyear(*vals):
    ys=[]
    for v in vals: ys+=[int(y) for y in re.findall(r"1[0-9]{3}|20[0-2][0-9]",v or "")]
    return max(ys) if ys else None
items=[]; held=[]; dropped=0; i=0
for k in sorted(glob.glob(f"{SRC}/**/*.krn",recursive=True)):
    rel=os.path.relpath(k,SRC); m=hdr(k)
    comp=normc(m.get("COM")); title=(m.get("OTL") or os.path.basename(k)).strip().rstrip(".") or os.path.basename(k)
    anon=comp.lower() in ANON
    if rel in fails:
        held.append({"file":rel,"composer":comp,"reason":"unparseable"}); continue
    if anon:
        y=maxyear(m.get("PDT"),m.get("CDT"),m.get("ODT"),m.get("SMS-shelfwork"),m.get("SMS-shelfmark"))
        if y is None: held.append({"file":rel,"composer":"(anonymous)","reason":"anon-undated"}); continue
        if y>1955: dropped+=1; continue
        rs,rm_,auth="NO_AUTHOR",f"anonymous, source dated {y} (>70y, PD)",None
    else:
        y=maxyear(m.get("CDT"))
        if y is None: held.append({"file":rel,"composer":comp,"reason":"composer-undated"}); continue
        if y>1955: dropped+=1; continue
        rs,rm_,auth="PD",f"composer !!!CDT latest {y} <=1955 (PD)",comp
    i+=1; fn=f"{i:05d}_{os.path.basename(k)}"; shutil.copyfile(k,f"{SHIP}/{fn}")
    items.append({"id":f"nifc_polish_{i:05d}","title":title[:180],"author":auth,
        "author_full":auth,"poet":None,"year":str(y),"transcribed":None,
        "instrument":m.get("AIN","") or "","instruments":[],"editor":"score","ensemble":False,
        "licence":"Creative Commons Attribution 4.0","source":"NIFC Polish Scores",
        "source_url":"https://github.com/pl-wnifc/humdrum-polish-scores",
        "attribution":"NIFC / pl-wnifc (CC BY 4.0)","format":"krn","tier":"ship",
        "rights_status":rs,"rights_method":rm_,"verified_from":"krn !!!CDT/!!!PDT + parse-check",
        "path":f"nifc/ship/polish/{fn}"})
json.dump(items,open(f"{ROOT}/polish-manifest.json","w"),indent=1,ensure_ascii=False)
json.dump(held,open(f"{ROOT}/polish_held.json","w"),indent=1,ensure_ascii=False)
from collections import Counter
print(f"SHIPPED {len(items)}  HELD {len(held)}  DROPPED(>1955) {dropped}")
print("ship rights:",dict(Counter(x['rights_status'] for x in items)))
print("held reasons:",dict(Counter(h['reason'] for h in held)))
