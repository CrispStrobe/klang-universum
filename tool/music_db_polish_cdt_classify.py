"""Reclassify polish-scores composers from the authoritative !!!CDT header dates
(composer's actual dates in the source metadata) — beats Wikidata. Latest year
in CDT <= 1955 -> PD; > 1955 -> RECENT; no year -> UNKNOWN. Anonymous -> NO_AUTHOR."""
import os, glob, re, json
from collections import Counter
SRC="/mnt/volume1/polish-scores-tmp"
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
def cdt_status(cdt):
    yrs=[int(y) for y in re.findall(r"1[0-9]{3}|20[0-2][0-9]", cdt or "")]
    if not yrs: return ("UNKNOWN",None)
    latest=max(yrs)
    return (("PD" if latest<=1955 else "RECENT"), latest)
# per file: composer -> collect CDT
comp_cdt={}   # composer -> set of latest years seen
file_status={}  # relpath -> status
for k in glob.glob(f"{SRC}/**/*.krn",recursive=True):
    m=hdr(k); comp=normc(m.get("COM")); rel=os.path.relpath(k,SRC)
    if comp.lower() in ANON:
        file_status[rel]=("NO_AUTHOR",comp,None); continue
    st,yr=cdt_status(m.get("CDT",""))
    file_status[rel]=(st,comp,yr)
    if yr is not None: comp_cdt.setdefault(comp,[]).append(yr)
byentry=Counter(v[0] for v in file_status.values())
print("polish entries:",len(file_status))
print("by CDT status (entry):",dict(byentry))
# composer-level (use max year across that composer's files)
comp_final={}
for c,ys in comp_cdt.items():
    comp_final[c]=("PD" if max(ys)<=1955 else "RECENT", max(ys))
recent=[(c,y) for c,(s,y) in comp_final.items() if s=="RECENT"]
print("composers RECENT by CDT (>1955):",len(recent))
for c,y in sorted(recent,key=lambda x:-x[1])[:15]: print(f"   {c} d/active {y}")
json.dump({rel:{"status":s,"composer":c,"year":y} for rel,(s,c,y) in file_status.items()},
          open("/tmp/polish_cdt.json","w"),ensure_ascii=False)
print("wrote /tmp/polish_cdt.json")
