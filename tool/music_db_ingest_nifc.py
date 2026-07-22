import json, os, glob
ROOT="/mnt/volume1/music-db"
def hdr(path):
    m={}
    for ln in open(path,encoding="utf-8",errors="replace"):
        if ln.startswith("!!!"):
            k=ln[3:].split(":",1)
            if len(k)==2: m[k[0].strip()]=k[1].strip()
        elif not ln.startswith("!") and m: break
    return m
items=[]
for i,krn in enumerate(sorted(glob.glob(f"{ROOT}/nifc/ship/chopin/*.krn"))):
    m=hdr(krn)
    comp=m.get("COM","Chopin, Fryderyk")
    if "," in comp: a,b=[s.strip() for s in comp.split(",",1)]; comp=f"{b} {a}"
    title=(m.get("OTL") or os.path.basename(krn)).rstrip(".")
    if m.get("OPS"): title=f"{title} ({m['OPS']})"
    items.append({"id":f"nifc_chopin_{i:03d}","title":title[:180],"author":comp,
        "author_full":comp,"poet":None,"year":None,"transcribed":None,
        "instrument":"piano","instruments":["piano"],"editor":"score","ensemble":False,
        "licence":"Creative Commons Attribution 4.0","source":"NIFC Chopin First Editions",
        "source_url":"https://github.com/pl-wnifc/humdrum-chopin-first-editions",
        "attribution":"NIFC / pl-wnifc (CC BY 4.0)","format":"krn","tier":"ship",
        "rights_status":"PD","rights_method":"Chopin d.1849 = PD; 1830s first-edition fingering PD; CC BY 4.0 encoding",
        "verified_from":"krn !!!COM","path":f"nifc/ship/chopin/{os.path.basename(krn)}"})
json.dump(items,open(f"{ROOT}/nifc-manifest.json","w"),indent=1,ensure_ascii=False)
print("NIFC Chopin:",len(items))
