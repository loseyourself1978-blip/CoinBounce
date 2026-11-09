#!/usr/bin/env python3
"""Generate CoinBounce sound effects and background music.

Everything is synthesized from scratch with the Python standard library
(sine/square/triangle oscillators, noise and envelopes), so the output is
original work with no third-party samples. Output: 16-bit mono WAV files.

Usage:
    python3 tools/audio/generate_audio.py [output_dir]
Default output_dir: ios/CoinBounce/Audio
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
rng = random.Random(20261026)  # fixed seed: identical output on every run


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq, seconds, wave_shape="sine", attack=0.005, decay=None, volume=1.0, freq_end=None):
    """One note. decay=None -> linear release over the last 20%; else exponential decay rate."""
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if freq_end is None else freq + (freq_end - freq) * (i / n)
        phase += 2 * math.pi * f / RATE
        if wave_shape == "sine":
            v = math.sin(phase)
        elif wave_shape == "square":
            v = 1.0 if math.sin(phase) >= 0 else -1.0
            v *= 0.5
        elif wave_shape == "triangle":
            v = 2 / math.pi * math.asin(math.sin(phase))
        else:
            raise ValueError(wave_shape)
        env = min(1.0, t / attack) if attack > 0 else 1.0
        if decay is None:
            tail = 0.2 * seconds
            if t > seconds - tail:
                env *= max(0.0, (seconds - t) / tail)
        else:
            env *= math.exp(-decay * t)
        out.append(v * env * volume)
    return out


def noise(seconds, decay=40.0, volume=1.0):
    n = int(RATE * seconds)
    return [rng.uniform(-1, 1) * math.exp(-decay * i / RATE) * volume for i in range(n)]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def at(track, seconds, total=None):
    """Place track starting at time `seconds`."""
    pad = silence(seconds)
    out = pad + track
    if total is not None:
        out = (out + silence(total))[: int(RATE * total)]
    return out


def concat(*tracks):
    out = []
    for t in tracks:
        out += t
    return out


def normalize(track, peak=0.85):
    m = max(1e-9, max(abs(v) for v in track))
    return [v / m * peak for v in track]


def write(path, track, peak=0.85):
    track = normalize(track, peak)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in track))


def clink(base=2100, seconds=0.25, volume=1.0):
    """Metallic coin hit: inharmonic partials with fast decay plus a click."""
    return mix(
        tone(base, seconds, decay=18, attack=0.001, volume=0.6 * volume),
        tone(base * 1.62, seconds, decay=24, attack=0.001, volume=0.4 * volume),
        tone(base * 2.76, seconds * 0.6, decay=35, attack=0.001, volume=0.25 * volume),
        noise(0.02, decay=300, volume=0.5 * volume),
    )


def note(name):
    """MIDI-style note name -> frequency, e.g. 'C5', 'G#4'."""
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    key, octave = name[:-1], int(name[-1])
    midi = names[key] + (octave + 1) * 12
    return 440.0 * 2 ** ((midi - 69) / 12)


def arpeggio(names, step, length, shape="square", volume=0.5):
    out = []
    for nm in names:
        out += tone(note(nm), step, shape, attack=0.003, volume=volume)
    return out + silence(max(0, length - step * len(names)))


SFX = {}

SFX["coin_drop"] = lambda: mix(clink(2300, 0.28), at(clink(2600, 0.18, 0.5), 0.05))
SFX["baffle_hit"] = lambda: mix(tone(1500, 0.07, "triangle", attack=0.001, decay=60), noise(0.015, decay=400, volume=0.3))
SFX["fruit_lit"] = lambda: mix(
    tone(note("C6"), 0.18, "sine", attack=0.002, decay=10, volume=0.7),
    at(tone(note("E6"), 0.25, "sine", attack=0.002, decay=8, volume=0.7), 0.08),
    at(tone(note("G6"), 0.3, "sine", attack=0.002, decay=7, volume=0.5), 0.16),
)
SFX["bed_drop"] = lambda: mix(*[at(clink(rng.uniform(1900, 2700), 0.2, rng.uniform(0.5, 1.0)), rng.uniform(0, 0.15)) for _ in range(4)])
SFX["slot_spin"] = lambda: concat(*[mix(tone(900 + 40 * i, 0.03, "square", attack=0.001, decay=80, volume=0.4), silence(max(0.0, 0.09 - i * 0.004))) for i in range(18)])
SFX["slot_stop"] = lambda: mix(tone(180, 0.15, "sine", attack=0.001, decay=30, volume=1.0), tone(900, 0.04, "square", attack=0.001, decay=120, volume=0.3))
SFX["win_small"] = lambda: arpeggio(["C5", "E5", "G5", "C6"], 0.08, 0.5, "square", 0.5)
SFX["win_big"] = lambda: mix(
    arpeggio(["C5", "E5", "G5", "C6", "E6", "G6"], 0.07, 1.0, "square", 0.45),
    at(tone(note("C6"), 0.5, "triangle", attack=0.01, volume=0.5), 0.42),
    at(tone(note("G5"), 0.5, "triangle", attack=0.01, volume=0.4), 0.42),
)
SFX["jackpot"] = lambda: mix(
    concat(arpeggio(["C5", "E5", "G5", "C6"], 0.07, 0.3, "square", 0.45),
           arpeggio(["D5", "F#5", "A5", "D6"], 0.07, 0.3, "square", 0.45),
           arpeggio(["E5", "G#5", "B5", "E6"], 0.07, 0.3, "square", 0.45)),
    at(mix(tone(note("E6"), 1.0, "triangle", attack=0.01, volume=0.5),
           tone(note("B5"), 1.0, "triangle", attack=0.01, volume=0.4),
           tone(note("G#5"), 1.0, "triangle", attack=0.01, volume=0.35)), 0.9),
    *[at(clink(rng.uniform(2500, 3600), 0.15, 0.35), 0.9 + rng.uniform(0, 0.9)) for _ in range(10)],
)
SFX["button_tap"] = lambda: tone(1100, 0.05, "sine", attack=0.001, decay=70, freq_end=700)
SFX["no_coins"] = lambda: concat(tone(330, 0.13, "square", attack=0.003, volume=0.4), silence(0.03), tone(247, 0.2, "square", attack=0.003, volume=0.4))


def bgm():
    """8-bar loop at 112 BPM: bass, arpeggio and a simple melody. Notes end inside the loop so it repeats cleanly."""
    bpm = 112
    beat = 60 / bpm
    bars = 8
    total = bars * 4 * beat
    chords = [("C3", ["C4", "E4", "G4"]), ("A2", ["A3", "C4", "E4"]), ("F2", ["F3", "A3", "C4"]), ("G2", ["G3", "B3", "D4"])] * 2
    melody = ["E5", "G5", "C6", "G5", "C5", "E5", "A5", "E5", "F5", "A5", "C6", "A5", "D5", "G5", "B5", "G5",
              "E5", "G5", "C6", "E6", "A5", "C6", "E6", "C6", "F5", "A5", "C6", "F5", "G5", "B5", "D6", "B5"]
    bass, arp, mel = [], [], []
    for root, triad in chords:
        for b in range(4):
            bass += tone(note(root), beat * 0.9, "triangle", attack=0.005, volume=0.55) + silence(beat * 0.1)
            for k in range(2):
                arp += tone(note(triad[(b * 2 + k) % 3]), beat / 2 * 0.8, "square", attack=0.002, volume=0.12) + silence(beat / 2 * 0.2)
    for m in melody:
        mel += tone(note(m), beat * 0.85, "sine", attack=0.01, volume=0.3) + silence(beat * 0.15)
    track = mix(bass, arp, mel)
    return (track + silence(total))[: int(RATE * total)]


# ---------------------------------------------------------------------------
# v11.7: casino crowd ambience, cheer, applause and a jackpot fanfare.
# Separate fixed-seed RNG so the files above stay byte-identical.
rng2 = random.Random(20261108)


def lowpass(track, cutoff):
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    y, out = 0.0, []
    for v in track:
        y += a * (v - y)
        out.append(y)
    return out


def highpass(track, cutoff):
    low = lowpass(track, cutoff)
    return [v - l for v, l in zip(track, low)]


def vowel(f0, seconds, formants=(600, 1200), volume=0.1, glide=0.0):
    """A short voice-like 'ah/oh': harmonics of f0 weighted by two formant bumps, smooth envelope."""
    n = int(RATE * seconds)
    harmonics = [k for k in range(1, 16) if f0 * k < 3500]
    weights = [sum(math.exp(-((f0 * k - f) / 250) ** 2) for f in formants) + 0.05 for k in harmonics]
    phases = [0.0] * len(harmonics)
    out = []
    for i in range(n):
        x = i / n
        f = f0 * (1 + glide * x)
        env = math.sin(math.pi * x) ** 2
        v = 0.0
        for j, k in enumerate(harmonics):
            phases[j] += 2 * math.pi * f * k / RATE
            v += weights[j] * math.sin(phases[j])
        out.append(v * env * volume / len(harmonics))
    return out


def babble(seconds, rate_per_s, pitch=(110, 240), volume=0.08, glide=(0.0, 0.0)):
    total = int(RATE * seconds)
    out = [0.0] * total
    count = int(seconds * rate_per_s)
    for _ in range(count):
        d = rng2.uniform(0.15, 0.5)
        v = vowel(rng2.uniform(*pitch), d, formants=(rng2.uniform(450, 800), rng2.uniform(1000, 1800)),
                  volume=volume * rng2.uniform(0.5, 1.0), glide=rng2.uniform(*glide))
        start = rng2.randrange(0, total)
        for i, s_ in enumerate(v):
            out[(start + i) % total] += s_          # wraps around: seamless loop
    return out


def crowd_loop():
    """12 s seamless casino murmur: low filtered noise bed + distant babble."""
    seconds = 12
    bed = lowpass([rng2.uniform(-1, 1) for _ in range(int(RATE * seconds))], 500)
    bed = [v * 0.6 for v in bed]
    talk = lowpass(babble(seconds, 30, volume=0.25), 1800)
    return mix(bed, talk)


def cheer():
    """2.4 s crowd cheer: a swell of bright noise, rising 'woo' voices and two whistles."""
    seconds = 2.4
    n = int(RATE * seconds)
    swell = highpass(lowpass([rng2.uniform(-1, 1) for _ in range(n)], 2500), 300)
    env = [min(1.0, (i / n) / 0.15) * math.exp(-1.6 * max(0.0, i / n - 0.25)) for i in range(n)]
    swell = [v * e * 0.9 for v, e in zip(swell, env)]
    woo = babble(seconds, 18, pitch=(220, 420), volume=0.5, glide=(0.15, 0.45))
    woo = [v * e for v, e in zip(woo, env)]
    whistles = mix(at(tone(1900, 0.5, "sine", attack=0.03, volume=0.25, freq_end=2700), 0.25),
                   at(tone(2200, 0.4, "sine", attack=0.03, volume=0.2, freq_end=3000), 0.9))
    return (mix(swell, woo, whistles) + silence(seconds))[:n]


def applause():
    """2.5 s applause: many short band-limited claps, dense at first then thinning out."""
    seconds = 2.5
    n = int(RATE * seconds)
    out = [0.0] * n
    for _ in range(140):
        t = rng2.random() ** 1.6 * (seconds - 0.05)
        clap = highpass(lowpass(noise(rng2.uniform(0.008, 0.02), decay=250, volume=rng2.uniform(0.4, 1.0)), rng2.uniform(1500, 3000)), 600)
        start = int(t * RATE)
        for i, v in enumerate(clap):
            if start + i < n:
                out[start + i] += v
    return out


def brass(freq, seconds, volume=0.3):
    """Brass-like note: band-limited sawtooth with a soft attack and slight vibrato, lowpassed."""
    n = int(RATE * seconds)
    out, phase = [], 0.0
    harmonics = [k for k in range(1, 12) if freq * k < 5000]
    for i in range(n):
        t = i / RATE
        f = freq * (1 + 0.004 * math.sin(2 * math.pi * 5.5 * t))
        phase += 2 * math.pi * f / RATE
        v = sum(math.sin(phase * k) / k for k in harmonics)
        env = min(1.0, t / 0.04) * (1.0 if t < seconds - 0.12 else max(0.0, (seconds - t) / 0.12))
        out.append(v * env * volume)
    return lowpass(out, 3000)


def timpani(seconds=0.6, volume=0.8):
    return mix(tone(70, seconds, "sine", attack=0.002, decay=6, volume=volume), lowpass(noise(seconds, decay=18, volume=0.5), 300))


def fanfare():
    """3 s jackpot fanfare: ta-ta-taaa on C major, then a held C major chord with timpani."""
    beat = 0.16
    lead = concat(brass(note("G4"), beat), brass(note("G4"), beat), brass(note("G4"), beat), brass(note("C5"), beat * 3),
                  brass(note("E5"), beat * 2), brass(note("D5"), beat), brass(note("E5"), beat * 1.2))
    chord_start = beat * 9.2
    chord = mix(*[brass(note(nm), 1.4, volume=0.22) for nm in ("C4", "E4", "G4", "C5")])
    hits = mix(at(timpani(), 0.0), at(timpani(), beat * 3), at(timpani(0.9, 1.0), chord_start))
    return mix(lead, at(chord, chord_start), hits)


EXTRA = {"cheer": cheer, "applause": applause, "jackpot_fanfare": fanfare}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "ios", "CoinBounce", "Audio")
    os.makedirs(out_dir, exist_ok=True)
    for name, make in SFX.items():
        write(os.path.join(out_dir, f"sfx_{name}.wav"), make())
    write(os.path.join(out_dir, "bgm_loop.wav"), bgm(), peak=0.6)
    for name, make in EXTRA.items():
        write(os.path.join(out_dir, f"sfx_{name}.wav"), make())
    write(os.path.join(out_dir, "amb_crowd_loop.wav"), crowd_loop(), peak=0.5)
    print(f"wrote {len(SFX) + len(EXTRA) + 2} files to {os.path.abspath(out_dir)}")


if __name__ == "__main__":
    main()
