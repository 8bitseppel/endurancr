#!/bin/sh
# Copies the screenshots from ./scripts/screenshots.sh to where they're used:
#   docs/screenshots/            README images and GIFs
#   screenshots/appstore/        App Store screenshots, 6.9" (1320 x 2868), named in
#                                upload order, plus 6.5-inch/ (1284 x 2778) and
#                                6.3-inch/ (1206 x 2622) copies, and the watch (416 x 496)
#   website/screens/             WebP stills and MP4 videos for endurancr.app
# then builds the App Store creative assets (scripts/appstore-creatives.py).
# Needs Pillow and ffmpeg.
set -e
cd "$(dirname "$0")/.."
S=screenshots
A=$S/appstore
mkdir -p docs/screenshots "$A/6.5-inch" "$A/6.3-inch" website/screens

for f in iphone-1-welcome.png iphone-2-goal.gif iphone-2-goal.png iphone-3-today.png iphone-4-run.png \
         iphone-5-summary.png iphone-6-progress.gif iphone-6-progress.png iphone-7-plan.png iphone-8-week.png iphone-9-paces.png \
         watch-1-today.png watch-2-run.gif watch-2-run.png watch-3-summary.gif watch-3-summary.png \
         watch-4-intervals.png watch-5-reps.png; do
  cp "$S/$f" docs/screenshots/
done

# App Store order: Today, Progress, Plan, Last week, Paces, Run, Run complete, Goal, Welcome.
rm -f $A/iphone-*.png $A/6.5-inch/iphone-*.png $A/6.3-inch/iphone-*.png
cp $S/iphone-3-today.png    $A/iphone-1-today.png
cp $S/iphone-6-progress.png $A/iphone-2-progress.png
cp $S/iphone-7-plan.png     $A/iphone-3-plan.png
cp $S/iphone-8-week.png     $A/iphone-4-week.png
cp $S/iphone-9-paces.png    $A/iphone-5-paces.png
cp $S/iphone-4-run.png      $A/iphone-6-run.png
cp $S/iphone-5-summary.png  $A/iphone-7-summary.png
cp $S/iphone-2-goal.png     $A/iphone-8-goal.png
cp $S/iphone-1-welcome.png  $A/iphone-9-welcome.png
cp $S/watch-1-today.png     $A/watch-1-today.png
cp $S/watch-2-run.png       $A/watch-2-run.png
cp $S/watch-3-summary.png   $A/watch-3-summary.png
cp $S/watch-4-intervals.png $A/watch-4-intervals.png
cp $S/watch-5-reps.png      $A/watch-5-reps.png

python3 - <<'PY'
from pathlib import Path
from PIL import Image
A = Path("screenshots/appstore")
for p in sorted(A.glob("iphone-*.png")) + sorted(A.glob("watch-*.png")):
    # No alpha channel: App Store Connect can refuse screenshots that have one.
    im = Image.open(p).convert("RGB")
    im.save(p)
    if p.name.startswith("watch"):
        continue
    # 6.5": scale to 1284 wide, trim to 2778. 6.3": scale to 2622 high, trim to 1206.
    w = 1284
    im.resize((w, round(im.height * w / im.width)), Image.LANCZOS).crop((0, 0, 1284, 2778)).save(A / "6.5-inch" / p.name)
    im.resize((1207, 2622), Image.LANCZOS).crop((0, 0, 1206, 2622)).save(A / "6.3-inch" / p.name)
for p in sorted(Path("screenshots").glob("iphone-*.png")) + sorted(Path("screenshots").glob("watch-*.png")):
    im = Image.open(p).convert("RGB")
    w = 340 if p.name.startswith("watch") else 660
    im.resize((w, round(im.height * w / im.width)), Image.LANCZOS).save(f"website/screens/{p.stem}.webp", "WEBP", quality=82, method=6)
PY

# Videos for the website. +igndts: the Simulator's recordings confuse ffmpeg's
# timing otherwise (see screenshots.sh).
for n in iphone-2-goal iphone-2-goal-dark iphone-6-progress iphone-6-progress-dark watch-2-run watch-3-summary; do
  w=440; case $n in watch*) w=340;; esac
  ffmpeg -loglevel error -y -fflags +igndts -i "build/screenshots/$n.mov" \
    -vf "fps=30,scale=$w:-2:flags=lanczos" -c:v libx264 -crf 26 -pix_fmt yuv420p -movflags +faststart -an \
    "website/screens/$n.mp4"
done

python3 scripts/appstore-creatives.py
echo "==> Published"
