"""Content oracle for our kern reader vs verovio (the Humdrum-native renderer —
a far better oracle than music21 for early music). Renders each .krn to MIDI with
both, compares note-on multisets. Residual is mostly repeat-expansion (verovio
expands repeats; our reader reads the notated score once). Usage:
  python music_db_krn_verovio_oracle.py <our_mid_dir> <krn_src_dir>"""
import os, sys, glob, base64
from collections import Counter
import mido, verovio
ours_dir, src = sys.argv[1], sys.argv[2]
vrv = os.path.join(os.path.dirname(ours_dir), "vrv"); os.makedirs(vrv, exist_ok=True)
tk = verovio.toolkit()
for f in sorted(glob.glob(src + "/*.krn")):
    b = os.path.basename(f)[:-4]; dst = f"{vrv}/{b}.mid"
    if os.path.exists(dst): continue
    if tk.loadFile(f):
        d = tk.renderToMIDI()
        open(dst, "wb").write(base64.b64decode(d) if isinstance(d, str) else d)
def noteons(p):
    mf = mido.MidiFile(p); out = Counter()
    for tr in mf.tracks:
        t = 0
        for m in tr:
            t += m.time
            if m.type == 'note_on' and m.velocity > 0:
                out[(m.note, round(t / mf.ticks_per_beat * 12))] += 1
    return out
tot = mat = 0
for f in sorted(glob.glob(src + "/*.krn")):
    b = os.path.basename(f)[:-4]
    po, pv = f"{ours_dir}/{b}.mid", f"{vrv}/{b}.mid"
    if not (os.path.exists(po) and os.path.exists(pv)): continue
    a, c = noteons(po), noteons(pv)
    ap, cp = Counter(), Counter()
    for (p, _), n in a.items(): ap[p] += n
    for (p, _), n in c.items(): cp[p] += n
    mat += sum((ap & cp).values()); tot += max(sum(ap.values()), sum(cp.values()))
print(f"pitch-multiset agreement vs verovio: {mat}/{tot} = {100*mat/tot:.2f}%")
