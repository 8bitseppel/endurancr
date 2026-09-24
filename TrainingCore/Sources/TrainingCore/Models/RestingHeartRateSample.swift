import Foundation

/// A single resting-heart-rate reading (mirrors an HKQuantitySample of type
/// `.restingHeartRate`). HealthKit publishes at most one per day; the engine uses
/// a series of these to detect fatigue — a rising resting HR is a classic sign of
/// incomplete recovery, illness, or accumulated training stress.
public struct RestingHeartRateSample: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var date: Date
    /// Beats per minute.
    public var bpm: Double

    public init(id: UUID = UUID(), date: Date, bpm: Double) {
        self.id = id
        self.date = date
        self.bpm = bpm
    }
}
