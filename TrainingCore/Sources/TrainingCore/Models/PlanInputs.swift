import Foundation

/// The minimal, regenerable inputs a plan is built from.
///
/// Persisting these (~1 KB) instead of the fully expanded calendar (~89 KB) keeps
/// on-device data small and makes recalculation and export cheap: the weeks are
/// deterministic from `(goal, fitness, startDate)` via the pure generator, and
/// adaptation (re-pacing, rescheduling, fatigue easing) is re-derived from HealthKit
/// on demand rather than stored.
public struct PlanInputs: Sendable, Equatable, Codable {
    public var goal: Goal
    public var fitness: FitnessSnapshot
    /// The date the plan was first generated from. Kept stable across regenerations
    /// so the week alignment and history don't shift when the plan is rebuilt.
    public var startDate: Date

    public init(goal: Goal, fitness: FitnessSnapshot, startDate: Date) {
        self.goal = goal
        self.fitness = fitness
        self.startDate = startDate
    }
}
