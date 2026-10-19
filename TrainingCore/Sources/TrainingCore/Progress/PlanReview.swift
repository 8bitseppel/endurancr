import Foundation

/// What the Plan tab shows on top of the plan itself: what was actually run on each
/// day, which days the plan changed and from what, how far each week is, what each
/// week is for, and the plan's longest runs.
///
/// - A past run day is done when a run fulfilled it (the same test as the adaptation:
///   matched to the workout, or at least 80% of its distance that day), shorter when
///   some running was recorded, and missed otherwise.
/// - A day counts as changed when the adapted plan has a different session or at
///   least 0.5 km more or less than the plan built from the goal (`original`).
public struct PlanReview: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case upcoming, today, done, shorter, missed
        /// A rest day with a recorded run.
        case extra
        case rest
    }

    public enum Milestone: Sendable, Equatable {
        /// The longest long run of the plan (the 32 km for a marathon).
        case longestRun
        /// The first long run of the taper, when the long runs get shorter.
        case taperBegins
    }

    public struct Day: Sendable, Equatable {
        public var status: Status
        /// Distance and time recorded that day (all runs together).
        public var ranMeters: Double
        public var ranSeconds: Double
        /// The session before the plan changed it; `nil` when unchanged.
        public var originalType: WorkoutType?
        public var originalMeters: Double?
        public var milestone: Milestone?

        public var isChanged: Bool { originalType != nil }
        /// Average pace of what was run (sec/km), `nil` without a run.
        public var ranPaceSecPerKm: Double? { ranMeters > 0 ? ranSeconds / (ranMeters / 1_000) : nil }
    }

    public struct Week: Sendable, Equatable {
        /// Run so far in this week, from the plan's first run day on.
        public var doneMeters: Double
        public var plannedMeters: Double
        /// The week's distance before the plan changed it; `nil` when within 1 km.
        public var originalMeters: Double?
        /// A lighter week inside the build (`VDOTPlanGenerator`'s cutbacks).
        public var isCutback: Bool
        /// One line on what the week is for.
        public var purpose: String
        /// The reason the plan gives on two or more of the week's changed days, so it
        /// can be said once for the week.
        public var changeNote: String?
    }

    /// Keyed by the start of each day.
    public var days: [Date: Day]
    /// Keyed by `TrainingWeek.index`.
    public var weeks: [Int: Week]

    public func day(_ date: Date, calendar: Calendar = .current) -> Day? { days[calendar.startOfDay(for: date)] }

    public static func make(
        plan: TrainingPlan, original: TrainingPlan?, completedRuns: [CompletedRun],
        asOf: Date, calendar: Calendar = .current
    ) -> PlanReview {
        let engine = AdaptationEngine()
        let today = calendar.startOfDay(for: asOf)
        let planStart = TrainingBuddy.firstRunDay(of: plan, calendar: calendar) ?? today
        let runs = completedRuns.filter {
            let d = calendar.startOfDay(for: $0.date)
            return d >= planStart && d <= today
        }
        var runsByDay: [Date: [CompletedRun]] = [:]
        for run in runs { runsByDay[calendar.startOfDay(for: run.date), default: []].append(run) }
        var originalByDay: [Date: PlannedWorkout] = [:]
        for w in original?.allWorkouts ?? [] { originalByDay[calendar.startOfDay(for: w.date)] = w }

        // The plan's longest long run, from the original so a capped run still shows it.
        let reference = original ?? plan
        let peakLong = reference.allWorkouts.filter { $0.type == .longRun }.map(\.distanceMeters).max() ?? 0
        let taperLong = reference.weeks.first { $0.phase == .taper }?
            .workouts.first { $0.type == .longRun }.map { calendar.startOfDay(for: $0.date) }

        var days: [Date: Day] = [:]
        for w in plan.allWorkouts {
            let d = calendar.startOfDay(for: w.date)
            let ran = runsByDay[d] ?? []
            let meters = ran.reduce(0) { $0 + $1.distanceMeters }
            let seconds = ran.reduce(0) { $0 + $1.durationSeconds }
            let status: Status
            if !w.type.isRunning {
                status = meters > 0 ? .extra : .rest
            } else if engine.isCompleted(w, by: runs, calendar: calendar) {
                status = .done
            } else if d == today {
                status = .today
            } else if d > today {
                status = .upcoming
            } else {
                status = meters > 0 ? .shorter : .missed
            }

            var day = Day(status: status, ranMeters: meters, ranSeconds: seconds)
            if let o = originalByDay[d], o.type != w.type || abs(o.distanceMeters - w.distanceMeters) >= 500 {
                day.originalType = o.type
                day.originalMeters = o.distanceMeters
            }
            let originalLong = originalByDay[d] ?? w
            if originalLong.type == .longRun, peakLong > 0, originalLong.distanceMeters >= peakLong - 1 {
                day.milestone = .longestRun
            } else if d == taperLong {
                day.milestone = .taperBegins
            }
            days[d] = day
        }

        var weeks: [Int: Week] = [:]
        var lastFullWeek: Double?
        for week in plan.weeks {
            let start = calendar.startOfDay(for: week.startDate)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let done = runs.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.distanceMeters }
            let originalWeek = original?.weeks.first { $0.index == week.index }
            let originalMeters = originalWeek?.plannedVolumeMeters
            let basis = originalMeters ?? week.plannedVolumeMeters
            let inBuild = [.base, .build, .peak].contains(week.phase)
            let isCutback = inBuild && lastFullWeek.map { basis < 0.85 * $0 } == true
            if inBuild, !isCutback { lastFullWeek = basis }
            let notes = week.workouts
                .filter { $0.type.isRunning && !$0.notes.isEmpty && days[calendar.startOfDay(for: $0.date)]?.isChanged == true }
                .map(\.notes)
            let common = Dictionary(grouping: notes, by: { $0 }).max { $0.value.count < $1.value.count }
            weeks[week.index] = Week(
                doneMeters: done,
                plannedMeters: week.plannedVolumeMeters,
                originalMeters: originalMeters.flatMap { abs($0 - week.plannedVolumeMeters) >= 1_000 ? $0 : nil },
                isCutback: isCutback,
                purpose: purpose(of: week, isCutback: isCutback),
                changeNote: common.flatMap { $0.value.count >= 2 ? $0.key : nil }
            )
        }
        return PlanReview(days: days, weeks: weeks)
    }

    /// What the week is for, and its longest run.
    static func purpose(of week: TrainingWeek, isCutback: Bool) -> String {
        let line: String = switch week.phase {
        case _ where isCutback: "An easier week, so the last weeks can sink in."
        case .base: "Easy runs and a long run build the base."
        case .build: "A harder session each week, and a growing long run."
        case .peak: "The biggest weeks, with two harder sessions."
        case .taper: "Less running, so you start the race rested."
        case .raceWeek: "Short and easy until race day."
        case .maintenance: "Steady weeks that hold your fitness."
        }
        guard week.phase != .raceWeek,
              let long = week.workouts.filter({ $0.type == .longRun }).map(\.distanceMeters).max() else { return line }
        return line + " Long run \(Self.km(long))."
    }

    static func km(_ meters: Double) -> String {
        let km = meters / 1_000
        return km.rounded() == km || km >= 10 ? "\(Int(km.rounded())) km" : String(format: "%.1f km", km)
    }
}
