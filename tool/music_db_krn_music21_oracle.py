import os, glob, sys
from collections import Counter
import mido
from music21 import converter
SD="/private/tmp/claude-501/-Users-christianstrobele-code-mus/f38d6e67-3e63-4290-9d77-14110a965d0f/scratchpad/krn"
src, ours, oracle = SD+"/src", SD+"/ours", SD+"/oracle"
os.makedirs(oracle, exist_ok=True)
# 1) music21 oracle (skip existing)
for f in sorted(glob.glob(src+"/*.krn")):
    b=os.path.basename(f)[:-4]; dst=f"{oracle}/{b}.mid"
    if os.path.exists(dst): continue
    try: converter.parse(f).write('midi', dst)
    except Exception as e: print("ORACLE-FAIL",b,type(e).__name__,flush=True)
# 2) note-ons normalized to quarter units (pitch, round(onset_q*12))
def noteons(path):
    mf=mido.MidiFile(path); ppq=mf.ticksPerBeat; out=[]
    for tr in mf.tracks:
        t=0
        for m in tr:
            t+=m.time
            if m.type=='note_on' and m.velocity>0:
                out.append((m.note, round(t/ppq*12)))
    return Counter(out)
tot=mat=0; files=0; rows=[]
for f in sorted(glob.glob(src+"/*.krn")):
    b=os.path.basename(f)[:-4]
    po, pr = f"{ours}/{b}.mid", f"{oracle}/{b}.mid"
    if not (os.path.exists(po) and os.path.exists(pr)): continue
    try:
        a=noteons(po); c=noteons(pr)
    except Exception: continue
    files+=1
    # pitch-only multiset (did we get the notes, ignore timing/repeats)
    ap=Counter(p for (p,_),n in a.items() for _ in range(n))
    cp=Counter(p for (p,_),n in c.items() for _ in range(n))
    inter=sum((ap&cp).values()); union=max(sum(ap.values()),sum(cp.values()))
    tot+=union; mat+=inter
    rows.append((b, sum(ap.values()), sum(cp.values()), inter))
print(f"\n=== KRN oracle: our parser vs music21 ({files} files) ===")
print(f"pitch-multiset agreement: {mat}/{tot} = {100*mat/tot:.2f}%")
rows.sort(key=lambda r: (r[3]/max(r[2],1)))
print("worst 8 (file | ours | music21 | matched):")
for b,ao,co,ii in rows[:8]:
    print(f"  {b[:44]:45} {ao:5} {co:5} {ii:5}  {100*ii/max(co,1):.0f}%")
