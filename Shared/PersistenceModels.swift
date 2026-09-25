import Foundation
import SwiftData
import TrainingCore

/// SwiftData store for the current plan. We persist only the regenerable
/// `PlanInputs` (~1 KB) as JSON rather than the fully expanded calendar (~89 KB):
/// the weeks are deterministic from the inputs via the pure generator, and
/// adaptation is re-derived from HealthKit at runtime. Everything is on-device —
/// no cloud. The persistence layer stays decoupled from the training logic.
@Model
final class StoredPlan {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    private var inputsData: Data

    init(inputs: PlanInputs, id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.inputsData = (try? JSONEncoder().encode(inputs)) ?? Data()
    }

    /// The decoded inputs, or `nil` if the stored data is unreadable.
    var inputs: PlanInputs? {
        get { try? JSONDecoder().decode(PlanInputs.self, from: inputsData) }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else { return }
            inputsData = data
            updatedAt = .now
        }
    }

    /// Builds the app's SwiftData container. If the on-disk store can't be opened
    /// (e.g. a pre-release schema change like the inputs refactor), the store is
    /// wiped and rebuilt — the plan is regenerable (re-onboard / adapt from Health),
    /// so nothing important is lost and the app doesn't crash on launch.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([StoredPlan.self, AchievedGoal.self])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            let url = config.url
            let fm = FileManager.default
            for suffix in ["", "-wal", "-shm"] {
                try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create SwiftData container after reset: \(error)")
            }
        }
    }

    /// The base plan regenerated from the stored inputs. Runtime adaptation
    /// (re-pacing, rescheduling, fatigue easing) is layered by `PlanCoordinator`
    /// and is not stored; this is enough for read-only surfaces like the watch's
    /// "today" view.
    var plan: TrainingPlan? {
        try? inputs?.makePlan(calendar: .current)
    }
}

/// A completed goal, kept as a permanent local record after the athlete confirms
/// it done. Stores the pure `GoalAchievement` summary as JSON — small, on-device,
/// no cloud. Survives deleting/replacing the active plan, so past achievements
/// accumulate independently of whatever the athlete is training for now.
@Model
final class AchievedGoal {
    @Attribute(.unique) var id: UUID
    /// When the goal was marked achieved — used to sort the achievements list.
    var achievedAt: Date
    private var achievementData: Data

    init(achievement: GoalAchievement) {
        self.id = achievement.id
        self.achievedAt = achievement.achievedDate
        self.achievementData = (try? JSONEncoder().encode(achievement)) ?? Data()
    }

    /// The decoded achievement summary, or `nil` if the stored data is unreadable.
    var achievement: GoalAchievement? {
        try? JSONDecoder().decode(GoalAchievement.self, from: achievementData)
    }
}
