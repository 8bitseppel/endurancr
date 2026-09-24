# Feature: Storage usage & pruning past data

**Status:** IMPLEMENTED 2026-09-21 (store-inputs path — no pruning needed).
Built into the "Storage & Data" screen (`App-iOS/Views/DataManagementView.swift`,
reached via the ••• menu → "Storage & backup"):
- **Storage section** shows two honest figures from `PlanCoordinator.storageUsage()`:
  *Plan data* = encoded `PlanInputs` byte count (~342 B), *On-device store* = the
  SwiftData SQLite file(s) on disk (`store` + `-wal` + `-shm`).
- **No "prune past weeks"** — the store-inputs design (below) makes it moot: past
  weeks are never persisted, so there's nothing to delete. The footer states this.
- **Reset all data** — destructive button → `coordinator.deletePlan()` (goal/plan
  removed; HealthKit runs untouched).

Original plan (kept for context):
**Motivation:** show how much on-device space the app uses and let the user delete
old data (e.g. past training weeks) to keep the footprint tiny. Complements
[export-import](export-import.md) and the "keep on-device data as small as possible"
constraint.

## What we control vs. what we don't

- **Our store (SwiftData `StoredPlan`):** the plan blob (~89 KB today for a full
  marathon; ~1 KB if we move to store-inputs + regenerate). This is what we can size
  and prune.
- **HealthKit runs:** owned by Apple's Health app; we neither size nor delete these
  (the user manages them in Health). No personal data lives in our store.

## Scope

1. **Show storage used** — a "Data" screen line: bytes used by the plan store
   (measure the encoded `StoredPlan` payload; optionally the SQLite file size via the
   store URL). Keep it honest and simple.
2. **Prune past weeks** — drop weeks/workouts dated before *today* (or before a
   chosen cutoff). Past workouts are already immutable history; removing them shrinks
   the store without affecting adaptation (which only re-paces the future). Keep a
   summary of pruned volume so the dashboard's "distance done" stays meaningful, or
   recompute completed distance from HealthKit instead of the plan.
3. Optional: "Reset all data" (delete the plan; onboarding rebuilds from HealthKit).

## Notes / dependencies

- If we adopt **store-inputs + regenerate** (export-import doc, option 1), pruning
  becomes trivial: past weeks aren't stored at all; the calendar is generated from
  the start date forward. That likely makes #2 unnecessary and is the preferred path.
- Dashboard's `PlanProgress` currently sums planned-to-date from the plan; if we
  prune past weeks, switch "completed distance / workouts done" to read from
  HealthKit runs so history isn't lost.

## Test plan (device-independent)

- Pruning removes only workouts strictly before the cutoff; future plan unchanged.
- Reported size matches the encoded payload length.
