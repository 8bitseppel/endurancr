import Foundation

/// What the Plan tab shows on top of the plan itself: what was actually run on each
/// day, which days the plan changed and from what, how far each week is, what each
/// week is for, and the plan's longest runs.
///
/// - A past run day is done when a run fulfilled it (the same test as the adaptation:
///   matched to the workout, or at least 80% of its distance that day), shorter when
///   some running was recorded, and missed otherwise.
/// - A day counts as changed when the adapted plan has a different session or at
///   least 0.5 km more or less than the plan built from the goal (`original`). Its
///   pace window counts as changed at 3 s/km or more.
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
        /// The pace window before the paces changed; `nil` when within 3 s/km.
        public var originalPace: ClosedRange<Double>?
        public var milestone: Milestone?
        /// How hard the run was, from its average pace against the plan's zones:
        /// `.easy`, `.marathonPace` (steady), `.threshold` or `.interval` (hard).
        /// `nil` without a run.
        public var effort: WorkoutType?
        /// The reps as they were run, for an interval day recorded by endurancr.
        public var reps: [RepSplit] = []

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
            day.reps = runsByDay[d]?.compactMap(\.reps).first ?? []
            if meters > 0 { day.effort = Self.effort(paceSecPerKm: seconds / (meters / 1_000), zones: plan.paceZones) }
            if let o = originalByDay[d], o.type != w.type || abs(o.distanceMeters - w.distanceMeters) >= 500 {
                day.originalType = o.type
                day.originalMeters = o.distanceMeters
            }
            if let o = originalByDay[d], o.type == w.type, let was = o.targetPaceSecPerKm, let now = w.targetPaceSecPerKm,
               abs(was.lowerBound - now.lowerBound) >= 3 || abs(was.upperBound - now.upperBound) >= 3 {
                day.originalPace = was
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
                .map { Self.reason(of: $0.notes) }
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

    /// The zone a run's average pace falls in, with a little room (3%, 2%) so a run
    /// at the fast end of easy still counts as easy.
    public static func effort(paceSecPerKm pace: Double, zones: PaceZones) -> WorkoutType {
        if pace >= zones.easySecPerKm * 0.97 { return .easy }
        if pace >= zones.marathonSecPerKm * 0.98 { return .marathonPace }
        if pace >= zones.thresholdSecPerKm * 0.98 { return .threshold }
        return .interval
    }

    /// A changed run's reason without the strides it keeps, so runs changed for the same
    /// reason match ("Shorter, then 6 × 20 s strides" is "Shorter").
    public static func reason(of notes: String) -> String {
        notes.replacingOccurrences(of: ", then 6 × 20 s strides", with: "")
    }

    /// What the week is for, its harder sessions, and its long run.
    static func purpose(of week: TrainingWeek, isCutback: Bool) -> String {
        let hasTuneUp = week.workouts.contains { $0.type == .timeTrial }
        let line: String = switch week.phase {
        case _ where hasTuneUp: "A lighter week around the tune-up race."
        case _ where isCutback: "An easier week, so the last weeks can sink in."
        case .base: "Easy runs build the base."
        case .build: "Building up, with a harder session each week."
        case .peak: "The biggest weeks of the plan."
        case .taper: "Less running, so you start the race rested."
        case .raceWeek: "Short and easy until race day."
        case .maintenance: "Steady weeks that hold your fitness."
        case .recovery: "Rest, then short easy runs: an easy day for every 3 km you raced."
        }
        guard week.phase != .raceWeek, week.phase != .recovery else { return line }
        // The harder sessions in order, then the long run, as one sentence:
        // "Threshold and a long run of 28 km, the last 9 km at marathon pace."
        let names: [WorkoutType: String] = [.threshold: "threshold", .interval: "intervals", .repetitionSpeed: "speed",
                                             .marathonPace: "a marathon-pace run"]
        var items = week.workouts.compactMap { names[$0.type] }
        if let long = week.workouts.filter({ $0.type == .longRun }).max(by: { $0.distanceMeters < $1.distanceMeters }) {
            if let s = long.structure, s.workType == .marathonPace {
                items.append("a long run of \(km(long.distanceMeters)), the last \(km((s.workMeters / 500).rounded() * 500)) at marathon pace")
            } else {
                items.append("a long run of \(km(long.distanceMeters))")
            }
        }
        var parts = [line]
        if !items.isEmpty {
            let sentence = items.count == 1 ? items[0] : items.dropLast().joined(separator: ", ") + " and " + items.last!
            parts.append(sentence.prefix(1).uppercased() + sentence.dropFirst() + ".")
        }
        return parts.joined(separator: " ")
    }

    static func km(_ meters: Double) -> String {
        let km = meters / 1_000
        return km.rounded() == km || km >= 10 ? "\(Int(km.rounded())) km" : String(format: "%.1f km", km)
    }
}
