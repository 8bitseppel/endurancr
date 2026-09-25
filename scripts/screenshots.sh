#!/bin/sh
# Takes Simulator screenshots of endurancr on iPhone and Apple Watch, using the
# Debug-only demo data (see Shared/DemoMode.swift). Output: screenshots/.
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
# 9:41, full bars and battery, like Apple's own screenshots.
xcrun simctl status_bar "$PHONE" override --time 9:41 --dataNetwork 5g \
  --cellularBars 4 --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$PHONE" appearance dark
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

# shot <device> <bundle id> <screen or "-"> <file name>
shot() {
  xcrun simctl terminate "$1" "$2" 2>/dev/null || true
  if [ "$3" = "-" ]; then
    xcrun simctl launch "$1" "$2" -demo >/dev/null
  else
    xcrun simctl launch "$1" "$2" -demo -demoScreen "$3" >/dev/null
  fi
  sleep 4
  xcrun simctl io "$1" screenshot --type=png "$OUT/$4.png" >/dev/null 2>&1
  echo "    $OUT/$4.png"
}

echo "==> iPhone"
shot "$PHONE" app.endurancr - iphone-1-today
shot "$PHONE" app.endurancr progress iphone-2-progress
shot "$PHONE" app.endurancr plan iphone-3-plan
shot "$PHONE" app.endurancr run iphone-4-run

echo "==> Apple Watch"
shot "$WATCH" app.endurancr.watchkitapp - watch-1-today
shot "$WATCH" app.endurancr.watchkitapp run watch-2-run
shot "$WATCH" app.endurancr.watchkitapp summary watch-3-summary

echo "==> Done"
