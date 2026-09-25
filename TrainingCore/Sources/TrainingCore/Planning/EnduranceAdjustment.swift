import Foundation

/// How much of a short race's fitness to hold back for a long goal race.
///
/// VDOT from an all-out 10 km is a good measure of speed, so easy, threshold and
/// interval paces use it as is. Its marathon prediction, though, assumes the
/// endurance to go the distance, which a shorter race doesn't show (Jack Tupper
/// Daniels makes the same caveat). So marathon pace and the race prediction start
/// a few VDOT points lower, and completed long runs earn the points back.
public enum EnduranceAdjustment {
    /// Most points ever held back.
    public static let maxPoints = 3.0
    /// Goals shorter than this (5 km, 10 km) are speed races: nothing held back.
    public static let minimumGoalMeters = 15_000.0

    /// Points held back before any long run: grows with how much longer the goal is
    /// than the race the fitness came from (about 1.5 for a half marathon from a
    /// 10 km race, about 2.8 for a marathon from 11.8 km), capped at `maxPoints`.
    public static func basePoints(fitnessDistanceMeters: Double, goalMeters: Double) -> Double {
        guard goalMeters >= minimumGoalMeters, fitnessDistanceMeters > 0,
              fitnessDistanceMeters < goalMeters else { return 0 }
        let points = 1.5 * log2(goalMeters / fitnessDistanceMeters)
        let credit = credit(longestRunMeters: fitnessDistanceMeters, goalMeters: goalMeters)
        return (min(maxPoints, points) * (1 - credit) * 10).rounded() / 10
    }

    /// The long run that earns every point back: 25 km for a marathon (the plan's
    /// peak long run, about Jack Tupper Daniels' 2.5 hour cap at easy pace), 85% of
    /// the distance for shorter goals (about 18 km for a half marathon).
    public static func fullCreditMeters(goalMeters: Double) -> Double {
        min(25_000, goalMeters * 0.85)
    }

    /// Share of the points earned back by the longest recent run, from 0 (at or
    /// below 55% of the full-credit distance) to 1 (at the full-credit distance).
    public static func credit(longestRunMeters: Double, goalMeters: Double) -> Double {
        let full = fullCreditMeters(goalMeters: goalMeters)
        let start = full * 0.55
        return min(1, max(0, (longestRunMeters - start) / (full - start)))
    }
}
