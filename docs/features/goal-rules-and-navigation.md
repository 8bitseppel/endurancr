# Feature: Dashboard-first navigation, editable goals, weekday rules, methodology tab

**Status:** planned (not implemented)
**Requested:** dashboard as the front page even with no goal; edit goals after
creation; define training rules (e.g. "never run Tuesdays/Thursdays") plus vacation
time-off; recalculate the plan from those rules; and a separate tab explaining the
rules/methodology the app uses.

## 1. Dashboard-first navigation

Today `RootView` shows `OnboardingView` whenever `currentPlan == nil`. Change so the
**tabbed UI is always the front page**; the dashboard (or Today) shows a friendly
empty state with a "Set your goal" button when there's no plan.

- `RootView`: always render `MainTabView`; drop the `currentPlan == nil` branch.
- Empty states: `ProgressDashboardView` / `TodayView` / `CalendarView` already use
  `ContentUnavailableView` — give the dashboard's a primary "Set your goal" button
  that presents the goal editor (sheet).
- Tabs become: **Dashboard** (front/default) · Today · Plan · **How it works** · (goal
  editor reachable from Dashboard/Settings, not a permanent tab).

## 2. Editable goals

Reuse onboarding as an editable form (`GoalEditorView`), pre-filled from the current
goal when one exists.

- Entry points: dashboard "Set your goal" (empty) and an "Edit goal" row (existing).
- Fields: race, race date, target time (optional), days/week, **rest-day weekdays**
  (see §3), vacation periods (link to existing `UnavailabilityView`).
- On save → regenerate the plan (§4). Confirm before replacing an existing plan.

## 3. Weekday training rules

Let the user pin specific weekdays as **never-run** (e.g. Tue/Thu), independent of the
one-off vacation periods (which already exist as `UnavailablePeriod`).

**Model (TrainingCore):** extend `Goal` (additive, tolerant decode like
`unavailablePeriods`):

```swift
/// Weekdays the user won't run (Calendar weekday numbers, 1 = Sun … 7 = Sat).
public var restWeekdays: Set<Int> = []
/// Persisted so the plan can be regenerated/recalculated later.
public var daysPerWeek: Int          // move off the generator arg into the goal
```

Also persist the `FitnessSnapshot` used to build the plan (needed to regenerate — it
is currently passed to `createPlan` and then thrown away). Store it alongside the plan
(e.g. on `StoredPlan`, or fold into the store-inputs model from
[export-import](export-import.md)).

**Generator (`VDOTPlanGenerator`):** honor `restWeekdays` when laying out each week —
place rest on those weekdays first, then distribute easy/quality/long runs across the
remaining allowed days. Keep the long run on a weekend allowed day when possible.

**Validation:** `allowedDaysPerWeek = 7 - restWeekdays.count`. Require
`daysPerWeek <= allowedDaysPerWeek`; surface a clear error otherwise ("You blocked 3
days, so at most 4 running days/week").

## 4. Recalculate training days

"Recalculate" = regenerate the plan from stored inputs (goal + rules + fitness), then
re-apply adaptation from HealthKit runs.

- Add `PlanCoordinator.recalculate()`:
  1. Rebuild weeks via `VDOTPlanGenerator.makePlan(goal:fitness:daysPerWeek:startDate:)`
     honoring `restWeekdays`.
  2. Run the adaptation steps (re-rate VDOT, re-pace, reschedule, ease-for-fatigue)
     as `refreshAdaptation` already does.
  3. `displayPlan` keeps applying vacation blanking at view time (unchanged).
- Past weeks: regenerate from *today* forward so history isn't rewritten (or keep the
  original start and only replace future weeks — decide during impl).
- This is the same regenerate machinery the store-inputs optimization needs, so do
  them together.

## 5. "How it works" methodology tab

A static, scrollable explainer (no data needed) describing the rules the engine uses.
Pull the specifics from `TrainingCore` so the copy matches the code:

- **VDOT / Jack Daniels:** paces derived from a VDOT estimated from a recent effort;
  zones easy > marathon > threshold > interval > repetition (`PaceZones`).
- **Progression:** ~10% weekly volume cap; 4th week is a cutback; two taper weeks;
  long-run distance caps per race (`VDOTPlanGenerator.longRunCap`).
- **Adaptation:** re-rates VDOT from recent strong runs (damped ≤2 pts/pass);
  re-paces only future workouts; reschedules a missed long run onto the next rest day.
- **Fatigue easing:** elevated resting HR or falling aerobic efficiency → the next
  quality session is eased to easy (see fatigue feature).
- **Rules you set:** rest weekdays + vacation periods blank those days.
- One line of honesty: rule-based & deterministic, not medical advice.

## Test plan (device-independent, TrainingCoreChecks)

- Generator honors `restWeekdays` (no running workouts on blocked weekdays).
- Validation rejects `daysPerWeek > 7 - restWeekdays.count`.
- Recalculate preserves race day, week count span, 10%/taper/cutback invariants.
- Goal decodes when `restWeekdays` / `daysPerWeek` absent (old plans).

## Dependencies / ordering

1. Persist `FitnessSnapshot` + `daysPerWeek` (prereq for recalculate) — ideally as the
   store-inputs model from the export-import doc (also shrinks on-device data).
2. Generator `restWeekdays` support + validation.
3. `recalculate()` + `GoalEditorView`.
4. Dashboard-first `RootView` + empty states.
5. "How it works" tab (independent; can be done any time).
