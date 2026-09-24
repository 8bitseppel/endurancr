# Feature: Plan Export / Import (offline backup & phone migration)

**Status:** implemented.
- `PlanBackup` + `PlanBackupCodec` in TrainingCore (pure, covered by the "Plan
  backup" suite in `TrainingCoreChecks`).
- `PlanCoordinator.exportData()` / `importData(_:)`.
- iOS UI: `DataManagementView` (share-sheet export via `.fileExporter`, restore via
  `.fileImporter`), reachable from the dashboard's Planning section ("Backup &
  restore") and the no-plan empty state ("Import a backup").

**Design change vs. the original plan below:** the store now persists only the
regenerable `PlanInputs` (~1 KB, option 1), not the 89 KB expanded calendar, so the
export is already tiny. We therefore write **plain (pretty-printed) JSON, not gzip** —
compression would add an Apple-only `Compression` dependency to the otherwise
platform-agnostic package for no meaningful saving, and would cost the file its
human-readability. The envelope wraps `PlanInputs` rather than a full `TrainingPlan`.

---

_Original design notes (retained for context):_
**Motivation:** the training plan lives only in a local SwiftData store. There is no
manual backup, and TestFlight builds expire after 90 days, so a new-phone restore
can land with no way to recover the plan. This adds an offline, cloud-free
export/import so the user can move their plan between devices.

## Constraints (from project charter)

- Local-only. **No cloud, no backend, no account, no network.**
- Apple frameworks only. Export goes through the share sheet / Files / AirDrop.
- **No personal data.** The stored/exported payload holds only training inputs
  (race, date, target time, VDOT, paces, self-labeled vacation periods) — no name,
  no identity, no location. GPS routes are written to HealthKit (Apple's store),
  never to our file. Vacation `reason` is free text the user types; keep it optional
  and unlabeled by default so nothing sensitive is required.
- **On-device data as small as possible**, and the file too. This pushes us toward
  storing *inputs* and regenerating the calendar rather than persisting 480 expanded
  workouts (see below).

## What is (and isn't) in the data

| Store | Contents | Exported? |
|---|---|---|
| SwiftData `StoredPlan` | goal, race + date, **vacation periods**, VDOT, paces, all weeks/workouts | **Yes** — this is the export |
| HealthKit | every recorded run (workout, HR, distance, energy, resting HR) | **No** — migrates with the OS (encrypted iCloud backup / device-to-device); source of truth for runs |

The plan is **regenerable**: reinstall → onboarding → the engine re-rates VDOT from
HealthKit history. Export exists to preserve the *goal metadata* (race, target,
vacation periods) and the adapted plan without re-entry.

## Measured size (today)

Full 69-week marathon plan, `JSONEncoder()` default (what `StoredPlan` uses):

- **Compact JSON: ~89 KB** (~185 B/workout, 480 workouts)
- Pretty-printed: ~150 KB
- A 16-week 5K plan: ~15 KB

Size scales with **number of weeks**, not with runs logged (runs aren't stored here).
Guarded by the `Serialization size` check in `TrainingCoreChecks` (fails >300 KB).

## Size drivers & how to shrink

Each workout serializes to ~185 B, dominated by repeated keys + 36-char UUIDs:

```json
{"id":"7C9…UUID","date":765547200,"type":"marathonPace",
 "distanceMeters":16000,"targetPaceSecPerKm":[298.05,316.2],"notes":""}
```

Options, biggest win first:

1. **Store inputs, regenerate weeks (~1 KB).** Weeks are deterministic from
   `(goal, VDOT/fitness, daysPerWeek, startDate)` via the pure generator. Persist
   only inputs + adaptation deltas (eased/rescheduled workouts) + vacation periods;
   rebuild the calendar on load. Best on-disk footprint; most refactor.
2. **gzip the blob (~8–10 KB).** This JSON is highly repetitive (~10× ratio) via the
   Compression framework. Smallest code change; best for the *export file*. **Chosen
   for v1.**
3. **Compact Codable (~45 KB).** Short `CodingKeys` (`id→i`…), omit empty `notes` /
   nil paces, round doubles. Hurts readability; optional later.

## Design (v1)

A versioned envelope, gzip-compressed, written to a `.endurancr` file (UTI:
`public.data`, or JSON if we want it human-openable before compression).

```
PlanBackup {
  schemaVersion: Int          // start at 1; bump on breaking TrainingPlan changes
  appVersion: String          // for diagnostics
  exportedAt: Date
  plan: TrainingPlan          // the Codable plan (goal incl. vacation periods)
}
```

- **Encode:** `JSONEncoder().encode(PlanBackup)` → gzip (Compression) → file.
- **Decode:** gunzip → decode `PlanBackup`; if `schemaVersion` unknown/newer, refuse
  with a clear message; if older, run a migration step (none needed at v1).
- **Import behavior:** replace the single active plan (same as `createPlan`), after a
  confirmation ("This replaces your current plan").
- Put backup codec in **TrainingCore** (pure, unit-testable): `PlanBackup` +
  `PlanBackupCodec.encode/decode`. gzip via `Compression` is Apple-only but available
  on macOS, so it stays testable in `TrainingCoreChecks`.

## UI

- **Export:** button in a new "Data" section (Settings, or the dashboard's planning
  section) → `ShareLink` / `.fileExporter` with the generated file.
- **Import:** `.fileImporter` → decode → confirmation → `coordinator.importPlan(_:)`.

## Coordinator API (to add)

```swift
func exportData() throws -> Data                 // gzipped PlanBackup
func importData(_ data: Data) throws             // decode + replace active plan
```

## Schema versioning policy

- `schemaVersion` starts at **1**.
- Additive fields decode tolerantly (see `Goal.init(from:)` precedent).
- Breaking change → bump version + add a decode-time migration keyed on the old value.

## Test plan (device-independent, in TrainingCoreChecks)

- Round-trip: encode → decode → equal plan (incl. vacation periods).
- gzip export is materially smaller than raw JSON (e.g. < 20 KB for the marathon plan).
- Unknown/newer `schemaVersion` is rejected.
- Corrupt/truncated data throws rather than crashes.

## Out of scope (v1)

- Merging two plans; run-history export (runs live in HealthKit).
- Encryption (file is user-controlled; add later if desired).
