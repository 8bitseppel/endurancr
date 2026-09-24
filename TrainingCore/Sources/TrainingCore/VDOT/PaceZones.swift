import Foundation

/// Training paces derived from a VDOT value, expressed as seconds per kilometer.
/// Ordered slowest → fastest: easy > marathon > threshold > interval > repetition.
public struct PaceZones: Sendable, Equatable, Codable {
    /// Easy / recovery running (conversational).
    public let easySecPerKm: Double
    /// Goal marathon-race pace.
    public let marathonSecPerKm: Double
    /// Threshold / tempo ("comfortably hard").
    public let thresholdSecPerKm: Double
    /// Interval pace (~ vVO2max), for VO2max sessions.
    public let intervalSecPerKm: Double
    /// Repetition pace, for speed/economy work.
    public let repetitionSecPerKm: Double

    public init(
        easySecPerKm: Double,
        marathonSecPerKm: Double,
        thresholdSecPerKm: Double,
        intervalSecPerKm: Double,
        repetitionSecPerKm: Double
    ) {
        self.easySecPerKm = easySecPerKm
        self.marathonSecPerKm = marathonSecPerKm
        self.thresholdSecPerKm = thresholdSecPerKm
        self.intervalSecPerKm = intervalSecPerKm
        self.repetitionSecPerKm = repetitionSecPerKm
    }

    /// The pace (sec/km) that a given workout type is run at. Long runs, easy runs,
    /// rest, and recovery jogs all run at easy pace; each quality type maps to its zone.
    public func pace(for type: WorkoutType) -> Double {
        switch type {
        case .easy, .longRun, .rest: return easySecPerKm
        case .marathonPace: return marathonSecPerKm
        case .threshold: return thresholdSecPerKm
        case .interval: return intervalSecPerKm
        case .repetitionSpeed: return repetitionSecPerKm
        case .raceDay: return marathonSecPerKm
        }
    }
}
