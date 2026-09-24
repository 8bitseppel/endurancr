import Foundation

/// A finished goal, captured as a self-contained summary of what the athlete
/// achieved. Pure value data (no device dependencies) so it can be built in the
/// engine, stored locally, and rendered without recomputation. Snapshotted at the
/// moment the goal is marked complete — it never changes afterward.
public struct GoalAchievement: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    /// Name the athlete gave the goal, or the race distance's name as a fallback.
    public var goalName: String
    /// The race distance's display name (e.g. "10K", "Marathon").
    public var raceName: String
    public var raceDistanceMeters: Double
    public var raceDate: Date
    /// When the athlete confirmed the goal complete.
    public var achievedDate: Date
    public var targetTimeSeconds: Double?
    /// Fitness (VDOT) reached by the end of the plan.
    public var finalVDOT: Double
    /// The VDOT the target time required, if a target was set.
    public var requiredVDOT: Double?

    // Training summary over the plan.
    public var weeksTrained: Int
    public var totalDistanceMeters: Double
    public var workoutsCompleted: Int
    public var workoutsPlanned: Int

    public init(
        id: UUID = UUID(),
        goalName: String,
        raceName: String,
        raceDistanceMeters: Double,
        raceDate: Date,
        achievedDate: Date = .now,
        targetTimeSeconds: Double? = nil,
        finalVDOT: Double,
        requiredVDOT: Double? = nil,
        weeksTrained: Int,
        totalDistanceMeters: Double,
        workoutsCompleted: Int,
        workoutsPlanned: Int
    ) {
        self.id = id
        self.goalName = goalName
        self.raceName = raceName
        self.raceDistanceMeters = raceDistanceMeters
        self.raceDate = raceDate
        self.achievedDate = achievedDate
        self.targetTimeSeconds = targetTimeSeconds
        self.finalVDOT = finalVDOT
        self.requiredVDOT = requiredVDOT
        self.weeksTrained = weeksTrained
        self.totalDistanceMeters = totalDistanceMeters
        self.workoutsCompleted = workoutsCompleted
        self.workoutsPlanned = workoutsPlanned
    }

    /// Whether the athlete finished at or above the fitness their target required.
    /// `true` when no target time was set (the goal was just "get to race day").
    public var metTargetFitness: Bool {
        guard let requiredVDOT else { return true }
        return finalVDOT >= requiredVDOT
    }

    /// Fraction of planned running workouts that were completed, clamped to [0, 1].
    public var completionFraction: Double {
        guard workoutsPlanned > 0 else { return 0 }
        return min(1, max(0, Double(workoutsCompleted) / Double(workoutsPlanned)))
    }

    /// Builds an achievement snapshot from a finished plan and its progress.
    public static func make(
        plan: TrainingPlan,
        progress: PlanProgress,
        achievedDate: Date = .now
    ) -> GoalAchievement {
        GoalAchievement(
            goalName: plan.goal.displayName,
            raceName: plan.goal.race.displayName,
            raceDistanceMeters: plan.goal.race.meters,
            raceDate: plan.goal.raceDate,
            achievedDate: achievedDate,
            targetTimeSeconds: plan.goal.targetTimeSeconds,
            finalVDOT: plan.vdot,
            requiredVDOT: progress.requiredVDOT,
            weeksTrained: plan.weeks.count,
            totalDistanceMeters: progress.completedDistanceMeters,
            workoutsCompleted: progress.workoutsCompleted,
            workoutsPlanned: plan.allWorkouts.filter(\.type.isRunning).count
        )
    }
}
