import Foundation

/// One rep as it was run: what the watch or iPhone measured from the rep's start to
/// its end. Saved with the run in Apple Health, so the plan can show every rep against
/// its target and judge the session by its reps rather than the run's average.
public struct RepSplit: Sendable, Equatable, Codable {
    /// "Rep 3/6", or the block's name ("Threshold", "Marathon pace", "Tune-up race").
    public var label: String
    public var number: Int
    public var total: Int
    public var meters: Double
    /// Running time, paused time left out.
    public var seconds: Double
    public var targetPaceSecPerKm: Double?
    public var averageHeartRate: Double?
    public var start: Date
    public var end: Date

    public init(label: String, number: Int, total: Int, meters: Double, seconds: Double,
                targetPaceSecPerKm: Double?, averageHeartRate: Double? = nil, start: Date, end: Date) {
        self.label = label
        self.number = number
        self.total = total
        self.meters = meters
        self.seconds = seconds
        self.targetPaceSecPerKm = targetPaceSecPerKm
        self.averageHeartRate = averageHeartRate
        self.start = start
        self.end = end
    }

    public var paceSecPerKm: Double? { meters > 0 && seconds > 0 ? seconds / (meters / 1_000) : nil }

    public enum Verdict: Sendable, Equatable { case onPace, faster, slower }

    /// Up to 5 s/km slower than the target is on pace, as on the run screen (the
    /// watch's GPS is that exact over a rep); more than 10 s/km faster is faster than
    /// planned, which Jack Tupper Daniels counts as a mistake too: it isn't the
    /// training the session is for.
    public static let slowerTolerance: Double = 5
    public static let fasterTolerance: Double = 10

    public var verdict: Verdict? {
        guard let pace = paceSecPerKm, let target = targetPaceSecPerKm else { return nil }
        if pace > target + Self.slowerTolerance { return .slower }
        if pace < target - Self.fasterTolerance { return .faster }
        return .onPace
    }
}

/// Follows a run's steps as the distance grows and closes each rep when it ends.
/// Strides aren't kept: 100 m is too short for GPS to time fairly, and they're run by
/// feel. A rep cut short (less than half its distance, the run ended) isn't kept either.
public struct RepTracker: Sendable {
    public let steps: [WorkoutStep]
    public private(set) var reps: [RepSplit] = []
    private var current: Open?

    private struct Open: Sendable {
        var step: WorkoutStep
        var startMeters: Double
        var startSeconds: Double
        var startDate: Date
        var heartRateSum: Double = 0
        var heartRateCount = 0
    }

    /// `nil` when the run has no reps to time (a steady run, or only strides).
    public init?(workout: PlannedWorkout, zones: PaceZones) {
        let steps = WorkoutSteps.steps(for: workout, zones: zones)
        guard steps.contains(where: Self.isTimed) else { return nil }
        self.steps = steps
    }

    static func isTimed(_ step: WorkoutStep) -> Bool {
        step.kind == .work && !step.label.hasPrefix("Stride")
    }

    /// Feed every new reading: the distance and running time so far, the time of the
    /// reading and the heart rate (0 when there's none).
    public mutating func update(distance: Double, elapsed: Double, date: Date, heartRate: Double) {
        let step = steps.first { $0.startMeters + $0.distanceMeters > distance } ?? steps.last
        guard let step else { return }
        if current?.step.index != step.index {
            close(distance: distance, elapsed: elapsed, date: date)
            current = Self.isTimed(step)
                ? Open(step: step, startMeters: distance, startSeconds: elapsed, startDate: date)
                : nil
        }
        if heartRate > 0 {
            current?.heartRateSum += heartRate
            current?.heartRateCount += 1
        }
    }

    /// The average pace of the rep in progress so far, once 50 m of it are run; `nil`
    /// between reps.
    public func currentPace(distance: Double, elapsed: Double) -> Double? {
        guard let open = current else { return nil }
        let meters = distance - open.startMeters
        let seconds = elapsed - open.startSeconds
        guard meters >= 50, seconds > 0 else { return nil }
        return seconds / (meters / 1_000)
    }

    /// At the end of the run: keeps the rep in progress if most of it was run.
    public mutating func finish(distance: Double, elapsed: Double, date: Date) {
        close(distance: distance, elapsed: elapsed, date: date)
        current = nil
    }

    private mutating func close(distance: Double, elapsed: Double, date: Date) {
        guard let open = current else { return }
        let meters = distance - open.startMeters
        let seconds = elapsed - open.startSeconds
        guard meters >= open.step.distanceMeters / 2, seconds > 0 else { return }
        let total = open.step.repTotal ?? 1
        reps.append(RepSplit(
            label: open.step.label, number: open.step.repNumber ?? 1, total: total,
            meters: meters, seconds: seconds, targetPaceSecPerKm: open.step.targetPaceSecPerKm,
            averageHeartRate: open.heartRateCount > 0 ? open.heartRateSum / Double(open.heartRateCount) : nil,
            start: open.startDate, end: date
        ))
    }
}

/// What the reps say, in plain words, for the plan and the run summary.
public enum RepReport {
    /// The reps with a pace and a target, the ones that can be judged.
    public static func judged(_ reps: [RepSplit]) -> [RepSplit] { reps.filter { $0.verdict != nil } }

    /// More than half the reps slower than their target: the session came in slow.
    /// Used by the plan to ease the paces (`TrainingBuddy`).
    public static func isSlow(_ reps: [RepSplit]) -> Bool {
        let judged = judged(reps)
        guard !judged.isEmpty else { return false }
        return judged.filter { $0.verdict == .slower }.count * 2 > judged.count
    }

    /// "5 of 6 reps on pace, target 4:15/km. Rep 6 slower, at 4:31/km." `nil` without reps.
    public static func summary(_ reps: [RepSplit]) -> String? {
        let judged = judged(reps)
        guard let first = judged.first else { return nil }
        let target = first.targetPaceSecPerKm.map { "target \(pace($0))" } ?? ""
        if judged.count == 1, first.total == 1 {
            let ran = first.paceSecPerKm.map(pace) ?? "--"
            switch first.verdict {
            case .onPace?: return "\(first.label) on pace: \(ran), \(target)."
            case .slower?: return "\(first.label) slower than planned: \(ran), \(target)."
            case .faster?: return "\(first.label) faster than planned: \(ran), \(target)."
            case nil: return nil
            }
        }
        let onPace = judged.filter { $0.verdict == .onPace }.count
        var parts = ["\(onPace) of \(judged.count) reps on pace, \(target)."]
        let slower = judged.filter { $0.verdict == .slower }
        if !slower.isEmpty { parts.append(list(slower, "slower")) }
        let faster = judged.filter { $0.verdict == .faster }
        if !faster.isEmpty { parts.append(list(faster, "faster")) }
        let missing = (reps.first?.total ?? judged.count) - judged.count
        if missing > 0 { parts.append("\(missing) \(missing == 1 ? "rep" : "reps") not run.") }
        return parts.joined(separator: " ")
    }

    /// "Reps 5 and 6 slower, at 4:31 and 4:40/km."
    private static func list(_ reps: [RepSplit], _ word: String) -> String {
        let numbers = joined(reps.map { "\($0.number)" })
        let paces = joined(reps.map { $0.paceSecPerKm.map { String(pace($0).dropLast(3)) } ?? "--" })
        return "\(reps.count == 1 ? "Rep" : "Reps") \(numbers) \(word), at \(paces)/km."
    }

    private static func joined(_ items: [String]) -> String {
        items.count <= 1 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    private static func pace(_ secPerKm: Double) -> String {
        let s = Int(secPerKm.rounded())
        return String(format: "%d:%02d/km", s / 60, s % 60)
    }

    /// The reps as JSON, for the run's metadata in Apple Health.
    public static let metadataKey = "EndurancrReps"

    public static func encode(_ reps: [RepSplit]) -> String? {
        guard !reps.isEmpty, let data = try? JSONEncoder().encode(reps) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode(_ text: String?) -> [RepSplit]? {
        guard let data = text?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([RepSplit].self, from: data)
    }
}
