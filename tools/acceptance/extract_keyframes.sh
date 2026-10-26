#!/bin/bash
set -euo pipefail

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found"
  exit 1
fi

in="${1:-}"
out_dir="${2:-}"
fps="${3:-2}" # default: 2 fps for quick browsing

if [ -z "$in" ] || [ -z "$out_dir" ]; then
  echo "Usage: $0 <input_video> <out_dir> [fps]"
  exit 1
fi

mkdir -p "$out_dir"

# Extract frames at fixed fps (deterministic).
ffmpeg -hide_banner -loglevel error -y \
  -i "$in" \
  -vf "fps=${fps},scale=400:-1:flags=lanczos" \
  "$out_dir/frame_%04d.png"

echo "Extracted frames to: $out_dir"

