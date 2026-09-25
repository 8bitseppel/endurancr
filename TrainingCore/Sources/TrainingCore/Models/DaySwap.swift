import Foundation

/// The athlete dragged one day of the plan onto another: the sessions on those two
/// days trade places. Swaps are stored on `PlanInputs` and replayed in order on top
/// of the generated plan, so they survive every regeneration.
public struct DaySwap: Sendable, Equatable, Hashable, Codable {
    public var first: Date
    public var second: Date

    public init(_ first: Date, _ second: Date) {
        self.first = first
        self.second = second
    }
}

extension TrainingPlan {
    /// The plan with each swap applied in order. The session (type, distance, pace,
    /// notes, structure and id) moves; the dates stay put. Race day never moves, and a
    /// swap naming a day outside the plan is ignored.
    public func applyingSwaps(_ swaps: [DaySwap], calendar: Calendar = .current) -> TrainingPlan {
        guard !swaps.isEmpty else { return self }
        var plan = self
        func locate(_ day: Date) -> (Int, Int)? {
            for w in plan.weeks.indices {
                if let i = plan.weeks[w].workouts.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                    return (w, i)
                }
            }
            return nil
        }
        for swap in swaps {
            guard !calendar.isDate(swap.first, inSameDayAs: swap.second),
                  let (wa, ia) = locate(swap.first), let (wb, ib) = locate(swap.second) else { continue }
            var a = plan.weeks[wa].workouts[ia], b = plan.weeks[wb].workouts[ib]
            guard a.type != .raceDay, b.type != .raceDay else { continue }
            (a.date, b.date) = (b.date, a.date)
            // A rest day's note explains its original day ("you keep Fridays free"),
            // which is wrong once it moves; call it what it is now.
            if a.type == .rest { a.notes = "Rest / cross-train" }
            if b.type == .rest { b.notes = "Rest / cross-train" }
            plan.weeks[wa].workouts[ia] = b
            plan.weeks[wb].workouts[ib] = a
        }
        return plan
    }
}
