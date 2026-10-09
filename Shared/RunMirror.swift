import Foundation

/// What the watch sends the iPhone about a run it records, through HealthKit's
/// workout mirroring (`HKWorkoutSession.sendToRemoteWorkoutSession`). The iPhone
/// shows it on the Lock Screen as a Live Activity, with Pause and Finish working
/// on the watch's run.
struct RunMirrorUpdate: Codable, Sendable, Equatable {
    var workoutTitle: String
    var goalName: String
    /// Today's planned pace window (sec/km), when the run follows the plan.
    var targetPaceLower: Double?
    var targetPaceUpper: Double?
    /// Planned distance (m); 0 for a free run.
    var targetDistanceMeters: Double

    var elapsedSeconds: TimeInterval
    var distanceMeters: Double
    var heartRate: Double
    /// Pace right now (sec/km), as the watch shows it.
    var paceSecPerKm: Double
    /// Average pace over the whole run (sec/km).
    var averagePaceSecPerKm: Double
    /// Paused by hand or by the watch's Auto-Pause.
    var isPaused: Bool

    /// The current step of a structured run, e.g. "Rep 3/6"; "" otherwise.
    var stepLabel: String
    var stepTargetPaceSecPerKm: Double
    var stepTargetDistanceMeters: Double

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> RunMirrorUpdate? {
        try? JSONDecoder().decode(RunMirrorUpdate.self, from: data)
    }
}
