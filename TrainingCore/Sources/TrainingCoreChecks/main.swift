import Foundation
import TrainingCore

let h = CheckHarness()
let cal = Fixtures.utcCalendar
func date(_ y: Int, _ m: Int, _ d: Int) -> Date { Fixtures.date(y, m, d) }
func marathonPlan(daysPerWeek: Int = 5) throws -> TrainingPlan { try Fixtures.marathonPlan(daysPerWeek: daysPerWeek) }

// MARK: VDOT calculator

h.suite("VDOT calculator") {
    let calc = VDOTCalculator()

    let vdot = calc.vdot(distanceMeters: 5_000, timeSeconds: 19 * 60 + 57)
    h.check(vdot > 49 && vdot < 51, "5K in 19:57 → VDOT ≈ 50 (got \(String(format: "%.2f", vdot)))")

    let time = Double(19 * 60 + 57)
    let predicted = calc.predictedTimeSeconds(distanceMeters: 5_000, vdot: calc.vdot(distanceMeters: 5_000, timeSeconds: time))
    h.approx(predicted, time, tolerance: 1.0, "predicted time round-trips")

    let tenK = calc.equivalentTimeSeconds(fromDistanceMeters: 5_000, timeSeconds: time, toDistanceMeters: 10_000)
    let ref = Double(41 * 60 + 21)
    h.check(abs(tenK - ref) / ref < 0.03, "equivalent 10K ≈ 41:21 (got \(Int(tenK))s)")

    let z = calc.paceZones(forVDOT: 50)
    h.check(z.easySecPerKm > z.marathonSecPerKm, "easy slower than marathon")
    h.check(z.marathonSecPerKm > z.thresholdSecPerKm, "marathon slower than threshold")
    h.check(z.thresholdSecPerKm > z.intervalSecPerKm, "threshold slower than interval")
    h.check(z.intervalSecPerKm > z.repetitionSecPerKm, "interval slower than repetition")
    h.check(z.easySecPerKm > 270 && z.easySecPerKm < 345, "easy pace in 4:30–5:45/km band (got \(Int(z.easySecPerKm))s/km)")

    let slow = calc.paceZones(forVDOT: 45)
    let fast = calc.paceZones(forVDOT: 55)
    h.check(fast.easySecPerKm < slow.easySecPerKm, "higher VDOT → faster easy pace")
    h.check(fast.thresholdSecPerKm < slow.thresholdSecPerKm, "higher VDOT → faster threshold pace")
}

// MARK: Plan generator

h.suite("VDOT plan generator") {
    let plan = try marathonPlan()

    let last = try require(plan.weeksToRace.last?.workouts.last, "final workout")
    h.check(last.type == .raceDay, "plan ends on race day")
    h.check(last.distanceMeters == RaceDistance.marathon.meters, "race-day distance is the marathon distance")
    h.check(cal.isDate(last.date, inSameDayAs: date(2027, 4, 25)), "race day is 2027-04-25")
    h.check(plan.weeksToRace.last?.phase == .raceWeek, "the last week before recovery is race week")
    h.check(plan.weeks.last?.phase == .recovery, "recovery weeks follow the race")

    // Weeks are anchored to Monday (ISO Kalenderwoche): the count spans the Monday of
    // the start week through the Monday of the race week, inclusive.
    let firstMonday = VDOTPlanGenerator.startOfWeek(date(2026, 1, 1), calendar: cal)
    let raceMonday = VDOTPlanGenerator.startOfWeek(date(2027, 4, 25), calendar: cal)
    let expectedWeeks = cal.dateComponents([.day], from: firstMonday, to: raceMonday).day! / 7 + 1
    h.check(plan.weeksToRace.count == expectedWeeks, "week count matches Monday-anchored span (\(plan.weeks.count) weeks)")
    h.check(plan.weeks.allSatisfy { cal.component(.weekday, from: $0.startDate) == 2 }, "every week starts on a Monday")

    let baseWeek = try require(plan.weeks.first { $0.phase == .base && $0.index > 0 }, "a base week")
    h.check(baseWeek.workouts.filter { $0.type.isRunning }.count == 5, "5 running days per week")
    h.check(baseWeek.workouts.filter { $0.type == .rest }.count == 2, "2 rest days per week")

    // The 10% ramp rule applies to full training weeks. Week 0 can be a partial
    // starting week (training begins mid-week) with a prorated, smaller volume, so
    // it is excluded — a partial week is fewer days, not a real load increase.
    var maxSoFar = 0.0
    var tenPercentOK = true
    for week in plan.weeks where week.phase != .raceWeek && week.index > 0 {
        if maxSoFar > 0 && week.plannedVolumeMeters > maxSoFar * 1.10 + 1 { tenPercentOK = false }
        maxSoFar = max(maxSoFar, week.plannedVolumeMeters)
    }
    h.check(tenPercentOK, "every week honors the 10% rule vs max-so-far")

    let peak = plan.weeks.filter { $0.phase != .raceWeek }.map(\.plannedVolumeMeters).max()!
    let taper = plan.weeks.filter { $0.phase == .taper }
    h.check(taper.count == 2, "two taper weeks")
    h.check(taper.allSatisfy { $0.plannedVolumeMeters < peak }, "taper weeks lighter than peak")

    // Cutbacks count back from the last progression week, so the peak long run
    // 3 weeks out sits in a full week with a lighter one before it.
    let progression = plan.weeks.filter { [.base, .build, .peak].contains($0.phase) }
    let lastBuild = progression.count - 1
    h.check(progression[lastBuild - 1].plannedVolumeMeters < progression[lastBuild].plannedVolumeMeters, "the week before the last build week is a cutback")
    h.check(progression[lastBuild - 5].plannedVolumeMeters < progression[lastBuild - 6].plannedVolumeMeters, "and every 4th week before that")

    let longCapOK = plan.allWorkouts.filter { $0.type == .longRun }
        .allSatisfy { $0.distanceMeters <= VDOTPlanGenerator.longRunCap(for: .marathon) + 1 }
    h.check(longCapOK, "long runs never exceed the marathon cap")

    // Regression: with few running days the long run must still be the week's
    // single longest run — no easy day may be longer than that week's long run.
    // (A 10K plan at 3 days/week previously produced a 13 km "easy" > 10 km "long".)
    let fewDayPlan = try! VDOTPlanGenerator().makePlan(
        goal: Goal(race: .tenK, raceDate: date(2026, 6, 1), daysPerWeek: 3),
        fitness: FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 3_000, date: date(2026, 1, 1)),
        startDate: date(2026, 1, 1), calendar: cal
    )
    let longestIsLongRun = fewDayPlan.weeks
        .filter { $0.phase != .raceWeek }
        .allSatisfy { week in
            guard let long = week.workouts.first(where: { $0.type == .longRun })?.distanceMeters else { return true }
            let othersMax = week.workouts.filter { $0.type != .longRun }.map(\.distanceMeters).max() ?? 0
            return long + 1 >= othersMax
        }
    h.check(longestIsLongRun, "long run is the week's longest run even at 3 days/week")

    // Structured quality sessions: interval/threshold days carry a breakdown whose
    // parts sum to the workout's distance (weekly volume must be preserved), with a
    // sane rep count and a warm-up + cool-down present.
    let qualityWorkouts = plan.allWorkouts.filter { $0.type == .interval || $0.type == .threshold }
    h.check(!qualityWorkouts.isEmpty, "plan produces at least one structured quality session")
    let structuresValid = qualityWorkouts.allSatisfy { w in
        guard let s = w.structure else { return false }
        let sumsToDistance = abs(s.totalMeters - w.distanceMeters) < 1
        let saneReps = s.reps >= 1 && s.reps <= 8
        let hasWarmCool = s.warmupMeters > 0 && s.cooldownMeters > 0
        return sumsToDistance && saneReps && hasWarmCool
    }
    h.check(structuresValid, "structured sessions sum to their distance with sane reps and warm-up/cool-down")
    // Intervals repeat; a tempo is one continuous block.
    let intervalsRepeat = plan.allWorkouts.filter { $0.type == .interval }.allSatisfy { ($0.structure?.reps ?? 0) >= 3 }
    h.check(intervalsRepeat, "interval sessions repeat at least 3 work bouts")
    let tempoContinuous = plan.allWorkouts.filter { $0.type == .threshold }.allSatisfy { $0.structure?.reps == 1 }
    h.check(tempoContinuous, "threshold sessions are one continuous tempo block")

    var rejected = false
    do {
        _ = try VDOTPlanGenerator().makePlan(
            goal: Goal(race: .fiveK, raceDate: date(2026, 1, 5), daysPerWeek: 4),
            fitness: FitnessSnapshot(distanceMeters: 5_000, timeSeconds: 1_500, date: date(2026, 1, 1)),
            startDate: date(2026, 1, 1), calendar: cal
        )
    } catch { rejected = true }
    h.check(rejected, "rejects a race that is too soon")
}

// MARK: Monday-anchored weeks

h.suite("Monday-anchored weeks") {
    let gen = VDOTPlanGenerator()
    let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 45 * 60, date: date(2026, 1, 1))
    let startWed = date(2026, 1, 7)  // a Wednesday
    let plan = try gen.makePlan(
        goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 5),
        fitness: fitness, startDate: startWed, calendar: cal
    )

    // Week 0 begins on the Monday of the week the start date falls in, and every
    // week runs Monday–Sunday (the ISO Kalenderwoche), not a 7-day block off the start.
    let week0 = plan.weeks[0]
    h.check(cal.component(.weekday, from: week0.startDate) == 2, "week 0 starts on a Monday")
    h.check(cal.isDate(week0.startDate, inSameDayAs: date(2026, 1, 5)), "week 0 is the Monday of the start week")
    h.check(plan.weeks.allSatisfy { cal.component(.weekday, from: $0.startDate) == 2 }, "all weeks start on Monday")

    // Days before the chosen start day carry no session (blank rest, not cross-train).
    let preStart = week0.workouts.filter { cal.startOfDay(for: $0.date) < cal.startOfDay(for: startWed) }
    h.check(preStart.count == 2, "the two days before a Wednesday start are present in week 0")
    h.check(preStart.allSatisfy { $0.type == .rest && $0.notes.isEmpty }, "pre-start days are blank rest days")

    // The first running workout is on or after the athlete's start day.
    let firstRun = try require(plan.allWorkouts.first { $0.type.isRunning }, "a first running workout")
    h.check(cal.startOfDay(for: firstRun.date) >= cal.startOfDay(for: startWed), "training starts on/after the start day")

    // Progress: the day before a mid-week start still resolves the current week (the
    // calendar week the start falls in), so "this week" isn't a phantom "0 of 0 km".
    let dayBefore = cal.date(byAdding: .day, value: -1, to: startWed)!  // Tuesday, same Mon–Sun week
    let progress = PlanProgress.make(plan: plan, completedRuns: [], asOf: dayBefore, calendar: cal)
    h.check(progress.currentWeekNumber == 1, "current week resolves the day before a mid-week start")
    h.check(progress.currentWeekPlannedMeters > 0, "current week shows planned volume, not 0 of 0")
}

// MARK: Rest days between runs

h.suite("Rest days between runs") {
    let gen = VDOTPlanGenerator()
    let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 45 * 60, date: date(2026, 1, 1))
    func firstWeekRunDays(start: Date, daysPerWeek: Int) throws -> [Int] {
        let plan = try gen.makePlan(
            goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: daysPerWeek),
            fitness: fitness, startDate: start, calendar: cal
        )
        return plan.weeks[0].workouts.filter(\.type.isRunning).map { cal.component(.weekday, from: $0.date) }
    }
    func backToBack(_ weekdays: [Int]) -> Bool {
        // Weekday numbers 2 (Mon) … 7 (Sat), 1 (Sun); map to Mon=0 … Sun=6.
        let days = weekdays.map { ($0 + 5) % 7 }.sorted()
        return zip(days, days.dropFirst()).contains { $1 - $0 == 1 }
    }

    // Start dates Monday 2026-01-05 through Sunday 2026-01-11, 3 to 6 runs a week.
    for offset in 1...6 {
        let start = date(2026, 1, 5 + offset)
        for dpw in 3...6 {
            let days = try firstWeekRunDays(start: start, daysPerWeek: dpw)
            h.check(!days.isEmpty && !backToBack(days),
                    "start \(cal.weekdaySymbols[cal.component(.weekday, from: start) - 1]), \(dpw)/week: no back-to-back runs in the first week (\(days))")
        }
    }

    // A Wednesday start with 3 a week keeps all three runs, spaced out.
    let wed = try firstWeekRunDays(start: date(2026, 1, 7), daysPerWeek: 3)
    h.check(wed == [4, 6, 1], "Wednesday start, 3/week → Wed, Fri, Sun (got \(wed))")
    // A Friday start can't fit three runs without stacking them: it drops one.
    let fri = try firstWeekRunDays(start: date(2026, 1, 9), daysPerWeek: 3)
    h.check(fri == [6, 1], "Friday start, 3/week → Fri and Sun, not Fri, Sat, Sun (got \(fri))")

    // Full weeks repeat, so Sunday's long run runs into next Monday. Count that
    // pair too: 3 a week never stacks runs, 4 a week stacks at most one pair, and
    // the day after the long run is a rest day whenever a week has one to spare.
    for dpw in 3...6 {
        let plan = try gen.makePlan(
            goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: dpw),
            fitness: fitness, startDate: date(2026, 1, 7), calendar: cal
        )
        let full = plan.weeks.dropFirst().filter { ![.raceWeek, .taper, .recovery].contains($0.phase) }
        let layouts = full.map { Set($0.workouts.filter(\.type.isRunning).map { (cal.component(.weekday, from: $0.date) + 5) % 7 }) }
        let pairs = layouts.map { days in days.filter { days.contains(($0 + 1) % 7) }.count }
        h.check(pairs.allSatisfy { $0 <= max(0, dpw - (7 - dpw)) },
                "\(dpw)/week: fewest back-to-back runs, Sunday to Monday included (got \(pairs.max() ?? 0))")
        h.check(layouts.allSatisfy { !$0.contains(0) }, "\(dpw)/week: the Monday after the Sunday long run is a rest day")
        let qualityNextToLong = full.flatMap(\.workouts).contains {
            ($0.type == .threshold || $0.type == .interval) && [1, 2].contains(cal.component(.weekday, from: $0.date))
        }
        h.check(!qualityNextToLong, "\(dpw)/week: no threshold or intervals right before or after the long run")
    }
}

// MARK: Day swaps

h.suite("Day swaps") {
    let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 45 * 60, date: date(2026, 1, 1))
    let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 3)
    let inputs = PlanInputs(goal: goal, fitness: fitness, startDate: date(2026, 1, 12))  // a Monday
    let base = try inputs.makePlan(calendar: cal)
    let week = base.weeks[1].workouts
    let run = try require(week.first { $0.type == .easy }, "an easy run")
    let rest = try require(week.first { $0.type == .rest && $0.date > run.date }, "a later rest day")
    let long = try require(week.first { $0.type == .longRun }, "the long run")

    // Run ↔ rest: the run moves to the rest day and the rest takes its place.
    var moved = inputs
    moved.daySwaps = [DaySwap(run.date, rest.date)]
    let swapped = try moved.makePlan(calendar: cal)
    let atRest = try require(swapped.allWorkouts.first { cal.isDate($0.date, inSameDayAs: rest.date) }, "rest day slot")
    let atRun = try require(swapped.allWorkouts.first { cal.isDate($0.date, inSameDayAs: run.date) }, "run day slot")
    h.check(atRest.type == .easy && atRest.id == run.id && atRest.distanceMeters == run.distanceMeters, "the run moves onto the rest day, keeping its id")
    h.check(atRun.type == .rest, "the rest day takes the run's old day")
    h.check(swapped.weeks[1].plannedVolumeMeters == base.weeks[1].plannedVolumeMeters, "a swap within a week keeps its volume")

    // Run ↔ run: the easy run and the long run trade days.
    moved.daySwaps = [DaySwap(run.date, long.date)]
    let runs = try moved.makePlan(calendar: cal)
    h.check(runs.allWorkouts.first { cal.isDate($0.date, inSameDayAs: run.date) }?.type == .longRun
            && runs.allWorkouts.first { cal.isDate($0.date, inSameDayAs: long.date) }?.type == .easy,
            "two runs trade days")

    // Swapping back restores the original plan.
    moved.daySwaps = [DaySwap(run.date, rest.date), DaySwap(rest.date, run.date)]
    let back = try moved.makePlan(calendar: cal)
    h.check(back.weeks[1].workouts.map(\.type) == base.weeks[1].workouts.map(\.type), "swapping twice puts the days back")

    // Race day never moves.
    let race = try require(base.allWorkouts.last, "race day")
    moved.daySwaps = [DaySwap(race.date, cal.date(byAdding: .day, value: -1, to: race.date)!)]
    h.check(try moved.makePlan(calendar: cal).weeksToRace.last?.workouts.last?.type == .raceDay, "race day can't be swapped")

    // Swaps survive encoding, and older data without swaps still decodes.
    moved.daySwaps = [DaySwap(run.date, rest.date)]
    let decoded = try JSONDecoder().decode(PlanInputs.self, from: JSONEncoder().encode(moved))
    h.check(decoded == moved, "swaps round-trip through JSON")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(inputs)) as! [String: Any]
    legacy.removeValue(forKey: "daySwaps")
    let old = try JSONDecoder().decode(PlanInputs.self, from: JSONSerialization.data(withJSONObject: legacy))
    h.check(old.daySwaps.isEmpty, "inputs without swaps decode with none")
}

// MARK: Progress counts

h.suite("Progress counts") {
    let gen = VDOTPlanGenerator()
    let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 45 * 60, date: date(2026, 1, 1))
    let plan = try gen.makePlan(
        goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 3),
        fitness: fitness, startDate: date(2026, 1, 7), calendar: cal  // Wednesday
    )
    // Wed, Fri, Sun. A run on Monday, before the plan starts, isn't progress.
    let wedRun = try require(plan.weeks[0].workouts.first { $0.type.isRunning }, "Wednesday run")
    let beforeStart = CompletedRun(date: date(2026, 1, 5), distanceMeters: 8_000, durationSeconds: 2_700)
    let onWed = CompletedRun(date: wedRun.date, distanceMeters: wedRun.distanceMeters, durationSeconds: 2_400, plannedWorkoutID: wedRun.id)

    // Friday morning, Friday's run not done yet: only Wednesday is due.
    let friday = date(2026, 1, 9)
    let p = PlanProgress.make(plan: plan, completedRuns: [beforeStart, onWed], asOf: friday, calendar: cal)
    h.check(p.workoutsScheduledToDate == 1 && p.workoutsCompleted == 1, "today's open run isn't due yet (\(p.workoutsCompleted) of \(p.workoutsScheduledToDate))")
    h.approx(p.runsDoneFraction, 1, tolerance: 0.0001, "1 of 1 runs done → 100%")
    h.approx(p.completedDistanceMeters, wedRun.distanceMeters, tolerance: 0.5, "a run before the plan starts isn't counted")
    h.approx(p.plannedToDateMeters, wedRun.distanceMeters, tolerance: 0.5, "planned to date is only the due run")
    h.approx(p.currentWeekCompletedMeters, wedRun.distanceMeters, tolerance: 0.5, "this week ignores the pre-start run too")

    // Once Friday's run is done, it's due and counted.
    let friRun = try require(plan.weeks[0].workouts.filter(\.type.isRunning).dropFirst().first, "Friday run")
    let onFri = CompletedRun(date: friRun.date, distanceMeters: friRun.distanceMeters, durationSeconds: 2_400, plannedWorkoutID: friRun.id)
    let p2 = PlanProgress.make(plan: plan, completedRuns: [onWed, onFri], asOf: friday, calendar: cal)
    h.check(p2.workoutsScheduledToDate == 2 && p2.workoutsCompleted == 2, "today's run counts once it's done")

    // Saturday with Friday skipped: 1 of 2.
    let p3 = PlanProgress.make(plan: plan, completedRuns: [onWed], asOf: date(2026, 1, 10), calendar: cal)
    h.approx(p3.runsDoneFraction, 0.5, tolerance: 0.0001, "missed Friday → 1 of 2 runs done")
}

// MARK: Adaptation engine

h.suite("Adaptation engine") {
    let engine = AdaptationEngine()

    let fastRun = CompletedRun(date: date(2026, 2, 1), distanceMeters: 5_000, durationSeconds: 20 * 60)
    let up = engine.reRatedVDOT(current: 45, completedRuns: [fastRun], asOf: date(2026, 2, 2), calendar: cal)
    h.check(up > 45 && up <= 47.0001, "strong run nudges VDOT up but is damped (got \(String(format: "%.2f", up)))")

    let slowRun = CompletedRun(date: date(2026, 2, 1), distanceMeters: 5_000, durationSeconds: 35 * 60)
    let same = engine.reRatedVDOT(current: 50, completedRuns: [slowRun], asOf: date(2026, 2, 2), calendar: cal)
    h.check(same == 50, "slow run does not lower VDOT")

    let plan = try marathonPlan()
    let asOf = date(2026, 3, 1)
    let asOfDay = cal.startOfDay(for: asOf)
    let futureEasy = try require(plan.allWorkouts.first { $0.type == .easy && cal.startOfDay(for: $0.date) >= asOfDay }, "future easy run")
    let pastEasy = try require(plan.allWorkouts.first { $0.type == .easy && cal.startOfDay(for: $0.date) < asOfDay }, "past easy run")

    let repaced = engine.repaced(plan: plan, withVDOT: plan.vdot + 5, asOf: asOf, calendar: cal)
    let futureAfter = try require(repaced.allWorkouts.first { $0.id == futureEasy.id }, "future easy after")
    let pastAfter = try require(repaced.allWorkouts.first { $0.id == pastEasy.id }, "past easy after")
    h.check(futureAfter.targetPaceSecPerKm!.upperBound < futureEasy.targetPaceSecPerKm!.upperBound, "future workouts re-paced faster")
    h.check(pastAfter.targetPaceSecPerKm == pastEasy.targetPaceSecPerKm, "past workouts left untouched")

    let rescheduled = engine.rescheduleMissedLongRun(plan: plan, completedRuns: [], asOf: date(2026, 2, 1), calendar: cal)
        .allWorkouts.filter { $0.notes.hasPrefix("Rescheduled long run") }
    h.check(rescheduled.count == 1, "exactly one missed long run rescheduled")
    if let moved = rescheduled.first {
        h.check(moved.type == .longRun && cal.startOfDay(for: moved.date) >= cal.startOfDay(for: date(2026, 2, 1)), "rescheduled onto a future day")
    }

    let strongTenK = CompletedRun(date: date(2026, 1, 25), distanceMeters: 10_000, durationSeconds: 43 * 60)
    let adapted = engine.adapt(plan: plan, completedRuns: [strongTenK], asOf: date(2026, 2, 1), calendar: cal)
    h.check(adapted.allWorkouts.count == plan.allWorkouts.count, "full adapt preserves workout count")
    h.check(adapted.vdot >= plan.vdot, "full adapt does not regress fitness")
}

// MARK: Weekly volume redistribution

h.suite("Weekly volume redistribution") {
    let engine = AdaptationEngine()
    let zones = VDOTCalculator().paceZones(forVDOT: 45)
    let goal = Goal(race: .marathon, raceDate: date(2026, 6, 1))
    let easyPace = 330.0...360.0

    // A 42 km week: Mon long 17, Tue easy 8, Thu easy 7, Sat threshold 10.
    let mon = PlannedWorkout(date: date(2026, 3, 2), type: .longRun, distanceMeters: 17_000, targetPaceSecPerKm: easyPace)
    let tue = PlannedWorkout(date: date(2026, 3, 3), type: .easy, distanceMeters: 8_000, targetPaceSecPerKm: easyPace)
    let thu = PlannedWorkout(date: date(2026, 3, 5), type: .easy, distanceMeters: 7_000, targetPaceSecPerKm: easyPace)
    let sat = PlannedWorkout(date: date(2026, 3, 7), type: .threshold, distanceMeters: 10_000, targetPaceSecPerKm: easyPace)
    let week = TrainingWeek(index: 0, startDate: date(2026, 3, 2), phase: .build, workouts: [mon, tue, thu, sat])
    let base = TrainingPlan(goal: goal, vdot: 45, paceZones: zones, weeks: [week])
    h.check(base.weeks[0].plannedVolumeMeters == 42_000, "week target is 42 km")

    // Athlete bails on Monday's long run, records only 5 km.
    let short = CompletedRun(date: date(2026, 3, 2), distanceMeters: 5_000, durationSeconds: 25 * 60)
    func find(_ id: UUID, in list: [PlannedWorkout]) -> PlannedWorkout { list.first { $0.id == id }! }
    // By default a short day is never made up: the easy runs keep their distance.
    let kept = engine.redistributedWithinWeek(plan: base, completedRuns: [short], asOf: date(2026, 3, 2), calendar: cal).weeks[0].workouts
    h.check(find(tue.id, in: kept).distanceMeters == 8_000 && find(thu.id, in: kept).distanceMeters == 7_000,
            "a short day isn't made up on the easy runs after it")
    // Asked to (maxEasyGrowth 1.5), easy runs can still absorb a shortfall.
    let out = engine.redistributedWithinWeek(plan: base, completedRuns: [short], asOf: date(2026, 3, 2), maxEasyGrowth: 1.5, calendar: cal)
    let w = out.weeks[0].workouts

    // The quality session and the (past, partial) long run are left untouched.
    h.check(find(sat.id, in: w).distanceMeters == 10_000 && find(sat.id, in: w).type == .threshold, "threshold session protected")
    h.check(find(mon.id, in: w).distanceMeters == 17_000, "the long run itself is left as history")
    // Easy runs grow to absorb the shortfall, each capped at 1.5x its original.
    h.check(find(tue.id, in: w).distanceMeters > 8_000 && find(tue.id, in: w).distanceMeters <= 12_001, "Tue easy grew, capped at 1.5x")
    h.check(find(thu.id, in: w).distanceMeters > 7_000 && find(thu.id, in: w).distanceMeters <= 10_501, "Thu easy grew, capped at 1.5x")
    h.check(find(tue.id, in: w).targetPaceSecPerKm == easyPace, "grown easy run keeps its easy pace")

    // Overshoot: banking the whole week on Monday leaves nothing for the easy runs.
    let big = CompletedRun(date: date(2026, 3, 2), distanceMeters: 42_000, durationSeconds: 3 * 3600)
    let out2 = engine.redistributedWithinWeek(plan: base, completedRuns: [big], asOf: date(2026, 3, 2), calendar: cal)
    let w2 = out2.weeks[0].workouts
    h.check(find(tue.id, in: w2).type == .rest, "Tue easy collapses to rest when volume is already met")
    h.check(find(thu.id, in: w2).type == .rest, "Thu easy collapses to rest when volume is already met")
    h.check(find(sat.id, in: w2).type == .threshold, "quality still protected on overshoot")

    // A missed Monday with the long run still ahead: easy runs grow, but never past
    // the long run (the user saw a 16.4 km easy run in a week with a 14.8 km long run).
    let lMon = PlannedWorkout(date: date(2026, 3, 2), type: .easy, distanceMeters: 8_000, targetPaceSecPerKm: easyPace)
    let lTue = PlannedWorkout(date: date(2026, 3, 3), type: .easy, distanceMeters: 10_000, targetPaceSecPerKm: easyPace)
    let lThu = PlannedWorkout(date: date(2026, 3, 5), type: .easy, distanceMeters: 9_000, targetPaceSecPerKm: easyPace)
    let lSat = PlannedWorkout(date: date(2026, 3, 7), type: .longRun, distanceMeters: 12_000, targetPaceSecPerKm: easyPace)
    let lateLong = TrainingPlan(goal: goal, vdot: 45, paceZones: zones, weeks: [
        TrainingWeek(index: 0, startDate: date(2026, 3, 2), phase: .build, workouts: [lMon, lTue, lThu, lSat])
    ])
    let w3 = engine.redistributedWithinWeek(plan: lateLong, completedRuns: [], asOf: date(2026, 3, 3), maxEasyGrowth: 1.5, calendar: cal).weeks[0].workouts
    h.check(find(lTue.id, in: w3).distanceMeters > 10_000 && find(lThu.id, in: w3).distanceMeters > 9_000, "with growth allowed, easy runs absorb the missed day")
    h.check(w3.filter { $0.type == .easy }.allSatisfy { $0.distanceMeters <= 12_000 }, "no easy run grows past the long run")
    h.check(find(lSat.id, in: w3).distanceMeters == 12_000, "long run keeps its distance")

    // A week that isn't the current week is never touched.
    let far = engine.redistributedWithinWeek(plan: base, completedRuns: [short], asOf: date(2026, 5, 1), calendar: cal)
    h.check(far.weeks[0].workouts == base.weeks[0].workouts, "non-current week left unchanged")
}

// MARK: Training buddy

h.suite("Training buddy: paces the plan to the training actually done") {
    let engine = AdaptationEngine()
    let buddy = TrainingBuddy()
    let goal = Goal(race: .marathon, raceDate: date(2026, 11, 1), targetTimeSeconds: 4 * 3600, daysPerWeek: 5)
    let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 52 * 60, date: date(2026, 5, 1))
    let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: fitness, startDate: date(2026, 5, 4), calendar: cal)

    /// Runs on the plan's running days before `until`, at `share` of the distance,
    /// skipping the days in `skip`.
    func ran(_ share: Double, until: Date, skip: ClosedRange<Date>? = nil, pace: Double = 380) -> [CompletedRun] {
        plan.allWorkouts.filter { $0.type.isRunning && $0.date < until && !(skip?.contains($0.date) ?? false) }
            .map { CompletedRun(date: $0.date, distanceMeters: $0.distanceMeters * share,
                                durationSeconds: $0.distanceMeters * share / 1_000 * pace) }
    }
    func week(_ p: TrainingPlan, containing d: Date) -> TrainingWeek {
        p.weeks.first { $0.startDate <= d && cal.date(byAdding: .day, value: 7, to: $0.startDate)! > d }!
    }
    func future(_ p: TrainingPlan, from d: Date) -> [PlannedWorkout] { p.allWorkouts.filter { $0.date >= d && $0.type.isRunning } }

    // Following the plan: on track, nothing shrinks.
    let asOf = date(2026, 6, 15)
    let full = ran(1, until: asOf)
    let onTrack = engine.adaptWithStatus(plan: plan, completedRuns: full, asOf: asOf, calendar: cal)
    h.check(onTrack.buddy.phase == .onTrack, "running the plan reads as on track")
    h.check(abs(week(onTrack.plan, containing: asOf).plannedVolumeMeters - week(plan, containing: asOf).plannedVolumeMeters) < 1_000,
            "on track, the week keeps its planned distance")

    // 80% of the plan: holding, this week stays at last week's planned level.
    let some = ran(0.8, until: asOf)
    let hold = engine.adaptWithStatus(plan: plan, completedRuns: some, asOf: asOf, calendar: cal)
    h.check(hold.buddy.phase == .holding, "80% of the plan reads as holding (got \(hold.buddy.phase))")
    let lastWeek = plan.weeks[week(plan, containing: asOf).index - 1].plannedVolumeMeters
    h.check(week(hold.plan, containing: asOf).plannedVolumeMeters <= max(lastWeek, week(plan, containing: asOf).plannedVolumeMeters) + 1_000,
            "holding, this week doesn't grow past last week's level")

    // Holding right after a cutback week: the cap is the last full week, not the cutback.
    let vols = plan.weeks.map(\.plannedVolumeMeters)
    if let w = (2..<plan.weeks.count).first(where: { plan.weeks[$0].phase == .build && vols[$0 - 1] < 0.85 * vols[$0 - 2] && vols[$0] > vols[$0 - 1] + 2_000 }) {
        let after = plan.weeks[w].startDate
        let r = engine.adaptWithStatus(plan: plan, completedRuns: ran(0.85, until: after), asOf: after, calendar: cal)
        h.check(r.buddy.phase == .holding, "85% of the plan reads as holding after a cutback (got \(r.buddy.phase))")
        h.check(r.plan.weeks[w].plannedVolumeMeters > vols[w - 1] + 1_000,
                "holding after a cutback week doesn't stay at the cutback level (\(Int(r.plan.weeks[w].plannedVolumeMeters)) vs \(Int(vols[w - 1])))")
    } else {
        h.check(false, "the test plan has a build week after a cutback")
    }

    // Half the plan: rebuilding from what was run, at most 10% more a week.
    let half = ran(0.5, until: asOf)
    let rebuild = engine.adaptWithStatus(plan: plan, completedRuns: half, asOf: asOf, calendar: cal)
    h.check(rebuild.buddy.phase == .rebuilding, "half the plan reads as rebuilding")
    let thisWeek = week(rebuild.plan, containing: asOf)
    let recent = rebuild.buddy.recentWeeklyMeters
    h.check(thisWeek.plannedVolumeMeters <= max(recent * 1.1, 0.5 * week(plan, containing: asOf).plannedVolumeMeters) + 1_000,
            "rebuilding, this week is about 10% over the recent average (\(Int(thisWeek.plannedVolumeMeters)) vs \(Int(recent)))")
    let next = rebuild.plan.weeks[thisWeek.index + 1].plannedVolumeMeters
    h.check(next <= thisWeek.plannedVolumeMeters * 1.1 + 1_000, "and the week after grows by at most 10%")
    h.check(future(rebuild.plan, from: asOf).contains { $0.type == .easy && !$0.notes.isEmpty }, "the shorter runs say why")
    // In a build week (base weeks have no hard sessions): one of this week's hard
    // sessions becomes easy, the ones in later weeks stay.
    let buildAsOf = date(2026, 8, 10)
    let rebuildBuild = engine.adaptWithStatus(plan: plan, completedRuns: ran(0.5, until: buildAsOf), asOf: buildAsOf, calendar: cal).plan
    func quality(_ p: TrainingPlan, from: Date, to: Date) -> Int {
        p.allWorkouts.filter { AdaptationEngine.qualityTypes.contains($0.type) && $0.date >= from && $0.date < to }.count
    }
    let weekEnd = cal.date(byAdding: .day, value: 7, to: week(plan, containing: buildAsOf).startDate)!
    h.check(quality(rebuildBuild, from: buildAsOf, to: weekEnd) == quality(plan, from: buildAsOf, to: weekEnd) - 1,
            "rebuilding, one hard session this week becomes an easy run")
    h.check(quality(rebuildBuild, from: weekEnd, to: date(2026, 9, 7)) == quality(plan, from: weekEnd, to: date(2026, 9, 7)),
            "and the hard sessions of later weeks stay")

    // A 10-day break: easing back, Daniels' pace factor, easy-only, half the volume.
    let breakStart = date(2026, 6, 3), back = date(2026, 6, 14)
    let withBreak = ran(1, until: breakStart) + [CompletedRun(date: back, distanceMeters: 5_000, durationSeconds: 5 * 400)]
    let easing = engine.adaptWithStatus(plan: plan, completedRuns: withBreak, asOf: date(2026, 6, 15), calendar: cal)
    let lastBefore = withBreak.map(\.date).filter { $0 < breakStart }.max()!
    let expectedOff = cal.dateComponents([.day], from: lastBefore, to: back).day! - 1
    if case .easingBack(let days, _) = easing.buddy.phase {
        h.check(days == expectedOff, "the break counts the days between the runs (\(days) days off)")
    } else { h.check(false, "a break of over 5 days eases back (got \(easing.buddy.phase))") }
    h.check(abs(easing.buddy.vdotFactor - TrainingBuddy.vdotFactor(daysOff: expectedOff)) < 0.0001
            && easing.buddy.vdotFactor < 0.99, "Daniels' factor for the days off lowers the VDOT")
    h.check(easing.plan.vdot < onTrack.plan.vdot, "paces are a bit easier after the break")
    let soon = future(easing.plan, from: date(2026, 6, 15)).filter { $0.date < date(2026, 6, 24) }
    h.check(!soon.isEmpty && soon.allSatisfy { !AdaptationEngine.qualityTypes.contains($0.type) }, "easy runs only while easing back")
    h.check(easing.buddy.message.contains("Welcome back"), "and the buddy says welcome back")
    let preBreak = TrainingBuddy.distance(of: withBreak, from: date(2026, 5, 6), to: date(2026, 6, 3), calendar: cal) / 4
    h.check(week(easing.plan, containing: date(2026, 6, 15)).plannedVolumeMeters <= preBreak * 0.5 + 6_000,
            "the first week back is about half the volume before the break")
    // 4 days off changes nothing.
    let shortGap = ran(1, until: date(2026, 6, 10)) + ran(1, until: asOf).filter { $0.date >= date(2026, 6, 14) }
    h.check(buddy.status(plan: plan, completedRuns: shortGap, asOf: asOf, calendar: cal).isEasingBack == false,
            "a few days off don't count as a break")

    // Daniels' table.
    h.check(TrainingBuddy.vdotFactor(daysOff: 3) == 1 && abs(TrainingBuddy.vdotFactor(daysOff: 21) - 0.952) < 0.0001
            && TrainingBuddy.vdotFactor(daysOff: 120) == 0.8, "VDOT factors follow Daniels' table")

    // Single runs: no more than 10% past the longest of the last 30 days.
    let little = plan.allWorkouts.filter { $0.type.isRunning && $0.date < asOf && $0.date >= date(2026, 5, 18) }
        .map { CompletedRun(date: $0.date, distanceMeters: min($0.distanceMeters, 8_000), durationSeconds: min($0.distanceMeters, 8_000) / 1_000 * 380) }
    let capped = engine.adaptWithStatus(plan: plan, completedRuns: little, asOf: asOf, calendar: cal).plan
    let firstLong = future(capped, from: asOf).first { $0.type == .longRun }!
    h.check(firstLong.distanceMeters <= 8_800 + 1, "the next long run is at most 10% past the longest recent run (got \(Int(firstLong.distanceMeters)))")

    // Paces: at most +1 VDOT per 3 weeks, from strong runs.
    let fast = [CompletedRun(date: date(2026, 5, 9), distanceMeters: 10_000, durationSeconds: 45 * 60)]
    let st = buddy.status(plan: plan, completedRuns: fast, asOf: date(2026, 5, 10), calendar: cal)
    h.check(buddy.pacingVDOT(base: plan.vdot, plan: plan, status: st, completedRuns: fast, asOf: date(2026, 5, 10), calendar: cal) == (plan.vdot * 10).rounded() / 10,
            "no pace increase in the first 3 weeks")
    let st2 = buddy.status(plan: plan, completedRuns: full + fast, asOf: asOf, calendar: cal)
    let raised = buddy.pacingVDOT(base: plan.vdot, plan: plan, status: st2, completedRuns: full + fast, asOf: asOf, calendar: cal)
    h.check(raised > plan.vdot && raised <= plan.vdot + 2.05, "after 6 weeks at most +2 VDOT (got \(raised - plan.vdot))")

    // Hard sessions run clearly slower than their target: paces come down 1 VDOT.
    // (In the build weeks, which have hard sessions.)
    let buildDay = date(2026, 8, 10)
    let slowQuality = ran(1, until: buildDay).map { run -> CompletedRun in
        guard let w = plan.allWorkouts.first(where: { cal.isDate($0.date, inSameDayAs: run.date) }),
              [.threshold, .interval, .marathonPace].contains(w.type), let target = w.targetPaceSecPerKm else { return run }
        // Work slower than its target; the session as a whole still faster than easy.
        let work = w.structure.map { Double($0.reps) * $0.workMeters } ?? w.distanceMeters
        let easyPace = plan.paceZones.easySecPerKm
        let expected = (work * target.upperBound + (w.distanceMeters - work) * easyPace * 1.03) / w.distanceMeters
        var r = run; r.durationSeconds = run.distanceMeters / 1_000 * min(expected * 1.06, easyPace * 0.995); return r
    }
    let st3 = buddy.status(plan: plan, completedRuns: slowQuality, asOf: buildDay, calendar: cal)
    let lowered = buddy.pacingVDOT(base: plan.vdot, plan: plan, status: st3, completedRuns: slowQuality, asOf: buildDay, calendar: cal)
    h.check(abs(lowered - (plan.vdot - 1)) < 0.11, "slower hard sessions lower the paces by 1 VDOT (got \(lowered - plan.vdot))")

    // Hard sessions run to plan (work at target, the rest easy) don't lower the paces.
    let onTarget = ran(1, until: buildDay).map { run -> CompletedRun in
        guard let w = plan.allWorkouts.first(where: { cal.isDate($0.date, inSameDayAs: run.date) }),
              [.threshold, .interval, .marathonPace].contains(w.type), let target = w.targetPaceSecPerKm else { return run }
        let work = w.structure.map { Double($0.reps) * $0.workMeters } ?? w.distanceMeters
        let mid = (target.lowerBound + target.upperBound) / 2
        var r = run; r.durationSeconds = (work * mid + (w.distanceMeters - work) * plan.paceZones.easySecPerKm) / 1_000; return r
    }
    let st4 = buddy.status(plan: plan, completedRuns: onTarget, asOf: buildDay, calendar: cal)
    h.check(buddy.pacingVDOT(base: plan.vdot, plan: plan, status: st4, completedRuns: onTarget, asOf: buildDay, calendar: cal) >= plan.vdot - 0.05,
            "hard sessions run to plan don't lower the paces")

    // No runs at all (no Health access looks the same): the plan stays as it is.
    let none = engine.adaptWithStatus(plan: plan, completedRuns: [], asOf: asOf, calendar: cal)
    h.check(none.buddy.phase == .starting && abs(week(none.plan, containing: asOf).plannedVolumeMeters - week(plan, containing: asOf).plannedVolumeMeters) < 1_000,
            "without any runs the plan isn't cut")

    // Running today's session doesn't change the rest of the week.
    let todayRun = plan.allWorkouts.first { $0.type.isRunning && $0.date >= asOf }!
    let halfToday = ran(0.5, until: todayRun.date)
    let before = engine.adaptWithStatus(plan: plan, completedRuns: halfToday, asOf: todayRun.date, calendar: cal).plan
    let planned = before.allWorkouts.first { cal.isDate($0.date, inSameDayAs: todayRun.date) }!
    let after = engine.adaptWithStatus(plan: plan, completedRuns: halfToday + [CompletedRun(date: todayRun.date, distanceMeters: planned.distanceMeters, durationSeconds: planned.distanceMeters / 1_000 * 380)],
                                       asOf: todayRun.date, calendar: cal).plan
    h.check(week(after, containing: todayRun.date).plannedVolumeMeters <= week(before, containing: todayRun.date).plannedVolumeMeters + 500,
            "running today's session as planned doesn't make the week bigger")

    // A missed long run moves only within 3 days; later, it's not made up.
    let missedLongDay = plan.allWorkouts.first { $0.type == .longRun && $0.date >= date(2026, 6, 1) }!.date
    let skipLong = ran(1, until: asOf).filter { !cal.isDate($0.date, inSameDayAs: missedLongDay) }
    let latePlan = engine.adaptWithStatus(plan: plan, completedRuns: skipLong, asOf: cal.date(byAdding: .day, value: 6, to: missedLongDay)!, calendar: cal).plan
    h.check(!latePlan.allWorkouts.contains { $0.notes.hasPrefix("Rescheduled long run") }, "a long run missed 6 days ago isn't made up")
}

// MARK: Goal outlook

h.suite("Plan review: what was run, what changed, what each week is for") {
    let engine = AdaptationEngine()
    let fitness = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 68 * 60 + 19, date: date(2026, 10, 3))
    let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: 4.5 * 3600, daysPerWeek: 5, restWeekdays: [2])
    let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: fitness, startDate: date(2026, 10, 5), calendar: cal)
    let asOf = date(2026, 11, 30)
    let past = plan.allWorkouts.filter { $0.type.isRunning && $0.date < asOf }
    // Every run as planned, except the last one missed and the one before it at half.
    var runs = past.dropLast(2).map { CompletedRun(date: $0.date, distanceMeters: $0.distanceMeters, durationSeconds: $0.distanceMeters / 1_000 * 400) }
    let short = past[past.count - 2], missed = past[past.count - 1]
    runs.append(CompletedRun(date: short.date, distanceMeters: short.distanceMeters / 2, durationSeconds: short.distanceMeters / 2_000 * 400))
    let adapted = engine.adapt(plan: plan, completedRuns: runs, asOf: asOf, calendar: cal)
    let review = PlanReview.make(plan: adapted, original: plan, completedRuns: runs, asOf: asOf, calendar: cal)

    h.check(review.day(past[0].date, calendar: cal)?.status == .done, "a run done as planned is done")
    h.check(review.day(short.date, calendar: cal)?.status == .shorter, "half the distance is shorter")
    h.check(review.day(missed.date, calendar: cal)?.status == .missed, "no run is missed")
    h.check(abs((review.day(past[0].date, calendar: cal)?.ranPaceSecPerKm ?? 0) - 400) < 0.5, "the run's pace is shown")
    let future = adapted.allWorkouts.first { $0.type.isRunning && $0.date > asOf }!
    h.check(review.day(future.date, calendar: cal)?.status == .upcoming, "later days are upcoming")

    // Changed days carry what they were.
    let changed = adapted.allWorkouts.filter { review.day($0.date, calendar: cal)?.isChanged == true }
    h.check(changed.allSatisfy { w in
        let o = plan.allWorkouts.first { cal.isDate($0.date, inSameDayAs: w.date) }!
        let d = review.day(w.date, calendar: cal)!
        return d.originalType == o.type && d.originalMeters == o.distanceMeters
    }, "a changed day knows its original session")
    let unchanged = PlanReview.make(plan: plan, original: plan, completedRuns: [], asOf: asOf, calendar: cal)
    h.check(unchanged.days.values.allSatisfy { !$0.isChanged } && unchanged.weeks.values.allSatisfy { $0.originalMeters == nil },
            "the plan itself has no changes")

    // Weeks: done so far, purpose, cutbacks.
    let first = review.weeks[0]!
    let firstDone = runs.filter { $0.date < cal.date(byAdding: .day, value: 7, to: plan.weeks[0].startDate)! }.reduce(0) { $0 + $1.distanceMeters }
    h.check(abs(first.doneMeters - firstDone) < 1, "week 1 counts what was run in it")
    h.check(review.weeks.values.contains { $0.isCutback } && review.weeks.values.filter(\.isCutback).allSatisfy { $0.purpose.hasPrefix("An easier week") },
            "cutback weeks say they're easier")
    h.check(review.weeks[plan.weeksToRace.count - 1]!.purpose == "Short and easy until race day.", "race week has its own line")
    h.check(review.weeks[0]!.purpose.contains("long run"), "a week names its long run")

    // Paces: a fast 10 km lifts them, says why, and the days know their old pace.
    let fastTime = VDOTCalculator().predictedTimeSeconds(distanceMeters: 10_000, vdot: plan.vdot + 3)
    let withFast = runs + [CompletedRun(date: date(2026, 11, 28), distanceMeters: 10_000, durationSeconds: fastTime)]
    let fit = engine.adaptWithStatus(plan: plan, completedRuns: withFast, asOf: asOf, calendar: cal)
    h.check(fit.pacing.isFaster && fit.pacing.reason?.contains("fitter") == true, "a fast run makes the paces faster, and says why")
    let fitReview = PlanReview.make(plan: fit.plan, original: plan, completedRuns: withFast, asOf: asOf, calendar: cal)
    let nextEasy = fit.plan.allWorkouts.first { $0.type == .easy && $0.date > asOf }!
    let was = fitReview.day(nextEasy.date, calendar: cal)?.originalPace
    h.check(was != nil && was!.lowerBound > nextEasy.targetPaceSecPerKm!.lowerBound, "a coming easy run shows its slower old pace")
    h.check(engine.adaptWithStatus(plan: plan, completedRuns: runs, asOf: asOf, calendar: cal).pacing.reason == nil
            || !(engine.adaptWithStatus(plan: plan, completedRuns: runs, asOf: asOf, calendar: cal).pacing.isFaster),
            "runs at the planned paces don't make them faster")

    // Milestones: the 32 km long runs and the taper.
    let longest = plan.allWorkouts.filter { review.day($0.date, calendar: cal)?.milestone == .longestRun }
    h.check(!longest.isEmpty && longest.allSatisfy { $0.type == .longRun && $0.distanceMeters == 32_000 }, "the 32 km runs are marked")
    h.check(plan.allWorkouts.filter { review.day($0.date, calendar: cal)?.milestone == .taperBegins }.count == 1, "the taper's first long run is marked")
}

h.suite("Sessions from the books: marathon pace, strides, tune-up, recovery") {
    let fitness = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 68 * 60 + 19, date: date(2026, 10, 3))
    let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: 4.5 * 3600, daysPerWeek: 5, restWeekdays: [2])
    let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: fitness, startDate: date(2026, 10, 5), calendar: cal)
    let race = plan.weeksToRace

    // Marathon pace: every other build week, as a block between easy parts.
    let build = race.filter { $0.phase == .build }
    let mpWeeks = build.filter { $0.workouts.contains { $0.type == .marathonPace } }
    h.check(!mpWeeks.isEmpty && mpWeeks.count == build.count / 2, "every other build week has a marathon-pace run (\(mpWeeks.count) of \(build.count))")
    let mp = mpWeeks.flatMap(\.workouts).filter { $0.type == .marathonPace }
    h.check(mp.allSatisfy { $0.structure?.workType == .marathonPace && $0.structure!.reps == 1 && abs($0.structure!.totalMeters - $0.distanceMeters) < 1 },
            "marathon-pace runs are warm-up, a block, cool-down, adding up to the run")
    // Peak long runs finish at marathon pace; the 32 km ones and the easier weeks don't.
    let peakLongs = race.filter { $0.phase == .peak }.flatMap(\.workouts).filter { $0.type == .longRun }
    let mpFinish = peakLongs.filter { $0.structure?.workType == .marathonPace }
    h.check(!mpFinish.isEmpty, "some peak long runs finish at marathon pace")
    h.check(peakLongs.filter { $0.distanceMeters >= 32_000 - 1 }.allSatisfy { $0.structure == nil }, "the 32 km runs stay easy")
    h.check(mpFinish.allSatisfy { $0.structure!.workMeters <= 16_000 && $0.structure!.workMeters <= $0.distanceMeters / 3 + 1 },
            "a marathon-pace finish is at most a third, and at most 16 km")
    h.check(WorkoutSteps.steps(for: mpFinish[0], zones: plan.paceZones).contains { $0.label == "Marathon pace" }, "the watch names the block Marathon pace")

    // Daniels' caps per session: T at most 10% of the week, I the lesser of 10 km
    // and 8%, M the lesser of 29 km and 20%.
    for week in race where week.plannedVolumeMeters > 0 {
        let v = week.plannedVolumeMeters
        for w in week.workouts {
            guard let st = w.structure else { continue }
            let work = Double(st.reps) * st.workMeters
            switch st.workType {
            case .threshold: h.check(work <= 0.10 * v + 1, "threshold \(Int(work)) m within 10% of week \(week.index + 1) (\(Int(v)) m)")
            case .interval: h.check(work <= min(10_000, 0.08 * v) + 1, "intervals \(Int(work)) m within Daniels' cap in week \(week.index + 1)")
            case .marathonPace: h.check(work <= min(29_000, 0.20 * v) + 1, "marathon pace \(Int(work)) m within 20% of week \(week.index + 1)")
            default: break
            }
        }
    }

    // At most two quality sessions a week (Daniels), a marathon-pace long run counting as one.
    h.check(race.allSatisfy { week in
        week.workouts.filter { AdaptationEngine.qualityTypes.contains($0.type) || $0.structure?.workType == .marathonPace && $0.type == .longRun }.count <= 2
    }, "never more than two quality sessions in a week")

    // Strides: one easy run a week in the base, two in the build and peak.
    let strides = { (w: TrainingWeek) in w.workouts.filter { $0.notes.contains("strides") }.count }
    h.check(race.filter { $0.phase == .base && $0.index > 0 }.allSatisfy { strides($0) == 1 }, "base weeks: strides once")
    h.check(race.filter { $0.phase == .build }.allSatisfy { strides($0) == 2 }, "build weeks: strides twice")

    // A run the plan shortens keeps its strides.
    h.check(VDOTPlanGenerator.note("Shorter", keepingStridesOf: VDOTPlanGenerator.stridesNote) == "Shorter, then 6 × 20 s strides",
            "a shortened run keeps its strides")

    // The tune-up: a 10 km six weeks out, with its race pace.
    let trials = plan.allWorkouts.filter { $0.type == .timeTrial }
    h.check(trials.count == 1, "one tune-up race in a marathon plan")
    let trial = trials[0]
    let trialWeek = race.firstIndex { $0.workouts.contains(trial) }!
    h.check(race.count - 1 - trialWeek == 6 && trial.structure?.workMeters == 10_000, "a 10 km six weeks before race week")
    // Running it fast lifts the paces in full and says so; skipping it changes nothing.
    let engine = AdaptationEngine()
    let before = plan.allWorkouts.filter { $0.type.isRunning && $0.date < trial.date }
        .map { w in CompletedRun(date: w.date, distanceMeters: w.distanceMeters,
                                 durationSeconds: w.distanceMeters / 1_000 * plan.paceZones.easySecPerKm * 1.01) }
    let raced = VDOTCalculator().predictedTimeSeconds(distanceMeters: 10_000, vdot: plan.vdot + 1.5)
    let withTrial = before + [CompletedRun(date: trial.date, distanceMeters: 13_500,
                                           durationSeconds: raced + 3_500 / 1_000 * plan.paceZones.easySecPerKm)]
    let after = cal.date(byAdding: .day, value: 1, to: trial.date)!
    let up = engine.adaptWithStatus(plan: plan, completedRuns: withTrial, asOf: after, calendar: cal).pacing
    h.check(abs(up.vdot - (plan.vdot + 1.5)) < 0.15, "the tune-up lifts the paces by its full VDOT (+\(up.vdot - plan.vdot))")
    h.check(up.reason?.contains("tune-up") == true, "and says it's from the tune-up")
    h.check(engine.adaptWithStatus(plan: plan, completedRuns: before, asOf: after, calendar: cal).pacing.vdot <= plan.vdot + 0.05,
            "skipping it doesn't change the paces")
    h.check(race[trialWeek].plannedVolumeMeters <= 0.92 * max(race[trialWeek - 1].plannedVolumeMeters, race[trialWeek + 1].plannedVolumeMeters),
            "the tune-up week is lighter than the weeks around it")
    let shortPlan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: fitness, startDate: date(2027, 2, 15), calendar: cal)
    h.check(!shortPlan.allWorkouts.contains { $0.type == .timeTrial }, "no tune-up in a plan under 14 weeks")

    // Recovery: an easy day per 3 km raced, rest first, then short easy runs.
    let recovery = plan.allWorkouts.filter { $0.date > goal.raceDate }
    h.check(recovery.count == 14, "14 recovery days after a marathon (got \(recovery.count))")
    h.check(recovery.prefix(3).allSatisfy { $0.type == .rest }, "the first 3 days are rest")
    h.check(recovery.filter(\.type.isRunning).allSatisfy { $0.type == .easy && $0.distanceMeters <= 10_000 }, "then only easy runs, at most 10 km")
    h.check(!recovery.contains { $0.type.isRunning && cal.component(.weekday, from: $0.date) == 2 }, "and none on the weekday kept free")
    let half = try VDOTPlanGenerator().makePlan(goal: Goal(race: .halfMarathon, raceDate: date(2027, 4, 25), daysPerWeek: 4),
                                                 fitness: fitness, startDate: date(2027, 1, 4), calendar: cal)
    h.check(half.allWorkouts.filter { $0.date > half.goal.raceDate }.count == 7, "7 recovery days after a half")
    // Race day: pacing always, carbohydrate for races over an hour, 90 g past 2½ hours.
    let raceDay = plan.allWorkouts.first { $0.type == .raceDay }!
    h.check(raceDay.notes.contains("not faster") && raceDay.notes.contains("90 g"), "a 4:30 marathon gets pacing and up to 90 g an hour")
    h.check(!VDOTPlanGenerator.raceDayAdvice(for: .tenK, expectedSeconds: 50 * 60).contains(" g "), "a 50-minute 10 km gets no fuelling advice")
    // Progress counts the weeks to race day only.
    h.check(PlanProgress.make(plan: plan, completedRuns: [], asOf: date(2026, 11, 1), calendar: cal).totalWeeks == race.count,
            "progress counts the weeks to race day")
}

h.suite("A run on the start day, before the first scheduled run") {
    // As reported: start Monday 19 Oct, 3 days a week, Tuesdays and Thursdays free,
    // so the first scheduled run is Wednesday. 8.3 km on Monday evening, and two empty
    // recordings at the same minute.
    let goal = Goal(name: "Hamburg", race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: 4.5 * 3600,
                    daysPerWeek: 3, restWeekdays: [3, 5])
    let fitness = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 68 * 60 + 19, date: date(2026, 9, 27))
    let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: fitness, startDate: date(2026, 10, 19), calendar: cal)
    let evening = date(2026, 10, 19).addingTimeInterval(20 * 3600 + 50 * 60)
    let raw = [CompletedRun(date: evening, distanceMeters: 8_300, durationSeconds: 55 * 60 + 5, averageHeartRate: 151),
               CompletedRun(date: evening, distanceMeters: 0, durationSeconds: 30, averageHeartRate: 85),
               CompletedRun(date: evening, distanceMeters: 0, durationSeconds: 22)]
    let runs = CompletedRun.cleaned(raw)
    h.check(runs.count == 1 && runs[0].distanceMeters == 8_300, "the empty recordings don't count")
    h.check(CompletedRun.cleaned([raw[0], CompletedRun(date: evening.addingTimeInterval(20), distanceMeters: 8_100, durationSeconds: 54 * 60)]).count == 1,
            "a run recorded on the watch and the iPhone counts once")
    let phone = CompletedRun(date: evening, distanceMeters: 8_400, durationSeconds: 55 * 60)
    let watch = CompletedRun(date: evening, distanceMeters: 8_200, durationSeconds: 55 * 60, averageHeartRate: 150)
    h.check(CompletedRun.cleaned([phone, watch]).first?.averageHeartRate == 150, "and keeps the watch's heart rate")
    let firstRun = plan.allWorkouts.first { $0.type.isRunning }!
    h.check(cal.component(.weekday, from: firstRun.date) == 4, "the first scheduled run is Wednesday")

    let asOf = evening.addingTimeInterval(3_600)
    let progress = PlanProgress.make(plan: plan, completedRuns: runs, asOf: asOf, calendar: cal)
    h.check(abs(progress.currentWeekCompletedMeters - 8_300) < 1, "this week counts the 8.3 km (got \(progress.currentWeekCompletedMeters))")
    h.check(abs(progress.completedDistanceMeters - 8_300) < 1, "and so does the plan so far")
    let review = PlanReview.make(plan: plan, original: plan, completedRuns: runs, asOf: asOf, calendar: cal)
    h.check(review.day(evening, calendar: cal)?.status == .extra && review.day(evening, calendar: cal)?.ranMeters == 8_300,
            "Monday shows the run, on a rest day")
    h.check(abs((review.weeks[0]?.doneMeters ?? 0) - 8_300) < 1, "the week header shows 8 km done")
    h.check(review.day(evening, calendar: cal)?.effort == .easy, "6:39/km is an easy run for this runner")
    let z = plan.paceZones
    h.check(PlanReview.effort(paceSecPerKm: z.thresholdSecPerKm, zones: z) == .threshold
            && PlanReview.effort(paceSecPerKm: z.intervalSecPerKm, zones: z) == .interval
            && PlanReview.effort(paceSecPerKm: z.marathonSecPerKm, zones: z) == .marathonPace, "efforts follow the zones")
    // The week takes it into account: the easy runs left get shorter, the long run keeps its length.
    let adapted = AdaptationEngine().adapt(plan: plan, completedRuns: runs, asOf: asOf, calendar: cal)
    let left = { (p: TrainingPlan) in p.weeks[0].workouts.filter { $0.date > asOf && $0.type == .easy }.map(\.distanceMeters).reduce(0, +) }
    h.check(left(adapted) < left(plan) - 1_000, "the week's easy runs left get shorter (\(Int(left(plan))) to \(Int(left(adapted))) m)")
    h.check(adapted.weeks[0].workouts.first { $0.type == .longRun }?.distanceMeters == plan.weeks[0].workouts.first { $0.type == .longRun }?.distanceMeters,
            "the long run keeps its length")
    // A plan saved before the start date existed still decodes.
    var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as! [String: Any]
    dict.removeValue(forKey: "startDate")
    let old = try JSONDecoder().decode(TrainingPlan.self, from: JSONSerialization.data(withJSONObject: dict))
    h.check(old.startDate == nil && old.trainingStart(calendar: cal) == cal.startOfDay(for: firstRun.date), "older plans fall back to the first run")
}

h.suite("Review fixes: tune-up, marathon pace, recovery") {
    let fitness = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 68 * 60 + 19, date: date(2026, 10, 3))
    let gen = VDOTPlanGenerator(), engine = AdaptationEngine()
    // 16-week marathon at 4 days, holding at the tune-up week: the race keeps 10 km.
    let m = try gen.makePlan(goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 4),
                             fitness: fitness, startDate: date(2027, 1, 4), calendar: cal)
    if let trial = m.allWorkouts.first(where: { $0.type == .timeTrial }) {
        let monday = VDOTPlanGenerator.startOfWeek(trial.date, calendar: cal)
        let runs = m.allWorkouts.filter { $0.type.isRunning && $0.date < monday }
            .map { CompletedRun(date: $0.date, distanceMeters: $0.distanceMeters * 0.8, durationSeconds: $0.distanceMeters * 0.8 / 1_000 * 420) }
        let a = engine.adapt(plan: m, completedRuns: runs, asOf: monday, calendar: cal)
        let t = a.allWorkouts.first { cal.isDate($0.date, inSameDayAs: trial.date) }!
        h.check(t.type == .easy || (t.type == .timeTrial && t.structure?.workMeters == 10_000 && t.notes.hasPrefix("Tune-up")),
                "a held-back tune-up keeps its 10 km race, or becomes an easy run (\(t.type) \(Int(t.structure?.workMeters ?? 0)))")
    } else { h.check(false, "the 16-week plan has a tune-up") }
    // 10 km plans of 8 to 10 weeks: the tune-up never longer than the long run, never in a cutback week.
    for weeks in 8...10 {
        for dpw in 3...6 {
            let race = date(2027, 4, 25)
            let p = try gen.makePlan(goal: Goal(race: .tenK, raceDate: race, daysPerWeek: dpw), fitness: fitness,
                                     startDate: cal.date(byAdding: .day, value: -7 * weeks, to: race)!, calendar: cal)
            for w in p.weeksToRace where w.workouts.contains(where: { $0.type == .timeTrial }) {
                let trial = w.workouts.first { $0.type == .timeTrial }!.distanceMeters
                let long = w.workouts.filter { $0.type == .longRun }.map(\.distanceMeters).max() ?? 0
                h.check(trial <= long + 1, "10 km plan, \(weeks) weeks, \(dpw) days: tune-up \(Int(trial)) m within the long run \(Int(long)) m")
            }
        }
    }
    // Recovery: no more runs a week than the days per week.
    let three = try gen.makePlan(goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 3), fitness: fitness,
                                 startDate: date(2026, 10, 5), calendar: cal)
    h.check(three.weeks.filter { $0.phase == .recovery }.allSatisfy { $0.workouts.filter(\.type.isRunning).count <= 3 },
            "3 days a week: at most 3 recovery runs a week")
    // Easing back after a break drops marathon-pace finishes from long runs.
    let full = try gen.makePlan(goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 5), fitness: fitness,
                                startDate: date(2026, 10, 5), calendar: cal)
    if let mpLong = full.allWorkouts.first(where: { $0.type == .longRun && $0.structure?.workType == .marathonPace }) {
        let back = cal.date(byAdding: .day, value: -6, to: mpLong.date)!
        let before = full.allWorkouts.filter { $0.type.isRunning && $0.date < cal.date(byAdding: .day, value: -25, to: back)! }
            .map { CompletedRun(date: $0.date, distanceMeters: $0.distanceMeters, durationSeconds: $0.distanceMeters / 1_000 * 400) }
        let a = engine.adaptWithStatus(plan: full, completedRuns: before, asOf: back, calendar: cal)
        let long = a.plan.allWorkouts.first { cal.isDate($0.date, inSameDayAs: mpLong.date) }!
        h.check(!a.buddy.isEasingBack || long.structure == nil, "easing back, the long run has no marathon-pace finish")
    }
    // The watch sees the plan's own notes as standard, the adaptation's as reasons.
    h.check(VDOTPlanGenerator.isStandardNote("Long run, easy and conversational. Practise your race-day drinks and gels on it.")
            && VDOTPlanGenerator.isStandardNote(VDOTPlanGenerator.stridesNote)
            && !VDOTPlanGenerator.isStandardNote("Shorter, the week's distance is nearly done"), "standard notes are told apart from changes")
}

h.suite("Older watches get a plan they can read") {
    // What a 1.1.0 watch knows: no tune-up type, no recovery phase.
    enum OldType: String, Decodable { case rest, easy, longRun, marathonPace, threshold, interval, repetitionSpeed, raceDay }
    enum OldPhase: String, Decodable { case base, build, peak, taper, raceWeek, maintenance }
    struct OldStructure: Decodable { var workType: OldType; var recoveryType: OldType }
    struct OldWorkout: Decodable { var type: OldType; var structure: OldStructure? }
    struct OldWeek: Decodable { var phase: OldPhase; var workouts: [OldWorkout] }
    struct OldGoal: Decodable { var skipHolidays: Bool? }
    struct OldPlan: Decodable { var goal: OldGoal; var weeks: [OldWeek] }

    let fitness = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 68 * 60 + 19, date: date(2026, 10, 3))
    let plan = try VDOTPlanGenerator().makePlan(goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 5),
                                                fitness: fitness, startDate: date(2026, 10, 5), calendar: cal)
    let data = try JSONEncoder().encode(plan)
    h.check((try? JSONDecoder().decode(OldPlan.self, from: data)) == nil, "as it is, an old watch can't read the new plan")
    let old = try? JSONDecoder().decode(OldPlan.self, from: LegacyFormat.forOlderWatch(data))
    h.check(old != nil, "in the older format, it can")
    h.check(old?.goal.skipHolidays == false, "and it doesn't skip Christmas")
    h.check(old?.weeks.count == plan.weeks.count, "with every week")
    // New builds read values from later versions instead of failing.
    let future = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"timeTrial\"", with: "\"hillRepeats\"")
    h.check((try? JSONDecoder().decode(TrainingPlan.self, from: Data(future.utf8))) != nil, "an unknown run type doesn't break this version")
}

h.suite("Target time: race-day pace, not training paces") {
    let fitness = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 68 * 60 + 19, date: date(2026, 10, 3))
    func plan(_ target: Double?) throws -> TrainingPlan {
        try VDOTPlanGenerator().makePlan(
            goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: target, daysPerWeek: 5),
            fitness: fitness, startDate: date(2026, 10, 5), calendar: cal)
    }
    let none = try plan(nil), four = try plan(4 * 3600), fast = try plan(3.5 * 3600)
    h.check(none.paceZones == four.paceZones && four.paceZones == fast.paceZones, "training paces are the same for no target, 4:00 and 3:30")
    let race = { (p: TrainingPlan) in p.allWorkouts.first { $0.type == .raceDay }!.targetPaceSecPerKm!.lowerBound }
    h.check(race(fast) < race(four), "a faster target gives a faster race-day pace")
}

h.suite("Goal outlook: an honest range and verdict") {
    let engine = AdaptationEngine()
    let fitness = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 68 * 60 + 19, date: date(2026, 10, 3))
    let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: 4.5 * 3600, daysPerWeek: 5, restWeekdays: [2])
    let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: fitness, startDate: date(2026, 10, 5), calendar: cal)
    func ran(_ share: Double, until: Date) -> [CompletedRun] {
        plan.allWorkouts.filter { $0.type.isRunning && $0.date < until }
            .map { CompletedRun(date: $0.date, distanceMeters: $0.distanceMeters * share, durationSeconds: $0.distanceMeters * share / 1_000 * 400) }
    }
    func outlook(_ share: Double, _ asOf: Date) -> GoalOutlook {
        let runs = ran(share, until: asOf)
        let r = engine.adaptWithStatus(plan: plan, completedRuns: runs, asOf: asOf, calendar: cal)
        return GoalOutlook.make(plan: r.plan, buddy: r.buddy, completedRuns: runs, asOf: asOf, calendar: cal)
    }
    let full = outlook(1, date(2026, 11, 30))
    let lighter = outlook(0.8, date(2026, 11, 30))
    let half = outlook(0.5, date(2026, 11, 30))
    h.check(full.raceDay.upperBound - full.raceDay.lowerBound > 15 * 60, "race day is a range, not one time")
    h.check(full.raceDay.lowerBound < full.today.lowerBound, "training to plan points to a faster race day than today")
    h.check(full.verdict == .onTrack, "following the plan, 4:30 is on track (got \(String(describing: full.verdict)))")
    h.check((lighter.verdict ?? .onTrack) > .onTrack && lighter.raceDay.lowerBound > full.raceDay.lowerBound,
            "80% of the plan gives a slower outlook")
    h.check(half.verdict == .unlikely && half.suggestedTargetSeconds != nil && half.suggestedTargetSeconds! > goal.targetTimeSeconds!,
            "half the plan: unlikely, with a slower realistic target")
    h.check(half.reason.contains("looks realistic") && half.reason.contains("50%"), "and it says why, kindly")
    let noTarget = GoalOutlook.make(plan: { var p = plan; p.goal.targetTimeSeconds = nil; return p }(),
                                    buddy: TrainingBuddy().status(plan: plan, completedRuns: [], asOf: date(2026, 10, 5), calendar: cal),
                                    completedRuns: [], asOf: date(2026, 10, 5), calendar: cal)
    h.check(noTarget.verdict == nil, "no target, no verdict, still a range")
}

// MARK: Peak long run

h.suite("Peak long run: 32 km for the marathon, 19 km for the half") {
    func longRun(_ plan: TrainingPlan, weeksOut: Int) -> Double {
        plan.weeksToRace[plan.weeksToRace.count - 1 - weeksOut].workouts.first { $0.type == .longRun }?.distanceMeters ?? 0
    }
    let fitness = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 12.2 * 336, date: date(2026, 10, 3))
    for (label, start) in [("28 weeks", date(2026, 10, 5)), ("16 weeks", date(2027, 1, 4))] {
        let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: 4.5 * 3600, daysPerWeek: 5, restWeekdays: [2])
        let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: fitness, startDate: start, calendar: cal)
        h.check(longRun(plan, weeksOut: 3) >= 32_000 - 1, "\(label): a 32 km long run 3 weeks before race day")
        h.check(longRun(plan, weeksOut: 5) >= 28_000, "\(label): and a long one 2 weeks earlier")
        h.check(longRun(plan, weeksOut: 4) < 0.7 * 32_000, "\(label): with a shorter long run between them")
        h.check(longRun(plan, weeksOut: 2) < 20_000 && longRun(plan, weeksOut: 1) < 14_000, "\(label): the taper long runs are shorter (19 km, 13 km)")
        let longs = plan.weeks.dropLast().compactMap { wk in wk.workouts.first { $0.type == .longRun }?.distanceMeters }
        let longestSoFar = longs.indices.map { longs[...$0].max()! }
        h.check(zip(longestSoFar, longs.dropFirst()).allSatisfy { $1 - $0 <= 5_000 }, "\(label): the long run never beats the longest so far by more than 5 km")
        h.check(plan.weeks.allSatisfy { wk in
            let long = wk.workouts.first { $0.type == .longRun }?.distanceMeters ?? 0
            return long <= 0.5 * wk.plannedVolumeMeters + 1 || long <= 0.36 * wk.plannedVolumeMeters + 1
        }, "\(label): the long run is at most half the week")
    }
    // A short plan grows at most 2 km a week, so it stops short of 32 km.
    let shortGoal = Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 5)
    let short = try VDOTPlanGenerator().makePlan(goal: shortGoal, fitness: fitness, startDate: date(2027, 2, 15), calendar: cal)
    h.check(longRun(short, weeksOut: 3) < 32_000, "a 10-week plan doesn't jump to 32 km")
    // A marathon runner who is already good to go still gets the 32 km run.
    let marathon = FitnessSnapshot(distanceMeters: 42_195, timeSeconds: 4.4 * 3600, date: date(2026, 10, 3))
    let ready = try VDOTPlanGenerator().makePlan(goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: 4.5 * 3600, daysPerWeek: 5),
                                                  fitness: marathon, startDate: date(2026, 10, 5), calendar: cal)
    h.check(ready.isMaintenance && longRun(ready, weeksOut: 3) >= 32_000 - 1, "a maintenance marathon plan has the 32 km run too")
    // The half builds to 19 km, the last one 3 weeks out.
    let half = try VDOTPlanGenerator().makePlan(goal: Goal(race: .halfMarathon, raceDate: date(2027, 4, 25), daysPerWeek: 5),
                                                 fitness: fitness, startDate: date(2026, 10, 5), calendar: cal)
    h.check(longRun(half, weeksOut: 3) >= 19_000 - 1, "half: a 19 km long run 3 weeks before race day")
    h.check(longRun(half, weeksOut: 2) < 19_000 && longRun(half, weeksOut: 1) < 19_000, "half: the taper long runs are shorter")
}

// MARK: Endurance adjustment

h.suite("Good to go needs proven endurance") {
    let engine = AdaptationEngine()
    // 12.2 km at 5:36/km: pace-wise already a 4:30 marathon, endurance unproven.
    let run = FitnessSnapshot(distanceMeters: 12_200, timeSeconds: 12.2 * 336, date: date(2026, 9, 24))
    let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: 4.5 * 3600)
    let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: run, startDate: date(2026, 9, 25), calendar: cal)
    h.check(!plan.isMaintenance, "a short run doesn't make a marathon plan maintenance")
    let longest = plan.allWorkouts.filter { $0.type == .longRun }.map(\.distanceMeters).max() ?? 0
    h.check(longest >= EnduranceAdjustment.fullCreditMeters(goalMeters: goal.race.meters),
            "the build's long runs reach the full-credit distance (got \(Int(longest)))")
    let progress = PlanProgress.make(plan: plan, completedRuns: [], asOf: date(2026, 10, 1), calendar: cal)
    h.check(!progress.isReadyForGoal, "not good to go while endurance is still held back")
    // A marathon result that meets the target is still good to go.
    let marathon = FitnessSnapshot(distanceMeters: 42_195, timeSeconds: 4.4 * 3600, date: date(2026, 9, 1))
    let hold = try VDOTPlanGenerator().makePlan(goal: goal, fitness: marathon, startDate: date(2026, 9, 25), calendar: cal)
    h.check(hold.isMaintenance, "a marathon faster than the target keeps the maintenance plan")
    // The fitness run the day before the plan starts doesn't fill week 1.
    let before = CompletedRun(date: date(2026, 9, 24).addingTimeInterval(8 * 3600), distanceMeters: 12_200, durationSeconds: 4_099)
    let week1 = engine.redistributedWithinWeek(plan: plan, completedRuns: [before], asOf: date(2026, 9, 25), calendar: cal).weeks[0]
    h.check(week1.workouts.filter(\.type.isRunning).count == plan.weeks[0].workouts.filter(\.type.isRunning).count,
            "a run before the plan starts doesn't cancel week 1 runs")
}

h.suite("Endurance adjustment") {
    let engine = AdaptationEngine()
    let calc = VDOTCalculator()
    // An all-out 11.8 km relay leg in 50 minutes, training for a marathon.
    let leg = FitnessSnapshot(distanceMeters: 11_800, timeSeconds: 50 * 60, date: date(2026, 1, 1))
    let goal = Goal(race: .marathon, raceDate: date(2026, 6, 1))
    let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: leg, startDate: date(2026, 1, 5), calendar: cal)
    let full = calc.paceZones(forVDOT: plan.vdot)
    h.check(plan.enduranceHoldback > 2 && plan.enduranceHoldback <= EnduranceAdjustment.maxPoints, "marathon from 11.8 km holds back 2 to 3 VDOT")
    h.check(plan.paceZones.marathonSecPerKm > full.marathonSecPerKm, "marathon pace is slower than the raw race suggests")
    h.check(plan.paceZones.easySecPerKm == full.easySecPerKm && plan.paceZones.intervalSecPerKm == full.intervalSecPerKm, "easy and interval paces keep the race's speed")
    let race = try require(plan.allWorkouts.first { $0.type == .raceDay }, "race day")
    let rawRacePace = calc.predictedTimeSeconds(distanceMeters: goal.race.meters, vdot: plan.vdot) / 42.195
    h.check(race.targetPaceSecPerKm!.lowerBound > rawRacePace, "race-day pace uses the held-back VDOT")

    // Long runs earn it back: 19 km about halfway, 25 km fully.
    let asOf = date(2026, 3, 1)
    let half = engine.creditingEndurance(plan: plan, completedRuns: [CompletedRun(date: date(2026, 2, 22), distanceMeters: 19_400, durationSeconds: 7_800)], asOf: asOf, calendar: cal)
    h.check(half.enduranceHoldback > 0 && half.enduranceHoldback < plan.enduranceHoldback, "a 19 km long run earns part back")
    let done = engine.creditingEndurance(plan: plan, completedRuns: [CompletedRun(date: date(2026, 2, 22), distanceMeters: 25_000, durationSeconds: 9_600)], asOf: asOf, calendar: cal)
    h.check(done.enduranceHoldback == 0 && done.raceVDOT == plan.vdot, "a 25 km long run earns it all back")
    let repaced = engine.repaced(plan: done, withVDOT: done.vdot, asOf: asOf, calendar: cal)
    h.check(abs(repaced.paceZones.marathonSecPerKm - full.marathonSecPerKm) < 0.01, "with the endurance shown, marathon pace is the race's")
    let old = engine.creditingEndurance(plan: plan, completedRuns: [CompletedRun(date: date(2025, 11, 1), distanceMeters: 30_000, durationSeconds: 10_800)], asOf: asOf, calendar: cal)
    h.check(old.enduranceHoldback == plan.enduranceHoldback, "a long run from months ago doesn't count")

    // Speed goals and long fitness races hold nothing back.
    h.check(EnduranceAdjustment.basePoints(fitnessDistanceMeters: 5_000, goalMeters: 10_000) == 0, "10 km goal: nothing held back")
    h.check(EnduranceAdjustment.basePoints(fitnessDistanceMeters: 30_000, goalMeters: 42_195) == 0, "a 30 km race already shows the endurance")
}

// MARK: Fatigue analyzer

h.suite("Fatigue analyzer") {
    let analyzer = FatigueAnalyzer()
    let asOf = date(2026, 3, 1)

    // Resting-HR readings across the baseline window (~50 bpm) with an elevated
    // recent window (~58 bpm).
    func resting(_ days: [Int], bpm: Double) -> [RestingHeartRateSample] {
        days.map { RestingHeartRateSample(date: date(2026, 2, $0), bpm: bpm) }
    }
    let baselineRHR = resting(Array(2...16), bpm: 50)           // Feb 2–16, in baseline window
    let elevatedRecent = resting([25, 26, 27, 28], bpm: 58)      // Feb 25–28, in recent window
    let calmRecent = resting([25, 26, 27, 28], bpm: 50)

    let elevated = analyzer.assess(restingHeartRates: baselineRHR + elevatedRecent, completedRuns: [], asOf: asOf, calendar: cal)
    h.check(elevated.signals.contains(.elevatedRestingHeartRate), "elevated resting HR fires when recent > baseline+5bpm")
    h.check(elevated.isFatigued, "elevated resting HR marks the athlete fatigued")

    let calm = analyzer.assess(restingHeartRates: baselineRHR + calmRecent, completedRuns: [], asOf: asOf, calendar: cal)
    h.check(!calm.signals.contains(.elevatedRestingHeartRate), "steady resting HR does not fire")

    // Not enough baseline samples → no verdict even if recent is high.
    let sparse = analyzer.assess(restingHeartRates: resting([2, 3], bpm: 50) + elevatedRecent, completedRuns: [], asOf: asOf, calendar: cal)
    h.check(!sparse.signals.contains(.elevatedRestingHeartRate), "sparse baseline suppresses resting-HR signal")

    // Aerobic efficiency: same pace, higher HR in the recent window = fatigue.
    func run(_ day: Int, hr: Double, seconds: Double = 2_700) -> CompletedRun {
        CompletedRun(date: date(2026, 2, day), distanceMeters: 10_000, durationSeconds: seconds, averageHeartRate: hr)
    }
    let baselineRuns = [run(3, hr: 150), run(7, hr: 150), run(12, hr: 150)]   // baseline window
    let tiredRuns = [run(26, hr: 168)]                                        // recent window, +12% HR
    let freshRuns = [run(26, hr: 150)]

    let effDrop = analyzer.assess(restingHeartRates: [], completedRuns: baselineRuns + tiredRuns, asOf: asOf, calendar: cal)
    h.check(effDrop.signals.contains(.reducedAerobicEfficiency), "higher HR at same pace fires reduced-efficiency signal")

    let effOK = analyzer.assess(restingHeartRates: [], completedRuns: baselineRuns + freshRuns, asOf: asOf, calendar: cal)
    h.check(!effOK.signals.contains(.reducedAerobicEfficiency), "same HR at same pace does not fire efficiency signal")

    // Runs without HR are ignored (no false fatigue).
    let noHR = analyzer.assess(restingHeartRates: [], completedRuns: [
        CompletedRun(date: date(2026, 2, 3), distanceMeters: 10_000, durationSeconds: 2_700),
        CompletedRun(date: date(2026, 2, 26), distanceMeters: 10_000, durationSeconds: 3_600),
    ], asOf: asOf, calendar: cal)
    h.check(!noHR.isFatigued, "runs lacking HR never produce a fatigue verdict")

    let none = analyzer.assess(restingHeartRates: [], completedRuns: [], asOf: asOf, calendar: cal)
    h.check(!none.isFatigued, "no data → not fatigued")
    h.check(none.summary == "no fatigue detected", "empty assessment summarizes cleanly")
}

// MARK: Fatigue-based easing

h.suite("Fatigue easing") {
    let engine = AdaptationEngine()
    let plan = try marathonPlan()
    let asOf = date(2026, 3, 1)
    let asOfDay = cal.startOfDay(for: asOf)

    let fatigued = FatigueAssessment(
        signals: [.elevatedRestingHeartRate],
        restingBaselineBpm: 50, restingRecentBpm: 58
    )

    let upcomingQuality = plan.allWorkouts
        .filter { AdaptationEngine.qualityTypes.contains($0.type) && cal.startOfDay(for: $0.date) >= asOfDay }
        .min(by: { $0.date < $1.date })
    let firstQuality = try require(upcomingQuality, "an upcoming quality session")

    let eased = engine.easedForFatigue(plan: plan, assessment: fatigued, asOf: asOf, calendar: cal)
    let easedWorkout = try require(eased.allWorkouts.first { $0.id == firstQuality.id }, "the eased workout")
    h.check(easedWorkout.type == .easy, "soonest quality session is converted to easy")
    h.check(easedWorkout.notes.hasPrefix("Eased to easy: fatigue detected"), "eased workout is annotated with the reason")
    h.check(easedWorkout.distanceMeters == firstQuality.distanceMeters, "easing keeps the distance, only drops intensity")
    if let center = easedWorkout.targetPaceSecPerKm {
        h.approx((center.lowerBound + center.upperBound) / 2, plan.paceZones.easySecPerKm, tolerance: 1, "eased pace centers on the easy zone")
    }

    let easedCount = eased.allWorkouts.filter { $0.notes.hasPrefix("Eased to easy") }.count
    h.check(easedCount == 1, "eases at most one session per pass")

    // Not fatigued → plan is untouched.
    let untouched = engine.easedForFatigue(plan: plan, assessment: FatigueAssessment(), asOf: asOf, calendar: cal)
    h.check(untouched == plan, "no fatigue leaves the plan unchanged")

    // Past quality sessions are never eased.
    let pastQuality = plan.allWorkouts.first { AdaptationEngine.qualityTypes.contains($0.type) && cal.startOfDay(for: $0.date) < asOfDay }
    if let past = pastQuality {
        let after = try require(eased.allWorkouts.first { $0.id == past.id }, "past quality after easing")
        h.check(after.type == past.type, "past quality sessions are left untouched")
    }

    // adapt() with resting-HR history performs the easing end-to-end.
    let baselineRHR = (2...16).map { RestingHeartRateSample(date: date(2026, 2, $0), bpm: 50) }
    let recentRHR = [25, 26, 27, 28].map { RestingHeartRateSample(date: date(2026, 2, $0), bpm: 60) }
    let adapted = engine.adapt(plan: plan, completedRuns: [], asOf: asOf, restingHeartRates: baselineRHR + recentRHR, calendar: cal)
    h.check(adapted.allWorkouts.contains { $0.notes.hasPrefix("Eased to easy") }, "adapt() eases a session when resting HR is elevated")

    // adapt() with no fatigue data eases nothing (backward compatible).
    let adaptedNoFatigue = engine.adapt(plan: plan, completedRuns: [], asOf: asOf, calendar: cal)
    h.check(!adaptedNoFatigue.allWorkouts.contains { $0.notes.hasPrefix("Eased to easy") }, "adapt() eases nothing without fatigue data")
}

// MARK: Unavailability (vacation)

h.suite("Unavailability") {
    let engine = AdaptationEngine()
    let plan = try marathonPlan()
    let asOf = date(2026, 3, 1)
    let asOfDay = cal.startOfDay(for: asOf)

    // A one-week vacation entirely in the future.
    let vacation = UnavailablePeriod(start: date(2026, 4, 6), end: date(2026, 4, 12), reason: "Vacation")
    h.check(vacation.dayCount(calendar: cal) == 7, "inclusive day count is correct")
    h.check(vacation.contains(date(2026, 4, 6), calendar: cal) && vacation.contains(date(2026, 4, 12), calendar: cal), "both ends are inclusive")
    h.check(!vacation.contains(date(2026, 4, 13), calendar: cal), "day after end is excluded")

    let runningInVacation = plan.allWorkouts.filter {
        $0.type.isRunning && vacation.contains($0.date, calendar: cal)
    }
    h.check(!runningInVacation.isEmpty, "vacation week originally has running workouts")

    let blanked = engine.applyingUnavailability(plan: plan, periods: [vacation], asOf: asOf, calendar: cal)
    let stillRunning = blanked.allWorkouts.filter { $0.type.isRunning && vacation.contains($0.date, calendar: cal) }
    h.check(stillRunning.isEmpty, "all workouts inside the vacation become rest")
    let blankedDay = try require(blanked.allWorkouts.first { vacation.contains($0.date, calendar: cal) && $0.notes == "Vacation" }, "annotated rest day")
    h.check(blankedDay.type == .rest && blankedDay.distanceMeters == 0, "blanked day is rest with zero distance")

    // A past period is left untouched (history).
    let pastPeriod = UnavailablePeriod(start: date(2026, 2, 2), end: date(2026, 2, 8), reason: "Sick")
    let pastRunningBefore = plan.allWorkouts.filter { $0.type.isRunning && pastPeriod.contains($0.date, calendar: cal) }.count
    let afterPast = engine.applyingUnavailability(plan: plan, periods: [pastPeriod], asOf: asOf, calendar: cal)
    let pastRunningAfter = afterPast.allWorkouts.filter { $0.type.isRunning && pastPeriod.contains($0.date, calendar: cal) }.count
    h.check(pastRunningBefore == pastRunningAfter, "past unavailable days are not rewritten")

    // Empty period list is a no-op.
    h.check(engine.applyingUnavailability(plan: plan, periods: [], asOf: asOf, calendar: cal) == plan, "no periods leaves plan unchanged")

    // adapt() honors periods stored on the goal.
    var goalPlan = plan
    goalPlan.goal.unavailablePeriods = [vacation]
    let adapted = engine.adapt(plan: goalPlan, completedRuns: [], asOf: asOf, calendar: cal)
    let adaptedRunningInVacation = adapted.allWorkouts.filter { $0.type.isRunning && vacation.contains($0.date, calendar: cal) }
    h.check(adaptedRunningInVacation.isEmpty, "adapt() applies the goal's unavailable periods")
}

// MARK: Plan progress

h.suite("Plan progress") {
    let plan = try marathonPlan()
    let asOf = date(2026, 3, 1)
    let asOfDay = cal.startOfDay(for: asOf)

    // Fulfill every running workout up to asOf with a matching run.
    let doneRuns: [CompletedRun] = plan.allWorkouts
        .filter { $0.type.isRunning && cal.startOfDay(for: $0.date) <= asOfDay }
        .map { CompletedRun(date: $0.date, distanceMeters: $0.distanceMeters, durationSeconds: 1_800, plannedWorkoutID: $0.id) }

    let full = PlanProgress.make(plan: plan, completedRuns: doneRuns, asOf: asOf, calendar: cal)
    h.check(full.totalWeeks == plan.weeksToRace.count, "total weeks matches the weeks to race day")
    h.check(full.daysUntilRace == cal.dateComponents([.day], from: asOfDay, to: date(2027, 4, 25)).day!, "days-until-race counts correctly")
    h.check(full.workoutsCompleted == full.workoutsScheduledToDate, "all scheduled-to-date workouts counted as done")
    h.check(full.workoutsScheduledToDate > 0, "there are scheduled workouts by March")
    h.approx(full.adherenceFraction, 1.0, tolerance: 0.0001, "full completion → adherence 1.0")
    h.check(full.currentWeekNumber != nil, "current week resolved for a mid-plan date")
    h.check(full.nextWorkout != nil && cal.startOfDay(for: full.nextWorkout!.date) >= asOfDay, "next workout is on/after today")
    h.check(full.completedDistanceMeters > 0 && full.completedDistanceMeters <= full.totalPlannedMeters, "completed distance within plan total")

    // No runs recorded → zero adherence but valid structure.
    let none = PlanProgress.make(plan: plan, completedRuns: [], asOf: asOf, calendar: cal)
    h.check(none.completedDistanceMeters == 0, "no runs → zero completed distance")
    h.check(none.adherenceFraction == 0, "no runs → zero adherence")
    h.check(none.workoutsCompleted == 0, "no runs → zero workouts completed")
    h.check(none.plannedToDateMeters > 0, "planned-to-date still computed without runs")

    // Before the plan starts: adherence defaults to 1 (nothing to fall behind on).
    let early = PlanProgress.make(plan: plan, completedRuns: [], asOf: date(2025, 12, 1), calendar: cal)
    h.check(early.adherenceFraction == 1, "pre-plan date → adherence 1 (nothing scheduled)")
    h.check(early.currentWeekNumber == nil, "pre-plan date has no current week")

    // On race day: zero days remaining.
    let raceDay = PlanProgress.make(plan: plan, completedRuns: [], asOf: date(2027, 4, 25), calendar: cal)
    h.check(raceDay.daysUntilRace == 0, "race day → 0 days remaining")
}

// MARK: Serialization size

h.suite("Serialization size") {
    let plan = try marathonPlan()
    let workouts = plan.allWorkouts.count

    let compact = try JSONEncoder().encode(plan)
    let pretty: Data = {
        let e = JSONEncoder(); e.outputFormatting = .prettyPrinted
        return (try? e.encode(plan)) ?? Data()
    }()
    print("  · weeks=\(plan.weeks.count) workouts=\(workouts)")
    print("  · JSON compact: \(compact.count) bytes (\(compact.count / max(workouts, 1)) B/workout)")
    print("  · JSON pretty:  \(pretty.count) bytes")
    h.check(compact.count < 300_000, "full marathon plan serializes under 300 KB (got \(compact.count) bytes)")
}

// MARK: Weekday rules & regeneration

h.suite("Weekday rules & regeneration") {
    let gen = VDOTPlanGenerator()
    let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 45 * 60, date: date(2026, 1, 1))

    // Block Tuesday (3) and Thursday (5): no running workouts may land on them.
    let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 4, restWeekdays: [3, 5])
    let plan = try gen.makePlan(goal: goal, fitness: fitness, startDate: date(2026, 1, 1), calendar: cal)

    let ranOnBlocked = plan.allWorkouts.contains { w in
        w.type.isRunning && [3, 5].contains(cal.component(.weekday, from: w.date))
    }
    h.check(!ranOnBlocked, "no running workouts on blocked weekdays (Tue/Thu)")

    let buildWeek = try require(plan.weeks.first { $0.phase == .build }, "a build week")
    h.check(buildWeek.workouts.filter { $0.type.isRunning }.count == 4, "honors daysPerWeek (4) alongside rest weekdays")

    // Rest days explain themselves: a blocked weekday reads as a fixed no-training
    // day the athlete set, a scheduled recovery day reads as cross-train.
    let blockedRest = buildWeek.workouts.filter { $0.type == .rest && [3, 5].contains(cal.component(.weekday, from: $0.date)) }
    h.check(!blockedRest.isEmpty && blockedRest.allSatisfy { $0.notes.hasPrefix("No training") },
            "blocked weekdays are labelled as fixed no-training days")
    let scheduledRest = buildWeek.workouts.filter { $0.type == .rest && ![3, 5].contains(cal.component(.weekday, from: $0.date)) }
    h.check(scheduledRest.allSatisfy { $0.notes == "Rest / cross-train" },
            "non-blocked rest days read as cross-training")

    // Enough space between sessions: never three running days in a row when the
    // week has slack (4 runs across 7 days), so recovery days fall between efforts.
    let ordered = buildWeek.workouts.sorted { $0.date < $1.date }
    var maxStreak = 0, streak = 0
    for w in ordered {
        streak = w.type.isRunning ? streak + 1 : 0
        maxStreak = max(maxStreak, streak)
    }
    h.check(maxStreak <= 2, "no more than two running days in a row (spacing preserved, got \(maxStreak))")

    // Editing the goal to change a rest weekday regenerates cleanly and moves runs
    // off the newly blocked day.
    var edited = goal
    edited.restWeekdays = [2, 4]  // now block Monday (2) and Wednesday (4) instead
    let replanned = try gen.makePlan(goal: edited, fitness: fitness, startDate: date(2026, 1, 1), calendar: cal)
    let ranOnNewBlocked = replanned.allWorkouts.contains { $0.type.isRunning && [2, 4].contains(cal.component(.weekday, from: $0.date)) }
    h.check(!ranOnNewBlocked, "changing rest weekdays reruns generation with no runs on the new blocked days")

    // Long runs stay on a free weekend day when one exists (weekends aren't blocked here).
    let longRuns = plan.weeks.filter { [.base, .build, .peak].contains($0.phase) }
        .compactMap { wk in wk.workouts.first { $0.type == .longRun } }
    let weekendLongs = longRuns.filter { [1, 7].contains(cal.component(.weekday, from: $0.date)) }
    h.check(!longRuns.isEmpty && weekendLongs.count == longRuns.count, "long runs fall on a weekend (Sat/Sun)")

    // Regeneration preserves the race-day anchor, Monday-anchored week span, and the 10% rule.
    h.check(plan.weeksToRace.last?.workouts.last?.type == .raceDay, "race day preserved with rest weekdays")
    h.check(cal.isDate(plan.weeksToRace.last!.workouts.last!.date, inSameDayAs: date(2027, 4, 25)), "race day date unchanged with rest weekdays")
    let firstMonday = VDOTPlanGenerator.startOfWeek(date(2026, 1, 1), calendar: cal)
    let raceMonday = VDOTPlanGenerator.startOfWeek(date(2027, 4, 25), calendar: cal)
    let expectedWeeks = cal.dateComponents([.day], from: firstMonday, to: raceMonday).day! / 7 + 1
    h.check(plan.weeksToRace.count == expectedWeeks, "week span unchanged with rest weekdays")

    var maxSoFar = 0.0, tenPercentOK = true
    for week in plan.weeks where week.phase != .raceWeek && week.index > 0 {
        if maxSoFar > 0 && week.plannedVolumeMeters > maxSoFar * 1.10 + 1 { tenPercentOK = false }
        maxSoFar = max(maxSoFar, week.plannedVolumeMeters)
    }
    h.check(tenPercentOK, "10% rule still honored with rest weekdays")

    // Validation: asking for more days than the rules leave free is rejected clearly.
    var rejected = false
    do {
        _ = try gen.makePlan(
            goal: Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 5, restWeekdays: [1, 2, 3]),
            fitness: fitness, startDate: date(2026, 1, 1), calendar: cal
        )
    } catch PlanError.daysPerWeekExceedsAvailable(let requested, let available) {
        rejected = (requested == 5 && available == 4)
    } catch {}
    h.check(rejected, "rejects daysPerWeek > 7 - restWeekdays.count")
}

// MARK: Goal decoding tolerance

h.suite("Goal decoding tolerance") {
    // Old plans persisted a Goal without daysPerWeek / restWeekdays / unavailablePeriods.
    let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: 4, restWeekdays: [2, 4])
    var dict = try require(
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(goal)) as? [String: Any],
        "goal JSON object"
    )
    dict.removeValue(forKey: "daysPerWeek")
    dict.removeValue(forKey: "restWeekdays")
    dict.removeValue(forKey: "unavailablePeriods")
    let legacyData = try JSONSerialization.data(withJSONObject: dict)
    let decoded = try JSONDecoder().decode(Goal.self, from: legacyData)
    h.check(decoded.daysPerWeek == 5, "missing daysPerWeek defaults to 5")
    h.check(decoded.restWeekdays.isEmpty, "missing restWeekdays defaults to empty")
    h.check(decoded.unavailablePeriods.isEmpty, "missing unavailablePeriods stays empty")
    h.check(decoded.race == .marathon && cal.isDate(decoded.raceDate, inSameDayAs: date(2027, 4, 25)), "core fields survive")
}

// MARK: Plan inputs round-trip

h.suite("Plan inputs round-trip") {
    let goal = Goal(
        race: .halfMarathon, raceDate: date(2026, 10, 4), targetTimeSeconds: 5_400,
        daysPerWeek: 4, restWeekdays: [2, 5],
        unavailablePeriods: [UnavailablePeriod(start: date(2026, 7, 1), end: date(2026, 7, 7), reason: "Trip")]
    )
    let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 2_700, date: date(2026, 6, 1))
    let inputs = PlanInputs(goal: goal, fitness: fitness, startDate: date(2026, 6, 1))

    let data = try JSONEncoder().encode(inputs)
    let decoded = try JSONDecoder().decode(PlanInputs.self, from: data)
    h.check(decoded == inputs, "inputs round-trip through JSON")
    h.check(data.count < 1_500, "stored inputs stay ~1 KB (got \(data.count) bytes)")

    // Regenerating from equal inputs is deterministic — the basis for recalculate().
    let gen = VDOTPlanGenerator()
    let a = try gen.makePlan(goal: inputs.goal, fitness: inputs.fitness, startDate: inputs.startDate, calendar: cal)
    let b = try gen.makePlan(goal: decoded.goal, fitness: decoded.fitness, startDate: decoded.startDate, calendar: cal)
    h.check(a == b, "regeneration from equal inputs is deterministic")
    h.check(a.weeksToRace.last?.workouts.last?.type == .raceDay, "regenerated plan still has race day last before recovery")
}

// MARK: Plan backup (export / import)

h.suite("Plan backup") {
    let goal = Goal(
        name: "Hamburg Marathon",
        race: .marathon, raceDate: date(2027, 4, 25), targetTimeSeconds: 3 * 3600 + 30 * 60,
        daysPerWeek: 4, restWeekdays: [3, 5],
        unavailablePeriods: [UnavailablePeriod(start: date(2026, 7, 1), end: date(2026, 7, 7), reason: "Trip")]
    )
    let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 2_700, date: date(2026, 6, 1))
    let inputs = PlanInputs(goal: goal, fitness: fitness, startDate: date(2026, 6, 1))
    let backup = PlanBackup(inputs: inputs, appVersion: "1.2.3", exportedAt: date(2026, 6, 2))

    // Round-trip: encode → decode → equal inputs (incl. vacation & rest weekdays).
    let data = try PlanBackupCodec.encode(backup)
    let decoded = try PlanBackupCodec.decode(data)
    h.check(decoded.inputs == inputs, "backup round-trips to equal inputs")
    h.check(decoded.schemaVersion == PlanBackup.currentSchemaVersion, "schema version preserved")
    h.check(decoded.appVersion == "1.2.3", "app version preserved for diagnostics")
    h.check(decoded.inputs.goal.unavailablePeriods.count == 1, "vacation periods survive the round-trip")
    h.check(decoded.inputs.goal.restWeekdays == [3, 5], "rest weekdays survive the round-trip")

    // The file stays tiny (it holds inputs, not the expanded calendar).
    h.check(data.count < 2_000, "backup file stays ~1 KB (got \(data.count) bytes)")

    // A newer schema than we understand is refused (not silently loaded).
    let future = PlanBackup(inputs: inputs, appVersion: "9", schemaVersion: PlanBackup.currentSchemaVersion + 1)
    var rejectedNewer = false
    do {
        _ = try PlanBackupCodec.decode(try PlanBackupCodec.encode(future))
    } catch PlanBackupError.unsupportedVersion(let found, let supported) {
        rejectedNewer = found == PlanBackup.currentSchemaVersion + 1 && supported == PlanBackup.currentSchemaVersion
    } catch {}
    h.check(rejectedNewer, "a newer schema version is rejected with a clear error")

    // Corrupt / truncated / unrelated data throws rather than crashing.
    var threwCorrupt = false
    do {
        _ = try PlanBackupCodec.decode(Data([0x00, 0x01, 0x02, 0xFF]))
    } catch PlanBackupError.corruptData {
        threwCorrupt = true
    } catch {}
    h.check(threwCorrupt, "corrupt data throws corruptData")

    var threwOnTruncated = false
    do {
        _ = try PlanBackupCodec.decode(data.prefix(data.count / 2))
    } catch { threwOnTruncated = true }
    h.check(threwOnTruncated, "truncated file throws rather than loading a partial plan")

    // The restored inputs still regenerate a valid plan ending on race day.
    let plan = try VDOTPlanGenerator().makePlan(
        goal: decoded.inputs.goal, fitness: decoded.inputs.fitness,
        startDate: decoded.inputs.startDate, calendar: cal
    )
    h.check(plan.weeksToRace.last?.workouts.last?.type == .raceDay, "restored inputs regenerate a plan ending on race day")
}

// MARK: Target VDOT + maintenance ("good to go")

h.suite("Target VDOT & maintenance") {
    let calc = VDOTCalculator()

    // Required VDOT is a clean round-trip of (distance, target time): the VDOT a
    // target time implies should predict back to that same time. Test every preset.
    let cases: [(RaceDistance, Double)] = [
        (.fiveK, 20 * 60),          // 5K in 20:00
        (.tenK, 50 * 60),           // 10K in 50:00
        (.halfMarathon, 95 * 60),   // Half in 1:35
        (.marathon, 3 * 3600 + 30 * 60) // Marathon in 3:30
    ]
    for (race, target) in cases {
        let required = calc.vdot(distanceMeters: race.meters, timeSeconds: target)
        let predicted = calc.predictedTimeSeconds(distanceMeters: race.meters, vdot: required)
        h.check(abs(predicted - target) < 2.0, "\(race.displayName) target VDOT round-trips to within 2s (got \(Int(predicted))s vs \(Int(target))s)")
        h.check(required > 20 && required < 85, "\(race.displayName) required VDOT is in a sane range (\(String(format: "%.1f", required)))")
    }

    // Reference point the design was checked against: 10K in 50:00 ≈ VDOT 40.
    let vdot10k = calc.vdot(distanceMeters: 10_000, timeSeconds: 50 * 60)
    h.check(abs(vdot10k - 40.0) < 0.6, "10K 50:00 ≈ VDOT 40 (got \(String(format: "%.1f", vdot10k)))")

    // Already-fit runner + an easy target for the SAME distance → maintenance plan.
    let fitRun = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 45 * 60, date: date(2026, 6, 1)) // ~VDOT 45
    let easyGoal = Goal(race: .tenK, raceDate: date(2026, 9, 1), targetTimeSeconds: 52 * 60) // needs ~VDOT 38
    let maint = try VDOTPlanGenerator().makePlan(goal: easyGoal, fitness: fitRun, startDate: date(2026, 6, 1), calendar: cal)
    h.check(maint.isMaintenance, "fitter-than-target runner gets a maintenance plan")
    let progress = PlanProgress.make(plan: maint, completedRuns: [], asOf: date(2026, 6, 1), calendar: cal)
    h.check(progress.isReadyForGoal, "progress reports the athlete is ready for the goal")
    h.check((progress.vdotToGoal ?? 0) <= 0, "no VDOT gap remains when already fit enough")
    // Maintenance weeks are steady (no base/build/peak ramp) and each has a long run.
    let bodyWeeks = maint.weeks.filter { $0.phase == .maintenance }
    h.check(!bodyWeeks.isEmpty, "maintenance plan has steady maintenance weeks")
    h.check(maint.weeks.allSatisfy { $0.phase == .maintenance || $0.phase == .taper || $0.phase == .raceWeek },
            "maintenance plan has no base/build/peak progression")
    if let w = bodyWeeks.first(where: { $0.workouts.contains { $0.type.isRunning } }) {
        let runs = w.workouts.filter { $0.type.isRunning }
        let longest = runs.max(by: { $0.distanceMeters < $1.distanceMeters })
        h.check(longest?.type == .longRun, "long run is the longest session in a maintenance week")
    }
    h.check(maint.allWorkouts.first { $0.type == .raceDay }.map { cal.isDate($0.date, inSameDayAs: maint.goal.raceDate) } == true
            && maint.allWorkouts.filter { $0.date > maint.goal.raceDate }.allSatisfy { $0.type == .rest || $0.notes.hasPrefix("Recovery run") },
            "maintenance plan: race day on its date, only recovery after it")

    // Slower runner + ambitious target for the same distance → a real build, not maintenance.
    let slowRun = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 60 * 60, date: date(2026, 6, 1)) // ~VDOT 32
    let hardGoal = Goal(race: .tenK, raceDate: date(2026, 12, 1), targetTimeSeconds: 42 * 60) // needs ~VDOT 48
    let build = try VDOTPlanGenerator().makePlan(goal: hardGoal, fitness: slowRun, startDate: date(2026, 6, 1), calendar: cal)
    h.check(!build.isMaintenance, "under-target runner gets a progressive (non-maintenance) plan")
    h.check(build.weeks.contains { $0.phase == .base } && build.weeks.contains { $0.phase == .build },
            "progressive plan has base and build phases")
    let buildProgress = PlanProgress.make(plan: build, completedRuns: [], asOf: date(2026, 6, 1), calendar: cal)
    h.check(!buildProgress.isReadyForGoal && (buildProgress.vdotToGoal ?? 0) > 0, "progress shows work still to do")

    // No target time set → readiness is simply unknown (not "ready"), plan builds normally.
    let noTargetGoal = Goal(race: .tenK, raceDate: date(2026, 12, 1))
    let noTargetPlan = try VDOTPlanGenerator().makePlan(goal: noTargetGoal, fitness: fitRun, startDate: date(2026, 6, 1), calendar: cal)
    h.check(!noTargetPlan.isMaintenance, "no target time → not a maintenance plan")
    let noTargetProgress = PlanProgress.make(plan: noTargetPlan, completedRuns: [], asOf: date(2026, 6, 1), calendar: cal)
    h.check(noTargetProgress.requiredVDOT == nil && !noTargetProgress.isReadyForGoal, "no target time → no required VDOT, not flagged ready")
}

// MARK: Goal achievements

h.suite("Goal achievement summary") {
    let fitRun = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 45 * 60, date: date(2026, 6, 1))
    let goal = Goal(name: "Autumn 10K", race: .tenK, raceDate: date(2026, 9, 1), targetTimeSeconds: 52 * 60)
    let plan = try VDOTPlanGenerator().makePlan(goal: goal, fitness: fitRun, startDate: date(2026, 6, 1), calendar: cal)
    let progress = PlanProgress.make(plan: plan, completedRuns: [], asOf: date(2026, 9, 1), calendar: cal)

    let achievement = GoalAchievement.make(plan: plan, progress: progress, achievedDate: date(2026, 9, 2))
    h.check(achievement.goalName == "Autumn 10K", "achievement keeps the goal name")
    h.check(achievement.raceName == "10K", "achievement records the race distance name")
    h.check(achievement.weeksTrained == plan.weeks.count, "achievement records weeks trained")
    h.check(achievement.workoutsPlanned > 0, "achievement records planned workout count")
    h.check(achievement.metTargetFitness, "athlete who exceeded target fitness is marked as met")

    // Round-trips through JSON (it's stored as JSON on-device).
    let data = try JSONEncoder().encode(achievement)
    let decoded = try JSONDecoder().decode(GoalAchievement.self, from: data)
    h.check(decoded == achievement, "achievement round-trips through JSON")

    // No target time → counts as met (the goal was just reaching race day).
    let openGoal = Goal(race: .fiveK, raceDate: date(2026, 9, 1))
    let openPlan = try VDOTPlanGenerator().makePlan(goal: openGoal, fitness: fitRun, startDate: date(2026, 6, 1), calendar: cal)
    let openProgress = PlanProgress.make(plan: openPlan, completedRuns: [], asOf: date(2026, 9, 1), calendar: cal)
    let openAchievement = GoalAchievement.make(plan: openPlan, progress: openProgress)
    h.check(openAchievement.requiredVDOT == nil && openAchievement.metTargetFitness, "no-target goal counts as met")
}

// MARK: Long-run spacing

h.suite("Long-run spacing") {
    // Regression: keeping Mon–Wed free with 3 running days used to place the long run
    // on Saturday and stack another big run on Sunday (21.5 km Sat + 17 km Sun, no
    // recovery). The long run must now be the last running day of its week, so a rest
    // day always follows it and the biggest efforts are never back-to-back.
    let goal = Goal(race: .halfMarathon, raceDate: date(2027, 4, 25),
                    daysPerWeek: 3, restWeekdays: [2, 3, 4])  // keep Mon/Tue/Wed free
    let plan = try VDOTPlanGenerator().makePlan(
        goal: goal,
        fitness: FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 3_000, date: date(2026, 1, 1)),
        startDate: date(2026, 6, 1), calendar: cal
    )

    let longRuns = plan.allWorkouts.filter { $0.type == .longRun }
    h.check(!longRuns.isEmpty && longRuns.allSatisfy { [1, 7].contains(cal.component(.weekday, from: $0.date)) },
            "long run stays on a weekend day")

    // The long run is the last run of its week — nothing runs after it that week.
    var lastRunOK = true
    for week in plan.weeks where week.phase != .raceWeek {
        guard let long = week.workouts.first(where: { $0.type == .longRun }) else { continue }
        let laterRuns = week.workouts.filter { $0.type.isRunning && $0.date > long.date }
        if !laterRuns.isEmpty { lastRunOK = false }
    }
    h.check(lastRunOK, "the long run is the last running day of its week (recovery after)")

    // Same invariant for the default 5-day marathon plan (where the weekend is free).
    let marathon = try marathonPlan()
    var lastRunOK5 = true
    for week in marathon.weeks where week.phase != .raceWeek {
        guard let long = week.workouts.first(where: { $0.type == .longRun }) else { continue }
        if week.workouts.contains(where: { $0.type.isRunning && $0.date > long.date }) { lastRunOK5 = false }
    }
    h.check(lastRunOK5, "long run is the last run of the week at 5 days/week too")
}

// MARK: Workout steps

h.suite("Workout steps") {
    let zones = PaceZones(
        easySecPerKm: 330, marathonSecPerKm: 280, thresholdSecPerKm: 250,
        intervalSecPerKm: 225, repetitionSecPerKm: 210
    )

    // An unstructured run is one steady step at its own zone.
    let easy = PlannedWorkout(date: date(2026, 6, 1), type: .easy, distanceMeters: 8_000)
    let easySteps = WorkoutSteps.steps(for: easy, zones: zones)
    h.check(easySteps.count == 1 && easySteps[0].kind == .steady && easySteps[0].targetPaceSecPerKm == 330,
            "steady run → one step at easy pace")

    // A classic 6×800 interval session: warm-up + 6×[work + recovery] + cool-down = 14.
    let structure = WorkoutStructure(
        warmupMeters: 1_600, reps: 6, workMeters: 800, recoveryMeters: 400,
        cooldownMeters: 1_600, workType: .interval
    )
    let interval = PlannedWorkout(
        date: date(2026, 6, 2), type: .interval,
        distanceMeters: structure.totalMeters, structure: structure
    )
    let steps = WorkoutSteps.steps(for: interval, zones: zones)
    h.check(steps.count == 14, "6×800 intervals → 14 steps (got \(steps.count))")
    h.check(steps.first?.kind == .warmup && steps.last?.kind == .cooldown,
            "interval steps run warm-up first, cool-down last")
    h.check(steps[1].kind == .work && steps[1].label == "Rep 1/6" && steps[1].targetPaceSecPerKm == 225,
            "first work rep is labelled Rep 1/6 at interval pace")

    // activeStep advances with distance. 1600 warm-up, then rep 1 (800) ends at 2400.
    let inWarmup = WorkoutSteps.activeStep(for: interval, zones: zones, distanceCovered: 800)
    h.check(inWarmup?.kind == .warmup, "800 m into the run is still the warm-up")
    let inRep1 = WorkoutSteps.activeStep(for: interval, zones: zones, distanceCovered: 2_000)
    h.check(inRep1?.kind == .work && inRep1?.repNumber == 1, "2000 m in is the first work rep")

    // Past the total distance clamps to the final cool-down step.
    let past = WorkoutSteps.activeStep(for: interval, zones: zones, distanceCovered: 999_999)
    h.check(past?.kind == .cooldown, "past the end returns the cool-down step")
}

h.finish()
