#!/usr/bin/env python3
"""Integrated loudness (ITU-R BS.1770 K-weighting, ungated mean, mono) for WAV files and gain-mixed layers.
usage: loudness.py file.wav[:gain] ...   — prints LUFS per layer and of the summed mix (layers looped to the longest)."""
import math, struct, sys, wave

def read(path):
    w = wave.open(path); n = w.getnframes(); r = w.getframerate(); ch = w.getnchannels(); sw = w.getsampwidth()
    raw = w.readframes(n)
    assert sw == 2, "16-bit only"
    d = struct.unpack("<%dh" % (n * ch), raw)
    if ch > 1: d = [sum(d[i:i + ch]) / ch for i in range(0, len(d), ch)]
    return [x / 32768 for x in d], r

def biquad(x, b, a):
    y = []; x1 = x2 = y1 = y2 = 0.0
    for v in x:
        o = b[0] * v + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y

def kweight(x, rate):
    # stage 1: high shelf (+4 dB above ~1.5 kHz); stage 2: high-pass ~38 Hz (BS.1770 coefficients re-derived for rate)
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / rate); Vh = 10 ** (G / 20); Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    x = biquad(x, b, a)
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / rate); a0 = 1 + K / Q + K * K
    return biquad(x, [1, -2, 1], [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0])

def lufs(x, rate):
    y = kweight(x, rate)
    blk = int(0.4 * rate); hop = int(0.1 * rate)
    ms = [sum(v * v for v in y[i:i + blk]) / blk for i in range(0, len(y) - blk, hop)] or [sum(v * v for v in y) / len(y)]
    ms = [m for m in ms if m > 0 and -0.691 + 10 * math.log10(m) > -70]          # absolute gate
    rel = -0.691 + 10 * math.log10(sum(ms) / len(ms)) - 10
    ms = [m for m in ms if -0.691 + 10 * math.log10(m) > rel]                       # relative gate
    return -0.691 + 10 * math.log10(sum(ms) / len(ms))

if __name__ == "__main__":
    layers = []
    for arg in sys.argv[1:]:
        path, _, g = arg.partition(":")
        x, r = read(path); g = float(g or 1)
        layers.append((path, [v * g for v in x], r))
    secs = float(__import__("os").environ.get("SECONDS_", "20"))
    rate = layers[0][2]; n = int(secs * rate)
    mix = [0.0] * n
    for path, x, r in layers:
        assert r == rate
        print(f"{path.split('/')[-1]:28s} {lufs(x, r):6.1f} LUFS  peak {20*math.log10(max(abs(v) for v in x)):5.1f} dBFS")
        for i in range(n): mix[i] += x[i % len(x)]
    print(f"{'MIX (' + str(int(secs)) + ' s)':28s} {lufs(mix, rate):6.1f} LUFS  peak {20*math.log10(max(abs(v) for v in mix)):5.1f} dBFS")
