# Releases

What went to App Store Connect for each version: the texts, screenshots, App
Preview and App Clip card, with an `UPLOAD.md` that says what goes where. New
versions are filled in by `./scripts/release.sh` (via `scripts/package-release.sh`);
the details and reasons behind each text are in `docs/APP_STORE.md`.

| Version | Build | Date | What changed |
|---|---|---|---|
| [1.5.0](1.5.0/UPLOAD.md) | 38 | 2026-10-24 | Start another session: intervals when they fit your week, and why when not |
| [1.4.0](1.4.0/UPLOAD.md) | 36 | 2026-10-23 | Intervals guided on Apple Watch, every rep saved and shown against its target |
| [1.3.0](1.3.0/UPLOAD.md) | 35 | 2026-10-20 | A new look in light and dark, run colours, the pace calculator in the app |
| [1.2.0](1.2.0/UPLOAD.md) | 31 | 2026-10-20 | Plan tab with what you ran and why it changed, sessions from the training books, App Clip |
| [1.1.0](1.1.0/UPLOAD.md) | 23 | 2026-10-18 | A plan that adapts like a running buddy, an honest outlook |
| [1.0.3](1.0.3/UPLOAD.md) | 21 | 2026-10-09 | Watch runs on the iPhone Lock Screen, double tap to pause, new screenshots |
| [1.0.2](1.0.2/UPLOAD.md) | 14 | 2026-10-05 | Longer long runs for the marathon and half marathon |
| [1.0.0](1.0.0/UPLOAD.md) | 12 | 2026-09-28 | The first version |

1.0.0 to 1.2.0 were rebuilt from the repository afterwards: their screenshots from
`docs/screenshots/` at each version's last commit, in the upload order noted in
`docs/APP_STORE.md`. Their App Previews and App Clip cards weren't kept, because
`screenshots/` isn't in git.
