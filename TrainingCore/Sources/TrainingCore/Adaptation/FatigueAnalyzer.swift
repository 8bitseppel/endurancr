import Foundation

/// The result of a fatigue assessment: which recovery signals fired, plus the
/// numbers behind them so the UI can explain *why* a session was eased.
public struct FatigueAssessment: Sendable, Equatable, Codable {
    /// A single physiological warning sign.
    public enum Signal: String, Sendable, Codable, CaseIterable {
        /// Recent resting HR sits meaningfully above the athlete's baseline.
        case elevatedRestingHeartRate
        /// Aerobic efficiency (speed per heartbeat) has dropped across recent runs —
        /// the athlete is working harder for the same pace.
        case reducedAerobicEfficiency
    }

    public var signals: [Signal]
    public var restingBaselineBpm: Double?
    public var restingRecentBpm: Double?
    public var efficiencyBaseline: Double?
    public var efficiencyRecent: Double?

    public init(
        signals: [Signal] = [],
        restingBaselineBpm: Double? = nil,
        restingRecentBpm: Double? = nil,
        efficiencyBaseline: Double? = nil,
        efficiencyRecent: Double? = nil
    ) {
        self.signals = signals
        self.restingBaselineBpm = restingBaselineBpm
        self.restingRecentBpm = restingRecentBpm
        self.efficiencyBaseline = efficiencyBaseline
        self.efficiencyRecent = efficiencyRecent
    }

    public var isFatigued: Bool { !signals.isEmpty }

    /// A short, human-readable explanation suitable for a workout note.
    public var summary: String {
        var parts: [String] = []
        if signals.contains(.elevatedRestingHeartRate),
           let base = restingBaselineBpm, let recent = restingRecentBpm {
            parts.append("resting HR \(Int(recent.rounded())) vs \(Int(base.rounded())) bpm baseline")
        }
        if signals.contains(.reducedAerobicEfficiency),
           let base = efficiencyBaseline, let recent = efficiencyRecent, base > 0 {
            let drop = Int(((base - recent) / base * 100).rounded())
            parts.append("aerobic efficiency down \(drop)%")
        }
        return parts.isEmpty ? "no fatigue detected" : parts.joined(separator: ", ")
    }
}

/// Detects fatigue from two independent, deterministic signals derived purely from
/// data the app already records: daily resting heart rate and per-run heart rate.
///
/// It compares a **recent** window against an earlier **baseline** window. Both
/// signals are conservative — they require a minimum amount of baseline data before
/// firing, so a sparse history never produces spurious "you're tired" verdicts.
public struct FatigueAnalyzer: Sendable {
    /// Resting HR is "elevated" if the recent average is at least this fraction
    /// above baseline …
    public var restingElevationFraction: Double
    /// … or at least this many bpm above baseline (whichever triggers first).
    public var restingElevationBpm: Double
    /// Aerobic efficiency counts as "reduced" if recent efficiency has fallen by at
    /// least this fraction below baseline.
    public var efficiencyDropFraction: Double

    /// Days back from `asOf` treated as the recent window (exclusive of older data).
    public var recentWindowDays: Int
    /// Days back from `asOf` covered by the baseline window (ends where recent begins).
    public var baselineWindowDays: Int

    /// Minimum resting-HR readings needed in the baseline window to trust it.
    public var minBaselineRestingSamples: Int
    /// Minimum HR-carrying runs needed in the baseline window to trust efficiency.
    public var minBaselineRuns: Int
    /// Runs shorter than this (meters) are ignored for efficiency (too noisy).
    public var minRunDistanceMeters: Double

    public init(
        restingElevationFraction: Double = 0.07,
        restingElevationBpm: Double = 5,
        efficiencyDropFraction: Double = 0.05,
        recentWindowDays: Int = 7,
        baselineWindowDays: Int = 28,
        minBaselineRestingSamples: Int = 5,
        minBaselineRuns: Int = 3,
        minRunDistanceMeters: Double = 3_000
    ) {
        self.restingElevationFraction = restingElevationFraction
        self.restingElevationBpm = restingElevationBpm
        self.efficiencyDropFraction = efficiencyDropFraction
        self.recentWindowDays = recentWindowDays
        self.baselineWindowDays = baselineWindowDays
        self.minBaselineRestingSamples = minBaselineRestingSamples
        self.minBaselineRuns = minBaselineRuns
        self.minRunDistanceMeters = minRunDistanceMeters
    }

    /// Aerobic efficiency for a run: speed (m/s) per heartbeat. Higher is fitter;
    /// a decline means more effort for the same pace. `nil` if HR/distance missing.
    public func efficiency(of run: CompletedRun) -> Double? {
        guard let hr = run.averageHeartRate, hr > 0,
              run.distanceMeters > 0, run.durationSeconds > 0 else { return nil }
        let speed = run.distanceMeters / run.durationSeconds
        return speed / hr
    }

    public func assess(
        restingHeartRates: [RestingHeartRateSample],
        completedRuns: [CompletedRun],
        asOf: Date,
        calendar: Calendar = .current
    ) -> FatigueAssessment {
        let asOfDay = calendar.startOfDay(for: asOf)
        let recentStart = calendar.date(byAdding: .day, value: -recentWindowDays, to: asOfDay) ?? asOfDay
        let baselineStart = calendar.date(byAdding: .day, value: -baselineWindowDays, to: asOfDay) ?? asOfDay

        var signals: [FatigueAssessment.Signal] = []

        // MARK: Resting-HR signal
        let restingBaseline = restingHeartRates
            .filter { $0.date >= baselineStart && $0.date < recentStart }
            .map(\.bpm)
        let restingRecent = restingHeartRates
            .filter { $0.date >= recentStart && $0.date <= asOf }
            .map(\.bpm)

        var baselineBpm: Double?
        var recentBpm: Double?
        if restingBaseline.count >= minBaselineRestingSamples, !restingRecent.isEmpty {
            let base = median(restingBaseline)
            let recent = mean(restingRecent)
            baselineBpm = base
            recentBpm = recent
            if recent - base >= restingElevationBpm || recent >= base * (1 + restingElevationFraction) {
                signals.append(.elevatedRestingHeartRate)
            }
        }

        // MARK: Aerobic-efficiency signal
        let eligible = completedRuns.filter { $0.distanceMeters >= minRunDistanceMeters }
        let baselineEff = eligible
            .filter { $0.date >= baselineStart && $0.date < recentStart }
            .compactMap(efficiency)
        let recentEff = eligible
            .filter { $0.date >= recentStart && $0.date <= asOf }
            .compactMap(efficiency)

        var baseEfficiency: Double?
        var recentEfficiency: Double?
        if baselineEff.count >= minBaselineRuns, !recentEff.isEmpty {
            let base = median(baselineEff)
            let recent = median(recentEff)
            baseEfficiency = base
            recentEfficiency = recent
            if recent <= base * (1 - efficiencyDropFraction) {
                signals.append(.reducedAerobicEfficiency)
            }
        }

        return FatigueAssessment(
            signals: signals,
            restingBaselineBpm: baselineBpm,
            restingRecentBpm: recentBpm,
            efficiencyBaseline: baseEfficiency,
            efficiencyRecent: recentEfficiency
        )
    }

    // MARK: - Statistics helpers

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}
