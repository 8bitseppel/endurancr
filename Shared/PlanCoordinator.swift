import Foundation
import SwiftData
import TrainingCore

/// Owns the current plan: creation, persistence (SwiftData), and adaptation from
/// recorded runs. This is the app-layer bridge to the pure `TrainingCore` engine.
///
/// Only the regenerable `PlanInputs` (goal + rules + fitness + start date) are
/// persisted; the calendar is rebuilt from them via the generator and re-adapted
/// (re-paced, rescheduled, eased for fatigue) from HealthKit at runtime. The
/// in-memory `currentPlan` is the canonical adapted schedule, kept free of vacation
/// blanking — unavailable periods live on the goal and are applied as a view-time
/// transform (`displayPlan`) so adding or removing a vacation never destroys the
/// underlying schedule.
@Observable
@MainActor
final class PlanCoordinator {
    private let context: ModelContext
    /// The shared HealthKit service. Exposed so run-history/detail screens can read
    /// workouts and their GPS routes directly.
    let health: HealthKitService
    private let generator = VDOTPlanGenerator()
    private let adaptation = AdaptationEngine()

    private(set) var inputs: PlanInputs?
    /// Every change is pushed to the watch, so a swap, a vacation or a fresh
    /// adaptation shows there too.
    private(set) var currentPlan: TrainingPlan? {
        didSet { syncToWatch() }
    }
    private(set) var recentRuns: [CompletedRun] = []
    private(set) var restingHeartRates: [RestingHeartRateSample] = []
    private(set) var fatigue: FatigueAssessment?
    var isWorking = false

    init(context: ModelContext, health: HealthKitService) {
        self.context = context
        self.health = health
        loadLatest()
    }

    private func loadLatest() {
        inputs = storedEntity?.inputs
        currentPlan = regeneratedBasePlan()
    }

    /// Pushes the current inputs and the adapted weeks around today to the paired
    /// Apple Watch (peer-to-peer, no cloud), so its today view matches this one.
    private func syncToWatch() {
        PlanSync.shared.publish(inputs: inputs, adapted: displayPlan.flatMap { AdaptedWeeks(plan: $0) })
    }

    /// Rebuilds the un-adapted plan from the stored inputs, or `nil` if there are none.
    private func regeneratedBasePlan() -> TrainingPlan? {
        try? inputs?.makePlan(calendar: .current)
    }

    private var storedEntity: StoredPlan? {
        var descriptor = FetchDescriptor<StoredPlan>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// The plan as the user should see it: canonical schedule with the goal's
    /// unavailable periods blanked out from today forward.
    var displayPlan: TrainingPlan? {
        guard let plan = currentPlan else { return nil }
        return adaptation.applyingUnavailability(
            plan: plan, periods: plan.effectiveUnavailablePeriods(calendar: .current), asOf: .now, calendar: .current
        )
    }

    /// The workout scheduled for `date` (defaults to today), if any.
    func workout(on date: Date = .now, calendar: Calendar = .current) -> PlannedWorkout? {
        displayPlan?.allWorkouts.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// A fresh progress snapshot for the dashboard.
    var progress: PlanProgress? {
        guard let plan = displayPlan else { return nil }
        return PlanProgress.make(plan: plan, completedRuns: recentRuns, asOf: .now, calendar: .current)
    }

    /// Generates a fresh plan and replaces any existing one. Running days per week
    /// and rest-weekday rules are read from `goal`. `startDate` is when training
    /// begins (defaults to today; the user can choose a later date).
    func createPlan(goal: Goal, fitness: FitnessSnapshot, startDate: Date = .now) throws {
        // Build once up front so invalid inputs throw before we touch the store.
        let plan = try generator.makePlan(goal: goal, fitness: fitness, startDate: startDate, calendar: .current)
        let newInputs = PlanInputs(goal: goal, fitness: fitness, startDate: startDate)

        // Single active plan: clear old ones.
        try context.delete(model: StoredPlan.self)
        context.insert(StoredPlan(inputs: newInputs))
        try context.save()
        inputs = newInputs
        currentPlan = plan
    }

    /// Replaces the goal/fitness inputs (e.g. from the goal editor) and rebuilds the
    /// plan. `startDate` defaults to the existing plan's start so history isn't
    /// rewritten unless the user deliberately changes when training begins.
    /// Follow with `refreshAdaptation()` to re-apply adaptation from HealthKit.
    func update(goal: Goal, fitness: FitnessSnapshot, startDate: Date? = nil) throws {
        guard let existing = inputs else {
            try createPlan(goal: goal, fitness: fitness, startDate: startDate ?? .now)
            return
        }
        let start = startDate ?? existing.startDate
        // Days the athlete moved stay moved when only the goal or rules change.
        let newInputs = PlanInputs(goal: goal, fitness: fitness, startDate: start, daySwaps: existing.daySwaps)
        let plan = try newInputs.makePlan(calendar: .current)
        inputs = newInputs
        persistInputs()
        currentPlan = plan
    }

    /// Rebuilds the plan from stored inputs (goal + rules + fitness) and re-applies
    /// adaptation from HealthKit. Same machinery as `refreshAdaptation`; call after
    /// editing the goal or training rules.
    func recalculate() async {
        await refreshAdaptation()
    }

    // MARK: Backup & restore

    /// Serializes the current plan's inputs to a portable, cloud-free backup
    /// (`PlanBackup`). Throws `PlanBackupError.nothingToExport` when there is no
    /// plan yet. The file holds only training inputs — no personal data, no runs.
    func exportData() throws -> Data {
        guard let inputs else { throw PlanBackupError.nothingToExport }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return try PlanBackupCodec.encode(PlanBackup(inputs: inputs, appVersion: version))
    }

    /// Restores a plan from a backup file, replacing the current one. The inputs
    /// are validated (they must build a plan) before anything is touched, so a bad
    /// file never leaves the app without a plan. Recorded runs in HealthKit are
    /// untouched; follow with `refreshAdaptation()` to re-layer adaptation.
    func importData(_ data: Data) throws {
        let restored = try PlanBackupCodec.decode(data).inputs
        // Build once up front so invalid inputs throw before we replace anything.
        let plan = try restored.makePlan(calendar: .current)
        try context.delete(model: StoredPlan.self)
        context.insert(StoredPlan(inputs: restored))
        try context.save()
        inputs = restored
        currentPlan = plan
    }

    // MARK: Storage

    /// A snapshot of how much on-device space the plan store occupies. `planBytes`
    /// is the encoded `PlanInputs` payload (what our data actually *is*); `storeBytes`
    /// is the SwiftData SQLite file(s) on disk, which include SQLite's own overhead
    /// and free pages, so `storeBytes >= planBytes` in practice.
    struct StorageUsage: Equatable {
        var planBytes: Int
        var storeBytes: Int
    }

    /// Measures current on-device storage. Cheap enough to call on view appear.
    func storageUsage() -> StorageUsage {
        let planBytes = inputs.flatMap { try? JSONEncoder().encode($0).count } ?? 0

        var storeBytes = 0
        if let url = context.container.configurations.first?.url {
            let fm = FileManager.default
            // SwiftData/SQLite writes the main DB plus a write-ahead log and shared
            // memory file; sum all three for an honest on-disk figure.
            for suffix in ["", "-wal", "-shm"] {
                if let attrs = try? fm.attributesOfItem(atPath: url.path + suffix),
                   let size = attrs[.size] as? Int {
                    storeBytes += size
                }
            }
        }
        return StorageUsage(planBytes: planBytes, storeBytes: storeBytes)
    }

    /// Recent running workouts read straight from HealthKit (independent of any
    /// plan), newest first — used to seed the initial fitness estimate from a real
    /// run instead of typing one in. Runs shorter than 2 km are dropped so warm-ups
    /// and strides don't masquerade as efforts.
    func recentHealthRuns(within days: Int = 120) async -> [CompletedRun] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return await health.fetchRuns(since: since)
            .filter { $0.distanceMeters >= 2_000 && $0.durationSeconds > 0 }
            .sorted { $0.date > $1.date }
    }

    /// Deletes the current goal and its plan, returning the app to the empty
    /// "set your goal" state. Recorded runs stay in HealthKit.
    func deletePlan() {
        try? context.delete(model: StoredPlan.self)
        try? context.save()
        inputs = nil
        currentPlan = nil
        recentRuns = []
        restingHeartRates = []
        fatigue = nil
    }

    // MARK: Achieved goals

    /// True once race day has arrived or passed for the current plan — the moment we
    /// prompt the athlete to confirm the goal complete. `false` with no plan.
    var raceDayReached: Bool {
        guard let goal = currentPlan?.goal else { return false }
        return Calendar.current.startOfDay(for: .now) >= Calendar.current.startOfDay(for: goal.raceDate)
    }

    /// Past achievements, newest first, decoded from the local store.
    func achievedGoals() -> [GoalAchievement] {
        let descriptor = FetchDescriptor<AchievedGoal>(sortBy: [SortDescriptor(\.achievedAt, order: .reverse)])
        return (try? context.fetch(descriptor))?.compactMap(\.achievement) ?? []
    }

    /// Marks the current goal complete: snapshots what the athlete achieved (fitness
    /// reached, weeks trained, distance run, workouts done) into a permanent local
    /// record, then clears the active plan so a new goal can be set. The achievement
    /// survives independently of the plan. No-op when there's nothing to complete.
    func completeCurrentGoal() {
        guard let plan = currentPlan, let progress else { return }
        let achievement = GoalAchievement.make(plan: plan, progress: progress)
        context.insert(AchievedGoal(achievement: achievement))
        try? context.save()
        deletePlan()
    }

    /// Pulls recent runs and resting HR from HealthKit, regenerates the plan from
    /// its inputs, and layers adaptation on top. Nothing here is persisted — the
    /// adapted plan is fully reproducible from the stored inputs + HealthKit.
    func refreshAdaptation() async {
        guard let base = regeneratedBasePlan() else { return }
        isWorking = true
        defer { isWorking = false }

        let since = base.weeks.first?.startDate ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let runs = await health.fetchRuns(since: since)
        let resting = await health.fetchRestingHeartRates(since: since)
        recentRuns = runs
        restingHeartRates = resting

        // Layer the adaptation steps ourselves so the canonical plan stays free of
        // vacation blanking (that is applied at display time from the goal).
        let now = Date.now
        let cal = Calendar.current
        let newVDOT = adaptation.reRatedVDOT(current: base.vdot, completedRuns: runs, asOf: now, calendar: cal)
        let credited = adaptation.creditingEndurance(plan: base, completedRuns: runs, asOf: now, calendar: cal)
        let repaced = adaptation.repaced(plan: credited, withVDOT: newVDOT, asOf: now, calendar: cal)
        let rescheduled = adaptation.rescheduleMissedLongRun(plan: repaced, completedRuns: runs, asOf: now, calendar: cal)
        let assessment = adaptation.assessFatigue(restingHeartRates: resting, completedRuns: runs, asOf: now, calendar: cal)
        let eased = adaptation.easedForFatigue(plan: rescheduled, assessment: assessment, asOf: now, calendar: cal)
        // Rebalance the current week's easy runs so completed + remaining lands on the
        // week's target: a short or spontaneous run flows onto the remaining easy days
        // (capped), while the long run and quality sessions keep their prescription.
        let redistributed = adaptation.redistributedWithinWeek(plan: eased, completedRuns: runs, asOf: now, calendar: cal)
        fatigue = assessment

        currentPlan = redistributed
    }

    // MARK: Moving days

    /// Whether a day can still be moved: today or later, not race day, and not inside
    /// a vacation (a run moved there would just be blanked again).
    func canMove(_ workout: PlannedWorkout) -> Bool {
        let cal = Calendar.current
        guard workout.type != .raceDay,
              cal.startOfDay(for: workout.date) >= cal.startOfDay(for: .now) else { return false }
        let away = currentPlan?.effectiveUnavailablePeriods(calendar: cal) ?? []
        return !away.contains { $0.contains(workout.date, calendar: cal) }
    }

    /// Swaps the sessions on two days (a run with a rest day, or two runs) and
    /// persists the swap so it survives regeneration and syncs to the watch.
    func swapDays(_ a: Date, _ b: Date) {
        let cal = Calendar.current
        guard var inputs, !cal.isDate(a, inSameDayAs: b),
              let first = workout(on: a), let second = workout(on: b),
              canMove(first), canMove(second) else { return }
        let swap = DaySwap(cal.startOfDay(for: a), cal.startOfDay(for: b))
        inputs.daySwaps.append(swap)
        self.inputs = inputs
        persistInputs()
        // Apply straight to the adapted plan so the list updates without a reload.
        currentPlan = currentPlan?.applyingSwaps([swap], calendar: cal)
    }

    /// Adds a vacation / unavailable period to the goal and persists it.
    func addUnavailablePeriod(start: Date, end: Date, reason: String) {
        guard var inputs else { return }
        let (lo, hi) = start <= end ? (start, end) : (end, start)
        inputs.goal.unavailablePeriods.append(UnavailablePeriod(start: lo, end: hi, reason: reason))
        applyUnavailabilityChange(inputs)
    }

    /// Removes an unavailable period by id.
    func removeUnavailablePeriod(id: UUID) {
        guard var inputs else { return }
        inputs.goal.unavailablePeriods.removeAll { $0.id == id }
        applyUnavailabilityChange(inputs)
    }

    var unavailablePeriods: [UnavailablePeriod] {
        (inputs?.goal.unavailablePeriods ?? []).sorted { $0.start < $1.start }
    }

    /// Persists changed unavailable periods and mirrors them onto the in-memory
    /// plan's goal. No regeneration needed — blanking is a display-time transform.
    private func applyUnavailabilityChange(_ updated: PlanInputs) {
        inputs = updated
        persistInputs()
        currentPlan?.goal.unavailablePeriods = updated.goal.unavailablePeriods
    }

    private func persistInputs() {
        guard let inputs, let entity = storedEntity else { return }
        entity.inputs = inputs
        try? context.save()
    }
}
