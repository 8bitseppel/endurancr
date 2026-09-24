import SwiftUI
import SwiftData
import TrainingCore

/// Watch home: shows today's planned workout (read from the shared SwiftData
/// store) and starts a recorded run. With no goal set, it invites a free run
/// rather than implying a session was missed.
struct WatchTodayView: View {
    /// Runs shorter than this don't warrant a post-run summary (stationary tests,
    /// accidental start/finish). 100 m is below any real run yet above GPS jitter.
    private static let minSummaryDistanceMeters: Double = 100

    @Environment(HealthKitService.self) private var health
    // Observes the store so a plan synced from the iPhone refreshes the view live.
    @Query(sort: \StoredPlan.updatedAt, order: .reverse) private var storedPlans: [StoredPlan]
    @State private var workout = WorkoutManager()
    @State private var showLiveRun = false
    // Captured at start so the live run screen can show step-aware targets. Nil for
    // a free run (no goal / rest day / nothing scheduled).
    @State private var runWorkout: PlannedWorkout?
    @State private var runZones: PaceZones?
    // Post-run summary shown after Finish, and the week's completed volume captured
    // at run start so the summary can never show less than "prior + this run" while
    // HealthKit's save is still settling.
    @State private var runSummary: WatchRunSummary?
    @State private var weekCompletedAtStart: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header
                    startButton
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            }
            .navigationTitle("endurancr")
            .navigationDestination(isPresented: $showLiveRun) {
                LiveRunView(workout: workout, plannedWorkout: runWorkout, zones: runZones)
            }
            .onChange(of: showLiveRun) { wasShowing, showing in
                // The run screen closed. Summarize only an explicit Finish (a back
                // swipe leaves didFinish false) of a run that actually covered ground
                // - a stationary or accidental run stays silent.
                guard wasShowing, !showing, workout.didFinish,
                      workout.distanceMeters >= Self.minSummaryDistanceMeters else { return }
                let distance = workout.distanceMeters
                let duration = workout.elapsedSeconds
                let saved = workout.lastError == nil
                let prior = weekCompletedAtStart
                let plan = currentPlan
                Task {
                    runSummary = await Self.makeSummary(
                        plan: plan, health: health,
                        distance: distance, duration: duration,
                        saved: saved, priorWeekCompleted: prior
                    )
                }
            }
            .sheet(item: $runSummary) { summary in
                NavigationStack { WatchRunSummaryView(summary: summary) }
            }
        }
    }

    /// Builds the post-run summary. Weekly numbers come from `PlanProgress` computed
    /// on-watch; the completed figure is floored at `priorWeekCompleted + distance`
    /// so a not-yet-visible HealthKit save never makes the week appear to shrink.
    /// A free run (no plan) yields stats only, no weekly section.
    private static func makeSummary(
        plan: TrainingPlan?, health: HealthKitService,
        distance: Double, duration: Double,
        saved: Bool, priorWeekCompleted: Double
    ) async -> WatchRunSummary {
        guard let plan else {
            return WatchRunSummary(distanceMeters: distance, durationSeconds: duration,
                                   saved: saved, weekNumber: nil,
                                   weekCompletedMeters: 0, weekTargetMeters: 0)
        }
        let since = plan.weeks.first?.startDate
            ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let runs = await health.fetchRuns(since: since)
        let progress = PlanProgress.make(plan: plan, completedRuns: runs, asOf: .now)
        return WatchRunSummary(
            distanceMeters: distance, durationSeconds: duration, saved: saved,
            weekNumber: progress.currentWeekNumber,
            weekCompletedMeters: max(progress.currentWeekCompletedMeters, priorWeekCompleted + distance),
            weekTargetMeters: progress.currentWeekPlannedMeters
        )
    }

    @ViewBuilder
    private var header: some View {
        switch state {
        case .workout(let planned):
            VStack(spacing: 4) {
                Text(Format.workoutTitle(planned.type)).font(.headline)
                Text(Format.distance(planned.distanceMeters))
                    .font(.title3).monospacedDigit()
                Text(Format.paceRange(planned.targetPaceSecPerKm))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .rest:
            VStack(spacing: 4) {
                Text("Rest day").font(.headline)
                Text("Recover well.").font(.footnote).foregroundStyle(.secondary)
            }
        case .noSessionToday:
            VStack(spacing: 4) {
                Text("Nothing scheduled").font(.headline)
                Text("Start a free run anytime.").font(.footnote).foregroundStyle(.secondary)
            }
        case .noGoal:
            VStack(spacing: 4) {
                Text("No goal yet").font(.headline)
                Text("Set a goal on your iPhone, or just start a free run.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var startButton: some View {
        Button {
            // Capture today's session and its paces so the run screen can show
            // step-aware targets; leave nil for a free run.
            if case .workout(let planned) = state, let plan = currentPlan {
                runWorkout = planned
                runZones = VDOTCalculator().paceZones(forVDOT: plan.vdot)
            } else {
                runWorkout = nil
                runZones = nil
            }
            workout.start()
            showLiveRun = true
            // Record this week's completed volume *before* the run so the post-run
            // summary has a true prior baseline (the run isn't in HealthKit yet).
            let plan = currentPlan
            Task {
                guard let plan else { weekCompletedAtStart = 0; return }
                let since = plan.weeks.first?.startDate
                    ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!
                let runs = await health.fetchRuns(since: since)
                weekCompletedAtStart = PlanProgress.make(plan: plan, completedRuns: runs, asOf: .now)
                    .currentWeekCompletedMeters
            }
        } label: {
            Label("Start Run", systemImage: "figure.run")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private enum TodayState {
        case workout(PlannedWorkout)
        case rest
        case noSessionToday
        case noGoal
    }

    private var state: TodayState {
        guard let plan = currentPlan else { return .noGoal }
        guard let planned = plan.allWorkouts.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: .now)
        }) else { return .noSessionToday }
        return planned.type == .rest ? .rest : .workout(planned)
    }

    private var currentPlan: TrainingPlan? {
        storedPlans.first?.plan
    }
}
