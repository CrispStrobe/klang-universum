"""Add a multi-format `files` map to every db.json entry from disk. Idempotent;
run AFTER merge_db.py and any fetch/derive jobs."""
import json, os
from collections import Counter
ROOT="/mnt/volume1/music-db"
d=json.load(open(f"{ROOT}/db.json"))
def swap(path, ext): return path.rsplit(".",1)[0]+"."+ext
for x in d:
    src, path = x["source"], x["path"]
    if src=="PDMX":
        prefix=ROOT; h=path.rsplit("/",1)[-1].rsplit(".",1)[0]
        cand={"midi":f"pdmx/ship/midi/{h}.mid","mxl":f"pdmx/ship/mxl/{h}.mxl",
              "json":f"pdmx/ship/json/{h}.json","pdf":f"pdmx/ship/pdf/{h}.pdf"}
    elif src.startswith("OpenScore"):
        prefix=f"{ROOT}/raw"
        cand={"mscx":path,"mxl":swap(path,"mxl"),"mscz":swap(path,"mscz"),"midi":swap(path,"mid")}
    elif src=="Mutopia Project":
        prefix=f"{ROOT}/mutopia"
        cand={"midi":path,"pdf":path.replace("/midi/","/pdf/").replace(".mid",".pdf"),
              "ly":path.replace("/midi/","/ly/").replace(".mid",".ly")}
    else:  # OpenEWLD / NIFC / EGSet12 …: path relative to ROOT, single format
        prefix=ROOT; cand={x["format"]:path}
    x["files"]={f:p for f,p in cand.items() if os.path.exists(os.path.join(prefix,p))}
json.dump(d,open(f"{ROOT}/db.json","w"),indent=1)
print("format availability:", dict(Counter(f for x in d for f in x["files"])))
print("by source:", dict(Counter(x["source"] for x in d)))
