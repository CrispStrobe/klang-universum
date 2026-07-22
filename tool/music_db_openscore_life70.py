"""Life+70 (EU) check for OpenScore composers AND poets. Wikidata, arts-occupation
constrained, backoff+maxlag, resumable. Statuses: PD (d<=1955 or born<1900) /
RECENT (d>1955) / ALIVE (born>=1900, no death) / UNKNOWN."""
import json, re, time, urllib.request, urllib.parse, urllib.error
API="https://www.wikidata.org/w/api.php"
UA="cometbeat-corpus/1.0 (music-education PD verification; stc.akrs@gmail.com)"
# composer + writer/poet occupations (so both roles resolve; blocks wrong namesakes)
ARTS={"Q36834","Q639669","Q486748","Q1259917","Q753110","Q158852","Q177220",  # music
      "Q49757","Q482980","Q36180","Q170790","Q214917","Q6625963","Q4853732","Q18844224","Q12144794","Q1930187"}  # writers/poets
CUTOFF=1955
def api(params):
    url=API+"?"+urllib.parse.urlencode({**params,"format":"json","maxlag":"5"})
    req=urllib.request.Request(url,headers={"User-Agent":UA})
    last=None
    for a in range(6):
        try:
            with urllib.request.urlopen(req,timeout=30) as r: return json.load(r)
        except urllib.error.HTTPError as e:
            last=e; time.sleep(min(int(e.headers.get("Retry-After") or 0) or 2**a,30))
        except Exception as e:
            last=e; time.sleep(2**a)
    raise last
def yr(cl):
    try: return int(re.sub(r"^[+-]","",cl[0]["mainsnak"]["datavalue"]["value"]["time"])[:4])
    except Exception: return None
def classify(name):
    hits=api({"action":"wbsearchentities","search":name,"language":"en","limit":6}).get("search",[])
    if not hits: return ("UNKNOWN",None,None,None,None)
    ents=api({"action":"wbgetentities","ids":"|".join(h["id"] for h in hits),
              "props":"claims|labels","languages":"en"}).get("entities",{})
    best=None
    for qid,ent in ents.items():
        cl=ent.get("claims",{})
        occ={o["mainsnak"].get("datavalue",{}).get("value",{}).get("id") for o in cl.get("P106",[])}
        if not (occ & ARTS): continue
        d=yr(cl.get("P570",[])); b=yr(cl.get("P569",[]))
        lab=ent.get("labels",{}).get("en",{}).get("value",name)
        score=(d is not None)+(b is not None)
        if best is None or score>best[0]: best=(score,qid,lab,b,d)
    if best is None: return ("UNKNOWN",None,None,None,None)
    _,qid,lab,b,d=best
    if d is not None: st="PD" if d<=CUTOFF else "RECENT"
    elif b is not None: st="ALIVE" if b>=1900 else "PD"
    else: st="UNKNOWN"
    return (st,qid,lab,b,d)
names=json.load(open("/tmp/os_cand.json"))["names"]
try: out=json.load(open("/tmp/os_classify.json"))
except Exception: out={}
todo=[n for n in names if n not in out or out[n].get("status") in ("ERROR",None)]
print(f"classifying {len(todo)} of {len(names)} names",flush=True)
for i,nm in enumerate(todo,1):
    try:
        st,qid,lab,b,d=classify(nm)
        out[nm]={"count":names[nm],"status":st,"qid":qid,"label":lab,"birth":b,"death":d}
    except Exception as e:
        out[nm]={"count":names[nm],"status":"ERROR","err":str(e)[:50]}
    if i%40==0:
        json.dump(out,open("/tmp/os_classify.json","w"),ensure_ascii=False)
        print(f"...{i}/{len(todo)}",flush=True)
    time.sleep(0.35)
json.dump(out,open("/tmp/os_classify.json","w"),ensure_ascii=False)
from collections import Counter
print("OS CLASSIFY DONE:",dict(Counter(v["status"] for v in out.values())),flush=True)
