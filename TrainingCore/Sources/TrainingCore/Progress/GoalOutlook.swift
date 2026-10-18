import Foundation

/// An honest look at the goal: the finish time to expect today and on race day, as
/// a range rather than one number, and how likely the target time is.
///
/// - Race-day fitness grows by at most 1 VDOT per 8 weeks of consistent training
///   (Jack Tupper Daniels' marathon guidance), less when fewer runs get done, none
///   below 75% of the plan.
/// - Marathon predictions from shorter races run too fast for most recreational
///   runners: about half run 10 or more minutes slower, a quarter 20 or more
///   (Vickers & Vertosick 2016, 2,303 runners). Weekly distance explains much of it
///   (50 vs 30 miles a week: about 25 to 32 minutes), so under 80 km a week the
///   marathon time gets slower, minus what the endurance holdback already accounts for.
/// - The range is ±5% for the marathon (about ±13 minutes at 4:30; the study's 5th
///   to 95th percentile is about ±21 minutes), ±4% for the half and ±3% for shorter
///   races, up to 2% wider the further away race day is.
/// - Missed time follows Pete Pfitzinger's "making up for lost time": more than 20
///   days missed, or 10 to 20 with under 8 weeks to go, is a reason to revise the goal.
/// - A marathon plan of under 18 weeks started without a base (about 40 km a week
///   and a long run near 16 km in the last month, after Pfitzinger) is unlikely.
public struct GoalOutlook: Sendable, Equatable {
    public enum Verdict: Int, Sendable, Comparable {
        case onTrack, withinReach, stretch, unlikely
        public static func < (a: Verdict, b: Verdict) -> Bool { a.rawValue < b.rawValue }

        public var title: String {
            switch self {
            case .onTrack: "On track"
            case .withinReach: "Within reach"
            case .stretch: "A stretch"
            case .unlikely: "Unlikely for this race"
            }
        }
    }

    /// Finish time if the race were today (seconds), low to high.
    public var today: ClosedRange<Double>
    /// Finish time to expect on race day if training goes on like the last weeks.
    public var raceDay: ClosedRange<Double>
    /// Only when a target time is set.
    public var verdict: Verdict?
    /// Why, in one or two sentences.
    public var reason: String
    /// A realistic target when the current one looks like a stretch or unlikely.
    public var suggestedTargetSeconds: Double?
    /// A race date by when the current target looks realistic, if within reach.
    public var suggestedRaceDate: Date?

    public static func make(
        plan: TrainingPlan, buddy: TrainingBuddy.Status, completedRuns: [CompletedRun],
        asOf: Date, calendar: Calendar = .current
    ) -> GoalOutlook {
        let calculator = VDOTCalculator()
        let goal = plan.goal
        let meters = goal.race.meters
        let today = calendar.startOfDay(for: asOf)
        let race = calendar.startOfDay(for: goal.raceDate)
        let daysLeft = max(0, calendar.dateComponents([.day], from: today, to: race).day ?? 0)
        let weeksLeft = Double(daysLeft) / 7

        // Fitness gain to expect: 1 VDOT per 8 weeks of training at 90% of the plan or
        // more, scaled down to none at 75%. Maintenance plans hold fitness.
        let consistency = buddy.completion.map { min(1, max(0, ($0 - 0.75) / 0.15)) } ?? 1
        let trainingWeeks = max(0, weeksLeft - 2)   // the taper doesn't add fitness
        let gain = plan.isMaintenance ? 0 : trainingWeeks / 8 * consistency

        let recentKmPerWeek = TrainingBuddy.distance(
            of: completedRuns, from: calendar.date(byAdding: .day, value: -28, to: today) ?? today,
            to: calendar.date(byAdding: .day, value: 1, to: today) ?? today, calendar: calendar) / 4 / 1_000
        // The plan's last 6 build weeks, at the share of the plan being run lately.
        let buildWeeks = plan.weeks.filter { $0.phase != .taper && $0.phase != .raceWeek }.suffix(6)
        let buildMeters: Double = buildWeeks.map(\.plannedVolumeMeters).reduce(0, +)
        let share: Double = max(0.5, min(1, buddy.completion ?? 1))
        let peakKmPerWeek = buildMeters / Double(max(1, buildWeeks.count)) / 1_000 * share

        func time(vdot: Double, kmPerWeek: Double) -> Double {
            let base = calculator.predictedTimeSeconds(distanceMeters: meters, vdot: vdot)
            guard goal.race == .marathon else { return base }
            // Under 80 km a week, marathons run slower than the VDOT tables say; the
            // endurance holdback already covers part of that.
            let mileage = min(35, max(0, (80 - kmPerWeek) * 0.875)) * 60
            let holdback = base - calculator.predictedTimeSeconds(distanceMeters: meters, vdot: vdot + plan.enduranceHoldback)
            return base + max(0, mileage - holdback)
        }
        let spread: Double = goal.race == .marathon ? 0.05 : (goal.race == .halfMarathon ? 0.04 : 0.03)
        func range(_ t: Double, extra: Double) -> ClosedRange<Double> {
            let s = spread + extra
            return (t * (1 - s))...(t * (1 + s))
        }

        let nowTime = time(vdot: plan.raceVDOT, kmPerWeek: recentKmPerWeek)
        let raceVDOT = plan.raceVDOT + gain
        let raceTime = time(vdot: raceVDOT, kmPerWeek: max(recentKmPerWeek, peakKmPerWeek))
        var outlook = GoalOutlook(
            today: range(nowTime, extra: 0),
            raceDay: range(raceTime, extra: min(0.02, weeksLeft / 4 * 0.005)),
            verdict: nil, reason: "", suggestedTargetSeconds: nil, suggestedRaceDate: nil
        )

        guard let target = goal.targetTimeSeconds else {
            outlook.reason = consistencyLine(buddy)
            return outlook
        }
        // Compare in VDOT: the target's against the one race day's expected time implies.
        let gap = calculator.vdot(distanceMeters: meters, timeSeconds: target)
            - calculator.vdot(distanceMeters: meters, timeSeconds: raceTime)
        var verdict: Verdict = gap <= 0 ? .onTrack : gap <= 1 ? .withinReach : gap <= 2 ? .stretch : .unlikely
        var reasons: [String] = []

        // Pfitzinger: missed time and when it calls for a new goal.
        let missed = buddy.longestRecentBreakDays
        if missed > 20 || (missed >= 10 && weeksLeft < 8) {
            verdict = max(verdict, .stretch)
            reasons.append("\(missed) days without running is a lot to make up this close to race day.")
        }
        // A marathon set up with under 18 weeks to go, without the base for it (judged
        // in the plan's first 4 weeks; later the plan's own weeks are the base).
        let longest28 = TrainingBuddy.longestRun(in: completedRuns, days: 28, before: today, calendar: calendar)
        let planDays = TrainingBuddy.firstRunDay(of: plan, calendar: calendar)
            .map { calendar.dateComponents([.day], from: $0, to: today).day ?? 0 } ?? 0
        let totalWeeks = weeksLeft + Double(planDays) / 7
        if goal.race == .marathon, totalWeeks < 18, planDays < 28, recentKmPerWeek < 40 || longest28 < 16_000 {
            verdict = .unlikely
            reasons.append("Marathon plans usually start from about 40 km a week and a long run near 16 km; the last 4 weeks were \(Int(recentKmPerWeek.rounded())) km a week.")
        }
        outlook.verdict = verdict

        let targetText = Self.format(target)
        switch verdict {
        case .onTrack:
            reasons.insert("Your training points to \(Self.format(outlook.raceDay.lowerBound)) to \(Self.format(outlook.raceDay.upperBound)) on race day, so \(targetText) fits.", at: 0)
        case .withinReach:
            reasons.insert("\(targetText) is within reach if the coming weeks go about as planned.", at: 0)
        case .stretch, .unlikely:
            let realistic = Self.rounded(raceTime, race: goal.race)
            outlook.suggestedTargetSeconds = realistic
            // Weeks more it would take at 1 VDOT per 8 weeks, if training keeps up.
            if gap > 0, gap <= 3 {
                let extraWeeks = Int((gap * 8).rounded(.up))
                outlook.suggestedRaceDate = calendar.date(byAdding: .day, value: extraWeeks * 7, to: race)
            }
            let start = verdict == .stretch
                ? "\(targetText) is a stretch for this race: it needs most weeks to go to plan."
                : "At this rate, \(targetText) is unlikely for this race."
            var line = "\(start) \(Self.format(realistic)) looks realistic"
            if let later = outlook.suggestedRaceDate {
                line += ", or keep \(targetText) for a race around \(later.formatted(.dateTime.month(.wide).year()))"
            }
            reasons.insert(line + ".", at: 0)
        }
        reasons.append(consistencyLine(buddy))
        outlook.reason = reasons.filter { !$0.isEmpty }.joined(separator: " ")
        return outlook
    }

    private static func consistencyLine(_ buddy: TrainingBuddy.Status) -> String {
        guard let c = buddy.completion else { return "" }
        let percent = Int((min(1.5, c) * 100).rounded())
        return "You ran \(percent)% of the planned distance in the last two weeks."
    }

    /// Marathon and half to the next 5 minutes, shorter races to the minute (up, so
    /// it's not optimistic).
    static func rounded(_ seconds: Double, race: RaceDistance) -> Double {
        let step: Double = (race == .marathon || race == .halfMarathon) ? 300 : 60
        return (seconds / step).rounded(.up) * step
    }

    public static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        // Hours and minutes for long races ("4:35"), minutes and seconds otherwise.
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%d:%02d", m, sec)
    }
}
