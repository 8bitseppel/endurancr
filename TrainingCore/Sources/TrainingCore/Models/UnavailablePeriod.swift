import Foundation

/// A stretch of days the athlete can't train — vacation, travel, illness, work.
/// Both ends are inclusive and compared at day granularity. The adaptation engine
/// blanks any future workout that lands inside a period so the calendar reflects
/// reality instead of prescribing runs that won't happen.
public struct UnavailablePeriod: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    /// Short label shown on the blanked days, e.g. "Vacation".
    public var reason: String

    public init(id: UUID = UUID(), start: Date, end: Date, reason: String = "Unavailable") {
        self.id = id
        self.start = start
        self.end = end
        self.reason = reason
    }

    /// True if `date` falls on or between `start` and `end` (inclusive, by day).
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }

    /// Number of calendar days the period spans (inclusive).
    public func dayCount(calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)).day ?? 0
        return max(0, days) + 1
    }
}
