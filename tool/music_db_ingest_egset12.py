import json, os, glob
ROOT="/mnt/volume1/music-db"
auth="Pedroza, Abreu, Corey, Roman"
items=[]
for gp in sorted(glob.glob(f"{ROOT}/egset12/ship/*.gp")):
    n=os.path.basename(gp).rsplit(".",1)[0]
    items.append({"id":f"egset12_{n}","title":f"EGSet12 — piece {n}","author":auth,
        "author_full":auth,"poet":None,"year":None,"transcribed":None,
        "instrument":"electric guitar","instruments":["guitar"],"editor":"tab","ensemble":False,
        "licence":"Creative Commons Attribution 4.0","source":"EGSet12",
        "source_url":"https://zenodo.org/records/11406378","attribution":auth+" (CC BY 4.0)",
        "format":"gp","tier":"ship","rights_status":"CC_BY_ORIGINAL",
        "rights_method":"original composition by dataset authors (axis-2 clean); CC BY 4.0",
        "verified_from":"Zenodo 11406378","path":f"egset12/ship/{os.path.basename(gp)}"})
json.dump(items,open(f"{ROOT}/egset12-manifest.json","w"),indent=1,ensure_ascii=False)
print("EGSet12:",len(items))
