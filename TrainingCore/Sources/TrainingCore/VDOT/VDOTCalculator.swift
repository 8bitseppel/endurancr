import Foundation

/// Computes VDOT (Daniels' pseudo-VO₂max) from race performances, predicts
/// equivalent race times, and derives training paces.
///
/// Based on the Daniels–Gilbert equations (Jack Daniels, *Daniels' Running
/// Formula*). Daniels' published VDOT tables are themselves generated from these
/// same formulas, so results here reproduce those tables to within rounding.
public struct VDOTCalculator: Sendable {
    public init() {}

    // MARK: Daniels–Gilbert primitives

    /// Fraction of VO₂max a runner can sustain for `minutes` of racing.
    /// %VO2max = 0.8 + 0.1894393·e^(-0.012778·t) + 0.2989558·e^(-0.1932605·t)
    static func percentVO2Max(minutes t: Double) -> Double {
        0.8
            + 0.1894393 * exp(-0.012778 * t)
            + 0.2989558 * exp(-0.1932605 * t)
    }

    /// Oxygen cost (ml/kg/min) of running at velocity `v` in meters/minute.
    /// VO2 = -4.60 + 0.182258·v + 0.000104·v²
    static func vo2Cost(velocity v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    /// Inverse of `vo2Cost`: the velocity (m/min) that costs the given VO₂.
    /// Solves the quadratic for its positive root.
    static func velocity(forVO2 vo2: Double) -> Double {
        let a = 0.000104
        let b = 0.182258
        let c = -4.60 - vo2
        return (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
    }

    // MARK: Public API

    /// VDOT implied by covering `distanceMeters` in `timeSeconds`.
    public func vdot(distanceMeters: Double, timeSeconds: Double) -> Double {
        precondition(distanceMeters > 0 && timeSeconds > 0, "distance and time must be positive")
        let minutes = timeSeconds / 60.0
        let velocity = distanceMeters / minutes
        return Self.vo2Cost(velocity: velocity) / Self.percentVO2Max(minutes: minutes)
    }

    /// Predicted race time (seconds) for `distanceMeters` at the given `vdot`.
    ///
    /// VDOT is monotonically decreasing in race time for a fixed distance, so we
    /// bisect on time until the implied VDOT matches the target.
    public func predictedTimeSeconds(distanceMeters: Double, vdot: Double) -> Double {
        precondition(distanceMeters > 0 && vdot > 0, "distance and vdot must be positive")
        var lo = 0.5          // minutes (very fast)
        var hi = 100_000.0    // minutes (absurdly slow) — brackets any human race
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            let velocity = distanceMeters / mid
            let implied = Self.vo2Cost(velocity: velocity) / Self.percentVO2Max(minutes: mid)
            if implied > vdot {
                lo = mid   // need more time to lower the implied VDOT
            } else {
                hi = mid
            }
        }
        return (lo + hi) / 2 * 60.0
    }

    /// Equivalent race time at another distance, preserving VDOT.
    public func equivalentTimeSeconds(
        fromDistanceMeters: Double,
        timeSeconds: Double,
        toDistanceMeters: Double
    ) -> Double {
        let v = vdot(distanceMeters: fromDistanceMeters, timeSeconds: timeSeconds)
        return predictedTimeSeconds(distanceMeters: toDistanceMeters, vdot: v)
    }

    // MARK: Training paces

    /// Training-intensity fractions of VDOT for each zone. Easy/Marathon/Threshold/
    /// Interval are taken as representative points within Daniels' ranges. Repetition
    /// is defined as a fixed increment faster than interval velocity (Daniels bases
    /// R on faster-than-VO2max speed rather than an oxygen cost).
    private enum Intensity {
        static let easy = 0.70        // Daniels E range ≈ 0.59–0.74
        static let marathon = 0.84    // Daniels M ≈ 0.75–0.84
        static let threshold = 0.88   // Daniels T ≈ 0.83–0.88
        static let interval = 0.98    // Daniels I ≈ 0.95–1.00
        static let repetitionVelocityBoost = 1.06 // R velocity ≈ 6% faster than I
    }

    /// Seconds per kilometer for running at `fraction` of VDOT.
    private func secPerKm(atFraction fraction: Double, vdot: Double) -> Double {
        let velocity = Self.velocity(forVO2: fraction * vdot) // m/min
        return 60_000.0 / velocity                            // sec per km
    }

    /// Full set of training paces for a VDOT value.
    public func paceZones(forVDOT vdot: Double) -> PaceZones {
        let intervalVelocity = Self.velocity(forVO2: Intensity.interval * vdot)
        let repetitionSecPerKm = 60_000.0 / (intervalVelocity * Intensity.repetitionVelocityBoost)
        return PaceZones(
            easySecPerKm: secPerKm(atFraction: Intensity.easy, vdot: vdot),
            marathonSecPerKm: secPerKm(atFraction: Intensity.marathon, vdot: vdot),
            thresholdSecPerKm: secPerKm(atFraction: Intensity.threshold, vdot: vdot),
            intervalSecPerKm: secPerKm(atFraction: Intensity.interval, vdot: vdot),
            repetitionSecPerKm: repetitionSecPerKm
        )
    }
}
