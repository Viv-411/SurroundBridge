#!/usr/bin/env python3
"""Generates a 5.1 WAV where a voice names each speaker, from that speaker only.
Uses the built-in macOS `say` command. Usage: make-voice-test.py <output.wav>"""
import struct, subprocess, sys, tempfile, os, wave, math

RATE = 48000
# WAV 5.1 channel order: FL, FR, C, LFE, SL(back L), SR(back R)
ORDER = [(0, "Front left"), (2, "Center"), (1, "Front right"), (5, "Surround right"), (4, "Surround left"), (3, None)]

def say(text):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "v.wav")
        subprocess.run(["say", "-o", p, "--data-format=LEI16@48000", text], check=True)
        with wave.open(p) as w:
            raw = w.readframes(w.getnframes())
        return list(struct.unpack("<%dh" % (len(raw) // 2), raw))

out = []  # list of 6-tuples
def emit(ch, samples):
    for s in samples:
        f = [0] * 6; f[ch] = s; out.append(f)
def silence(sec): emit(0, [0] * int(sec * RATE))

for ch, label in ORDER:
    if label:
        v = say(label); emit(ch, v); silence(0.3); emit(ch, v)
    else:  # subwoofer: voices are too high-pitched for it, so use a pulsing 50 Hz rumble
        n = int(2.5 * RATE)
        emit(ch, [int(14000 * math.sin(2 * math.pi * 50 * i / RATE) * (1 if (i // (RATE // 4)) % 2 == 0 else 0.15)) for i in range(n)])
    silence(0.8)

data = b"".join(struct.pack("<6h", *f) for f in out)
with open(sys.argv[1], "wb") as f:  # WAVE_FORMAT_EXTENSIBLE header so players know it's 5.1
    fmt = struct.pack("<HHIIHHHHIH14s", 0xFFFE, 6, RATE, RATE * 12, 12, 16, 22, 16, 0x3F, 1,
                      bytes.fromhex("000000001000800000aa00389b71"))
    f.write(b"RIFF" + struct.pack("<I", 4 + 8 + len(fmt) + 8 + len(data)) + b"WAVE")
    f.write(b"fmt " + struct.pack("<I", len(fmt)) + fmt)
    f.write(b"data" + struct.pack("<I", len(data)) + data)
print("wrote", sys.argv[1], "%.1f s" % (len(out) / RATE))
