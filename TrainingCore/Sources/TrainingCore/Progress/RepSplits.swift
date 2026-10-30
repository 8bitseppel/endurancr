import Foundation

/// One rep as it was run: what the watch or iPhone measured from the rep's start to
/// its end. Saved with the run in Apple Health, so the plan can show every rep against
/// its target and judge the session by its reps rather than the run's average.
public struct RepSplit: Sendable, Equatable, Codable {
    /// A rep of a session, or a 20 s stride at the end of an easy run. Strides are
    /// recorded but never marked off against a pace: they're run by feel.
    public enum Kind: String, Sendable, Equatable, Codable { case rep, stride }

    /// "Rep 3/6", or the block's name ("Threshold", "Marathon pace", "Tune-up race").
    public var label: String
    public var kind: Kind
    public var number: Int
    public var total: Int
    public var meters: Double
    /// Running time, paused time left out.
    public var seconds: Double
    public var targetPaceSecPerKm: Double?
    public var averageHeartRate: Double?
    public var start: Date
    public var end: Date

    public init(label: String, kind: Kind = .rep, number: Int, total: Int, meters: Double, seconds: Double,
                targetPaceSecPerKm: Double?, averageHeartRate: Double? = nil, start: Date, end: Date) {
        self.label = label
        self.kind = kind
        self.number = number
        self.total = total
        self.meters = meters
        self.seconds = seconds
        self.targetPaceSecPerKm = targetPaceSecPerKm
        self.averageHeartRate = averageHeartRate
        self.start = start
        self.end = end
    }

    /// Runs saved before strides were recorded have no `kind`: they're all reps.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .rep
        number = try c.decode(Int.self, forKey: .number)
        total = try c.decode(Int.self, forKey: .total)
        meters = try c.decode(Double.self, forKey: .meters)
        seconds = try c.decode(Double.self, forKey: .seconds)
        targetPaceSecPerKm = try c.decodeIfPresent(Double.self, forKey: .targetPaceSecPerKm)
        averageHeartRate = try c.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
    }

    public var paceSecPerKm: Double? { meters > 0 && seconds > 0 ? seconds / (meters / 1_000) : nil }

    public enum Verdict: Sendable, Equatable { case onPace, faster, slower }

    /// Up to 5 s/km slower than the target is on pace, as on the run screen (the
    /// watch's GPS is that exact over a rep); more than 10 s/km faster is faster than
    /// planned, which Jack Tupper Daniels counts as a mistake too: it isn't the
    /// training the session is for.
    public static let slowerTolerance: Double = 5
    public static let fasterTolerance: Double = 10

    /// `nil` for a stride: 20 s by feel is nothing to mark off against a pace.
    public var verdict: Verdict? {
        guard kind == .rep, let pace = paceSecPerKm, let target = targetPaceSecPerKm else { return nil }
        if pace > target + Self.slowerTolerance { return .slower }
        if pace < target - Self.fasterTolerance { return .faster }
        return .onPace
    }
}

/// What the reps say, in plain words, for the plan and the run summary.
public enum RepReport {
    /// The reps with a pace and a target, the ones that can be judged. Strides are
    /// never among them: they're run by feel, so there's nothing to judge.
    public static func judged(_ reps: [RepSplit]) -> [RepSplit] { reps.filter { $0.verdict != nil } }

    /// The session's reps, without the strides.
    public static func reps(_ reps: [RepSplit]) -> [RepSplit] { reps.filter { $0.kind == .rep } }

    /// The strides at the end of an easy run, as they were run.
    public static func strides(_ reps: [RepSplit]) -> [RepSplit] { reps.filter { $0.kind == .stride } }

    /// More than half the reps slower than their target: the session came in slow.
    /// Used by the plan to ease the paces (`TrainingBuddy`).
    public static func isSlow(_ reps: [RepSplit]) -> Bool {
        let judged = judged(reps)
        guard !judged.isEmpty else { return false }
        return judged.filter { $0.verdict == .slower }.count * 2 > judged.count
    }

    /// "5 of 6 reps on pace, target 4:15/km. Rep 6 slower, at 4:31/km.", or for an
    /// easy run that ended with strides "All 6 strides done, 3:24 to 3:41/km."
    /// `nil` when there's nothing recorded.
    public static func summary(_ reps: [RepSplit]) -> String? {
        let parts = [repSummary(reps), strideSummary(strides(reps))].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// What the strides came to: how many were run, and how fast they were.
    /// They're reported, never marked off: 20 s quick and light has no target pace.
    private static func strideSummary(_ strides: [RepSplit]) -> String? {
        guard let first = strides.first else { return nil }
        let done = strides.count >= first.total
            ? "All \(first.total) strides done"
            : "\(strides.count) of \(first.total) strides done"
        let paces = strides.compactMap(\.paceSecPerKm).sorted()
        guard let fastest = paces.first, let slowest = paces.last else { return done + "." }
        return fastest == slowest
            ? "\(done), at \(pace(fastest))."
            : "\(done), \(String(pace(fastest).dropLast(3))) to \(pace(slowest))."
    }

    private static func repSummary(_ all: [RepSplit]) -> String? {
        let reps = reps(all)
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
