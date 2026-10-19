import Foundation

/// Paces the plan to the training the athlete actually does, like a running buddy
/// who isn't pushy: after a break it eases back in, after lighter weeks it builds
/// from what was run, and it never piles missed kilometres onto later days.
/// Deterministic and stateless: everything is recomputed from the plan and the
/// recorded runs, so the same inputs always give the same plan.
///
/// The rules and where they come from (also in How it works):
/// - Breaks: Jack Tupper Daniels, Daniels' Running Formula (3rd ed.), Table 15.2 and
///   the VDOT adjustments for time off (news.vdoto2.com, 2018). Up to 5 days off
///   changes nothing; longer breaks lower the paces and bring back easy-only weeks
///   at a share of the volume run before the break.
/// - Lighter weeks: Pete Pfitzinger's "90 percent of the planned training is going
///   really well" (Advanced Marathoning); below that the plan holds or rebuilds from
///   the volume actually run, at most 10% more a week (Nielsen et al. 2014 found more
///   injuries above +30% in two weeks).
/// - Single runs: no run more than 10% longer than the longest run of the last 30
///   days (Frandsen et al. 2025, 5,205 runners).
/// - Paces: up at most 1 VDOT per 3 weeks (Daniels), down 1 when hard sessions keep
///   coming in slower than their target.
public struct TrainingBuddy: Sendable {
    public init() {}

    private let calculator = VDOTCalculator()

    // MARK: Status

    /// Where the athlete stands, and what the buddy does about it.
    public struct Status: Sendable, Equatable {
        public enum Phase: Sendable, Equatable {
            /// Not enough runs in the plan yet to judge.
            case starting
            /// Running about as planned (90% or more over 14 days).
            case onTrack
            /// A bit lighter than planned (75–90%): the next week holds instead of growing.
            case holding
            /// Clearly lighter (under 75%): the plan rebuilds from what was run.
            case rebuilding
            /// Back from (or still in) a break of more than 5 days: easy-only weeks
            /// at a share of the volume before the break, until `until`.
            case easingBack(daysOff: Int, until: Date)
        }

        public var phase: Phase
        /// Kilometres run over planned kilometres, last 14 days (vacation excluded).
        public var completion: Double?
        /// Average weekly distance actually run over the last 14 days (m).
        public var recentWeeklyMeters: Double
        /// Longest run of the last 30 days (m); 0 without runs.
        public var longestRecentMeters: Double
        /// Days without a run in the longest break of the last 8 weeks, for the goal
        /// outlook (Pfitzinger's "making up for lost time").
        public var longestRecentBreakDays: Int
        /// What the paces are multiplied by after time off (Daniels), 1 otherwise.
        public var vdotFactor: Double
        /// One friendly line about this week.
        public var message: String

        public var isEasingBack: Bool {
            if case .easingBack = phase { return true }
            return false
        }
    }

    /// Reads the athlete's recent training against the plan, as of `asOf`.
    public func status(
        plan: TrainingPlan, completedRuns: [CompletedRun], asOf: Date, calendar: Calendar = .current
    ) -> Status {
        let today = calendar.startOfDay(for: asOf)
        let planStart = Self.firstRunDay(of: plan, calendar: calendar) ?? today
        let runs = completedRuns
            .filter { calendar.startOfDay(for: $0.date) <= today }
            .sorted { $0.date < $1.date }
        let planRuns = runs.filter { calendar.startOfDay(for: $0.date) >= planStart }

        let longest = Self.longestRun(in: runs.filter { calendar.startOfDay(for: $0.date) < today },
                                      days: 30, before: today, calendar: calendar)
        let recentWeekly = Self.distance(of: runs, from: day(-14, today, calendar), to: today, calendar: calendar) / 2
        let completion = completionRatio(plan: plan, runs: runs, planStart: planStart, today: today, calendar: calendar)
        let breakDays = Self.longestBreak(planRuns: planRuns, planStart: planStart, today: today,
                                          withinDays: 56, calendar: calendar)

        var status = Status(
            phase: .starting, completion: completion, recentWeeklyMeters: recentWeekly,
            longestRecentMeters: longest, longestRecentBreakDays: breakDays,
            vdotFactor: 1, message: ""
        )

        // No runs in the plan yet: nothing to judge (and no Health access looks the
        // same), so the plan stays as it is.
        if planRuns.isEmpty {
            status.message = completion == nil
                ? "Every run you do shapes the weeks ahead."
                : "No runs from Apple Health yet. If you've been running, check that endurancr may read your workouts in the Health app."
            status.completion = nil
            return status
        }
        if let ret = returnFromBreak(planRuns: planRuns, planStart: planStart, today: today, calendar: calendar) {
            status.phase = .easingBack(daysOff: ret.daysOff, until: ret.until)
            status.vdotFactor = Self.vdotFactor(daysOff: ret.daysOff)
            status.message = ret.ongoing
                ? "No runs for \(ret.daysOff) days. Whenever you're ready, the plan starts you off with easy runs, nothing to catch up on."
                : "Welcome back! After \(ret.daysOff) days off we ease in with easy runs, shorter than before. Nothing to catch up on."
            return status
        }
        guard let completion else {
            status.message = "Every run you do shapes the weeks ahead."
            return status
        }
        switch completion {
        case 0.9...:
            status.phase = .onTrack
            status.message = "You're running the plan, so it keeps building step by step."
        case 0.75..<0.9:
            status.phase = .holding
            status.message = "The last two weeks were a little lighter, so this week stays at your last full week instead of growing."
        default:
            status.phase = .rebuilding
            status.message = "The last two weeks were lighter, so the coming weeks build from what you ran, a little more each week."
        }
        return status
    }

    // MARK: Adjusting the plan

    /// The plan with its future days paced to `status`: weekly caps after a break or
    /// lighter weeks, easy-only while easing back, one hard session less when behind,
    /// and no run more than 10% past the longest recent one. Past days, rest days and
    /// race day are left as they are.
    public func adjusted(
        plan: TrainingPlan, status: Status, completedRuns: [CompletedRun], asOf: Date, calendar: Calendar = .current
    ) -> TrainingPlan {
        let today = calendar.startOfDay(for: asOf)
        var updated = plan
        applyWeeklyCaps(&updated, status: status, completedRuns: completedRuns, today: today, calendar: calendar)
        let off = plan.goal.unavailablePeriods
        // Today keeps the plan it had this morning, run or not, so finishing a run
        // never reshapes the week; only runs before today count.
        let firstOpen = today
        if case .easingBack(_, let until) = status.phase {
            // Easy-only for the return period, not beyond it.
            easeQuality(&updated, from: firstOpen, before: until, onlyFirst: false,
                        note: "Easy for now while we ease back in", calendar: calendar)
        } else if status.phase == .rebuilding
                    || (status.phase != .starting && missedQuality(plan: plan, runs: completedRuns, today: today, calendar: calendar)) {
            // One hard session this week, not every one from now on.
            let weekEnd = plan.weeks.first { contains($0, today, calendar) }.map { day(7, $0.startDate, calendar) } ?? day(7, today, calendar)
            easeQuality(&updated, from: firstOpen, before: weekEnd, onlyFirst: true,
                        note: "Easy instead of a hard session, the last days were lighter than planned", calendar: calendar)
        }
        capSingleRuns(&updated, longestRecent: status.longestRecentMeters, from: firstOpen, skipping: off, calendar: calendar)
        return updated
    }

    // MARK: Paces

    /// The VDOT for training paces: the plan's starting VDOT, raised by strong runs
    /// (half the gap, and at most 1 point per 3 weeks in the plan), lowered by 1 when
    /// hard sessions keep coming in slower than their targets, then scaled for any
    /// break (Daniels).
    /// The VDOT the coming runs are paced at, and why it differs from the plan's.
    public struct Pacing: Sendable, Equatable {
        /// The plan's own VDOT, from the run it was built on.
        public var base: Double
        /// The VDOT the coming runs are paced at.
        public var vdot: Double
        /// One sentence on why the paces changed; `nil` when they didn't.
        public var reason: String?

        public var isFaster: Bool { vdot > base }
    }

    public func pacing(
        base: Double, plan: TrainingPlan, status: Status, completedRuns: [CompletedRun],
        asOf: Date, calendar: Calendar = .current
    ) -> Pacing {
        let vdot = pacingVDOT(base: base, plan: plan, status: status, completedRuns: completedRuns, asOf: asOf, calendar: calendar)
        let reason: String?
        if abs(vdot - base) < 0.05 {
            reason = nil
        } else if case .easingBack(let daysOff, _) = status.phase, status.vdotFactor < 1 {
            reason = "Your paces eased a little after \(daysOff) days off, as Jack Tupper Daniels advises, and come back as you do."
        } else if vdot > base {
            reason = "Your paces are a little faster: a recent run showed you're fitter than when the plan started."
        } else {
            reason = "Your paces are a little slower: the hard sessions lately came in slower than their target."
        }
        return Pacing(base: base, vdot: vdot, reason: reason)
    }

    public func pacingVDOT(
        base: Double, plan: TrainingPlan, status: Status, completedRuns: [CompletedRun],
        asOf: Date, calendar: Calendar = .current
    ) -> Double {
        let today = calendar.startOfDay(for: asOf)
        let planStart = Self.firstRunDay(of: plan, calendar: calendar) ?? today
        let daysIn = max(0, calendar.dateComponents([.day], from: planStart, to: today).day ?? 0)
        let allowedGain = Double(daysIn / 21)

        let best = completedRuns
            .filter { let d = calendar.startOfDay(for: $0.date); return d >= planStart && d <= today && $0.distanceMeters >= 3_000 }
            .map { calculator.vdot(distanceMeters: $0.distanceMeters, timeSeconds: $0.durationSeconds) }
            .max() ?? base
        let gain = min(max(0, (best - base) * 0.5), allowedGain)
        let slower = hardSessionsSlower(plan: plan, runs: completedRuns, today: today, calendar: calendar) ? 1.0 : 0
        return ((base + gain - slower) * status.vdotFactor * 10).rounded() / 10
    }

    /// Daniels' multiplier for VDOT after `daysOff` without running (no cross-training).
    public static func vdotFactor(daysOff: Int) -> Double {
        let table: [(days: Double, factor: Double)] = [
            (5, 1.0), (7, 0.994), (10, 0.985), (14, 0.973), (21, 0.952), (28, 0.931),
            (35, 0.910), (42, 0.889), (56, 0.847), (70, 0.805), (72, 0.800),
        ]
        let d = Double(daysOff)
        guard d > table[0].days else { return 1 }
        guard d < table[table.count - 1].days else { return 0.8 }
        for (a, b) in zip(table, table.dropFirst()) where d <= b.days {
            return a.factor + (b.factor - a.factor) * (d - a.days) / (b.days - a.days)
        }
        return 0.8
    }

    // MARK: Breaks

    struct BreakReturn {
        var daysOff: Int
        /// The first day back (the first run after the break, or today if still off).
        var returnDay: Date
        var until: Date
        var ongoing: Bool
        /// Share of the pre-break week for a day of the return period.
        var share: (Date) -> Double
        /// Average weekly distance in the 4 weeks before the break (m).
        var preBreakWeeklyMeters: Double
    }

    /// The break (more than 5 days without a run, inside the plan) whose return period
    /// covers today, with Daniels' steps: 6–28 days off, half the time back at 50%
    /// then 75%; 29–56 days, thirds at 33/50/75%; longer, five 3-week steps at
    /// 33/50/70/85/100%.
    func returnFromBreak(planRuns: [CompletedRun], planStart: Date, today: Date, calendar: Calendar) -> BreakReturn? {
        guard let first = planRuns.first else { return nil }
        // Gaps between runs, and the one still going if the last run was a while ago.
        var gaps: [(lastRun: Date, back: Date?, daysOff: Int)] = []
        var previous = calendar.startOfDay(for: first.date)
        for run in planRuns.dropFirst() {
            let d = calendar.startOfDay(for: run.date)
            let off = (calendar.dateComponents([.day], from: previous, to: d).day ?? 0) - 1
            if off > 5 { gaps.append((previous, d, off)) }
            previous = max(previous, d)
        }
        let ongoingOff = (calendar.dateComponents([.day], from: previous, to: today).day ?? 0) - 1
        if ongoingOff > 5 { gaps.append((previous, nil, ongoingOff)) }

        for gap in gaps.reversed() {
            let back = gap.back ?? today
            let period = gap.daysOff > 56 ? 105 : gap.daysOff
            guard let until = calendar.date(byAdding: .day, value: period, to: back), today < until else { continue }
            let before = Self.distance(
                of: planRuns, from: day(-28, gap.lastRun, calendar), to: day(1, gap.lastRun, calendar), calendar: calendar
            ) / 4
            let daysOff = gap.daysOff
            let share: (Date) -> Double = { date in
                let t = Double(max(0, calendar.dateComponents([.day], from: back, to: date).day ?? 0))
                let p = Double(period)
                if daysOff <= 28 { return t < p / 2 ? 0.5 : 0.75 }
                if daysOff <= 56 { return t < p / 3 ? 0.33 : (t < 2 * p / 3 ? 0.5 : 0.75) }
                return [0.33, 0.5, 0.7, 0.85, 1.0][min(4, Int(t / 21))]
            }
            return BreakReturn(daysOff: daysOff, returnDay: back, until: until, ongoing: gap.back == nil,
                               share: share, preBreakWeeklyMeters: before)
        }
        return nil
    }

    // MARK: Weekly caps

    /// Caps each week from the current one: while easing back, the break's share of
    /// the pre-break volume; when holding, last week's planned volume; when
    /// rebuilding, 10% over the average of the last two weeks (at least half the
    /// plan). From there each week may grow by at most 10% until it meets the plan.
    private func applyWeeklyCaps(
        _ plan: inout TrainingPlan, status: Status, completedRuns: [CompletedRun], today: Date, calendar: Calendar
    ) {
        guard let current = plan.weeks.firstIndex(where: { contains($0, today, calendar) }) else { return }
        let planStart = Self.firstRunDay(of: plan, calendar: calendar) ?? today
        let planRuns = completedRuns.filter { calendar.startOfDay(for: $0.date) >= planStart }
            .sorted { $0.date < $1.date }
        let ret = status.isEasingBack
            ? returnFromBreak(planRuns: planRuns, planStart: planStart, today: today, calendar: calendar) : nil

        var cap: Double?
        switch status.phase {
        case .easingBack:
            if let ret {
                let reference = ret.preBreakWeeklyMeters > 0 ? ret.preBreakWeeklyMeters : plan.weeks[current].plannedVolumeMeters
                cap = reference * ret.share(today)
            }
        case .holding:
            // The last full week's planned level (a cutback week the week before
            // doesn't count), but never more than 10% over what was run.
            let last = plan.weeks[max(0, current - 2)..<max(1, current)].map(\.plannedVolumeMeters).max()
                ?? plan.weeks[current].plannedVolumeMeters
            cap = min(last, max(status.recentWeeklyMeters * 1.10, 0.5 * plan.weeks[current].plannedVolumeMeters))
        case .rebuilding:
            cap = max(status.recentWeeklyMeters * 1.10, 0.5 * plan.weeks[current].plannedVolumeMeters)
        case .onTrack, .starting:
            cap = nil
        }
        guard var weekCap = cap else { return }

        let note: String
        switch status.phase {
        case .easingBack: note = "Shorter while we ease back in after the break"
        case .holding: note = "No step up this time, the last weeks were a little lighter"
        default: note = "Shorter, building back from what you ran lately"
        }

        for w in current..<plan.weeks.count {
            if plan.weeks[w].phase == .raceWeek { break }
            if w > current {
                // Daniels' steps while easing back; otherwise at most 10% a week.
                let next = weekCap * 1.10
                if let ret, let start = plan.weeks[w].workouts.first?.date, start < ret.until {
                    let reference = ret.preBreakWeeklyMeters > 0 ? ret.preBreakWeeklyMeters : plan.weeks[w].plannedVolumeMeters
                    weekCap = max(next, reference * ret.share(start))
                } else {
                    weekCap = next
                }
            }
            let planned = plan.weeks[w].plannedVolumeMeters
            guard planned > weekCap + 500 else {
                if w > current { break }   // met the plan again: the rest stays as planned
                continue
            }
            scaleWeek(&plan.weeks[w], to: weekCap, completedRuns: completedRuns, today: today,
                      off: plan.goal.unavailablePeriods, note: note, calendar: calendar)
        }
    }

    /// Shrinks the week's runs still to come so the week lands on `cap`, counting
    /// what was already run this week. Every run keeps its share, so the long run
    /// stays the longest; a run that would end up under 2 km becomes rest.
    private func scaleWeek(
        _ week: inout TrainingWeek, to cap: Double, completedRuns: [CompletedRun], today: Date,
        off: [UnavailablePeriod], note: String, calendar: Calendar
    ) {
        let start = calendar.startOfDay(for: week.startDate)
        let end = day(7, start, calendar)
        // Runs done this week before today; today's session is still part of the plan.
        let done = Self.distance(of: completedRuns, from: start, to: min(end, today), calendar: calendar)
        let future = week.workouts.indices.filter {
            let w = week.workouts[$0]
            let d = calendar.startOfDay(for: w.date)
            return w.type.isRunning && w.type != .raceDay && d >= today
                && !off.contains { $0.contains(d, calendar: calendar) }   // time off is blanked anyway
        }
        let remaining = future.reduce(0.0) { $0 + week.workouts[$1].distanceMeters }
        guard remaining > 0 else { return }
        let factor = max(0, cap - done) / remaining
        guard factor < 0.97 else { return }
        for i in future {
            let scaled = (week.workouts[i].distanceMeters * factor / 100).rounded() * 100
            if scaled < 2_000 {
                week.workouts[i].type = .rest
                week.workouts[i].distanceMeters = 0
                week.workouts[i].targetPaceSecPerKm = nil
                week.workouts[i].structure = nil
                week.workouts[i].notes = "Rest, an easier week"
            } else {
                week.workouts[i].distanceMeters = scaled
                week.workouts[i].structure = week.workouts[i].structure.map { Self.scaled($0, to: scaled) }
                week.workouts[i].notes = note
            }
        }
    }

    // MARK: Hard sessions

    /// Turns hard sessions from `from` on into easy runs: all of them, or only the
    /// next one.
    private func easeQuality(
        _ plan: inout TrainingPlan, from today: Date, before end: Date, onlyFirst: Bool, note: String, calendar: Calendar
    ) {
        let easy = plan.paceZones.easySecPerKm
        // A session already eased for fatigue counts as this week's easier one.
        if onlyFirst, plan.allWorkouts.contains(where: {
            let d = calendar.startOfDay(for: $0.date)
            return d >= today && d < end && $0.notes.hasPrefix("Eased to easy")
        }) { return }
        for w in plan.weeks.indices {
            for i in plan.weeks[w].workouts.indices {
                let workout = plan.weeks[w].workouts[i]
                let d = calendar.startOfDay(for: workout.date)
                guard AdaptationEngine.qualityTypes.contains(workout.type), d >= today, d < end else { continue }
                plan.weeks[w].workouts[i].type = .easy
                plan.weeks[w].workouts[i].targetPaceSecPerKm = (easy * 0.97)...(easy * 1.03)
                plan.weeks[w].workouts[i].structure = nil
                plan.weeks[w].workouts[i].notes = note
                if onlyFirst { return }
            }
        }
        _ = calendar
    }

    /// A hard session in the last 7 days had no run on its day (missed, not made up).
    private func missedQuality(plan: TrainingPlan, runs: [CompletedRun], today: Date, calendar: Calendar) -> Bool {
        let from = day(-7, today, calendar)
        let skipped = plan.goal.unavailablePeriods
        return plan.allWorkouts.contains { w in
            let d = calendar.startOfDay(for: w.date)
            return AdaptationEngine.qualityTypes.contains(w.type) && d >= from && d < today
                && !skipped.contains { $0.contains(d, calendar: calendar) }
                && !runs.contains { calendar.startOfDay(for: $0.date) == d }
        }
    }

    /// At least two of the hard sessions run in the last 28 days came in more than
    /// 3% slower than the slow end of their target, and most of them did.
    private func hardSessionsSlower(plan: TrainingPlan, runs: [CompletedRun], today: Date, calendar: Calendar) -> Bool {
        let from = day(-28, today, calendar)
        var slow = 0, total = 0
        let easyPace = plan.paceZones.easySecPerKm
        for w in plan.allWorkouts where [.threshold, .interval, .marathonPace].contains(w.type) {
            let d = calendar.startOfDay(for: w.date)
            guard d >= from, d < today, let target = w.targetPaceSecPerKm, w.distanceMeters > 0,
                  let run = runs.first(where: { calendar.startOfDay(for: $0.date) == d && $0.distanceMeters > 0 }),
                  run.averagePaceSecPerKm < easyPace   // run hard at all, not as an easy day
            else { continue }
            // The pace the whole session should average: work at the slow end of
            // its target, warm-up, cool-down and recoveries at easy pace.
            let work = w.structure.map { Double($0.reps) * $0.workMeters } ?? w.distanceMeters
            let rest = max(0, w.distanceMeters - work)
            let expected = (work * target.upperBound + rest * easyPace * 1.03) / w.distanceMeters
            total += 1
            if run.averagePaceSecPerKm > expected * 1.03 { slow += 1 }
        }
        return slow >= 2 && Double(slow) >= Double(total) * 2 / 3
    }

    // MARK: Single runs

    /// No upcoming run more than 10% longer than the longest run so far, counting
    /// the runs planned before it as done (Frandsen et al. 2025). Without a run in
    /// the last 30 days there's nothing to measure against, so nothing changes.
    private func capSingleRuns(
        _ plan: inout TrainingPlan, longestRecent: Double, from today: Date, skipping off: [UnavailablePeriod], calendar: Calendar
    ) {
        guard longestRecent >= 3_000 else { return }
        var longest = longestRecent
        let order = plan.weeks.indices.flatMap { w in plan.weeks[w].workouts.indices.map { (w, $0) } }
            .sorted { plan.weeks[$0.0].workouts[$0.1].date < plan.weeks[$1.0].workouts[$1.1].date }
        for (w, i) in order {
            let workout = plan.weeks[w].workouts[i]
            let d = calendar.startOfDay(for: workout.date)
            // Days off won't be run, so they don't count as done either.
            guard workout.type.isRunning, workout.type != .raceDay, d >= today,
                  !off.contains(where: { $0.contains(d, calendar: calendar) }) else { continue }
            let cap = (longest * 1.10 / 100).rounded(.down) * 100
            if workout.distanceMeters > cap {
                plan.weeks[w].workouts[i].distanceMeters = cap
                plan.weeks[w].workouts[i].structure = workout.structure.map { Self.scaled($0, to: cap) }
                plan.weeks[w].workouts[i].notes = "\(Self.km(cap)) for now, a step past your longest recent run"
            }
            longest = max(longest, plan.weeks[w].workouts[i].distanceMeters)
        }
    }

    // MARK: Helpers

    /// Kilometres run over kilometres planned for the last 14 days (fewer at the
    /// start of the plan), leaving out days blanked as time off. Nil until there are
    /// at least 7 days and 10 km planned to compare with.
    private func completionRatio(
        plan: TrainingPlan, runs: [CompletedRun], planStart: Date, today: Date, calendar: Calendar
    ) -> Double? {
        let from = max(planStart, day(-14, today, calendar))
        guard (calendar.dateComponents([.day], from: from, to: today).day ?? 0) >= 7 else { return nil }
        let off = plan.goal.unavailablePeriods
        let planned = plan.allWorkouts.filter { w in
            let d = calendar.startOfDay(for: w.date)
            return w.type.isRunning && w.type != .raceDay && d >= from && d < today
                && !off.contains { $0.contains(d, calendar: calendar) }
        }.reduce(0.0) { $0 + $1.distanceMeters }
        guard planned >= 10_000 else { return nil }
        return Self.distance(of: runs, from: from, to: today, calendar: calendar) / planned
    }

    static func firstRunDay(of plan: TrainingPlan, calendar: Calendar) -> Date? {
        plan.allWorkouts.filter(\.type.isRunning).map { calendar.startOfDay(for: $0.date) }.min()
    }

    public static func distance(of runs: [CompletedRun], from: Date, to: Date, calendar: Calendar) -> Double {
        runs.filter { let d = calendar.startOfDay(for: $0.date); return d >= from && d < to }
            .reduce(0.0) { $0 + $1.distanceMeters }
    }

    static func longestRun(in runs: [CompletedRun], days: Int, before today: Date, calendar: Calendar) -> Double {
        let from = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        return runs.filter { let d = calendar.startOfDay(for: $0.date); return d >= from && d <= today }
            .map(\.distanceMeters).max() ?? 0
    }

    /// The most days in a row without a run, inside the plan, over the last `withinDays`.
    static func longestBreak(planRuns: [CompletedRun], planStart: Date, today: Date, withinDays: Int, calendar: Calendar) -> Int {
        guard let first = planRuns.first else { return 0 }
        let from = max(calendar.startOfDay(for: first.date),
                       calendar.date(byAdding: .day, value: -withinDays, to: today) ?? today)
        var days = Set(planRuns.map { calendar.startOfDay(for: $0.date) }.filter { $0 >= from })
        days.insert(from)
        let sorted = days.sorted() + [today]
        return zip(sorted, sorted.dropFirst())
            .map { (calendar.dateComponents([.day], from: $0, to: $1).day ?? 0) - 1 }
            .max() ?? 0
    }

    static func scaled(_ s: WorkoutStructure, to total: Double) -> WorkoutStructure {
        let f = s.totalMeters > 0 ? total / s.totalMeters : 1
        var r = s
        r.warmupMeters *= f
        r.workMeters *= f
        r.recoveryMeters *= f
        r.cooldownMeters *= f
        return r
    }

    static func km(_ meters: Double) -> String {
        let km = meters / 1_000
        return km.rounded() == km ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
    }

    private func contains(_ week: TrainingWeek, _ date: Date, _ calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: week.startDate)
        return date >= start && date < day(7, start, calendar)
    }

    private func day(_ offset: Int, _ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
    }
}
