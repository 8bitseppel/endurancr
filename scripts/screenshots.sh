#!/bin/sh
# Takes Simulator screenshots of endurancr on iPhone and Apple Watch, using the
# Debug-only demo data (see Shared/DemoMode.swift). Long screens are also
# recorded while they scroll and saved as GIFs. Output: screenshots/.
# Needs ffmpeg for the GIFs (brew install ffmpeg).
#
#   ./scripts/screenshots.sh
#
# Needs the iOS and watchOS Simulator runtimes:
#   xcodebuild -downloadPlatform iOS && xcodebuild -downloadPlatform watchOS
set -eu

cd "$(dirname "$0")/.."

PHONE_TYPE=${PHONE_TYPE:-"iPhone 17 Pro Max"}
WATCH_TYPE=${WATCH_TYPE:-"Apple Watch Series 11 (46mm)"}
OUT=screenshots
BUILD=build/screenshots
mkdir -p "$OUT"

# Reuses a Simulator called "endurancr <type>", creating it the first time.
device() {
  name="endurancr $1"
  udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name:
            print(d["udid"]); sys.exit()
' "$name")
  if [ -z "$udid" ]; then
    udid=$(xcrun simctl create "$name" "$1")
    >&2 echo "    created $name"
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  echo "$udid"
}

echo "==> Booting Simulators"
PHONE=$(device "$PHONE_TYPE")
WATCH=$(device "$WATCH_TYPE")
# 10:09, full bars and battery. The watch Simulator has no fixed time, so its
# clock is set to 10:09 afterwards (scripts/watch-clock.py).
xcrun simctl status_bar "$PHONE" override --time 10:09 --dataNetwork 5g \
  --cellularBars 4 --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$PHONE" appearance light   # the light look is the face of the app
xcrun simctl ui "$WATCH" appearance dark 2>/dev/null || true

echo "==> Building"
xcodegen generate --quiet
xcodebuild -project Endurancr.xcodeproj -scheme Endurancr -configuration Debug \
  -destination "id=$PHONE" -derivedDataPath "$BUILD" -quiet build
xcodebuild -project Endurancr.xcodeproj -scheme "Endurancr Watch App" -configuration Debug \
  -destination "id=$WATCH" -derivedDataPath "$BUILD" -quiet build

PHONE_APP="$BUILD/Build/Products/Debug-iphonesimulator/Endurancr.app"
WATCH_APP="$BUILD/Build/Products/Debug-watchsimulator/Endurancr Watch App.app"
xcrun simctl install "$PHONE" "$PHONE_APP"
xcrun simctl install "$WATCH" "$WATCH_APP"

# shot <device> <bundle id> <screen or "-"> <file name> [more launch arguments]
shot() {
  device=$1; bundle=$2; screen=$3; file=$4; shift 4
  xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
  if [ "$screen" = "-" ]; then
    xcrun simctl launch "$device" "$bundle" -demo "$@" >/dev/null
  else
    xcrun simctl launch "$device" "$bundle" -demo -demoScreen "$screen" "$@" >/dev/null
  fi
  set -- "$device" "$bundle" "$screen" "$file"
  sleep 4
  xcrun simctl io "$1" screenshot --type=png "$OUT/$4.png" >/dev/null 2>&1
  echo "    $OUT/$4.png"
}

# rec <device> <bundle id> <screen> <file name> <gif width> <gif fps> [more launch arguments]
# Takes the screenshot, then records the screen scrolling down and back up (the
# watch's two-page screens turn to page 2 and back instead).
rec() {
  d=$1; b=$2; scr=$3; f=$4; gw=$5; gf=$6; shift 6
  shot "$d" "$b" "$scr" "$f" "$@"
  xcrun simctl terminate "$d" "$b" 2>/dev/null || true
  if [ "$scr" = "-" ]; then
    xcrun simctl launch "$d" "$b" -demo -demoScroll YES "$@" >/dev/null
  else
    xcrun simctl launch "$d" "$b" -demo -demoScreen "$scr" -demoScroll YES "$@" >/dev/null
  fi
  set -- "$d" "$b" "$scr" "$f" "$gw" "$gf"
  sleep 2.5
  xcrun simctl io "$1" recordVideo --codec=h264 --force "$BUILD/$4.mov" >/dev/null 2>&1 &
  recorder=$!
  sleep 14
  kill -INT "$recorder"
  wait "$recorder" || true
  # The Simulator only writes a frame when the screen changes, and its decode
  # timestamps confuse ffmpeg: +igndts keeps the still stretches their real
  # length (a page held 4 s stays 4 s), tpad holds the last frame 2 s.
  ffmpeg -loglevel error -y -fflags +igndts -i "$BUILD/$4.mov" -vf \
    "tpad=stop_mode=clone:stop_duration=2,fps=$6,scale=$5:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$OUT/$4.gif"
  echo "    $OUT/$4.gif"
}

# The order follows a first week with the app: set a goal, run, check in.
echo "==> iPhone"
shot "$PHONE" app.endurancr welcome iphone-1-welcome
rec  "$PHONE" app.endurancr goal iphone-2-goal 360 20
shot "$PHONE" app.endurancr - iphone-3-today
shot "$PHONE" app.endurancr run iphone-4-run
# The run just finished was an interval session: its reps, two a little slow.
shot "$PHONE" app.endurancr summary iphone-5-summary -demoReps YES
rec  "$PHONE" app.endurancr progress iphone-6-progress 360 20
shot "$PHONE" app.endurancr plan iphone-7-plan
# Last week: runs done (highlighted), one missed (struck through), an extra run on a rest day.
shot "$PHONE" app.endurancr plan iphone-8-week -demoPlanWeek 6
# The pace calculator, on its results.
shot "$PHONE" app.endurancr paces iphone-9-paces -clipResults
# Another session: intervals offered today instead of the easy run.
shot "$PHONE" app.endurancr - iphone-10-another -demoOffers offer -demoOffersOpen YES

# The same in dark, for the light and dark slider on the website.
echo "==> iPhone, dark"
xcrun simctl ui "$PHONE" appearance dark
shot "$PHONE" app.endurancr welcome iphone-1-welcome-dark
rec  "$PHONE" app.endurancr goal iphone-2-goal-dark 360 20
shot "$PHONE" app.endurancr - iphone-3-today-dark
shot "$PHONE" app.endurancr run iphone-4-run-dark
shot "$PHONE" app.endurancr summary iphone-5-summary-dark -demoReps YES
rec  "$PHONE" app.endurancr progress iphone-6-progress-dark 360 20
shot "$PHONE" app.endurancr plan iphone-7-plan-dark
shot "$PHONE" app.endurancr plan iphone-8-week-dark -demoPlanWeek 6
shot "$PHONE" app.endurancr paces iphone-9-paces-dark -clipResults
shot "$PHONE" app.endurancr - iphone-10-another-dark -demoOffers offer -demoOffersOpen YES
xcrun simctl ui "$PHONE" appearance light

echo "==> App Clip"
xcrun simctl install "$PHONE" "$BUILD/Build/Products/Debug-iphonesimulator/EndurancrClip.app"
clip() {
  # Close the full app first, so the status bar shows no "back to endurancr" link.
  xcrun simctl terminate "$PHONE" app.endurancr 2>/dev/null || true
  xcrun simctl terminate "$PHONE" app.endurancr.Clip 2>/dev/null || true
  xcrun simctl launch "$PHONE" app.endurancr.Clip "$@" >/dev/null
  sleep 4
}
clip; xcrun simctl io "$PHONE" screenshot --type=png "$OUT/clip-1-calculator.png" >/dev/null 2>&1
clip -clipResults; xcrun simctl io "$PHONE" screenshot --type=png "$OUT/clip-2-results.png" >/dev/null 2>&1
echo "    $OUT/clip-1-calculator.png, $OUT/clip-2-results.png"

echo "==> Apple Watch"
# Home, then a turn of the Crown to Another session and back.
rec "$WATCH" app.endurancr.watchkitapp - watch-1-today 312 25 -demoOffers offer
rec "$WATCH" app.endurancr.watchkitapp run watch-2-run 312 25
rec "$WATCH" app.endurancr.watchkitapp summary watch-3-summary 312 25 -demoReps YES
# Intervals: the card when a rep starts, and the reps after the run.
rec  "$WATCH" app.endurancr.watchkitapp run watch-4-intervals 312 25 -demoStepCard YES
rec  "$WATCH" app.endurancr.watchkitapp summary watch-5-reps 312 25 -demoReps YES -demoRepsPage YES
shot "$WATCH" app.endurancr.watchkitapp - watch-6-another -demoOffers offer -demoOffersOpen YES
python3 scripts/watch-clock.py

echo "==> Done"
