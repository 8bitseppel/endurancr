<p align="center">
  <img src="website/logo.svg" width="240" height="240" alt="endurancr app icon">
</p>

<h1 align="center">endurancr</h1>

<p align="center">
  Run for you. Not for the feed.<br>
  A private, adaptive running plan for iPhone and Apple Watch.
</p>

<p align="center">
  <a href="https://apps.apple.com/app/endurancr/id6815730653">App Store</a> ·
  <a href="https://endurancr.app">endurancr.app</a> ·
  <a href="https://endurancr.app/privacy">Privacy</a> ·
  <a href="LICENSE">MIT License</a>
</p>

---

endurancr builds a training plan around your goal and the pace you actually like,
records your runs on Apple Watch or iPhone, and adapts the plan to what you really
ran. Paces come from the VDOT method by Jack Tupper Daniels.

- **Local only.** No account, no server, no analytics, no ads. The plan is stored on
  your device, and your runs live in Apple Health.
- **Free.** No subscription and no in-app purchases.
- **Open source.** You can read every line that touches your data.

<p align="center">
  <img src="docs/screenshots/iphone-1-welcome.png" width="180" alt="Start: set your goal">
  <img src="docs/screenshots/iphone-2-goal.gif" width="180" alt="Setting up the goal">
  <img src="docs/screenshots/iphone-3-today.png" width="180" alt="Today">
  <img src="docs/screenshots/iphone-4-run.png" width="180" alt="Running">
</p>
<p align="center">
  <img src="docs/screenshots/iphone-5-summary.png" width="180" alt="Run complete">
  <img src="docs/screenshots/iphone-6-progress.gif" width="180" alt="Progress">
  <img src="docs/screenshots/iphone-7-plan.png" width="180" alt="Plan">
</p>
<p align="center">
  <img src="docs/screenshots/watch-1-today.png" width="156" alt="Watch home">
  <img src="docs/screenshots/watch-2-run.gif" width="156" alt="Watch during a run">
  <img src="docs/screenshots/watch-3-summary.gif" width="156" alt="Watch after a run">
</p>

## Features

- A goal (for example a marathon on a given date) or a target VDOT, and a plan that
  builds towards it week by week.
- The plan adapts like a running buddy who isn't pushy, and never piles missed
  kilometres onto later days:
  - 90% or more of the planned distance over two weeks keeps it building
    (Pfitzinger's benchmark). 75 to 90% holds the week. Below that it rebuilds from
    what you ran, at most 10% more a week, and the next hard session becomes easy.
  - After more than 5 days off, paces ease by Daniels' table and easy-only weeks
    bring you back at a share of your volume before the break.
  - No run is planned more than 10% longer than your longest of the last 30 days
    (Frandsen et al. 2025).
  - VDOT goes up by at most 1 point per 3 weeks, and down 1 when hard sessions
    keep coming in slower than their targets.
- An honest outlook: finish-time ranges for today and race day, and whether the
  target is on track, within reach, a stretch or unlikely, with a realistic time
  to switch to (only if you tap it). Marathon ranges account for weekly distance
  (Vickers & Vertosick 2016).
- Honest marathon pace: when your fitness comes from a much shorter race, marathon
  pace and the finish prediction start up to 3 VDOT lower, and long runs earn it
  back (fully at 25 km for a marathon). Until they do, you get a full build, never
  a "good to go" plan. Easy and interval paces keep your speed.
- Long runs that build to the race: for a marathon, 32 km runs 5 and 3 weeks before race
  day (growing about 2 km a week, never more than half the week), for a half
  marathon 19 km, then shorter long runs in the two taper weeks.
- Runs are spread over the repeating week: a rest day after the Sunday long run when
  there's one to spare, and no threshold or intervals right next to the long run.
- Swap days by dragging them in the plan; the watch shows the same adjusted days.
- A run on Apple Watch shows on the iPhone's Lock Screen too, through HealthKit workout
  mirroring, with Pause and Finish. Auto-pause comes from watchOS (Auto-Pause in the
  watch's Workout settings), and a double tap pauses or resumes.
- Live run screens on Apple Watch and iPhone, with a Live Activity and controls on
  the Lock Screen.
- The plan syncs directly between iPhone and Apple Watch with WatchConnectivity.
- Backup and import of your plan as a file, only when you choose to share it.

## Project layout

```
TrainingCore/       Plain Swift package: VDOT engine, plan generator, adaptation. Runs anywhere.
Shared/             Code shared by both apps: HealthKit, SwiftData store, plan coordinator.
App-iOS/            iPhone app.
App-iOS-Widgets/    Live Activity extension.
App-watchOS/        Apple Watch app and run recorder.
LiveActivity/       Shared Live Activity attributes and App Intents.
website/            endurancr.app, a static site on Cloudflare Pages.
project.yml         XcodeGen project definition.
```

## Requirements

- Xcode 27 or newer, with the iOS 26 and watchOS 26 SDKs
- Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A real iPhone and Apple Watch to test runs, since the Simulator has no heart rate
  or real GPS

## Build

Check the training engine first. It needs no Xcode project:

```sh
cd TrainingCore
swift run TrainingCoreChecks
```

Then generate and open the app project:

```sh
xcodegen generate
open Endurancr.xcodeproj
```

To run it on your own devices, set your own team in `project.yml`
(`DEVELOPMENT_TEAM`) and change the bundle identifiers (`app.endurancr`,
`app.endurancr.widgets`, `app.endurancr.watchkitapp`) to a prefix you own. Then run
`xcodegen generate` again.

## Screenshots and releases

`./scripts/screenshots.sh` takes the screenshots on the iPhone and Apple Watch
Simulators, using sample data that only exists in Debug builds
(`Shared/DemoMode.swift`): a 4:30 marathon plan from a 12.2 km run at 5:36/km, six
weeks in. Long screens are recorded while they scroll, and the watch's two-page
screens while they turn to page 2 and back (needs ffmpeg and Pillow). Every clock
reads 10:09. `./scripts/publish-screenshots.sh` then copies them to the README
(`docs/screenshots/`), the App Store folders (`screenshots/appstore/`, in three
iPhone sizes, plus the iOS 27 header and search images) and the website.
`./scripts/release.sh` raises the build number and archives a build for the App Store.

## Privacy

endurancr makes no network requests. It reads and writes workouts, heart rate and
routes in Apple Health only with your permission, and uses location only while you
record a run. Read the full [privacy policy](https://endurancr.app/privacy).

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md)
first, and report security problems privately as described in
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 Sebastian Käßinger
