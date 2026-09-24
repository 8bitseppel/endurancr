import Foundation

/// One segment of a run with its own target pace and distance — a warm-up, a work
/// rep, a recovery jog, a cool-down, or (for an unstructured run) the whole thing.
/// Decomposed from a `PlannedWorkout` so the live run screen and Live Activity can
/// show *where you are* and advance the target automatically as each step's
/// distance is covered.
public struct WorkoutStep: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case warmup, work, recovery, cooldown, steady
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
    public var distanceMeters: Double
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
        distanceMeters: Double, startMeters: Double,
        paceType: WorkoutType, targetPaceSecPerKm: Double?, label: String
    ) {
        self.kind = kind
        self.index = index
        self.total = total
        self.repNumber = repNumber
        self.repTotal = repTotal
        self.distanceMeters = distanceMeters
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
        case .rest, .raceDay: return nil
        }
    }

    /// Decomposes a workout into ordered steps. An unstructured run becomes a single
    /// `.steady` step; a structured session becomes warm-up + reps×[work + recovery]
    /// + cool-down, with cumulative `startMeters` assigned in order.
    public static func steps(for w: PlannedWorkout, zones: PaceZones) -> [WorkoutStep] {
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
            drafts.append(Draft(kind: .warmup, distance: s.warmupMeters,
                                paceType: s.recoveryType, repNumber: nil, repTotal: nil,
                                label: "Warm-up"))
        }
        for r in 1...max(1, s.reps) {
            drafts.append(Draft(kind: .work, distance: s.workMeters,
                                paceType: s.workType, repNumber: r, repTotal: s.reps,
                                label: "Rep \(r)/\(s.reps)"))
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
                paceType: d.paceType, targetPaceSecPerKm: zonePace(d.paceType, zones),
                label: d.label
            ))
            cumulative += d.distance
        }
        return steps
    }

    /// The step the athlete is currently in for a given cumulative distance: the
    /// first step whose end (`startMeters + distanceMeters`) is still ahead. Past the
    /// end, returns the last step (you're finishing the cool-down); `nil` if there are
    /// no steps at all.
    public static func activeStep(for w: PlannedWorkout, zones: PaceZones, distanceCovered: Double) -> WorkoutStep? {
        let all = steps(for: w, zones: zones)
        if let step = all.first(where: { $0.startMeters + $0.distanceMeters > distanceCovered }) {
            return step
        }
        return all.last
    }
}
