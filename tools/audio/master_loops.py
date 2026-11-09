#!/usr/bin/env python3
"""v11.8: loudness-master the music and ambience loops (gain to a LUFS target + tanh soft limiter).
usage: master_loops.py <audio dir>   (called by generate_audio.py after it writes the loops)"""
import math, os, struct, sys, wave
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from loudness import read, lufs

TARGETS = {"bgm_loop.wav": -18.0, "amb_crowd_loop.wav": -21.0}

def master(path, target):
    x, rate = read(path)
    for _ in range(3):                                   # limiter lowers loudness a little: iterate
        g = 10 ** ((target - lufs(x, rate)) / 20)
        x = [math.tanh(v * g * 1.15) / 1.15 for v in x]  # soft limit, ceiling ≈ -1.2 dBFS
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in x))
    print(f"{os.path.basename(path)}: {lufs(x, rate):.1f} LUFS")

if __name__ == "__main__":
    d = sys.argv[1]
    for name, t in TARGETS.items():
        master(os.path.join(d, name), t)
