#!/bin/sh
# Collects everything to upload to App Store Connect for this version into
# releases/<version>/, so each version keeps a record of what went to the store:
#
#   ./scripts/package-release.sh
#
#   UPLOAD.md                 what goes where, with the build number
#   promotional-text.txt      the texts from docs/APP_STORE.md, ready to paste
#   whats-new.txt
#   description.txt
#   keywords.txt
#   app-clip-subtitle.txt
#   screenshots/6.9-inch/     iPhone screenshots, in upload order
#   screenshots/6.5-inch/
#   screenshots/6.3-inch/
#   screenshots/watch/
#   app-preview/iphone-6.9.mp4
#   app-clip/card-3x2.png     the App Clip card header image
#   product-page/             header (21:9) and search results (3:2) images
#
# Run ./scripts/screenshots.sh, ./scripts/publish-screenshots.sh and
# ./scripts/app-preview.sh first; ./scripts/release.sh runs this after archiving.
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n -E 's/^ *MARKETING_VERSION: "?([0-9.]+)"?$/\1/p' project.yml | head -1)
BUILD=$(sed -n -E 's/^ *CURRENT_PROJECT_VERSION: "?([0-9]+)"?$/\1/p' project.yml | head -1)
OUT="releases/$VERSION"
A=screenshots/appstore

rm -rf "$OUT"
mkdir -p "$OUT/screenshots/6.9-inch" "$OUT/screenshots/6.5-inch" "$OUT/screenshots/6.3-inch" \
  "$OUT/screenshots/watch" "$OUT/app-preview" "$OUT/app-clip" "$OUT/product-page"

cp $A/iphone-*.png "$OUT/screenshots/6.9-inch/"
cp $A/6.5-inch/iphone-*.png "$OUT/screenshots/6.5-inch/"
cp $A/6.3-inch/iphone-*.png "$OUT/screenshots/6.3-inch/"
cp $A/watch-*.png "$OUT/screenshots/watch/"
cp $A/preview/iphone-6.9.mp4 "$OUT/app-preview/"
cp $A/appclip/card-3x2.png "$OUT/app-clip/"
cp $A/creative/header-21x9.png $A/creative/search-3x2.png "$OUT/product-page/"

# The texts, from this version's section of docs/APP_STORE.md (the keywords and the
# App Clip subtitle from wherever they were last set).
VERSION="$VERSION" OUT="$OUT" python3 - <<'PY'
import os, re
doc = open("docs/APP_STORE.md").read()
version, out = os.environ["VERSION"], os.environ["OUT"]
m = re.search(rf"^## Version {re.escape(version)}\n(.*?)(?=^## |\Z)", doc, re.S | re.M)
if not m:
    raise SystemExit(f"docs/APP_STORE.md has no '## Version {version}' section")
section = m.group(1)

def sub(text, heading):
    m = re.search(rf"^### {re.escape(heading)}[^\n]*\n(.*?)(?=^### |\Z)", text, re.S | re.M)
    return m.group(1).strip() if m else None

def last(heading):
    found = [x for x in re.findall(rf"^### {re.escape(heading)}[^\n]*\n(.*?)(?=^### |^## |\Z)", doc, re.S | re.M)]
    return found[-1].strip() if found else None

texts = {
    "promotional-text.txt": sub(section, "Promotional text"),
    "whats-new.txt": sub(section, "What's New"),
    "description.txt": sub(section, "Description"),
    "keywords.txt": last("Keywords"),
}
subtitle = re.findall(r"\*\*Subtitle \(56\):\*\* `([^`]+)`", doc)
if subtitle:
    texts["app-clip-subtitle.txt"] = subtitle[-1]
for name, text in texts.items():
    if not text:
        raise SystemExit(f"Missing text for {name} in docs/APP_STORE.md")
    open(f"{out}/{name}", "w").write(text + "\n")
limits = {"promotional-text.txt": 170, "whats-new.txt": 4000, "description.txt": 4000, "keywords.txt": 100}
for name, limit in limits.items():
    n = len(texts[name])
    print(f"    {name}: {n} of {limit} characters" + ("  TOO LONG" if n > limit else ""))
    if n > limit:
        raise SystemExit(1)
PY

cat > "$OUT/UPLOAD.md" <<EOF
# endurancr $VERSION ($BUILD)

Everything for the $VERSION page in App Store Connect, as it was uploaded.

1. **Build:** Xcode > Window > Organizer, "endurancr $VERSION ($BUILD)", Distribute App >
   App Store Connect. On the $VERSION page, pick build $BUILD.
2. **Texts:** paste \`promotional-text.txt\`, \`whats-new.txt\`, \`description.txt\` and
   \`keywords.txt\`.
3. **iPhone screenshots:** \`screenshots/6.9-inch/\` under 6.9", in file name order
   (\`6.5-inch/\` and \`6.3-inch/\` only if App Store Connect asks for those sizes).
4. **App Preview:** \`app-preview/iphone-6.9.mp4\` under 6.9", before the screenshots.
5. **Apple Watch screenshots:** \`screenshots/watch/\`.
6. **App Clip:** pick build $BUILD's clip, subtitle from \`app-clip-subtitle.txt\`, action
   Open, header image \`app-clip/card-3x2.png\` (save the subtitle and action first).
7. **Product page header and search results:** \`product-page/header-21x9.png\` (21:9,
   3840 x 1646) and \`product-page/search-3x2.png\` (3:2, 3840 x 2560), under the version
   or in the Asset Library; check them in the product page preview, in Dark Mode too.
8. Save, then Add for Review.

Details and the reasons behind each text: docs/APP_STORE.md, "Version $VERSION".
EOF

echo "==> $OUT ($VERSION, build $BUILD)"
