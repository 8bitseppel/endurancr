import Foundation

/// Follows a session's steps while it's being run, and records each rep as it ends.
///
/// One engine for both jobs on purpose: the screen's "where am I" and the saved
/// rep splits have to agree, and only something that remembers *when the current
/// step began* can tell. Distance alone isn't enough — a stride lasts 20 s, and
/// the easy minute before it takes as long as it takes.
///
/// Feed it every new reading (`update`), then `finish` when the run ends. It says
/// which steps were entered, so the watch can tap the wrist and show what's next.
public struct GuidedRun: Sendable, Equatable {
    public let steps: [WorkoutStep]
    /// Where the athlete is now.
    public private(set) var index = 0
    /// The reps and strides as they were run, in order, ready to save with the run.
    public private(set) var reps: [RepSplit] = []

    /// The distance and the running time at which the current step began.
    private var stepStartMeters: Double = 0
    private var stepStartSeconds: Double = 0
    private var stepStartDate: Date?
    private var heartRateSum: Double = 0
    private var heartRateCount = 0

    public init(steps: [WorkoutStep]) {
        self.steps = steps.isEmpty
            ? [WorkoutStep(kind: .steady, index: 0, total: 1, distanceMeters: 0, startMeters: 0,
                           paceType: .easy, targetPaceSecPerKm: nil, label: "")]
            : steps
    }

    /// `nil` when there's nothing to guide: one steady step, run at one pace.
    public init?(workout: PlannedWorkout, zones: PaceZones) {
        let steps = WorkoutSteps.steps(for: workout, zones: zones)
        guard steps.count > 1 else { return nil }
        self.init(steps: steps)
    }

    public var step: WorkoutStep { steps[min(index, steps.count - 1)] }

    /// Whether this step is one that gets recorded: a rep or a stride.
    public static func isTimed(_ step: WorkoutStep) -> Bool {
        step.kind == .work || step.kind == .stride
    }

    /// The step after this one, when there is one.
    public var nextStep: WorkoutStep? {
        index + 1 < steps.count ? steps[index + 1] : nil
    }

    /// Feed every new reading: the distance and running time so far (paused time
    /// left out), the time of the reading and the heart rate (0 when there's none).
    /// Returns the steps that began with this reading, in order — usually none.
    @discardableResult
    public mutating func update(distance: Double, elapsed: Double, date: Date, heartRate: Double) -> [WorkoutStep] {
        if stepStartDate == nil { stepStartDate = date }
        if heartRate > 0, Self.isTimed(step) {
            heartRateSum += heartRate
            heartRateCount += 1
        }
        var entered: [WorkoutStep] = []
        // More than one step can end in the same reading: a stride is 20 s, and
        // readings can arrive further apart than that when the watch is busy.
        while index < steps.count - 1, isOver(step, distance: distance, elapsed: elapsed) {
            let ended = step
            close(distance: distance, elapsed: elapsed, date: date)
            // The next step starts where this one was due to end, not where the
            // reading happens to be, so a late reading doesn't shorten the next step.
            stepStartMeters = ended.seconds == nil ? stepStartMeters + ended.distanceMeters : distance
            stepStartSeconds = ended.seconds.map { stepStartSeconds + $0 } ?? elapsed
            stepStartDate = date
            index += 1
            entered.append(step)
        }
        return entered
    }

    /// After the app was relaunched mid-run: picks up at the step the distance says,
    /// without recording the reps it couldn't watch. Only an estimate where steps run
    /// on the clock, which is the best anyone can do once the count is lost.
    public mutating func seek(distance: Double, elapsed: Double) {
        while index < steps.count - 1, step.startMeters + step.distanceMeters <= distance { index += 1 }
        stepStartMeters = step.startMeters
        stepStartSeconds = elapsed
        stepStartDate = nil
    }

    /// At the end of the run: keeps the rep or stride in progress if most of it was run.
    public mutating func finish(distance: Double, elapsed: Double, date: Date) {
        close(distance: distance, elapsed: elapsed, date: date)
        index = steps.count - 1
    }

    /// How far into the current step the athlete is, 0 to 1, by whichever of the two
    /// runs it: the clock for a stride, the distance for a rep.
    public func progress(distance: Double, elapsed: Double) -> Double {
        if let seconds = step.seconds, seconds > 0 {
            return min(1, max(0, (elapsed - stepStartSeconds) / seconds))
        }
        guard step.distanceMeters > 0 else { return 0 }
        return min(1, max(0, (distance - stepStartMeters) / step.distanceMeters))
    }

    /// What's left of the current step on the clock, for a step run by the clock.
    public func remainingSeconds(elapsed: Double) -> Double? {
        step.seconds.map { max(0, $0 - (elapsed - stepStartSeconds)) }
    }

    /// What's left of the current step in metres, for a step run by distance. `nil`
    /// for the last step, which runs to the end of the run.
    public func remainingMeters(distance: Double) -> Double? {
        guard step.seconds == nil, step.distanceMeters > 0 else { return nil }
        return max(0, stepStartMeters + step.distanceMeters - distance)
    }

    /// The average pace of the rep or stride in progress so far, once there's enough
    /// of it to mean anything; `nil` between reps.
    public func currentPace(distance: Double, elapsed: Double) -> Double? {
        guard Self.isTimed(step) else { return nil }
        let meters = distance - stepStartMeters
        let seconds = elapsed - stepStartSeconds
        guard meters >= 50, seconds > 0 else { return nil }
        return seconds / (meters / 1_000)
    }

    private func isOver(_ step: WorkoutStep, distance: Double, elapsed: Double) -> Bool {
        if let seconds = step.seconds { return elapsed - stepStartSeconds >= seconds }
        return distance - stepStartMeters >= step.distanceMeters
    }

    /// Records the step that just ended, if it was a rep or a stride and enough of
    /// it was run (the run can end mid-rep).
    private mutating func close(distance: Double, elapsed: Double, date: Date) {
        defer {
            heartRateSum = 0
            heartRateCount = 0
        }
        guard Self.isTimed(step) else { return }
        let meters = distance - stepStartMeters
        let seconds = elapsed - stepStartSeconds
        let enough = step.seconds.map { seconds >= $0 / 2 } ?? (meters >= step.distanceMeters / 2)
        guard enough, seconds > 0 else { return }
        reps.append(RepSplit(
            label: step.label, kind: step.kind == .stride ? .stride : .rep,
            number: step.repNumber ?? 1, total: step.repTotal ?? 1,
            meters: max(0, meters), seconds: seconds,
            // A stride is run by feel, not to a pace: it's recorded, not marked off.
            targetPaceSecPerKm: step.kind == .stride ? nil : step.targetPaceSecPerKm,
            averageHeartRate: heartRateCount > 0 ? heartRateSum / Double(heartRateCount) : nil,
            start: stepStartDate ?? date, end: date
        ))
    }
}
