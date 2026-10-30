import Foundation

/// One segment of a run with its own target pace and distance — a warm-up, a work
/// rep, a recovery jog, a cool-down, or (for an unstructured run) the whole thing.
/// Decomposed from a `PlannedWorkout` so the live run screen and Live Activity can
/// show *where you are* and advance the target automatically as each step's
/// distance is covered.
public struct WorkoutStep: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// `stride` is a 20 s burst inside an easy run: work, but run by the clock
        /// and by feel rather than to a pace target.
        case warmup, work, stride, recovery, cooldown, steady
    }

    public var kind: Kind
    /// 0-based position within the ordered step list.
    public var index: Int
    /// Total number of steps in the workout.
    public var total: Int
    /// 1-based rep number for `work`/`recovery` steps; `nil` otherwise.
    public var repNumber: Int?
    /// Total rep count for `work`/`recovery` steps; `nil` otherwise.
    public var repTotal: Int?
    /// How far the step runs. For a timed step (`seconds != nil`) this is only an
    /// estimate of what its seconds cover, used to show it and to add the session up.
    public var distanceMeters: Double
    /// How long the step lasts, when it's run by the clock instead of by distance:
    /// strides and the easy stretch between them. `nil` = run by distance.
    ///
    /// A stride is 20 s quick and light. Timing it is the only honest way: GPS needs
    /// longer than 20 s to settle, so 100 m of distance arrives late and the burst
    /// would be over before the watch noticed.
    public var seconds: Double?
    /// Cumulative distance at which this step begins.
    public var startMeters: Double
    /// The pace zone this step runs at.
    public var paceType: WorkoutType
    /// Target pace (sec/km); `nil` for rest/raceDay zones with no defined pace.
    public var targetPaceSecPerKm: Double?
    /// Human label: "Warm-up", "Rep 3/6", "Recovery 3/6", "Cool-down", or "" for steady.
    public var label: String

    public init(
        kind: Kind, index: Int, total: Int,
        repNumber: Int? = nil, repTotal: Int? = nil,
        distanceMeters: Double, seconds: Double? = nil, startMeters: Double,
        paceType: WorkoutType, targetPaceSecPerKm: Double?, label: String
    ) {
        self.kind = kind
        self.index = index
        self.total = total
        self.repNumber = repNumber
        self.repTotal = repTotal
        self.distanceMeters = distanceMeters
        self.seconds = seconds
        self.startMeters = startMeters
        self.paceType = paceType
        self.targetPaceSecPerKm = targetPaceSecPerKm
        self.label = label
    }
}

/// Pure engine that turns a `PlannedWorkout` into ordered `WorkoutStep`s and finds
/// the active step for a given distance. Paces are read from `PaceZones` (from the
/// athlete's current VDOT), never stored on the workout, so it stays correct after
/// re-pacing.
public enum WorkoutSteps {
    /// The pace (sec/km) a zone runs at, or `nil` for zones with no defined pace
    /// (rest, race day). Distinct from `PaceZones.pace(for:)`, which maps those to
    /// easy/marathon — here we want to *omit* a target rather than invent one.
    public static func zonePace(_ type: WorkoutType, _ z: PaceZones) -> Double? {
        switch type {
        case .easy, .longRun: return z.easySecPerKm
        case .marathonPace: return z.marathonSecPerKm
        case .threshold: return z.thresholdSecPerKm
        case .interval: return z.intervalSecPerKm
        case .repetitionSpeed: return z.repetitionSecPerKm
        case .rest, .raceDay, .timeTrial: return nil
        }
    }

    /// Decomposes a workout into ordered steps. An unstructured run becomes a single
    /// `.steady` step; a structured session becomes warm-up + reps×[work + recovery]
    /// + cool-down, with cumulative `startMeters` assigned in order.
    public static func steps(for w: PlannedWorkout, zones: PaceZones) -> [WorkoutStep] {
        if w.structure == nil, hasStrides(w) {
            return strideSteps(for: w, zones: zones)
        }
        guard let s = w.structure else {
            return [WorkoutStep(
                kind: .steady, index: 0, total: 1,
                distanceMeters: w.distanceMeters, startMeters: 0,
                paceType: w.type, targetPaceSecPerKm: zonePace(w.type, zones), label: ""
            )]
        }

        // Build the ordered kinds/distances/paces first, then assign index/total and
        // cumulative starts in a single pass.
        struct Draft {
            var kind: WorkoutStep.Kind
            var distance: Double
            var paceType: WorkoutType
            var repNumber: Int?
            var repTotal: Int?
            var label: String
        }
        var drafts: [Draft] = []

        if s.warmupMeters > 0 {
            // A long run's easy part before its marathon-pace finish isn't a warm-up.
            drafts.append(Draft(kind: .warmup, distance: s.warmupMeters,
                                paceType: s.recoveryType, repNumber: nil, repTotal: nil,
                                label: w.type == .longRun ? "Easy" : "Warm-up"))
        }
        for r in 1...max(1, s.reps) {
            // A single block is named for what it is ("Marathon pace"), not "Rep 1/1".
            let label = s.reps == 1 ? blockLabel(s.workType) : "Rep \(r)/\(s.reps)"
            drafts.append(Draft(kind: .work, distance: s.workMeters,
                                paceType: s.workType, repNumber: r, repTotal: s.reps,
                                label: label))
            if s.recoveryMeters > 0 {
                drafts.append(Draft(kind: .recovery, distance: s.recoveryMeters,
                                    paceType: s.recoveryType, repNumber: r, repTotal: s.reps,
                                    label: "Recovery \(r)/\(s.reps)"))
            }
        }
        if s.cooldownMeters > 0 {
            drafts.append(Draft(kind: .cooldown, distance: s.cooldownMeters,
                                paceType: s.recoveryType, repNumber: nil, repTotal: nil,
                                label: "Cool-down"))
        }

        var steps: [WorkoutStep] = []
        var cumulative: Double = 0
        for (i, d) in drafts.enumerated() {
            steps.append(WorkoutStep(
                kind: d.kind, index: i, total: drafts.count,
                repNumber: d.repNumber, repTotal: d.repTotal,
                distanceMeters: d.distance, startMeters: cumulative,
                paceType: d.paceType, targetPaceSecPerKm: pace(d.paceType, of: w, zones),
                label: d.label
            ))
            cumulative += d.distance
        }
        return steps
    }

    // MARK: Strides

    /// Strides end an easy run: 6 × 20 s quick and light, a minute easy between.
    /// They run on the clock, not on distance: each one is the 20 s burst itself,
    /// preceded by the minute of easy running that sets it up. So the block reads
    /// easy, stride, easy, stride … and the last stride is followed by easy running
    /// to the end of the run.
    public static let strideCount = 6
    public static let strideSeconds: Double = 20
    /// The easy minute before each stride, Daniels' "full recovery" between them.
    public static let strideEasySeconds: Double = 60
    /// What a stride and its easy minute cover when there's no pace to work from.
    public static let strideMeters: Double = 100
    public static let strideRecoveryMeters: Double = 150

    /// An easy run with strides at the end, long enough to hold them after an easy part.
    public static func hasStrides(_ w: PlannedWorkout) -> Bool {
        w.notes.contains("6 × 20 s strides")
            && w.distanceMeters >= Double(strideCount) * (strideMeters + strideRecoveryMeters) + 1_500
    }

    /// Roughly how far the stride block covers at these paces, so the easy part
    /// before it can be as long as the rest of the run.
    public static func strideBlockMeters(_ zones: PaceZones) -> Double {
        Double(strideCount) * (meters(strideSeconds, at: zones.repetitionSecPerKm, fallback: strideMeters)
            + meters(strideEasySeconds, at: zones.easySecPerKm, fallback: strideRecoveryMeters))
    }

    private static func meters(_ seconds: Double, at paceSecPerKm: Double, fallback: Double) -> Double {
        paceSecPerKm > 0 ? (seconds / paceSecPerKm * 1_000 / 10).rounded() * 10 : fallback
    }

    private static func strideSteps(for w: PlannedWorkout, zones: PaceZones) -> [WorkoutStep] {
        let stride = meters(strideSeconds, at: zones.repetitionSecPerKm, fallback: strideMeters)
        let easy = meters(strideEasySeconds, at: zones.easySecPerKm, fallback: strideRecoveryMeters)
        let lead = max(1_000, w.distanceMeters - Double(strideCount) * (stride + easy))
        // Easy part, then six times [easy minute, stride], then easy to the end.
        let total = 2 + strideCount * 2
        var steps = [WorkoutStep(
            kind: .warmup, index: 0, total: total,
            distanceMeters: lead, startMeters: 0,
            paceType: .easy, targetPaceSecPerKm: zones.easySecPerKm, label: "Easy"
        )]
        var start = lead
        for r in 1...strideCount {
            steps.append(WorkoutStep(
                kind: .recovery, index: steps.count, total: total, repNumber: r, repTotal: strideCount,
                distanceMeters: easy, seconds: strideEasySeconds, startMeters: start,
                paceType: .easy, targetPaceSecPerKm: zones.easySecPerKm,
                label: "Easy \(r)/\(strideCount)"
            ))
            start += easy
            steps.append(WorkoutStep(
                kind: .stride, index: steps.count, total: total, repNumber: r, repTotal: strideCount,
                distanceMeters: stride, seconds: strideSeconds, startMeters: start,
                paceType: .repetitionSpeed, targetPaceSecPerKm: zones.repetitionSecPerKm,
                label: "Stride \(r)/\(strideCount)"
            ))
            start += stride
        }
        // Whatever is left of the run, easy. The strides take their own time, so how
        // much that is only shows at the end: the step runs to the finish.
        steps.append(WorkoutStep(
            kind: .cooldown, index: steps.count, total: total,
            distanceMeters: max(0, w.distanceMeters - start), startMeters: start,
            paceType: .easy, targetPaceSecPerKm: zones.easySecPerKm, label: "Easy to the end"
        ))
        return steps
    }

    /// Whether the run has steps to guide (reps, a block, strides), not just one pace.
    public static func isGuided(_ w: PlannedWorkout) -> Bool {
        w.structure != nil || hasStrides(w)
    }

    /// A time trial's pace is the race pace predicted for its distance, kept on the
    /// workout (it depends on the VDOT, not on a zone); every other part runs at its zone.
    private static func pace(_ type: WorkoutType, of w: PlannedWorkout, _ zones: PaceZones) -> Double? {
        if type == .timeTrial, let range = w.targetPaceSecPerKm { return (range.lowerBound + range.upperBound) / 2 }
        return zonePace(type, zones)
    }

    private static func blockLabel(_ type: WorkoutType) -> String {
        switch type {
        case .marathonPace: "Marathon pace"
        case .threshold: "Threshold"
        case .timeTrial: "Tune-up race"
        default: "Rep 1/1"
        }
    }

    /// The step at a given cumulative distance: the first step whose end
    /// (`startMeters + distanceMeters`) is still ahead. Past the end, returns the last
    /// step (you're finishing the cool-down); `nil` if there are no steps at all.
    ///
    /// Only an estimate where steps run on the clock (strides), so a run in progress
    /// is followed by `GuidedRun`, which knows when each step actually began.
    public static func activeStep(for w: PlannedWorkout, zones: PaceZones, distanceCovered: Double) -> WorkoutStep? {
        let all = steps(for: w, zones: zones)
        if let step = all.first(where: { $0.startMeters + $0.distanceMeters > distanceCovered }) {
            return step
        }
        return all.last
    }
}
