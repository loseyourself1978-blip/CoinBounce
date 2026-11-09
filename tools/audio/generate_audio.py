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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

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



# ---------------------------------------------------------------------------
# v11.8: livelier casino floor. Upbeat 128 BPM loop (kick, clap, hats, walking
# bass, brass stabs, lead) and a 20 s floor ambience (crowd, distant slot
# jingles, bells, coin cascades). Own fixed-seed RNG; earlier files unchanged.
rng3 = random.Random(20261109)


def saw(freq, seconds, harmonics=8, attack=0.004, decay=None, volume=1.0):
    """Band-limited saw built from sine harmonics (brassy stab)."""
    return mix(*[tone(freq * k, seconds, "sine", attack=attack, decay=decay, volume=volume / k)
                 for k in range(1, harmonics + 1) if freq * k < RATE / 2 - 500])


def kick(volume=1.0):
    return mix(tone(110, 0.22, "sine", attack=0.001, decay=18, volume=volume, freq_end=45),
               noise(0.01, decay=500, volume=0.3 * volume))


def clap(volume=0.5):
    burst = [0.0] * int(RATE * 0.18)
    for off in (0.0, 0.011, 0.022):
        n = highpass(noise(0.15, decay=30, volume=volume), 900)
        s0 = int(off * RATE)
        for i, v in enumerate(n):
            if s0 + i < len(burst):
                burst[s0 + i] += v
    return burst


def hat(volume=0.18, open_=False):
    return highpass(noise(0.12 if open_ else 0.04, decay=25 if open_ else 90, volume=volume), 5000)


def place(track, clip, seconds, gain=1.0):
    """Add clip into track at time seconds, wrapping around (seamless loops)."""
    s0 = int(seconds * RATE)
    n = len(track)
    for i, v in enumerate(clip):
        track[(s0 + i) % n] += v * gain


def bgm_casino():
    """8-bar 128 BPM loop: four-on-the-floor kick, claps on 2 and 4, 8th hats,
    walking bass, brass stabs on the off-beats and a bright lead. Wraps cleanly."""
    bpm = 128
    beat = 60 / bpm
    bars = 8
    total = bars * 4 * beat
    out = [0.0] * int(RATE * total)
    prog = [("C", ["C4", "E4", "G4", "A#4"]), ("A", ["A3", "C#4", "E4", "G4"]),
            ("D", ["D4", "F4", "A4", "C5"]), ("G", ["G3", "B3", "D4", "F4"])] * 2
    walk = {"C": ["C2", "E2", "G2", "A2"], "A": ["A1", "C#2", "E2", "G2"],
            "D": ["D2", "F2", "A2", "C3"], "G": ["G1", "B1", "D2", "F2"]}
    lead = ["G5", "A#5", "C6", "A#5", "G5", "E5", "G5", "C6",
            "E5", "G5", "A5", "C#6", "E6", "C#6", "A5", "G5",
            "F5", "A5", "D6", "C6", "A5", "F5", "A5", "D6",
            "B5", "D6", "F6", "D6", "B5", "G5", "F5", "D5"]
    k, c, h, ho = kick(0.9), clap(0.45), hat(0.16), hat(0.12, True)
    for bar, (root, chord) in enumerate(prog):
        t0 = bar * 4 * beat
        for b in range(4):
            tb = t0 + b * beat
            place(out, k, tb)
            if b in (1, 3):
                place(out, c, tb)
            place(out, h, tb)
            place(out, ho, tb + beat / 2)
            place(out, tone(note(walk[root][b]), beat * 0.85, "triangle", attack=0.004, volume=0.5), tb)
            # brass stab on the off-beat
            stab = mix(*[saw(note(n), beat * 0.28, harmonics=6, attack=0.006, decay=9, volume=0.06) for n in chord])
            place(out, lowpass(stab, 2600), tb + beat / 2)
        # lead: one 8-bar phrase of quarter notes, every other bar answered by a fill
        for q in range(4):
            idx = (bar * 4 + q) % len(lead)
            place(out, mix(tone(note(lead[idx]), beat * 0.7, "square", attack=0.004, decay=4, volume=0.07),
                           tone(note(lead[idx]), beat * 0.7, "sine", attack=0.004, decay=3, volume=0.12)), t0 + q * beat)
    # light swing shimmer: a coin clink at the end of every second bar
    for bar in range(1, bars, 2):
        place(out, clink(rng3.uniform(2600, 3200), 0.2, 0.25), (bar * 4 + 3.5) * beat)
    return out


def slot_jingle(volume=0.2):
    seq = rng3.choice([["C6", "E6", "G6", "C7"], ["G5", "B5", "D6", "G6"], ["E6", "G6", "B6"], ["A5", "C#6", "E6", "A6"]])
    out = []
    for nm in seq * rng3.choice([1, 2]):
        out += tone(note(nm), 0.07, "square", attack=0.002, decay=20, volume=volume)
    return lowpass(out, 3000)


def bell(freq, volume=0.2):
    return mix(tone(freq, 1.4, "sine", attack=0.002, decay=3.5, volume=volume),
               tone(freq * 2.76, 0.9, "sine", attack=0.002, decay=6, volume=volume * 0.5),
               tone(freq * 5.4, 0.5, "sine", attack=0.002, decay=10, volume=volume * 0.25))


def coin_cascade(volume=0.3):
    n = rng3.randint(6, 16)
    out = [0.0] * int(RATE * 1.4)
    for _ in range(n):
        c = clink(rng3.uniform(1900, 3400), 0.2, rng3.uniform(0.4, 1.0) * volume)
        s0 = int(rng3.uniform(0, 1.1) * RATE)
        for i, v in enumerate(c):
            if s0 + i < len(out):
                out[s0 + i] += v
    return out


def casino_floor_loop():
    """20 s seamless casino floor: crowd murmur, distant slot jingles and bells, coin cascades, the odd 'woo'."""
    seconds = 20
    total = int(RATE * seconds)
    bed = lowpass([rng3.uniform(-1, 1) for _ in range(total)], 450)
    out = [v * 0.5 for v in bed]
    talk = lowpass(babble(seconds, 55, volume=0.3), 1900)
    for i, v in enumerate(talk):
        out[i] += v
    for _ in range(9):
        place(out, slot_jingle(rng3.uniform(0.08, 0.18)), rng3.uniform(0, seconds))
    for _ in range(4):
        place(out, bell(note(rng3.choice(["C6", "E6", "G6", "A6"])), rng3.uniform(0.06, 0.12)), rng3.uniform(0, seconds))
    for _ in range(5):
        place(out, coin_cascade(rng3.uniform(0.15, 0.3)), rng3.uniform(0, seconds))
    for _ in range(2):
        place(out, lowpass(vowel(rng3.uniform(260, 340), 0.6, formants=(500, 900), volume=0.12, glide=0.3), 1500), rng3.uniform(0, seconds))
    return out


# ---------------------------------------------------------------------------
# v11.8 (2): casino floor bed with real CC0 recordings mixed in — Kenney "Casino Audio"
# chip and card clatter and OpenGameArt bell dings (see tools/audio/cc0/README.md),
# placed around a synthesized crowd murmur and distant slot jingles. 20 s seamless loop.
CC0_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cc0")


def load_clip(path):
    """Decode any audio file to RATE mono floats with ffmpeg."""
    import subprocess
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    return [v / 32768 for v in struct.unpack("<%dh" % (len(raw) // 2), raw)]


def casino_floor_loop_cc0():
    seconds = 20
    out = casino_floor_loop()            # synth murmur, jingles, bells, coin cascades (rng3 sequence unchanged)
    out = [v * 0.8 for v in out]
    kenney = os.path.join(CC0_DIR, "kenney_casino_audio")
    clatter = [load_clip(os.path.join(kenney, f)) for f in sorted(os.listdir(kenney)) if f.endswith(".ogg")]
    bells = [load_clip(os.path.join(CC0_DIR, "oga_bell_dings", f)) for f in sorted(os.listdir(os.path.join(CC0_DIR, "oga_bell_dings")))]
    rng4 = random.Random(20261110)
    # table games around the room: chips and cards, some near, most far (quieter, darker)
    for _ in range(26):
        clip = rng4.choice(clatter)
        far = rng4.random() < 0.7
        c = lowpass(clip, 2500 if far else 6000)
        place(out, c, rng4.uniform(0, seconds), gain=rng4.uniform(0.08, 0.16) if far else rng4.uniform(0.2, 0.32))
    # a machine paying out somewhere: bell dings
    for _ in range(5):
        place(out, lowpass(rng4.choice(bells), 4000), rng4.uniform(0, seconds), gain=rng4.uniform(0.12, 0.22))
    return out


def main():
    if "--ambience" in sys.argv:          # only rebuild the floor ambience loop
        sys.argv.remove("--ambience")
        out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "ios", "CoinBounce", "Audio")
        path = os.path.join(out_dir, "amb_crowd_loop.wav")
        write(path, casino_floor_loop_cc0(), peak=0.5)
        import master_loops
        master_loops.master(path, master_loops.TARGETS["amb_crowd_loop.wav"])
        return
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "ios", "CoinBounce", "Audio")
    os.makedirs(out_dir, exist_ok=True)
    for name, make in SFX.items():
        write(os.path.join(out_dir, f"sfx_{name}.wav"), make())
    # v11.8: the shipped music is "Catchy Swing" (CC0), rendered by make_music.sh; bgm_casino() stays as a fallback
    if os.environ.get("SYNTH_MUSIC"):
        write(os.path.join(out_dir, "bgm_loop.wav"), bgm_casino(), peak=0.6)
    for name, make in EXTRA.items():
        write(os.path.join(out_dir, f"sfx_{name}.wav"), make())
    write(os.path.join(out_dir, "amb_crowd_loop.wav"), casino_floor_loop_cc0(), peak=0.5)
    # v11.8: loudness-master the loops so the casino bed is clearly audible on a phone
    import master_loops
    for name, target in master_loops.TARGETS.items():
        if name != "bgm_loop.wav" or os.environ.get("SYNTH_MUSIC"):
            master_loops.master(os.path.join(out_dir, name), target)
    subprocess_music = os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_music.sh")
    if not os.environ.get("SYNTH_MUSIC"):
        os.system(f'"{subprocess_music}" "{out_dir}"')
    print(f"wrote {len(SFX) + len(EXTRA) + 2} files to {os.path.abspath(out_dir)}")


if __name__ == "__main__":
    main()
