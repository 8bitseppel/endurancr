import Foundation
import TrainingCore

/// Shared test fixtures. Kept out of `main.swift` because top-level code in an
/// executable target is main-actor isolated under Swift 6; these stay nonisolated.
enum Fixtures {
    static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func marathonPlan(daysPerWeek: Int = 5) throws -> TrainingPlan {
        let goal = Goal(race: .marathon, raceDate: date(2027, 4, 25), daysPerWeek: daysPerWeek)
        let fitness = FitnessSnapshot(distanceMeters: 10_000, timeSeconds: 45 * 60, date: date(2026, 1, 1))
        return try VDOTPlanGenerator().makePlan(
            goal: goal, fitness: fitness,
            startDate: date(2026, 1, 1), calendar: utcCalendar
        )
    }
}
