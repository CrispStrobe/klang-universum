#!/usr/bin/env python3
"""PDMX JSON (muspy format) -> Standard MIDI, plus a stdlib roundtrip validator.

PDMX (openmusic/pdmx) ships JSON-only; there is no MIDI in the tarball. This
converts the CC0-original subset to MIDI and verifies each conversion by parsing
the produced MIDI back and comparing its notes to the source JSON.

Stdlib only (VPS python is /usr/bin/python3 3.12, no pip). Subcommands:

    extract   stream PDMX.tar.gz once, write the wanted <hash>.json to json/
    convert   json/*.json -> mid/*.mid
    validate  roundtrip: MIDI note-ons must equal JSON notes (per track)
    all       extract + convert + validate

Note model for validation: we compare, per track, the multiset of
(pitch, onset_tick) of note-ons. Pitches/velocities are clamped to [0,127]
identically on both sides so clamping never causes a spurious mismatch.
"""
import argparse
import glob
import json
import math
import os
import struct
import sys
import tarfile


# --------------------------------------------------------------------------- #
# MIDI writer
# --------------------------------------------------------------------------- #
def _vlq(n):
    """MIDI variable-length quantity."""
    n = max(int(n), 0)
    b = [n & 0x7F]
    n >>= 7
    while n > 0:
        b.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(b))


def _clamp7(x, default=0):
    try:
        x = int(x)
    except (TypeError, ValueError):
        x = default
    return 0 if x < 0 else 127 if x > 127 else x


def json_to_midi(d):
    """muspy-format dict -> Standard MIDI (format 1) bytes.

    Returns (midi_bytes, stats) where stats records clamped/dropped counts.
    """
    stats = {"clamped": 0, "grace_clamped_dur": 0, "notes": 0}
    res = int(d.get("resolution") or 480)
    if res <= 0:
        res = 480
    tracks = []

    # --- meta track: tempos + time signatures ---------------------------- #
    ev = []
    for t in (d.get("tempos") or [{"time": 0, "qpm": 120}]):
        qpm = t.get("qpm") or 120
        if qpm <= 0:
            qpm = 120
        us = int(round(60_000_000 / qpm))
        us = max(1, min(us, 0xFFFFFF))
        ev.append((int(t.get("time", 0) or 0), 0,
                   b"\xFF\x51\x03" + us.to_bytes(3, "big")))
    for ts in (d.get("time_signatures") or []):
        num = int(ts.get("numerator", 4) or 4)
        den = int(ts.get("denominator", 4) or 4)
        num = max(1, min(num, 255))
        dd = int(round(math.log2(den))) if den > 0 else 2
        dd = max(0, min(dd, 255))
        ev.append((int(ts.get("time", 0) or 0), 0,
                   b"\xFF\x58\x04" + bytes([num, dd, 24, 8])))
    ev.sort(key=lambda e: (e[0], e[1]))
    buf = bytearray()
    prev = 0
    for tick, _, data in ev:
        buf += _vlq(tick - prev) + data
        prev = tick
    buf += _vlq(0) + b"\xFF\x2F\x00"
    tracks.append(buf)

    # --- one MIDI track per JSON track ----------------------------------- #
    ci = 0
    for tr in d.get("tracks", []):
        if tr.get("is_drum"):
            ch = 9
        else:
            ch = ci if ci < 9 else ci + 1   # skip channel 9 for pitched tracks
            ci += 1
            if ch > 15:
                ch = 15                     # >15 tracks: reuse last channel
        prog = _clamp7(tr.get("program") or 0)
        notes = []
        for n in tr.get("notes", []):
            on = int(n.get("time", 0) or 0)
            raw_p = n.get("pitch", 0)
            p = _clamp7(raw_p)
            if isinstance(raw_p, (int, float)) and not (0 <= raw_p <= 127):
                stats["clamped"] += 1
            v = _clamp7(n.get("velocity", 64), 64)
            if v == 0:
                v = 1  # a 0-velocity note-on reads as note-off; keep it audible
            dur = int(n.get("duration", 1) or 0)
            if dur < 1:
                dur = 1
                if n.get("is_grace"):
                    stats["grace_clamped_dur"] += 1
            notes.append((on, 1, 0x90 | ch, p, v))        # note-on
            notes.append((on + dur, 0, 0x80 | ch, p, 0))  # note-off
            stats["notes"] += 1
        # note-off (flag 0) sorts before note-on (flag 1) at the same tick
        notes.sort(key=lambda e: (e[0], e[1]))
        b = bytearray()
        b += _vlq(0) + bytes([0xC0 | ch, prog])
        prev = 0
        for tick, _, status, p, v in notes:
            b += _vlq(tick - prev) + bytes([status, p, v])
            prev = tick
        b += _vlq(0) + b"\xFF\x2F\x00"
        tracks.append(b)

    out = bytearray(b"MThd") + struct.pack(">IHHH", 6, 1, len(tracks), res)
    for t in tracks:
        out += b"MTrk" + struct.pack(">I", len(t)) + bytes(t)
    return bytes(out), stats


# --------------------------------------------------------------------------- #
# MIDI reader (stdlib) — extract note-ons per track for validation
# --------------------------------------------------------------------------- #
def _read_vlq(data, i):
    n = 0
    while True:
        b = data[i]
        i += 1
        n = (n << 7) | (b & 0x7F)
        if not (b & 0x80):
            break
    return n, i


def midi_note_ons(data):
    """Parse Standard MIDI bytes -> {track_index: [(pitch, abs_tick), ...]}.

    Track 0 (meta) is skipped implicitly since it carries no note-ons; the
    per-JSON-track MIDI tracks start at index 1, which we re-key to 0-based
    JSON track order.
    """
    assert data[:4] == b"MThd", "not a MIDI file"
    _, fmt, ntrk, div = struct.unpack(">IHHH", data[4:14])
    i = 14
    out = {}
    midi_trk = 0
    while i < len(data):
        if data[i:i + 4] != b"MTrk":
            break
        (length,) = struct.unpack(">I", data[i + 4:i + 8])
        i += 8
        end = i + length
        abs_t = 0
        running = None
        notes = []
        while i < end:
            dt, i = _read_vlq(data, i)
            abs_t += dt
            status = data[i]
            if status & 0x80:
                i += 1
                running = status
            else:
                status = running
            hi = status & 0xF0
            if status == 0xFF:  # meta
                mtype = data[i]
                i += 1
                mlen, i = _read_vlq(data, i)
                i += mlen
            elif hi in (0xC0, 0xD0):
                i += 1
            elif hi in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
                p = data[i]
                v = data[i + 1]
                i += 2
                if hi == 0x90 and v > 0:
                    notes.append((p, abs_t))
            elif status in (0xF0, 0xF7):  # sysex
                slen, i = _read_vlq(data, i)
                i += slen
            else:
                i += 1
        if notes:  # only note-bearing tracks map to JSON tracks
            out[midi_trk] = notes
        midi_trk += 1
        i = end
    return out


def json_note_ons(d):
    """{json_track_index: [(pitch, onset_tick), ...]} using the same clamping."""
    out = {}
    for ti, tr in enumerate(d.get("tracks", [])):
        notes = []
        for n in tr.get("notes", []):
            on = int(n.get("time", 0) or 0)
            p = _clamp7(n.get("pitch", 0))
            notes.append((p, on))
        if notes:
            out[ti] = notes
    return out


# --------------------------------------------------------------------------- #
# Steps
# --------------------------------------------------------------------------- #
def step_extract(root, tarpath, listpath):
    want = set()
    for line in open(listpath):
        line = line.strip()
        if not line:
            continue
        want.add(line.split("/")[-1].replace(".mid", ".json"))
    outdir = os.path.join(root, "json")
    os.makedirs(outdir, exist_ok=True)
    got = set()
    with tarfile.open(tarpath, "r:gz") as t:
        for m in t:
            if not m.isfile() or not m.name.endswith(".json"):
                continue
            base = m.name.split("/")[-1]
            if base in want and base not in got:
                with open(os.path.join(outdir, base), "wb") as f:
                    f.write(t.extractfile(m).read())
                got.add(base)
    missing = want - got
    print(f"extracted {len(got)} of {len(want)}")
    if missing:
        print(f"MISSING {len(missing)} (first 10): {sorted(missing)[:10]}")
    return len(got), len(want)


def step_convert(root):
    indir = os.path.join(root, "json")
    outdir = os.path.join(root, "mid")
    os.makedirs(outdir, exist_ok=True)
    files = sorted(glob.glob(os.path.join(indir, "*.json")))
    ok = skip = 0
    total_clamped = total_grace = 0
    for f in files:
        try:
            with open(f) as fh:
                d = json.load(fh)
            midi, stats = json_to_midi(d)
            out = os.path.join(outdir, os.path.basename(f).replace(".json", ".mid"))
            with open(out, "wb") as fh:
                fh.write(midi)
            ok += 1
            total_clamped += stats["clamped"]
            total_grace += stats["grace_clamped_dur"]
        except Exception as e:
            skip += 1
            print(f"SKIP {os.path.basename(f)}: {e}", file=sys.stderr)
    print(f"converted {ok}, skipped {skip}; "
          f"pitch-clamped {total_clamped}, grace-dur-clamped {total_grace}")
    return ok, skip


def step_validate(root):
    indir = os.path.join(root, "json")
    middir = os.path.join(root, "mid")
    files = sorted(glob.glob(os.path.join(indir, "*.json")))
    n_files = perfect = 0
    total_notes = matched_notes = 0
    imperfect = []
    for f in files:
        mid = os.path.join(middir, os.path.basename(f).replace(".json", ".mid"))
        if not os.path.exists(mid):
            imperfect.append((os.path.basename(f), "NO_MIDI"))
            continue
        with open(f) as fh:
            d = json.load(fh)
        with open(mid, "rb") as fh:
            midi_notes = midi_note_ons(fh.read())
        json_notes = json_note_ons(d)
        n_files += 1
        # align by track order (both keyed 0-based over note-bearing tracks)
        j_keys = sorted(json_notes)
        m_keys = sorted(midi_notes)
        file_total = sum(len(v) for v in json_notes.values())
        file_matched = 0
        if len(j_keys) == len(m_keys):
            from collections import Counter
            for jk, mk in zip(j_keys, m_keys):
                jc = Counter(json_notes[jk])
                mc = Counter(midi_notes[mk])
                inter = jc & mc
                file_matched += sum(inter.values())
        total_notes += file_total
        matched_notes += file_matched
        if file_matched == file_total and len(j_keys) == len(m_keys):
            perfect += 1
        else:
            imperfect.append((os.path.basename(f),
                              f"{file_matched}/{file_total} notes, "
                              f"{len(j_keys)} json trk vs {len(m_keys)} midi trk"))
    pct = (100.0 * matched_notes / total_notes) if total_notes else 0.0
    print(f"\n=== ROUNDTRIP ===")
    print(f"files validated : {n_files}")
    print(f"perfect files   : {perfect}")
    print(f"notes matched   : {matched_notes}/{total_notes} ({pct:.4f}%)")
    if imperfect:
        print(f"imperfect files : {len(imperfect)} (first 20):")
        for name, why in imperfect[:20]:
            print(f"  {name}: {why}")
    verdict = "PASS" if pct >= 99.9 else "FAIL"
    print(f"ROUNDTRIP {verdict}")
    return pct, perfect, n_files


# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("step", choices=["extract", "convert", "validate", "all"])
    ap.add_argument("--root", default="/mnt/volume1/pdmx-cc0-midi")
    ap.add_argument("--tar", default="/mnt/volume1/pdmx-cc0-midi/PDMX.tar.gz")
    ap.add_argument("--list", default="/mnt/volume1/pdmx_cc0_mid.txt")
    a = ap.parse_args()
    if a.step in ("extract", "all"):
        step_extract(a.root, a.tar, a.list)
    if a.step in ("convert", "all"):
        step_convert(a.root)
    if a.step in ("validate", "all"):
        step_validate(a.root)


if __name__ == "__main__":
    main()
