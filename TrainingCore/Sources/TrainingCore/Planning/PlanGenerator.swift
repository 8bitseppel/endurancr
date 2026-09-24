import Foundation

public enum PlanError: Error, Equatable {
    /// The race date is too close to the start date to build a meaningful plan.
    case raceTooSoon(daysAvailable: Int, minimum: Int)
    case invalidFitness
    /// The goal asks for more running days than the rest-weekday rules leave free.
    /// `available` is `7 - restWeekdays.count`.
    case daysPerWeekExceedsAvailable(requested: Int, available: Int)
}

/// Strategy for turning a goal + current fitness into a periodized plan.
///
/// Kept as a protocol so the whole training methodology (Daniels/VDOT today,
/// Hansons/Pfitzinger later) can be swapped without touching the app or the
/// adaptation loop.
public protocol PlanGenerator: Sendable {
    /// Builds a plan. Running days per week and rest-weekday rules are read from
    /// `goal` so the plan is fully determined by its persisted inputs.
    func makePlan(
        goal: Goal,
        fitness: FitnessSnapshot,
        startDate: Date,
        calendar: Calendar
    ) throws -> TrainingPlan
}
