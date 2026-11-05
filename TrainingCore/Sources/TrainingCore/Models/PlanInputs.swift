import Foundation

/// The minimal, regenerable inputs a plan is built from.
///
/// Persisting these (~1 KB) instead of the fully expanded calendar (~89 KB) keeps
/// on-device data small and makes recalculation and export cheap: the weeks are
/// deterministic from `(goal, fitness, startDate, daySwaps)` via the pure generator,
/// and adaptation (re-pacing, rescheduling, fatigue easing) is re-derived from
/// HealthKit on demand rather than stored.
public struct PlanInputs: Sendable, Equatable, Codable {
    public var goal: Goal
    public var fitness: FitnessSnapshot
    /// The date the plan was first generated from. Kept stable across regenerations
    /// so the week alignment and history don't shift when the plan is rebuilt.
    public var startDate: Date
    /// Days the athlete swapped by dragging in the plan, replayed in order.
    public var daySwaps: [DaySwap]
    /// How much the athlete already ran when the plan was made, and at each step up
    /// since (`TrainingHistory`). Empty for a beginner, or a plan from before 1.9.0.
    public var history: [TrainingHistory]

    public init(goal: Goal, fitness: FitnessSnapshot, startDate: Date, daySwaps: [DaySwap] = [],
                history: [TrainingHistory] = []) {
        self.goal = goal
        self.fitness = fitness
        self.startDate = startDate
        self.daySwaps = daySwaps
        self.history = history
    }

    private enum CodingKeys: String, CodingKey { case goal, fitness, startDate, daySwaps, history }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decode(Goal.self, forKey: .goal)
        fitness = try c.decode(FitnessSnapshot.self, forKey: .fitness)
        startDate = try c.decode(Date.self, forKey: .startDate)
        // Older stores and backups predate swaps and the training history.
        daySwaps = try c.decodeIfPresent([DaySwap].self, forKey: .daySwaps) ?? []
        history = try c.decodeIfPresent([TrainingHistory].self, forKey: .history) ?? []
    }

    /// Builds the plan these inputs describe: the generated schedule with the
    /// athlete's day swaps applied.
    public func makePlan(calendar: Calendar = .current) throws -> TrainingPlan {
        try VDOTPlanGenerator()
            .makePlan(goal: goal, fitness: fitness, startDate: startDate, history: history, calendar: calendar)
            .applyingSwaps(daySwaps, calendar: calendar)
    }
}
