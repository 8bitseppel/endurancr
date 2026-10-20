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

extension CompletedRun {
    /// The runs that count, from what Apple Health holds:
    /// - Recordings with hardly any running in them (under 200 m or a minute) are
    ///   left out: a start tapped by mistake, or a watch that started on its own.
    /// - Two recordings at the same time (the watch and the iPhone both running) are
    ///   one run: the one with the longer distance counts.
    public static func cleaned(_ runs: [CompletedRun]) -> [CompletedRun] {
        let real = runs.filter { $0.distanceMeters >= 200 && $0.durationSeconds >= 60 }
            .sorted { $0.distanceMeters > $1.distanceMeters }
        var kept: [CompletedRun] = []
        for run in real {
            let end = run.date.addingTimeInterval(run.durationSeconds)
            let overlap = kept.firstIndex { k in
                let kEnd = k.date.addingTimeInterval(k.durationSeconds)
                let shared = min(end, kEnd).timeIntervalSince(max(run.date, k.date))
                return shared > 0.5 * min(run.durationSeconds, k.durationSeconds)
            }
            if let i = overlap {
                // The watch's heart rate stays with the run when the iPhone's GPS
                // recording is the one that counts.
                if kept[i].averageHeartRate == nil { kept[i].averageHeartRate = run.averageHeartRate }
            } else {
                kept.append(run)
            }
        }
        return kept.sorted { $0.date < $1.date }
    }
}
