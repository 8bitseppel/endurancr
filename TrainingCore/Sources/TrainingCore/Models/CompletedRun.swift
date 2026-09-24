import Foundation

/// A run the app actually recorded (mirrors an HKWorkout). HealthKit remains the
/// source of truth on-device; this is the value type the engine reasons about.
public struct CompletedRun: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var date: Date
    public var distanceMeters: Double
    public var durationSeconds: Double
    public var averageHeartRate: Double?
    /// The planned workout this run fulfilled, if it was matched to the plan.
    public var plannedWorkoutID: UUID?

    public init(
        id: UUID = UUID(),
        date: Date,
        distanceMeters: Double,
        durationSeconds: Double,
        averageHeartRate: Double? = nil,
        plannedWorkoutID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averageHeartRate = averageHeartRate
        self.plannedWorkoutID = plannedWorkoutID
    }

    /// Average pace in seconds per kilometer. Returns `.infinity` for a zero-distance run.
    public var averagePaceSecPerKm: Double {
        guard distanceMeters > 0 else { return .infinity }
        return durationSeconds / (distanceMeters / 1_000)
    }
}
