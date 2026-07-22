import json, os, glob, shutil
from pathlib import Path
SRC="/mnt/volume1/jams-corpus/tierA/OpenEWLD-eu-pd"
ROOT="/mnt/volume1/music-db"; SHIP=f"{ROOT}/openewld/ship"; os.makedirs(SHIP,exist_ok=True)
items=[]
for i,mxl in enumerate(sorted(glob.glob(f"{SRC}/**/*.mxl",recursive=True))):
    p=Path(mxl); title=p.stem.replace("_"," ")
    people=[c.replace("_"," ").strip() for c in p.parent.parent.name.split("-") if c.strip()]
    composer=people[-1] if people else None
    poet=people[0] if len(people)>1 else None
    fn=f"{i:03d}_{p.name}"; shutil.copyfile(mxl,f"{SHIP}/{fn}")
    items.append({"id":f"openewld_{i:03d}","title":title[:180],"author":composer,
        "author_full":", ".join(people) or None,"poet":poet,"year":None,"transcribed":None,
        "instrument":"voice","instruments":["voice"],"editor":"score","ensemble":False,
        "licence":"MIT","source":"OpenEWLD","source_url":"https://github.com/00sapo/OpenEWLD",
        "attribution":None,"format":"mxl","tier":"ship","rights_status":"EU_PD",
        "rights_method":"OpenEWLD author-death filter (EU life+70, verified)",
        "verified_from":"eu-pd-verification.json","path":f"openewld/ship/{fn}"})
json.dump(items,open(f"{ROOT}/openewld-manifest.json","w"),indent=1,ensure_ascii=False)
print("OpenEWLD:",len(items))
