# Audio credits

## Third-party audio (CC0, public domain)

Downloaded on 2026-11-09 with the owner's consent. CC0 1.0 needs no attribution; we credit the
authors anyway. The source files and licence proof are kept in `tools/audio/cc0/` (see its README).

| Used in | Work | Author | Source | Licence |
|---|---|---|---|---|
| `bgm_loop.wav` (background music) | "Catchy Swing" (60 s loop) | Doge | https://opengameart.org/content/catchy-swing | CC0 1.0 |
| `amb_crowd_loop.wav` (casino floor) | 14 chip and card clips from "Casino Audio" 1.1 | Kenney Vleugels (Kenney.nl) | https://kenney.nl/assets/casino-audio | CC0 1.0 (`tools/audio/cc0/kenney_casino_audio/License.txt`) |
| `amb_crowd_loop.wav` (casino floor) | "Bell dings/chimes" | PWL | https://opengameart.org/content/bell-dingschimes | CC0 1.0 |

## Original audio

Everything else is synthesized by `tools/audio/generate_audio.py` with the Python standard library
(oscillators, filtered noise, envelopes): all `sfx_*.wav` effects, plus the crowd murmur, distant
slot-machine jingles, synth bells and coin cascades in the floor ambience. No samples were used.

The eight pachinko effects (`sfx_pk_launch`, `sfx_pk_nail_1`…`3`, `sfx_pk_start`, `sfx_pk_reach`,
`sfx_pk_attacker`, `sfx_pk_count`, v12.5) are synthesized the same way: `python3 tools/audio/generate_audio.py --pachinko`
writes only those files.

## How the shipped loops are made (v11.8)

- `tools/audio/make_music.sh` renders `bgm_loop.wav` from "Catchy Swing": 32 kHz mono, about −18 LUFS.
- `python3 tools/audio/generate_audio.py --ambience` renders `amb_crowd_loop.wav`: the synthesized
  floor plus the CC0 chip, card and bell recordings. 20 s seamless loop, mastered to about −21 LUFS by
  `master_loops.py`.
- `tools/audio/loudness.py` measures loudness (BS.1770 K-weighted, gated). Music plus ambience comes to
  about −16.5 LUFS. The coin effects play at 0.6 volume (about −19 LUFS) on top.

Playback (`AudioManager`): music and ambience play at full volume and follow the Music switch; effects
follow the Sound switch. The audio session is `.ambient`, so the silent switch mutes everything and
the player's own music keeps playing. Big wins, the jackpot, cheers, applause and the fanfare duck the
music and ambience to 30% while they play.
