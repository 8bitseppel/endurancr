#!/bin/sh
# Builds a release archive of endurancr for TestFlight.
#
#   ./scripts/release.sh            raise the build number, then archive
#   ./scripts/release.sh --no-bump  archive with the current build number
#   ./scripts/release.sh --upload   archive, then upload to App Store Connect
#
# The archive lands in Xcode's Archives folder, so it also shows up in
# Window > Organizer, where you can press Distribute App yourself.
set -eu

cd "$(dirname "$0")/.."

BUMP=1
UPLOAD=0
for arg in "$@"; do
  case "$arg" in
    --no-bump) BUMP=0 ;;
    --upload) UPLOAD=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

current_build() {
  sed -n -E 's/^ *CURRENT_PROJECT_VERSION: "?([0-9]+)"?$/\1/p' project.yml | head -1
}
VERSION=$(sed -n -E 's/^ *MARKETING_VERSION: "?([0-9.]+)"?$/\1/p' project.yml | head -1)

if [ "$BUMP" = 1 ]; then
  NEXT=$(( $(current_build) + 1 ))
  sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: )\"?[0-9]+\"?$/\1\"$NEXT\"/" project.yml
fi
BUILD=$(current_build)
echo "==> endurancr $VERSION ($BUILD)"

echo "==> Checking the training engine"
(cd TrainingCore && swift run -q TrainingCoreChecks | tail -1)

echo "==> Generating the Xcode project"
xcodegen generate --quiet

ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/endurancr $VERSION ($BUILD).xcarchive"
echo "==> Archiving to $ARCHIVE"
xcodebuild -project Endurancr.xcodeproj -scheme Endurancr -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates -quiet archive

if [ "$UPLOAD" = 1 ]; then
  OPTIONS=$(mktemp -t endurancr-export).plist
  cat > "$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF
  echo "==> Uploading to App Store Connect"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
    -exportPath "$(mktemp -d)" -allowProvisioningUpdates
  echo "==> Uploaded. TestFlight shows the build once Apple has processed it."
else
  echo "==> Done. Open Xcode > Window > Organizer, pick \"endurancr $VERSION ($BUILD)\","
  echo "    then Distribute App > App Store Connect."
fi
