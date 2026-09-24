import Foundation

/// The user's race goal: what and when. `targetTimeSeconds` is optional — when set
/// it can pull the plan's paces slightly toward the goal; otherwise paces come
/// purely from current fitness.
public struct Goal: Sendable, Equatable, Codable {
    /// A user-given name for the goal (e.g. "Hamburg Marathon"). Optional — empty
    /// when the user hasn't named it; UI falls back to the race distance's name.
    public var name: String
    public var race: RaceDistance
    public var raceDate: Date
    public var targetTimeSeconds: Double?
    /// Running days per week (clamped to 3…6 by the generator). Persisted on the
    /// goal so the plan can be regenerated/recalculated from stored inputs later.
    public var daysPerWeek: Int
    /// Weekdays the athlete won't run (Calendar weekday numbers, 1 = Sun … 7 = Sat).
    /// The generator places rest on these days; validation caps `daysPerWeek` at
    /// `7 - restWeekdays.count`.
    public var restWeekdays: Set<Int>
    /// Days the athlete can't train (vacation, travel, illness). Workouts landing
    /// inside these are blanked to rest during adaptation.
    public var unavailablePeriods: [UnavailablePeriod]
    /// When true, the fixed year-end holidays (Christmas Eve–Boxing Day and New
    /// Year's Eve–Day) are treated as time off wherever the plan crosses them, on
    /// top of any `unavailablePeriods` the athlete adds. See `Holidays`.
    public var skipHolidays: Bool

    public init(
        name: String = "",
        race: RaceDistance,
        raceDate: Date,
        targetTimeSeconds: Double? = nil,
        daysPerWeek: Int = 5,
        restWeekdays: Set<Int> = [],
        unavailablePeriods: [UnavailablePeriod] = [],
        skipHolidays: Bool = true
    ) {
        self.name = name
        self.race = race
        self.raceDate = raceDate
        self.targetTimeSeconds = targetTimeSeconds
        self.daysPerWeek = daysPerWeek
        self.restWeekdays = restWeekdays
        self.unavailablePeriods = unavailablePeriods
        self.skipHolidays = skipHolidays
    }

    private enum CodingKeys: String, CodingKey {
        case name, race, raceDate, targetTimeSeconds, daysPerWeek, restWeekdays, unavailablePeriods, skipHolidays
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        race = try c.decode(RaceDistance.self, forKey: .race)
        raceDate = try c.decode(Date.self, forKey: .raceDate)
        targetTimeSeconds = try c.decodeIfPresent(Double.self, forKey: .targetTimeSeconds)
        // Tolerate plans persisted before these fields existed.
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        daysPerWeek = try c.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? 5
        restWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .restWeekdays) ?? []
        unavailablePeriods = try c.decodeIfPresent([UnavailablePeriod].self, forKey: .unavailablePeriods) ?? []
        skipHolidays = try c.decodeIfPresent(Bool.self, forKey: .skipHolidays) ?? true
    }

    /// The name to show for this goal, falling back to the race distance when the
    /// user hasn't named it.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? race.displayName : trimmed
    }
}

/// A recent performance used to estimate current fitness (VDOT). Typically a race
/// or a hard time-trial the user enters, or a strong recorded run.
public struct FitnessSnapshot: Sendable, Equatable, Codable {
    public var distanceMeters: Double
    public var timeSeconds: Double
    public var date: Date

    public init(distanceMeters: Double, timeSeconds: Double, date: Date) {
        self.distanceMeters = distanceMeters
        self.timeSeconds = timeSeconds
        self.date = date
    }
}
