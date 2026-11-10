#!/bin/bash
# v11.8 background music: "Catchy Swing" (CC0, see tools/audio/cc0/README.md), 60 s seamless loop,
# loudness-normalised to about -18 LUFS, 32 kHz mono 16-bit WAV (WAV loops without a gap in AVAudioPlayer).
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-../../ios/CoinBounce/Audio}/bgm_loop.wav"
ffmpeg -v error -y -i cc0/oga_catchy_swing/catchyswing.ogg -ac 1 -ar 32000 -af "loudnorm=I=-18:TP=-1.5:LRA=11" -ar 32000 -c:a pcm_s16le "$OUT"
python3 loudness.py "$OUT"
