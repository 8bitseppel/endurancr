import Foundation

/// How much someone already runs, from their recent runs in Apple Health: the
/// weekly distance and the longest run. A plan is sized from it, as Jack Tupper
/// Daniels and Pete Pfitzinger both size a plan from current mileage, so an
/// experienced runner doesn't start at a beginner's volume and spend weeks
/// building back up to where they already are.
///
/// Kept with the plan's inputs, so the plan regenerates the same every time. A
/// plan can hold more than one: the first from when it was made, and one more
/// each time the athlete accepts a step up (`TrainingBuddy`), each counting from
/// its own week on.
public struct TrainingHistory: Sendable, Equatable, Codable {
    /// When it was read; it shapes the plan from this week on.
    public var asOf: Date
    /// Average distance a week over the weeks read.
    public var weeklyMeters: Double
    /// The longest single run in the last 30 days.
    public var longestMeters: Double
    /// Average runs a week, shown for reference; the plan keeps the days chosen.
    public var runsPerWeek: Double
    /// How many weeks it's averaged over.
    public var weeks: Int

    public init(asOf: Date, weeklyMeters: Double, longestMeters: Double, runsPerWeek: Double, weeks: Int) {
        self.asOf = asOf
        self.weeklyMeters = weeklyMeters
        self.longestMeters = longestMeters
        self.runsPerWeek = runsPerWeek
        self.weeks = weeks
    }

    /// How far back it reads.
    public static let lookbackWeeks = 6
    /// Less than this a week isn't a history to size a plan from: a beginner's plan
    /// stays exactly as it was.
    public static let minimumWeeklyMeters: Double = 10_000

    /// From the runs of the last six weeks before `asOf`. The weekly figure is the
    /// average over the weeks since the first of those runs (at least three), so a
    /// fortnight of running doesn't read as six weeks of it, and a single long week
    /// doesn't read as a habit. `nil` when there's too little to go on.
    public static func make(runs: [CompletedRun], asOf: Date, calendar: Calendar = .current) -> TrainingHistory? {
        let today = calendar.startOfDay(for: asOf)
        guard let from = calendar.date(byAdding: .day, value: -7 * lookbackWeeks, to: today),
              let monthAgo = calendar.date(byAdding: .day, value: -30, to: today) else { return nil }
        let recent = CompletedRun.cleaned(runs).filter { $0.date >= from && $0.date < today && $0.distanceMeters > 0 }
        guard let first = recent.map(\.date).min() else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: today).day ?? 0
        let weeks = min(Double(lookbackWeeks), max(3, Double(days) / 7))
        let total = recent.reduce(0) { $0 + $1.distanceMeters }
        let weekly = total / weeks
        guard weekly >= minimumWeeklyMeters else { return nil }
        let longest = recent.filter { $0.date >= monthAgo }.map(\.distanceMeters).max() ?? 0
        return TrainingHistory(asOf: today, weeklyMeters: weekly, longestMeters: longest,
                               runsPerWeek: Double(recent.count) / weeks, weeks: Int(weeks.rounded()))
    }
}
