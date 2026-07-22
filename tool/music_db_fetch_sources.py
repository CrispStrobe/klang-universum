import json, os, urllib.request, urllib.parse, time
ROOT="/mnt/volume1/music-db"
UA="cometbeat-corpus/1.0 (music-education PD archive; stc.akrs@gmail.com)"
def get(url):
    req=urllib.request.Request(url,headers={"User-Agent":UA})
    for a in range(4):
        try:
            with urllib.request.urlopen(req,timeout=45) as r: return r.read()
        except Exception:
            if a==3: raise
            time.sleep(2**a)
def tree(repo):
    j=json.loads(get(f"https://api.github.com/repos/{repo}/git/trees/main?recursive=1"))
    return [t["path"] for t in j.get("tree",[]) if t["type"]=="blob"]

# --- NIFC Chopin first editions + Polish scores (CC BY 4.0, .krn) ---
for repo,sub in [("pl-wnifc/humdrum-chopin-first-editions","chopin"),
                 ("pl-wnifc/humdrum-polish-scores","polish")]:
    try:
        paths=[p for p in tree(repo) if p.endswith(".krn")]
    except Exception as e:
        print(f"{repo}: tree FAIL {e}"); continue
    outdir=f"{ROOT}/nifc/ship/{sub}"; os.makedirs(outdir,exist_ok=True)
    n=0
    for p in paths:
        dst=f"{outdir}/{p.rsplit('/',1)[-1]}"
        if os.path.exists(dst): n+=1; continue
        try:
            url=f"https://raw.githubusercontent.com/{repo}/main/"+urllib.parse.quote(p)
            open(dst,"wb").write(get(url)); n+=1
        except Exception as e:
            print(f"  FAIL {p}: {e}")
        if n%50==0: print(f"  {sub}: {n}/{len(paths)}",flush=True)
    print(f"{sub}: {n}/{len(paths)} krn")

# --- EGSet12 (.gp only; skip the big .wav) Zenodo 11406378 ---
j=json.loads(get("https://zenodo.org/api/records/11406378"))
outdir=f"{ROOT}/egset12/ship"; os.makedirs(outdir,exist_ok=True)
n=0
for f in j.get("files",[]):
    if not f["key"].endswith(".gp"): continue
    dst=f"{outdir}/{f['key']}"
    if os.path.exists(dst): n+=1; continue
    open(dst,"wb").write(get(f["links"]["self"])); n+=1
print(f"egset12: {n} .gp")
print("creators:", [c.get("name") for c in j["metadata"].get("creators",[])][:4])
