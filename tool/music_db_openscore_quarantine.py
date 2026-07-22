import json, os
os.chdir("/mnt/volume1/music-db")
prob = json.load(open("os_problematic.json"))
genuine = {"Erich Jansen", "Bruce Blunt"}   # the ~2 real in-copyright poets
excl = []
for p in prob:
    for b in p["bad"]:
        if b["role"] == "poet" and b["name"] in genuine:
            excl.append(p["id"])
excl = sorted(set(excl))
json.dump(excl, open("os_exclude.json", "w"), indent=1)
print("quarantining", len(excl), "entries:", excl)
print("\nall 13 blocked (for the record):")
for p in prob:
    for b in p["bad"]:
        keep = "GENUINE->QUARANTINE" if (b["role"]=="poet" and b["name"] in genuine) else "false-match->keep"
        print(f"  {b['role']:8} {b['name'][:20]:21} -> {(b['match'] or '')[:20]:21} {b['birth']}-{b['death']}  [{keep}]")
