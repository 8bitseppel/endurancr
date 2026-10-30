import Foundation

/// What else can be started today instead of today's run, within what the athlete can
/// do now: this week's own hard session moved to today, or strides at the end of today's
/// easy run. Never a made-up workout: the plan's session is already sized to the week by
/// Jack Tupper Daniels' limits and paced from the current VDOT. When intervals don't fit
/// today, `reason` says why in plain words.
public struct SessionOffers: Sendable, Equatable {
    public struct Offer: Sendable, Equatable, Identifiable {
        public var id: String { title }
        /// "This week's intervals", "Strides".
        public var title: String
        /// "From Thursday · 6 × 1 km at 4:15/km".
        public var detail: String
        /// The session as it's run today.
        public var workout: PlannedWorkout
        /// The plan day it comes from; starting it swaps that day with today.
        public var movesFrom: Date?

        public init(title: String, detail: String, workout: PlannedWorkout, movesFrom: Date?) {
            self.title = title
            self.detail = detail
            self.workout = workout
            self.movesFrom = movesFrom
        }
    }

    public var offers: [Offer]
    /// Why no hard session is offered today, or `nil` when one is.
    public var reason: String?

    public init(offers: [Offer], reason: String?) {
        self.offers = offers
        self.reason = reason
    }

    public static func make(plan: TrainingPlan, runs: [CompletedRun], isEasingBack: Bool,
                            isFatigued: Bool, asOf: Date, calendar: Calendar = .current) -> SessionOffers {
        let today = calendar.startOfDay(for: asOf)
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: today)! }
        let workouts = plan.allWorkouts
        let planned = { (date: Date) in workouts.first { calendar.isDate($0.date, inSameDayAs: date) } }
        guard let now = planned(today) else { return SessionOffers(offers: [], reason: nil) }
        // Today is already a session: Start runs it. (Strides are an easy run: those
        // days can still take intervals.)
        if now.structure != nil || hardTypes.contains(now.type) || now.type == .longRun || now.type == .raceDay {
            return SessionOffers(offers: [], reason: nil)
        }

        var offers: [Offer] = []
        if now.type == .easy, !WorkoutSteps.hasStrides(now) {
            var strides = now
            strides.notes = VDOTPlanGenerator.stridesNote
            if WorkoutSteps.hasStrides(strides) {
                offers.append(Offer(title: "Strides",
                                    detail: "Today's easy run, then 6 × 20 s quick and light",
                                    workout: strides, movesFrom: nil))
            }
        }

        guard let week = plan.weeks.first(where: { w in
            let start = calendar.startOfDay(for: w.startDate)
            return start <= today && today < calendar.date(byAdding: .day, value: 7, to: start)!
        }) else { return SessionOffers(offers: offers, reason: nil) }
        let reason = hardReason(plan: plan, runs: runs, today: today, weekStart: calendar.startOfDay(for: week.startDate),
                                day: day, planned: planned,
                                isEasingBack: isEasingBack, isFatigued: isFatigued, calendar: calendar)
        if let reason { return SessionOffers(offers: offers, reason: reason) }

        // This week's hard session still to come.
        let later = week.workouts
            .filter { calendar.startOfDay(for: $0.date) > today && hardTypes.contains($0.type) }
            .sorted { $0.date < $1.date }
        if week.phase == .base {
            return SessionOffers(offers: offers, reason: "No intervals yet: base weeks build the easy running intervals rest on. They start in the build phase.")
        }
        guard let session = later.first else {
            // No hard session left this week: one of the plan's own size, if the week
            // has room for a second hard session.
            let plannedHard = week.workouts.filter { hardTypes.contains($0.type) || $0.type == .timeTrial }.count
            let hardRun = runs.filter { $0.date >= calendar.startOfDay(for: week.startDate) && $0.date < today
                && isHard($0, zones: plan.paceZones) }.count
            guard max(plannedHard, hardRun) < 2 else {
                return SessionOffers(offers: offers, reason: "This week already has its two hard sessions.")
            }
            guard let generated = intervals(for: now, weekMeters: week.plannedVolumeMeters, zones: plan.paceZones) else {
                return SessionOffers(offers: offers, reason: "Your weeks are still too short for an interval session.")
            }
            offers.insert(Offer(title: "Intervals",
                                detail: "Instead of today's run · \(summary(generated, plan.paceZones))",
                                workout: generated, movesFrom: nil), at: 0)
            return SessionOffers(offers: offers, reason: nil)
        }
        // Moving it must not put two hard days side by side: tomorrow stays easy.
        if let next = planned(day(1)), next.id != session.id, hardTypes.contains(next.type) || next.type == .longRun {
            return SessionOffers(offers: offers, reason: "Tomorrow is a \(name(next.type)): today stays easy.")
        }
        var moved = session
        moved.date = now.date
        let weekday = session.date.formatted(Date.FormatStyle(calendar: calendar).weekday(.wide))
        offers.insert(Offer(title: "This week's \(name(session.type))",
                            detail: "From \(weekday) · \(summary(session, plan.paceZones))",
                            workout: moved, movesFrom: calendar.startOfDay(for: session.date)), at: 0)
        return SessionOffers(offers: offers, reason: nil)
    }

    /// An interval session the size the plan would give this week, by Jack Tupper
    /// Daniels' rules: reps of about 3 to 4 minutes at interval pace (rounded to 200 m,
    /// 400 m to 1.2 km), at most 8% of the week or 10 km of them in all, 3 to 6 reps,
    /// half the rep's distance easy between them, a 2 km warm-up and 1.5 km cool-down.
    /// `nil` when the week is too short for three reps.
    public static func intervals(for today: PlannedWorkout, weekMeters: Double, zones: PaceZones) -> PlannedWorkout? {
        let pace = zones.intervalSecPerKm
        let cap = min(10_000, 0.08 * weekMeters)
        var rep = min(1_200, max(400, ((210 / pace * 1_000) / 200).rounded() * 200))
        while rep > 400, Int(cap / rep) < 3 { rep -= 200 }
        let reps = min(6, Int(cap / rep))
        guard reps >= 3 else { return nil }
        let structure = WorkoutStructure(warmupMeters: 2_000, reps: reps, workMeters: rep,
                                         recoveryMeters: rep / 2, cooldownMeters: 1_500,
                                         workType: .interval, recoveryType: .easy)
        return PlannedWorkout(date: today.date, type: .interval, distanceMeters: structure.totalMeters,
                              targetPaceSecPerKm: (pace - 3)...(pace + 3),
                              notes: "Intervals: \(reps) × \(Int(rep)) m at interval pace, \(Int(rep / 2)) m easy between",
                              structure: structure)
    }

    /// Threshold, intervals, speed and marathon-pace runs: the sessions that count as
    /// hard. The tune-up race keeps its day; long runs aren't moved here.
    static let hardTypes: Set<WorkoutType> = [.threshold, .interval, .repetitionSpeed, .marathonPace]

    public static func isHard(_ type: WorkoutType) -> Bool { hardTypes.contains(type) }

    /// Why a hard session doesn't fit today, Daniels' rules first.
    private static func hardReason(plan: TrainingPlan, runs: [CompletedRun], today: Date, weekStart: Date,
                                   day: (Int) -> Date, planned: (Date) -> PlannedWorkout?,
                                   isEasingBack: Bool, isFatigued: Bool, calendar: Calendar) -> String? {
        let race = calendar.startOfDay(for: plan.goal.raceDate)
        let daysToRace = calendar.dateComponents([.day], from: today, to: race).day ?? 0
        if today > race { return "After the race it's rest and easy runs only." }
        if daysToRace <= 10 { return "In the last 10 days before the race the plan keeps you fresh: no extra hard sessions." }
        if isEasingBack { return "While you ease back in after a break, it's easy runs only." }
        if isFatigued { return "Your resting heart rate is up: an easy day is better today." }
        if let tomorrow = planned(day(1)), tomorrow.type == .longRun {
            return "Tomorrow is the long run: today stays easy."
        }
        // Yesterday hard: a hard or long run planned and run, or a run at threshold
        // effort or faster.
        let yesterday = day(-1)
        let ranYesterday = runs.filter { calendar.isDate($0.date, inSameDayAs: yesterday) && $0.distanceMeters > 0 }
        let hardRun = ranYesterday.contains { isHard($0, zones: plan.paceZones) }
        if let y = planned(yesterday), !ranYesterday.isEmpty, hardTypes.contains(y.type) || y.type == .longRun || y.type == .timeTrial {
            return y.type == .longRun
                ? "The day after the long run is for easy running."
                : "The day after a hard session is for easy running."
        }
        if hardRun { return "The day after a hard session is for easy running." }
        // At most two hard sessions a week, the ones already run counted.
        let hardThisWeek = runs.filter { $0.date >= weekStart && $0.date < today && isHard($0, zones: plan.paceZones) }.count
        if hardThisWeek >= 2 { return "This week already had its two hard sessions." }
        return nil
    }

    /// A run with reps, or one run at threshold effort or faster on average. An easy
    /// run that ended with strides stays easy: six 20 s bursts are form work, and
    /// shouldn't cost tomorrow its session.
    static func isHard(_ run: CompletedRun, zones: PaceZones) -> Bool {
        if let reps = run.reps, !RepReport.reps(reps).isEmpty { return true }
        guard run.distanceMeters >= 3_000 else { return false }
        let effort = PlanReview.effort(paceSecPerKm: run.averagePaceSecPerKm, zones: zones)
        return effort == .threshold || effort == .interval
    }

    private static func name(_ type: WorkoutType) -> String {
        switch type {
        case .interval: "intervals"
        case .threshold: "threshold run"
        case .repetitionSpeed: "speed session"
        case .marathonPace: "marathon-pace run"
        case .longRun: "long run"
        default: "run"
        }
    }

    /// "6 × 1 km at 4:15/km", "5 km at threshold, 4:30/km".
    private static func summary(_ w: PlannedWorkout, _ zones: PaceZones) -> String {
        guard let s = w.structure else { return String(format: "%.1f km", w.distanceMeters / 1_000) }
        let pace = WorkoutSteps.zonePace(s.workType, zones).map { p -> String in
            let t = Int(p.rounded()); return String(format: "%d:%02d/km", t / 60, t % 60)
        } ?? ""
        let work = s.workMeters >= 1_000
            ? (s.workMeters.truncatingRemainder(dividingBy: 1_000) == 0 ? String(format: "%.0f km", s.workMeters / 1_000) : String(format: "%.1f km", s.workMeters / 1_000))
            : String(format: "%.0f m", s.workMeters)
        return s.reps > 1 ? "\(s.reps) × \(work) at \(pace)" : "\(work) at \(pace)"
    }
}
