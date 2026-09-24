# endurancr: TestFlight checklist

Version 1.0.0 (build 1). Bundle IDs: `app.endurancr` (iOS), `app.endurancr.watchkitapp`
(watch, embedded), `app.endurancr.widgets` (Live Activity extension, embedded).
Team `CZS8ZHY988`. TestFlight needs a paid Apple Developer Program membership;
a free personal team cannot upload.

## 1. Build commands (from the repo root)

```sh
xcodegen generate                 # project.yml is the source of truth

# Compile check, no signing (builds the iOS app + embedded watch app + widget extension)
xcodebuild -project Endurancr.xcodeproj -scheme Endurancr -configuration Release \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# Archive (automatic signing; lets Xcode create/refresh distribution profiles)
xcodebuild -project Endurancr.xcodeproj -scheme Endurancr -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/endurancr.xcarchive \
  -allowProvisioningUpdates archive

# Unit checks for the training engine
(cd TrainingCore && swift run TrainingCoreChecks)
```

Never pass `-sdk` on the command line (it miscompiles the watch target, see `docs/DEPLOY.md`).
For every new upload, bump `CURRENT_PROJECT_VERSION` in `project.yml` (all three targets inherit it).

## 2. App Store Connect (one time)

1. Xcode > Settings > Accounts: make sure the Apple ID for team CZS8ZHY988 is signed in.
2. Developer portal (Certificates, IDs & Profiles): confirm App IDs exist for
   `app.endurancr`, `app.endurancr.watchkitapp`, `app.endurancr.widgets`, with the
   HealthKit capability on the app and watch IDs. Automatic signing usually creates them
   on the first archive.
3. App Store Connect > Apps > + > New App:
   - Platform iOS, name `endurancr`, primary language, bundle ID `app.endurancr`, SKU e.g. `endurancr`.
4. App Information:
   - Privacy Policy URL: https://endurancr.app/privacy
   - Support URL (on the version page): https://endurancr.app
   - Category: Health & Fitness.
5. App Privacy: answer "No, we do not collect data from this app" (matches the
   PrivacyInfo.xcprivacy manifests: no tracking, no collected data).

## 3. Archive and upload

1. `xcodegen generate`, then `open Endurancr.xcodeproj`.
2. Scheme `Endurancr`, destination "Any iOS Device (arm64)".
3. Product > Archive.
4. Organizer > select the archive > Distribute App > TestFlight (or App Store Connect) > Upload.
   Keep "Upload your app's symbols" and "Manage version and build number" defaults.
5. Wait for processing (email). Export compliance is pre-answered
   (`ITSAppUsesNonExemptEncryption = NO`).

## 4. TestFlight setup

1. TestFlight tab > Test Information:
   - Beta App Description, e.g.: "endurancr builds an adaptive marathon training plan from
     your goal and your runs in Apple Health. Record runs on iPhone or Apple Watch; the plan
     adjusts as you train. Everything stays on your device."
   - Feedback email, and the privacy policy URL above.
2. What to Test (per build), e.g.:
   - Set a goal and check the generated plan.
   - Record a run on iPhone with the screen locked; use Pause/Resume/Finish on the Live Activity.
   - Record a run on Apple Watch; confirm the plan appears on the watch after opening the phone app.
   - Check that runs show up in Apple Health and the plan adapts afterwards.
   - Export and re-import a backup in Data Management.
3. Internal testing: add yourself to an internal group, install via the TestFlight app.
4. External testing: create an external group, add the build, submit for Beta App Review.
   Once approved, enable the Public Link and share it.
