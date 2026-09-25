import Foundation

/// A snapshot of where the athlete stands in a plan, computed purely from the plan
/// and recorded runs. This is the data a dashboard renders — countdown, volume
/// done vs. planned, adherence, current week, and what's next. No side effects.
public struct PlanProgress: Sendable, Equatable {
    public var asOf: Date
    public var raceDate: Date
    /// Days remaining until race day (0 on/after race day).
    public var daysUntilRace: Int

    public var totalWeeks: Int
    /// 1-based number of the week `asOf` falls in; `nil` before the plan starts.
    public var currentWeekNumber: Int?
    public var currentWeekPhase: TrainingPhase?

    /// Distance actually run (sum of recorded runs within the plan window, up to `asOf`).
    public var completedDistanceMeters: Double
    /// Planned running distance for the runs due so far (see `workoutsScheduledToDate`).
    public var plannedToDateMeters: Double
    /// Planned running distance across the whole plan.
    public var totalPlannedMeters: Double

    /// Running workouts due so far: every one before today, plus today's once it's done.
    public var workoutsScheduledToDate: Int
    /// Of those, how many a recorded run fulfilled.
    public var workoutsCompleted: Int

    public var currentWeekPlannedMeters: Double
    public var currentWeekCompletedMeters: Double

    /// The next running workout on or after `asOf`, if any remain.
    public var nextWorkout: PlannedWorkout?

    public var vdot: Double

    /// The VDOT the goal's target time requires at the goal distance; `nil` when the
    /// athlete hasn't set a target time. Derived from `(race distance, target time)`.
    public var requiredVDOT: Double?
    /// True when current fitness (`vdot`) already meets `requiredVDOT` — the athlete
    /// is "good to go" and the plan holds fitness rather than building it. `false`
    /// when no target time is set.
    public var isReadyForGoal: Bool
    /// How much VDOT still separates the athlete from the target (positive = work to
    /// do, ≤ 0 = already there); `nil` when no target time is set.
    public var vdotToGoal: Double? {
        guard let requiredVDOT else { return nil }
        return requiredVDOT - vdot
    }

    /// Completed vs. planned distance to date, clamped to [0, 1]. 1 when nothing is
    /// scheduled yet (nothing to fall behind on).
    public var adherenceFraction: Double {
        guard plannedToDateMeters > 0 else { return 1 }
        return min(1, max(0, completedDistanceMeters / plannedToDateMeters))
    }

    /// Share of the runs due so far that a recorded run fulfilled, clamped to [0, 1].
    /// 1 when nothing is due yet.
    public var runsDoneFraction: Double {
        guard workoutsScheduledToDate > 0 else { return 1 }
        return min(1, Double(workoutsCompleted) / Double(workoutsScheduledToDate))
    }

    /// Fraction of the plan's total planned distance completed, clamped to [0, 1].
    public var overallCompletionFraction: Double {
        guard totalPlannedMeters > 0 else { return 0 }
        return min(1, max(0, completedDistanceMeters / totalPlannedMeters))
    }

    /// Builds a progress snapshot. `completedRuns` should be the runs HealthKit knows
    /// about; only those within the plan's date span and on/before `asOf` count.
    public static func make(
        plan: TrainingPlan,
        completedRuns: [CompletedRun],
        asOf: Date = .now,
        calendar: Calendar = .current
    ) -> PlanProgress {
        let engine = AdaptationEngine()
        let asOfDay = calendar.startOfDay(for: asOf)
        let workouts = plan.allWorkouts

        let daysUntil = max(0, calendar.dateComponents([.day], from: asOfDay,
            to: calendar.startOfDay(for: plan.goal.raceDate)).day ?? 0)

        // Plan span, for filtering runs to this plan. Week 0 starts on a Monday, but
        // training may begin later that week; runs from the days before the first
        // scheduled run belong to no plan and must not count as progress.
        let firstRunDay = workouts.filter(\.type.isRunning).map { calendar.startOfDay(for: $0.date) }.min()
        let planStart = firstRunDay
            ?? plan.weeks.first.map { calendar.startOfDay(for: $0.startDate) } ?? asOfDay
        let runsInPlan = completedRuns.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= planStart && day <= asOfDay
        }
        let completedDistance = runsInPlan.reduce(0) { $0 + $1.distanceMeters }

        // A run is due once its day has passed. Today's run only counts once it's
        // done, so the morning of a run day doesn't read as a missed session.
        let runningToDate = workouts.filter {
            guard $0.type.isRunning else { return false }
            let day = calendar.startOfDay(for: $0.date)
            return day < asOfDay || (day == asOfDay && engine.isCompleted($0, by: completedRuns, calendar: calendar))
        }
        let plannedToDate = runningToDate.reduce(0) { $0 + $1.distanceMeters }
        let totalPlanned = workouts.filter(\.type.isRunning).reduce(0) { $0 + $1.distanceMeters }
        let completedCount = runningToDate.filter { engine.isCompleted($0, by: completedRuns, calendar: calendar) }.count

        // Locate the current week (the one containing `asOf`).
        let currentWeek = plan.weeks.first { week in
            let start = calendar.startOfDay(for: week.startDate)
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return false }
            return asOfDay >= start && asOfDay < end
        }
        let currentWeekCompleted: Double = currentWeek.map { week in
            let start = calendar.startOfDay(for: week.startDate)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return completedRuns
                .filter { $0.date >= max(start, planStart) && $0.date < end && $0.date <= asOf }
                .reduce(0) { $0 + $1.distanceMeters }
        } ?? 0

        let next = workouts
            .filter { $0.type.isRunning && calendar.startOfDay(for: $0.date) >= asOfDay }
            .min(by: { $0.date < $1.date })

        // Readiness: the VDOT the goal's target time requires, versus current fitness.
        let calculator = VDOTCalculator()
        let requiredVDOT = plan.goal.targetTimeSeconds.map {
            calculator.vdot(distanceMeters: plan.goal.race.meters, timeSeconds: $0)
        }
        // Ready only once the endurance is earned too, not just the pace.
        let isReady = plan.enduranceHoldback == 0 && (requiredVDOT.map { plan.raceVDOT >= $0 } ?? false)

        return PlanProgress(
            asOf: asOf,
            raceDate: plan.goal.raceDate,
            daysUntilRace: daysUntil,
            totalWeeks: plan.weeks.count,
            currentWeekNumber: currentWeek.map { $0.index + 1 },
            currentWeekPhase: currentWeek?.phase,
            completedDistanceMeters: completedDistance,
            plannedToDateMeters: plannedToDate,
            totalPlannedMeters: totalPlanned,
            workoutsScheduledToDate: runningToDate.count,
            workoutsCompleted: completedCount,
            currentWeekPlannedMeters: currentWeek?.plannedVolumeMeters ?? 0,
            currentWeekCompletedMeters: currentWeekCompleted,
            nextWorkout: next,
            vdot: plan.raceVDOT,
            requiredVDOT: requiredVDOT,
            isReadyForGoal: isReady
        )
    }
}
