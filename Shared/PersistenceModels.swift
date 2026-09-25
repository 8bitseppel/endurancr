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
    /// The phone's adapted current and next week (`AdaptedWeeks`), set only on the
    /// watch. Optional so existing stores migrate without a reset.
    private var adaptedData: Data? = nil

    init(inputs: PlanInputs, adapted: AdaptedWeeks? = nil, id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.inputsData = (try? JSONEncoder().encode(inputs)) ?? Data()
        self.adaptedData = adapted.flatMap { try? JSONEncoder().encode($0) }
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

    /// The plan regenerated from the stored inputs. On the watch, the phone's
    /// adapted weeks replace their base versions, so today's run and the week ring
    /// match what the iPhone shows. On the phone, adaptation is layered at runtime
    /// by `PlanCoordinator` instead.
    var plan: TrainingPlan? {
        guard var plan = try? inputs?.makePlan(calendar: .current) else { return nil }
        if let adaptedData, let adapted = try? JSONDecoder().decode(AdaptedWeeks.self, from: adaptedData) {
            plan = adapted.applied(to: plan)
        }
        return plan
    }
}

/// The phone's adapted version of the weeks around today (re-paced, eased for
/// fatigue, redistributed, vacations blanked), sent to the watch with the inputs.
/// Only a couple of weeks: the full calendar is too large for WatchConnectivity's
/// application context, and the watch only shows today and this week.
struct AdaptedWeeks: Codable, Sendable {
    var vdot: Double
    var paceZones: PaceZones
    var weeks: [TrainingWeek]

    /// The current week and the next one from `plan`.
    init?(plan: TrainingPlan, asOf now: Date = .now) {
        guard let current = plan.weeks.lastIndex(where: { $0.startDate <= now }) else { return nil }
        vdot = plan.vdot
        paceZones = plan.paceZones
        weeks = Array(plan.weeks[current..<min(current + 2, plan.weeks.count)])
    }

    /// `plan` with these weeks in place of the ones of the same index.
    func applied(to plan: TrainingPlan) -> TrainingPlan {
        var plan = plan
        plan.vdot = vdot
        plan.paceZones = paceZones
        for week in weeks {
            if let i = plan.weeks.firstIndex(where: { $0.index == week.index }) { plan.weeks[i] = week }
        }
        return plan
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
