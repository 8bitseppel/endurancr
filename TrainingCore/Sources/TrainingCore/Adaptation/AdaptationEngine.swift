import Foundation

/// Adjusts a plan from recorded runs. Deterministic, rule-based:
///  1. Re-rate VDOT from recent strong runs (damped, so paces don't whipsaw),
///     and earn back held-back marathon endurance from long runs.
///  2. Re-pace all *future* workouts from the updated VDOT.
///  3. Reschedule a missed long run onto the next upcoming rest day.
///  4. Ease the next quality session to easy when fatigue signals fire.
///
/// Past workouts are never rewritten — they're history.
public struct AdaptationEngine: Sendable {
    public init() {}

    private let calculator = VDOTCalculator()

    /// Intensity sessions that should be softened to easy running when the athlete
    /// is showing fatigue. Long runs and easy days are left alone.
    public static let qualityTypes: Set<WorkoutType> = [
        .marathonPace, .threshold, .interval, .repetitionSpeed,
    ]

    // MARK: Fitness re-rating

    /// VDOT implied by a single run (treated as a maximal effort for that distance).
    public func estimatedVDOT(from run: CompletedRun) -> Double {
        guard run.distanceMeters > 0, run.durationSeconds > 0 else { return 0 }
        return calculator.vdot(distanceMeters: run.distanceMeters, timeSeconds: run.durationSeconds)
    }

    /// Nudges the current VDOT toward the best recent effort, damped to at most
    /// `maxIncrease` points per adaptation so a single fast day doesn't overshoot.
    public func reRatedVDOT(
        current: Double,
        completedRuns: [CompletedRun],
        asOf: Date,
        lookbackDays: Int = 21,
        minimumDistanceMeters: Double = 3_000,
        maxIncrease: Double = 2.0,
        calendar: Calendar = .current
    ) -> Double {
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: asOf) ?? asOf
        let recentBest = completedRuns
            .filter { $0.date >= cutoff && $0.date <= asOf && $0.distanceMeters >= minimumDistanceMeters }
            .map { estimatedVDOT(from: $0) }
            .max()

        guard let best = recentBest, best > current else { return current }
        // Move halfway toward the demonstrated fitness, capped.
        let target = current + (best - current) * 0.5
        return min(target, current + maxIncrease)
    }

    // MARK: Endurance credit

    /// Earns back endurance points held back at plan start (`EnduranceAdjustment`)
    /// from the longest run in the last `lookbackDays`. Never holds back more than
    /// at plan start, and never less than zero.
    public func creditingEndurance(
        plan: TrainingPlan,
        completedRuns: [CompletedRun],
        asOf: Date,
        lookbackDays: Int = 56,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        guard plan.enduranceHoldbackBase > 0 else { return plan }
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: asOf) ?? asOf
        let longest = completedRuns
            .filter { $0.date >= cutoff && $0.date <= asOf }
            .map(\.distanceMeters).max() ?? 0
        let credit = EnduranceAdjustment.credit(longestRunMeters: longest, goalMeters: plan.goal.race.meters)
        var updated = plan
        updated.enduranceHoldback = (plan.enduranceHoldbackBase * (1 - credit) * 10).rounded() / 10
        return updated
    }

    // MARK: Re-pacing

    /// Returns the plan with future workouts (date ≥ `asOf`) re-paced from `vdot`.
    public func repaced(
        plan: TrainingPlan,
        withVDOT vdot: Double,
        asOf: Date,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        let zones = calculator.paceZones(forVDOT: vdot, raceVDOT: vdot - plan.enduranceHoldback)
        let asOfDay = calendar.startOfDay(for: asOf)
        var updated = plan
        updated.vdot = vdot
        updated.paceZones = zones
        updated.weeks = plan.weeks.map { week in
            var week = week
            week.workouts = week.workouts.map { workout in
                guard calendar.startOfDay(for: workout.date) >= asOfDay,
                      workout.type != .rest,
                      workout.targetPaceSecPerKm != nil else { return workout }
                var w = workout
                let center = paceCenter(for: workout.type, zones: zones, plan: plan, vdot: vdot)
                let tolerance = workout.type == .raceDay ? 0.015 : 0.03
                w.targetPaceSecPerKm = (center * (1 - tolerance))...(center * (1 + tolerance))
                return w
            }
            return week
        }
        return updated
    }

    private func paceCenter(for type: WorkoutType, zones: PaceZones, plan: TrainingPlan, vdot: Double) -> Double {
        switch type {
        case .easy, .longRun, .rest: return zones.easySecPerKm
        case .marathonPace: return zones.marathonSecPerKm
        case .threshold: return zones.thresholdSecPerKm
        case .interval: return zones.intervalSecPerKm
        case .repetitionSpeed: return zones.repetitionSecPerKm
        case .raceDay:
            let goalKm = plan.goal.race.meters / 1_000
            let seconds = plan.goal.targetTimeSeconds
                ?? calculator.predictedTimeSeconds(distanceMeters: plan.goal.race.meters, vdot: vdot - plan.enduranceHoldback)
            return seconds / goalKm
        }
    }

    // MARK: Missed-workout rescheduling

    /// Was this planned workout fulfilled by a recorded run? True if a run is
    /// explicitly linked, or one on the same day covered ≥ 80% of the distance.
    public func isCompleted(_ workout: PlannedWorkout, by runs: [CompletedRun], calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: workout.date)
        return runs.contains { run in
            if run.plannedWorkoutID == workout.id { return true }
            return calendar.startOfDay(for: run.date) == day
                && run.distanceMeters >= 0.8 * workout.distanceMeters
        }
    }

    /// If a past long run was missed, move it onto the next upcoming rest day so the
    /// key endurance session isn't simply lost. Reschedules at most one.
    public func rescheduleMissedLongRun(
        plan: TrainingPlan,
        completedRuns: [CompletedRun],
        asOf: Date,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        let asOfDay = calendar.startOfDay(for: asOf)

        let missedLong = plan.allWorkouts
            .filter { $0.type == .longRun
                && calendar.startOfDay(for: $0.date) < asOfDay
                && !isCompleted($0, by: completedRuns, calendar: calendar) }
            .max(by: { $0.date < $1.date })

        guard let missed = missedLong else { return plan }

        var updated = plan
        var rescheduled = false
        outer: for weekIndex in updated.weeks.indices {
            for workoutIndex in updated.weeks[weekIndex].workouts.indices {
                let w = updated.weeks[weekIndex].workouts[workoutIndex]
                guard w.type == .rest, calendar.startOfDay(for: w.date) >= asOfDay else { continue }
                updated.weeks[weekIndex].workouts[workoutIndex].type = .longRun
                updated.weeks[weekIndex].workouts[workoutIndex].distanceMeters = missed.distanceMeters
                updated.weeks[weekIndex].workouts[workoutIndex].targetPaceSecPerKm = missed.targetPaceSecPerKm
                updated.weeks[weekIndex].workouts[workoutIndex].notes = "Rescheduled long run (missed \(shortDate(missed.date, calendar: calendar)))"
                rescheduled = true
                break outer
            }
        }
        return rescheduled ? updated : plan
    }

    // MARK: Fatigue-based easing

    /// Evaluates recovery signals (resting HR, aerobic efficiency) as of `asOf`.
    public func assessFatigue(
        restingHeartRates: [RestingHeartRateSample],
        completedRuns: [CompletedRun],
        asOf: Date,
        analyzer: FatigueAnalyzer = FatigueAnalyzer(),
        calendar: Calendar = .current
    ) -> FatigueAssessment {
        analyzer.assess(
            restingHeartRates: restingHeartRates,
            completedRuns: completedRuns,
            asOf: asOf,
            calendar: calendar
        )
    }

    /// If `assessment` shows fatigue, softens the *soonest upcoming* quality session
    /// (date ≥ `asOf`) to an easy run — same distance, easy pace — so the athlete
    /// recovers instead of pushing intensity while run down. Eases at most one
    /// session per pass; a plan with no fatigue or no upcoming quality day is returned
    /// unchanged.
    public func easedForFatigue(
        plan: TrainingPlan,
        assessment: FatigueAssessment,
        asOf: Date,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        guard assessment.isFatigued else { return plan }
        let asOfDay = calendar.startOfDay(for: asOf)

        // Locate the earliest upcoming quality session by date.
        var target: (week: Int, workout: Int, date: Date)?
        for w in plan.weeks.indices {
            for i in plan.weeks[w].workouts.indices {
                let workout = plan.weeks[w].workouts[i]
                guard Self.qualityTypes.contains(workout.type),
                      calendar.startOfDay(for: workout.date) >= asOfDay else { continue }
                if target == nil || workout.date < target!.date {
                    target = (w, i, workout.date)
                }
            }
        }

        guard let t = target else { return plan }
        var updated = plan
        let easyCenter = plan.paceZones.easySecPerKm
        updated.weeks[t.week].workouts[t.workout].type = .easy
        updated.weeks[t.week].workouts[t.workout].targetPaceSecPerKm =
            (easyCenter * 0.97)...(easyCenter * 1.03)
        updated.weeks[t.week].workouts[t.workout].structure = nil
        updated.weeks[t.week].workouts[t.workout].notes =
            "Eased to easy: fatigue detected (\(assessment.summary))"
        return updated
    }

    // MARK: Unavailability (vacation / travel / illness)

    /// Blanks every *future* running workout (date ≥ `asOf`) that falls inside any
    /// unavailable period, turning it into a rest day annotated with the reason.
    /// Past days are history and never touched; rest days are left as-is.
    public func applyingUnavailability(
        plan: TrainingPlan,
        periods: [UnavailablePeriod],
        asOf: Date,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        guard !periods.isEmpty else { return plan }
        let asOfDay = calendar.startOfDay(for: asOf)
        var updated = plan
        for w in updated.weeks.indices {
            for i in updated.weeks[w].workouts.indices {
                let workout = updated.weeks[w].workouts[i]
                guard calendar.startOfDay(for: workout.date) >= asOfDay,
                      workout.type != .rest,
                      let period = periods.first(where: { $0.contains(workout.date, calendar: calendar) })
                else { continue }
                updated.weeks[w].workouts[i].type = .rest
                updated.weeks[w].workouts[i].distanceMeters = 0
                updated.weeks[w].workouts[i].targetPaceSecPerKm = nil
                updated.weeks[w].workouts[i].structure = nil
                updated.weeks[w].workouts[i].notes = period.reason
            }
        }
        return updated
    }

    // MARK: Weekly volume redistribution

    /// Keeps the *current* week on its planned volume by absorbing any gap into the
    /// remaining EASY runs. Long runs and quality sessions are protected — their
    /// prescribed distance is never changed — so the training stimulus survives; only
    /// easy days flex. Each easy run grows by at most `maxEasyGrowth`× its original so
    /// no recovery day balloons, and never beyond the week's long run, so the long
    /// run stays the longest run of the week. An easy run the week no longer needs (volume
    /// already banked) collapses to a rest day.
    ///
    /// Example: a 42 km week with a Saturday 17 km long run. The athlete can only run
    /// 5 km, records it, and this redistributes the 12 km shortfall onto the week's
    /// remaining easy runs (capped) while the long run and any threshold/interval day
    /// keep their distance.
    public func redistributedWithinWeek(
        plan: TrainingPlan,
        completedRuns: [CompletedRun],
        asOf: Date,
        maxEasyGrowth: Double = 1.5,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        let asOfDay = calendar.startOfDay(for: asOf)
        guard let wi = plan.weeks.firstIndex(where: { wk in
            let start = calendar.startOfDay(for: wk.startDate)
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return false }
            return asOfDay >= start && asOfDay < end
        }) else { return plan }

        var week = plan.weeks[wi]
        let weeklyTarget = week.plannedVolumeMeters
        guard weeklyTarget > 0 else { return plan }

        let start = calendar.startOfDay(for: week.startDate)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        // Runs before the plan's first run (e.g. the effort that set the fitness)
        // don't count toward the first week.
        let planStart = plan.allWorkouts.filter(\.type.isRunning).map { calendar.startOfDay(for: $0.date) }.min() ?? start
        let completedThisWeek = completedRuns
            .filter { $0.date >= max(start, planStart) && $0.date < end && $0.date <= asOf }
            .reduce(0.0) { $0 + $1.distanceMeters }

        // A planned day is still "to do" only if it's today or later and no run was
        // recorded on it yet — so a partially-run long run today isn't double-counted.
        func alreadyRun(_ workout: PlannedWorkout) -> Bool {
            let day = calendar.startOfDay(for: workout.date)
            return completedRuns.contains { calendar.startOfDay(for: $0.date) == day }
        }
        let remainingIdx = week.workouts.indices.filter {
            let w = week.workouts[$0]
            return w.type.isRunning
                && calendar.startOfDay(for: w.date) >= asOfDay
                && !alreadyRun(w)
        }
        let easyIdx = remainingIdx.filter { week.workouts[$0].type == .easy }
        guard !easyIdx.isEmpty else { return plan }

        // Protected (long + quality) remaining runs keep their prescribed distance.
        let protectedRemaining = remainingIdx
            .filter { week.workouts[$0].type != .easy }
            .reduce(0.0) { $0 + week.workouts[$1].distanceMeters }

        // What the easy runs should collectively cover to land the week on target.
        let easyBudget = max(0, weeklyTarget - completedThisWeek - protectedRemaining)

        // Water-fill the budget across the easy runs, proportional to their original
        // size, capping each at maxEasyGrowth× so no single recovery day overloads,
        // and never past the week's long run: an easy run longer than the long run
        // turns the week upside down. Leftover shortfall is simply not made up.
        let longRun = week.workouts.filter { $0.type == .longRun }.map(\.distanceMeters).max()
        let caps = Dictionary(uniqueKeysWithValues: easyIdx.map { i in
            let original = week.workouts[i].distanceMeters
            var cap = original * maxEasyGrowth
            if let longRun { cap = min(cap, max(original, longRun)) }
            return (i, cap)
        })
        var alloc = Dictionary(uniqueKeysWithValues: easyIdx.map { ($0, 0.0) })
        var active = Set(easyIdx)
        var budget = easyBudget
        var iterations = 0
        while budget > 1, !active.isEmpty, iterations < 20 {
            iterations += 1
            let weightSum = active.reduce(0.0) { $0 + week.workouts[$1].distanceMeters }
            guard weightSum > 0 else { break }
            var used = 0.0
            for i in active {
                let want = budget * (week.workouts[i].distanceMeters / weightSum)
                let room = (caps[i] ?? 0) - (alloc[i] ?? 0)
                let give = min(want, room)
                alloc[i, default: 0] += give
                used += give
            }
            budget -= used
            active = active.filter { (alloc[$0] ?? 0) < (caps[$0] ?? 0) - 0.5 }
        }

        for i in easyIdx {
            let original = week.workouts[i].distanceMeters
            let newDistance = (alloc[i] ?? 0).rounded()
            if newDistance < 1_000 {
                // Volume already met: the week no longer needs this easy run.
                week.workouts[i].type = .rest
                week.workouts[i].distanceMeters = 0
                week.workouts[i].targetPaceSecPerKm = nil
                week.workouts[i].structure = nil
                week.workouts[i].notes = "Rest, the week's distance is already done"
            } else if abs(newDistance - original) >= 100 {
                week.workouts[i].distanceMeters = newDistance
                week.workouts[i].notes = "Adjusted to keep the week on target"
            }
        }

        var updated = plan
        updated.weeks[wi] = week
        return updated
    }

    // MARK: Convenience

    /// Full adaptation pass: re-rate → re-pace → reschedule → ease-for-fatigue →
    /// apply the goal's unavailable periods → redistribute the current week's volume.
    ///
    /// `restingHeartRates` defaults to empty; with no resting-HR history and no
    /// heart-rate-carrying runs, the fatigue step is a no-op, so existing callers
    /// keep their prior behavior.
    public func adapt(
        plan: TrainingPlan,
        completedRuns: [CompletedRun],
        asOf: Date,
        restingHeartRates: [RestingHeartRateSample] = [],
        analyzer: FatigueAnalyzer = FatigueAnalyzer(),
        calendar: Calendar = .current
    ) -> TrainingPlan {
        let newVDOT = reRatedVDOT(current: plan.vdot, completedRuns: completedRuns, asOf: asOf, calendar: calendar)
        let credited = creditingEndurance(plan: plan, completedRuns: completedRuns, asOf: asOf, calendar: calendar)
        let repacedPlan = repaced(plan: credited, withVDOT: newVDOT, asOf: asOf, calendar: calendar)
        let rescheduled = rescheduleMissedLongRun(plan: repacedPlan, completedRuns: completedRuns, asOf: asOf, calendar: calendar)
        let assessment = assessFatigue(
            restingHeartRates: restingHeartRates,
            completedRuns: completedRuns,
            asOf: asOf,
            analyzer: analyzer,
            calendar: calendar
        )
        let eased = easedForFatigue(plan: rescheduled, assessment: assessment, asOf: asOf, calendar: calendar)
        let available = applyingUnavailability(plan: eased, periods: eased.effectiveUnavailablePeriods(calendar: calendar), asOf: asOf, calendar: calendar)
        // Last: rebalance the current week's easy runs so completed + remaining lands
        // on the week's target, after any rescheduling/easing/unavailability reshaped it.
        return redistributedWithinWeek(plan: available, completedRuns: completedRuns, asOf: asOf, calendar: calendar)
    }

    private func shortDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }
}
