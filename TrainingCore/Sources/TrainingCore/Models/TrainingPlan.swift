import Foundation

/// The kind of session a planned day represents.
public enum WorkoutType: String, Sendable, Codable, CaseIterable {
    case rest
    case easy
    case longRun
    case marathonPace
    case threshold
    case interval
    case repetitionSpeed
    case raceDay

    /// Non-rest sessions count toward the weekly running-days budget.
    public var isRunning: Bool { self != .rest }
}

/// Where a week sits in the periodized build toward race day.
public enum TrainingPhase: String, Sendable, Codable {
    case base
    case build
    case peak
    case taper
    case raceWeek
    /// Steady, non-progressive week used by a maintenance plan — the athlete is
    /// already fit enough for the goal, so volume holds instead of ramping.
    case maintenance
}

/// The breakdown of a structured quality session (intervals, tempo) into a
/// warm-up, a repeated work/recovery block, and a cool-down. Pure geometry — it
/// stores distances and which pace *zone* each part runs at, never the paces
/// themselves, so re-pacing from an updated VDOT needs no change here. The parts
/// sum to the parent workout's `distanceMeters`.
public struct WorkoutStructure: Sendable, Equatable, Codable {
    public var warmupMeters: Double
    /// How many times the work/recovery block repeats (≥ 1).
    public var reps: Int
    public var workMeters: Double
    /// Recovery-jog distance between reps; 0 for a continuous tempo (reps == 1).
    public var recoveryMeters: Double
    public var cooldownMeters: Double
    /// Pace zone the work bouts are run at (e.g. `.interval`, `.threshold`).
    public var workType: WorkoutType
    /// Pace zone for warm-up, cool-down, and recovery jogs (normally `.easy`).
    public var recoveryType: WorkoutType

    public init(
        warmupMeters: Double,
        reps: Int,
        workMeters: Double,
        recoveryMeters: Double,
        cooldownMeters: Double,
        workType: WorkoutType,
        recoveryType: WorkoutType = .easy
    ) {
        self.warmupMeters = warmupMeters
        self.reps = reps
        self.workMeters = workMeters
        self.recoveryMeters = recoveryMeters
        self.cooldownMeters = cooldownMeters
        self.workType = workType
        self.recoveryType = recoveryType
    }

    /// Total distance covered — should match the parent workout's `distanceMeters`.
    public var totalMeters: Double {
        warmupMeters + Double(reps) * (workMeters + recoveryMeters) + cooldownMeters
    }
}

/// A single planned day.
public struct PlannedWorkout: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var date: Date
    public var type: WorkoutType
    public var distanceMeters: Double
    /// Target pace window (sec/km); `nil` for rest days.
    public var targetPaceSecPerKm: ClosedRange<Double>?
    public var notes: String
    /// Structured breakdown for quality sessions (intervals/tempo); `nil` for
    /// steady runs. Optional so plans encoded before this field decode cleanly.
    public var structure: WorkoutStructure?

    public init(
        id: UUID = UUID(),
        date: Date,
        type: WorkoutType,
        distanceMeters: Double,
        targetPaceSecPerKm: ClosedRange<Double>? = nil,
        notes: String = "",
        structure: WorkoutStructure? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.distanceMeters = distanceMeters
        self.targetPaceSecPerKm = targetPaceSecPerKm
        self.notes = notes
        self.structure = structure
    }
}

/// One calendar week of the plan.
public struct TrainingWeek: Sendable, Equatable, Codable {
    public var index: Int
    public var startDate: Date
    public var phase: TrainingPhase
    public var workouts: [PlannedWorkout]

    public init(index: Int, startDate: Date, phase: TrainingPhase, workouts: [PlannedWorkout]) {
        self.index = index
        self.startDate = startDate
        self.phase = phase
        self.workouts = workouts
    }

    /// Total planned running distance for the week (meters).
    public var plannedVolumeMeters: Double {
        workouts.reduce(0) { $0 + $1.distanceMeters }
    }
}

/// A complete generated plan: the goal, the fitness it was built from, and the weeks.
public struct TrainingPlan: Sendable, Equatable, Codable {
    public var goal: Goal
    public var vdot: Double
    public var paceZones: PaceZones
    public var weeks: [TrainingWeek]
    /// True when the athlete's current fitness already meets the goal's target, so
    /// the plan holds fitness (steady volume) rather than building toward it.
    public var isMaintenance: Bool

    public init(goal: Goal, vdot: Double, paceZones: PaceZones, weeks: [TrainingWeek], isMaintenance: Bool = false) {
        self.goal = goal
        self.vdot = vdot
        self.paceZones = paceZones
        self.weeks = weeks
        self.isMaintenance = isMaintenance
    }

    private enum CodingKeys: String, CodingKey {
        case goal, vdot, paceZones, weeks, isMaintenance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decode(Goal.self, forKey: .goal)
        vdot = try c.decode(Double.self, forKey: .vdot)
        paceZones = try c.decode(PaceZones.self, forKey: .paceZones)
        weeks = try c.decode([TrainingWeek].self, forKey: .weeks)
        isMaintenance = try c.decodeIfPresent(Bool.self, forKey: .isMaintenance) ?? false
    }

    public var allWorkouts: [PlannedWorkout] { weeks.flatMap(\.workouts) }
    public var peakVolumeMeters: Double { weeks.map(\.plannedVolumeMeters).max() ?? 0 }

    /// Every stretch of time off the calendar should blank: the athlete's own
    /// `unavailablePeriods` plus the fixed year-end holidays (when `goal.skipHolidays`
    /// is on) for the span this plan actually covers.
    public func effectiveUnavailablePeriods(calendar: Calendar = .current) -> [UnavailablePeriod] {
        var periods = goal.unavailablePeriods
        if goal.skipHolidays,
           let first = weeks.first?.startDate,
           let last = allWorkouts.map(\.date).max() {
            periods += Holidays.periods(from: first, to: last, calendar: calendar)
        }
        return periods
    }
}
