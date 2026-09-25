import Foundation
import SwiftData
import TrainingCore

/// Sample data for Simulator screenshots, switched on with the `-demo` launch
/// argument in Debug builds only. It seeds a marathon plan six weeks in, answers
/// HealthKit queries with runs that follow that plan, and skips the Health
/// permission sheet. Release builds compile it out, so it can't reach TestFlight.
///
/// `-demoScreen <name>` opens a specific screen: `run` (live run), `summary`
/// (post-run summary, watch only), `progress` or `plan` (iPhone tabs).
enum DemoMode {
    static var isOn: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }

    static var screen: String? {
        guard isOn else { return nil }
        return UserDefaults.standard.string(forKey: "demoScreen")
    }

    static var inputs: PlanInputs {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Monday six weeks ago, so week 1 is a full week.
        let thisMonday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let start = calendar.date(byAdding: .day, value: -42, to: thisMonday)!
        let race = calendar.date(byAdding: .day, value: 160, to: today)!
        let goal = Goal(
            name: "Hamburg Marathon",
            race: .marathon,
            raceDate: race,
            targetTimeSeconds: 3 * 3600 + 45 * 60,
            daysPerWeek: 5,
            restWeekdays: [2]
        )
        // A 10K in 49:30 about two months ago.
        let fitness = FitnessSnapshot(
            distanceMeters: 10_000,
            timeSeconds: 49 * 60 + 30,
            date: calendar.date(byAdding: .day, value: -60, to: today)!
        )
        return PlanInputs(goal: goal, fitness: fitness, startDate: start)
    }

    static var plan: TrainingPlan? {
        let inputs = inputs
        return try? VDOTPlanGenerator().makePlan(
            goal: inputs.goal, fitness: inputs.fitness,
            startDate: inputs.startDate, calendar: .current
        )
    }

    /// Today's planned session, for the live run screens.
    static var todaysWorkout: PlannedWorkout? {
        plan?.allWorkouts.first { Calendar.current.isDateInToday($0.date) && $0.type != .rest }
    }

    /// Runs that followed the plan up to yesterday, a little off here and there.
    static var runs: [CompletedRun] {
        guard let plan else { return [] }
        let today = Calendar.current.startOfDay(for: .now)
        return plan.allWorkouts.enumerated().compactMap { index, workout in
            guard workout.type != .rest, workout.date < today, index % 9 != 4 else { return nil }
            let pace = workout.targetPaceSecPerKm.map { ($0.lowerBound + $0.upperBound) / 2 } ?? 330
            let distance = workout.distanceMeters * (index % 3 == 0 ? 1.02 : 0.99)
            return CompletedRun(
                date: workout.date.addingTimeInterval(7 * 3600),
                distanceMeters: distance,
                durationSeconds: distance / 1_000 * pace,
                averageHeartRate: 138 + Double(index % 5) * 3
            )
        }
    }

    /// Replaces whatever plan is stored with the demo plan.
    @MainActor
    static func seed(_ container: ModelContainer) {
        guard isOn else { return }
        let context = container.mainContext
        try? context.delete(model: StoredPlan.self)
        context.insert(StoredPlan(inputs: inputs))
        try? context.save()
    }
}
