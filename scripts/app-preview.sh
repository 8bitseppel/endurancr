#!/bin/sh
# Records the App Store App Preview video from the demo in the Simulator:
#
#   ./scripts/app-preview.sh
#
# Writes screenshots/appstore/preview/iphone-6.9.mp4: 886 x 1920 portrait, 30 fps,
# H.264 with a silent stereo AAC track, under 30 seconds, as App Store Connect wants
# for 6.9" and 6.5" iPhones (smaller ones scale it). Only app footage, no text.
#
# Run ./scripts/screenshots.sh first: it builds and installs the demo app on the
# "endurancr" iPhone Simulator and sets its status bar to 10:09. Needs ffmpeg.
set -eu
cd "$(dirname "$0")/.."

BUILD=build/preview
OUT=screenshots/appstore/preview
mkdir -p "$BUILD" "$OUT"

PHONE=$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"].startswith("endurancr iPhone"):
            print(d["udid"]); sys.exit()
')
[ -n "$PHONE" ] || { echo "Boot the endurancr iPhone Simulator first (./scripts/screenshots.sh)." >&2; exit 1; }

# segment <name> <seconds to record> <trim start> <trim length> <launch arguments...>
segment() {
  name=$1; record=$2; from=$3; length=$4; shift 4
  xcrun simctl terminate "$PHONE" app.endurancr 2>/dev/null || true
  xcrun simctl launch "$PHONE" app.endurancr -demo "$@" >/dev/null
  sleep 1.5
  xcrun simctl io "$PHONE" recordVideo --codec=h264 --force "$BUILD/$name.mov" >/dev/null 2>&1 &
  recorder=$!
  sleep "$record"
  kill -INT "$recorder"
  wait "$recorder" || true
  # As in screenshots.sh: +igndts keeps still stretches their real length, tpad
  # holds the last frame. Then the 886 x 1920 frame and 30 fps.
  ffmpeg -loglevel error -y -fflags +igndts -i "$BUILD/$name.mov" -vf \
    "tpad=stop_mode=clone:stop_duration=3,fps=30,trim=start=$from:duration=$length,setpts=PTS-STARTPTS,scale=886:-2:flags=lanczos,crop=886:1920" \
    -an -c:v libx264 -crf 14 -pix_fmt yuv420p "$BUILD/$name.mp4"
  echo "    $name"
}

echo "==> Recording"
segment 1-welcome  3  0.3 2.4 -demoScreen welcome
segment 2-goal    10  2.4 5.6 -demoScreen goal -demoScroll YES
segment 3-today    3  0.3 2.6
segment 4-run      4  0.5 3.0 -demoScreen run
segment 5-summary  3  0.3 2.4 -demoScreen summary
segment 6-progress 10 2.4 5.4 -demoScreen progress -demoScroll YES
segment 7-plan    10 2.4 5.4 -demoScreen plan -demoScroll YES -demoScrollPoints 1500

echo "==> Joining"
# 0.35 s crossfades between the parts, then a silent stereo track for the length.
fade=0.35
inputs=""; filter=""; offset=0; prev="0:v"; i=0
for f in "$BUILD"/[1-7]-*.mp4; do
  inputs="$inputs -i $f"
  length=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  if [ "$i" -gt 0 ]; then
    filter="$filter[$prev][$i:v]xfade=transition=fade:duration=$fade:offset=$offset[v$i];"
    prev="v$i"
  fi
  offset=$(python3 -c "print(round($offset + $length - $fade, 3))")
  i=$((i + 1))
done
total=$(python3 -c "print(round($offset + $fade, 3))")
# shellcheck disable=SC2086
ffmpeg -loglevel error -y $inputs -f lavfi -t "$total" -i "anullsrc=channel_layout=stereo:sample_rate=48000" \
  -filter_complex "${filter%;}" -map "[$prev]" -map "$i:a" \
  -c:v libx264 -profile:v high -level 4.0 -r 30 -crf 16 -pix_fmt yuv420p -movflags +faststart \
  -c:a aac -b:a 256k -shortest "$OUT/iphone-6.9.mp4"

ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,channels -show_entries format=duration \
  -of compact "$OUT/iphone-6.9.mp4"
echo "==> $OUT/iphone-6.9.mp4"
