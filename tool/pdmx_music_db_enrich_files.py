"""Add a multi-format `files` map to every db.json entry from what's on disk.

Paths in `files` use the SAME per-source relative root as the entry's `path`
(OpenScore -> raw/, Mutopia -> mutopia/, PDMX -> music-db root), so a consumer
resolves them exactly like `path`. Only formats that actually exist are listed.
Idempotent; run AFTER merge_db.py."""
import json, os
from collections import Counter
ROOT = "/mnt/volume1/music-db"
d = json.load(open(f"{ROOT}/db.json"))

def swap(path, ext):
    return path.rsplit(".", 1)[0] + "." + ext

for x in d:
    src, path = x["source"], x["path"]
    if src == "PDMX":
        prefix = ROOT
        h = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        cand = {"midi": f"pdmx/ship/midi/{h}.mid",
                "mxl":  f"pdmx/ship/mxl/{h}.mxl",
                "json": f"pdmx/ship/json/{h}.json",
                "pdf":  f"pdmx/ship/pdf/{h}.pdf"}
    elif src.startswith("OpenScore"):
        prefix = f"{ROOT}/raw"
        cand = {"mscx": path, "mxl": swap(path, "mxl"), "mscz": swap(path, "mscz")}
    else:  # Mutopia
        prefix = f"{ROOT}/mutopia"
        cand = {"midi": path}
    files = {f: p for f, p in cand.items() if os.path.exists(os.path.join(prefix, p))}
    x["files"] = files

json.dump(d, open(f"{ROOT}/db.json", "w"), indent=1)
# report: how many entries carry each format
fmtcount = Counter(f for x in d for f in x["files"])
nfmts = Counter(len(x["files"]) for x in d)
print("entries:", len(d))
print("format availability across entries:", dict(fmtcount))
print("formats-per-entry distribution:", dict(sorted(nfmts.items())))
for src in ["PDMX", "OpenScore Lieder", "OpenScore String Quartets", "Mutopia Project"]:
    e = next(x for x in d if x["source"] == src)
    print(f"  {src:28} e.g. files = {list(e['files'])}")
