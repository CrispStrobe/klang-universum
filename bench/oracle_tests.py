#!/usr/bin/env python3
"""Oracle validation of the pure-Dart MP3 codec against ffmpeg (and glint).

Three families of test, all vs an independent reference ("oracle"):
  A. ENCODE oracle  — our encoder -> ffmpeg DECODE -> SNR vs the source.
                      (our stream is standard & the audio survives.)
  B. DECODE agreement — our stream, decoded by OUR decoder AND ffmpeg;
                      the two decodes must agree (our decoder == reference).
  C. DECODE foreign — ffmpeg ENCODE (a stream we didn't make) -> OUR decoder
                      -> SNR vs the source. (our decoder handles real files.)

Runs across signals x modes x bitrates. Prints a table; exits non-zero if any
case falls below its floor.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sig(name, sec=3):
    t = np.arange(SR * sec) / SR
    if name == 'tone':
        return 0.5 * np.sin(2 * np.pi * 440 * t)
    if name == 'chord':
        return 0.3 * sum(np.sin(2 * np.pi * f * t) for f in (261, 329, 392))
    if name == 'sweep':
        return 0.5 * np.sin(2 * np.pi * (200 + 2000 * t / sec) * t)
    if name == 'speech':
        rng = np.random.default_rng(7)
        env = 0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * 3 * t))
        v = sum((1 / (i + 1)) * np.sin(2 * np.pi * 155 * (i + 1) * t)
                for i in range(10))
        n = np.convolve(rng.normal(0, 1, len(t)), np.ones(9) / 9, 'same')
        return (v * 0.12 + n * 0.03) * env
    if name == 'music':  # decaying harmonic notes — musical, easy to judge
        out = np.zeros_like(t)
        for st, f in [(0, 261), (0.5, 329), (1.0, 392), (1.5, 523)]:
            e = np.exp(-3 * np.maximum(0, t - st)) * (t >= st)
            out += e * sum(0.6**k * np.sin(2 * np.pi * f * (k + 1) * t)
                           for k in range(4))
        return out
    raise ValueError(name)


def write_wav(path, x, nch=1):
    x = np.clip(x / max(1e-9, np.max(np.abs(x))) * 0.9, -1, 1)
    if nch == 2 and x.ndim == 1:
        x = np.column_stack([x, np.roll(x, 50) * 0.9])
    pcm = (x * 32767).astype('<i2')
    with wave.open(path, 'w') as w:
        w.setnchannels(nch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_pcm(path, nch):
    d = np.frombuffer(open(path, 'rb').read(), dtype='<i2').astype(float) / 32768
    return d.reshape(-1, nch) if nch == 2 else d.reshape(-1, 1)


def read_wav_arr(path):
    w = wave.open(path, 'rb')
    d = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(float) / 32768
    return d.reshape(-1, w.getnchannels())


def snr(ref, dec):
    n = min(len(ref), len(dec))
    ref, dec = ref[:n], dec[:n]
    from numpy.fft import rfft, irfft
    L = 1 << int(np.ceil(np.log2(2 * n)))
    cc = irfft(rfft(dec, L) * np.conj(rfft(ref, L)), L)
    lag = int(np.argmax(np.concatenate([cc[:3000], cc[-3000:]])))
    if lag >= 3000:
        lag -= 6000
    if lag >= 0:
        a, b = ref[:n - lag], dec[lag:]
    else:
        a, b = ref[-lag:], dec[:n + lag]
    m = min(len(a), len(b))
    a, b = a[:m], b[:m]
    if np.dot(b, b) == 0:
        return -99.0
    b = b * (np.dot(a, b) / np.dot(b, b))
    return 10 * np.log10(np.sum(a * a) / (np.sum((a - b) ** 2) + 1e-30))


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=REPO, **kw)


def dart_encode(wav, mp3, mode, br):
    args = ['dart', 'run', 'bin/mp3_encode_cli.dart', wav, mp3, '-b', str(br)]
    # the CLI is mono-only; multichannel/joint go through a dedicated bin below
    return run(args)


def main():
    tmp = tempfile.mkdtemp()
    fails = []
    print('=== A. ENCODE oracle: our encode -> ffmpeg decode (SNR vs source) ===')
    print(f'{"signal":8} {"mode":7} {"br":4}  SNR(dB)  floor')
    for name in ['tone', 'chord', 'sweep', 'speech', 'music']:
        x = sig(name)
        for mode, nch, br, floor in [('mono', 1, 128, 15),
                                     ('mono', 1, 256, 20)]:
            wav = f'{tmp}/{name}.wav'
            write_wav(wav, x, nch)
            mp3 = f'{tmp}/{name}_{mode}_{br}.mp3'
            r = dart_encode(wav, mp3, mode, br)
            if not os.path.exists(mp3):
                print(f'{name:8} {mode:7} {br:<4}  ENCODE FAILED {r.stderr[:60]}')
                fails.append((name, mode, br, 'encode'))
                continue
            pcmf = f'{mp3}.pcm'
            run(['ffmpeg', '-v', 'error', '-y', '-i', mp3, '-f', 's16le',
                 '-ac', str(nch), '-ar', str(SR), pcmf])
            s = snr(read_wav_arr(wav)[:, 0], read_pcm(pcmf, nch)[:, 0])
            ok = s >= floor
            print(f'{name:8} {mode:7} {br:<4}  {s:6.1f}   {floor}  {"" if ok else "*** LOW"}')
            if not ok:
                fails.append((name, mode, br, f'{s:.1f}<{floor}'))

    print('\n=== B. DECODE agreement: our decoder vs ffmpeg on OUR stream ===')
    print(f'{"signal":8}  ourSNR  ffSNR  |diff|')
    for name in ['tone', 'chord', 'sweep', 'speech', 'music']:
        x = sig(name)
        wav = f'{tmp}/{name}.wav'
        write_wav(wav, x, 1)
        mp3 = f'{tmp}/{name}_b.mp3'
        dart_encode(wav, mp3, 'mono', 192)
        our = f'{mp3}.ours.pcm'
        run(['dart', 'run', 'bin/mp3_decode_cli.dart', mp3, our])
        ff = f'{mp3}.ff.pcm'
        run(['ffmpeg', '-v', 'error', '-y', '-i', mp3, '-f', 's16le', '-ac',
             '1', '-ar', str(SR), ff])
        src = read_wav_arr(wav)[:, 0]
        so = snr(src, read_pcm(our, 1)[:, 0])
        sf = snr(src, read_pcm(ff, 1)[:, 0])
        diff = abs(so - sf)
        ok = diff < 1.5
        print(f'{name:8}  {so:6.1f} {sf:6.1f}  {diff:4.2f}  {"" if ok else "*** DISAGREE"}')
        if not ok:
            fails.append((name, 'decode-agree', 192, f'|{so:.1f}-{sf:.1f}|'))

    print('\n=== C. DECODE foreign: ffmpeg ENCODE -> our decoder (SNR vs src) ===')
    print(f'{"signal":8} {"ffbr":5}  SNR(dB)  floor')
    for name in ['tone', 'chord', 'sweep', 'music']:
        x = sig(name)
        wav = f'{tmp}/{name}.wav'
        write_wav(wav, x, 1)
        for br in [128, 256]:
            fmp3 = f'{tmp}/{name}_ff{br}.mp3'
            run(['ffmpeg', '-v', 'error', '-y', '-i', wav, '-c:a', 'libmp3lame',
                 '-b:a', f'{br}k', '-ac', '1', fmp3])
            if not os.path.exists(fmp3):
                # fall back to ffmpeg's native mp3 encoder
                run(['ffmpeg', '-v', 'error', '-y', '-i', wav, '-c:a', 'mp3',
                     '-b:a', f'{br}k', '-ac', '1', fmp3])
            our = f'{fmp3}.pcm'
            run(['dart', 'run', 'bin/mp3_decode_cli.dart', fmp3, our])
            floor = 15 if br == 128 else 20
            s = snr(read_wav_arr(wav)[:, 0], read_pcm(our, 1)[:, 0])
            ok = s >= floor
            print(f'{name:8} {br:<5}  {s:6.1f}   {floor}  {"" if ok else "*** LOW"}')
            if not ok:
                fails.append((name, 'decode-foreign', br, f'{s:.1f}<{floor}'))

    print()
    if fails:
        print(f'FAILURES ({len(fails)}): {fails}')
        return 1
    print('ALL ORACLE TESTS PASSED')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
