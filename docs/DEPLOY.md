# Deploying endurancr to your iPhone

How to build and install the app onto a physical, cable-connected iPhone from
this Mac. This worked in earlier sessions; this doc captures the exact steps so
it's repeatable.

## Prerequisites (already true on this Mac)

- **Xcode 27** and **xcodegen 2.46.0** are installed.
- Signing is baked into `project.yml`: `DEVELOPMENT_TEAM: CZS8ZHY988`, automatic
  signing. `xcodegen generate` preserves it, so you never have to re-enter the
  team in Xcode after regenerating.
- Bundle IDs: `app.endurancr` (app), `.watchkitapp` (watch),
  `.widgets` (widgets).
- Deployment targets: iOS 26.0 / watchOS 26.0.

## Connected device

- Verify your iPhone is visible any time with:
  ```
  xcrun xctrace list devices
  ```
  The iPhone must be unlocked, trusted ("Trust This Computer"), and Developer
  Mode enabled (Settings → Privacy & Security → Developer Mode).

## ⚠️ Don't force `-sdk` on the command line

The app compiles and deploys fine as-is (verified 2026-09-21). But note this
gotcha: **never pass `-sdk iphonesimulator…` to `xcodebuild` for this project.**
That flag forces the simulator SDK onto the *entire* dependency graph, including
the embedded **watchOS** app, so the watch target gets miscompiled as an iOS
target. You then get spurious errors like `'HKLiveWorkoutBuilder' is only
available in iOS 26.0 or newer` in `App-watchOS/WorkoutManager.swift` — that API
is fine on watchOS, the error only appears because the file was wrongly built
for iOS. Let each target build for its own platform (device destination, or
Xcode's Run) and it just works.

---

## Path A — Xcode GUI (simplest)

1. Regenerate the project (safe to run any time; keeps signing):
   ```
   xcodegen generate
   ```
2. Open it:
   ```
   open Endurancr.xcodeproj
   ```
3. In the toolbar's run-destination dropdown, pick **Ding** (the physical iPhone,
   not a simulator).
4. Select the **Endurancr** scheme.
5. Press **⌘R** (Run). Xcode builds, signs, installs, and launches on the phone.
   - First install: on the iPhone, approve the developer under
     Settings → General → VPN & Device Management if prompted.

## Path B — Command line (no GUI)

1. Regenerate:
   ```
   xcodegen generate
   ```
2. Build **and install** onto the connected device in one step:
   ```
   xcodebuild \
     -project Endurancr.xcodeproj \
     -scheme Endurancr \
     -destination 'id=<YOUR-DEVICE-UDID>' \
     -allowProvisioningUpdates \
     build
   ```
   `xcodebuild` with a device `-destination` builds a signed device binary.
   `-allowProvisioningUpdates` lets it fetch/refresh the provisioning profile for
   the personal team automatically.
3. `xcodebuild build` produces the signed `.app` but does not install it. Install
   it onto the device:
   ```
   xcrun devicectl device install app \
     --device <YOUR-DEVICE-UDID> \
     ~/Library/Developer/Xcode/DerivedData/Endurancr-*/Build/Products/Debug-iphoneos/Endurancr.app
   ```

---

## Troubleshooting

- **"No devices found" / device greyed out:** unlock the phone, tap "Trust", and
  make sure Developer Mode is on. Re-check with `xcrun xctrace list devices`.
- **Signing errors:** confirm `DEVELOPMENT_TEAM: CZS8ZHY988` in `project.yml`,
  run `xcodegen generate` again, and use `-allowProvisioningUpdates`.
- **7-day expiry:** apps signed with a personal (free) Apple team stop launching
  after ~7 days — just re-run to reinstall. A paid Apple Developer account
  removes this and is what you'd use for TestFlight.
- **`HKLiveWorkoutBuilder is only available in iOS 26.0` in `WorkoutManager.swift`:**
  you forced `-sdk iphonesimulator…` — see the warning near the top. Build for a
  device destination (or use Xcode Run) instead; the code is correct.
- **`database is locked … two concurrent builds`:** an Xcode build and a terminal
  `xcodebuild` hit the same DerivedData at once. Run only one at a time; if stuck,
  ⇧⌘K (Clean Build Folder) or quit/reopen Xcode.

## Beyond the phone: TestFlight

Installing on your own device (above) needs no App Store Connect access. A
TestFlight distribution additionally requires a paid Apple Developer account and
your App Store Connect credentials, then `Product → Archive` in Xcode (or
`xcodebuild archive` + `xcrun altool`/Transporter) and an upload.
