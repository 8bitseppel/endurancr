# TrainingCore

Pure, platform-agnostic training logic for the adaptive running app — no UI, no
HealthKit, no networking. It builds and runs on any machine with a Swift
toolchain, so the training math is testable without Apple hardware.

## What's here

| Area | Type | Responsibility |
| --- | --- | --- |
| VDOT | `VDOTCalculator` | Daniels–Gilbert equations: VDOT from a race, equivalent times, training paces |
| Paces | `PaceZones` | Easy / Marathon / Threshold / Interval / Repetition (sec/km) |
| Planning | `PlanGenerator` (protocol) + `VDOTPlanGenerator` | Back-planned Base → Build → Peak → Taper → Race calendar |
| Adaptation | `AdaptationEngine` | Re-rate VDOT from runs, re-pace future workouts, reschedule missed long runs |
| Models | `Goal`, `FitnessSnapshot`, `TrainingPlan`, `PlannedWorkout`, `CompletedRun` | Value types the app persists (SwiftData) and HealthKit fills |

The methodology sits behind `PlanGenerator`, so Daniels/VDOT can later be swapped
for Hansons/Pfitzinger without touching the app or the adaptation loop.

## Running the checks

XCTest / Swift Testing aren't available with the standalone Command Line Tools,
so the test suite runs as an executable:

```sh
swift run TrainingCoreChecks
```

Under full Xcode, the same assertions can move into a normal XCTest/Swift Testing
target. All 31 checks currently pass, including Daniels VDOT reference values, the
10% volume rule, taper/cutback structure, and the adaptation behaviors.

## Next (needs full Xcode)

This package is consumed by the `App-iOS` and `App-watchOS` targets (HealthKit
capability, live workout recording, SwiftData persistence) — see the project plan.
