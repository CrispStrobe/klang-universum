"""Join the life+70 classification back to OpenScore entries; flag any whose
composer OR poet is in-copyright (RECENT/ALIVE). Writes os_problematic.json."""
import json, os
os.chdir("/mnt/volume1/music-db")
cls = json.load(open("/tmp/os_classify.json"))
d = json.load(open("db.json"))
def norm(n):
    if not n: return None
    n=n.strip()
    if not n or n.lower() in ("unknown","anonymous","traditional","trad.","n/a"): return None
    if "," in n and n.count(",")==1:
        a,b=[p.strip() for p in n.split(",")]
        if a and b: n=f"{b} {a}"
    return n
BAD={"RECENT","ALIVE"}
os_rows=[x for x in d if x["source"].startswith("OpenScore")]
from collections import Counter
verdict=Counter(); prob=[]
for x in os_rows:
    comp=norm(x.get("author")); poet=norm(x.get("poet"))
    cs=cls.get(comp,{}) if comp else {}
    ps=cls.get(poet,{}) if poet else {}
    bad_roles=[]
    if cs.get("status") in BAD: bad_roles.append(("composer",comp,cs))
    if ps.get("status") in BAD: bad_roles.append(("poet",poet,ps))
    if bad_roles:
        verdict["BLOCKED"]+=1
        prob.append({"id":x["id"],"title":x["title"],"source":x["source"],
                     "bad":[{"role":r,"name":n,"status":s["status"],
                             "match":s.get("label"),"birth":s.get("birth"),"death":s.get("death")}
                            for r,n,s in bad_roles]})
    else:
        verdict["CLEAR"]+=1
json.dump(prob,open("os_problematic.json","w"),indent=1,ensure_ascii=False)
print("OpenScore entries:",len(os_rows))
print("verdict:",dict(verdict))
# name-level summary
namest=Counter(v["status"] for v in cls.values())
print("name-level status:",dict(namest))
print(f"\nBLOCKED entries: {len(prob)} -> os_problematic.json")
seen=set()
for p in prob:
    for b in p["bad"]:
        k=(b["role"],b["name"])
        if k in seen: continue
        seen.add(k)
        print(f"  {b['role']:8} {b['name'][:28]:29} -> {(b['match'] or '')[:24]:25} {b['birth']}-{b['death']} ({b['status']})")
