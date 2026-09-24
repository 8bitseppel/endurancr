# Contributing

Thanks for taking a look. endurancr is a small, opinionated project, so a few
ground rules keep it that way:

- **Local only.** No network calls, no accounts, no analytics, no third party
  SDKs. Apple frameworks only.
- **Swift 6** with strict concurrency, iOS 26 and watchOS 26 minimum.
- The app name is always written in lowercase: endurancr.
- The training engine lives in `TrainingCore` and is plain Swift. Run
  `swift run TrainingCoreChecks` inside `TrainingCore/` before sending a change.
- The Xcode project is generated. Edit `project.yml`, then run `xcodegen generate`.

Open an issue first for anything bigger than a small fix, so we can agree on the
approach before you spend time on it.
